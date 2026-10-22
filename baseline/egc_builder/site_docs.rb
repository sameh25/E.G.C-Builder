# frozen_string_literal: true

require 'json'

module EGC
  # REAL 2D SITE / EXECUTION DOCUMENTS - every line is derived from the current model + constraints (no template drawings):
  # site plan, wall elevations, sections, electrical / plumbing / gas + duct plans, appliance installation dimensions, worktop plan,
  # installation plan and notes. Each function returns a printable HTML sheet (inline SVG + title block) and the data it used.
  module SiteDocs
    module_function

    H = SvgDraw

    DEFAULT_DEV = { 'oven' => 'OVEN_60', 'hob' => 'HOB_60', 'hob_gas' => 'HOB_GAS_60', 'fridge' => 'FRIDGE_TALL', 'dishwasher' => 'DISH_60', 'washer' => 'WASHER_60', 'hood' => 'HOOD_CHIMNEY',
                    'microwave' => 'MICRO_38', 'coffee' => 'COFFEE_45', 'dryer' => 'DRYER_60', 'wine_cooler' => 'WINE_COOLER', 'warming' => 'WARMING_DRAWER', 'freezer' => 'FREEZER_TALL' }.freeze
    # proposals only: typical heights above the finished floor (mm). They are NOT confirmed site data.
    PROPOSAL_Z = { 'fridge' => 300, 'oven' => 300, 'hob' => 300, 'hob_gas' => 300, 'hood' => 2300, 'microwave' => 300, 'dishwasher' => 300, 'washer' => 500, 'dryer' => 500,
                   'coffee' => 1100, 'wine_cooler' => 300, 'warming' => 300, 'freezer' => 300, 'led' => 2750 }.freeze
    WATER_Z = { 'water_cold' => 550, 'water_hot' => 550, 'drain' => 450 }.freeze
    SERVICE_STATUSES = %w[CONFIRMED INFERRED REQUIRES_CONFIRMATION MISSING_DATA].freeze
    LEVELS = [0, 100, 880, 900, 1500, 2200, 2700, 2800].freeze

    # Save explicit review status; absent status remains unapproved rather than silently confirmed.
    def normalize_service_review(rows)
      raise 'SERVICE_REVIEW_EMPTY: no modeled service points were supplied for review.' unless rows.is_a?(Array) && rows.any?

      rows.map do |p|
        off = Float(p['off']); z = Float(p['z'])
        raise "SERVICE_REVIEW_INVALID_COORDINATE: #{p['id']} has a non-finite X or Z value." unless off.finite? && z.finite?
        status = p['status'].to_s
        status = 'REQUIRES_CONFIRMATION' unless SERVICE_STATUSES.include?(status)
        { 'kind' => p['kind'].to_s, 'wall' => p['wall'].to_s, 'device' => p['unit'].to_s, 'off' => off, 'z' => z,
          'spec' => p['spec'].to_s.strip.empty? ? nil : p['spec'].to_s.strip,
          'notes' => p['notes'].to_s.strip.empty? ? nil : p['notes'].to_s.strip, 'id' => p['id'].to_s, 'st' => status }
      rescue ArgumentError, TypeError
        raise "SERVICE_REVIEW_INVALID_COORDINATE: #{p['id']} requires numeric X and Z dimensions in mm."
      end
    end

    # ------------------------------------------------------------------ data
    def collect(model, proj, cfg)
      ws = Assistant.walls(proj)
      ws = Civil.reference_lines(model) if ws.empty?
      recs = Exposure.collect(model)
      units = recs[:units].map do |u|
        d = u.g.attribute_dictionary('egc')
        fp = [0, 2, 6, 4].map { |i| c = u.corners[i]; [c.x.to_mm, c.y.to_mm] }
        wall = nil
        along = nil
        out = nil
        best = 1e9
        front = u.tr.yaxis.reverse # the unit faces the room: its front must be the wall's room-side normal (right of the wall direction)
        ws.each do |w|
          a0, a1, d0, d1, = AssistantValidate.in_wall_frame(u, w)
          next unless (front.x * w['dir'][1] - front.y * w['dir'][0]) > 0.9
          next unless d0 > -60 && d0 < 900 && AssistantValidate.ov(a0, a1, 0, w['len']) > 50 && (d1 - d0) > 100

          if d0.abs < best
            best = d0.abs
            wall = w['id']
            along = [a0, a1]
            out = [d0, d1]
          end
        end
        apps = Validate.parts_of(u).select { |p| p[:role] == 'appliance' }.map do |p|
          kind = p[:part].to_s
          did = p[:d]['dev_id'] || DEFAULT_DEV[kind] || DEFAULT_DEV[kind.sub(/_gas|_chimney|_slim/, '')]
          dv = did && Catalog.device(did)
          pts = [[p[:x][0], p[:y][0], p[:z][0]], [p[:x][1], p[:y][1], p[:z][1]]].flat_map { |a| [a] }
          ctr = u.tr * Geom::Point3d.new(((p[:x][0] + p[:x][1]) / 2.0).mm, ((p[:y][0] + p[:y][1]) / 2.0).mm, ((p[:z][0] + p[:z][1]) / 2.0).mm)
          { 'kind' => kind, 'dev' => did, 'dev_src' => p[:d]['dev_src'] || 'default', 'dev_name' => dv && dv[:en], 'dev_name_ar' => dv && dv[:ar], 'profile' => (Catalog.profile(did) if did), 'center' => [ctr.x.to_mm, ctr.y.to_mm, ctr.z.to_mm],
            'z' => [u.tr.origin.z.to_mm + p[:z][0], u.tr.origin.z.to_mm + p[:z][1]], 'opening' => (JSON.parse(p[:d]['opening'].to_s) rescue nil), 'box' => pts }
        end
        { 'rec' => u, 'name' => u.g.name, 'code' => d['code'].to_s, 'kind' => u.kind, 'type' => d['type'].to_s, 'w' => u.w, 'd' => u.d, 'h' => u.h, 'z0' => u.tr.origin.z.to_mm,
          'tier' => d['tier'], 'fp' => fp, 'wall' => wall, 'along' => along, 'out' => out, 'apps' => apps, 'led' => (JSON.parse(d['led'].to_s) rescue nil),
          'requires' => (JSON.parse(d['requires'].to_s) rescue []) }
      end
      units.concat(Civil.device_units(recs[:blockers], ws, cfg))
      { units: units, walls: ws, proj: proj, cfg: cfg, model: model }
    end

    def used_walls(data)
      ids = data[:units].map { |u| u['wall'] }.compact.uniq
      data[:walls].select { |w| ids.include?(w['id']) }
    end

    def world_of(w, along, out)
      [w['p0'][0] + w['dir'][0] * along + w['dir'][1] * out, w['p0'][1] + w['dir'][1] * along - w['dir'][0] * out]
    end

    # ------------------------------------------------------------------ SITE PLAN (also the base of the service / installation plans)
    def draw_plan(data, opts = {})
      proj = data[:proj]
      poly = proj['room']['poly']
      thk = (proj['room']['wall_thk'] || 200).to_f
      xs = poly.map(&:first)
      ys = poly.map(&:last)
      if poly.empty?
        points = data[:units].flat_map { |u| u['fp'] } + data[:walls].flat_map { |w| [w['p0'], w['p1']] }
        raise 'No units available for site drawing' if points.empty?
        xs = points.map(&:first)
        ys = points.map(&:last)
      end
      cv = SvgDraw::Canvas.new(xs.min - thk, ys.min - thk, xs.max + thk, ys.max + thk, pad: 1100)
      cv.poly(poly, fill: '#fbfaf5', stroke: 'none') unless poly.empty?
      data[:walls].each do |w|
        if w['reference_only']
          cv.line(*w['p0'], *w['p1'], stroke: '#888', dash: '20 12')
          next
        end
        ox = -w['dir'][1] * thk
        oy = w['dir'][0] * thk
        cv.poly([w['p0'], w['p1'], [w['p1'][0] + ox, w['p1'][1] + oy], [w['p0'][0] + ox, w['p0'][1] + oy]], fill: '#8b8b86', stroke: '#444')
      end
      proj['openings'].each do |o|
        w = data[:walls].find { |x| x['id'] == o['wall'] }
        next unless w

        a = world_of(w, o['off'], -5)
        b = world_of(w, o['off'] + o['w'], -5)
        c = world_of(w, o['off'] + o['w'], -thk - 5)
        dd = world_of(w, o['off'], -thk - 5)
        cv.poly([a, b, c, dd], fill: (o['type'] == 'door' ? '#fff' : '#cfe6f0'), stroke: '#333')
        if o['type'] == 'door'
          ang = Math.atan2(w['dir'][1], w['dir'][0]) * 180 / Math::PI
          hx, hy = world_of(w, o['off'], 0)
          cv.arc(hx, hy, o['w'], ang - 90, ang, stroke: '#666') # swing into the room
          cv.line(hx, hy, hx + w['dir'][1] * o['w'], hy - w['dir'][0] * o['w'], stroke: '#666')
        end
        mx, my = world_of(w, o['off'] + o['w'] / 2.0, -thk / 2.0)
        cv.text(mx, my, o['id'], size: cv.fs * 0.8, bold: true)
      end
      proj['columns'].each do |c|
        w = data[:walls].find { |x| x['id'] == c['wall'] }
        next unless w

        cv.poly([world_of(w, c['off'], 0), world_of(w, c['off'] + c['w'], 0), world_of(w, c['off'] + c['w'], c['d']), world_of(w, c['off'], c['d'])], fill: '#555', stroke: '#222')
        mx, my = world_of(w, c['off'] + c['w'] / 2.0, c['d'] / 2.0)
        cv.text(mx, my, c['id'], size: cv.fs * 0.7, fill: '#fff')
      end
      data[:units].each do |u|
        case u['kind']
        when 'base' then cv.poly(u['fp'], fill: '#efe3c6', stroke: '#6b5a33')
        when 'tall' then cv.poly(u['fp'], fill: '#d7d7d0', stroke: '#444')
        else cv.poly(u['fp'], fill: 'none', stroke: '#9a8f70', dash: "#{cv.fs / 2} #{cv.fs / 3}", sw: cv.fs / 40.0)
        end
        next unless %w[base tall].include?(u['kind']) && !opts[:no_labels]

        cx = EGC::Num.sum(u['fp'], &:first) / 4.0
        cy = EGC::Num.sum(u['fp'], &:last) / 4.0
        cv.text(cx, cy - cv.fs * 0.3, u['code'], size: cv.fs * 0.75, bold: true)
        cv.text(cx, cy + cv.fs * 0.7, "#{u['w'].round}", size: cv.fs * 0.6, fill: '#555')
      end
      data[:units].each do |u|
        u['apps'].each do |a|
          next if a['kind'] == 'hood'

          lab = { 'fridge' => 'F', 'oven' => 'O', 'hob' => 'H', 'hob_gas' => 'H', 'sink' => 'S', 'dishwasher' => 'D', 'washer' => 'W' }[a['kind']] || a['kind'][0].upcase
          cv.circle(a['center'][0], a['center'][1], cv.fs * 0.7, fill: '#fff', stroke: '#333')
          cv.text(a['center'][0], a['center'][1] - cv.fs * 0.28, lab, size: cv.fs * 0.8, bold: true)
        end
      end
      # dimensions: wall lengths outside, run overall + unit chains inside
      data[:walls].each do |w|
        cv.dim(w['p0'][0] - w['dir'][1] * thk, w['p0'][1] + w['dir'][0] * thk, w['p1'][0] - w['dir'][1] * thk, w['p1'][1] + w['dir'][0] * thk, thk * 1.6 + 250, w['len'].round.to_s)
      end
      unless opts[:no_chain]
        used_walls(data).each do |w|
          us = data[:units].select { |u| u['wall'] == w['id'] && u['kind'] == 'base' }.sort_by { |u| u['along'][0] }
          us.each do |u|
            a = world_of(w, u['along'][0], u['out'][1] + 120)
            b = world_of(w, u['along'][1], u['out'][1] + 120)
            cv.dim(a[0], a[1], b[0], b[1], -cv.fs * 1.2, u['w'].round.to_s)
          end
          next if us.empty?

          a = world_of(w, us.first['along'][0], us.map { |u| u['out'][1] }.max + 120)
          b = world_of(w, us.last['along'][1], us.map { |u| u['out'][1] }.max + 120)
          cv.dim(a[0], a[1], b[0], b[1], -cv.fs * 3.4, "#{(us.last['along'][1] - us.first['along'][0]).round} run #{w['id']}")
        end
      end
      poly.each_with_index do |(x, y), i|
        cv.circle(x, y, cv.fs * 0.35, fill: '#b42318', stroke: '#b42318')
        cv.text(x + cv.fs * 1.2, y + cv.fs * 0.9, "P#{i + 1} (#{x.round}, #{y.round})", size: cv.fs * 0.6, anchor: 'start', fill: '#b42318')
      end
      cv
    end

    def legend(lang)
      ar = lang == 'ar'
      "<div class='note'>#{ar ? 'الرموز: F ثلاجة · O فرن · H بوتجاز · S حوض · D غسالة أطباق · وحدات علوية بخط منقط · P1.. نقاط مرجعية (إحداثيات مم)' : 'Legend: F refrigerator · O oven · H hob · S sink · D dishwasher · upper units dashed · P1.. reference points (mm coordinates)'}</div>"
    end

    def site_plan(data, lang, st)
      cv = draw_plan(data)
      SvgDraw.sheet(data[:proj], title: lang == 'ar' ? 'المسقط الأفقي للموقع' : 'SITE PLAN', sheet_no: '01', scale: '1:50 (as printed)', zone: 'ALL', status: st[:status], lang: lang, extra_status: st[:doc],
                    body: "<div class='draw'>#{cv.svg}</div>#{legend(lang)}#{reference_notes(data)}#{unit_table(data, lang)}")
    end

    def reference_notes(data)
      notes = []
      notes << 'R references are inferred from cabinet backs, not measured room walls. Verify all site dimensions.' if data[:walls].any? { |w| w['reference_only'] }
      data[:units].select { |u| !u['wall'] && !u['apps'].empty? }.each do |u|
        notes << "#{u['code']} / #{u['name']}: no matching wall/reference; service positions NOT VERIFIED."
      end
      notes.map { |note| "<div class='warn'>#{H.h(note)}</div>" }.join
    end

    def unit_table(data, lang)
      ar = lang == 'ar'
      rows = data[:units].select { |u| %w[base tall].include?(u['kind']) }.sort_by { |u| [u['wall'].to_s, u['along'] ? u['along'][0] : 0] }.map do |u|
        [u['code'], u['name'], u['type'], "#{u['w'].round}×#{u['h'].round}×#{u['d'].round}", u['wall'], u['along'] ? "#{u['along'][0].round}–#{u['along'][1].round}" : '-']
      end
      SvgDraw.data_table([ar ? 'الكود' : 'ID', ar ? 'الوحدة' : 'Unit', ar ? 'النوع' : 'Type', 'W×H×D', ar ? 'الحائط' : 'Wall', ar ? 'من–إلى (مم)' : 'from–to (mm)'], rows)
    end

    # ------------------------------------------------------------------ WALL ELEVATIONS
    def elevation(data, wall, lang, st)
      cfg = data[:cfg]
      proj = data[:proj]
      ceiling = (proj['room']['ceiling']['v'] || cfg['ceiling']).to_f
      cv = SvgDraw::Canvas.new(0, 0, wall['len'], ceiling, pad: 800)
      cv.rect(0, 0, wall['len'], ceiling, fill: '#fbfaf5', stroke: '#333')
      cv.text(wall['len'] / 2.0, ceiling + cv.fs * 2, 'INFERRED REFERENCE — VERIFY ON SITE', size: cv.fs * 0.7) if wall['reference_only']
      cv.line(-300, 0, wall['len'] + 300, 0, stroke: '#000', sw: cv.fs / 10.0)
      cv.text(-330, -cv.fs * 1.2, 'FFL ±0.00', size: cv.fs * 0.8, anchor: 'end', bold: true)
      cv.text(-330, ceiling + cv.fs * 0.3, "CEILING #{ceiling.round}", size: cv.fs * 0.7, anchor: 'end')
      proj['openings'].select { |o| o['wall'] == wall['id'] }.each do |o|
        z0 = o['type'] == 'door' ? 0 : o['sill']
        cv.rect(o['off'], z0, o['off'] + o['w'], z0 + o['h'], fill: (o['type'] == 'door' ? '#e8e0d0' : '#cfe6f0'), stroke: '#336', dash: "#{cv.fs / 3} #{cv.fs / 4}")
        cv.text(o['off'] + o['w'] / 2.0, z0 + o['h'] / 2.0, "#{o['id']} #{o['w'].round}×#{o['h'].round}#{o['type'] == 'window' ? " sill #{o['sill'].round}" : ''}", size: cv.fs * 0.7)
        cv.dim(o['off'], -260, o['off'] + o['w'], -260, -1, nil) if false
      end
      proj['columns'].select { |c| c['wall'] == wall['id'] }.each { |c| cv.rect(c['off'], 0, c['off'] + c['w'], ceiling, fill: '#bbb', stroke: '#444'); cv.text(c['off'] + c['w'] / 2.0, ceiling / 2.0, c['id'], size: cv.fs * 0.7) }
      us = data[:units].select { |u| u['wall'] == wall['id'] }
      us.each do |u|
        a0, a1 = u['along']
        z0 = u['z0']
        case u['kind']
        when 'base'
          pl = (u['rec'].g.attribute_dictionary('egc')['spec'].to_s[/"plinth":([0-9.]+)/, 1] || cfg['plinth']).to_f
          cv.rect(a0, 0, a1, pl, fill: '#ddd', stroke: '#777')
          cv.rect(a0, pl, a1, u['h'] - cfg['top_thk'].to_f, fill: '#efe3c6', stroke: '#6b5a33')
          cv.text((a0 + a1) / 2.0, u['h'] / 2.0, u['code'], size: cv.fs * 0.8, bold: true)
        when 'tall'
          cv.rect(a0, z0, a1, z0 + u['h'], fill: '#e4e1d5', stroke: '#555')
          cv.text((a0 + a1) / 2.0, z0 + u['h'] * 0.62, u['code'], size: cv.fs * 0.8, bold: true)
        else
          cv.rect(a0, z0, a1, z0 + u['h'], fill: '#f3e7cb', stroke: '#6b5a33')
          cv.text((a0 + a1) / 2.0, z0 + u['h'] / 2.0, u['code'], size: cv.fs * 0.7, bold: true)
          cv.text((a0 + a1) / 2.0, z0 + u['h'] / 2.0 - cv.fs * 0.9, "T#{u['tier']}", size: cv.fs * 0.55, fill: '#8a5a00') if u['tier']
        end
        u['apps'].each do |ap|
          zs = ap['z']
          w = ap['opening'] && ap['opening']['w']
          ac = along_of(wall, ap['center'])
          half = (u['w'] * 0.45)
          cv.rect(ac - [half, (ap['dev'] && Catalog.device(ap['dev']) ? Catalog.device(ap['dev'])[:w] / 2.0 : half)].min, zs[0], ac + [half, (ap['dev'] && Catalog.device(ap['dev']) ? Catalog.device(ap['dev'])[:w] / 2.0 : half)].min, zs[1], fill: '#3b3f45', stroke: '#111', opacity: 0.85)
          cv.text(ac, (zs[0] + zs[1]) / 2.0, ap['kind'], size: cv.fs * 0.6, fill: '#fff') if zs[1] - zs[0] > cv.fs * 2
        end
      end
      # worktop + fascia (real parts)
      each_part(data[:model], %w[countertop fascia], data[:walls]).each do |p|
        next unless (p[:wall] == wall['id'])

        cv.rect(p[:along][0], p[:z][0], p[:along][1], p[:z][1], fill: p[:part] == 'countertop' ? '#222' : '#e0d3b4', stroke: '#111')
        cv.text((p[:along][0] + p[:along][1]) / 2.0, p[:z][0] - cv.fs * 0.9, p[:part] == 'fascia' ? "fascia #{(p[:z][1] - p[:z][0]).round}" : '', size: cv.fs * 0.55) if p[:part] == 'fascia'
      end
      # levels (left) and unit widths (top)
      lv = LEVELS.select { |z| z <= ceiling }
      lv.each_cons(2) { |a, b| cv.dim(0, a, 0, b, cv.fs * 5.0, (b - a).round.to_s) }
      cv.dim(0, 0, 0, ceiling, cv.fs * 8.5, "#{ceiling.round}")
      lv.each { |z| cv.text(-cv.fs * 0.5, z - cv.fs * 0.2, z.to_s, size: cv.fs * 0.55, anchor: 'end', fill: '#b42318') }
      base = us.select { |u| u['kind'] != 'wall' && u['kind'] != 'hood' }.sort_by { |u| u['along'][0] }
      base.each { |u| cv.dim(u['along'][0], 0, u['along'][1], 0, -cv.fs * 2.4, u['w'].round.to_s) }
      cv.dim(0, 0, wall['len'], 0, -cv.fs * 4.6, "#{wall['len'].round} wall #{wall['id']}")
      SvgDraw.sheet(proj, title: (lang == 'ar' ? 'واجهة الحائط ' : 'WALL ELEVATION ') + wall['id'], sheet_no: "02-#{wall['id']}", scale: '1:25 (as printed)', zone: "Wall #{wall['id']}", status: st[:status], lang: lang, extra_status: st[:doc],
                    body: "<div class='draw'>#{cv.svg}</div><div class='note'>#{lang == 'ar' ? 'المناسيب من الأرضية النهائية FFL. الأبعاد بالمليمتر.' : 'Levels from the finished floor (FFL). Dimensions in mm.'} #{us.size} units on this wall.</div>")
    end

    def along_of(w, c)
      (c[0] - w['p0'][0]) * w['dir'][0] + (c[1] - w['p0'][1]) * w['dir'][1]
    end

    # real parts by name (countertop, fascia, filler ...) with their position in wall frames
    def each_part(model, names, walls = nil)
      out = []
      walk = lambda do |ents, tr|
        ents.each do |e|
          next unless e.is_a?(Sketchup::Group)

          t = tr * e.transformation
          d = e.attribute_dictionary('egc')
          if d && d['role'] == 'part' && names.include?(d['part'].to_s)
            lb = e.local_bounds
            pts = [lb.min.x, lb.max.x].product([lb.min.y, lb.max.y], [lb.min.z, lb.max.z]).map { |x, y, z| t * Geom::Point3d.new(x, y, z) }
            out << { part: d['part'].to_s, pts: pts, z: pts.map { |p| p.z.to_mm }.minmax, d: d, ent: e, tr: t }
          elsif !(d && d['role'])
            walk.call(e.entities, t)
          end
        end
      end
      walk.call(model.entities, Geom::Transformation.new)
      ws = walls || Assistant.walls(Assistant.load(model))
      ws = Civil.reference_lines(model) if ws.empty?
      out.each do |p|
        best = ws.map do |w|
          nx = w['dir'][1]
          ny = -w['dir'][0]
          al = p[:pts].map { |q| (q.x.to_mm - w['p0'][0]) * w['dir'][0] + (q.y.to_mm - w['p0'][1]) * w['dir'][1] }
          ot = p[:pts].map { |q| (q.x.to_mm - w['p0'][0]) * nx + (q.y.to_mm - w['p0'][1]) * ny }
          [w, al.minmax, ot.min]
        end.select { |w, al, ot| ot > -60 && ot < 900 && AssistantValidate.ov(al[0], al[1], 0, w['len']) > 0 }.min_by { |_w, _al, ot| ot.abs }
        next unless best

        p[:wall] = best[0]['id']
        p[:along] = best[1]
        p[:out] = best[2]
      end
      out
    end

    # ------------------------------------------------------------------ SERVICE POINTS (electrical / plumbing / gas / duct)
    # Every point is linked to a device. The user's confirmed service points win; otherwise a PROPOSAL is drawn and marked REQUIRES_CONFIRMATION.
    # No rating, breaker, pipe size or circuit is ever invented.
    # ---- rough-in rules for PROPOSED points (a point the user placed always wins; every proposal stays REQUIRES_CONFIRMATION) ----
    # socket of a built-in appliance: in the neighbouring accessible cabinet, never behind the appliance; hood socket on the hood centreline.
    ELEC_RULE_Z = { 'oven' => 250, 'hob' => 250, 'hob_gas' => 250, 'microwave' => 250, 'dishwasher' => 400, 'fridge' => 250, 'freezer' => 250, 'hood' => 1950 }.freeze
    FRIDGE_HIGH_Z = 1200
    WORKTOP_OUTLET_ABOVE = 200 # above the finished worktop (1050 - 1100 AFFL on a 900 worktop)
    WORKTOP_OUTLET_PITCH = 1200
    BLOCKING_APPS = %w[oven dishwasher washer dryer fridge freezer microwave].freeze

    def app_kind(ap)
      ap['kind'].to_s.sub(/_(chimney|slim|builtin)\z/, '')
    end

    # base cabinet standing directly beside u on the same wall whose inside can be reached (no built-in appliance in it)
    def service_neighbour(data, u, prefer_sink = false)
      return nil unless u['wall'] && u['along']

      c = data[:units].select do |n|
        !n.equal?(u) && n['wall'] == u['wall'] && n['kind'].to_s == 'base' && n['along'] &&
          ((n['along'][0] - u['along'][1]).abs < 6 || (n['along'][1] - u['along'][0]).abs < 6) &&
          n['apps'].none? { |a| BLOCKING_APPS.include?(app_kind(a)) }
      end
      (prefer_sink && c.find { |n| n['apps'].any? { |a| app_kind(a) == 'sink' } }) || c.first
    end

    # [offset along the wall, height AFFL, note] of a proposed point that must sit in the neighbouring cabinet; inset = distance into that cabinet
    def in_neighbour(nb, u, inset)
      nb['along'][0] >= u['along'][1] - 6 ? nb['along'][0] + inset : nb['along'][1] - inset
    end

    def elec_rule(data, u, ap, off, z)
      k = app_kind(ap)
      zr = ELEC_RULE_Z[k]
      return [off, z, nil] unless zr
      return [off, zr.to_f, 'rule: hood socket on the hood centreline, 1900-2000 AFFL'] if k == 'hood'

      nb = service_neighbour(data, u, k == 'dishwasher')
      if nb
        inset = %w[hob hob_gas].include?(k) ? 270 : 150 # a hob over an oven: two sockets side by side, not on top of each other
        return [in_neighbour(nb, u, inset).round, zr.to_f, "rule: socket inside the adjacent cabinet #{nb['code']}, #{zr} AFFL (never behind the appliance)"]
      end
      return [off, FRIDGE_HIGH_Z.to_f, "rule: no adjacent base cabinet - socket above the appliance at #{FRIDGE_HIGH_Z} AFFL"] if %w[fridge freezer].include?(k)

      [off, zr.to_f, 'NO ADJACENT ACCESSIBLE CABINET: socket position needs a site decision (must not end up behind the appliance)']
    end

    def services(data)
      proj = data[:proj]
      cfg = data[:cfg]
      pts = []
      n = Hash.new(0)
      add = lambda do |kind, u, ap, label|
        w = data[:walls].find { |x| x['id'] == u['wall'] }
        next unless w

        key = { 'elec' => 'E', 'water_cold' => 'CW', 'water_hot' => 'HW', 'drain' => 'D', 'gas' => 'G', 'duct' => 'DU' }[kind]
        n[kind] += 1
        available = proj['services'].select do |s|
          s['kind'] == kind && s['wall'] == w['id'] && !pts.any? { |p| p['service_id'] == s['id'] }
        end
        conf = available.find { |s| s['device'] == u['code'] }
        conf ||= available.select { |s| s['device'].to_s.empty? && (s['off'].to_f - along_of(w, ap['center'])).abs < 700 }.min_by { |s| (s['off'].to_f - along_of(w, ap['center'])).abs }
        off = conf ? conf['off'] : along_of(w, ap['center']).round
        z = conf ? conf['z'] : ap['center'][2].to_f
        rule = nil
        if !conf && kind == 'elec'
          off, z, rule = elec_rule(data, u, ap, off, z)
        elsif !conf && WATER_Z.key?(kind) && %w[dishwasher washer].include?(app_kind(ap)) && (nb = service_neighbour(data, u, true))
          off = in_neighbour(nb, u, kind == 'drain' ? 300 : 200).round # supply and drain of the machine are taken inside the neighbouring (sink) cabinet
          rule = "rule: connection inside the adjacent cabinet #{nb['code']}"
        end
        unless conf # proposals only: water supplies sit either side of the drain at typical heights (flagged, never confirmed)
          if WATER_Z.key?(kind)
            z = WATER_Z[kind].to_f
            off += { 'water_cold' => -60, 'water_hot' => 60, 'drain' => 0 }[kind] unless rule
          end
        end
        pts << { 'id' => "#{key}#{format('%02d', n[kind])}", 'service_id' => conf && conf['id'], 'kind' => kind, 'device' => ap['dev'], 'device_kind' => ap['kind'], 'unit' => u['code'], 'wall' => w['id'], 'wall_status' => w['st'] || (w['reference_only'] ? 'INFERRED' : 'CONFIRMED'), 'off' => off, 'z' => z, 'label' => label, 'spec' => conf && conf['spec'],
                 'notes' => conf && conf['notes'], 'st' => conf ? (conf['st'] || 'CONFIRMED') : 'REQUIRES_CONFIRMATION', 'src' => conf ? "user point #{conf['id']}" : [rule, 'proposal from current modeled appliance position; verify FFL and site datum'].compact.join(' - ') }
      end
      data[:units].each do |u|
        u['apps'].each do |ap|
          k = ap['kind'].sub(/_(chimney|slim|builtin)\z/, '')
          lab = ap['dev'] || k
          add.call('elec', u, ap, lab) if %w[fridge freezer oven hob hob_gas hood microwave dishwasher washer dryer coffee wine_cooler warming warming_drawer].include?(k)
          if k == 'sink'
            %w[water_cold water_hot drain].each { |x| add.call(x, u, ap, lab) }
          elsif %w[dishwasher washer].include?(k)
            %w[water_cold drain].each { |x| add.call(x, u, ap, lab) }
          elsif k == 'hob_gas'
            add.call('gas', u, ap, lab)
          elsif k == 'hood'
            add.call('duct', u, ap, lab)
          end
        end
      end
      # worktop sockets: proposed over plain base cabinets (no sink / hob / appliance), one per WORKTOP_OUTLET_PITCH along each wall
      data[:walls].each do |w|
        last = nil
        data[:units].select { |u| u['wall'] == w['id'] && u['kind'].to_s == 'base' && u['along'] && u['apps'].empty? }.sort_by { |u| u['along'][0] }.each do |u|
          c = (u['along'][0] + u['along'][1]) / 2.0
          next if last && c - last < WORKTOP_OUTLET_PITCH

          last = c
          n['elec'] += 1
          zt = u['z0'].to_f + u['h'].to_f + WORKTOP_OUTLET_ABOVE
          pts << { 'id' => "E#{format('%02d', n['elec'])}", 'service_id' => nil, 'kind' => 'elec', 'device' => 'WORKTOP_OUTLET', 'device_kind' => 'outlet', 'unit' => u['code'], 'wall' => w['id'],
                   'wall_status' => w['st'] || (w['reference_only'] ? 'INFERRED' : 'CONFIRMED'), 'off' => c.round, 'z' => zt.round, 'label' => 'Worktop outlet', 'spec' => nil, 'notes' => nil,
                   'st' => 'REQUIRES_CONFIRMATION', 'src' => "rule: worktop socket #{WORKTOP_OUTLET_ABOVE} above the finished worktop (1050-1100 AFFL); count and positions to be confirmed with the client" }
        end
      end
      runs = LedRun.detect(data[:model])
      runs.each do |r|
        u = data[:units].find { |x| x['rec'].g.persistent_id == r['pids'].first }
        next unless u && u['wall']

        w = data[:walls].find { |x| x['id'] == u['wall'] }
        n['led'] += 1
        pts << { 'id' => "LED#{format('%02d', n['led'])}", 'kind' => 'led', 'device' => r['id'], 'device_kind' => 'led', 'unit' => u['code'], 'wall' => w['id'], 'wall_status' => w['st'] || (w['reference_only'] ? 'INFERRED' : 'CONFIRMED'), 'off' => u['along'][0].round, 'z' => (u['z0'].to_f + u['h'].to_f).round, 'label' => "#{r['id']} driver", 'spec' => nil,
                 'st' => 'REQUIRES_CONFIRMATION', 'src' => 'proposed at modeled upper unit top and run start; driver rating and FFL require confirmation' }
      end
      orphans = proj['services'].reject { |s| pts.any? { |p| p['service_id'] == s['id'] } }
      unmatched = data[:units].select { |u| !u['wall'] && !u['apps'].empty? }.map { |u| { 'unit' => u['code'], 'name' => u['name'], 'reason' => 'No matching wall/reference; service positions NOT VERIFIED' } }
      { 'points' => pts, 'orphans' => orphans, 'unmatched_devices' => unmatched }
    end

    def services_plan(data, kinds, title_en, title_ar, sheet_no, lang, st)
      sv = services(data)
      pts = sv['points'].select { |p| kinds.include?(p['kind']) }
      cv = draw_plan(data, no_chain: true, no_labels: false)
      colors = { 'elec' => '#c2410c', 'water_cold' => '#1d4ed8', 'water_hot' => '#dc2626', 'drain' => '#4b5563', 'gas' => '#a16207', 'duct' => '#6d28d9' }
      pts.each do |p|
        w = data[:walls].find { |x| x['id'] == p['wall'] }
        x, y = world_of(w, p['off'], 0)
        col = colors[p['kind']]
        cv.circle(x, y, cv.fs * 0.9, fill: p['st'] == 'CONFIRMED' ? col : '#fff', stroke: col, sw: cv.fs / 14.0)
        cv.text(x, y - cv.fs * 0.3, p['id'], size: cv.fs * 0.7, fill: p['st'] == 'CONFIRMED' ? '#fff' : col, bold: true)
      end
      rows = pts.map { |p| [p['id'], p['label'], p['unit'], "#{p['wall']}", "#{p['off'].round} mm", "#{p['z'].round} mm", SvgDraw.badge(p['st']), p['src']] }
      ar = lang == 'ar'
      tbl = SvgDraw.data_table([ar ? 'النقطة' : 'Point', ar ? 'الجهاز' : 'Device', ar ? 'الوحدة' : 'Unit', ar ? 'الحائط' : 'Wall', ar ? 'البعد من بداية الحائط' : 'Offset from wall start', ar ? 'الارتفاع من FFL' : 'Height above FFL', ar ? 'الحالة' : 'Status', ar ? 'المصدر' : 'Source'], rows)
      note = "<div class='warn'>#{ar ? 'المواضع المقترحة تحتاج تأكيد. لم يتم افتراض أي قدرة كهربائية أو قاطع أو مقاس مواسير.' : 'Proposed positions REQUIRE CONFIRMATION. No power rating, breaker, circuit or pipe size is specified here.'}</div>"
      body = "<div class='draw'>#{cv.svg}</div>#{tbl}#{note}#{reference_notes(data)}"
      SvgDraw.sheet(data[:proj], title: ar ? title_ar : title_en, sheet_no: sheet_no, scale: '1:50 (as printed)', zone: 'ALL', status: st[:status], lang: lang, extra_status: st[:doc], body: body)
    end

    # ------------------------------------------------------------------ APPLIANCE INSTALLATION / SERVICE DIMENSIONS
    def appliance_table(data, lang)
      ar = lang == 'ar'
      sv = services(data)
      rows = []
      data[:units].each do |u|
        u['apps'].each do |ap|
          dv = ap['dev'] && Catalog.device(ap['dev'])
          op = ap['opening']
          pts = sv['points'].select { |p| p['unit'] == u['code'] && p['device_kind'] == ap['kind'] }.map { |p| p['id'] }.join(', ')
          rows << [ap['dev'] || ap['kind'], ar ? (ap['dev_name_ar'] || ap['kind']) : (ap['dev_name'] || ap['kind']), u['name'], u['code'],
                   op ? (op['cutout'] ? "cutout #{op['w'].round}×#{op['d'].round}" : "#{op['w'].round}×#{op['h'].round}×#{op['d'].round}") : '-',
                   dv ? "#{dv[:w]}×#{dv[:h]}×#{dv[:d]}" : '-', pts.empty? ? '-' : pts, SvgDraw.badge(ap['dev_src'] == 'spec' ? 'CONFIRMED' : 'INFERRED')]
        end
      end
      req = data[:units].flat_map { |u| u['requires'].map { |r| [u['name'], r['item'], r['detail'], SvgDraw.badge('REQUIRES_CONFIRMATION')] } }
      s = SvgDraw.data_table([ar ? 'رقم الجهاز' : 'Appliance ID', ar ? 'الجهاز' : 'Appliance', ar ? 'البيت (الوحدة)' : 'Housing', ar ? 'كود' : 'ID', ar ? 'الفتحة (عرض×ارتفاع×عمق)' : 'Opening W×H×D', ar ? 'مقاس الجهاز الاسمي' : 'Nominal appliance W×H×D', ar ? 'نقاط الخدمة' : 'Service points', ar ? 'المصدر' : 'Device source'], rows)
      s << "<h2>#{ar ? 'خلوصات تحتاج تأكيد' : 'Clearances that REQUIRE CONFIRMATION'}</h2>" + SvgDraw.data_table([ar ? 'الوحدة' : 'Unit', ar ? 'البند' : 'Item', ar ? 'القيمة الحالية' : 'Current default', ar ? 'الحالة' : 'Status'], req) unless req.empty?
      s + reference_notes(data)
    end

    def appliance_sheet(data, lang, st)
      SvgDraw.sheet(data[:proj], title: lang == 'ar' ? 'أبعاد تركيب الأجهزة' : 'APPLIANCE INSTALLATION / SERVICE DIMENSIONS', sheet_no: '06-A', scale: 'NTS', zone: 'ALL', status: st[:status], lang: lang, extra_status: st[:doc], body: appliance_table(data, lang))
    end

    # ------------------------------------------------------------------ SECTIONS
    def unit_boxes(u)
      Validate.parts_of(u['rec']).select { |p| %w[part glass appliance].include?(p[:role]) }.map do |p|
        { part: p[:part], role: p[:role], d0: -p[:y][1], d1: -p[:y][0], x0: p[:x][0], x1: p[:x][1], z0: u['z0'] + p[:z][0], z1: u['z0'] + p[:z][1], mat: p[:mat] }
      end
    end

    # side section through the middle of a column (one or several stacked units): cut boards hatched, the rest as outline
    def section_canvas(units, cfg, title_units = nil)
      boxes = units.flat_map { |u| unit_boxes(u).map { |b| b.merge(unit: u) } }
      maxd = boxes.map { |b| b[:d1] }.max + 250
      maxz = boxes.map { |b| b[:z1] }.max + 200
      cv = SvgDraw::Canvas.new(0, 0, maxd, maxz, pad: 700)
      cv.line(0, 0, 0, maxz, stroke: '#000', sw: cv.fs / 8.0) # the wall
      cv.text(-cv.fs * 0.5, maxz, 'WALL', size: cv.fs * 0.6, anchor: 'end')
      cv.line(-200, 0, maxd, 0, stroke: '#000', sw: cv.fs / 10.0)
      units.each do |u|
        mid = u['w'] / 2.0
        bs = boxes.select { |b| b[:unit].equal?(u) }
        bs.each do |b|
          cut = b[:x0] <= mid && b[:x1] >= mid
          next if !cut && !%w[side_l side_r].include?(b[:part])

          if cut
            fill = { 'front' => '#c9a06a', 'carcass' => '#e9e5d6', 'back' => '#d8d2be', 'drawer' => '#efece2', 'appliance' => '#5b5f66', 'top' => '#222' }[b[:mat]] || '#ddd'
            cv.rect(b[:d0], b[:z0], b[:d1], b[:z1], fill: fill, stroke: '#111', sw: cv.fs / 18.0)
          else
            cv.rect(b[:d0], b[:z0], b[:d1], b[:z1], fill: 'none', stroke: '#aaa', dash: "#{cv.fs / 3} #{cv.fs / 4}", sw: cv.fs / 40.0)
          end
        end
        if u['led']
          l = u['led']
          bot = bs.find { |b| b[:part] == 'bottom' }
          if bot
            cv.rect(l['off'], bot[:z0], l['off'] + l['lw'], bot[:z0] + l['ld'], fill: '#f5c542', stroke: '#8a5a00', sw: cv.fs / 30.0)
            cv.text(l['off'] + l['lw'] / 2.0, bot[:z0] - cv.fs * 1.4, "LED groove #{l['off'].round} / #{l['lw'].round}×#{l['ld'].round}", size: cv.fs * 0.6, fill: '#8a5a00', bold: true)
          end
        end
        d = u['d']
        cv.dim(0, u['z0'] + u['h'], d, u['z0'] + u['h'], cv.fs * 1.5, "#{d.round} (#{u['code']})")
        cv.dim(-350 - (units.index(u) % 2) * 260, u['z0'], -350 - (units.index(u) % 2) * 260, u['z0'] + u['h'], 1, "#{u['h'].round}") if false
      end
      lv = LEVELS.select { |z| z <= maxz }
      lv.each_cons(2) { |a, b| cv.dim(0, a, 0, b, cv.fs * 3.5, (b - a).round.to_s) }
      cv
    end

    def sections(data, lang, st)
      cfg = data[:cfg]
      ar = lang == 'ar'
      sheets = []
      us = data[:units]
      # 1. tier stack (base + Upper 1 + Upper 2) of the first full column
      lc = ->(u) { Cabinet.legacy_code(u['name'].to_s) } # column membership comes from the builder name (run + position), not from the B / W / T unit ID
      col = us.select { |u| u['kind'] == 'base' && lc.call(u) =~ /^[A-Z]\d+$/ && us.any? { |o| lc.call(o) == "#{lc.call(u)}W1" } }.max_by { |u| u['w'] }
      if col
        stack = us.select { |u| lc.call(u) =~ /^#{lc.call(col)}(W\d)?$/ }.sort_by { |u| u['z0'] }
        cv = section_canvas(stack, cfg)
        sheets << ["#{ar ? 'قطاع رأسي: قاعدة + علوي 1 + علوي 2' : 'Vertical section: base + Upper 1 + Upper 2'} (#{col['code']})", cv.svg]
      end
      # 2. one representative per special family
      { 'fridge_open' => ['بيت الثلاجة المفتوح', 'Refrigerator open housing'], 'hob_oven' => ['بوتجاز + فرن', 'Hob + oven cabinet'], 'sink' => ['وحدة الحوض', 'Sink unit'], 'corner_l' => ['وحدة الركنة', 'Corner unit'] }.each do |type, (na, ne)|
        u = us.find { |x| x['type'] == type }
        next unless u

        group = [u] + us.select { |o| o["code"] == "#{u["code"]}over" || o["name"] == "#{u["name"]}_over" }
        sheets << ["#{ar ? na : ne} (#{u['code']})", section_canvas(group, cfg).svg]
      end
      # 3. LED groove details (measured from the units)
      us.select { |u| u['led'] }.group_by { |u| u['led']['off'] }.each do |off, list|
        u = list.first
        l = u['led']
        cv = SvgDraw::Canvas.new(0, 0, off + 120, 30, pad: 25)
        cv.rect(0, 0, off + 120, 18, fill: '#e9e5d6', stroke: '#111')
        cv.rect(off, 0, off + l['lw'], l['ld'], fill: '#fff', stroke: '#8a5a00')
        cv.dim(0, 0, off, 0, -8, "#{off.round} from the back")
        cv.dim(off, 0, off + l['lw'], 0, -18, "#{l['lw'].round}")
        cv.dim(off + l['lw'] + 8, 0, off + l['lw'] + 8, l['ld'], 8, "#{l['ld'].round}")
        cv.dim(off + 100, 0, off + 100, 18, 12, '18')
        sheets << ["#{ar ? 'تفصيل مجرى LED (الأرضية)' : 'LED groove detail (bottom panel)'} — #{list.map { |x| x['code'] }.first(4).join(', ')}#{list.size > 4 ? ' ...' : ''}", cv.svg]
      end
      out = sheets.each_with_index.map { |(t, svg), i| SvgDraw.sheet(data[:proj], title: t, sheet_no: format('06-S%02d', i + 1), scale: 'as printed', zone: 'SECTION', status: st[:status], lang: lang, extra_status: st[:doc], body: "<div class='draw'>#{svg}</div>") }
      out
    end

    # ------------------------------------------------------------------ WORKTOP PLAN
    def worktop(data, lang, st)
      ar = lang == 'ar'
      cfg = data[:cfg]
      parts = each_part(data[:model], ['countertop'], data[:walls])
      proj = data[:proj]
      poly = proj['room']['poly']
      xs = poly.map(&:first)
      ys = poly.map(&:last)
      if poly.empty?
        points = data[:units].flat_map { |u| u['fp'] } + data[:walls].flat_map { |w| [w['p0'], w['p1']] }
        raise 'No units available for worktop drawing' if points.empty?
        xs = points.map(&:first)
        ys = points.map(&:last)
      end
      cv = SvgDraw::Canvas.new(xs.min, ys.min, xs.max, ys.max, pad: 900)
      cv.poly(poly, fill: '#fbfaf5', stroke: '#555') unless poly.empty?
      rows = []
      parts.each do |p|
        base = p[:pts].select { |q| (q.z.to_mm - p[:z][0]).abs < 0.5 }
        quad = base.map { |q| [q.x.to_mm, q.y.to_mm] }
        cx = EGC::Num.sum(quad, &:first) / 4.0
        cy = EGC::Num.sum(quad, &:last) / 4.0
        quad = quad.sort_by { |x, y| Math.atan2(y - cy, x - cx) }
        cv.poly(quad, fill: '#3a3a3d', stroke: '#111')
        rows << [p[:d]['pid'], "#{p[:d]['len']} × #{p[:d]['wid']} × #{p[:d]['thk']}", cfg['mat_names']['top'], "L×#{p[:d]['eb_l']} W×#{p[:d]['eb_w']}", p[:d]['notes'].to_s, p[:wall] || '-']
        cv.text(cx, cy, p[:d]['pid'].to_s, size: cv.fs * 0.7, fill: '#fff', bold: true)
      end
      cut = []
      data[:units].each do |u|
        u['apps'].each do |ap|
          op = ap['opening']
          next unless op && op['cutout']

          # the cutout as it is in the slab: recomputed from the unit frame with the same rule the slab was cut with
          kind = ap['kind'] == 'sink' ? :sink : :hob
          r = Kitchen.cutout_rect(kind, 0, u['w'], cfg)
          pts = [[r[0], -(r[1])], [r[0] + r[2], -(r[1])], [r[0] + r[2], -(r[1] + r[3])], [r[0], -(r[1] + r[3])]].map do |x, y|
            c = u['rec'].tr * Geom::Point3d.new(x.mm, y.mm, 900.mm)
            [c.x.to_mm, c.y.to_mm]
          end
          cv.poly(pts, fill: '#fbfaf5', stroke: '#b42318', dash: "#{cv.fs / 3} #{cv.fs / 4}", sw: cv.fs / 20.0)
          cx = EGC::Num.sum(pts, &:first) / 4.0
          cy = EGC::Num.sum(pts, &:last) / 4.0
          cv.text(cx, cy, "#{ap['kind'].upcase} #{r[2].round}×#{r[3].round}", size: cv.fs * 0.6, fill: '#b42318', bold: true)
          cut << [u['code'], ap['kind'], ap['dev'], "#{r[2].round}×#{r[3].round}", "#{r[0].round} from the unit's left edge, #{r[1].round} from the wall", SvgDraw.badge(ap['dev_src'] == 'spec' ? 'CONFIRMED' : 'INFERRED')]
        end
      end
      tbl = SvgDraw.data_table([ar ? 'رقم القطعة' : 'Piece', ar ? 'الطول × العمق × السمك' : 'Length × depth × thickness', ar ? 'الخامة' : 'Material', ar ? 'حواف' : 'Edges', ar ? 'ملاحظات / قطع' : 'Notes / cutouts', ar ? 'الحائط' : 'Wall'], rows)
      ctbl = SvgDraw.data_table([ar ? 'الوحدة' : 'Unit', ar ? 'النوع' : 'Kind', ar ? 'الجهاز' : 'Device', ar ? 'مقاس الفتحة' : 'Cutout W×D', ar ? 'الموضع' : 'Position', ar ? 'المصدر' : 'Device source'], cut)
      SvgDraw.sheet(proj, title: ar ? 'مسقط سطح العمل (الرخام)' : 'WORKTOP PLAN', sheet_no: '05', scale: '1:50 (as printed)', zone: 'ALL', status: st[:status], lang: lang, extra_status: st[:doc],
                    body: "<div class='draw'>#{cv.svg}</div>#{tbl}<h2>#{ar ? 'فتحات (Cutouts)' : 'Cutouts'}</h2>#{ctbl}")
    end

    # ------------------------------------------------------------------ INSTALLATION PLAN + NOTES
    def installation(data, lang, st)
      ar = lang == 'ar'
      cv = draw_plan(data)
      cfg = data[:cfg]
      runs = used_walls(data).map do |w|
        us = data[:units].select { |u| u['wall'] == w['id'] && u['kind'] != 'wall' && u['kind'] != 'hood' }.sort_by { |u| u['along'][0] }
        next if us.empty?

        [w['id'], us.first['along'][0].round, us.last['along'][1].round, (us.last['along'][1] - us.first['along'][0]).round, us.size]
      end.compact
      fillers = each_part(data[:model], ['filler'], data[:walls]).map { |p| [p[:d]['pid'], "#{p[:d]['len']} × #{p[:d]['wid']} × #{p[:d]['thk']}", p[:wall] || '-', p[:along] ? "#{p[:along][0].round}–#{p[:along][1].round}" : '-'] }
      lv = [['FFL', 0], ['Plinth top', cfg['plinth']], ['Base carcass top', cfg['base_h'].to_f - cfg['top_thk'].to_f], ['Worktop top', cfg['base_h']], ['Upper 1 bottom', cfg['base_h'].to_f + cfg['gap_h'].to_f],
            ['Upper 2 bottom', cfg['base_h'].to_f + cfg['gap_h'].to_f + cfg['w1_h'].to_f], ['Top fascia bottom', Config.top_line(cfg)], ['Ceiling', data[:proj]['room']['ceiling']['v'] || cfg['ceiling']]]
      sv = services(data)
      body = "<div class='draw'>#{cv.svg}</div>#{legend(lang)}#{reference_notes(data)}"
      body << "<h2>#{ar ? 'الأضلاع (المسافات من بداية الحائط)' : 'Runs (distances from the wall start)'}</h2>" + SvgDraw.data_table([ar ? 'الحائط' : 'Wall', ar ? 'البداية' : 'Start', ar ? 'النهاية' : 'End', ar ? 'الطول' : 'Length', ar ? 'عدد الوحدات' : 'Base/tall units'], runs)
      body << "<h2>#{ar ? 'الحشوات' : 'Fillers'}</h2>" + SvgDraw.data_table([ar ? 'رقم' : 'ID', ar ? 'المقاس' : 'Size', ar ? 'الحائط' : 'Wall', ar ? 'من–إلى' : 'from–to'], fillers)
      body << "<h2>#{ar ? 'المناسيب' : 'Levels'}</h2>" + SvgDraw.data_table([ar ? 'المنسوب' : 'Level', 'mm (FFL)'], lv.map { |a, b| [a, b.to_f.round] })
      body << "<h2>#{ar ? 'نقاط الخدمة (مقترحة / مؤكدة)' : 'Service points (proposed / confirmed)'}</h2>" + SvgDraw.data_table(%w[ID Device Wall Offset Height Status], sv['points'].map { |p| [p['id'], p['label'], p['wall'], "#{p['off'].round}", "#{p['z'].round}", SvgDraw.badge(p['st'])] })
      SvgDraw.sheet(data[:proj], title: ar ? 'مخطط التركيب' : 'INSTALLATION PLAN', sheet_no: '06-I', scale: '1:50 (as printed)', zone: 'ALL', status: st[:status], lang: lang, extra_status: st[:doc], body: body)
    end

    def notes(data, unresolved, lang, st)
      ar = lang == 'ar'
      items = []
      items << (ar ? 'تأكيد جميع نقاط الخدمة (كهرباء، مياه، صرف، غاز، شفاط) قبل تسليم الخشب.' : 'Confirm every service point (electrical, water, drain, gas, hood duct) before the cabinets are delivered.')
      items << (ar ? 'التحقق من استواء الأرضية وارتفاع السقف الفعلي قبل التركيب.' : 'Check the floor level and the real ceiling height on site before installation.')
      items << (ar ? 'المناسيب من الأرضية النهائية FFL: قاعدة 100 · سطح العمل 900 · وحدات علوية 1500 / 2200 · وزرة 2700–2800.' : 'Levels above the finished floor: plinth 100 · worktop 900 · Upper 1 at 1500 · Upper 2 at 2200 · top fascia 2700–2800.')
      items << (ar ? 'وحدات LED: مجرى 10×10 مم داخل ألواح الأرضية (علوي 1 عند 35 مم، علوي 2 عند 450 مم من الخلف)، مسار متصل بين الوحدات المتجاورة.' : 'LED: 10×10 mm groove in the bottom panels (Upper 1 at 35 mm, Upper 2 at 450 mm from the back), continuous across adjacent units.')
      items << (ar ? 'الأجهزة تُورَّد بمقاساتها الاسمية الموضحة؛ أي جهاز مختلف يستلزم إعادة التحقق من فتحته.' : 'Appliances are supplied at the nominal sizes shown; a different model needs its opening re-checked.')
      list = items.map { |x| "<li>#{H.h(x)}</li>" }.join
      un = unresolved.map { |u| "<li><span class='st REQUIRES_CONFIRMATION'>REQUIRES_CONFIRMATION</span> #{H.h(u)}</li>" }.join
      body = "<h2>#{ar ? 'ملاحظات تجهيز الموقع' : 'Site preparation notes'}</h2><ol>#{list}</ol><h2>#{ar ? 'بنود تحتاج تأكيد' : 'Open items (REQUIRES CONFIRMATION)'}</h2><ul>#{un.empty? ? '<li>-</li>' : un}</ul>"
      SvgDraw.sheet(data[:proj], title: ar ? 'ملاحظات التركيب' : 'INSTALLATION NOTES', sheet_no: '11', scale: 'NTS', zone: 'ALL', status: st[:status], lang: lang, extra_status: st[:doc], body: body)
    end
  end
end
