# frozen_string_literal: true

require 'cgi'

module EGC
  module Report
    module_function

    def h(s)
      CGI.escapeHTML(s.to_s)
    end

    def num(v, d = 0)
      format("%.#{d}f", v.to_f).sub(/\.0+$/, '').sub(/(\.\d*?)0+$/, '\1')
    end

    def html(out, lang = 'en', title = nil)
      cfg = out[:cfg]
      t = ->(k) { I18n.t(k, lang) }
      dir = lang == 'ar' ? 'rtl' : 'ltr'
      title ||= Sketchup.active_model.title.to_s
      title = 'E.G.C Kitchen' if title.empty?
      rows = out[:rows]
      total_parts = EGC::Num.sum(rows) { |r| r[:qty] }
      sheets = EGC::Num.sum(out[:nest].values) { |n| n[:sheets].size }
      net = EGC::Num.sum(out[:area].values)
      cur = out[:cost][:currency]
      s = +"<!doctype html><html lang='#{lang}' dir='#{dir}'><head><meta charset='utf-8'><title>#{h(t['report'])}</title>"
      s << CSS
      s << "</head><body><div class='wrap'>"
      s << Costing.incomplete_banner(Costing.internal(out, cfg, lang), lang)
      s << "<header><div><div class='brand'>E.G.C <b>Builder</b></div><h1>#{h(t['report'])}</h1></div>"
      s << "<div class='meta'>#{h(t['project'])}: <b>#{h(title)}</b><br>#{h(t['date'])}: #{Time.now.strftime('%Y-%m-%d')}</div></header>"
      if rows.empty?
        s << "<p class='warn'>#{h(t['nothing'])}</p></div></body></html>"
        return s
      end
      s << "<section class='cards'>"
      [[t['parts_total'], total_parts], [t['net_area'], num(net, 2)], [t['sheets'], sheets],
       [t['cost'], "#{num(out[:cost][:total], 0)} #{h(cur)}"]].each do |k, v|
        s << "<div class='card'><div class='k'>#{h(k)}</div><div class='v'>#{v}</div></div>"
      end
      s << '</section>'

      # cabinets
      s << "<h2>#{h(t['cabinets'])} (#{out[:cabs].size})</h2><table><tr><th>#{h(t['name'])}</th><th>#{h(t['size'])}</th></tr>"
      out[:cabs].each do |c|
        s << "<tr><td>#{h(c[:name])}</td><td>#{num(c[:w])} × #{num(c[:h])} × #{num(c[:d])}</td></tr>"
      end
      s << '</table>'

      # cut list per material
      s << "<h2>#{h(t['cutlist'])}</h2>"
      rows.group_by { |r| [r[:mat], r[:thk]] }.each do |(mat, thk), rs|
        area = EGC::Num.sum(rs) { |r| r[:len] * r[:wid] * r[:qty] } / 1_000_000.0
        s << "<h3>#{h(cfg['mat_names'][mat] || mat)} — #{num(thk, 1)} mm <span class='sub'>#{num(area, 2)} m²</span></h3>"
        s << "<table><tr><th>#</th><th>#{h(t['part'])}</th><th>#{h(t['len'])}</th><th>#{h(t['wid'])}</th><th>#{h(t['qty'])}</th>"
        s << "<th>#{h(t['edge'])}</th><th>#{h(t['groove'])}</th></tr>"
        rs.each_with_index do |r, i|
          eb = (r[:eb_l].zero? && r[:eb_w].zero?) ? '' : "L×#{r[:eb_l]} W×#{r[:eb_w]} (#{num(r[:eb_t], 1)})"
          s << "<tr><td>#{i + 1}</td><td>#{h(I18n.part(r[:part], lang))}</td><td>#{num(r[:len], 1)}</td><td>#{num(r[:wid], 1)}</td>"
          s << "<td><b>#{r[:qty]}</b></td><td>#{h(eb)}</td><td>#{h([r[:groove], r[:notes]].compact.join(' | '))}</td></tr>"
        end
        s << '</table>'
      end

      # edge banding
      s << "<h2>#{h(t['edging'])}</h2><table><tr><th>mm</th><th>m</th></tr>"
      out[:edge].each { |k, v| s << "<tr><td>#{num(k, 1)}</td><td>#{num(v, 1)}</td></tr>" }
      s << '</table>'

      # hardware + appliances
      s << "<h2>#{h(t['hardware'])}</h2><table><tr><th>#{h(t['item'])}</th><th>#{h(t['count'])}</th></tr>"
      (out[:hw_view] || out[:hw]).each do |k, v|
        next if v <= 0

        s << "<tr><td>#{h(I18n.t(k, lang))}</td><td>#{num(v, 2)}</td></tr>"
      end
      s << '</table>'
      unless out[:apps].empty?
        s << "<h2>#{h(t['appliances'])}</h2><table><tr><th>#{h(t['item'])}</th><th>#{h(t['count'])}</th></tr>"
        out[:apps].each { |k, v| s << "<tr><td>#{h(I18n.app(k, lang))}</td><td>#{v}</td></tr>" }
        s << '</table>'
      end

      # cost
      s << "<h2>#{h(t['cost'])}</h2><table><tr><th>#{h(t['item'])}</th><th>#{h(t['count'])}</th><th>#{h(t['price'])}</th>"
      s << "<th>#{h(t['amount'])} (#{h(cur)})</th></tr>"
      out[:cost][:lines].each do |l|
        name = l[:cat] == 'hw' ? I18n.t(l[:key], lang) : l[:item]
        s << "<tr><td>#{h(name)}</td><td>#{num(l[:qty], 2)} #{h(l[:unit])}</td><td>#{num(l[:price], 2)}</td><td>#{num(l[:amount], 0)}</td></tr>"
      end
      if out[:cost][:labor] > 0
        s << "<tr><td>#{h(t['labor'])}</td><td></td><td>#{num(cfg['labor_pct'], 1)}%</td><td>#{num(out[:cost][:labor], 0)}</td></tr>"
      end
      s << "<tr class='tot'><td colspan='3'>#{h(t['total'])}</td><td>#{num(out[:cost][:total], 0)} #{h(cur)}</td></tr></table>"

      # nesting
      s << "<h2>#{h(t['nesting'])}</h2><p class='sub'>#{h(t['stock_by_material'])} — #{h(t['kerf'])}: #{num(cfg['kerf'])} mm</p>"
      out[:nest].each do |(mat, thk), n|
        s << "<h3>#{h(cfg['mat_names'][mat] || mat)} (#{num(n[:sheet][0])}×#{num(n[:sheet][1])}) — #{n[:sheets].size} #{h(t['sheets'])} · #{h(t['waste'])} #{num(n[:waste], 1)}%</h3>"
        unless n[:oversize].empty?
          s << "<p class='warn'>#{h(t['oversize'])}: #{n[:oversize].map { |o| "#{o[:id]} (#{num(o[:l])}×#{num(o[:w])})" }.join(', ')}</p>"
        end
        n[:sheets].each_with_index do |sh, i|
          s << "<div class='sheetbox'><div class='sub'>#{h(t['sheet'])} #{i + 1} · #{h(t['waste'])} #{num(sh[:waste_pct], 1)}%</div>#{Nesting.svg(sh, n[:sheet][0], n[:sheet][1])}</div>"
        end
        s << "<table class='legend'><tr><th>ID</th><th>#{h(t['part'])}</th><th>#{h(t['len'])}</th><th>#{h(t['wid'])}</th></tr>"
        n[:items].sort_by { |it| it[:id] }.each do |it|
          s << "<tr><td>#{it[:id]}</td><td>#{h(I18n.part(it[:part], lang))}</td><td>#{num(it[:l], 1)}</td><td>#{num(it[:w], 1)}</td></tr>"
        end
        s << '</table>'
      end
      s << '</div></body></html>'
      s
    end

    CSS = <<~CSS
      <style>
      :root{--ink:#1c1f24;--mut:#6b7280;--line:#e5e7eb;--acc:#b8862b;--bg:#fafaf7}
      *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 "Segoe UI",Tahoma,Arial,sans-serif}
      .wrap{max-width:1000px;margin:0 auto;padding:28px 20px}
      header{display:flex;justify-content:space-between;align-items:flex-end;border-bottom:3px solid var(--acc);padding-bottom:12px;margin-bottom:18px}
      .brand{letter-spacing:.18em;font-size:12px;color:var(--mut)}.brand b{color:var(--acc)}h1{margin:2px 0 0;font-size:24px}
      .meta{font-size:13px;color:var(--mut);text-align:end}h2{margin:28px 0 8px;font-size:18px;border-inline-start:4px solid var(--acc);padding-inline-start:10px}
      h3{margin:18px 0 6px;font-size:15px}.sub{color:var(--mut);font-weight:400;font-size:12px}
      .cards{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}.card{background:#fff;border:1px solid var(--line);border-radius:10px;padding:12px}
      .card .k{color:var(--mut);font-size:12px}.card .v{font-size:22px;font-weight:700;margin-top:2px}
      table{width:100%;border-collapse:collapse;background:#fff;border:1px solid var(--line);border-radius:8px;overflow:hidden;font-size:13px}
      th,td{padding:6px 10px;border-bottom:1px solid var(--line);text-align:start}th{background:#f3efe4;font-weight:600}
      tr.tot td{font-weight:700;background:#f3efe4;font-size:15px}.warn{color:#b42318;font-weight:600}
      .sheetbox{margin:8px 0}.sheet{max-width:100%;height:auto;border-radius:4px}.legend{margin-top:8px}
      @media print{body{background:#fff}.wrap{padding:0}h2{break-after:avoid}.sheetbox{break-inside:avoid}}
      </style>
    CSS
  end
end
