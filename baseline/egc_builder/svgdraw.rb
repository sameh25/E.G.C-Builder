# frozen_string_literal: true

require 'cgi'

module EGC
  # Tiny SVG drawing kit + the printable SHEET (with a proper title block) used by every site / manufacturing document.
  # World coordinates are millimetres with Y UP (like the model); the canvas flips them for SVG.
  module SvgDraw
    module_function

    def h(s)
      CGI.escapeHTML(s.to_s)
    end

    class Canvas
      attr_reader :minx, :miny, :maxx, :maxy, :body

      def initialize(minx, miny, maxx, maxy, pad: 700)
        @minx = minx - pad
        @miny = miny - pad
        @maxx = maxx + pad
        @maxy = maxy + pad
        @body = +''
        @fs = [(maxx - minx + maxy - miny) / 2.0 / 55.0, 60.0].max # text size in mm (readable at sheet scale)
      end

      def w
        @maxx - @minx
      end

      def hgt
        @maxy - @miny
      end

      def fs
        @fs
      end

      def sx(x)
        (x - @minx).round(1)
      end

      def sy(y)
        (@maxy - y).round(1)
      end

      def rect(x0, y0, x1, y1, fill: 'none', stroke: '#222', sw: nil, opacity: 1, dash: nil, cls: nil)
        sw ||= @fs / 22.0
        @body << "<rect x='#{sx([x0, x1].min)}' y='#{sy([y0, y1].max)}' width='#{(x1 - x0).abs.round(1)}' height='#{(y1 - y0).abs.round(1)}' fill='#{fill}' fill-opacity='#{opacity}' stroke='#{stroke}' stroke-width='#{sw.round(2)}'#{dash ? " stroke-dasharray='#{dash}'" : ''}#{cls ? " class='#{cls}'" : ''}/>"
      end

      def poly(pts, fill: 'none', stroke: '#222', sw: nil, close: true, dash: nil)
        sw ||= @fs / 22.0
        d = pts.map { |x, y| "#{sx(x)},#{sy(y)}" }.join(' ')
        @body << "<#{close ? 'polygon' : 'polyline'} points='#{d}' fill='#{fill}' stroke='#{stroke}' stroke-width='#{sw.round(2)}' stroke-linejoin='round'#{dash ? " stroke-dasharray='#{dash}'" : ''}/>"
      end

      def line(x0, y0, x1, y1, stroke: '#222', sw: nil, dash: nil)
        sw ||= @fs / 22.0
        @body << "<line x1='#{sx(x0)}' y1='#{sy(y0)}' x2='#{sx(x1)}' y2='#{sy(y1)}' stroke='#{stroke}' stroke-width='#{sw.round(2)}'#{dash ? " stroke-dasharray='#{dash}'" : ''}/>"
      end

      def circle(x, y, r, fill: 'none', stroke: '#222', sw: nil)
        sw ||= @fs / 22.0
        @body << "<circle cx='#{sx(x)}' cy='#{sy(y)}' r='#{r.round(1)}' fill='#{fill}' stroke='#{stroke}' stroke-width='#{sw.round(2)}'/>"
      end

      def arc(cx, cy, r, a0, a1, stroke: '#222', sw: nil)
        sw ||= @fs / 22.0
        p0 = [cx + r * Math.cos(a0 * Math::PI / 180), cy + r * Math.sin(a0 * Math::PI / 180)]
        p1 = [cx + r * Math.cos(a1 * Math::PI / 180), cy + r * Math.sin(a1 * Math::PI / 180)]
        large = (a1 - a0).abs > 180 ? 1 : 0
        sweep = a1 > a0 ? 0 : 1
        @body << "<path d='M#{sx(p0[0])},#{sy(p0[1])} A#{r.round(1)},#{r.round(1)} 0 #{large} #{sweep} #{sx(p1[0])},#{sy(p1[1])}' fill='none' stroke='#{stroke}' stroke-width='#{sw.round(2)}'/>"
      end

      def text(x, y, str, size: nil, anchor: 'middle', fill: '#111', bold: false, rot: 0)
        size ||= @fs
        tr = rot.zero? ? '' : " transform='rotate(#{-rot} #{sx(x)} #{sy(y)})'"
        @body << "<text x='#{sx(x)}' y='#{sy(y)}' font-size='#{size.round(1)}' text-anchor='#{anchor}' fill='#{fill}'#{bold ? " font-weight='700'" : ''}#{tr}>#{SvgDraw.h(str)}</text>"
      end

      # linear dimension between two world points, drawn `off` mm away from the measured line (positive = left of a->b)
      def dim(x0, y0, x1, y1, off, label = nil, color: '#b42318')
        dx = x1 - x0
        dy = y1 - y0
        len = Math.hypot(dx, dy)
        return if len < 1

        ux = dx / len
        uy = dy / len
        nx = -uy
        ny = ux
        ax = x0 + nx * off
        ay = y0 + ny * off
        bx = x1 + nx * off
        by = y1 + ny * off
        sw = @fs / 30.0
        line(x0 + nx * (off * 0.15), y0 + ny * (off * 0.15), ax + nx * @fs * 0.4 * (off <=> 0), ay + ny * @fs * 0.4 * (off <=> 0), stroke: color, sw: sw)
        line(x1 + nx * (off * 0.15), y1 + ny * (off * 0.15), bx + nx * @fs * 0.4 * (off <=> 0), by + ny * @fs * 0.4 * (off <=> 0), stroke: color, sw: sw)
        line(ax, ay, bx, by, stroke: color, sw: sw)
        t = @fs * 0.35
        [[ax, ay], [bx, by]].each { |px, py| line(px - (ux - nx) * t, py - (uy - ny) * t, px + (ux - nx) * t, py + (uy - ny) * t, stroke: color, sw: sw * 1.6) }
        ang = Math.atan2(dy, dx) * 180 / Math::PI
        ang += 180 if ang > 90 || ang < -90
        text((ax + bx) / 2 + nx * @fs * 0.6 * (off <=> 0), (ay + by) / 2 + ny * @fs * 0.6 * (off <=> 0), label || len.round.to_s, size: @fs * 0.8, fill: color, rot: ang)
      end

      def svg(width_css = '100%')
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 #{w.round} #{hgt.round}' width='#{width_css}' style='max-width:100%;background:#fff;font-family:Segoe UI,Arial,sans-serif'>#{@body}</svg>"
      end
    end

    CSS = <<~CSS
      :root{--ink:#1c1f24;--mut:#6b7280;--line:#c9c5b8;--acc:#b8862b;--bad:#b42318;--ok:#177245}
      *{box-sizing:border-box}body{margin:0;background:#efede6;color:var(--ink);font:13px/1.45 "Segoe UI",Tahoma,Arial,sans-serif}
      .sheet{max-width:1180px;margin:14px auto;background:#fff;border:2px solid #222;padding:14px;page-break-after:always}
      .draw{border:1px solid var(--line);margin-bottom:10px;padding:6px}
      table.tb{width:100%;border-collapse:collapse;border:2px solid #222;margin-top:6px;font-size:12px}
      table.tb td{border:1px solid #222;padding:3px 8px;vertical-align:top}table.tb td.k{background:#f3efe4;width:12%;color:var(--mut);font-size:11px}
      table.data{width:100%;border-collapse:collapse;margin:8px 0;font-size:12px}table.data th,table.data td{padding:4px 8px;border-bottom:1px solid #ddd;text-align:start}table.data th{background:#f3efe4}
      .st{display:inline-block;padding:1px 8px;border-radius:9px;font-size:11px;font-weight:700}
      .CONFIRMED,.CURRENT,.APPROVED,.FOR_PRODUCTION{background:#dff3e6;color:#177245}.INFERRED,.DRAFT,.FOR_REVIEW{background:#fdf1d3;color:#8a5a00}.REQUIRES_CONFIRMATION,.MISSING_PRICE,.MISSING_DATA,.OUTDATED,.STALE{background:#fde0dc;color:#b42318}.AS_BUILT{background:#dbeafe;color:#1e40af}
      h1,h2{margin:4px 0}h1{font-size:20px}h2{font-size:15px;border-bottom:2px solid var(--acc);padding-bottom:2px;margin-top:14px}
      .warn{color:var(--bad);font-weight:600}.note{color:var(--mut);font-size:11.5px}
      .hd{display:flex;align-items:baseline;gap:14px;border-bottom:2px solid #222;margin-bottom:8px;padding-bottom:2px}.hd h1{flex:1;margin:0}.hd .brand{font-weight:600;letter-spacing:.4px;font-size:13px;white-space:nowrap}.hd .sn{font-weight:700;font-size:15px}
      @media print{body{background:#fff}.sheet{margin:0;border:2px solid #222}}
    CSS

    # one printable sheet: title, drawing / content, TITLE BLOCK (project, client, sheet, revision, date, scale, wall / zone, status)
    def sheet(proj, title:, sheet_no:, scale: 'NTS', zone: '-', status: 'DRAFT', body:, lang: 'en', extra_status: nil)
      ar = lang == 'ar'
      k = lambda { |en, a| ar ? a : en }
      st_cls = status.to_s.gsub(/\W/, '_')
      "<section class='sheet'><div class='hd'><span class='brand'>E.G.C <b>Builder</b></span><h1>#{h(title)}</h1><span class='sn'>#{h(sheet_no)}</span></div>#{body}" \
        "<table class='tb'><tr><td class='k'>#{k.call('Project', 'المشروع')}</td><td>#{h(proj['name'])}</td><td class='k'>#{k.call('Client', 'العميل')}</td><td>#{h(proj['client'])}</td>" \
        "<td class='k'>#{k.call('Sheet', 'اللوحة')}</td><td><b>#{h(sheet_no)}</b></td><td class='k'>#{k.call('Revision', 'المراجعة')}</td><td>#{h(proj['rev'])}</td></tr>" \
        "<tr><td class='k'>#{k.call('Date', 'التاريخ')}</td><td>#{Time.now.strftime('%Y-%m-%d')}</td><td class='k'>#{k.call('Scale', 'المقياس')}</td><td>#{h(scale)}</td>" \
        "<td class='k'>#{k.call('Wall / Zone', 'الحائط / المنطقة')}</td><td>#{h(zone)}</td><td class='k'>#{k.call('Status', 'الحالة')}</td><td><span class='st #{st_cls}'>#{h(status)}</span>#{extra_status ? " <span class='st #{extra_status.to_s.gsub(/\W/, '_')}'>#{h(extra_status)}</span>" : ''}</td></tr></table></section>"
    end

    def page(title, sheets, lang = 'en')
      "<!doctype html><html lang='#{lang}' dir='#{lang == 'ar' ? 'rtl' : 'ltr'}'><head><meta charset='utf-8'><title>#{h(title)}</title><style>#{CSS}</style></head><body>#{Array(sheets).join}</body></html>"
    end

    def data_table(headers, rows, cls = 'data')
      "<table class='#{cls}'><tr>#{headers.map { |x| "<th>#{h(x)}</th>" }.join}</tr>#{rows.map { |r| "<tr>#{r.map { |c| "<td>#{c.is_a?(Hash) ? c[:html] : h(c)}</td>" }.join}</tr>" }.join}</table>"
    end

    def badge(st)
      { html: "<span class='st #{st.to_s.gsub(/\W/, '_')}'>#{h(st)}</span>" }
    end
  end
end
