# frozen_string_literal: true

require 'json'

module EGC
  module ExecSite
    module_function

    # ----------------------------------------------------------------------------------------------------------------- plan + unit positions
    def plan_sheets(data, sv, wall, lang, proj, no)
      units = data[:units].select { |u| u['wall'] == wall['id'] && u['along'] }
      return [] if units.empty?

      sh = ED::Sheet.new(proj, lang: lang, no: no, title: "#{tx(lang, 'GENERAL ARRANGEMENT - PLAN', 'المخطط العام - مسقط أفقي')} - #{wall['id']}", zone: wall['id'].to_s)
      ax0, ay0, ax1, ay1 = sh.area
      len = [wall['len'].to_f, units.map { |u| u['along'][1] }.max].max
      deep = units.map { |u| (u['out'] || [0, u['d']])[1] }.max.to_f
      wt = (data[:proj].dig('room', 'wall_thk') || 200).to_f
      ceil0 = [(data[:proj].dig('room', 'ceiling', 'v') || data[:cfg]['ceiling']).to_f, units.map { |u| u['z0'] + u['h'] }.max.to_f].max
      n = ED::STD_SCALES.find { |nn| len / nn <= ax1 - ax0 - 42 && (deep + wt) / nn + 58 + ceil0 / nn + 48 <= ay1 - ay0 } || ED::STD_SCALES.last
      k = 1.0 / n
      ox = ax0 + 20 + ((ax1 - ax0 - 40) - len * k) / 2.0
      fx = ->(a) { sh.rtl ? ox + len * k - a * k : ox + a * k }
      y0 = ay0 + 26
      sh.instance_variable_set(:@scale, ED.scale_label(n))
      # wall (cut, hatched) above the room-side line, datum
      wx = fx.call(sh.rtl ? len : 0)
      sh.hatch(wx, y0 - wt * k, len * k, wt * k)
      sh.text(sh.rtl ? ax1 - 2 : ax0 + 2, y0 - wt * k - 4, "#{tx(lang, 'WALL', 'الحائط')} #{wall['id']}  (#{st_label(wall['st'] || 'INFERRED', lang)})", size: 2.8, anchor: :left, color: '#444')
      units.sort_by { |u| u['kind'] == 'base' ? 0 : 1 }.each do |u|
        next if u['kind'] == 'tall' && u['code'].to_s.end_with?('U') && units.any? { |q| q['code'] == u['code'].to_s.sub(/Uz/, 'L') } # the stacked module has the same plan footprint as its lower module
        a0, a1 = u['along']
        d0, d1 = u['out'] || [0, u['d']]
        x = fx.call(sh.rtl ? a1 : a0)
        if %w[base tall].include?(u['kind'])
          sh.rect(x, y0 + d0 * k, (a1 - a0) * k, (d1 - d0) * k, fill: '#f1e8d0', stroke: '#222', sw: 0.25)
          sh.text(x + (a1 - a0) * k / 2.0, y0 + (d0 + d1) / 2.0 * k + 1, u['code'].to_s.sub(/L\z/, ''), size: [[(a1 - a0) * k / [u['code'].to_s.length, 1].max * 1.2, 2.6].min, 1.6].max, anchor: :center) if (a1 - a0) * k > 5 && !u['code'].to_s.end_with?('U')
        elsif u['tier'].to_i == 1
          sh.rect(x, y0 + d0 * k, (a1 - a0) * k, (d1 - d0) * k, stroke: '#555', sw: 0.18, dash: '1.4 0.9')
        end
        u['apps'].each do |ap|
          cx = SiteDocs.along_of(wall, ap['center'])
          sh.line(fx.call(cx), y0 + d0 * k, fx.call(cx), y0 + d1 * k, w: 0.15, dash: '3 1 0.6 1', color: '#0b57d0') if %w[base tall].include?(u['kind'])
        end
      end
      # ordinate X from datum, unit chain, depth
      yb = y0 + deep * k
      xs = EV.edges(units.flat_map { |u| u['along'] } + [0, len])
      xs.each_with_index do |a, i|
        x = fx.call(a)
        sh.line(x, yb + 0.5, x, yb + 6 + (i % 2) * 5, w: 0.1, color: '#8a1c12')
        sh.text(x + 0.9, yb + 10 + (i % 2) * 5, ED.fmt(a), size: 2.4, anchor: :pleft, color: '#8a1c12', ltr: true)
      end
      sh.dim_h(fx.call(sh.rtl ? len : 0), fx.call(sh.rtl ? 0 : len), yb + 22, ED.fmt(len), from_y: yb + 0.5)
      base = units.select { |u| u['kind'] == 'base' }
      bd = base.map { |u| (u['out'] || [0, u['d']])[1] }.max
      xr = fx.call(sh.rtl ? 0 : len)
      sh.dim_v(y0, y0 + bd * k, xr + 8, ED.fmt(bd), from_x: xr + 0.5, side: :right) if bd # outside the run end in both languages
      dx = fx.call(0)
      sh.poly([[dx - 2.2, y0 - wt * k - 8], [dx + 2.2, y0 - wt * k - 8], [dx, y0 - wt * k - 4]], fill: '#0b57d0', stroke: '#0b57d0', sw: 0.1)
      sh.text(dx + (sh.rtl ? -3.4 : 3.4), y0 - wt * k - 8, "#{ED.t(lang, 'datum')} X=0", size: 2.7, anchor: :pleft, color: '#0b57d0', bold: true)
      # elevation below the plan: same scale and datum
      fr = elev_frame(sh, data, wall, [ax0, yb + 28, ax1, ay1 - 2], lang, force_n: n, top_margin: 14.0, bottom_margin: 34.0)
      ordinates(sh, fr, lang)
      rows = units.sort_by { |u| [u['along'][0], u['z0']] }.map { |u| [u['code'], u['type'], ED.fmt(u['along'][0]), ED.fmt(u['along'][1]), "#{ED.fmt(u['w'])} x #{ED.fmt(u['h'])} x #{ED.fmt(u['d'])}", ED.fmt(u['z0'])] }
      heads = [tx(lang, 'Unit', 'وحدة'), tx(lang, 'Type', 'النوع'), tx(lang, 'X start', 'X البداية'), tx(lang, 'X end', 'X النهاية'), 'W x H x D', tx(lang, 'Z bottom (AFFL)', 'Z أسفل')]
      tab = ED.table_sheets(proj, lang, "#{no}-T", tx(lang, 'UNIT POSITIONS FROM DATUM', 'مواضع الوحدات من المرجع'), heads, rows, [26, 60, 34, 34, 70, 40], per_page: 34)
      [sh] + tab
    end

    # compact table inside rect; returns the rows that did not fit
    # source note shown in the schedule (data keeps the English text; drawings follow the selected language)
    def src_text(src, lang)
      t = src.to_s
      return t unless lang == 'ar' # fit_text decides; never cut mid-word here
      return 'مقترح من موضع الجهاز الحالي؛ تحقق من المستوى والمرجع في الموقع' if t.start_with?('proposal from current')
      return 'مقترح عند أعلى الوحدة العلوية وبداية الصف؛ تحقق من قدرة المحول والمستوى' if t.start_with?('proposed at modeled')
      return t.sub('user point', 'نقطة مستخدم') if t.start_with?('user point')
      t
    end

    def simple_table(sh, heads, widths, rows, rect)
      x0, y0, x1, y1 = rect
      scale = (x1 - x0) / widths.sum
      ws = widths.map { |w| w * scale }
      rh = 5.0
      fit = [((y1 - y0) / rh).floor - 1, 0].max
      draw = lambda do |vals, y, head|
        v = sh.rtl ? vals.reverse : vals
        w2 = sh.rtl ? ws.reverse : ws
        x = x0
        sh.rect(x0, y, x1 - x0, rh, fill: head ? '#e9e4d3' : 'none', sw: 0.12, stroke: '#888')
        v.each_with_index do |c, i|
          sh.line(x, y, x, y + rh, w: 0.08, color: '#aaa') if i.positive?
          sh.text(sh.rtl ? x + w2[i] - 1 : x + 1, y + rh - 1.5, ED.fit_text(c.to_s, 2.6, w2[i] - 2), size: 2.6, anchor: :left, bold: head)
          x += w2[i]
        end
      end
      draw.call(heads, y0, true)
      rows.first(fit).each_with_index { |r, i| draw.call(r, y0 + rh * (i + 1), false) }
      rows.drop(fit)
    end

    # ----------------------------------------------------------------------------------------------------------------- elevation + appliance layout
    def elevation_sheets(data, wall, lang, proj, no)
      units = data[:units].select { |u| u['wall'] == wall['id'] && u['along'] }
      return [] if units.empty?

      sh = ED::Sheet.new(proj, lang: lang, no: no, title: "#{tx(lang, 'WALL ELEVATION', 'واجهة الحائط')} - #{wall['id']}", zone: wall['id'].to_s)
      ax0, ay0, ax1, ay1 = sh.area
      fr = elev_frame(sh, data, wall, [ax0, ay0, ax1, ay1 - 8], lang)
      ordinates(sh, fr, lang)
      sh.instance_variable_set(:@scale, ED.scale_label(fr[:n]))
      sh.text(sh.rtl ? ax1 - 2 : ax0 + 2, ay1 - 2, ED.t(lang, 'inferred_note'), size: 2.6, anchor: :left, color: '#8a1c12')
      sh
    end

    def appliance_sheets(data, sv, wall, lang, proj, no)
      units = data[:units].select { |u| u['wall'] == wall['id'] && u['along'] }
      apps = units.flat_map { |u| u['apps'].map { |a| [u, a] } }
      return [] if apps.empty?

      sh = ED::Sheet.new(proj, lang: lang, no: no, title: "#{tx(lang, 'APPLIANCE LAYOUT', 'توزيع الأجهزة')} - #{wall['id']}", zone: wall['id'].to_s)
      ax0, ay0, ax1, ay1 = sh.area
      fr = elev_frame(sh, data, wall, [ax0, ay0, ax1, ay0 + 170], lang, emphasise_apps: true, code_labels: false)
      ordinates(sh, fr, lang)
      marks = []
      dim_rows = []
      sh.instance_variable_set(:@scale, ED.scale_label(fr[:n]))
      mp = fr[:mp]
      rows = []
      apps.each_with_index do |(u, a), i|
        cx = SiteDocs.along_of(wall, a['center'])
        aw = ((a['opening'] || {})['w'] || [u['w'] - 40, 0].max).to_f
        left = cx - aw / 2.0
        z0, z1 = a['z']
        z1 = [z1, u['z0'] + u['h']].min if %w[sink hob hob_gas].include?(a['kind'].to_s)
        x1 = fr[:fx].call(sh.rtl ? left + aw : left)
        x2 = fr[:fx].call(sh.rtl ? left : left + aw)
        lo, hi = [x1, x2].minmax
        need = [hi - lo, ED.tw(ED.fmt(aw), 2.7) + 2].max
        mid = (lo + hi) / 2.0
        lvl = (0..5).find { |l| dim_rows.none? { |(l2, a, b)| l2 == l && mid - need / 2.0 < b && mid + need / 2.0 > a } } || 0
        dim_rows << [lvl, mid - need / 2.0, mid + need / 2.0]
        sh.dim_h(x1, x2, mp.y(z1) - 3 - lvl * 5, ED.fmt(aw), from_y: mp.y(z1) - 0.5)
        sh.dim_v(mp.y(z1), mp.y(z0), (sh.rtl ? x1 : x2) + (sh.rtl ? -4 : 4), ED.fmt(z1 - z0), from_x: (sh.rtl ? x1 : x2) + (sh.rtl ? -0.5 : 0.5), side: sh.rtl ? :left : :right)
        my = mp.y((z0 + z1) / 2.0) # marker inside the appliance zone, clear of the dimension lines
        my = mp.y(z0) + 5.5 if (z1 - z0) * fr[:k] < 6 # thin cutout (sink / hob): marker just below it
        marks << { 'off' => cx, 'z' => (z1 - z0) * fr[:k] < 6 ? z0 - 5.5 / fr[:k] : (z0 + z1) / 2.0, 'id' => '  ' }
        sh.circle(fr[:fx].call(cx), my, 2.4, fill: '#fff', stroke: '#111', sw: 0.25)
        sh.text(fr[:fx].call(cx), my + 1.0, (i + 1).to_s, size: 2.7, anchor: :center, bold: true)
        op = a['opening'] || {}
        rows << [(i + 1).to_s, u['code'], a['dev'] || a['kind'], a['kind'], ED.fmt(left), ED.fmt(z0), [op['w'], op['h'], op['d']].compact.join(' x '), (a['profile'] || {})['data_status'] || 'REQUIRES CONFIRMATION']
      end
      unit_labels(sh, fr, marks)
      heads = ['#', tx(lang, 'Unit', 'وحدة'), tx(lang, 'Equipment', 'الجهاز'), tx(lang, 'Type', 'النوع'), tx(lang, 'X left', 'X يسار'), tx(lang, 'Z bottom', 'Z أسفل'), tx(lang, 'Opening W x H x D', 'الفتحة'), tx(lang, 'Data status', 'حالة البيانات')]
      rest = simple_table(sh, heads, [14, 20, 60, 40, 32, 32, 60, 138], rows, [ax0, ay0 + 182, ax1, ay1 - 2])
      out = [sh]
      out.concat(ED.table_sheets(proj, lang, "#{no}-T", tx(lang, 'APPLIANCE POSITIONS', 'مواضع الأجهزة'), heads, rest, [14, 20, 60, 40, 32, 32, 60, 138], per_page: 30)) unless rest.empty?
      out
    end

    # ----------------------------------------------------------------------------------------------------------------- hood / duct / gas
    def hood_sheets(data, sv, wall, lang, proj, no)
      kinds = %w[duct gas]
      pts = sv['points'].select { |p| kinds.include?(p['kind']) && p['wall'] == wall['id'] }
      return [] if pts.empty?

      extra = lambda do |sh, fr|
        units = fr[:units]
        hobs = units.flat_map { |u| u['apps'].select { |a| %w[hob hob_gas].include?(a['kind'].to_s) }.map { |a| [u, a] } }
        hoods = units.flat_map { |u| u['apps'].select { |a| a['kind'].to_s.start_with?('hood') }.map { |a| [u, a] } }
        mp = fr[:mp]
        hobs.each do |u, a|
          cx = SiteDocs.along_of(wall_of(fr), a['center'])
          x = fr[:fx].call(cx)
          sh.line(x, mp.y(a['z'][0]), x, mp.y(fr[:ceiling]), w: 0.2, dash: '5 1.2 1 1.2', color: '#6d28d9')
          sh.text(x + (sh.rtl ? -1.5 : 1.5), mp.y(fr[:ceiling]) + 5, "#{tx(sh.lang, 'HOB CENTERLINE', 'محور البوتجاز')} X=#{ED.fmt(cx)}", size: 2.4, anchor: :pleft, color: '#6d28d9')
          hoods.each do |_hu, h|
            hx = SiteDocs.along_of(wall_of(fr), h['center'])
            off = hx - cx
            sh.dim_h(fr[:fx].call(sh.rtl ? [cx, hx].max : [cx, hx].min), fr[:fx].call(sh.rtl ? [cx, hx].min : [cx, hx].max), mp.y(h['z'][1]) - 5, "#{tx(sh.lang, 'offset', 'إزاحة')} #{ED.fmt(off.abs)}", from_y: mp.y(h['z'][1]) - 0.5) if off.abs > 1
            clear = h['z'][0] - a['z'][1]
            sh.dim_v(mp.y(h['z'][0]), mp.y(a['z'][1]), x - (sh.rtl ? -10 : 10), "#{ED.fmt(clear)}", from_x: x - (sh.rtl ? -0.5 : 0.5), side: sh.rtl ? :right : :left) if clear.positive?
          end
        end
      end
      service_sheets(data, sv, kinds, wall, lang, proj, no, tx(lang, 'HOOD / DUCT / GAS', 'الشفاط / المجرى / الغاز'), extra: extra, unit_details: true)
    end

    def wall_of(fr)
      fr[:wall]
    end

    # ----------------------------------------------------------------------------------------------------------------- LED / power
    def led_sheets(data, sv, wall, lang, proj, no)
      leds = data[:units].select { |u| u['wall'] == wall['id'] && u['led'] }
      pts = sv['points'].select { |p| p['kind'] == 'led' && p['wall'] == wall['id'] }
      return [] if leds.empty? && pts.empty?

      extra = lambda do |sh, fr|
        mp = fr[:mp]
        leds.each do |u|
          x0 = fr[:fx].call(sh.rtl ? u['along'][1] : u['along'][0])
          sh.line(x0, mp.y(u['z0']) + 1.2, x0 + (u['along'][1] - u['along'][0]) * fr[:k], mp.y(u['z0']) + 1.2, w: 0.7, color: '#0e7c5a')
        end
        runs = leds.group_by { |u| u['z0'].round }
        run_i = 0
        runs.sort_by { |z, _| z }.each do |z, us|
          a0 = us.map { |u| u['along'][0] }.min
          a1 = us.map { |u| u['along'][1] }.max
          lab = "LED  Z=#{ED.fmt(z)}  X=#{ED.fmt(a0)}..#{ED.fmt(a1)}  (#{ED.fmt(a1 - a0)})  #{tx(sh.lang, 'groove', 'حفر')} #{ED.fmt(us.first['led']['lw'])}x#{ED.fmt(us.first['led']['ld'])} @ #{ED.fmt(us.first['led']['off'])}"
          ly = mp.y(0) + 36 + run_i * 5 # run notes below the elevation (free area), never over the units
          run_i += 1
          lx = fr[:fx].call(sh.rtl ? fr[:len] : 0) + (sh.rtl ? 0 : 0)
          sh.line(lx + (sh.rtl ? fr[:len] * fr[:k] - 8 : 0), ly - 1.0, lx + (sh.rtl ? fr[:len] * fr[:k] : 8), ly - 1.0, w: 0.7, color: '#0e7c5a')
          sh.text(sh.rtl ? lx + fr[:len] * fr[:k] - 10 : lx + 10, ly, lab, size: 2.6, anchor: :left, color: '#0e7c5a')
        end
      end
      service_sheets(data, sv, ['led'], wall, lang, proj, no, tx(lang, 'LED / POWER', 'الإضاءة / الكهرباء'), extra: extra, allow_empty: leds.any?, unit_details: true)
    end

    # ----------------------------------------------------------------------------------------------------------------- schedules
    def schedule_sheets(data, sv, lang, proj)
      rows = sv['points'].map { |p| [p['id'], kind_label(p['kind'], lang), p['device'], p['unit'], p['wall'], ED.fmt(p['off']), ED.fmt(p['z']), p['spec'] || '-', st_label(p['st'], lang), src_text(p['src'], lang)] }
      out = ED.table_sheets(proj, lang, 'S-08', tx(lang, 'SERVICE SCHEDULE', 'جدول الخدمات'), ['ID', tx(lang, 'Type', 'النوع'), tx(lang, 'Equipment', 'الجهاز'), tx(lang, 'Unit', 'وحدة'), tx(lang, 'Wall', 'حائط'), 'X', 'Z AFFL', tx(lang, 'Specification', 'المواصفة'), tx(lang, 'Status', 'الحالة'), tx(lang, 'Source', 'المصدر')],
                            rows, [16, 30, 40, 14, 14, 18, 20, 44, 44, 156], per_page: 34,
                            notes: [ED.t(lang, 'inferred_note'), tx(lang, 'X = distance from datum (wall start); Z = AFFL. No ratings or sizes are issued unless confirmed.', 'X = المسافة من المرجع (بداية الحائط)؛ Z = ارتفاع فوق الأرضية. لا تصدر قيم كهربائية أو مقاسات غير مؤكدة.')])
      arows = data[:units].flat_map do |u|
        u['apps'].map do |a|
          ids = sv['points'].select { |p| p['unit'] == u['code'] && p['device'] == a['dev'] }.map { |p| p['id'] }.join(' ')
          op = a['opening'] || {}
          [u['code'], a['dev'] || a['kind'], a['kind'], ids.empty? ? '-' : ids, [op['w'], op['h'], op['d']].compact.join(' x '), (a['profile'] || {})['data_status'] || 'REQUIRES CONFIRMATION']
        end
      end
      out.concat(ED.table_sheets(proj, lang, 'S-09', tx(lang, 'APPLIANCE SERVICE SCHEDULE', 'جدول خدمات الأجهزة'), [tx(lang, 'Unit', 'وحدة'), tx(lang, 'Equipment', 'الجهاز'), tx(lang, 'Type', 'النوع'), tx(lang, 'Service IDs', 'أرقام الخدمات'), tx(lang, 'Opening W x H x D', 'الفتحة'), tx(lang, 'Data status', 'حالة البيانات')], arows, [24, 70, 40, 90, 60, 112], per_page: 34))
      review = sv['points'].reject { |p| p['st'] == 'CONFIRMED' }.map { |p| [p['id'], kind_label(p['kind'], lang), p['unit'], st_label(p['st'], lang), tx(lang, 'Confirm position (X, Z AFFL) and specification on site', 'أكد الموضع (X, Z) والمواصفة في الموقع')] }
      sv['orphans'].to_a.each { |o| review << [o['id'], kind_label(o['kind'], lang), o['device'].to_s, st_label('MISSING_DATA', lang), tx(lang, 'User point has no matching appliance', 'نقطة المستخدم بلا جهاز مطابق')] }
      sv['unmatched_devices'].to_a.each { |u| review << ['-', tx(lang, 'Appliance', 'جهاز'), u['unit'], st_label('MISSING_DATA', lang), u['reason'].to_s[0, 90]] }
      review << ['-', tx(lang, 'Wall reference', 'مرجع الحائط'), '-', st_label((data[:walls].first || {})['st'] || 'INFERRED', lang), tx(lang, 'Datum wall inferred from cabinet backs: measure the real wall', 'مرجع الحائط مستنتج من ظهر الوحدات: قس الحائط الفعلي')] if data[:walls].any? { |w| w['st'] != 'CONFIRMED' }
      out.concat(ED.table_sheets(proj, lang, 'S-10', tx(lang, 'REVIEW / UNCONFIRMED ITEMS', 'مراجعة / بنود غير مؤكدة'), ['ID', tx(lang, 'Type', 'النوع'), tx(lang, 'Unit', 'وحدة'), tx(lang, 'Status', 'الحالة'), tx(lang, 'Action', 'الإجراء')], review, [20, 50, 24, 60, 242], per_page: 34))
      out
    end

    # ----------------------------------------------------------------------------------------------------------------- cover
    def cover_sheet(proj, lang, data, sv, sheets)
      sh = ED::Sheet.new(proj, lang: lang, no: 'S-00', title: tx(lang, 'SITE / CIVIL-MEP COVER, INDEX AND DATUM', 'غلاف الموقع والفهرس والمرجع'))
      ax0, ay0, ax1, ay1 = sh.area
      rtl = sh.rtl
      lx = rtl ? ax1 - 2 : ax0 + 2
      info = [[ED.t(lang, 'project'), sh.instance_variable_get(:@proj)['name']], [ED.t(lang, 'client'), proj['client'].to_s], [ED.t(lang, 'rev'), proj['rev'].to_s],
              [ED.t(lang, 'date'), Time.now.strftime('%Y-%m-%d')], [ED.t(lang, 'status'), sh.send(:status_text)]]
      info.each_with_index do |(kk, v), i|
        sh.text(lx, ay0 + 6 + i * 6.5, kk, size: 2.7, anchor: :left, color: '#666')
        sh.text(rtl ? ax1 - 34 : ax0 + 34, ay0 + 6 + i * 6.5, v.to_s, size: 3.4, anchor: :left, bold: true)
      end
      # datum diagram
      dy = ay0 + 44
      sh.text(lx, dy, ED.t(lang, 'datum').to_s + ' / ' + ED.t(lang, 'ffl'), size: 3.6, bold: true, anchor: :left)
      bx = rtl ? ax1 - 100 : ax0 + 6
      by = dy + 6
      sh.rect(bx, by, 90, 44, fill: '#f6f3ea', stroke: '#444', sw: 0.2)
      sh.hatch(bx, by, 5, 44)
      sh.line(bx - 4, by + 40, bx + 94, by + 40, w: 0.5)
      sh.line(bx + 5, by + 42, bx + 5, by - 4, w: 0.25, dash: '5 1.2 1 1.2', color: '#0b57d0')
      sh.circle(bx + 50, by + 18, 1.9, fill: '#c2410c', stroke: '#c2410c', sw: 0.3)
      sh.dim_h(bx + 5, bx + 50, by + 36, 'X', from_y: by + 20)
      sh.dim_v(by + 18, by + 40, bx + 58, 'Z', from_x: bx + 51, side: :right)
      sh.text(bx + 8, by - 1.5, "#{ED.t(lang, 'datum')} X=0", size: 2.5, anchor: :pleft, color: '#0b57d0', bold: true)
      sh.text(bx + 62, by + 39, "#{ED.t(lang, 'ffl')} Z=0", size: 2.5, anchor: :pleft, color: '#0b57d0', bold: true)
      [ED.t(lang, 'x_dim') + ' (mm)', ED.t(lang, 'z_dim') + ' (mm)', ED.t(lang, 'inferred_note')].each_with_index do |ln, i|
        sh.text(lx, by + 52 + i * 5, ED.fit_text(ln, 2.8, 150), size: 2.8, anchor: :left, color: '#444')
      end
      # legend
      ly = by + 72
      sh.text(lx, ly, ED.t(lang, 'legend'), size: 3.6, bold: true, anchor: :left)
      kinds = %w[elec water_cold water_hot drain duct led]
      kinds << 'gas' if sv['points'].any? { |p| p['kind'] == 'gas' }
      kinds.each_with_index do |kd, i|
        yy = ly + 6 + i * 6
        sx = rtl ? ax1 - 8 : ax0 + 8
        symbol(sh, sx, yy - 1, kd, 'CONFIRMED', CODES[kd], lang)
        sh.text(rtl ? ax1 - 22 : ax0 + 22, yy, kind_label(kd, lang), size: 2.8, anchor: :left)
      end
      yy = ly + 6 + kinds.size * 6
      symbol(sh, rtl ? ax1 - 8 : ax0 + 8, yy - 1, 'elec', 'INFERRED', '', lang)
      sh.text(rtl ? ax1 - 22 : ax0 + 22, yy, tx(lang, 'dashed outline = INFERRED / REQUIRES CONFIRMATION', 'خط متقطع = مستنتج / يتطلب تأكيد'), size: 2.8, anchor: :left)
      # services summary (counts by type / status)
      sy = ly + 6 + (kinds.size + 2) * 6 + 6
      sh.text(lx, sy, tx(lang, 'SERVICE SUMMARY', 'ملخص الخدمات'), size: 3.6, bold: true, anchor: :left)
      kinds.each_with_index do |kd, i|
        list = sv['points'].select { |p| p['kind'] == kd }
        conf = list.count { |p| p['st'] == 'CONFIRMED' }
        sh.text(lx, sy + 6 + i * 5, "#{kind_label(kd, lang)}: #{list.size}  (#{tx(lang, 'confirmed', 'مؤكد')} #{conf} / #{tx(lang, 'unconfirmed', 'غير مؤكد')} #{list.size - conf})", size: 2.8, anchor: :left)
      end
      # index (right half)
      colw = 188
      ix = rtl ? ax0 : ax1 - colw
      sh.text(rtl ? ix + colw - 2 : ix + 2, ay0 + 6, ED.t(lang, 'index'), size: 4, bold: true, anchor: :left)
      sheets.first(36).each_with_index do |s, i|
        yy = ay0 + 10 + i * 6.3
        sh.rect(ix, yy, colw, 6, fill: i.even? ? '#f6f3ea' : 'none', stroke: '#aaa', sw: 0.1)
        sh.text(rtl ? ix + colw - 3 : ix + 3, yy + 4.3, ED.fit_text(s.no, 2.8, 36), size: 2.8, bold: true, anchor: :left)
        sh.text(rtl ? ix + colw - 42 : ix + 42, yy + 4.3, ED.fit_text(s.title, 2.8, colw - 46), size: 2.8, anchor: :left)
      end
      sh
    end

    # ----------------------------------------------------------------------------------------------------------------- whole set
    def build(model, cfg, lang, proj = Assistant.load(model))
      data = SiteDocs.collect(model, proj, cfg)
      raise 'SITE_DRAWING_ERROR: add modeled kitchen units or defined room/wall references before exporting.' if data[:units].empty?

      sv = SiteDocs.services(data)
      sheets = []
      walls = SiteDocs.used_walls(data)
      multi = walls.size > 1
      walls.each do |wall|
        sfx = multi ? "-#{wall['id']}" : ''
        sheets.concat(plan_sheets(data, sv, wall, lang, proj, "S-01#{sfx}"))
        sheets.concat(appliance_sheets(data, sv, wall, lang, proj, "S-02A#{sfx}"))
        sheets.concat(service_sheets(data, sv, %w[elec], wall, lang, proj, "S-03#{sfx}", tx(lang, 'ELECTRICAL', 'الكهرباء'), unit_details: true))
        sheets.concat(service_sheets(data, sv, %w[water_cold water_hot drain], wall, lang, proj, "S-04#{sfx}", tx(lang, 'WATER / DRAIN', 'المياه / الصرف')))
        sheets.concat(hood_sheets(data, sv, wall, lang, proj, "S-05#{sfx}"))
        sheets.concat(led_sheets(data, sv, wall, lang, proj, "S-06#{sfx}"))
        sheets.concat(service_sheets(data, sv, %w[elec water_cold water_hot drain duct gas led], wall, lang, proj, "S-07#{sfx}", tx(lang, 'COORDINATED SERVICES', 'تنسيق الخدمات'), label: false))
      end
      sheets.compact!
      sheets.concat(schedule_sheets(data, sv, lang, proj))
      cover = cover_sheet(proj, lang, data, sv, sheets)
      { sheets: [cover] + sheets, data: data, sv: sv }
    end
  end
end
