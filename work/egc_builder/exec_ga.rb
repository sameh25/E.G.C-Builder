# frozen_string_literal: true

require 'json'

module EGC
  # Factory set assembly: general arrangement, unit identification, cover/index, schedules and the complete ordered set.
  module ExecFactory
    module_function

    KIND_FILL = { 'base' => '#efe3c6', 'wall' => '#e4e1d5', 'tall' => '#e9e0cc', 'hood' => '#e4e1d5' }.freeze

    # elevation of every wall run. identify: true = large unit IDs only (F-02)
    def ga_sheets(data, lang, proj, no, identify: false)
      walls = SiteDocs.used_walls(data)
      walls = [{ 'id' => 'R1', 'len' => data[:units].map { |u| (u['along'] || [0, 0])[1] }.max.to_f }] if walls.empty?
      title = ED.t(lang, identify ? 'ids' : 'ga')
      walls.each_with_index.flat_map do |wall, wi|
        units = data[:units].select { |u| u['wall'] == wall['id'] && u['along'] }
        next [] if units.empty?

        id = walls.size > 1 ? "#{no}-#{wall['id']}" : no
        sh = ED::Sheet.new(proj, lang: lang, no: id, title: "#{title} - #{wall['id']}", zone: wall['id'].to_s)
        ax0, ay0, ax1, ay1 = sh.area
        run0 = units.map { |u| u['along'][0] }.min
        run1 = units.map { |u| u['along'][1] }.max
        ceiling = [(data[:proj].dig('room', 'ceiling', 'v') || data[:cfg]['ceiling']).to_f, units.map { |u| u['z0'] + u['h'] }.max].max
        len = run1 - run0
        mL = 36.0
        mR = 30.0
        mT = 20.0
        mB = 38.0
        n = ED.pick_scale(len, ceiling, ax1 - ax0 - mL - mR, ay1 - ay0 - mT - mB)
        k = 1.0 / n
        ox = ax0 + mL + ((ax1 - ax0 - mL - mR) - len * k) / 2.0
        oy = ay0 + mT + ceiling * k + 2
        sh.instance_variable_set(:@scale, ED.scale_label(n))
        mp = ED::Map.new(ox - run0 * k, oy, k, :elev)
        mpx = lambda do |a|
          sh.rtl ? ox + len * k - (a - run0) * k : ox + (a - run0) * k
        end
        rx = ->(a0, a1) { [mpx.call([a0, a1].send(sh.rtl ? :max : :min)), (a1 - a0).abs * k] }
        # ceiling + floor lines
        sh.line(ax0 + 8, mp.y(0), ax1 - 8, mp.y(0), w: 0.5)
        sh.line(ox - 2, mp.y(ceiling), ox + len * k + 2, mp.y(ceiling), w: 0.2, dash: '3 1.5', color: '#666')
        sh.text(sh.rtl ? ax1 - 10 : ax0 + 10, mp.y(0) + 4.5, "#{ED.t(lang, 'ffl')} +0.00", size: 2.8, anchor: :left, bold: true)
        sh.text(ox + len * k + 3, mp.y(ceiling) + 1, "#{ED.fmt(ceiling)}", size: 2.5, anchor: :pleft, color: '#666', ltr: true)
        tops = []
        units.sort_by { |u| [u['kind'] == 'base' ? 0 : 1, u['along'][0]] }.each do |u|
          x, wd = rx.call(*u['along'])
          y = mp.y(u['z0'] + u['h'])
          ht = u['h'] * k
          sh.rect(x, y, wd, ht, fill: identify ? (KIND_FILL[u['kind'].to_s] || '#eee') : '#ffffff', stroke: '#222', sw: 0.28)
          real = !identify && unit_fronts(sh, u, wall, mpx, mp, k) # the elevation as it is BUILT: every door, drawer front, handle, plinth
          if u['kind'] == 'base'
            tt = (data[:cfg]['top_thk'] || 20).to_f
            sh.rect(x, y, wd, tt * k, fill: '#aeb2b8', stroke: '#222', sw: 0.2)
          end
          u['apps'].each do |ap|
            next unless ap['z']

            cx = ap['center'] ? SiteDocs.along_of((wall['p0'] ? wall : { 'p0' => [0, 0], 'dir' => [1, 0] }), ap['center']) : (u['along'][0] + u['along'][1]) / 2.0
            aw = ((ap['opening'] || {})['w'] || [u['w'] - 40, 0].max).to_f
            ax = mpx.call(sh.rtl ? cx + aw / 2.0 : cx - aw / 2.0)
            z1 = %w[sink hob hob_gas].include?(ap['kind'].to_s) ? [ap['z'][1], u['z0'] + u['h']].min : ap['z'][1]
            sh.rect(ax, mp.y(z1), aw * k, (z1 - ap['z'][0]) * k, fill: '#d9dee4', stroke: '#555', sw: 0.2, dash: '1.2 0.8', op: 0.7)
            appliance_face(sh, ap['kind'].to_s, ax, mp.y(z1), aw * k, (z1 - ap['z'][0]) * k) if real
          end
          cx = x + wd / 2.0
          cy = y + ht / 2.0
          if identify
            fs = 6.0
            fs -= 0.2 while fs > 2.0 && ED.tw(u['code'].to_s, fs) > wd - 3.5
            if ED.tw(u['code'].to_s, fs) > wd - 3.5 # still too wide: run the id along the unit
              sh.text(cx + fs * 0.35, cy, u['code'].to_s, size: fs, anchor: :center, bold: true, rot: 90)
            else
              sh.text(cx, cy + fs * 0.35, u['code'].to_s, size: fs, anchor: :center, bold: true)
            end
          elsif real # the fronts are drawn: only the unit ID, small, on a white tag (sizes are on the dimension chains and the unit sheets)
            fs = 2.6
            fs -= 0.1 while fs > 1.5 && ED.tw(u['code'].to_s, fs) > wd - 1.6
            tw = ED.tw(u['code'].to_s, fs) + 2.0
            sh.rect(cx - tw / 2.0, cy - fs * 0.75, tw, fs * 1.3, fill: '#ffffff', stroke: '#b0b0b0', sw: 0.12, op: 0.85)
            sh.text(cx, cy + fs * 0.25, u['code'].to_s, size: fs, anchor: :center, bold: true)
          else
            fs = 3.4
            fs -= 0.1 while fs > 1.5 && ED.tw(u['code'].to_s, fs) > wd - 1.2
            sh.text(cx, cy - 2.4, u['code'].to_s, size: fs, anchor: :center, bold: true)
            dims_txt = "#{ED.fmt(u['w'])}x#{ED.fmt(u['h'])}x#{ED.fmt(u['d'])}"
            ts = 2.1
            ts -= 0.1 while ts > 1.5 && ED.tw(dims_txt, ts) > wd - 1.2 # shrink to fit, never cut an id or a dimension
            sh.text(cx, cy + 0.6, u['type'].to_s, size: ts, anchor: :center, color: '#444') if ED.tw(u['type'].to_s, ts) <= wd - 1.2
            sh.text(cx, cy + 3.6, dims_txt, size: ts, anchor: :center, color: '#444')
          end
          tops << u
        end
        # worktop run dimensions (base row widths), upper row widths on top, overall on the outermost line
        yb = mp.y(0)
        a_edges = ->(arr) { EV.edges(arr.flat_map { |u| u['along'] }) }
        base = units.select { |u| u['kind'] == 'base' && u['z0'].to_f < 200 }
        be = a_edges.call(base)
        be.each_cons(2) { |a, b| sh.dim_h(mpx.call(sh.rtl ? b : a), mpx.call(sh.rtl ? a : b), yb + 9, ED.fmt(b - a), from_y: yb + 0.5) if (b - a) * k > 5.5 }
        sh.dim_h(mpx.call(sh.rtl ? run1 : run0), mpx.call(sh.rtl ? run0 : run1), yb + 18, ED.fmt(len), from_y: yb + 0.5)
        uppers = units.select { |u| u['kind'] == 'wall' && u['tier'].to_i == 1 }
        ue = a_edges.call(uppers)
        ytop = mp.y(ceiling) - 8
        ue.each_cons(2) { |a, b| sh.dim_h(mpx.call(sh.rtl ? b : a), mpx.call(sh.rtl ? a : b), ytop, ED.fmt(b - a), from_y: mp.y(units.select { |u| u['kind'] == 'wall' }.map { |u| u['z0'] + u['h'] }.max || ceiling) - 0.5) if (b - a) * k > 5.5 }
        # levels chain (left): distinct unit z edges
        ze = EV.edges(units.flat_map { |u| [u['z0'], u['z0'] + u['h']] } + [0, ceiling])
        lx = sh.rtl ? ox + len * k + 14 : ox - 14
        ze.each_cons(2) { |a, b| sh.dim_v(mp.y(b), mp.y(a), lx, ED.fmt(b - a), from_x: sh.rtl ? ox + len * k + 0.5 : ox - 0.5, side: sh.rtl ? :right : :left) if (b - a) * k > 3.4 }
        sh.dim_v(mp.y(ceiling), mp.y(0), sh.rtl ? ox + len * k + 24 : ox - 24, ED.fmt(ceiling), from_x: sh.rtl ? ox + len * k + 0.5 : ox - 0.5, side: sh.rtl ? :right : :left)
        ga_plan(sh, units, wall, data, mpx, k, mp.y(0) + 28, run0, run1, lang, identify) unless identify
        legend(sh, lang, ax0, ay1, identify)
        sh
      end
    end

    FRONT_PARTS = %w[door drawer_front flap filler trim sliding_door fascia].freeze
    FRONT_HW = %w[handle profile gola_profile].freeze

    # The real fronts of one unit, seen from the room, on the elevation: fronts and glass, then handles / grip profiles, the plinth.
    # Read from the built parts (so it is whatever the unit really has); -> true when something was drawn.
    def unit_fronts(sh, u, wall, mpx, mp, k)
      rec = u['rec']
      return false unless rec && rec.respond_to?(:g) && u['along']

      ps = Validate.parts_of(rec)
      dir = wall['dir'] || [1, 0]
      xa = rec.tr.xaxis
      same = (xa.x * dir[0] + xa.y * dir[1]) >= 0
      box = lambda do |p, fill, stroke, sw|
        a0, a1 = (same ? [u['along'][0] + p[:x][0], u['along'][0] + p[:x][1]] : [u['along'][1] - p[:x][1], u['along'][1] - p[:x][0]])
        next if a1 - a0 < 1 || p[:z][1] - p[:z][0] < 1

        sh.rect(mpx.call(sh.rtl ? a1 : a0), mp.y(u['z0'] + p[:z][1]), (a1 - a0) * k, (p[:z][1] - p[:z][0]) * k, fill: fill, stroke: stroke, sw: sw)
      end
      fronts = ps.select { |p| (p[:role] == 'part' && FRONT_PARTS.include?(p[:part])) || p[:role] == 'glass' }
      return false if fronts.empty? && ps.none? { |p| p[:part] == 'plinth' }

      ps.each { |p| box.call(p, '#26282c', '#111', 0.15) if p[:part] == 'plinth' }
      fronts.each { |p| box.call(p, p[:role] == 'glass' ? '#dcebf2' : '#fbf7ee', '#222', 0.22) }
      front_y = fronts.map { |p| p[:y][0] }.min # the front plane (local y is negative towards the room)
      ps.each { |p| box.call(p, '#2f3237', '#111', 0.1) if p[:role] == 'hw' && FRONT_HW.include?(p[:part]) && (front_y.nil? || p[:y][0] <= front_y + 60) }
      true
    rescue StandardError
      false
    end

    # a few lines that say what the appliance is (not a drawing of a product)
    def appliance_face(sh, kind, x, y, w, h)
      case kind
      when 'oven', 'microwave', 'coffee'
        sh.rect(x + w * 0.1, y + h * 0.3, w * 0.8, h * 0.56, fill: '#30343a', stroke: '#111', sw: 0.15)
        sh.line(x + w * 0.12, y + h * 0.22, x + w * 0.88, y + h * 0.22, w: 0.4)
        sh.circle(x + w * 0.85, y + h * 0.1, [w, h].min * 0.04, fill: '#30343a')
      when 'dishwasher', 'washer', 'dryer'
        sh.line(x, y + h * 0.14, x + w, y + h * 0.14, w: 0.2)
        sh.circle(x + w / 2.0, y + h * 0.58, [w, h].min * 0.3, fill: '#eef1f4', stroke: '#333', sw: 0.2) unless kind == 'dishwasher'
      when 'fridge', 'freezer'
        sh.line(x, y + h * 0.3, x + w, y + h * 0.3, w: 0.25)
        sh.line(x + w * 0.1, y + h * 0.18, x + w * 0.1, y + h * 0.27, w: 0.5)
        sh.line(x + w * 0.1, y + h * 0.34, x + w * 0.1, y + h * 0.5, w: 0.5)
      end
    rescue StandardError
      nil
    end

    # plan of the run below the elevation (same scale): footprints in the wall frame, base solid / wall units dashed
    def ga_plan(sh, units, _wall, data, mpx, k, y0, run0, run1, lang, _identify)
      deep = units.map { |u| (u['out'] || [0, u['d']])[1] }.max.to_f
      return if y0 + deep * k + 14 > sh.area[3] - 6

      sh.text(sh.rtl ? sh.area[2] - 4 : sh.area[0] + 4, y0 - 3, lang == 'ar' ? 'المسقط الأفقي' : 'PLAN', size: 3.4, bold: true, anchor: :left)
      units.sort_by { |u| u['kind'] == 'base' ? 0 : 1 }.each do |u|
        a0, a1 = u['along']
        d0, d1 = u['out'] || [0, u['d']]
        next if u['kind'] == 'tall' && u['code'].to_s.end_with?('U') && units.any? { |q| q['code'] == u['code'].to_s.sub(/Uz/, 'L') } # same plan footprint as its lower module
        x = mpx.call(sh.rtl ? a1 : a0)
        w = (a1 - a0) * k
        if u['kind'] == 'base' || u['kind'] == 'tall'
          sh.rect(x, y0 + d0 * k, w, (d1 - d0) * k, fill: KIND_FILL[u['kind'].to_s], stroke: '#222', sw: 0.25)
          sh.text(x + w / 2.0, y0 + (d0 + d1) / 2.0 * k + 1, (u['code'].to_s.sub(/[LU]\z/, '') if true).to_s, size: [[w / [u['code'].to_s.length, 1].max * 1.2, 2.6].min, 1.6].max, anchor: :center) if w > 5 && !u['code'].to_s.end_with?('U')
        elsif u['tier'].to_i == 1
          sh.rect(x, y0 + d0 * k, w, (d1 - d0) * k, fill: 'none', stroke: '#555', sw: 0.18, dash: '1.4 0.9')
        end
      end
      xr = mpx.call(sh.rtl ? run0 : run1)
      base = units.select { |u| u['kind'] == 'base' }
      bd = base.map { |u| (u['out'] || [0, u['d']])[1] }.max
      sh.dim_v(y0, y0 + bd * k, xr + 6, ED.fmt(bd), from_x: xr + 0.5, side: :right) if bd
      wl = units.select { |u| u['kind'] == 'wall' && u['tier'].to_i == 1 }
      wd = wl.map { |u| (u['out'] || [0, u['d']])[1] }.max
      sh.dim_v(y0, y0 + wd * k, xr + 14, ED.fmt(wd), from_x: xr + 0.5, side: :right) if wd && wd != bd
      _ = data
    end

    def legend(sh, lang, ax0, ay1, identify)
      x = sh.rtl ? sh.area[2] - 2 : ax0 + 2
      y = ay1 - 8
      sh.text(x, y, ED.t(lang, identify ? 'unit_ids' : 'inferred_note'), size: 2.6, anchor: :left, color: '#444')
    end

    # ------------------------------------------------------------------------------------------------------------ schedules
    def schedule_sheets(an, data, groups, cfg, lang, proj)
      t = ->(k) { ED.t(lang, k) }
      out = []
      names = cfg['mat_names'] || {}
      tk = Costing.takeoff(an, cfg, lang)
      rows = tk['boards'].map { |b| [b['material'], b['thk'], b['sheet'].join(' x '), b['sheets'], b['net_m2'], b['gross_m2'], "#{b['waste_pct']}%", b['oversize'].to_a.empty? ? '-' : b['oversize'].join(',')] }
      tk['sheet_goods'].each { |gd| rows << [gd['material'], gd['thk'], gd['category'], gd['pieces'], gd['net_m2'], '', '', ''] }
      tk['edge'].each { |e| rows << ["#{t.call('edge')} PVC", e['thk'], '', '', "#{e['meters']} m", '', '', ''] }
      plinth_m = an[:hw].fetch('plinth_m', 0).to_f
      rows << [t.call('plinth_note'), '', '3000 mm', (plinth_m * 1000 / 3000.0).ceil, "#{plinth_m.round(2)} m", '', '', ''] if plinth_m.positive?
      out.concat(ED.table_sheets(proj, lang, 'F-04', lang == 'ar' ? 'جدول الخامات' : 'MATERIAL SCHEDULE', [t.call('material'), t.call('thk'), lang == 'ar' ? 'اللوح' : 'Sheet', lang == 'ar' ? 'عدد الألواح' : 'Sheets', 'm2', 'm2 gross', 'Waste', 'Oversize'], rows, [118, 20, 50, 28, 34, 36, 28, 82], per_page: 30))
      parts = (an[:raw] || []).sort_by { |p| [p[:code].to_s, p[:pid].to_s] }
      out.concat(ED.table_sheets(proj, lang, 'F-05', lang == 'ar' ? 'قائمة القطع' : 'CUT LIST', [t.call('pid'), t.call('unit'), t.call('part'), t.call('material'), t.call('thk'), t.call('length'), 'W', t.call('edge'), t.call('notes_col')],
                                 parts.map { |p| [p[:pid], p[:code], I18n.part(p[:part], lang), names[p[:mat]] || p[:mat], p[:thk], p[:len], p[:wid], "#{p[:eb_l]}L/#{p[:eb_w]}W", [p[:groove], p[:notes]].compact.join(' ')] },
                                 [40, 30, 36, 48, 14, 22, 22, 24, 156], per_page: 36))
      eb = parts.select { |p| p[:eb_l].to_i.positive? || p[:eb_w].to_i.positive? }
      out.concat(ED.table_sheets(proj, lang, 'F-06', lang == 'ar' ? 'جدول شريط الحواف' : 'EDGE BAND SCHEDULE', [t.call('pid'), t.call('unit'), t.call('material'), 'mm', 'L', 'W'],
                                 eb.map { |p| [p[:pid], p[:code], names[p[:mat]] || p[:mat], p[:eb_t], p[:eb_l], p[:eb_w]] }, [40, 30, 140, 40, 70, 76], per_page: 36))
      hw = an[:hw].select { |kk, v| v.to_f.positive? && kk.to_s != 'plinth_m' }.map { |kk, v| [kk, v.round(1), kk.to_s =~ /hinge|slide|lift/ ? t.call('req_hinge').split(' - ').first : 'GENERIC'] }
      hw << [t.call('plinth_note'), "#{(plinth_m * 1000 / 3000.0).ceil} x 3000 mm", 'PURCHASED'] if plinth_m.positive?
      out.concat(ED.table_sheets(proj, lang, 'F-07', lang == 'ar' ? 'جدول الإكسسوارات' : 'HARDWARE SCHEDULE', [t.call('item'), t.call('quantity'), t.call('data_status')], hw, [160, 80, 156], per_page: 36))
      mech = groups.filter_map do |g|
        id = g.get_attribute('egc', 'mech')
        next unless id

        [g.get_attribute('egc', 'code'), id, Mechanisms.verification(id), 1, t.call('req_mech').split(' - ').first]
      end
      out.concat(ED.table_sheets(proj, lang, 'F-08', lang == 'ar' ? 'جدول الميكانيزمات' : 'MECHANISM SCHEDULE', [t.call('unit'), t.call('mechanism'), t.call('verification'), t.call('qty'), t.call('data_status')], mech, [40, 100, 100, 30, 126], per_page: 36))
      apps = data[:units].flat_map do |u|
        u['apps'].map do |a|
          op = a['opening'] || {}
          [u['code'], a['dev'] || a['kind'], a['kind'], [op['w'], op['h'], op['d']].compact.join(' x '), (a['profile'] || {})['data_status'] || 'REQUIRES CONFIRMATION']
        end
      end
      out.concat(ED.table_sheets(proj, lang, 'F-09', lang == 'ar' ? 'جدول الأجهزة' : 'APPLIANCE SCHEDULE', [t.call('unit'), t.call('appliance'), t.call('type'), t.call('opening'), t.call('data_status')], apps, [30, 70, 50, 100, 146], per_page: 36))
      top = parts.select { |p| p[:mat] == 'top' }.map { |p| [p[:pid], p[:code], p[:len], p[:wid], p[:thk], p[:notes]] }
      out.concat(ED.table_sheets(proj, lang, 'F-10-T', lang == 'ar' ? 'الرخام والفتحات' : 'WORKTOP AND CUTOUT SCHEDULE', [t.call('pid'), t.call('unit'), t.call('length'), 'W', t.call('thk'), t.call('notes_col')], top, [40, 30, 36, 36, 20, 234], per_page: 36))
      out
    end

    # groove / drilling summary sheet (human readable; machine files stay in Production_Data)
    def groove_sheet(an, cfg, lang, proj, groups)
      t = ->(k) { ED.t(lang, k) }
      rows = (an[:raw] || []).filter_map do |p|
        g = p[:back_groove]
        next unless g

        gd = (JSON.parse(g.to_s) rescue {})
        [p[:pid], p[:code], p[:part], gd['reference'], gd['offset'], gd['depth'], gd['width'], gd['status']]
      end
      conf = []
      groups.each do |gr|
        Drawings.drilling_rows(Drawings.boxes(gr.entities.to_a)).each { |r| conf << [gr.get_attribute('egc', 'code'), *r.first(5)] }
      end
      sheets = ED.table_sheets(proj, lang, 'F-11', lang == 'ar' ? 'مجاري الظهر والثقوب' : 'BACK GROOVES AND CONFIRMED DRILLING', [t.call('pid'), t.call('unit'), t.call('part'), 'ref', t.call('offset'), t.call('groove_depth'), 'W', t.call('data_status')], rows, [30, 20, 30, 54, 24, 24, 20, 194], per_page: 30,
                               notes: [conf.empty? ? t.call('no_drill') : "#{t.call('confirmed_drill')}: #{conf.size}", t.call('req_hinge'), t.call('req_runner')])
      sheets
    end

    # ------------------------------------------------------------------------------------------------------------ cover + whole set
    def cover_sheets(proj, lang, sheets, an, groups)
      t = ->(k) { ED.t(lang, k) }
      rows = []
      seen = {}
      sheets.each do |s|
        base = s.no.to_s.sub(/-(P|D)(-\d+)?\z/, '').sub(/-(\d+)\z/) { |m| s.no.to_s.start_with?('F-03-') ? m : '' }
        if s.no.to_s.start_with?('F-03-')
          code = s.no.to_s.sub(/\AF-03-/, '').sub(/-(P|D)(-\d+)?\z/, '')
          key = "F-03-#{code}"
          if seen[key]
            seen[key][0] << ", #{s.no.to_s.sub(key, '').sub(/\A-/, '')}"
            next
          end
          row = [key.dup, s.title.to_s.sub(/\A[^-]*- /, "#{t.call('unit')} ")]
          row[1] = "#{t.call('unit')} #{code} - #{s.title.to_s.sub(/\A[^-]*- /, '')}"
          seen[key] = row
          rows << row
        else
          _ = base
          rows << [s.no.to_s, s.title.to_s]
        end
      end
      per = 31
      pages = (rows.size / (per * 2.0)).ceil
      pages = 1 if pages.zero?
      (0...pages).map do |pi|
        sh = ED::Sheet.new(proj, lang: lang, no: pages > 1 ? "F-00-#{pi + 1}" : 'F-00', title: t.call('cover'))
        x0, y0, x1, = sh.area
        if pi.zero?
          info = [[t.call('project'), sh.instance_variable_get(:@proj)['name']], [t.call('client'), proj['client'].to_s], [t.call('rev'), proj['rev'].to_s], [t.call('unit'), groups.size.to_s],
                  [t.call('parts'), (an[:raw] || []).size.to_s], [t.call('date'), Time.now.strftime('%Y-%m-%d')], [t.call('status'), sh.send(:status_text)]]
          lx = sh.rtl ? x1 - 2 : x0 + 2
          vx = sh.rtl ? x1 - 36 : x0 + 36
          info.each_with_index do |(k, v), i|
            yy = y0 + 8 + i * 7
            sh.text(lx, yy, k, size: 2.8, anchor: :left, color: '#666')
            sh.text(vx, yy, v.to_s, size: 3.6, anchor: :left, bold: true)
          end
          y = y0 + 66
          [t.call('unit_ids'), t.call('plinth_note'), (lang == 'ar' ? 'الأبعاد بالمليمتر. المقاسات والتركيبات وفق إعدادات المشروع.' : 'Dimensions in mm. Stock: carcass 2400x1200, back 2400x1200, finish 2800x1220. Drawer box 18. Back groove 10 deep / 5 offset.')].each_with_index do |ln, i|
            words = ln.split(' ')
            line = +''
            row = 0
            words.each do |wd|
              if ED.tw("#{line} #{wd}", 2.8) > 92 && !line.empty?
                sh.text(lx, y + (i * 3 + row) * 4.2, line, size: 2.8, anchor: :left, color: '#444')
                row += 1
                line = +''
              end
              line << (line.empty? ? wd : " #{wd}")
            end
            sh.text(lx, y + (i * 3 + row) * 4.2, line, size: 2.8, anchor: :left, color: '#444')
          end
          y += 38
          hx = sh.rtl ? x1 - 14 : x0 + 2
          sh.hatch(hx, y + 2, 12, 5)
          sh.text(sh.rtl ? x1 - 17 : x0 + 17, y + 6, lang == 'ar' ? 'مادة مقطوعة (قطاع)' : 'cut material (section)', size: 2.8, anchor: :left)
          sh.rect(hx, y + 11, 12, 5, stroke: '#0b57d0', dash: '1.6 0.9', sw: 0.25)
          sh.text(sh.rtl ? x1 - 17 : x0 + 17, y + 15, lang == 'ar' ? 'منطقة التفصيل (مكبرة)' : 'detail zone (enlarged)', size: 2.8, anchor: :left)
        end
        colw = (x1 - x0 - 100) / 2.0
        sh.text(sh.rtl ? x0 + 100 + 2 * colw - 1 : x0 + 100 + 1, y0 + 4, t.call('index'), size: 4, bold: true, anchor: :left) if pi.zero?
        slice = rows.slice(pi * per * 2, per * 2).to_a
        slice.each_with_index do |(no, ttl), i|
          col = i / per
          ri = i % per
          cx = sh.rtl ? x0 + (1 - col) * colw : x0 + 100 + col * colw
          cx = x0 + (1 - col) * colw if sh.rtl
          yy = y0 + 8 + ri * 7
          sh.rect(cx, yy, colw - 2, 6.4, sw: 0.1, stroke: '#aaa', fill: ri.even? ? '#f6f3ea' : 'none')
          sh.text(sh.rtl ? cx + colw - 4 : cx + 2, yy + 4.4, ED.fit_text(no, 2.8, 52), size: 2.8, bold: true, anchor: :left)
          sh.text(sh.rtl ? cx + colw - 56 : cx + 56, yy + 4.4, ED.fit_text(ttl, 2.8, colw - 62), size: 2.8, anchor: :left)
        end
        sh
      end
    end

    # 3D VIEWS: one sheet with four pictures of the model as it stands (two perspectives, the plan and the front), so whoever reads
    # the drawings sees what is being built. The pictures are taken from the SketchUp view and the camera is put back afterwards.
    def view_sheets(model, groups, lang, proj)
      require 'tmpdir'
      view = model.active_view
      bb = Geom::BoundingBox.new
      groups.each { |g| bb.add(g.bounds) }
      return [] if bb.empty?

      c = bb.center
      rad = [bb.width.to_mm, bb.height.to_mm, bb.depth.to_mm].max
      ar = lang == 'ar'
      shots = [[[-0.75, -1.25, 0.7], true, ar ? 'منظور 1' : 'Perspective 1'], [[0.75, -1.25, 0.7], true, ar ? 'منظور 2' : 'Perspective 2'],
               [[0.0, -0.001, 1.0], false, ar ? 'مسقط أفقي' : 'Plan'], [[0.0, -1.0, 0.0], false, ar ? 'واجهة أمامية' : 'Front']]
      now = view.camera # a COPY: the view keeps one camera object and writes every new camera into it
      old = Sketchup::Camera.new(now.eye, now.target, now.up, now.perspective?)
      now.perspective? ? old.fov = now.fov : old.height = now.height
      pics = []
      begin
        shots.each_with_index do |(dir, persp, label), i|
          v = Geom::Vector3d.new(*dir)
          v = v.normalize
          eye = c.offset(v, (rad * 2.2).mm)
          cam = Sketchup::Camera.new(eye, c, dir[2] > 0.99 ? [0, 1, 0] : [0, 0, 1])
          cam.perspective = persp
          view.camera = cam
          view.zoom(groups)
          f = File.join(Dir.tmpdir, "egc_view_#{Process.pid}_#{i}.png")
          view.write_image(f, 1200, 800, true)
          pics << [File.binread(f), label] if File.file?(f)
          File.delete(f) if File.file?(f)
        end
      ensure
        view.camera = old
      end
      return [] if pics.empty?

      sh = ED::Sheet.new(proj, lang: lang, no: 'F-3D', title: ar ? 'مناظير ثلاثية الأبعاد' : '3D views')
      x0, y0, x1, y1 = sh.area
      cw = (x1 - x0 - 4) / 2.0
      ch = (y1 - y0 - 4) / 2.0
      pics.each_with_index do |(png, label), i|
        px = x0 + (i % 2) * (cw + 4)
        py = y0 + (i / 2) * (ch + 4)
        sh.rect(px, py, cw, ch, stroke: '#9aa1ad', sw: 0.12)
        sh.image(px + 1, py + 6, cw - 2, ch - 7, png)
        sh.text(ar ? px + cw - 2 : px + 2, py + 4.4, label, size: 3.2, bold: true, anchor: :left)
      end
      [sh]
    rescue StandardError => e
      Diag.log('view_sheets', {}, error: e) rescue nil
      []
    end

    # Whole Factory drawing set in order. ctx: { model:, cfg:, lang:, proj: }
    def build(model, cfg, lang, proj = Assistant.load(model))
      groups = ProductionPackages.unit_groups(model)
      raise 'FACTORY_DRAWING_ERROR: no E.G.C units in the model.' if groups.empty?

      an = Cutlist.analyse(cfg, model, use_selection: false)
      Cutlist.guard_exports!(an)
      data = SiteDocs.collect(model, proj, cfg)
      ctx = { lang: lang, cfg: cfg, proj: proj, an: an, data: data }
      sheets = []
      sheets.concat(view_sheets(model, groups, lang, proj))
      sheets.concat(ga_sheets(data, lang, proj, 'F-01'))
      sheets.concat(ga_sheets(data, lang, proj, 'F-02', identify: true))
      sheets.concat(stack_sheets(groups, ctx))
      groups.sort_by { |gr| [gr.get_attribute('egc', 'code').to_s.gsub(/\d+/) { |n| format('%04d', n.to_i) }] }.each do |gr|
        sheets.concat(unit_sheets(gr, ctx))
      end
      sheets.concat(ExecWorktop.sheets(data, cfg, lang, proj))
      sheets.concat(schedule_sheets(an, data, groups, cfg, lang, proj))
      sheets.concat(groove_sheet(an, cfg, lang, proj, groups))
      cover = cover_sheets(proj, lang, sheets, an, groups)
      { sheets: cover + sheets, an: an, data: data, groups: groups }
    end
  end
end
