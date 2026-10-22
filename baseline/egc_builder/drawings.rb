# frozen_string_literal: true

require 'cgi'
require 'json'

module EGC
  # Shop drawings: front / side / plan views + part table, generated from the real geometry.
  module Drawings
    module_function

    def h(s)
      CGI.escapeHTML(s.to_s)
    end

    # Collect part boxes in cabinet-local mm: { part, role, mat, pid, x0,x1,d0,d1,z0,z1 }
    def boxes(ents, t = Geom::Transformation.new, acc = [])
      ents.each do |g|
        next unless g.is_a?(Sketchup::Group)

        d = g.attribute_dictionary('egc')
        tt = t * g.transformation
        if d && d['role']
          bb = g.definition.bounds
          xs = []
          ys = []
          zs = []
          [bb.min.x, bb.max.x].each do |x|
            [bb.min.y, bb.max.y].each do |y|
              [bb.min.z, bb.max.z].each do |z|
                p = tt * Geom::Point3d.new(x, y, z)
                xs << p.x.to_mm
                ys << p.y.to_mm
                zs << p.z.to_mm
              end
            end
          end
          acc << { part: d['part'], role: d['role'], mat: d['mat'], pid: d['pid'], x0: xs.min, x1: xs.max, d0: -ys.max, d1: -ys.min,
                   z0: zs.min, z1: zs.max, len: d['len'], wid: d['wid'], thk: d['thk'], eb_l: d['eb_l'], eb_w: d['eb_w'], notes: d['notes'],
                   groove: d['groove'], bore: d['bore'], ex: d['ex'] }
        else
          boxes(g.entities.to_a, tt, acc)
        end
      end
      acc
    end

    COLORS = { 'front' => '#c9a06a', 'carcass' => '#f4f2ea', 'back' => '#e4dfd0', 'drawer' => '#efece2', 'top' => '#2a2a2c',
               'appliance' => '#c9ced3', 'profile' => '#222', 'glass' => '#bfe0ee', 'splash' => '#ddd' }.freeze

    def color(b, cfg)
      return '#9aa1a8' if b[:role] == 'hw'
      return cfg['front_color'] if b[:mat] == 'front'

      COLORS[b[:mat]] || '#eee'
    end

    def dim_h(x1, x2, y, label)
      "<g class='dim'><line x1='#{x1}' y1='#{y}' x2='#{x2}' y2='#{y}'/><line x1='#{x1}' y1='#{y - 5}' x2='#{x1}' y2='#{y + 5}'/><line x1='#{x2}' y1='#{y - 5}' x2='#{x2}' y2='#{y + 5}'/>" \
        "<text x='#{(x1 + x2) / 2.0}' y='#{y - 4}' text-anchor='middle'>#{label}</text></g>"
    end

    def dim_v(x, y1, y2, label)
      "<g class='dim'><line x1='#{x}' y1='#{y1}' x2='#{x}' y2='#{y2}'/><line x1='#{x - 5}' y1='#{y1}' x2='#{x + 5}' y2='#{y1}'/><line x1='#{x - 5}' y1='#{y2}' x2='#{x + 5}' y2='#{y2}'/>" \
        "<text transform='translate(#{x - 5},#{(y1 + y2) / 2.0}) rotate(-90)' text-anchor='middle'>#{label}</text></g>"
    end

    # view: :front (x,z) :side (d,z) :plan (x,d)
    def view_svg(bs, view, cfg, maxpx = 300)
      case view
      when :front then a0, a1, b0, b1 = :x0, :x1, :z0, :z1
      when :side then a0, a1, b0, b1 = :d0, :d1, :z0, :z1
      else a0, a1, b0, b1 = :x0, :x1, :d0, :d1
      end
      minA = bs.map { |b| b[a0] }.min
      maxA = bs.map { |b| b[a1] }.max
      minB = bs.map { |b| b[b0] }.min
      maxB = bs.map { |b| b[b1] }.max
      spanA = [maxA - minA, 1].max
      spanB = [maxB - minB, 1].max
      sc = maxpx / [spanA, spanB].max
      m = 40
      w = spanA * sc + 2 * m
      hgt = spanB * sc + 2 * m
      fx = ->(v) { (m + (v - minA) * sc).round(1) }
      fy = lambda do |v|
        view == :plan ? (m + (v - minB) * sc).round(1) : (m + (maxB - v) * sc).round(1)
      end
      order = bs.sort_by do |b|
        case view
        when :front then (b[:d0] + b[:d1]) / 2.0
        when :side then (b[:x0] + b[:x1]) / 2.0
        else (b[:z0] + b[:z1]) / 2.0
        end
      end
      s = +"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 #{w.round} #{hgt.round}' width='#{w.round}' height='#{hgt.round}' class='v'>"
      order.each do |b|
        y0 = view == :plan ? fy.call(b[b0]) : fy.call(b[b1])
        y1 = view == :plan ? fy.call(b[b1]) : fy.call(b[b0])
        op = b[:role] == 'hw' ? 0.55 : 1
        s << "<rect x='#{fx.call(b[a0])}' y='#{y0}' width='#{[fx.call(b[a1]) - fx.call(b[a0]), 0.6].max.round(1)}' height='#{[y1 - y0, 0.6].max.round(1)}' " \
             "fill='#{color(b, cfg)}' fill-opacity='#{op}' stroke='#444' stroke-width='0.6'/>"
      end
      s << dim_h(fx.call(minA), fx.call(maxA), (hgt - 12).round, (maxA - minA).round.to_s)
      s << dim_v(12, fy.call(view == :plan ? minB : maxB), fy.call(view == :plan ? maxB : minB), (maxB - minB).round.to_s)
      s << '</svg>'
      s
    end

    # SECTION (side, cut at the middle of the unit): boards the cut plane crosses are hatched, the sides stay as outline; the LED groove is drawn from the
    # part's own groove data (offset / width / depth) and dimensioned
    def section_svg(bs, cfg, maxpx = 300)
      minA = bs.map { |b| b[:d0] }.min
      maxA = bs.map { |b| b[:d1] }.max
      minB = bs.map { |b| b[:z0] }.min
      maxB = bs.map { |b| b[:z1] }.max
      mid = (bs.map { |b| b[:x0] }.min + bs.map { |b| b[:x1] }.max) / 2.0
      sc = maxpx / [maxA - minA, maxB - minB, 1].max
      m = 40
      w = (maxA - minA) * sc + 2 * m
      hgt = (maxB - minB) * sc + 2 * m
      fx = ->(v) { (m + (v - minA) * sc).round(1) }
      fy = ->(v) { (m + (maxB - v) * sc).round(1) }
      s = +"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 #{w.round} #{hgt.round}' width='#{w.round}' height='#{hgt.round}' class='v'>"
      s << "<defs><pattern id='ht' width='5' height='5' patternUnits='userSpaceOnUse' patternTransform='rotate(45)'><line x1='0' y1='0' x2='0' y2='5' stroke='#555' stroke-width='1'/></pattern></defs>"
      bs.sort_by { |b| (b[:x0] + b[:x1]) / 2.0 }.each do |b|
        cut = b[:x0] <= mid && b[:x1] >= mid && b[:role] != 'hw'
        next unless cut || %w[side_l side_r].include?(b[:part])

        s << "<rect x='#{fx.call(b[:d0])}' y='#{fy.call(b[:z1])}' width='#{[fx.call(b[:d1]) - fx.call(b[:d0]), 0.8].max.round(1)}' height='#{[fy.call(b[:z0]) - fy.call(b[:z1]), 0.8].max.round(1)}' " \
             "fill='#{cut ? 'url(#ht)' : 'none'}' stroke='#{cut ? '#111' : '#aaa'}' stroke-width='#{cut ? 1.2 : 0.5}'#{cut ? '' : " stroke-dasharray='3 2'"}/>"
        next unless b[:groove].to_s =~ /(\d+)x(\d+)@(\d+)/ && b[:part] == 'bottom'

        lw = Regexp.last_match(1).to_f
        ld = Regexp.last_match(2).to_f
        off = Regexp.last_match(3).to_f
        s << "<rect x='#{fx.call(off)}' y='#{fy.call(b[:z0] + ld)}' width='#{(lw * sc).round(1)}' height='#{(ld * sc).round(1)}' fill='#f5c542' stroke='#8a5a00' stroke-width='0.8'/>"
        s << "<text x='#{fx.call(off) + 4}' y='#{fy.call(b[:z0]) + 14}' font-size='9' fill='#8a5a00'>LED #{off.round}/#{lw.round}×#{ld.round}</text>"
      end
      s << dim_h(fx.call(minA), fx.call(maxA), (hgt - 12).round, (maxA - minA).round.to_s)
      s << dim_v(12, fy.call(maxB), fy.call(minB), (maxB - minB).round.to_s)
      s << '</svg>'
    end

    # EXPLODED side view: every part shifted along its own explode direction (the same table the 3D exploded view uses)
    def exploded_svg(bs, cfg, maxpx = 300, k = 320.0)
      ex = bs.map do |b|
        v = (JSON.parse(b[:ex].to_s) rescue nil) || [0, 0, 0]
        b.merge(d0: b[:d0] + v[1].to_f * k, d1: b[:d1] + v[1].to_f * k, z0: b[:z0] + v[2].to_f * k, z1: b[:z1] + v[2].to_f * k)
      end
      view_svg(ex.reject { |b| b[:role] == 'hw' }, :side, cfg, maxpx)
    end

    def drilling_rows(bs)
      hw = Cutlist.hw_bores?
      bs.select { |b| b[:bore] && !b[:bore].to_s.empty? }.flat_map do |b|
        holes = hw ? (JSON.parse(b[:bore]) rescue []) : [].reject { |hh| hh['t'].to_s == 'hinge cup' && hh['status'].to_s != 'CONFIRMED' }
        holes.group_by { |hh| [hh['t'], hh['dia'], hh['depth']] }.map do |(t, dia, depth), list|
          [b[:pid], b[:part], t, "Ø#{dia} × #{depth}", list.size, list.first(6).map { |hh| "(#{hh['x']}, #{hh['y']})" }.join(' ') + (list.size > 6 ? ' …' : '')]
        end
      end
    end

    # groups: array of E.G.C cabinet groups
    def html(groups, cfg, lang = 'en', title = nil)
      t = ->(k) { I18n.t(k, lang) }
      dir = lang == 'ar' ? 'rtl' : 'ltr'
      title ||= Sketchup.active_model.title.to_s
      s = +"<!doctype html><html lang='#{lang}' dir='#{dir}'><head><meta charset='utf-8'><title>Shop drawings</title><style>#{CSS}</style></head><body>"
      runs = (LedRun.detect(Sketchup.active_model) rescue [])
      if runs.any? && groups.any? { |g| runs.any? { |r| r['pids'].include?(g.persistent_id) } }
        s << "<section class='page'><header><div class='brand'>E.G.C <b>Builder</b></div><div><h1>#{lang == 'ar' ? 'مسارات الإضاءة LED' : 'LED runs'}</h1></div></header>"
        s << "<table><tr><th>ID</th><th>#{lang == 'ar' ? 'الوحدات' : 'Units'}</th><th>#{lang == 'ar' ? 'الطول (مم)' : 'Length (mm)'}</th><th>#{lang == 'ar' ? 'البداية' : 'Start'}</th><th>#{lang == 'ar' ? 'النهاية' : 'End'}</th></tr>"
        runs.each { |r| s << "<tr><td><b>#{h(r['id'])}</b></td><td>#{h(r['units'].join(' + '))}</td><td>#{r['length_mm']}</td><td>#{h(r['start'].map(&:round).join(', '))}</td><td>#{h(r['end'].map(&:round).join(', '))}</td></tr>" }
        s << '</table></section>'
      end
      fr = groups.empty? ? [] : (Cutlist.analyse(cfg, Sketchup.active_model, use_selection: false)[:fascia] rescue [])
      if fr.any?
        s << "<section class='page'><header><div class='brand'>E.G.C <b>Builder</b></div><div><h1>#{lang == 'ar' ? 'الوزرة العلوية (فاشيا)' : 'Top plinth / fascia'}</h1></div></header>"
        s << "<table><tr><th>ID</th><th>#{lang == 'ar' ? 'طول التصميم (مم)' : 'Design run length (mm)'}</th><th>#{lang == 'ar' ? 'الارتفاع (مم)' : 'Height (mm)'}</th><th>#{lang == 'ar' ? 'قطع التصنيع' : 'Manufacturing pieces'}</th><th>#{h(t['material'])}</th></tr>"
        fr.each { |r| s << "<tr><td><b>#{h(r['id'])}</b></td><td>#{r['length_mm']}</td><td>#{r['height_mm']}</td><td>#{r['pieces']}</td><td>#{h(cfg['mat_names'][r['mat']] || r['mat'])}</td></tr>" }
        s << '</table></section>'
      end
      groups.each_with_index do |g, i|
        bs = boxes(g.entities.to_a)
        next if bs.empty?

        parts = bs.select { |b| %w[part glass].include?(b[:role]) }
        solid = bs.reject { |b| b[:role] == 'hw' && false }
        ext = lambda do |list|
          "#{(list.map { |b| b[:x1] }.max - list.map { |b| b[:x0] }.min).round} × #{(list.map { |b| b[:z1] }.max - list.map { |b| b[:z0] }.min).round} × #{(list.map { |b| b[:d1] }.max - list.map { |b| b[:d0] }.min).round}"
        end
        # NOMINAL cabinet size = the boards (carcass + fronts + glass); the OVERALL envelope (handles, hob glass, appliances sticking out) is shown separately
        nominal = ext.call(parts.empty? ? solid : parts)
        overall = ext.call(solid)
        dims = nominal + " mm" + (overall == nominal ? "" : (lang == "ar" ? " (الشامل للمقابض والأجهزة #{overall} مم)" : " (overall incl. handles / appliances #{overall} mm)"))
        s << "<section class='page'><header><div class='brand'>E.G.C <b>Builder</b></div><div><h1>#{h(g.name)}</h1>" \
             "<div class='sub'>#{h(title)} · #{h(dims)} · #{Time.now.strftime('%Y-%m-%d')} · #{i + 1}/#{groups.size}</div></div></header>"
        if (run = runs.find { |r| r['pids'].include?(g.persistent_id) })
          s << "<div class='sub' style='color:#b8862b;font-weight:600'>#{h(run['id'])} · #{lang == 'ar' ? 'الطول' : 'Length'} = #{run['length_mm']} mm · #{run['pids'].index(g.persistent_id) + 1}/#{run['n']}</div>"
        end
        s << "<div class='views'><figure>#{view_svg(solid, :front, cfg)}<figcaption>#{lang == 'ar' ? 'واجهة أمامية' : 'Front'}</figcaption></figure>"
        s << "<figure>#{view_svg(solid, :side, cfg)}<figcaption>#{lang == 'ar' ? 'قطاع جانبي' : 'Side'}</figcaption></figure>"
        s << "<figure>#{view_svg(solid, :plan, cfg)}<figcaption>#{lang == 'ar' ? 'مسقط أفقي' : 'Plan'}</figcaption></figure>"
        s << "<figure>#{section_svg(solid, cfg)}<figcaption>#{lang == 'ar' ? 'قطاع رأسي في المنتصف' : 'Section (mid-plane)'}</figcaption></figure>"
        s << "<figure>#{exploded_svg(solid, cfg)}<figcaption>#{lang == 'ar' ? 'منظر مفكوك' : 'Exploded'}</figcaption></figure></div>"
        s << "<table><tr><th>ID</th><th>#{h(t['part'])}</th><th>#{h(t['len'])}</th><th>#{h(t['wid'])}</th><th>#{h(t['thk'])}</th><th>#{h(t['material'])}</th><th>#{h(t['edge'])}</th><th>#{h(t['groove'])}</th></tr>"
        parts.sort_by { |b| b[:pid].to_s }.each do |b|
          eb = b[:eb_l].to_i.zero? && b[:eb_w].to_i.zero? ? '' : "L×#{b[:eb_l]} W×#{b[:eb_w]}"
          s << "<tr><td>#{h(b[:pid])}</td><td>#{h(I18n.part(b[:part], lang))}</td><td>#{b[:len]}</td><td>#{b[:wid]}</td><td>#{b[:thk]}</td>" \
               "<td>#{h(cfg['mat_names'][b[:mat]] || b[:mat])}</td><td>#{h(eb)}</td><td>#{h([b[:groove], b[:notes]].compact.join(' '))}</td></tr>"
        end
        dr = drilling_rows(bs)
        unless dr.empty?
          s << "<h3 style='margin:10px 0 2px'>#{lang == 'ar' ? 'التخريم' : 'Drilling'}</h3><table><tr><th>ID</th><th>#{h(t['part'])}</th><th>Type</th><th>Ø × depth</th><th>Qty</th><th>Positions (x, y mm)</th></tr>"
          dr.each { |r| s << "<tr>#{r.map { |c| "<td>#{h(c)}</td>" }.join}</tr>" }
          s << '</table>'
        end
        s << '</table></section>'
      end
      s << '</body></html>'
      s
    end

    CSS = <<~CSS
      :root{--ink:#1c1f24;--mut:#6b7280;--line:#e5e7eb;--acc:#b8862b}
      *{box-sizing:border-box}body{margin:0;background:#fafaf7;color:var(--ink);font:13px/1.45 "Segoe UI",Tahoma,Arial,sans-serif}
      .page{max-width:1000px;margin:0 auto;padding:22px;page-break-after:always}
      header{display:flex;justify-content:space-between;align-items:flex-end;border-bottom:3px solid var(--acc);padding-bottom:8px;margin-bottom:12px}
      .brand{letter-spacing:.16em;color:var(--mut);font-size:12px}.brand b{color:var(--acc)}h1{margin:0;font-size:22px}.sub{color:var(--mut);font-size:12px}
      .views{display:flex;gap:14px;flex-wrap:wrap;align-items:flex-end}figure{margin:0;background:#fff;border:1px solid var(--line);border-radius:8px;padding:6px}
      figcaption{text-align:center;color:var(--mut);font-size:11px}.dim line{stroke:#b42318;stroke-width:.8}.dim text{fill:#b42318;font-size:10px}
      table{width:100%;border-collapse:collapse;background:#fff;border:1px solid var(--line);margin-top:12px;font-size:12px}
      th,td{padding:4px 8px;border-bottom:1px solid var(--line);text-align:start}th{background:#f3efe4}
      @media print{body{background:#fff}.page{padding:8px}}
    CSS
  end
end
