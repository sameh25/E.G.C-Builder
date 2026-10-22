# frozen_string_literal: true

require 'json'

module EGC
  # Unit manufacturing sheet: the front elevation, section A-A and plan section B-B plus lettered DETAIL cells are packed onto one A3 sheet
  # at the largest standard scale that fits; details that do not fit move to a continuation sheet.
  module ExecFactory
    module_function

    DW = 92.0
    DH = 82.0

    # shelf packer: items [{w:,h:}] placed left to right, wrapping; returns positions or nil
    def pack(items, aw, ah, gap = 3.0)
      x = 0.0
      y = 0.0
      rowh = 0.0
      pos = []
      items.each do |it|
        return nil if it[:w] > aw + 0.01

        if x.positive? && x + it[:w] > aw + 0.01
          y += rowh + gap
          x = 0.0
          rowh = 0.0
        end
        pos << [x, y]
        x += it[:w] + gap
        rowh = [rowh, it[:h]].max
      end
      y + rowh > ah + 0.01 ? nil : pos
    end

    # ctx: { proj:, cfg:, lang:, data: (SiteDocs.collect), an: (Cutlist analysis) }
    def unit_sheets(g, ctx)
      lang = ctx[:lang]
      cfg = ctx[:cfg]
      proj = ctx[:proj]
      d = g.attribute_dictionary('egc').to_h
      code = d['code'].to_s
      no = "F-03-#{code}"
      bs = Drawings.boxes(g.entities.to_a)
      return [] if bs.empty?

      sm = EV.summary(bs)
      xmin, xmax = sm[:x]
      dmin, dmax = sm[:d]
      zmin, zmax = sm[:z]
      w = xmax - xmin
      h = zmax - zmin
      dd = dmax - dmin
      type = d['type'].to_s
      sh = ED::Sheet.new(proj, lang: lang, no: no, title: "#{ED.t(lang, 'unit')} #{code} - #{type}", zone: "#{code}  #{ED.fmt(d['w'])} x #{ED.fmt(d['h'])} x #{ED.fmt(d['d'])}")
      ax0, ay0, ax1, ay1 = sh.area
      aw = ax1 - ax0
      ah = ay1 - ay0
      cands = EV.detail_candidates(bs, d, cfg, {})
      lines = ED.wrap_rows(unit_lines(d, bs, sm, code, type, lang), 2.7, DW - 3)
      ublock = { w: DW, h: 17.0 + 4.2 * lines.size + 2.0 }
      mL = 21.0
      mR = 19.0
      mT = 13.0
      mB = 24.0
      chosen = nil
      ED::STD_SCALES.each do |n|
        items = { f: { w: w / n + mL + mR, h: h / n + mT + mB }, s: { w: dd / n + mL + mR, h: h / n + mT + mB }, p: { w: w / n + mL + mR, h: dd / n + mT + mB }, u: ublock }
        dets = cands.each_index.map { |i| { w: DW, h: DH, det: i } }
        orders = [%i[f s p u], %i[f s u p], %i[f p s u], %i[u f s p]]
        [[2, cands.size].min, 0].uniq.each do |core|
          orders.each do |ord|
            seq = ord.map { |kk| items[kk].merge(key: kk) } + dets.first(core)
            pos = pack(seq, aw, ah)
            next unless pos

            extra = core
            while extra < dets.size
              pos2 = pack(seq + [dets[extra]], aw, ah)
              break unless pos2

              seq += [dets[extra]]
              pos = pos2
              extra += 1
            end
            chosen = [n, seq, pos]
            break
          end
          break if chosen
        end
        break if chosen
      end
      n, seq, pos = chosen || begin
        nn = ED::STD_SCALES.last
        its = { f: { w: w / nn + 40, h: h / nn + 37 }, s: { w: dd / nn + 40, h: h / nn + 37 }, p: { w: w / nn + 40, h: dd / nn + 37 }, u: ublock }
        sq = %i[f s p u].map { |kk| its[kk].merge(key: kk) }
        [nn, sq, pack(sq, 1e9, 1e9)]
      end
      k = 1.0 / n
      sh.instance_variable_set(:@scale, "#{ED.t(lang, 'front').split.first} #{ED.scale_label(n)}")
      place = lambda do |it, p|
        x = ax0 + p[0]
        x = ax0 + ax1 - x - it[:w] if sh.rtl
        [x, ay0 + p[1], it[:w], it[:h]]
      end
      cellmap = {}
      slots = []
      seq.each_with_index do |it, i|
        c = place.call(it, pos[i])
        if it[:key]
          cellmap[it[:key]] = c
        else
          slots << [c, it[:det]]
        end
      end
      fc = cellmap[:f]
      sc = cellmap[:s]
      pc = cellmap[:p]
      mp_f = ED::Map.new(fc[0] + mL - xmin * k, fc[1] + mT + h * k + zmin * k, k, :elev)
      mp_s = ED::Map.new(sc[0] + mL - dmin * k, sc[1] + mT + h * k + zmin * k, k, :elev)
      zmid = (zmin + zmax) / 2.0
      xmid = (xmin + xmax) / 2.0
      mp_p = ED::Map.new(pc[0] + mL - xmin * k, pc[1] + mT - dmin * k, k, :plan)
      title = lambda do |c, key|
        tx = c[0] + (sh.rtl ? c[2] - 2 : 2)
        sh.text(tx, c[1] + 5, ED.t(lang, key), size: 3.4, bold: true, anchor: :left)
        sh.text(tx, c[1] + 9, "#{ED.t(lang, 'scale')} #{ED.scale_label(n)}", size: 2.5, anchor: :left, color: '#444')
      end
      title.call(fc, 'front')
      title.call(sc, 'section_a')
      title.call(pc, 'section_b')
      EV.draw_front(sh, mp_f, bs)
      EV.draw_section_a(sh, mp_s, bs, xmid)
      EV.draw_plan(sh, mp_p, bs, zmid)
      outline = lambda do |mp, a0, a1, b0, b1|
        sh.rect(mp.x(a0), mp.kind == :plan ? mp.y(b0) : mp.y(b1), mp.len(a1 - a0), mp.len(b1 - b0), stroke: '#111', sw: 0.35)
      end
      outline.call(mp_f, xmin, xmax, zmin, zmax)
      outline.call(mp_s, dmin, dmax, zmin, zmax)
      dims_front(sh, mp_f, bs, sm, d)
      dims_section(sh, mp_s, bs, sm, xmid)
      dims_plan(sh, mp_p, bs, sm)
      draw_lines(sh, cellmap[:u], lines, lang)
      dctx = { zmid: zmid, xmid: xmid }
      labels = %w[A B C D E F G H]
      placed_idx = slots.map { |_c, di| di }
      slots.each_with_index { |(c, di), si| EV.draw_detail(sh, cands[di], bs, c, labels[si], cfg, d, dctx) }
      unplaced = cands.each_index.reject { |q| placed_idx.include?(q) }
      cands.each_with_index do |c, di|
        lab = placed_idx.include?(di) ? labels[placed_idx.index(di)] : labels[placed_idx.size + unplaced.index(di)]
        marker(sh, mp_f, mp_s, mp_p, c, lab, bs, sm, d)
      end
      rest = unplaced.map { |q| cands[q] }
      out = [sh]
      out.concat(parts_sheets(g, d, bs, ctx, no, code, rest, labels.drop(placed_idx.size), dctx, cfg))
      out
    end

    def unit_lines(d, bs, sm, _code, _type, lang)
      rows = []
      rows << ["#{ED.t(lang, 'width')} x #{ED.t(lang, 'height')} x #{ED.t(lang, 'depth')} = #{ED.fmt(d['w'])} x #{ED.fmt(d['h'])} x #{ED.fmt(d['d'])}", '#111']
      dmin, dmax = sm[:joinery_d] || sm[:d]
      rows << ["#{ED.t(lang, 'depth')} #{ED.t(lang, 'incl_front')} = #{ED.fmt(dmax - dmin)}", '#111']
      g = EV.back_groove(bs)
      rows << ["#{ED.t(lang, 'back_groove')}: #{ED.fmt(g[:depth])} / #{ED.fmt(g[:offset])} / #{ED.fmt(g[:back_thk])}", '#111'] if g
      rows << ["#{ED.t(lang, 'mechanism')}: #{d['mech']}", '#111'] unless d['mech'].to_s.empty?
      rows << [ED.t(lang, 'req_hinge'), '#8a1c12'] if bs.any? { |b| b[:mat] == 'front' && %w[door door1 door2].include?(b[:part]) }
      rows << [ED.t(lang, 'req_runner'), '#8a1c12'] if bs.any? { |b| b[:part] == 'drawer_front' }
      rows << [ED.t(lang, 'req_mech'), '#8a1c12'] unless d['mech'].to_s.empty?
      rows << [ED.t(lang, 'req_app'), '#8a1c12'] if bs.any? { |b| b[:role] == 'appliance' && b[:part] != 'leg' }
      rows
    end

    def draw_lines(sh, c, lines, lang)
      x, y, w, h = c
      sh.rect(x, y, w, h, stroke: '#333', sw: 0.3)
      tx = sh.rtl ? x + w - 1.5 : x + 1.5
      sh.text(tx, y + 6, "#{ED.t(lang, 'unit')} #{sh.no.to_s.sub('F-03-', '')}", size: 4.4, bold: true, anchor: :left)
      sh.text(tx, y + 11, sh.title.to_s.sub(/\A[^-]*- /, ''), size: 3.0, anchor: :left, color: '#444')
      ln = y + 17
      lines.each do |txt, col|
        sh.text(tx, ln, ED.fit_text(txt, 2.7, w - 3), size: 2.7, anchor: :left, color: col)
        ln += 4.2
      end
    end
  end
end
