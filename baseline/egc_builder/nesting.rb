# frozen_string_literal: true

module EGC
  # 2D rectangle packing (MaxRects, best short side fit) for sheet goods.
  module Nesting
    Rect = Struct.new(:x, :y, :w, :h)

    module_function

    # items: [{ id:, l:, w:, rot: bool, label: }]  (l = along grain)
    # returns { sheets: [{ placed: [{x,y,w,h,item}], area:, offcut: [l, w] }], oversize: [items], strategy: 'order/fit' }
    #
    # LEAST WASTE: the boards are laid out several ways (five orders of the parts x four ways of choosing the place) and the best layout is
    # kept - fewest sheets first; among those, the one that leaves the last sheet emptiest, so what is left is one large usable offcut and
    # not scattered strips. Deterministic: the same parts always give the same layout.
    # GLOBAL NESTING: every cuttable part of one material/thickness is collected into
    # one pool first, then the whole pool is laid out on stock sheets.  We deliberately
    # do not nest cabinet-by-cabinet because that creates avoidable waste.
    ORDERS = {
      'area' => ->(i) { [-(i[:l] * i[:w]), -[i[:l], i[:w]].max, -[i[:l], i[:w]].min] },
      'long side' => ->(i) { [-[i[:l], i[:w]].max, -[i[:l], i[:w]].min, -(i[:l] * i[:w])] },
      'short side' => ->(i) { [-[i[:l], i[:w]].min, -[i[:l], i[:w]].max, -(i[:l] * i[:w])] },
      'length' => ->(i) { [-i[:l], -i[:w], -(i[:l] * i[:w])] },
      'width' => ->(i) { [-i[:w], -i[:l], -(i[:l] * i[:w])] },
      'perimeter' => ->(i) { [-(2 * (i[:l] + i[:w])), -[i[:l], i[:w]].max, -(i[:l] * i[:w])] },
      'aspect' => ->(i) { [-(i[:l].to_f / [i[:w].to_f, 1.0].max), -(i[:l] * i[:w]), -[i[:l], i[:w]].max] },
      'area-min-side' => ->(i) { [-(i[:l] * i[:w]), [i[:l], i[:w]].min, -[i[:l], i[:w]].max] },
      'large-first' => ->(i) { [-[i[:l], i[:w]].max, -(i[:l] * i[:w]), -[i[:l], i[:w]].min] },
      'large-first-compact' => ->(i) { [-(i[:l] * i[:w]), -([i[:l], i[:w]].max * 2 + [i[:l], i[:w]].min), -[i[:l], i[:w]].max] }
    }.freeze
    FITS = %w[short-side long-side area bottom-left contact].freeze

    def stable_piece_rank(it)
      it[:id].to_s.each_byte.with_index.inject(0) { |a, (b, i)| (a + b * (i + 1)) % 1000003 }
    end

    def pack(items, sheet_l, sheet_w, kerf, trim, compact: true)
      best = nil
      ORDERS.each do |oname, key|
        sorted = items.each_with_index.sort_by { |it, n| [key.call(it), n] }.map(&:first)
        if %w[large-first large-first-compact].include?(oname)
          max_area = items.map { |it| it[:l].to_f * it[:w].to_f }.max.to_f
          small_cut = max_area * 0.18
          large = sorted.select { |it| it[:l].to_f * it[:w].to_f > small_cut }
          small = sorted.reject { |it| it[:l].to_f * it[:w].to_f > small_cut }
          small.sort_by! { |it| [-(it[:l].to_f * it[:w].to_f), -[it[:l], it[:w]].max, stable_piece_rank(it)] }
          sorted = large + small
        end
        FITS.product([false, true]).each do |fit, any_sheet|
          r = pack_once(sorted, sheet_l, sheet_w, kerf, trim, fit, any_sheet)
          r[:strategy] = "#{oname}/#{fit}#{any_sheet ? '/best sheet' : ''}"
          # Rank by the things that matter in production: no oversize parts,
          # minimum stock sheets, then a useful remnant pattern.  The total net
          # part area is fixed, so waste % is identical for any layout using the
          # same number of sheets; the tie-breaker therefore prefers fewer, larger
          # usable offcuts instead of scattered strips.
          r[:sheets].each do |sh|
            sh[:free_area] = EGC::Num.sum(sh[:free]) { |fr| [fr.w - kerf, 0].max * [fr.h - kerf, 0].max }
            sh[:largest_free] = sh[:free].map { |fr| [[fr.w - kerf, 0].max, [fr.h - kerf, 0].max] }.max_by { |l, w| l * w } || [0, 0]
          end
          frag = EGC::Num.sum(r[:sheets]) { |sh| sh[:free].length }
          largest = r[:sheets].map { |sh| sh[:largest_free][0] * sh[:largest_free][1] }.max || 0
          tiny = EGC::Num.sum(r[:sheets]) do |sh|
            EGC::Num.sum(sh[:free]) do |fr|
              a = [fr.w - kerf, 0].max * [fr.h - kerf, 0].max
              a < 0.025 * sheet_l * sheet_w ? 1 : 0
            end
          end
          r[:rank] = [r[:oversize].size, r[:sheets].size, tiny, frag, -largest]
          best = r if best.nil? || (r[:rank] <=> best[:rank]).negative?
        end
      end
      # A second, genuinely remnant-aware pass.  Unlike the order/fit trials
      # above, it does not commit to a complete part order.  After every cut it
      # chooses the remaining part and the free rectangle together, so small
      # pieces are consumed by the offcuts created by large pieces before a new
      # sheet is opened.  This is still deterministic and is deliberately kept
      # inside one material/thickness pool (Cutlist#nest_all).
      FITS.each do |fit|
        r = pack_remnant_aware(items, sheet_l, sheet_w, kerf, trim, fit)
        r[:strategy] = "global-remnant/#{fit}"
        r[:sheets].each do |sh|
          sh[:free_area] = EGC::Num.sum(sh[:free]) { |fr| [fr.w - kerf, 0].max * [fr.h - kerf, 0].max }
          sh[:largest_free] = sh[:free].map { |fr| [[fr.w - kerf, 0].max, [fr.h - kerf, 0].max] }.max_by { |l, w| l * w } || [0, 0]
        end
        # The production decision is explicit: stock count, then unused board
        # area, then fragmentation.  Waste is normally close between layouts,
        # but is not assumed to be identical when trim/kerf leaves slivers.
        waste = EGC::Num.sum(r[:sheets]) { |sh| sh[:free_area] }
        frag = EGC::Num.sum(r[:sheets]) { |sh| sh[:free].length }
        tiny = EGC::Num.sum(r[:sheets]) do |sh|
          EGC::Num.sum(sh[:free]) { |fr| ((fr.w - kerf) * (fr.h - kerf) < 0.025 * sheet_l * sheet_w) ? 1 : 0 }
        end
        r[:rank] = [r[:oversize].size, r[:sheets].size, waste.round(4), frag, tiny]
        best = r if best.nil? || (r[:rank] <=> best[:rank]).negative?
      end
      best ||= { sheets: [], oversize: [], strategy: 'none' }
      # POST-COMPACTION: try to empty the least-filled sheet into the others -
      # one part at a time, spots recomputed after every move, never loses a
      # part (the donor sheet is dropped only when it is fully emptied). The
      # pass loops until nothing moves any more (capped, deterministic), and
      # each pass tries the fit rules in turn: a part that will not close a gap
      # under one rule can close it under another.
      if compact
        moved = true
        pass = 0
        rules = %w[short-side area contact long-side bottom-left]
        while moved && pass < 20
          moved = false
          rules.each do |f|
            before = best[:sheets].map { |sh| [sh[:area], sh[:placed].size] }
            compact_sheets!(best, kerf, f)
            after = best[:sheets].map { |sh| [sh[:area], sh[:placed].size] }
            moved ||= before != after
          end
          pass += 1
        end
      end
      best[:sheets].each do |sh|
        o = sh[:free].map { |fr| [[fr.w - kerf, 0].max, [fr.h - kerf, 0].max] }.max_by { |l, w| l * w }
        sh[:offcut] = o ? o.map { |v| v.round } : [0, 0]
        sh[:waste_pct] = (100.0 * (1.0 - sh[:area] / (sheet_l.to_f * sheet_w))).round(2)
      end
      best
    end

    # Dynamic global packing: first open a sheet with the largest remaining
    # piece, then repeatedly choose the best fitting remaining piece from every
    # free rectangle on every already-open sheet.  A fresh sheet is permitted
    # only when no remainder can accept anything.  That makes remnants a real
    # resource rather than a by-product of an initial sort order.
    def pack_remnant_aware(items, sheet_l, sheet_w, kerf, trim, fit)
      remaining = items.each_with_index.sort_by { |it, n| [-it[:l].to_f * it[:w].to_f, -[it[:l], it[:w]].max, n] }.map(&:first)
      oversize, remaining = remaining.partition { |it| !fits_sheet?(it, sheet_l, sheet_w, trim) }
      sheets = []
      until remaining.empty?
        choices = []
        sheets.each_with_index do |sh, si|
          remaining.each_with_index do |it, ii|
            sp = spot(sh, it, kerf, fit)
            next unless sp

            # Close a remnant tightly first; among equal closures, put the
            # larger part down first.  The score supplied by #spot includes
            # rotation wherever the part permits it.
            choices << [[sp[0], [sp[3] * sp[4], 0].max * -1, stable_piece_rank(it), si, ii], sh, it, sp, ii]
          end
        end
        if choices.empty?
          it = remaining.shift
          sh = { free: [Rect.new(trim, trim, sheet_l - 2 * trim + kerf, sheet_w - 2 * trim + kerf)], placed: [], area: 0.0 }
          place(sh, it, kerf, fit)
          sheets << sh
        else
          _, sh, it, sp, ii = choices.min_by(&:first)
          put(sh, it, kerf, sp)
          remaining.delete_at(ii)
        end
      end
      { sheets: sheets, oversize: oversize }
    end

    # any_sheet: the piece goes to the sheet where it fits best (not simply the first sheet that takes it)
    def pack_once(sorted, sheet_l, sheet_w, kerf, trim, fit, any_sheet = false)
      sheets = []
      oversize = []
      sorted.each do |it|
        unless fits_sheet?(it, sheet_l, sheet_w, trim)
          oversize << it
          next
        end
        if any_sheet
          best = sheets.map { |sh| [sh, spot(sh, it, kerf, fit)] }.select { |_, sp| sp }.min_by { |_, sp| sp[0] }
          if best
            put(best[0], it, kerf, best[1])
            next
          end
        elsif sheets.any? { |sh| place(sh, it, kerf, fit) }
          next
        end

        sh = { free: [Rect.new(trim, trim, sheet_l - 2 * trim + kerf, sheet_w - 2 * trim + kerf)], placed: [], area: 0.0 }
        place(sh, it, kerf, fit)
        sheets << sh
      end
      { sheets: sheets, oversize: oversize }
    end

    def fits_sheet?(it, sl, sw, trim)
      l = it[:l]
      w = it[:w]
      al = sl - 2 * trim
      aw = sw - 2 * trim
      (l <= al && w <= aw) || (it[:rot] && w <= al && l <= aw)
    end

    # the best free place of one sheet for a piece: [score, x, y, l, w, rotated] or nil
    def spot(sh, it, kerf, fit = 'short-side')
      best = nil
      sh[:free].each do |f|
        orients = [[it[:l], it[:w], false]]
        orients << [it[:w], it[:l], true] if it[:rot] && it[:l] != it[:w]
        orients.each do |l, w, rot|
          fw = l + kerf
          fh = w + kerf
          next if fw > f.w + 1e-6 || fh > f.h + 1e-6

          dw = f.w - fw
          dh = f.h - fh
          score = case fit
                  when 'long-side' then [[dw, dh].max, [dw, dh].min]
                  when 'area' then [f.w * f.h - fw * fh, [dw, dh].min]
                  when 'bottom-left' then [f.y + fh, f.x]
                  when 'contact'
                    # Prefer exact closure of one or both dimensions of the free
                    # rectangle. This closes unusable strips without changing the
                    # physical kerf/trim rules.
                    exact = (dw.abs <= 1e-6 ? 1 : 0) + (dh.abs <= 1e-6 ? 1 : 0)
                    [-exact, [dw, dh].min, [dw, dh].max]
                  else [[dw, dh].min, [dw, dh].max]
                  end
          best = [score, f.x, f.y, l, w, rot] if best.nil? || (score <=> best[0]).negative?
        end
      end
      best
    end

    def put(sh, it, kerf, best)
      _, x, y, l, w, rot = best
      split_free(sh, Rect.new(x, y, l + kerf, w + kerf))
      sh[:placed] << { x: x, y: y, w: l, h: w, item: it, rotated: rot }
      sh[:area] += l * w
      true
    end

    def place(sh, it, kerf, fit = 'short-side')
      best = spot(sh, it, kerf, fit)
      best ? put(sh, it, kerf, best) : false
    end

    # One compaction step: every part of the least-filled sheet tries the best
    # free rectangle on any other sheet (MaxRects spot, kerf- and grain-aware).
    # A part moves only when it really lands; the donor sheet is removed only
    # when empty. Deterministic. Returns the result (mutated in place).
    def compact_sheets!(r, kerf, fit = 'short-side')
      return r if r[:sheets].size < 2

      donor = r[:sheets].min_by { |sh| sh[:area] }
      others = r[:sheets] - [donor]
      donor[:placed].dup.each do |pl|
        t = others.map { |sh| [sh, spot(sh, pl[:item], kerf, fit)] }.select { |_, sp| sp }.min_by { |_, sp| sp[0] }
        next unless t

        put(t[0], pl[:item], kerf, t[1])
        donor[:placed].delete(pl)
      end
      r[:sheets].delete(donor) if donor[:placed].empty?
      r
    end

    def split_free(sh, u)
      out = []
      sh[:free].each do |f|
        if u.x >= f.x + f.w || u.x + u.w <= f.x || u.y >= f.y + f.h || u.y + u.h <= f.y
          out << f
          next
        end
        out << Rect.new(f.x, f.y, u.x - f.x, f.h) if u.x > f.x
        out << Rect.new(u.x + u.w, f.y, f.x + f.w - (u.x + u.w), f.h) if u.x + u.w < f.x + f.w
        out << Rect.new(f.x, f.y, f.w, u.y - f.y) if u.y > f.y
        out << Rect.new(f.x, u.y + u.h, f.w, f.y + f.h - (u.y + u.h)) if u.y + u.h < f.y + f.h
      end
      out.reject! { |r| r.w < 1 || r.h < 1 }
      # prune contained rectangles
      keep = out.reject do |a|
        out.any? { |b| !b.equal?(a) && a.x >= b.x && a.y >= b.y && a.x + a.w <= b.x + b.w && a.y + a.h <= b.y + b.h }
      end
      sh[:free] = keep
    end

    # Minimal DXF (R12) export of all nested sheets: layers SHEET, PARTS, TEXT
    def dxf(nest, gap = 400)
      out = +"0
SECTION
2
ENTITIES
"
      line = lambda do |layer, x1, y1, x2, y2|
        out << "0
LINE
8
#{layer}
10
#{x1.round(2)}
20
#{y1.round(2)}
30
0
11
#{x2.round(2)}
21
#{y2.round(2)}
31
0
"
      end
      text = lambda do |x, y, h, str|
        out << "0
TEXT
8
TEXT
10
#{x.round(2)}
20
#{y.round(2)}
30
0
40
#{h}
1
#{str}
"
      end
      oy = 0
      nest.each do |(mat, thk), n|
        sl, sw = n[:sheet]
        n[:sheets].each_with_index do |sh, i|
          ox = i * (sl + gap)
          [[0, 0, sl, 0], [sl, 0, sl, sw], [sl, sw, 0, sw], [0, sw, 0, 0]].each { |a, b, c, d| line.call('SHEET', ox + a, oy + b, ox + c, oy + d) }
          text.call(ox, oy + sw + 40, 40, "#{mat} #{thk}mm sheet #{i + 1}")
          sh[:placed].each do |p|
            x = ox + p[:x]
            y = oy + p[:y]
            [[x, y, x + p[:w], y], [x + p[:w], y, x + p[:w], y + p[:h]], [x + p[:w], y + p[:h], x, y + p[:h]], [x, y + p[:h], x, y]].each { |a, b, c, d| line.call('PARTS', a, b, c, d) }
            th = [[p[:h] / 6.0, 30].min, 8].max.round
            text.call(x + 10, y + p[:h] / 2.0, th, p[:item][:id])
            groove_paths(p, x, y, line, text, th) if p[:item][:groove].to_s.match?(/\d+x\d+@\d+/)
          end
        end
        oy -= (sw + 300)
      end
      out << "0
ENDSEC
0
EOF
"
      out
    end


    # LED groove as REAL router geometry on the sheet (layers GROOVE_D<depth> = pocket outline, GROOVE_CL_D<depth> = tool centre line, BACK_EDGE = the
    # part's back edge). Everything comes from the part itself (attribute groove_geo, written by the builder from the same numbers that cut the groove in 3D):
    #   axis 'len' = route along the part LENGTH, ref 'wid0' / 'wid1' = the width-edge the offset is measured from ('wid0' = the BACK edge), face 'underside', route 'through'.
    # A part whose data is missing or unknown (other axis / face / ref) is NOT drawn: an explicit note is written instead.
    # Sheet placement: the sheet frame is the view of the groove face (part flipped about its length axis), length along X (Y when the part is rotated 90 deg on the sheet),
    # the ref edge on the low side of the width axis.
    def groove_paths(p, x, y, line, text, th)
      geo = begin; JSON.parse(p[:item][:groove_geo].to_s); rescue StandardError; nil; end
      ok = geo.is_a?(Hash) && geo['off'] && geo['w'] && geo['d'] && geo['axis'] == 'len' && %w[wid0 wid1].include?(geo['ref']) && geo['face'] == 'underside' && geo['route'] == 'through'
      unless ok
        text.call(x + 10, y + p[:h] / 2.0 - th * 1.5, [th * 0.7, 6].max.round, "LED GROOVE #{p[:item][:groove]} - ROUTER ORIENTATION NOT RECORDED (rebuild the unit)")
        return
      end
      lw = geo['w'].to_f
      d = geo['d'].to_f.round
      wid = p[:rotated] ? p[:w] : p[:h] # width of the part along the sheet axis that carries the offset
      off = geo['ref'] == 'wid0' ? geo['off'].to_f : wid - geo['off'].to_f - lw
      lay = "GROOVE_D#{d}"
      cl = "GROOVE_CL_D#{d}"
      if p[:rotated]
        x0 = x + off
        x1 = x0 + lw
        [[x0, y, x1, y], [x1, y, x1, y + p[:h]], [x1, y + p[:h], x0, y + p[:h]], [x0, y + p[:h], x0, y]].each { |a, b, c, e| line.call(lay, a, b, c, e) }
        line.call(cl, x0 + lw / 2.0, y, x0 + lw / 2.0, y + p[:h])
        line.call('BACK_EDGE', x, y, x, y + p[:h]) if geo['ref'] == 'wid0'
        tx = x + 10
        ty = y + 12
      else
        y0 = y + off
        y1 = y0 + lw
        [[x, y0, x + p[:w], y0], [x + p[:w], y0, x + p[:w], y1], [x + p[:w], y1, x, y1], [x, y1, x, y0]].each { |a, b, c, e| line.call(lay, a, b, c, e) }
        line.call(cl, x, y0 + lw / 2.0, x + p[:w], y0 + lw / 2.0)
        line.call('BACK_EDGE', x, y, x + p[:w], y) if geo['ref'] == 'wid0'
        tx = x + 10
        ty = y + p[:h] / 2.0 - th * 1.5
      end
      text.call(tx, ty, [th * 0.7, 6].max.round, "ROUTER #{lw.round}x#{d} deep, #{geo['off'].to_f.round(1)} from #{geo['ref'] == 'wid0' ? 'BACK' : 'FRONT'} edge, through #{p[:item][:l].round} (groove face UP, ref edge = low #{p[:rotated] ? 'X' : 'Y'})")
    end

    PALETTE = %w[#bfd7ea #f6d6a8 #cfe8c4 #f1c4c4 #d9c7ec #f4efb3 #bfe6e0 #e5cfb4].freeze

    def svg(sheet, sheet_l, sheet_w, scale_w = 900)
      sc = scale_w.to_f / sheet_l
      h = (sheet_w * sc).round(1)
      s = +"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 #{scale_w} #{h}' width='#{scale_w}' height='#{h}' class='sheet'>"
      s << "<rect x='0' y='0' width='#{scale_w}' height='#{h}' fill='#faf8f2' stroke='#333' stroke-width='1.5'/>"
      sheet[:placed].each do |p|
        it = p[:item]
        x = (p[:x] * sc).round(1)
        y = (p[:y] * sc).round(1)
        w = (p[:w] * sc).round(1)
        hh = (p[:h] * sc).round(1)
        col = PALETTE[it[:color] % PALETTE.size]
        s << "<rect x='#{x}' y='#{y}' width='#{w}' height='#{hh}' fill='#{col}' stroke='#444' stroke-width='0.8'/>"
        s << DrillMap.sheet_marks(p, sc) if defined?(DrillMap) # the holes and grooves of the piece, where the machine puts them
        next if w < 22 || hh < 12

        fs = [[[w, hh].min / 5.0, 11].min, 6].max.round(1)
        s << "<text x='#{(x + w / 2).round(1)}' y='#{(y + hh / 2 + fs / 3).round(1)}' font-size='#{fs}' " \
             "text-anchor='middle' fill='#222' font-family='sans-serif'>#{it[:id]}</text>"
        if w > 60 && hh > 26
          s << "<text x='#{(x + w / 2).round(1)}' y='#{(y + hh / 2 + fs / 3 + fs + 1).round(1)}' font-size='#{(fs * 0.75).round(1)}' " \
               "text-anchor='middle' fill='#555' font-family='sans-serif'>#{p[:w].round}x#{p[:h].round}</text>"
        end
      end
      s << '</svg>'
      s
    end
  end
end
