# frozen_string_literal: true

module EGC
  # DRILLING MAP: one board drawn flat with every bore, groove and notch the CNC feature list (Cam.features) holds for it, so the paper
  # (work order, cutting layout, execution sheets) and the machine file always show the same holes. Nothing is added here: a board
  # without stored drilling data gets no map. Positions are on the FINISHED piece: u along its length, v across its width.
  module DrillMap
    module_function

    COLORS = { 'POCKET_35MM' => '#b42318', 'DRILL_5MM' => '#0b57d0', 'DRILL_8MM' => '#15803d' }.freeze

    def color(layer)
      COLORS[layer] || (layer.to_s.start_with?('DRILL') ? '#7c3aed' : '#c2410c')
    end

    # a cut-list part or a nested piece -> the record Cam.features reads
    def item(p)
      p.merge(fin_l: p[:fin_l] || p[:len], fin_w: p[:fin_w] || p[:wid], id: p[:id] || p[:pid])
    end

    def data(part)
      it = item(part)
      f = Cam.features(it)
      { it: it, l: it[:fin_l].to_f, w: it[:fin_w].to_f, circles: f[:circles], rects: f[:rects] }
    rescue StandardError
      nil
    end

    def any?(d)
      !d.nil? && d[:l].positive? && d[:w].positive? && (d[:circles].any? || d[:rects].any?)
    end

    # the positions that get a figure: every distinct one, thinned where two would print on top of each other
    def ticks(vals, scale, gap)
      out = []
      vals.map { |v| v.round(1) }.uniq.sort.each { |v| out << v if out.empty? || (v - out.last) * scale >= gap }
      out
    end

    def num(v)
      format('%.1f', v.to_f).sub(/\.0\z/, '')
    end

    # 'Ø5 × 12: 24' per kind of bore
    def summary(d)
      d[:circles].group_by { |c| [c[3].round(1), c[4].round(1)] }.sort.map { |(dia, dep), l| "Ø#{num(dia)}×#{num(dep)}: #{l.size}" }.join('   ')
    end

    # ---- work order / report: a small stand-alone SVG ---------------------------------------------------------------------------
    def svg(part, max_w = 330.0, max_h = 170.0)
      d = data(part)
      return '' unless any?(d)

      sc = [max_w / d[:l], max_h / d[:w]].min
      pw = d[:l] * sc
      ph = d[:w] * sc
      ml = 34.0
      mt = 5.0
      tw = (pw + ml + 8).round(1)
      th = (ph + mt + 26).round(1)
      s = +"<svg xmlns='http://www.w3.org/2000/svg' class='dmap' direction='ltr' width='#{tw}' height='#{th}' viewBox='0 0 #{tw} #{th}'>"
      s << "<rect x='#{ml}' y='#{mt}' width='#{pw.round(1)}' height='#{ph.round(1)}' fill='#fbf7ec' stroke='#333' stroke-width='1'/>"
      d[:rects].each do |lay, u0, v0, u1, v1, _dep|
        x = ml + [u0, u1].min * sc
        y = mt + [v0, v1].min * sc
        notch = lay == 'NOTCH_GOLA'
        s << "<rect x='#{x.round(1)}' y='#{y.round(1)}' width='#{[(u1 - u0).abs * sc, 1.2].max.round(1)}' height='#{[(v1 - v0).abs * sc, 1.2].max.round(1)}' " \
             "fill='#{notch ? '#ffffff' : '#fde6c8'}' stroke='#c2410c' stroke-width='0.7'#{notch ? '' : " stroke-dasharray='4 2'"}/>"
      end
      d[:circles].each do |lay, u, v, dia, _dep|
        s << "<circle cx='#{(ml + u * sc).round(1)}' cy='#{(mt + v * sc).round(1)}' r='#{[dia * sc / 2.0, 1.4].max.round(1)}' fill='#{color(lay)}' fill-opacity='0.35' stroke='#{color(lay)}' stroke-width='0.8'/>"
      end
      ticks(d[:circles].map { |c| c[1] }, sc, 24.0).each do |u|
        x = (ml + u * sc).round(1)
        s << "<line x1='#{x}' y1='#{(mt + ph).round(1)}' x2='#{x}' y2='#{(mt + ph + 4).round(1)}' stroke='#555' stroke-width='0.6'/>"
        s << "<text x='#{x}' y='#{(mt + ph + 13).round(1)}' font-size='8' text-anchor='middle' fill='#333' font-family='sans-serif'>#{num(u)}</text>"
      end
      ticks(d[:circles].map { |c| c[2] }, sc, 10.0).each do |v|
        y = (mt + v * sc).round(1)
        s << "<line x1='#{ml - 4}' y1='#{y}' x2='#{ml}' y2='#{y}' stroke='#555' stroke-width='0.6'/>"
        s << "<text x='#{ml - 6}' y='#{(y + 3).round(1)}' font-size='8' text-anchor='end' fill='#333' font-family='sans-serif'>#{num(v)}</text>"
      end
      s << "<text x='#{(ml + pw / 2.0).round(1)}' y='#{(mt + ph + 23).round(1)}' font-size='8.5' text-anchor='middle' fill='#7a5612' font-family='sans-serif'>#{num(d[:l])} × #{num(d[:w])}</text>"
      s << '</svg>'
      s
    end

    # ---- execution sheets: the same map drawn into a cell [x, y, w, h] (mm on paper) of an ExecDraw sheet ------------------------
    def draw(sh, part, cell, head)
      d = data(part)
      return false unless any?(d)

      x0, y0, cw, ch = cell
      sh.rect(x0, y0, cw, ch, stroke: '#9aa1ad', sw: 0.12)
      sh.text(x0 + 2, y0 + 4.6, head, size: 2.9, bold: true, ltr: true)
      sh.text(x0 + 2, y0 + 8.6, summary(d), size: 2.4, color: '#444', ltr: true)
      ml = 13.0
      mt = 12.0
      sc = [(cw - ml - 6) / d[:l], (ch - mt - 13) / d[:w]].min
      pw = d[:l] * sc
      ph = d[:w] * sc
      px = x0 + ml
      py = y0 + mt
      sh.rect(px, py, pw, ph, fill: '#fbf7ec', sw: 0.25)
      d[:rects].each do |lay, u0, v0, u1, v1, _dep|
        notch = lay == 'NOTCH_GOLA'
        sh.rect(px + [u0, u1].min * sc, py + [v0, v1].min * sc, [(u1 - u0).abs * sc, 0.4].max, [(v1 - v0).abs * sc, 0.4].max,
                fill: notch ? '#ffffff' : '#fde6c8', stroke: '#c2410c', sw: 0.15, dash: notch ? nil : '1.2 0.7')
      end
      d[:circles].each do |lay, u, v, dia, _dep|
        cup = lay == 'POCKET_35MM' # the cup is the E.G.C standard bore (35 / K4): shown dashed until the hinge is confirmed
        sh.circle(px + u * sc, py + v * sc, [dia * sc / 2.0, 0.45].max, fill: cup ? 'none' : color(lay), stroke: color(lay), sw: 0.15, dash: cup ? '0.9 0.5' : nil)
      end
      ticks(d[:circles].map { |c| c[1] }, sc, 7.5).each do |u|
        sh.line(px + u * sc, py + ph, px + u * sc, py + ph + 1.2, w: 0.1, color: '#555')
        sh.text(px + u * sc, py + ph + 3.6, num(u), size: 2.1, anchor: :center, color: '#333', ltr: true)
      end
      ticks(d[:circles].map { |c| c[2] }, sc, 3.0).each do |v|
        sh.line(px - 1.2, py + v * sc, px, py + v * sc, w: 0.1, color: '#555')
        sh.text(px - 1.6, py + v * sc + 0.8, num(v), size: 2.1, anchor: :right, color: '#333', ltr: true)
      end
      sh.text(px + pw / 2.0, py + ph + 7.2, "#{num(d[:l])} × #{num(d[:w])}", size: 2.5, anchor: :center, color: '#8a1c12', ltr: true)
      true
    end

    # ---- cutting layout: the features of one PLACED piece in sheet coordinates (same mapping as the nested DXF) -------------------
    def placed(p)
      it = p[:item]
      f = Cam.features(it)
      du, dv, = Cam.band_shift(it)
      cw = it[:w].to_f
      map = lambda do |u, v|
        u -= du
        v -= dv
        p[:rotated] ? [p[:x] + cw - v, p[:y] + u] : [p[:x] + u, p[:y] + v]
      end
      circles = f[:circles].map { |lay, u, v, dia, _| [lay, *map.call(u, v), dia] }
      rects = f[:rects].map do |lay, u0, v0, u1, v1, _|
        a = map.call([u0, du].max, v0)
        b = map.call([u1, du + it[:l].to_f].min, v1)
        [lay, [a[0], b[0]].min, [a[1], b[1]].min, [a[0], b[0]].max, [a[1], b[1]].max]
      end
      { circles: circles, rects: rects }
    rescue StandardError
      { circles: [], rects: [] }
    end

    def sheet_marks(p, sc)
      m = placed(p)
      s = +''
      m[:rects].each do |lay, x0, y0, x1, y1|
        s << "<rect x='#{(x0 * sc).round(1)}' y='#{(y0 * sc).round(1)}' width='#{[(x1 - x0) * sc, 0.8].max.round(1)}' height='#{[(y1 - y0) * sc, 0.8].max.round(1)}' " \
             "fill='#{lay == 'NOTCH_GOLA' ? '#ffffff' : 'none'}' stroke='#c2410c' stroke-width='0.5'/>"
      end
      m[:circles].each do |lay, cx, cy, dia|
        s << "<circle cx='#{(cx * sc).round(1)}' cy='#{(cy * sc).round(1)}' r='#{[dia * sc / 2.0, 1.0].max.round(1)}' fill='#{color(lay)}'/>"
      end
      s
    end
  end
end
