# frozen_string_literal: true

require 'json'

module EGC
  # Factory execution drawing set (A3 landscape SVG sheets): cover + index, general arrangement, unit identification, one manufacturing
  # sheet per unit (front, section A-A, plan section B-B, W x H x D dimension hierarchy, auto DETAIL callouts), parts sheets and schedules.
  module ExecFactory
    module_function

    ED = ExecDraw
    EV = ExecViews
    PANEL_W = 92.0

    # ------------------------------------------------------------------------------------------------------------ helpers
    # ------------------------------------------------------------------------------------------------------------ dimensions
    def dims_front(sh, mp, bs, sm, d)
      xmin, xmax = sm[:x]
      zmin, zmax = sm[:z]
      xl = mp.x(xmin)
      xr = mp.x(xmax)
      yb = mp.y(zmin)
      yt = mp.y(zmax)
      sh.dim_h(xl, xr, yb + 15, ED.fmt(xmax - xmin), from_y: yb + 0.5)
      panels = EV.front_panels(bs).reject { |b| b[:part] == 'drawer_front' && false }
      xe = EV.edges(panels.flat_map { |b| [b[:x0], b[:x1]] })
      if xe.size > 2
        pairs = xe.each_cons(2).select { |a, b| (b - a) * mp.k > 6 }
        pairs.each { |a, b| sh.dim_h(mp.x(a), mp.x(b), yb + 8, ED.fmt(b - a), from_y: yb + 0.5) }
      end
      sh.dim_v(yt, yb, xl - 15, ED.fmt(zmax - zmin), from_x: xl - 0.5)
      sides = bs.select { |b| EV::GRID.include?(b[:part]) }
      if sides.any?
        ze = EV.edges([zmin, sides.map { |b| b[:z0] }.min, sides.map { |b| b[:z1] }.max, zmax])
        if ze.size > 2
          ze.each_cons(2).each { |a, b| sh.dim_v(mp.y(b), mp.y(a), xl - 8, ED.fmt(b - a), from_x: xl - 0.5) if (b - a) * mp.k > 3.4 }
        end
      end
      fronts = panels.select { |b| %w[drawer_front door door1 door2 flap flap_upper flap_lower].include?(b[:part]) }
      seen = []
      fronts.sort_by { |b| b[:z0] }.each do |b|
        key = [b[:z0].round, b[:z1].round]
        next if seen.include?(key)

        seen << key
        sh.dim_v(mp.y(b[:z1]), mp.y(b[:z0]), xr + 9, ED.fmt(b[:z1] - b[:z0]), from_x: xr + 0.5, side: :right)
      end
    end

    def dims_section(sh, mp, bs, sm, xmid)
      dmin, dmax = sm[:d]
      zmin, zmax = sm[:z]
      xl = mp.x(dmin)
      yb = mp.y(zmin)
      dmin, dmax = sm[:joinery_d] || sm[:d]
      sh.dim_h(mp.x(dmin), mp.x(dmax), yb + 15, ED.fmt(dmax - dmin), from_y: yb + 0.5)
      cd = sm[:carcass_d]
      sh.dim_h(mp.x(cd[0]), mp.x(cd[1]), yb + 8, ED.fmt(cd[1] - cd[0]), from_y: yb + 0.5) if cd && ((cd[1] - cd[0]) - (dmax - dmin)).abs > 1
      sh.dim_v(mp.y(zmax), yb, xl - 15, ED.fmt(zmax - zmin), from_x: xl - 0.5)
      horiz = bs.select { |b| b[:role] != 'hw' && b[:x0] <= xmid && b[:x1] >= xmid && (b[:z1] - b[:z0]) <= 30 && (b[:d1] - b[:d0]) >= 100 && b[:mat] != 'front' && b[:mat] != 'drawer' && b[:role] != 'appliance' }
      ze = EV.edges(horiz.flat_map { |b| [b[:z0], b[:z1]] } + [zmax])
      ze = [zmin] + ze if ze.first && ze.first - zmin > 6
      ze.each_cons(2).each { |a, b| sh.dim_v(mp.y(b), mp.y(a), xl - 8, ED.fmt(b - a), from_x: xl - 0.5) if (b - a) * mp.k > 3.4 }
    end

    def dims_plan(sh, mp, bs, sm)
      xmin, xmax = sm[:x]
      dmin, dmax = sm[:d]
      yb = mp.y(dmax)
      xl = mp.x(xmin)
      xr = mp.x(xmax)
      sh.dim_h(xl, xr, yb + 15, ED.fmt(xmax - xmin), from_y: yb + 0.5)
      sl = bs.find { |b| b[:part] == 'side_l' }
      sr = bs.find { |b| b[:part] == 'side_r' }
      sh.dim_h(mp.x(sl[:x1]), mp.x(sr[:x0]), yb + 8, ED.fmt(sr[:x0] - sl[:x1]), from_y: yb + 0.5) if sl && sr
      jmin, jmax = sm[:joinery_d] || sm[:d]
      sh.dim_v(mp.y(jmin), mp.y(jmax), xr + 15, ED.fmt(jmax - jmin), from_x: xr + 0.5, side: :right)
      cd = sm[:carcass_d]
      sh.dim_v(mp.y(cd[0]), mp.y(cd[1]), xr + 8, ED.fmt(cd[1] - cd[0]), from_x: xr + 0.5, side: :right) if cd && ((cd[1] - cd[0]) - (jmax - jmin)).abs > 1
    end

    # callout: dashed zoom rectangle on the parent view + lettered tag
    def marker(sh, mp_f, mp_s, mp_p, c, label, bs, sm, d)
      a0, a1, b0, b1 = c[:region] || []
      b1 = [b1, sm[:z][1]].min if c[:region] && c[:view] != :plan && sm && sm[:z] && b1 # the zone never rises above the unit (it would cover the view title)
      mp, kind = case c[:view]
                 when :plan then [mp_p, :plan]
                 when :section then [mp_s, :elev]
                 when :front then [mp_f, :elev]
                 when :cutout then [mp_f, :elev]
                 else [mp_s, :elev]
                 end
      if c[:region]
        x0 = mp.x(a0)
        x1 = mp.x(a1)
        y0 = kind == :plan ? mp.y(b0) : mp.y(b1)
        y1 = kind == :plan ? mp.y(b1) : mp.y(b0)
      else
        x0 = mp.x(sm[:x][0])
        x1 = mp.x(sm[:x][1])
        y0 = mp.y(sm[:z][1]) + 0.5
        y1 = y0 + 4
        if c[:view] == :lift
          x0 = mp.x(sm[:d][0])
          x1 = mp.x(sm[:d][1])
        end
      end
      cx = (x0 + x1) / 2.0
      cy = (y0 + y1) / 2.0
      wmin = 9.0
      ww = [x1 - x0, wmin].max
      hh = [y1 - y0, wmin].max
      sh.rect(cx - ww / 2.0, cy - hh / 2.0, ww, hh, stroke: '#0b57d0', sw: 0.22, dash: '1.6 0.9')
      tx = [[cx + ww / 2.0 + 3.6, ED::PW - ED::FRAME - 5].min, ED::FRAME + 5].max
      below = kind == :plan || c[:region].nil? || (cy - hh / 2.0 - 3.0) < ED::FRAME + 20 # a tag above a zone at the top of a view would sit on the view title / scale line
      ty = below ? cy + hh / 2.0 + 3.0 : cy - hh / 2.0 - 3.0
      ty = [ty, ED::FRAME + 6].max
      sh.line(cx + ww / 2.0, below ? cy + hh / 2.0 : cy - hh / 2.0, tx - 2.4, below ? ty - 1.8 : ty + 1.8, w: 0.18, color: '#0b57d0')
      sh.circle(tx, ty, 3.2, fill: '#fff', stroke: '#0b57d0', sw: 0.3)
      sh.text(tx, ty + 1.1, label, size: 3.3, anchor: :center, bold: true, color: '#0b57d0')
    end

    # ------------------------------------------------------------------------------------------------------------ parts sheets
    def part_rows(an, code, lang, cfg)
      names = cfg['mat_names'] || {}
      (an[:raw] || []).select { |p| p[:code].to_s == code }.sort_by { |p| p[:pid].to_s }.map do |p|
        [p[:pid], I18n.part(p[:part], lang), names[p[:mat]] || p[:mat], p[:thk], p[:len], p[:wid], "#{p[:eb_l]}L/#{p[:eb_w]}W", [p[:groove], p[:notes]].compact.join(' ')]
      end
    end

    # DRILLING SHEETS of one unit: every board that is drilled or grooved, drawn flat with its holes (the data of the CNC file)
    def drill_sheets(ctx, no, code, cfg)
      lang = ctx[:lang]
      ar = lang == 'ar'
      parts = (ctx[:an][:raw] || []).select { |p| p[:code].to_s == code && DrillMap.any?(DrillMap.data(p)) }.sort_by { |p| p[:pid].to_s }
      return [] if parts.empty?

      names = cfg['mat_names'] || {}
      out = []
      parts.each_slice(6).each_with_index do |grp, pi|
        sh = ED::Sheet.new(ctx[:proj], lang: lang, no: "#{no}-B#{pi.zero? ? '' : pi + 1}", title: "#{ED.t(lang, 'unit')} #{code} - #{ar ? 'الحفر والمجاري' : 'Drilling and grooving'}", zone: code)
        x0, y0, x1, y1 = sh.area
        note_h = 9.0
        cw = (x1 - x0 - 6) / 3.0
        ch = (y1 - y0 - note_h - 3) / 2.0
        grp.each_with_index do |p, i|
          head = "#{p[:pid]}  #{I18n.part(p[:part], 'en')}  #{names[p[:mat]] || p[:mat]} #{DrillMap.num(p[:thk])} mm"
          DrillMap.draw(sh, p, [x0 + (i % 3) * (cw + 3), y0 + (i / 3) * (ch + 3), cw, ch], ED.fit_text(head, 2.9, cw - 4))
        end
        sh.text(ar ? x1 : x0, y1 - 5.2, ar ? 'المواضع على القطعة بعد التشطيب: على الطول من طرف، وعلى العرض من حرف. الأزرق Ø5، الأخضر Ø8، الأحمر المتقطع كوباية مفصلة Ø35 (قياسي K4 - تتأكد من المفصلة)، البرتقالي مجرى.' : 'Positions on the finished piece: along the length from one end, across the width from one edge. Blue = 5 mm, green = 8 mm, dashed red = 35 mm hinge cup (standard K4 - confirm with the hinge), orange = groove.', size: 2.5, anchor: :left, color: '#444')
        sh.text(ar ? x1 : x0, y1 - 1.6, ar ? 'نفس بيانات ملف الـ CNC وأمر الشغل. مجاري الأدراج والميكانيزمات تتحفر حسب ورقة المورد.' : 'Same data as the CNC file and the work order. Drawer runners and mechanisms are drilled from the supplier sheet.', size: 2.5, anchor: :left, color: '#444')
        out << sh
      end
      out
    rescue StandardError => e
      Diag.log("drill_sheets #{code}: #{e.message}") if defined?(Diag) && Diag.respond_to?(:log)
      []
    end

    def parts_sheets(g, d, bs, ctx, no, code, rest_details, rest_labels, dctx, cfg)
      lang = ctx[:lang]
      proj = ctx[:proj]
      headers = [ED.t(lang, 'pid'), ED.t(lang, 'part'), ED.t(lang, 'material'), ED.t(lang, 'thk'), ED.t(lang, 'length'), 'W', ED.t(lang, 'edge'), ED.t(lang, 'notes_col')]
      rows = part_rows(ctx[:an], code, lang, cfg)
      hw = (JSON.parse(d['hw'].to_s) rescue {})
      hw.each { |kk, v| rows << ['HW', kk.to_s, (kk.to_s =~ /hinge|slide|lift/ ? 'GENERIC / REQUIRES SPECIFICATION' : 'GENERIC'), '', v, '', '', ''] }
      dr = Drawings.drilling_rows(bs)
      notes = []
      notes << (dr.empty? ? ED.t(lang, 'no_drill') : "#{ED.t(lang, 'confirmed_drill')}: " + dr.map { |r| "#{r[0]} #{r[2]} #{r[3]} x#{r[4]}" }.first(4).join(' | '))
      notes << ED.t(lang, 'unit_ids')
      sheets = ED.table_sheets(proj, lang, "#{no}-P", "#{ED.t(lang, 'unit')} #{code} - #{ED.t(lang, 'parts')}", headers, rows, [28, 40, 72, 14, 22, 22, 24, 174], per_page: 34, notes: notes)
      if rest_details.any?
        last = sheets.last
        x0, y0, x1, y1 = last.area
        free = y1 - (last.table_bottom || y0) - 6
        cw = 128.0
        chh = 100.0
        if free >= chh * 0.9
          ds = last
          oy = last.table_bottom + 4
          chh = [free - 2, 100.0].min
        else
          ds = ED::Sheet.new(proj, lang: lang, no: "#{no}-D", title: "#{ED.t(lang, 'unit')} #{code} - #{ED.t(lang, 'detail')}", zone: code)
          oy = y0
          sheets << ds
        end
        per_row = [((x1 - x0) / (cw + 3)).floor, 1].max
        rest_details.each_with_index do |c, i|
          col = i % per_row
          row = i / per_row
          cx = ds.rtl ? x1 - (col + 1) * cw - col * 3 : x0 + col * (cw + 3)
          EV.draw_detail(ds, c, bs, [cx, oy + row * (chh + 3), cw, chh], rest_labels[i], cfg, d, dctx)
        end
      end
      sheets.concat(drill_sheets(ctx, no, code, cfg))
      sheets
    end
  end
end
