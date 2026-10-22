# frozen_string_literal: true

require 'json'

module EGC
  # ONE room model for every room input (SketchUp geometry, dimensioned image read by the vision provider, DXF ...). Each input is normalised into
  #   { 'source', 'poly' => [[x, y], ...] (mm, clockwise from the south-west corner: wall A = west, B = north ...),
  #     'walls' => [ { 'id', 'name', 'len', 'physical', 'st', 'src' } ], 'openings' => [ { 'wall', 'type', 'off', 'w', 'h', 'sill', 'above', 'st', 'src' } ],
  #     'ceiling' => { 'v', 'st', 'src' }, 'dims' => [ { 'text', 'value', 'measured', 'what', 'st' } ], 'relations' => [...], 'problems' => [...] }
  # and then written into the assistant constraint model with RoomModel.apply. Statuses: CONFIRMED (measured AND a printed dimension agrees, or typed
  # by the user), INFERRED (measured / derived, no printed dimension), REQUIRES_CONFIRMATION (missing, unreadable or contradicting).
  # A side of the room without a wall (an open L) is a non-physical wall: nothing is built against it.
  module RoomModel
    module_function

    C = 'CONFIRMED'
    I = 'INFERRED'
    R = 'REQUIRES_CONFIRMATION'
    IDS = ('A'..'Z').to_a.freeze
    TOL = 1.0 # mm: a printed dimension agrees with the geometry

    def mm(v)
      v.to_f.to_mm
    end

    # polygon -> clockwise (y up), starting at the corner nearest the south-west, translated so that corner is 0,0
    def canonical(poly)
      p = poly.map { |x, y| [x.to_f, y.to_f] }
      p = p.reverse if Assistant.signed_area(p) > 0
      k = (0...p.size).min_by { |i| [p[i][0] + p[i][1], p[i][0]] }
      p = p.rotate(k)
      ox, oy = p.first
      p.map { |x, y| [(x - ox).round(1), (y - oy).round(1)] }
    end

    def wall_dirs(poly)
      poly.each_with_index.map do |a, i|
        b = poly[(i + 1) % poly.size]
        len = Math.hypot(b[0] - a[0], b[1] - a[1])
        { 'id' => IDS[i], 'p0' => a, 'p1' => b, 'len' => len.round(1), 'dir' => [(b[0] - a[0]) / len, (b[1] - a[1]) / len] }
      end
    end

    def dist_point_seg(p, w)
      dx = p[0] - w['p0'][0]
      dy = p[1] - w['p0'][1]
      t = (dx * w['dir'][0] + dy * w['dir'][1]).clamp(0.0, w['len'])
      [Math.hypot(dx - w['dir'][0] * t, dy - w['dir'][1] * t), t]
    end

    def parse_len(text)
      t = text.to_s.strip.downcase.tr(',', '.')
      n = t[/-?\d+(\.\d+)?/]
      return nil unless n

      v = n.to_f
      return v * 1000 if t =~ /\d\s*m\z/ && t !~ /mm/
      return v * 10 if t.include?('cm')

      v
    end

    # ---------------------------------------------------------------------------------------------------------------- SketchUp geometry
    # floor = the largest upward horizontal face at the lowest level; walls = vertical faces standing on the floor outline (their room-side face);
    # openings = holes in those wall faces; ceiling = wall height; printed dimensions = DimensionLinear entities (text vs measured length).
    def from_skp(model = Sketchup.active_model)
      faces = []
      dims = []
      walk = lambda do |list, tr|
        list.each do |e|
          if e.is_a?(Sketchup::Face)
            faces << [e, tr]
          elsif e.is_a?(Sketchup::DimensionLinear)
            dims << [e, tr]
          elsif (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && !e.attribute_dictionary('egc')
            walk.call(e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities, tr * e.transformation)
          end
        end
      end
      walk.call(model.entities.to_a, Geom::Transformation.new)
      pts_of = ->(loop, tr) { loop.vertices.map { |v| p = tr * v.position; [mm(p.x), mm(p.y), mm(p.z)] } }
      horiz = faces.select { |f, tr| n = f.normal.transform(tr); n.z > 0.99 }
      problems = []
      raise 'ROOM_NO_FLOOR: no floor face found (draw the floor of the room as one face)' if horiz.empty?

      zmin = horiz.map { |f, tr| pts_of.call(f.outer_loop, tr).map { |p| p[2] }.min }.min
      floor, ftr = horiz.select { |f, tr| pts_of.call(f.outer_loop, tr).all? { |p| (p[2] - zmin).abs < 1 } }.max_by { |f, tr| f.area }
      raw = pts_of.call(floor.outer_loop, ftr).map { |x, y, _| [x, y] }
      raw = raw.each_with_index.reject do |q, k| # drop vertices on a straight edge
        a = raw[k - 1]
        b = raw[(k + 1) % raw.size]
        ((q[0] - a[0]) * (b[1] - q[1]) - (q[1] - a[1]) * (b[0] - q[0])).abs < 1e-3 * [Math.hypot(q[0] - a[0], q[1] - a[1]) * Math.hypot(b[0] - q[0], b[1] - q[1]), 1e-9].max
      end.map(&:first)
      poly = canonical(raw)
      sx, sy = poly_origin(raw) # model point that became 0,0
      ws = wall_dirs(poly)
      vert = faces.select { |f, tr| f.normal.transform(tr).z.abs < 0.05 }
      walls = ws.map do |w|
        on = vert.select do |f, tr|
          vs = pts_of.call(f.outer_loop, tr)
          base = vs.select { |p| (p[2] - zmin).abs < 1 }.map { |x, y, _| [x - sx, y - sy] }
          base.size >= 2 && base.all? { |p| dist_point_seg(p, w)[0] < 1 } && (base.map { |p| dist_point_seg(p, w)[1] }.max - base.map { |p| dist_point_seg(p, w)[1] }.min) > w['len'] * 0.5
        end
        f, tr = on.max_by { |ff, _| ff.area }
        h = f ? pts_of.call(f.outer_loop, tr).map { |p| p[2] }.max - zmin : nil
        { 'id' => w['id'], 'name' => nil, 'len' => w['len'], 'physical' => !f.nil?, 'height' => h && h.round(1), 'face' => f, 'tr' => tr, 'st' => I, 'src' => f ? 'geometry: wall face on the floor outline' : 'geometry: floor edge without a wall (open side)' }
      end
      phys = walls.select { |w| w['physical'] }
      problems << { 'code' => 'ROOM_NO_WALLS', 'message' => 'no wall face stands on the floor outline' } if phys.empty?
      openings = []
      phys.each do |w|
        wd = ws.find { |x| x['id'] == w['id'] }
        w['face'].loops.reject(&:outer?).each do |l|
          vs = pts_of.call(l, w['tr'])
          ts = vs.map { |x, y, _| dist_point_seg([x - sx, y - sy], wd)[1] }
          zs = vs.map { |p| p[2] - zmin }
          sill = zs.min.round(1)
          openings << { 'wall' => w['id'], 'type' => sill < 50 ? 'door' : 'window', 'off' => ts.min.round(1), 'w' => (ts.max - ts.min).round(1), 'h' => (zs.max - zs.min).round(1),
                        'sill' => sill, 'st' => I, 'src' => 'geometry: hole in the wall face' }
        end
      end
      hmax = phys.map { |w| w['height'].to_f }.max
      ceiling = { 'v' => hmax && hmax.round(1), 'st' => hmax ? I : R, 'src' => hmax ? 'geometry: wall height' : 'no wall' }
      openings.each { |o| o['above'] = hmax ? (hmax - o['sill'] - o['h']).round(1) : nil }
      rm = { 'source' => 'skp', 'poly' => poly, 'walls' => walls.map { |w| w.reject { |k, _| %w[face tr].include?(k) } }, 'openings' => openings, 'ceiling' => ceiling,
             'dims' => [], 'problems' => problems }
      dims.each do |d, tr|
        a = d.start.is_a?(Array) ? d.start[1] : d.start
        b = d.end.is_a?(Array) ? d.end[1] : d.end
        a = tr * Geom::Point3d.new(a) rescue nil
        b = tr * Geom::Point3d.new(b) rescue nil
        # a SketchUp linear dimension measures either the straight distance or its projection on the red / green / blue axis it was drawn along
        val = parse_len(d.text)
        cands = a && b ? [a.distance(b), (b.x - a.x).abs, (b.y - a.y).abs, (b.z - a.z).abs].map { |v| v.to_mm.round(1) } : []
        meas = val ? (cands.min_by { |v| (v - val).abs }) : cands.first
        rm['dims'] << { 'text' => d.text.to_s, 'value' => val, 'measured' => meas }
      end
      verify(rm)
    end

    def poly_origin(raw)
      p = raw.map { |x, y| [x.to_f, y.to_f] }
      p = p.reverse if Assistant.signed_area(p) > 0
      k = (0...p.size).min_by { |i| [p[i][0] + p[i][1], p[i][0]] }
      p[k]
    end

    # ---------------------------------------------------------------------------------------------------------------- vision (dimensioned picture)
    # read = AssistantVision.normalize(...) with site['view'] == 'perspective': site['walls'] = [ { 'name', 'len', 'chain', 'src' } ] in picture order (left to right),
    # meeting at corners. Two walls = an L: the first is the west wall (A), the second the north wall (B); the other sides of the rectangle are open.
    def from_vision(read)
      s = read['site']
      wl = Array(s['walls'])
      problems = Array(read['problems']).dup
      raise 'ROOM_IMAGE_NO_WALLS: no wall length could be read from the picture' if wl.empty? || wl.all? { |w| w['len'].nil? }

      lens = wl.map { |w| w['len'] }
      if lens.any?(&:nil?)
        problems << { 'code' => 'WALL_LENGTH_NOT_WRITTEN', 'message' => "#{wl.select { |w| w['len'].nil? }.map { |w| w['name'] }.join(', ')}: length not written - type it" }
      end
      d = (wl.size >= 2 ? wl[0]['len'] : 3000.0).to_f
      w = (wl.size >= 2 ? wl[1]['len'] : wl[0]['len']).to_f
      poly = [[0.0, 0.0], [0.0, d], [w, d], [w, 0.0]]
      phys = wl.size >= 2 ? %w[A B] + (wl.size >= 3 ? ['C'] : []) : ['B']
      names = wl.size >= 2 ? { 'A' => wl[0], 'B' => wl[1], 'C' => wl[2] } : { 'B' => wl[0] }
      walls = wall_dirs(poly).map do |x|
        v = names[x['id']]
        { 'id' => x['id'], 'name' => v && v['name'], 'len' => x['len'], 'physical' => phys.include?(x['id']),
          'st' => v ? (v['src'] == 'written' || v['src'] == 'chain' ? C : I) : (wl.size >= 2 ? I : R),
          'src' => v ? "image: #{v['src']}#{v['chain'] ? " (#{v['chain'].map(&:round).join(' + ')})" : ''}" : (wl.size >= 2 ? 'closing side of the L (open)' : 'room depth unknown (only one wall seen)') }
      end
      by_name = names.each_with_object({}) { |(id, v), h| h[v['name'].to_s] = id if v }
      openings = Array(s['openings']).filter_map do |o|
        next unless o.is_a?(Hash)

        id = by_name[o['wall'].to_s] || (wl.size >= 2 ? 'B' : 'B')
        unless o['off'] && o['w'] && o['w'].to_f.positive?
          problems << { 'code' => 'OPENING_INCOMPLETE', 'message' => "#{o['type'] || 'Opening'} on wall #{o['wall'] || id} was detected, but its position or width is missing. Confirm or type those measurements before designing." }
        end

        src = o['src'] || {}
        complete = %w[off w h sill].all? { |k| %w[written derived].include?(src[k]) && !o[k].nil? }
        allw = complete && o['off'].to_f >= 0 && o['w'].to_f.positive? && o['h'].to_f.positive? && o['sill'].to_f >= 0
        type = %w[door window].include?(o['type'].to_s) ? o['type'].to_s : 'window'
        { 'wall' => id, 'type' => type, 'off' => o['off'], 'w' => o['w'], 'h' => o['h'], 'sill' => o['sill'], 'above' => o['above'],
          'st' => allw ? C : R, 'src' => "image: #{src.map { |k, v| "#{k} #{v}" }.join(', ')}" }
      end
      cv = s['ceiling']
      rm = { 'source' => 'image', 'poly' => poly, 'walls' => walls, 'openings' => openings,
             'ceiling' => { 'v' => cv, 'st' => cv ? C : R, 'src' => cv ? 'image: written' : 'not written' },
             'dims' => Array(s['written']).map { |n| { 'text' => n.to_s, 'value' => n.to_f * (read['unit'] == 'cm' ? 10 : (read['unit'] == 'm' ? 1000 : 1)), 'measured' => nil } },
             'problems' => problems }
      verify(rm)
    end

    # ---------------------------------------------------------------------------------------------------------------- printed dimensions vs model
    # every printed dimension is matched to a room quantity (wall length, chain part, opening size / sill / head, ceiling). A quantity confirmed by a printed
    # dimension becomes CONFIRMED; a printed dimension that disagrees with its own measured length is REQUIRES_CONFIRMATION.
    def quantities(rm)
      q = []
      rm['walls'].select { |w| w['physical'] }.each { |w| q << ["wall #{w['id']} length", w['len'], [:wall, w['id']]] }
      rm['openings'].each_with_index do |o, i|
        wl = rm['walls'].find { |w| w['id'] == o['wall'] }
        q << ["opening #{i + 1} width", o['w'], [:op, i, 'w']] << ["opening #{i + 1} height", o['h'], [:op, i, 'h']]
        q << ["opening #{i + 1} sill (floor to opening)", o['sill'], [:op, i, 'sill']] if o['sill'].to_f.positive?
        q << ["opening #{i + 1} head (opening to ceiling)", o['above'], [:op, i, 'above']] if o['above']
        q << ["wall #{o['wall']}: start to opening #{i + 1}", o['off'], [:op, i, 'off']]
        q << ["wall #{o['wall']}: opening #{i + 1} to end", (wl['len'] - o['off'] - o['w']).round(1), [:op, i, 'right']] if wl && o['off'] && o['w']
      end
      q << ['ceiling height', rm['ceiling']['v'], [:ceiling]] if rm['ceiling']['v']
      q
    end

    def verify(rm)
      q = quantities(rm)
      used = Hash.new(0)
      rm['dims'].each do |d|
        if d['value'].nil?
          d['st'] = R
          d['what'] = 'unreadable'
          next
        end
        if d['measured'] && (d['measured'] - d['value']).abs > TOL
          d['st'] = R
          rm['problems'] << { 'code' => 'DIMENSION_TEXT_DISAGREES', 'message' => "printed \"#{d['text']}\" but the dimension measures #{d['measured'].round} mm" }
        end
        cand = q.select { |_, v, _| v && (v - d['value']).abs <= TOL }
        hit = cand.min_by { |_, _, key| used[key] }
        if hit
          used[hit[2]] += 1
          d['what'] = hit[0]
          d['st'] ||= C
        else
          d['what'] = 'not matched to a room quantity'
          d['st'] ||= I
        end
      end
      confirmed = ->(key) { used[key].positive? }
      rm['walls'].each do |w|
        next unless w['physical']

        ops = rm['openings'].each_with_index.select { |o, _| o['wall'] == w['id'] }
        chain = ops.size == 1 && confirmed.call([:op, ops[0][1], 'off']) && confirmed.call([:op, ops[0][1], 'w']) && confirmed.call([:op, ops[0][1], 'right'])
        if confirmed.call([:wall, w['id']]) || chain
          w['st'] = C
          w['src'] = "#{w['src']}; #{chain && !confirmed.call([:wall, w['id']]) ? 'confirmed by the dimension chain' : 'confirmed by a printed dimension'}"
        end
      end
      rm['openings'].each_with_index do |o, i|
        keys = %w[w h off].map { |k| [:op, i, k] }
        o['st'] = C if keys.all? { |k| confirmed.call(k) } && (confirmed.call([:op, i, 'sill']) || o['sill'].to_f.zero?)
      end
      rm['ceiling']['st'] = C if confirmed.call([:ceiling])
      rm['relations'] = rm['walls'].each_cons(2).select { |a, b| a['physical'] && b['physical'] }.map { |a, b| "#{a['id']}-#{b['id']}: corner" }
      flags!(rm)
    end

    # ---------------------------------------------------------------------------------------------------------------- one confirmation criterion
    # Every measurement a design needs: the physical walls, the ceiling height and every opening (place and size). Used wherever the room is called
    # ready / confirmed, so the walls alone never decide it.
    def required(rm)
      list = rm['walls'].select { |w| w['physical'] }.map { |w| ["wall #{w['id']}", w['st'], !w['len'].nil?] }
      list << ['ceiling', rm['ceiling']['st'], !rm['ceiling']['v'].nil?]
      rm['openings'].each_with_index { |o, i| list << ["opening #{i + 1}", o['st'], !o['off'].nil? && !o['w'].nil?] }
      list
    end

    # usable for a proposal: nothing REQUIRES CONFIRMATION and nothing is missing
    def ready?(rm)
      required(rm).all? { |_n, st, has| has && st != R }
    end

    # CONFIRMED: every required measurement is CONFIRMED (an INFERRED ceiling or opening keeps the room unconfirmed even when all walls are confirmed)
    def confirmed?(rm)
      required(rm).all? { |_n, st, has| has && st == C }
    end

    def pending(rm)
      required(rm).reject { |_n, st, has| has && st == C }.map { |n, st, has| "#{n}: #{has ? st : 'missing'}" }
    end

    def flags!(rm)
      rm['ready'] = ready?(rm)
      rm['confirmed'] = confirmed?(rm)
      rm['pending'] = pending(rm)
      rm
    end

    # ---------------------------------------------------------------------------------------------------------------- user corrections (no rebuild by hand)
    # key: 'wall:A:len' | 'opening:0:off|w|h|sill' | 'ceiling' ; the value becomes CONFIRMED ('typed by the user').
    def correct(rm, key, value)
      return RoomReader.correct(rm, key, value) if rm['reader'] # a picture read: corrected values are solved again with the whole dimension set

      v = value.to_f
      raise "#{key}: a positive number is required" unless v.positive? || key.end_with?(':sill')

      parts = key.split(':')
      case parts[0]
      when 'wall'
        w = rm['walls'].find { |x| x['id'] == parts[1] } or raise "unknown wall #{parts[1]}"
        poly = rm['poly']
        raise 'only a rectangular room can be resized here' unless poly.size == 4

        wid = poly[2][0] - poly[0][0]
        dep = poly[1][1] - poly[0][1]
        %w[A C].include?(w['id']) ? dep = v : wid = v
        rm['poly'] = [[0.0, 0.0], [0.0, dep], [wid, dep], [wid, 0.0]]
        wall_dirs(rm['poly']).each { |x| (rm['walls'].find { |y| y['id'] == x['id'] } || {})['len'] = x['len'] }
        w['st'] = C
        w['src'] = 'typed by the user'
      when 'opening'
        o = rm['openings'][parts[1].to_i] or raise "unknown opening #{parts[1]}"
        o[parts[2]] = v
        o['above'] = (rm['ceiling']['v'].to_f - o['sill'].to_f - o['h'].to_f).round(1) if rm['ceiling']['v']
        o['st'] = C
        o['src'] = "#{o['src']}; #{parts[2]} typed by the user"
      when 'ceiling'
        rm['ceiling'] = { 'v' => v, 'st' => C, 'src' => 'typed by the user' }
        rm['openings'].each { |o| o['above'] = (v - o['sill'].to_f - o['h'].to_f).round(1) }
      when 'main_wall'
        rm['main_wall'] = parts[1]
      else
        raise "unknown field #{key}"
      end
      flags!(rm)
    end

    # ---------------------------------------------------------------------------------------------------------------- into the assistant constraint model
    def apply(rm, proj)
      st = ->(s) { s == C ? Assistant::CONFIRMED : (s == I ? Assistant::INFERRED : Assistant::REQ) }
      Assistant.set_room(proj, rm['poly'], rm['walls'].select { |w| w['physical'] }.all? { |w| w['st'] == C } ? Assistant::CONFIRMED : Assistant::INFERRED)
      %w[openings no_build].each { |k| proj[k].reject! { |e| e['src'] == 'room_model' } }
      ids = Assistant.walls(proj).map { |w| w['id'] }
      rm['walls'].each do |w|
        next if w['physical'] || !ids.include?(w['id'])

        proj['no_build'] << { 'id' => "NB#{w['id']}", 'wall' => w['id'], 'off' => 0.0, 'w' => w['len'], 'why' => 'open side of the room (no wall)', 'src' => 'room_model' }
      end
      rm['openings'].each do |o|
        next unless o['off'] && o['w']

        e = Assistant.add_opening(proj, o['wall'], o['type'], o['off'], o['w'], o['h'].to_f, o['sill'].to_f, st.call(o['st']))
        e['src'] = 'room_model'
      end
      Assistant.set_ceiling(proj, rm['ceiling']['v'].to_f, st.call(rm['ceiling']['st'])) if rm['ceiling']['v']
      # the room as a whole is CONFIRMED only when every required measurement is (walls, ceiling, openings); 'ready' stays the reader's own verdict
      rm['confirmed'] = confirmed?(rm)
      rm['pending'] = pending(rm)
      proj['room_model'] = rm
      proj
    end

    # ---------------------------------------------------------------------------------------------------------------- what the user checks before any proposal
    def table(rm, lang = 'en')
      ar = lang == 'ar'
      rows = []
      rm['walls'].each { |w| rows << { 'key' => "wall:#{w['id']}:len", 'item' => "#{ar ? 'حائط' : 'Wall'} #{w['id']}#{w['name'] ? " (#{w['name']})" : ''}#{w['physical'] ? '' : (ar ? ' - مفتوح' : ' - open')}", 'value' => w['len'], 'st' => w['physical'] ? w['st'] : I, 'src' => w['src'], 'edit' => w['physical'] && (rm['reader'] || rm['poly'].size == 4) } }
      (rm['angles'] || []).each { |a| rows << { 'key' => "wall:#{rm['map'][a['wall']]}:angle", 'item' => "#{ar ? 'زاوية الركن' : 'Corner angle'} #{a['at']}", 'value' => a['deg'], 'st' => C, 'src' => 'GEOMETRY: inside corner angle (90 = square)', 'edit' => true } }
      rm['openings'].each_with_index do |o, i|
        nm = "#{o['type'] == 'door' ? (ar ? 'باب' : 'Door') : (ar ? 'فتحة / شباك' : 'Opening / window')} #{i + 1} (#{ar ? 'حائط' : 'wall'} #{o['wall']})"
        { 'off' => ar ? 'من بداية الحائط' : 'from wall start', 'w' => ar ? 'العرض' : 'width', 'h' => ar ? 'الارتفاع' : 'height', 'sill' => ar ? 'الجلسة' : 'sill' }.each do |k, lab|
          rows << { 'key' => "opening:#{i}:#{k}", 'item' => "#{nm} - #{lab}", 'value' => o[k], 'st' => o['st'], 'src' => o['src'], 'edit' => true }
        end
        rows << { 'key' => nil, 'item' => "#{nm} - #{ar ? 'فوق الفتحة' : 'above the opening'}", 'value' => o['above'], 'st' => o['st'], 'src' => 'ceiling - sill - height', 'edit' => false } if o['above']
      end
      rows << { 'key' => 'ceiling', 'item' => ar ? 'ارتفاع السقف' : 'Ceiling height', 'value' => rm['ceiling']['v'], 'st' => rm['ceiling']['st'], 'src' => rm['ceiling']['src'], 'edit' => true }
      rows
    end

    # plan + one elevation per physical wall, drawn from the model only (what was understood, before any kitchen)
    def svg(rm)
      return '' if rm['poly'].to_a.size < 3

      mnx = rm['poly'].map(&:first).min
      mny = rm['poly'].map(&:last).min
      poly = rm['poly'].map { |x, y| [x - mnx, y - mny] }
      w = poly.map(&:first).max
      d = poly.map(&:last).max
      s = 260.0 / [w, d].max
      pad = 30
      out = +"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 #{(w * s + 2 * pad).round} #{(d * s + 2 * pad).round}' style='max-width:100%;background:#fff'>"
      wall_dirs(poly).each do |x|
        wm = rm['walls'].find { |y| y['id'] == x['id'] }
        a = [pad + x['p0'][0] * s, pad + (d - x['p0'][1]) * s]
        b = [pad + x['p1'][0] * s, pad + (d - x['p1'][1]) * s]
        out << "<line x1='#{a[0].round(1)}' y1='#{a[1].round(1)}' x2='#{b[0].round(1)}' y2='#{b[1].round(1)}' stroke='#{wm['physical'] ? '#222' : '#bbb'}' stroke-width='#{wm['physical'] ? 5 : 1.5}' #{wm['physical'] ? '' : "stroke-dasharray='5 4'"}/>"
        mx = (a[0] + b[0]) / 2
        my = (a[1] + b[1]) / 2
        out << "<text x='#{mx.round(1)}' y='#{(my + (x['dir'][0].abs > 0.5 ? (x['p0'][1] > d / 2 ? -9 : 16) : 4)).round(1)}' font-size='10' text-anchor='middle' font-family='Arial'>#{x['id']} #{wm['len'].round}</text>"
        rm['openings'].select { |o| o['wall'] == x['id'] && o['off'] && o['w'] }.each do |o|
          p0 = [pad + (x['p0'][0] + x['dir'][0] * o['off']) * s, pad + (d - x['p0'][1] - x['dir'][1] * o['off']) * s]
          p1 = [pad + (x['p0'][0] + x['dir'][0] * (o['off'] + o['w'])) * s, pad + (d - x['p0'][1] - x['dir'][1] * (o['off'] + o['w'])) * s]
          out << "<line x1='#{p0[0].round(1)}' y1='#{p0[1].round(1)}' x2='#{p1[0].round(1)}' y2='#{p1[1].round(1)}' stroke='#2b7bd6' stroke-width='7'/>"
        end
      end
      out << '</svg>'
      phys = rm['walls'].select { |x| x['physical'] }
      ch = rm['ceiling']['v'] || 2800.0
      phys.each do |x|
        e = 250.0 / [x['len'], ch].max
        out << "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 #{(x['len'] * e + 60).round} #{(ch * e + 40).round}' style='max-width:100%;background:#fff;margin-top:6px'>"
        out << "<rect x='30' y='10' width='#{(x['len'] * e).round(1)}' height='#{(ch * e).round(1)}' fill='#f3f1ec' stroke='#333'/>"
        out << "<text x='#{(30 + x['len'] * e / 2).round}' y='#{(ch * e + 30).round}' font-size='10' text-anchor='middle' font-family='Arial'>#{x['id']} = #{x['len'].round} mm</text>"
        out << "<text x='22' y='#{(10 + ch * e / 2).round}' font-size='10' text-anchor='middle' font-family='Arial' transform='rotate(-90 22 #{(10 + ch * e / 2).round})'>#{ch.round}</text>"
        rm['openings'].select { |o| o['wall'] == x['id'] && o['off'] && o['w'] && o['h'] }.each do |o|
          ox = 30 + o['off'] * e
          oy = 10 + (ch - o['sill'].to_f - o['h'].to_f) * e
          out << "<rect x='#{ox.round(1)}' y='#{oy.round(1)}' width='#{(o['w'] * e).round(1)}' height='#{(o['h'] * e).round(1)}' fill='#dbe9f7' stroke='#2b7bd6'/>"
          out << "<text x='#{(ox + o['w'] * e / 2).round}' y='#{(oy - 3).round}' font-size='9' text-anchor='middle' font-family='Arial'>#{o['w'].round} x #{o['h'].round} @ #{o['off'].round} / sill #{o['sill'].round}</text>"
        end
        out << '</svg>'
      end
      out
    end
  end
end
