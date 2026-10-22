# frozen_string_literal: true

require 'json'

module EGC
  # DESIGN VALIDATION: a generated (or hand-edited) design is checked against the constraint model BEFORE it is accepted.
  # Returns PROBLEMS (error: must be fixed), WARNINGS and SUGGESTED FIXES - the assistant never silently redesigns anything.
  module AssistantValidate
    module_function

    SEV = { 'error' => 0, 'warn' => 1, 'info' => 2 }.freeze

    def item(code, sev, where, msg, fix = nil)
      { 'code' => code, 'severity' => sev, 'where' => where, 'message' => msg, 'fix' => fix }
    end

    # point in polygon (mm)
    def inside?(poly, x, y, tol = 5.0)
      ins = false
      j = poly.size - 1
      poly.each_index do |i|
        xi, yi = poly[i]
        xj, yj = poly[j]
        ins = !ins if ((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)
        j = i
      end
      return true if ins

      # within tol of an edge counts as inside (a cabinet against the wall)
      poly.each_index.any? do |i|
        a = poly[i]
        b = poly[(i + 1) % poly.size]
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        t = ((x - a[0]) * dx + (y - a[1]) * dy) / (dx * dx + dy * dy)
        t = [[t, 0].max, 1].min
        Math.hypot(x - (a[0] + dx * t), y - (a[1] + dy * t)) <= tol
      end
    end

    # unit box expressed in a wall's frame: [along0, along1, out0, out1, z0, z1] (out = distance from the wall face toward the room)
    def in_wall_frame(unit, w)
      nx = w['dir'][1]
      ny = -w['dir'][0]
      pts = unit.corners.map do |p|
        px = p.x.to_mm - w['p0'][0]
        py = p.y.to_mm - w['p0'][1]
        [px * w['dir'][0] + py * w['dir'][1], px * nx + py * ny, p.z.to_mm]
      end
      [pts.map(&:first).minmax, pts.map { |p| p[1] }.minmax, pts.map { |p| p[2] }.minmax].flatten
    end

    def ov(a0, a1, b0, b1)
      [a1, b1].min - [a0, b0].max
    end

    # -> { 'problems'=>[], 'warnings'=>[], 'info'=>[], 'ok'=>bool }
    def run(proj, cfg, model = Sketchup.active_model)
      items = []
      recs = Exposure.collect(model)
      units = recs[:units]
      ws = Assistant.walls(proj)
      poly = proj['room']['poly']
      # 1. units standing inside each other
      Exposure.overlaps(model).each do |o|
        items << item('OVERLAPPING_UNITS', 'error', o[:cab], "#{o[:cab]} #{o[:detail]}", 'Delete or move the duplicate / resize the neighbour')
      end
      # 2. every unit inside the room
      if poly.size >= 3
        units.each do |u|
          bad = u.corners.select { |p| !inside?(poly, p.x.to_mm, p.y.to_mm, 8.0) }
          items << item('OUTSIDE_ROOM', 'error', u.g.name, "#{u.g.name} sticks out of the room by #{bad.size} of 8 corners", 'Shorten the run or move the unit inside the walls') unless bad.empty?
        end
      end
      # 3. openings (doors must stay free, windows must not be covered by units in front of them)
      proj['openings'].each do |o|
        w = ws.find { |x| x['id'] == o['wall'] }
        next unless w

        units.each do |u|
          a0, a1, d0, d1, z0, z1 = in_wall_frame(u, w)
          next unless d0 < 900 && ov(a0, a1, o['off'], o['off'] + o['w']) > 20

          if o['type'] == 'door'
            items << item('DOOR_BLOCKED', 'error', u.g.name, "#{u.g.name} stands in front of door #{o['id']}", 'Remove or shorten the unit')
          elsif ov(z0, z1, o['sill'], o['sill'] + o['h']) > 20
            sev = u.kind == 'base' ? 'warn' : 'error'
            items << item('WINDOW_COVERED', sev, u.g.name, "#{u.g.name} covers window #{o['id']} (sill #{o['sill'].round} mm)", u.kind == 'base' ? 'A base unit below a window is normal only when the sill is above the worktop (900 mm)' : 'Remove the upper unit in front of the window')
          end
        end
        items << item('WINDOW_BELOW_WORKTOP', 'warn', o['id'], "window #{o['id']} sill #{o['sill'].round} mm is below the 900 mm worktop", 'Raise the worktop splash / confirm') if o['type'] == 'window' && o['sill'] < 900
      end
      # 4. columns
      proj['columns'].each do |c|
        w = ws.find { |x| x['id'] == c['wall'] }
        next unless w

        units.each do |u|
          a0, a1, d0, _d1, = in_wall_frame(u, w)
          items << item('COLUMN_CONFLICT', 'error', u.g.name, "#{u.g.name} collides with column #{c['id']}", 'Use a notch (Edit > column notch) or leave the space') if d0 < c['d'] - 5 && ov(a0, a1, c['off'], c['off'] + c['w']) > 5
        end
      end
      # 5. appliances / housings
      units.each do |u|
        d = u.g.attribute_dictionary('egc')
        req = (JSON.parse(d['requires'].to_s) rescue [])
        req.each { |r| items << item(r['code'] || 'REQUIRES_CONFIRMATION', 'warn', u.g.name, "#{u.g.name}: #{r['item']} (#{r['detail']}) is a configurable default, not manufacturer data", 'Confirm the clearances for the real appliance (Settings)') }
        next unless d['type'].to_s == 'hob_oven'

        ps = Validate.parts_of(u)
        oven = ps.find { |p| p[:role] == 'appliance' && p[:part].to_s =~ /oven/ }
        hob = ps.find { |p| p[:role] == 'appliance' && p[:part].to_s =~ /hob/ }
        next unless oven && hob

        gap = hob[:z][0] - oven[:z][1]
        items << item('HOB_OVEN_CLEARANCE', 'error', u.g.name, "hob-to-oven clearance #{gap.round} mm < #{cfg['hob_oven_min_clear']} mm", 'Choose a shallower hob / oven or a taller base') if gap < cfg['hob_oven_min_clear'].to_f
      end
      # 5b. hard layout rules, measured on the built units (cabinet edge to cabinet edge along each wall)
      sev = proj['design'] && (proj['design']['opts'] || {})['from_vision'] ? 'warn' : 'error' # a layout copied from the client's design image is reported, not refused
      ws.each do |w|
        row = units.map { |u| [u, in_wall_frame(u, w)] }.select { |u, f| f[2].abs < 150 && %w[base tall].include?(u.kind.to_s) }
        row.select { |u, _| u.g.get_attribute('egc', 'type').to_s.include?('hob') }.each do |hu, hf|
          row.each do |u, f|
            next if u.equal?(hu)

            gap = [f[0] - hf[1], hf[0] - f[1]].max
            next if gap < -1

            t = u.g.get_attribute('egc', 'type').to_s
            items << item('HOB_SINK_CLEARANCE', sev, hu.g.name, format(AssistantDesign::RULE_TEXT['HOB_SINK_CLEARANCE'], gap.round), 'Move the hob or the sink apart') if t =~ /sink/ && gap < AssistantDesign::HOB_SINK_MIN - 1
            items << item('HOB_TALL_CLEARANCE', sev, hu.g.name, format(AssistantDesign::RULE_TEXT['HOB_TALL_CLEARANCE'], gap.round), 'Keep a base unit between the hob and the tall unit') if u.kind.to_s == 'tall' && gap < AssistantDesign::HOB_TALL_MIN - 1
          end
          side = [hf[0], w['len'] - hf[1]].min
          items << item('HOB_WALL_CLEARANCE', sev, hu.g.name, format(AssistantDesign::RULE_TEXT['HOB_WALL_CLEARANCE'], side.round), 'Move the hob away from the side wall') if side < AssistantDesign::HOB_TALL_MIN - 1
        end
      end
      ic = proj['image'] && proj['image']['consistency']
      items << item('IMAGE_SCALE_INCONSISTENT', 'error', 'image', "the sketch is not to scale: other labelled lengths imply scales that differ by up to #{ic['rows'].map { |r| r['dev_pct'].abs }.max} %", 'Give real dimensions (walls) instead of tracing this image') if ic && !ic['ok']
      # 6. ceiling
      cl = proj['room']['ceiling']['v']
      if cl
        items << item('CEILING_UNCONFIRMED', 'warn', 'room', "ceiling #{cl.round} mm is #{proj['room']['ceiling']['st']} (not confirmed by the user)", 'Confirm the ceiling height') unless proj['room']['ceiling']['st'] == Assistant::CONFIRMED
        top = units.map { |u| u.tr.origin.z.to_mm + u.h }.max.to_f
        items << item('CEILING_LOW', 'error', 'room', "units reach #{top.round} mm but the ceiling is #{cl.round} mm", 'Lower the tiers or confirm the ceiling') if top > cl + 1
      else
        items << item('CEILING_UNKNOWN', 'warn', 'room', 'ceiling height not confirmed', 'Enter the ceiling height')
      end
      # 7. services around the sink / hob
      sinks = units.select { |u| u.g.get_attribute('egc', 'type').to_s =~ /sink/ }
      sinks.each do |u|
        near = proj['services'].select { |s| %w[water_cold drain].include?(s['kind']) }.any? do |s|
          w = ws.find { |x| x['id'] == s['wall'] }
          next false unless w

          a0, a1, d0, = in_wall_frame(u, w)
          d0 < 900 && s['off'] >= a0 - 800 && s['off'] <= a1 + 800
        end
        items << item('SERVICE_NOT_NEAR_SINK', 'warn', u.g.name, "no water / drain point within 800 mm of #{u.g.name}", 'Confirm or add the water and drain points (or move the sink)') unless near || proj['services'].empty?
      end
      items << item('SERVICES_UNKNOWN', 'warn', 'room', 'no service points confirmed (water / drain / electrical / gas): the drawings will show proposals marked REQUIRES_CONFIRMATION', 'Enter the real service points') if proj['services'].empty?
      # 8. aisle
      d = proj['design']
      if d && %w[parallel island].include?(d['layout'].to_s)
        (d['plan'] || []).each do |k|
          a = k['params']['aisle'].to_f
          items << item('AISLE_TOO_NARROW', 'error', "layout #{d['layout']}", "aisle #{a.round} mm < #{AssistantDesign::AISLE_MIN.round} mm", 'Narrow the island / drop the second run') if a < AssistantDesign::AISLE_MIN
        end
      end
      # 9. stale / production integrity
      begin
        an = Cutlist.analyse(cfg, model, use_selection: false)
        an[:integrity].reject { |b| b[:code] == 'OVERLAPPING_UNITS' }.each do |b|
          items << item('STALE_PRODUCTION_DATA', 'error', "#{b[:cab]}/#{b[:part]}", b[:detail].to_s, 'Rebuild the unit with E.G.C Resize / Edit')
        end
      rescue StandardError => e
        items << item('ANALYSIS_FAILED', 'error', 'production', e.message[0, 120])
      end
      items.sort_by! { |i| SEV[i['severity']] }
      { 'problems' => items.select { |i| i['severity'] == 'error' }, 'warnings' => items.select { |i| i['severity'] == 'warn' }, 'info' => items.select { |i| i['severity'] == 'info' },
        'ok' => items.none? { |i| i['severity'] == 'error' } }
    end
  end
end
