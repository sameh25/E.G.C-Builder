# frozen_string_literal: true

require 'cgi'

module EGC
  # FACTORY WORK ORDER: one printable document a workshop can run a job from. Everything in it is read from the same analysis the cut list,
  # the nesting DXF and the CNC files use (Cutlist.analyse) - nothing is typed twice and nothing is estimated:
  #   1. boards to issue, counted in SHEETS per board type (never in square metres), with the waste and the offcut that comes back to stock;
  #   2. the units of the job;
  #   3. sheet by sheet: the cutting layout and the list of the pieces cut from that sheet (cut size, finished size, edge banding);
  #   4. drilling and grooving of every piece (hinge cups, handle screws, shelf pins, grooves) in the finished piece's own coordinates;
  #   5. edge banding in metres, hardware in pieces.
  module WorkOrder
    module_function

    TXT = {
      'en' => { title: 'Factory work order', order: 'Order', project: 'Project', date: 'Date', units: 'Units', pieces: 'Pieces', sheets: 'Sheets', boards: '1. Boards to issue (by the sheet)',
                board: 'Board', thk: 'Thickness', stock: 'Sheet size', qty_sheets: 'Sheets', used: 'Used', waste: 'Waste', offcut: 'Largest offcut back to stock', oversize: 'LARGER THAN THE SHEET - order a bigger board or split',
                unit_list: '2. Units of this job', code: 'Unit', type: 'Type', size: 'W x H x D', cutting: '3. Cutting, sheet by sheet', sheet: 'Sheet', of: 'of', piece: 'Piece', part: 'Part',
                cut: 'Cut size', fin: 'Finished size', turned: 'Turned', band: 'Edge banding', notes: 'Notes', drill: '4. Drilling and grooving', op: 'Operation', along: 'Along length', across: 'Across width',
                dia: 'Dia', depth: 'Depth', n: 'No.', edges: '5. Edge banding', metres: 'm', hardware: '6. Hardware', item: 'Item', qty: 'Quantity', handle: 'Handle type', none: 'nothing to cut: build at least one unit first',
                maps: 'Drilling maps', legend: 'Blue = 5 mm, green = 8 mm, red = 35 mm hinge cup, orange = groove / notch. Figures: along the length (below) and across the width (beside).',
                coords: 'Positions are measured on the finished piece: along its length from one end, across its width from one edge. Hinge cups are bored from the back face.',
                long: 'long', short: 'short', sides: 'side(s)', prepared: 'Prepared by', approved: 'Approved (factory)', received: 'Received (workshop)', layout: 'Layout', yes: 'yes', pcs: 'pcs', groove: 'groove', through: 'through' },
      'ar' => { title: 'أمر تشغيل للمصنع', order: 'رقم الأمر', project: 'المشروع', date: 'التاريخ', units: 'الوحدات', pieces: 'القطع', sheets: 'الألواح', boards: '1. الألواح المطلوب صرفها (بالعدد)',
                board: 'نوع اللوح', thk: 'السُمك', stock: 'مقاس اللوح', qty_sheets: 'عدد الألواح', used: 'المستخدم', waste: 'الهادر', offcut: 'أكبر فضلة ترجع المخزن', oversize: 'أكبر من اللوح - اطلب لوح أكبر أو قسّم القطعة',
                unit_list: '2. وحدات الأمر', code: 'الوحدة', type: 'النوع', size: 'عرض × ارتفاع × عمق', cutting: '3. التقطيع لوح بلوح', sheet: 'لوح', of: 'من', piece: 'القطعة', part: 'الاسم',
                cut: 'مقاس القص', fin: 'المقاس النهائي', turned: 'ملفوفة', band: 'شريط الحرف', notes: 'ملاحظات', drill: '4. الحفر والمجاري', op: 'العملية', along: 'على الطول', across: 'على العرض',
                dia: 'القطر', depth: 'العمق', n: 'العدد', edges: '5. شريط الحرف', metres: 'متر', hardware: '6. الإكسسوارات', item: 'الصنف', qty: 'الكمية', handle: 'نوع المقبض', none: 'لا توجد قطع: ابنِ وحدة واحدة على الأقل',
                maps: 'خرائط الحفر', legend: 'الأزرق Ø5، الأخضر Ø8، الأحمر كوباية مفصلة Ø35، البرتقالي مجرى أو قطع. الأرقام: على الطول (تحت) وعلى العرض (جنب).',
                coords: 'المواضع مقاسة على القطعة بعد التشطيب: على الطول من أحد الطرفين، وعلى العرض من أحد الحرفين. كوباية المفصلة تُحفر من الوش الخلفي.',
                long: 'طول', short: 'عرض', sides: 'حرف', prepared: 'إعداد', approved: 'اعتماد المصنع', received: 'استلام الورشة', layout: 'طريقة الرص', yes: 'نعم', pcs: 'قطعة', groove: 'مجرى', through: 'نافذ' }
    }.freeze

    CSS = <<~CSS
      <style>
      *{box-sizing:border-box}body{font-family:'Segoe UI',Tahoma,Arial,sans-serif;color:#1d2330;margin:0;background:#eef0f4}
      .wrap{max-width:1180px;margin:0 auto;padding:22px;background:#fff}
      header{display:flex;justify-content:space-between;align-items:flex-end;border-bottom:4px solid #b8862b;padding-bottom:12px;margin-bottom:14px;gap:16px}
      h1{margin:2px 0 0;font-size:28px}h2{font-size:18px;margin:26px 0 8px;padding:6px 10px;background:#1d2330;color:#fff;border-radius:4px}
      h3{font-size:15px;margin:18px 0 6px;color:#7a5612}.brand{color:#b8862b;font-weight:700;letter-spacing:.5px}
      .meta{font-size:13px;line-height:1.7;text-align:end}.cards{display:flex;gap:10px;flex-wrap:wrap;margin:8px 0}
      .card{flex:1;min-width:130px;border:1px solid #d9dce3;border-radius:8px;padding:10px 12px}.card b{display:block;font-size:24px}.card span{font-size:12px;color:#5d6577}
      table{border-collapse:collapse;width:100%;font-size:12.5px;margin:6px 0 12px}th,td{border:1px solid #cfd3dc;padding:4px 7px;text-align:start;vertical-align:top}
      th{background:#f1ede2}td.n,th.n{text-align:center;white-space:nowrap}tr.big td{font-size:15px;font-weight:700}
      .sheetbox{border:1px solid #cfd3dc;border-radius:6px;padding:10px;margin:10px 0;page-break-inside:avoid}.sheet{max-width:100%;height:auto;display:block;margin:6px 0}
      .maps{display:flex;flex-wrap:wrap;gap:8px}.map{border:1px solid #cfd3dc;border-radius:6px;padding:6px 8px;font-size:12px;page-break-inside:avoid}.dmap{display:block;margin:4px 0}
      .warn{background:#fdecea;border:1px solid #e0a39c;padding:8px 10px;border-radius:6px;font-weight:700}.note{font-size:12px;color:#5d6577}
      .sign{display:flex;gap:18px;margin-top:34px}.sign div{flex:1;border-top:1px solid #1d2330;padding-top:6px;font-size:13px}
      .mat{page-break-before:always}@media print{body{background:#fff}.wrap{padding:0;max-width:none}h2{-webkit-print-color-adjust:exact;print-color-adjust:exact}}
      </style>
    CSS

    def h(v)
      CGI.escapeHTML(v.to_s)
    end

    def num(v, d = 0)
      format("%.#{d}f", v.to_f).sub(/\.0+\z/, '')
    end

    def order_no(time = Time.now)
      "WO-#{time.strftime('%Y%m%d-%H%M')}"
    end

    # the drilling / grooving operations of one nested piece, from the CNC feature list (so the paper and the machine file agree)
    def operations(item, tx)
      f = Cam.features(item)
      ops = f[:circles].group_by { |c| [c[0], c[3].round(1), c[4].round(1)] }.map do |(layer, dia, depth), list|
        { op: layer, dia: dia, depth: depth, n: list.size, at: list.map { |c| [c[1].round(1), c[2].round(1)] }.sort }
      end
      f[:rects].each do |r|
        ops << { op: "#{tx[:groove]} #{r[0]}", dia: nil, depth: r[5], n: 1, at: [[r[1].round(1), r[2].round(1)], [r[3].round(1), r[4].round(1)]], rect: true }
      end
      [ops, f[:notes]]
    rescue StandardError => e
      [[], ["operations not available: #{e.message}"]]
    end

    def band(item, tx)
      t = item[:eb_t].to_f
      l = item[:eb_l].to_i
      w = item[:eb_w].to_i
      return '' if t <= 0 || (l + w).zero?

      [l.positive? ? "#{l} #{tx[:long]}" : nil, w.positive? ? "#{w} #{tx[:short]}" : nil].compact.join(' + ') + " (#{num(t, 1)} mm)"
    end

    def html(res, cfg, lang = 'en', title = nil, time = Time.now)
      lang = TXT.key?(lang) ? lang : 'en'
      tx = TXT[lang]
      ar = lang == 'ar'
      title = title.to_s.empty? ? 'E.G.C Kitchen' : title.to_s
      names = cfg['mat_names'] || {}
      nest = res[:nest] || {}
      s = +"<!doctype html><html lang='#{lang}' dir='#{ar ? 'rtl' : 'ltr'}'><head><meta charset='utf-8'><title>#{h(tx[:title])} #{h(order_no(time))}</title>#{CSS}</head><body><div class='wrap'>"
      s << "<header><div><div class='brand'>E.G.C Builder</div><h1>#{h(tx[:title])}</h1></div><div class='meta'>#{h(tx[:order])}: <b>#{h(order_no(time))}</b><br>#{h(tx[:project])}: <b>#{h(title)}</b><br>#{h(tx[:date])}: #{time.strftime('%Y-%m-%d')}<br>#{h(tx[:handle])}: #{h(cfg['handle'])}</div></header>"
      if nest.empty? || (res[:rows] || []).empty?
        s << "<p class='warn'>#{h(tx[:none])}</p></div></body></html>"
        return s
      end
      pieces = nest.values.sum { |n| n[:items].size }
      sheets = nest.values.sum { |n| n[:sheets].size }
      s << "<section class='cards'><div class='card'><b>#{(res[:cabs] || []).size}</b><span>#{h(tx[:units])}</span></div><div class='card'><b>#{pieces}</b><span>#{h(tx[:pieces])}</span></div><div class='card'><b>#{sheets}</b><span>#{h(tx[:sheets])}</span></div></section>"

      # ---- 1. boards, by the sheet
      s << "<h2>#{h(tx[:boards])}</h2><table><tr><th>#{h(tx[:board])}</th><th class='n'>#{h(tx[:thk])}</th><th class='n'>#{h(tx[:stock])}</th><th class='n'>#{h(tx[:qty_sheets])}</th><th class='n'>#{h(tx[:pieces])}</th><th class='n'>#{h(tx[:waste])}</th><th>#{h(tx[:offcut])}</th></tr>"
      nest.each do |(mat, thk), n|
        off = n[:sheets].map { |sh| sh[:offcut] || [0, 0] }.max_by { |l, w| l * w } || [0, 0]
        s << "<tr class='big'><td>#{h(names[mat] || mat)}</td><td class='n'>#{num(thk, 1)} mm</td><td class='n'>#{num(n[:sheet][0])} × #{num(n[:sheet][1])}</td><td class='n'>#{n[:sheets].size}</td><td class='n'>#{n[:items].size}</td><td class='n'>#{num(n[:waste], 1)} %</td><td>#{off[0]} × #{off[1]} mm</td></tr>"
        next if n[:oversize].empty?

        s << "<tr><td colspan='7' class='warn'>#{h(tx[:oversize])}: #{n[:oversize].map { |it| "#{h(it[:id])} (#{num(it[:l])} × #{num(it[:w])})" }.join(', ')}</td></tr>"
      end
      s << '</table>'

      # ---- 2. units
      s << "<h2>#{h(tx[:unit_list])}</h2><table><tr><th class='n'>#{h(tx[:code])}</th><th>#{h(tx[:type])}</th><th class='n'>#{h(tx[:size])}</th></tr>"
      (res[:cabs] || []).sort_by { |c| c[:code].to_s[/\d+/].to_i }.each do |c|
        s << "<tr><td class='n'><b>#{h(c[:code])}</b></td><td>#{h(c[:type])} (#{h(c[:kind])})</td><td class='n'>#{num(c[:w])} × #{num(c[:h])} × #{num(c[:d])}</td></tr>"
      end
      s << '</table>'

      # ---- 3. cutting, sheet by sheet
      s << "<h2>#{h(tx[:cutting])}</h2>"
      nest.each_with_index do |((mat, thk), n), mi|
        s << "<div class='#{mi.zero? ? '' : 'mat'}'><h3>#{h(names[mat] || mat)} — #{num(thk, 1)} mm — #{n[:sheets].size} × (#{num(n[:sheet][0])} × #{num(n[:sheet][1])})</h3>"
        s << "<p class='note'>#{h(tx[:layout])}: #{h(n[:strategy])}</p>" if n[:strategy]
        n[:sheets].each_with_index do |sh, si|
          off = sh[:offcut] || [0, 0]
          s << "<div class='sheetbox'><b>#{h(tx[:sheet])} #{si + 1} #{h(tx[:of])} #{n[:sheets].size}</b> — #{sh[:placed].size} #{h(tx[:pcs])} — #{h(tx[:offcut])}: #{off[0]} × #{off[1]} mm"
          s << Nesting.svg(sh, n[:sheet][0], n[:sheet][1], 1000)
          s << "<table><tr><th class='n'>#{h(tx[:piece])}</th><th class='n'>#{h(tx[:code])}</th><th>#{h(tx[:part])}</th><th class='n'>#{h(tx[:cut])}</th><th class='n'>#{h(tx[:fin])}</th><th class='n'>#{h(tx[:turned])}</th><th>#{h(tx[:band])}</th><th>#{h(tx[:notes])}</th></tr>"
          sh[:placed].sort_by { |p| [p[:y], p[:x]] }.each do |p|
            it = p[:item]
            s << "<tr><td class='n'><b>#{h(it[:id])}</b></td><td class='n'>#{h(it[:code])}</td><td>#{h(I18n.part(it[:part], lang))}</td><td class='n'>#{num(it[:l], 1)} × #{num(it[:w], 1)}</td><td class='n'>#{num(it[:fin_l], 1)} × #{num(it[:fin_w], 1)}</td><td class='n'>#{p[:rotated] ? h(tx[:yes]) : ''}</td><td>#{h(band(it, tx))}</td><td>#{h(it[:notes])}</td></tr>"
          end
          s << '</table></div>'
        end
        s << '</div>'
      end

      # ---- 4. drilling and grooving
      s << "<div class='mat'><h2>#{h(tx[:drill])}</h2><p class='note'>#{h(tx[:coords])}</p><table><tr><th class='n'>#{h(tx[:piece])}</th><th class='n'>#{h(tx[:code])}</th><th>#{h(tx[:part])}</th><th>#{h(tx[:op])}</th><th class='n'>#{h(tx[:dia])}</th><th class='n'>#{h(tx[:depth])}</th><th class='n'>#{h(tx[:n])}</th><th>#{h(tx[:along])} / #{h(tx[:across])} (mm)</th></tr>"
      nest.each_value do |n|
        n[:items].sort_by { |it| it[:id].to_s }.each do |it|
          ops, notes = operations(it, tx)
          ops.each do |o|
            deep = o[:depth].to_f >= it[:thk].to_f - 0.01 ? "#{num(o[:depth], 1)} (#{tx[:through]})" : num(o[:depth], 1)
            s << "<tr><td class='n'><b>#{h(it[:id])}</b></td><td class='n'>#{h(it[:code])}</td><td>#{h(I18n.part(it[:part], lang))}</td><td>#{h(o[:op])}</td><td class='n'>#{o[:dia] ? num(o[:dia], 1) : ''}</td><td class='n'>#{deep}</td><td class='n'>#{o[:n]}</td><td>#{o[:at].map { |u, v| "#{num(u, 1)} / #{num(v, 1)}" }.join(o[:rect] ? ' → ' : '  ·  ')}</td></tr>"
          end
          notes.each { |nt| s << "<tr><td class='n'><b>#{h(it[:id])}</b></td><td class='n'>#{h(it[:code])}</td><td>#{h(I18n.part(it[:part], lang))}</td><td colspan='5' class='warn'>#{h(nt)}</td></tr>" }
        end
      end
      s << '</table>'
      # the same operations drawn: one map per piece that is drilled or grooved
      s << "<h3>#{h(tx[:maps])}</h3><p class='note'>#{h(tx[:legend])}</p><div class='maps'>"
      nest.each_value do |n|
        n[:items].sort_by { |it| it[:id].to_s }.each do |it|
          m = DrillMap.svg(it)
          next if m.empty?

          s << "<div class='map'><b>#{h(it[:id])}</b> #{h(it[:code])} — #{h(I18n.part(it[:part], lang))}<br>#{m}<div class='note'>#{h(DrillMap.summary(DrillMap.data(it)))}</div></div>"
        end
      end
      s << '</div></div>'

      # ---- 5. edge banding, 6. hardware
      s << "<h2>#{h(tx[:edges])}</h2><table><tr><th>#{h(tx[:band])}</th><th class='n'>#{h(tx[:metres])}</th></tr>"
      (res[:edge] || {}).select { |_, m| m.to_f.positive? }.sort.each { |t, m| s << "<tr><td>#{num(t, 1)} mm</td><td class='n'>#{num(m.ceil)}</td></tr>" }
      s << "</table><h2>#{h(tx[:hardware])}</h2><table><tr><th>#{h(tx[:item])}</th><th class='n'>#{h(tx[:qty])}</th></tr>"
      (res[:hw] || {}).select { |_, v| v.to_f.positive? }.sort_by { |k, _| k.to_s }.each do |k, v|
        metres = k.to_s.end_with?('_mm')
        key = metres ? k.to_s.sub(/_mm\z/, '_m') : k.to_s
        # lengths (handle / LED profile) as they are needed - the exact mm and the metres, never rounded up to whole metres (a 600 unit needs
        # 597 mm of profile, not "1 m")
        s << "<tr><td>#{h(I18n.t(key, lang))}</td><td class='n'>#{metres ? "#{num(v.to_f.round)} mm (#{format('%.2f', v.to_f / 1000.0)} #{tx[:metres]})" : num(v.to_f.ceil)}</td></tr>"
      end
      mark = defined?(License) ? License.build_mark : ''
      s << "</table>#{mark.empty? ? '' : "<p class='note'>#{h(mark)}</p>"}<div class='sign'><div>#{h(tx[:prepared])}</div><div>#{h(tx[:approved])}</div><div>#{h(tx[:received])}</div></div></div></body></html>"
      s
    end
  end
end
