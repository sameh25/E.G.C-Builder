# frozen_string_literal: true

module EGC
  # Factory worktop drawing: plan of the real countertop pieces (positions from the model), joints, sink / hob cutouts
  # (same rule the slab was cut with: Kitchen.cutout_rect) with W x D and position dimensions, plus enlarged cutout details.
  module ExecWorktop
    module_function

    ED = ExecDraw

    def tx(lang, en, ar)
      lang == 'ar' ? ar : en
    end

    # -> [Sheet, ...] (empty when the model has no worktop piece)
    def sheets(data, cfg, lang, proj, no = 'F-10')
      pieces = SiteDocs.each_part(data[:model], ['countertop'], data[:walls]).select { |p| p[:wall] && p[:along] }
      return [] if pieces.empty?

      walls = pieces.map { |p| p[:wall] }.uniq
      walls.flat_map.with_index do |wid, wi|
        ps = pieces.select { |p| p[:wall] == wid }.sort_by { |p| p[:along][0] }
        r0 = ps.map { |p| p[:along][0] }.min
        r1 = ps.map { |p| p[:along][1] }.max
        units = data[:units].select { |u| u['wall'] == wid && u['kind'] == 'base' && u['along'] && u['along'][0] >= r0 - 1 && u['along'][1] <= r1 + 1 } # units carrying this slab run
        sheet_no = walls.size > 1 ? "#{no}-#{wid}" : no
        draw(ps, units, cfg, lang, proj, sheet_no, wid, wi)
      end
    end

    def cutouts(units, cfg)
      out = []
      units.each do |u|
        u['apps'].each do |ap|
          op = ap['opening']
          next unless op && op['cutout']

          kind = ap['kind'].to_s == 'sink' ? :sink : :hob
          r = op['rect'] || Kitchen.cutout_rect(kind, 0, u['w'], cfg) # a product sink carries the opening it was built with
          out << { code: u['code'], kind: kind, a0: u['along'][0] + r[0], w: r[2], d0: r[1], d: r[3], off_unit: r[0], unit_w: u['w'], unit_a0: u['along'][0],
                   status: op['status'], product: op['product'], overall: op['overall'], shape: op['shape'] }
        end
      end
      out
    end

    def draw(ps, units, cfg, lang, proj, no, wid, _wi)
      sh = ED::Sheet.new(proj, lang: lang, no: no, title: "#{tx(lang, 'WORKTOP PLAN AND CUTOUTS', 'مسقط سطح العمل والفتحات')} - #{wid}", zone: wid.to_s)
      ax0, ay0, ax1, ay1 = sh.area
      run0 = ps.map { |p| p[:along][0] }.min
      run1 = ps.map { |p| p[:along][1] }.max
      depth = ps.map { |p| p[:d]['wid'].to_f }.max
      len = run1 - run0
      cuts = cutouts(units, cfg)
      # plan occupies the upper half; enlarged cutout details the lower strip
      plan_h = (ay1 - ay0) * (cuts.empty? ? 0.8 : 0.5)
      mL = 14.0
      mR = 14.0
      n = ED.pick_scale(len, depth + 260, ax1 - ax0 - mL - mR, plan_h - 40)
      k = 1.0 / n
      ox = ax0 + mL + ((ax1 - ax0 - mL - mR) - len * k) / 2.0
      oy = ay0 + 26.0 # wall line
      sh.instance_variable_set(:@scale, ED.scale_label(n))
      mpx = ->(a) { sh.rtl ? ox + len * k - (a - run0) * k : ox + (a - run0) * k }
      rx = ->(a0, a1) { [mpx.call(sh.rtl ? a1 : a0), (a1 - a0) * k] }
      # wall
      sh.hatch(ox - 4, oy - 5, len * k + 8, 5)
      sh.text(sh.rtl ? ox + len * k + 4 : ox - 4, oy - 7, "#{tx(lang, 'WALL', 'الحائط')} #{wid}", size: 2.6, anchor: sh.rtl ? :pleft : :pright, color: '#444')
      # base unit footprints (what carries the slab)
      units.each do |u|
        x, w = rx.call(*u['along'])
        sh.rect(x, oy, w, [u['d'].to_f, depth].min * k, stroke: '#8a8a8a', dash: '1.2 0.8', sw: 0.15)
        sh.text(x + w / 2.0, oy + [u['d'].to_f, depth].min * k - 1.6, ED.fit_text(u['code'].to_s, 2.2, w - 1), size: 2.2, anchor: :center, color: '#777')
      end
      # worktop pieces
      ps.each do |p|
        x, w = rx.call(*p[:along])
        dpt = p[:d]['wid'].to_f
        y = oy + [p[:out].to_f, 0].max * k
        sh.rect(x, y, w, dpt * k, fill: '#cfd3d8', stroke: '#111', sw: 0.35)
        lab = "#{p[:d]['pid']}  #{ED.fmt(p[:d]['len'])} x #{ED.fmt(dpt)} x #{ED.fmt(p[:d]['thk'])}"
        if ED.tw(lab, 2.6) <= w - 2
          sh.text(x + w / 2.0, y + dpt * k - 8, lab, size: 2.6, anchor: :center, bold: true)
          sh.text(x + w / 2.0, y + dpt * k - 4, ED.fit_text(p[:d]['notes'].to_s, 2.2, w - 2), size: 2.2, anchor: :center, color: '#555') unless p[:d]['notes'].to_s.empty?
        else
          sh.text(x + w / 2.0 + 1, y + dpt * k / 2.0, lab, size: 2.4, anchor: :center, rot: 90, bold: true) # narrow piece: label along the piece
        end
      end
      # cutouts
      cuts.each_with_index do |c, i|
        x, w = rx.call(c[:a0], c[:a0] + c[:w])
        y = oy + c[:d0] * k
        if c[:shape] == 'round'
          sh.circle(x + w / 2.0, y + c[:d] * k / 2.0, [w, c[:d] * k].min / 2.0, fill: '#ffffff', stroke: '#b42318', sw: 0.3, dash: '1.6 0.9')
        else
          sh.rect(x, y, w, c[:d] * k, fill: '#ffffff', stroke: '#b42318', sw: 0.3, dash: '1.6 0.9')
        end
        sh.text(x + w / 2.0, y + c[:d] * k / 2.0 + 1, "#{tx(lang, c[:kind] == :sink ? 'SINK' : 'HOB', c[:kind] == :sink ? 'الحوض' : 'الموقد')} #{('A'.ord + i).chr}", size: 2.6, anchor: :center, bold: true, color: '#b42318')
        sh.text(x + w / 2.0, y + c[:d] * k / 2.0 + 4.5, Kitchen::CUTOUT_REQUIRED, size: 1.9, anchor: :center, bold: true, color: '#b42318') if c[:status] == Kitchen::CUTOUT_REQUIRED
      end
      # dimensions: piece widths (top), overall run (outermost), joints
      yd = oy - 10
      ps.each { |p| a, w = rx.call(*p[:along]); sh.dim_h(a, a + w, yd, ED.fmt(p[:along][1] - p[:along][0]), from_y: oy) }
      a, w = rx.call(run0, run1)
      sh.dim_h(a, a + w, yd - 7, ED.fmt(len), from_y: yd) if ps.size > 1
      # depth dimension at the end of the run
      xe = sh.rtl ? ox - 6 : ox + len * k + 6
      sh.dim_v(oy, oy + depth * k, xe, ED.fmt(depth), from_x: sh.rtl ? ox : ox + len * k, side: sh.rtl ? :left : :right)
      # unit widths under the plan
      yb = oy + depth * k + 8
      units.each { |u| a, w = rx.call(*u['along']); sh.dim_h(a, a + w, yb, ED.fmt(u['w']), from_y: oy + [u['d'].to_f, depth].min * k) }
      sh.text(sh.rtl ? ax1 - 2 : ax0 + 2, ay0 + 5, tx(lang, 'Datum: wall face. Depth measured from the wall; X measured along the run from the run start.', 'المرجع: وجه الحائط. العمق من الحائط و X على امتداد الصف من بدايته.'), size: 2.6, anchor: :left, color: '#444')
      # enlarged cutout details (own scale per cutout: same data, larger scale)
      unless cuts.empty?
        top = [yb + 14, ay0 + plan_h + 8].min
        cell_w = (ax1 - ax0 - 4) / [cuts.size, 3].min
        cuts.first(3).each_with_index do |c, i|
          cx0 = ax0 + 2 + i * cell_w
          cw = cell_w - 4
          ch = ay1 - top - 2
          sh.rect(cx0, top, cw, ch, stroke: '#0b57d0', sw: 0.25, dash: '1.6 0.9')
          sh.text(sh.rtl ? cx0 + cw - 2 : cx0 + 2, top + 5, "#{tx(lang, 'DETAIL', 'تفصيل')} #{('A'.ord + i).chr} - #{c[:code]} #{tx(lang, c[:kind] == :sink ? 'SINK CUTOUT' : 'HOB CUTOUT', c[:kind] == :sink ? 'فتحة الحوض' : 'فتحة الموقد')}", size: 3.0, bold: true, anchor: :left)
          pad = c[:off_unit]
          dn = ED.pick_scale(c[:w] + 2 * pad, c[:d] + c[:d0] + 40, cw - 44, ch - 40, [2, 2.5, 4, 5, 8, 10, 12.5, 15, 20])
          dk = 1.0 / dn
          fx0 = cx0 + 22
          fy0 = top + 16
          # slab edge strip (wall at top)
          wx = ->(a) { sh.rtl ? fx0 + (c[:w] + 2 * pad) * dk - (a + pad) * dk : fx0 + (a + pad) * dk }
          sw_ = sh.rtl ? wx.call(c[:w]) : wx.call(0)
          sh.rect(fx0, fy0, (c[:w] + 2 * pad) * dk, (c[:d0] + c[:d] + 40) * dk, fill: '#cfd3d8', stroke: '#111', sw: 0.3)
          sh.text(fx0 + (c[:w] + 2 * pad) * dk / 2.0, fy0 - 2, tx(lang, 'WALL SIDE', 'جهة الحائط'), size: 2.2, anchor: :center, color: '#555')
          if c[:shape] == 'round'
            sh.circle(sw_ + c[:w] * dk / 2.0, fy0 + (c[:d0] + c[:d] / 2.0) * dk, c[:w] * dk / 2.0, fill: '#fff', stroke: '#b42318', sw: 0.35, dash: '1.6 0.9')
            sh.text(sw_ + c[:w] * dk / 2.0, fy0 + (c[:d0] + c[:d] / 2.0) * dk, "Ø #{ED.fmt(c[:w])}", size: 2.6, anchor: :center, bold: true, color: '#b42318')
          else
            sh.rect(sw_, fy0 + c[:d0] * dk, c[:w] * dk, c[:d] * dk, fill: '#fff', stroke: '#b42318', sw: 0.35, dash: '1.6 0.9')
          end
          if c[:status] == Kitchen::CUTOUT_REQUIRED # no cutting dimensions are given for an opening that has no template yet
            mx = sw_ + c[:w] * dk / 2.0
            my = fy0 + (c[:d0] + c[:d] / 2.0) * dk
            sh.text(mx, my - 3, Kitchen::CUTOUT_REQUIRED, size: 2.6, anchor: :center, bold: true, color: '#b42318')
            sh.text(mx, my + 1.5, "#{c[:product]}  #{ED.fmt(c[:overall][0])} x #{ED.fmt(c[:overall][1])} #{tx(lang, 'overall', 'المقاس الكلي')}", size: 2.2, anchor: :center, color: '#111')
            sh.text(mx, my + 5.5, tx(lang, 'Opening shown is indicative - cut from the sink template only', 'الفتحة المرسومة استرشادية - القطع من باترون الحوض فقط'), size: 2.0, anchor: :center, color: '#b42318')
          else
            sh.dim_h(sw_, sw_ + c[:w] * dk, fy0 + (c[:d0] + c[:d]) * dk + 9, ED.fmt(c[:w]), from_y: fy0 + (c[:d0] + c[:d]) * dk)
            sh.dim_h(fx0, fx0 + pad * dk, fy0 + (c[:d0] + c[:d]) * dk + 22, ED.fmt(pad), from_y: fy0 + (c[:d0] + c[:d]) * dk + 9) if !sh.rtl && pad * dk > 1
            dx = sh.rtl ? sw_ + c[:w] * dk + 8 : sw_ - 8
            sh.dim_v(fy0 + c[:d0] * dk, fy0 + (c[:d0] + c[:d]) * dk, dx, ED.fmt(c[:d]), from_x: sh.rtl ? sw_ + c[:w] * dk : sw_, side: sh.rtl ? :right : :left)
            dx2 = sh.rtl ? sw_ + c[:w] * dk + 16 : sw_ - 16
            sh.dim_v(fy0, fy0 + c[:d0] * dk, dx2, ED.fmt(c[:d0]), from_x: sh.rtl ? sw_ + c[:w] * dk : sw_, side: sh.rtl ? :right : :left)
          end
          sh.text(sh.rtl ? cx0 + cw - 2 : cx0 + 2, ay1 - 3, "#{tx(lang, 'Scale', 'المقياس')} #{ED.scale_label(dn)}   #{tx(lang, 'unit width', 'عرض الوحدة')} #{ED.fmt(c[:unit_w])}", size: 2.4, anchor: :left, color: '#444')
        end
      end
      [sh]
    end
  end
end
