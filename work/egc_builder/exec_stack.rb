# frozen_string_literal: true

require 'json'

module EGC
  # Assembly sheet for a stacked tall unit: the assembled unit (overall W x H x D), both modules with their IDs and W x H x D, the joint
  # level and an enlarged DETAIL of the carcass joint (lower top board / upper bottom board / back panels).
  module ExecFactory
    module_function

    def stack_boxes(lo, up)
      jz = up.transformation.origin.z.to_mm - lo.transformation.origin.z.to_mm
      lb = Drawings.boxes(lo.entities.to_a)
      ub = Drawings.boxes(up.entities.to_a).map { |b| b.merge(z0: b[:z0] + jz, z1: b[:z1] + jz) }
      [lb, ub, jz]
    end

    def stack_sheet(asm, lo, up, ctx)
      lang = ctx[:lang]
      cfg = ctx[:cfg]
      proj = ctx[:proj]
      lb, ub, jz = stack_boxes(lo, up)
      bs = lb + ub
      sm = EV.summary(bs)
      xmin, xmax = sm[:x]
      dmin, dmax = sm[:d]
      zmin, zmax = sm[:z]
      w = xmax - xmin
      h = zmax - zmin
      dd = dmax - dmin
      dl = lo.attribute_dictionary('egc').to_h
      du = up.attribute_dictionary('egc').to_h
      t = ->(k) { ED.t(lang, k) }
      sh = ED::Sheet.new(proj, lang: lang, no: "F-03-#{asm}", title: "#{t.call('stack')} #{asm} = #{dl['code']} + #{du['code']}", zone: "#{asm}  #{ED.fmt(w)} x #{ED.fmt(h)} x #{ED.fmt(dd)}")
      ax0, ay0, ax1, ay1 = sh.area
      aw = ax1 - ax0
      ah = ay1 - ay0
      mL = 24.0
      mR = 22.0
      mT = 13.0
      mB = 24.0
      lines = [["#{t.call('assembly')} #{asm}: #{t.call('width')} x #{t.call('height')} x #{t.call('depth')} = #{ED.fmt(w)} x #{ED.fmt(h)} x #{ED.fmt(dd)}", '#111'],
               ["#{t.call('lower_mod')} #{dl['code']}: #{ED.fmt(dl['w'])} x #{ED.fmt(dl['h'])} x #{ED.fmt(dl['d'])}", '#111'],
               ["#{t.call('upper_mod')} #{du['code']}: #{ED.fmt(du['w'])} x #{ED.fmt(du['h'])} x #{ED.fmt(du['d'])}", '#111'],
               ["#{t.call('joint')} z = #{ED.fmt(jz)}", '#111'],
               ["#{asm} -> #{dl['code']} / #{du['code']}", '#444'],
               ['REQUIRES CONNECTOR SPECIFICATION - no joint drilling issued', '#8a1c12']]
      lines[-1][0] = lang == 'ar' ? 'يتطلب مواصفة الوصلات - لا توجد ثقوب وصل صادرة' : lines.last[0]
      lines = ED.wrap_rows(lines, 2.7, DW - 3)
      ublock = { w: DW, h: 17.0 + 4.2 * lines.size + 2.0 }
      chosen = nil
      ED::STD_SCALES.each do |n|
        items = { f: { w: w / n + mL + mR, h: h / n + mT + mB }, s: { w: dd / n + mL + mR, h: h / n + mT + mB }, u: ublock }
        seq = [items[:f].merge(key: :f), items[:s].merge(key: :s), items[:u].merge(key: :u), { w: DW + 20, h: DH + 20, det: 0 }]
        pos = pack(seq, aw, ah)
        if pos
          chosen = [n, seq, pos]
          break
        end
      end
      n, seq, pos = chosen || [ED::STD_SCALES.last, [], []]
      k = 1.0 / n
      sh.instance_variable_set(:@scale, ED.scale_label(n))
      cells = {}
      slot = nil
      seq.each_with_index do |it, i|
        x = ax0 + pos[i][0]
        x = ax0 + ax1 - x - it[:w] if sh.rtl
        c = [x, ay0 + pos[i][1], it[:w], it[:h]]
        it[:key] ? cells[it[:key]] = c : slot = c
      end
      fc = cells[:f]
      sc = cells[:s]
      mp_f = ED::Map.new(fc[0] + mL - xmin * k, fc[1] + mT + h * k + zmin * k, k, :elev)
      mp_s = ED::Map.new(sc[0] + mL - dmin * k, sc[1] + mT + h * k + zmin * k, k, :elev)
      xmid = (xmin + xmax) / 2.0
      [[fc, 'front'], [sc, 'section_a']].each do |c, key|
        tx = c[0] + (sh.rtl ? c[2] - 2 : 2)
        sh.text(tx, c[1] + 5, ED.t(lang, key), size: 3.4, bold: true, anchor: :left)
        sh.text(tx, c[1] + 9, "#{t.call('scale')} #{ED.scale_label(n)}", size: 2.5, anchor: :left, color: '#444')
      end
      EV.draw_front(sh, mp_f, bs)
      EV.draw_section_a(sh, mp_s, bs, xmid)
      [mp_f, mp_s].each_with_index do |mp, i|
        a0, a1 = i.zero? ? [xmin, xmax] : [dmin, dmax]
        sh.rect(mp.x(a0), mp.y(zmax), mp.len(a1 - a0), mp.len(h), stroke: '#111', sw: 0.35)
        sh.line(mp.x(a0) - 3, mp.y(jz), mp.x(a1) + 3, mp.y(jz), w: 0.2, dash: '4 1.2 1 1.2', color: '#0b57d0')
      end
      # module IDs on the front
      [[dl['code'], (zmin + jz) / 2.0], [du['code'], (jz + zmax) / 2.0]].each do |cd, zz|
        sh.text(mp_f.x(xmin) + mp_f.len(w) / 2.0, mp_f.y(zz), cd.to_s, size: [[mp_f.len(w) / 3.0, 7.0].min, 3.0].max, anchor: :center, bold: true, color: '#7a6a45')
      end
      # dimensions: overall W; modules chain + overall H on the left; D below the section
      xl = mp_f.x(xmin)
      yb = mp_f.y(zmin)
      sh.dim_h(xl, mp_f.x(xmax), yb + 8, ED.fmt(w), from_y: yb + 0.5)
      sh.dim_v(mp_f.y(jz), yb, xl - 8, ED.fmt(jz), from_x: xl - 0.5)
      sh.dim_v(mp_f.y(zmax), mp_f.y(jz), xl - 8, ED.fmt(zmax - jz), from_x: xl - 0.5)
      sh.dim_v(mp_f.y(zmax), yb, xl - 16, ED.fmt(h), from_x: xl - 0.5)
      sl = mp_s.x(dmin)
      sh.dim_h(sl, mp_s.x(dmax), mp_s.y(zmin) + 8, ED.fmt(dd), from_y: mp_s.y(zmin) + 0.5)
      sh.dim_v(mp_s.y(jz), mp_s.y(zmin), sl - 8, ED.fmt(jz), from_x: sl - 0.5)
      sh.dim_v(mp_s.y(zmax), mp_s.y(jz), sl - 8, ED.fmt(zmax - jz), from_x: sl - 0.5)
      # callout A on the section (joint) + DETAIL A
      rx0 = mp_s.x(dmin) - 3
      rx1 = mp_s.x(dmax) + 3
      ry0 = mp_s.y(jz + 40)
      ry1 = mp_s.y(jz - 40)
      sh.rect(rx0, ry0, rx1 - rx0, ry1 - ry0, stroke: '#0b57d0', sw: 0.22, dash: '1.6 0.9')
      tx = rx1 + 3.6
      ty = ry0 - 3.0
      sh.line(rx1, ry0, tx - 2.4, ty + 1.8, w: 0.18, color: '#0b57d0')
      sh.circle(tx, ty, 3.2, fill: '#fff', stroke: '#0b57d0', sw: 0.3)
      sh.text(tx, ty + 1.1, 'A', size: 3.3, anchor: :center, bold: true, color: '#0b57d0')
      joint_detail(sh, slot, bs, jz, dmin, dmax, xmid, lang) if slot
      draw_lines(sh, cells[:u], lines, lang)
      sh
    end

    # enlarged carcass joint: section A-A zoomed around the joint level (same boxes as the parent drawing)
    def joint_detail(sh, c, bs, jz, dmin, dmax, xmid, lang)
      x, y, w, h = c
      sh.rect(x, y, w, h, stroke: '#333', sw: 0.3)
      sh.text(x + (sh.rtl ? w - 2 : 2), y + 5, "#{ED.t(lang, 'detail')} A - #{ED.t(lang, 'joint')}", size: 3.2, bold: true, anchor: :left)
      inner = [x + 2, y + 9, w - 4, h - 16]
      reg = [dmin - 6, dmax + 6, jz - 55, jz + 55]
      n = ED.pick_scale((reg[1] - reg[0]), (reg[3] - reg[2]), inner[2] - 8, inner[3] - 6, EV::DETAIL_SCALES)
      k = 1.0 / n
      mp = ED::Map.new(inner[0] + inner[2] / 2.0 - ((reg[0] + reg[1]) / 2.0) * k, inner[1] + inner[3] / 2.0 + jz * k, k, :elev)
      sh.clip_begin(*inner)
      EV.draw_section_a(sh, mp, bs, xmid)
      sh.clip_end
      sh.line(inner[0], mp.y(jz), inner[0] + inner[2], mp.y(jz), w: 0.18, dash: '4 1.2 1 1.2', color: '#0b57d0')
      lowtop = bs.select { |b| b[:x0] <= xmid && b[:x1] >= xmid && b[:z1] <= jz + 0.5 && b[:z1] > jz - 40 && (b[:z1] - b[:z0]) <= 30 }.max_by { |b| b[:z1] }
      upbot = bs.select { |b| b[:x0] <= xmid && b[:x1] >= xmid && b[:z0] >= jz - 0.5 && b[:z0] < jz + 40 && (b[:z1] - b[:z0]) <= 30 }.min_by { |b| b[:z0] }
      if lowtop && upbot
        dx = mp.x(lowtop[:d1]) + 5
        sh.dim_v(mp.y(lowtop[:z1]), mp.y(lowtop[:z0]), dx, ED.fmt(lowtop[:z1] - lowtop[:z0]), from_x: mp.x(lowtop[:d1]) + 0.5, side: :right)
        sh.dim_v(mp.y(upbot[:z1]), mp.y(upbot[:z0]), dx + 9, ED.fmt(upbot[:z1] - upbot[:z0]), from_x: mp.x(upbot[:d1]) + 0.5, side: :right)
      end
      sh.text(x + (sh.rtl ? w - 2 : 2), y + h - 3, "#{ED.t(lang, 'scale')} #{ED.scale_label(n)}", size: 2.8, anchor: :left)
    end

    def stack_sheets(groups, ctx)
      ProductionPackagesHelper.assemblies(groups).filter_map do |code, mods|
        next unless mods[:lower] && mods[:upper]

        stack_sheet(code, mods[:lower], mods[:upper], ctx)
      end
    end

    module ProductionPackagesHelper
      module_function

      def assemblies(groups)
        TallStack.assemblies(groups)
      end
    end
  end
end
