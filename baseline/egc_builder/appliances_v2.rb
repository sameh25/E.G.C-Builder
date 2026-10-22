# frozen_string_literal: true

module EGC
  # Detailed replacements for the appliance builders (loaded after appliances.rb, so they take over).
  # Every builder uses ONE consistent frame: x left->right, d from the back (0) to the FRONT face
  # (d = dep), z up. The old builders placed oven/microwave front details at d-2/d-4, i.e. on the
  # BACK of the housing, and drew most fronts as 2-5 mm relief that is invisible at normal zoom.
  # These give real proud doors, recessed-looking glass, proper handles and control panels.
  module Appliances
    module_function

    # protruding slab whose FRONT face sits `inset` mm behind the appliance front (d = front)
    def slab(ents, x, z, w, h, front, t, material, inset = 0)
      box(ents, x, front - inset - t, z, w, t, h, material)
    end

    # door / drawer front with its two FRONT vertical edges rounded (radius r, smooth) - same outer size as slab
    def rslab(ents, x, z, w, h, front, t, material, r = 9.0)
      r = [r, t * 0.6, w * 0.2].min
      return slab(ents, x, z, w, h, front, t, material) if r < 2

      g = ents.add_group
      d0 = front - t
      arc = ->(cx, cd, a0) { (0..6).map { |i| a = (a0 + i * 15.0) * Math::PI / 180.0; [cx + r * Math.cos(a), cd + r * Math.sin(a)] } }
      pts = [[x, d0], [x + w, d0]] + arc.call(x + w - r, front - r, 0.0) + arc.call(x + r, front - r, 90.0)
      f = g.entities.add_face(pts.map { |px, pd| Geo.p3(px, pd, z) })
      return slab(ents, x, z, w, h, front, t, material) unless f

      f.pushpull((f.normal.z >= 0 ? 1 : -1) * Geo.mm(h))
      g.entities.grep(Sketchup::Edge).each do |e|
        v = e.line[1]
        next unless v.z.abs > 0.99

        px = e.start.position.x.to_mm
        pd = -e.start.position.y.to_mm
        next if pd < d0 + 0.5 || ((px - x).abs < 0.01 && pd < front - r + 0.01) || ((px - x - w).abs < 0.01 && pd < front - r + 0.01)

        e.soft = true
        e.smooth = true
      end
      g.material = material
      g
    rescue StandardError
      g.erase! if g&.valid?
      slab(ents, x, z, w, h, front, t, material)
    end

    # horizontal bar handle standing off the front by `off`
    def hbar(ents, x0, x1, z, front, material, off = 30, r = 6)
      [x0 + 24, x1 - 24].each { |px| cyl(ents, px, front - 2, z, r * 0.7, off + 2, material, :y, 12) }
      cyl(ents, x0, front + off - 2, z, r, x1 - x0, material, :x, 14)
    end

    # vertical bar handle
    def vbar(ents, x, z0, z1, front, material, off = 30, r = 7)
      [z0 + 30, z1 - 30].each { |pz| cyl(ents, x, front - 2, pz, r * 0.7, off + 2, material, :y, 12) }
      cyl(ents, x, front + off - 2, z0, r, z1 - z0, material, :z, 14)
    end

    def button_row(ents, x0, z, count, gap, front, material, size = 10)
      count.times { |i| slab(ents, x0 + i * gap, z, size, size * 0.6, front, 3, material, -1) }
    end

    # tapered block (canopy): rectangle w0 x dp0 at z narrowing to w1 x dp1 at z + h, centred on the base
    def frustum(ents, x, d, z, w0, dp0, w1, dp1, h, material)
      g = ents.add_group
      e = g.entities
      ox = (w0 - w1) / 2.0
      od = (dp0 - dp1) / 2.0
      b = [[0, 0], [w0, 0], [w0, dp0], [0, dp0]].map { |px, pd| Geo.p3(px, pd, 0) }
      t = [[ox, od], [ox + w1, od], [ox + w1, od + dp1], [ox, od + dp1]].map { |px, pd| Geo.p3(px, pd, h) }
      e.add_face(b)
      e.add_face(t)
      4.times { |i| e.add_face(b[i], b[(i + 1) % 4], t[(i + 1) % 4], t[i]) }
      g.transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), -Geo.mm(d), Geo.mm(z))))
      g.material = material
      g
    end

    # ---- reusable detail builders (fixed-size details are never stretched with the appliance) -------------------
    # frame ring around a glass / panel: 4 thin strips standing proud of the front
    def bezel(ents, x, z, w, h, front, t, material, wd = 8, off = 0)
      slab(ents, x, z, w, wd, front, t, material, off)
      slab(ents, x, z + h - wd, w, wd, front, t, material, off)
      slab(ents, x, z + wd, wd, h - 2 * wd, front, t, material, off)
      slab(ents, x + w - wd, z + wd, wd, h - 2 * wd, front, t, material, off)
    end

    # dark gap / gasket line between two doors or door and body
    def seal_v(ents, x, z0, z1, front, material, wd = 3)
      slab(ents, x, z0, wd, z1 - z0, front, 2, material, -1)
    end

    def seal_h(ents, x0, x1, z, front, material, ht = 3)
      slab(ents, x0, z, x1 - x0, ht, front, 2, material, -1)
    end

    # row of vent slots
    def vent_slots(ents, x, z, w, count, front, material, sl_h = 3, sl_w = 26)
      pitch = w / count.to_f
      count.times { |i| slab(ents, x + i * pitch + (pitch - sl_w) / 2.0, z, sl_w, sl_h, front, 2, material, -1) }
    end

    # recessed finger grip (dark channel) along the top of a door
    def recessed_grip(ents, x, w, z, front, material)
      slab(ents, x, z, w, 14, front, 4, material, -1)
      slab(ents, x, z + 14, w, 2, front, 3, pal[:chrome], -1)
    end

    # two adjustable feet / plinth grille near the bottom
    def feet(ents, x, d, z, w, dep, material, h = 16)
      [[x + 30, d + 30], [x + w - 46, d + 30], [x + 30, d + dep - 46], [x + w - 46, d + dep - 46]].each do |fx, fy|
        cyl(ents, fx + 8, fy + 8, z, 8, h, material, :z, 10)
      end
    end

    # louvre / filter grille
    def grille(ents, x, d, z, w, dep, material, bars = 9)
      gap = dep / bars.to_f
      bars.times { |i| box(ents, x, d + i * gap + gap * 0.25, z, w, gap * 0.5, 3, material) }
    end

    # ------------------------------------------------------------------ oven
    def oven(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      cs = h > 500 ? 74.0 : 62.0
      dh = h - cs
      box(ents, x, d, z, w, dep - 24, h, p[:enamel])
      # control panel
      slab(ents, x, z + dh, w, cs, d + dep, 24, p[:body])
      slab(ents, x + w * 0.5 - 62, z + dh + cs * 0.3, 124, cs * 0.4, d + dep, 3, p[:black], -1)
      slab(ents, x + w * 0.5 - 50, z + dh + cs * 0.44, 100, 8, d + dep, 3, p[:blue], -4)
      [0.11, 0.25, 0.75, 0.89].each { |k| knob(ents, x + w * k, d + dep, z + dh + cs * 0.5, 13, p[:grey_dk]) }
      # door: steel frame + smoked glass + bar handle
      slab(ents, x + 2, z + 2, w - 4, dh - 4, d + dep, 24, p[:steel_dk])
      slab(ents, x + w * 0.09, z + dh * 0.16, w * 0.82, dh * 0.66, d + dep, 3, p[:smoke], -1)
      slab(ents, x + w * 0.09, z + dh * 0.16 - 4, w * 0.82, 4, d + dep, 4, p[:black], -1)
      bezel(ents, x + w * 0.085, z + dh * 0.15, w * 0.83, dh * 0.68, d + dep, 5, p[:chrome], 5, -1)
      seal_h(ents, x + 2, x + w - 2, z + dh - 3, d + dep, p[:black])
      vent_slots(ents, x + w * 0.2, z + dh * 0.05, w * 0.6, 12, d + dep, p[:black], 3, 18)
      hbar(ents, x + w * 0.1, x + w * 0.9, z + dh - 30, d + dep, p[:chrome], 34, 7)
    end

    # ------------------------------------------------------------------ microwave
    def microwave(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      col = [w * 0.24, 80.0].min
      box(ents, x, d, z, w, dep - 22, h, p[:body])
      dw = w - col - 6
      slab(ents, x + 3, z + 3, dw, h - 6, d + dep, 22, p[:steel_dk])
      slab(ents, x + 3 + dw * 0.08, z + h * 0.14, dw * 0.84, h * 0.72, d + dep, 3, p[:smoke], -1)
      slab(ents, x + w - col, z + 3, col - 3, h - 6, d + dep, 22, p[:body])
      slab(ents, x + w - col + 8, z + h * 0.62, col - 19, h * 0.24, d + dep, 3, p[:black], -1)
      slab(ents, x + w - col + 12, z + h * 0.7, col - 27, 6, d + dep, 3, p[:blue], -4)
      3.times { |i| slab(ents, x + w - col + 10, z + h * 0.22 + i * (h * 0.11), col - 23, h * 0.07, d + dep, 3, p[:grey_dk], -1) }
      knob(ents, x + w - col * 0.5 - 3, d + dep, z + h * 0.42, 9, p[:grey_dk])
      vbar(ents, x + dw - 4, z + h * 0.18, z + h * 0.82, d + dep, p[:chrome], 22, 5)
    end

    # ------------------------------------------------------------------ hobs (knobs on the FRONT edge)
    def hob_electric(ents, x, d, z, w, dep, h, cfg = {})
      p = pal
      induction = cfg['hob_style'].to_s == 'induction'
      box(ents, x, d, z, w, dep, h, p[:ceramic])
      box(ents, x - 4, d - 4, z + h - 4, w + 8, dep + 8, 4, p[:steel_dk])
      # Continuous black-glass top plate sits above the appliance chassis; the printed zones and
      # capacitive controls below are separate geometry, not markings painted onto a block.
      box(ents, x + 4, d + 4, z + h - 0.5, w - 8, dep - 8, 1.2, p[:black])
      cols = w < 400 ? [0.5] : (w > 700 ? [0.22, 0.5, 0.78] : [0.28, 0.72])
      rows = dep > 400 ? [0.32, 0.68] : [0.5]
      cols.each do |cx|
        rows.each do |cy|
          zx = x + w * cx
          zy = d + dep * cy
          if induction # induction: no glowing rings - a thin printed circle and a cross mark where the pan stands
            ring(ents, zx, zy, z + h + 0.7, 88, 86.5, 0.3, p[:grey_dk], :z, 32)
            box(ents, zx - 16, zy - 0.8, z + h + 0.7, 32, 1.6, 0.3, p[:grey_dk])
            box(ents, zx - 0.8, zy - 16, z + h + 0.7, 1.6, 32, 0.3, p[:grey_dk])
          else
            hob_zone(ents, zx, zy, z + h, 62, p[:zone], p[:steel_dk])
          end
        end
      end
      cols.each { |cx| slab(ents, x + w * cx - 7, z + h - 3, 14, 3, d + dep, 3, p[:grey_dk], -1) }
      seal_h(ents, x + 8, x + w - 8, z + h - 2, d + dep - 30, p[:steel_dk], 2)
      # touch-control strip on the glass (front edge): dark band, power key, slider dots and a timer display
      box(ents, x + w * 0.22, d + dep - 50, z + h, w * 0.56, 30, 0.6, p[:black])
      box(ents, x + w * 0.22 + 12, d + dep - 42, z + h + 0.6, 12, 12, 0.4, p[:led])
      7.times { |i| box(ents, x + w * 0.36 + i * (w * 0.28 / 6.0) - 3, d + dep - 38, z + h + 0.6, 6, 6, 0.4, p[:blue]) }
      box(ents, x + w * 0.78 - 34, d + dep - 42, z + h + 0.6, 22, 12, 0.4, p[:blue])
      cols.each { |cx| rows.each { |cy| hob_zone(ents, x + w * cx, d + dep * cy, z + h + 0.5, 34, p[:steel_dk], p[:zone]) } if false }
    end

    # cast-iron pan support (reusable): four corner feet, rectangular frame, two cross bars and the centre ring for one burner
    def gas_grate(ents, x, d, z, gs, gd)
      # Built from plain boxes inside ONE definition: nesting MechParts.defn calls invalidates the outer Entities reference in SketchUp 2026
      # (the whole gas hob then silently fell back to a flat slab).
      df = MechParts.defn("gas_grate_v16_#{gs.round}_#{gd.round}") do |e|
        mt = 9.0
        bh = 8.0
        box = ->(bx, bd, bz, sx, sd, sz) { Geo.box(e, bx, bd, bz, sx, sd, sz) }
        [[0, 0], [gs - 10, 0], [0, gd - 10], [gs - 10, gd - 10]].each { |fx, fd| box.call(fx, fd, 0, 10, 10, 14) }
        box.call(0, 0, 14, gs, mt, bh)
        box.call(0, gd - mt, 14, gs, mt, bh)
        box.call(0, 0, 14, mt, gd, bh)
        box.call(gs - mt, 0, 14, mt, gd, bh)
        box.call(gs / 2.0 - 4, 0, 14, 8, gd, bh - 2)
        box.call(0, gd / 2.0 - 4, 14, gs, 8, bh - 2)
        c = Geom::Point3d.new(Geo.mm(gs / 2.0), -Geo.mm(gd / 2.0), Geo.mm(14))
        f = e.add_face(e.add_circle(c, Geom::Vector3d.new(0, 0, 1), Geo.mm(26), 16))
        f&.pushpull(f.normal.z >= 0 ? Geo.mm(bh) : -Geo.mm(bh))
        e.grep(Sketchup::Face).each { |fc| fc.material = pal[:cast]; fc.back_material = pal[:cast] }
      end
      MechParts.put(ents, df, x, d, z)
    end

    def hob_gas(ents, x, d, z, w, dep, h, cfg = {})
      p = pal
      glass = cfg['hob_style'].to_s == 'glass' # gas on glass: a black tempered-glass plate instead of the stainless tray
      box(ents, x, d, z, w, dep, h, p[:body])
      box(ents, x + 6, d + 6, z + h - 3, w - 12, dep - 12, 3.4, glass ? p[:black] : p[:steel_dk]) # spill tray (just proud of the body top: no two faces in one plane)
      # Raised stainless tray lip over the chassis, with a separate burner deck and cast supports.
      box(ents, x + 3, d + 3, z + h - 1.2, w - 6, 2.4, 2.0, p[:chrome])
      box(ents, x + 3, d + dep - 5.4, z + h - 1.2, w - 6, 2.4, 2.0, p[:chrome])
      box(ents, x + 3, d + 5, z + h - 1.2, 2.4, dep - 10, 2.0, p[:chrome])
      box(ents, x + w - 5.4, d + 5, z + h - 1.2, 2.4, dep - 10, 2.0, p[:chrome])
      box(ents, x + 2, d + 2, z + h - 1.5, w - 4, 3, 1.5, p[:steel_dk])                  # rim bead (front / back)
      box(ents, x + 2, d + dep - 5, z + h - 1.5, w - 4, 3, 1.5, p[:steel_dk])
      cols = w < 400 ? [0.5] : (w > 700 ? [0.2, 0.5, 0.8] : [0.28, 0.72])
      rows = dep > 420 ? [0.3, 0.7] : [0.5]
      gs = [w / cols.size - 36, 214.0].min
      gd = [dep / rows.size - 36, 214.0].min
      # [across, depth, size]: a wide hob (70 / 90) has five burners - the big wok burner alone in the middle
      burners = cols.flat_map { |cx| cols.size == 3 && cx == 0.5 ? [[cx, 0.5, 1.35]] : rows.map { |cy| [cx, cy, 1.0] } }
      burners.each do |cx, cy, k|
        bx = x + w * cx
        by = d + dep * cy
        cyl(ents, bx, by, z + h - 3, 26 * k, 9, p[:cast], :z, 20)                        # burner crown
        cyl(ents, bx, by, z + h + 6, 17 * k, 6, p[:steel_dk], :z, 20)                    # burner cap
        ring(ents, bx, by, z + h + 6, 26 * k, 22 * k, 3, p[:black], :z, 20)             # flame ports
        gas_grate(ents, bx - gs / 2.0, by - gd / 2.0, z + h, gs, gd)                     # cast-iron pan support
      end
      # control knobs ON the top plate, one per burner, in a row at the front edge (a built-in hob has no front apron: its body is in the worktop)
      nb = burners.size
      nb.times do |i|
        kx = x + w * 0.5 + (i - (nb - 1) / 2.0) * 44.0
        cyl(ents, kx, d + dep - 30, z + h, 17, 2.5, p[:chrome], :z, 20)                 # chrome base ring
        cyl(ents, kx, d + dep - 30, z + h + 2.5, 13, 15, p[:grey_dk], :z, 16)
        box(ents, kx - 1.5, d + dep - 42, z + h + 17.5, 3, 10, 0.8, p[:chrome])
      end
    end

    # ------------------------------------------------------------------ hoods
    # WALL RAIL with accessories (generic): an aluminium rail screwed to the wall; a hook strip, a shelf, a roll holder and a utensil cup hang on it
    def wall_rail(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      zr = z + h - 30
      rd = d + 38                                                                   # axis of the round rail, off the wall
      cyl(ents, x + 6, rd, zr, 8, w - 12, p[:chrome], :x, 20)                        # the rail, dia 16
      [x, x + w - 6].each { |ex| cyl(ents, ex, rd, zr, 9.5, 6, p[:chrome], :x, 20) }   # end caps: the rail is the full width
      ([x + 50, x + w - 50] + (w > 1000 ? [x + w / 2.0] : [])).each do |bx|          # wall brackets: rose + stem
        cyl(ents, bx, d, zr, 15, 5, p[:chrome], :y, 24)
        cyl(ents, bx, d + 5, zr, 5, rd - d - 5, p[:chrome], :y, 12)
      end
      # S-hooks with utensils (left part of the rail)
      n = [(w * 0.26 / 52).floor, 3].max
      n.times do |i|
        hx = x + 70 + i * 52
        cyl(ents, hx, rd, zr - 46, 1.8, 38, p[:chrome], :z, 8)
        cyl(ents, hx, rd, zr - 48, 1.8, 10, p[:chrome], :y, 8)
        len = [190 - i * 30, 120].max
        cyl(ents, hx, rd + 8, zr - 48 - len, 3.2, len, p[:body], :z, 10)          # handle
        if i.even?
          cyl(ents, hx, rd + 8, zr - 48 - len - 22, 34, 22, p[:body], :z, 24)     # ladle / strainer head
        else
          box(ents, hx - 28, rd + 6, zr - 48 - len - 50, 56, 4, 56, p[:body])     # turner blade
        end
      end
      # wire shelf hanging on the rail
      sx = x + w * 0.36
      sw = [w * 0.3, 360.0].min
      zs = zr - 160
      [sx + 20, sx + sw - 20].each { |hx| cyl(ents, hx, rd - 4, zs, 2.2, zr - zs - 6, p[:chrome], :z, 8) } # hangers
      (0..5).each { |k| cyl(ents, sx, d + 20 + k * 19, zs, 2.2, sw, p[:chrome], :x, 8) }               # floor wires
      [zs + 22, zs + 44].each { |rz| cyl(ents, sx, d + 118, rz, 2.2, sw, p[:chrome], :x, 8) }           # front rails
      [sx, sx + sw].each { |ex| cyl(ents, ex, d + 20, zs + 44, 2.2, 98, p[:chrome], :y, 8); cyl(ents, ex, d + 118, zs, 2.2, 44, p[:chrome], :z, 8) }
      [[0.0, 40], [0.22, 34], [0.42, 40], [0.62, 30], [0.8, 38]].each do |k, r|                           # jars
        cyl(ents, sx + 24 + k * (sw - 48), d + 50, zs + 3, r * 0.5, 90, p[:glass], :z, 16)
        cyl(ents, sx + 24 + k * (sw - 48), d + 50, zs + 93, r * 0.52, 14, p[:grey_dk], :z, 16)
      end
      # kitchen roll holder
      rw = [w * 0.2, 280.0].min
      rx = x + w - rw - 70
      [rx, rx + rw].each { |ax| cyl(ents, ax, rd, zr - 96, 2.8, 90, p[:chrome], :z, 10) }
      cyl(ents, rx, rd + 30, zr - 96, 4, rw, p[:chrome], :x, 12)
      cyl(ents, rx + 8, rd + 30, zr - 96, 55, rw - 16, p[:white], :x, 32)           # the roll
      cyl(ents, rx + 6, rd + 30, zr - 96, 20, 3, p[:wood], :x, 20)
    end

    def hood_slim(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      box(ents, x, d, z + h * 0.35, w, dep, h * 0.65, p[:body])
      slab(ents, x + 6, z, w - 12, h * 0.52, d + dep, 10, p[:black])   # front glass runs down to the nominal bottom (overall height = nominal)
      box(ents, x + 12, d + 12, z + h * 0.35 - 2, w - 24, dep - 24, 2, p[:steel_dk])
      3.times { |i| slab(ents, x + w * 0.5 - 20 + i * 14, z + h * 0.42, 6, 6, d + dep, 3, p[:led], -1) }
      slab(ents, x, z + h * 0.6, w, h * 0.4, d + dep, 5, p[:body])
      grille(ents, x + 16, d + 30, z + h * 0.35 - 5, w - 32, dep - 60, p[:steel_dk], 8)
      hbar(ents, x + w * 0.12, x + w * 0.88, z + 4, d + dep, p[:chrome], 8, 3)          # pull-out visor grip
      vent_slots(ents, x + w * 0.15, z + h * 0.72, w * 0.7, 14, d + dep, p[:black], 3, 30) # intake / filter slots
    end

    def hood_chimney(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      body_h = 260.0
      box(ents, x + w * 0.5 - 100, d + dep * 0.5 - 80, z + body_h, 200, 160, [h - body_h, 100].max, p[:body])
      box(ents, x, d, z, w, dep, 70, p[:body])
      frustum(ents, x, d, z + 70, w, dep, 200, 160, body_h - 70, p[:body])
      box(ents, x + w * 0.5 - 104, d + dep * 0.5 - 84, z + body_h - 4, 208, 168, 8, p[:steel_dk]) # chimney collar
      slab(ents, x + w * 0.06, z + 14, w * 0.88, 60, d + dep, 4, p[:black], -1)
      3.times { |i| slab(ents, x + w * 0.5 - 24 + i * 24, z + 6, 10, 6, d + dep, 3, p[:led], -1) }
      box(ents, x + 20, d + 20, z - 2, w - 40, dep - 40, 2, p[:steel_dk])
      grille(ents, x + 30, d + 30, z - 4, w - 60, dep - 60, p[:steel_dk], 9)
      slab(ents, x + w * 0.5 - 100, z + 90, 200, 6, d + dep * 0.5 + 80, 3, p[:steel_dk], -1)
    end

    # ------------------------------------------------------------------ fridge / freezer
    def fridge(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      box(ents, x, d, z, w, dep - 30, h, p[:body])
      if h < 1200 # under-counter: one door, top handle bar
        slab(ents, x + 2, z + 2, w - 4, h - 4, d + dep, 30, p[:steel_dk])
        slab(ents, x + 8, z + h - 60, w - 16, 3, d + dep, 3, p[:black], -1)
        hbar(ents, x + 30, x + w - 30, z + h - 90, d + dep, p[:chrome], 28, 7)
        return
      end
      if w >= 800 # side-by-side American style: freezer left (with water/ice dispenser), fridge right
        fw = w * 0.4
        slab(ents, x + 2, z + 4, fw - 3, h - 8, d + dep, 30, p[:steel_dk])
        slab(ents, x + fw + 1, z + 4, w - fw - 3, h - 8, d + dep, 30, p[:steel_dk])
        slab(ents, x + fw * 0.5 - 60, z + h * 0.52, 120, 200, d + dep, 3, p[:black], -1)
        slab(ents, x + fw * 0.5 - 45, z + h * 0.52 + 120, 90, 50, d + dep, 3, p[:blue], -4)
        box(ents, x + fw * 0.5 - 35, d + dep - 20, z + h * 0.52 + 30, 70, 20, 10, p[:steel_dk])
        vbar(ents, x + fw - 22, z + h * 0.35, z + h * 0.35 + 620, d + dep, p[:chrome], 30, 8)
        vbar(ents, x + fw + 20, z + h * 0.35, z + h * 0.35 + 620, d + dep, p[:chrome], 30, 8)
        seal_v(ents, x + fw - 1, z + 6, z + h - 6, d + dep, p[:black], 4)
        bezel(ents, x + fw * 0.5 - 66, z + h * 0.52 - 6, 132, 212, d + dep, 3, p[:chrome], 3, -2)
        slab(ents, x + fw * 0.5 - 50, z + h * 0.52 - 12, 100, 10, d + dep, 14, p[:chrome], 0) # drip tray
        [x + 12, x + w - 40].each { |hx| [z + 8, z + h - 30].each { |hz| slab(ents, hx, hz, 28, 22, d + dep, 3, p[:grey_dk], -1) } }
        vent_slots(ents, x + 30, z + 4, w - 60, 14, d + dep, p[:black], 3, 28)
        feet(ents, x, d, z - 10, w, dep, p[:rubber], 10)
        return
      end
      split = h * 0.32
      slab(ents, x + 2, z + split + 2, w - 4, h - split - 4, d + dep, 30, p[:steel_dk])
      slab(ents, x + 2, z + 2, w - 4, split - 6, d + dep, 30, p[:steel_dk])
      slab(ents, x + w * 0.5 - 40, z + h - 120, 80, 40, d + dep, 3, p[:black], -1)
      slab(ents, x + w * 0.5 - 30, z + h - 108, 60, 6, d + dep, 3, p[:blue], -4)
      vbar(ents, x + w - 34, z + split + 60, z + split + 60 + [h * 0.3, 420].min, d + dep, p[:chrome], 30, 8)
      vbar(ents, x + w - 34, z + split * 0.25, z + split * 0.25 + [split * 0.6, 260].min, d + dep, p[:chrome], 30, 8)
    end

    def freezer(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      box(ents, x, d, z, w, dep - 30, h, p[:body])
      n = h > 1500 ? 5 : 3
      dh = (h - 8) / n
      n.times do |i|
        slab(ents, x + 2, z + 4 + i * dh, w - 4, dh - 4, d + dep, 30, p[:steel_dk])
        hbar(ents, x + w * 0.2, x + w * 0.8, z + 4 + i * dh + dh - 40, d + dep, p[:chrome], 26, 6)
      end
      slab(ents, x + w * 0.5 - 30, z + h - 60, 60, 6, d + dep, 3, p[:blue], -4)
    end

    # ------------------------------------------------------------------ dishwasher
    def dishwasher(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      cs = 74.0
      box(ents, x, d, z, w, dep - 22, h, p[:body])
      slab(ents, x + 2, z + 2, w - 4, h - cs - 4, d + dep, 22, p[:steel_dk])
      slab(ents, x + 2, z + h - cs, w - 4, cs - 2, d + dep, 22, p[:black])
      slab(ents, x + w * 0.5 - 50, z + h - cs + 30, 100, 10, d + dep, 3, p[:blue], -1)
      6.times { |i| slab(ents, x + 24 + i * ((w - 60) / 5.0), z + h - cs + 12, 12, 8, d + dep, 3, p[:grey_dk], -1) }
      knob(ents, x + w - 42, d + dep, z + h - cs * 0.5 + 6, 13, p[:grey_dk])
      hbar(ents, x + 50, x + w - 50, z + h - cs - 46, d + dep, p[:chrome], 30, 8)
      slab(ents, x + 10, z + 6, w - 20, 12, d + dep, 6, p[:steel_dk], -1) # kick strip
      seal_h(ents, x + 2, x + w - 2, z + h - cs - 3, d + dep, p[:black])
      bezel(ents, x + 6, z + h - cs + 4, w - 12, cs - 10, d + dep, 3, p[:steel_dk], 4, -1)
      vent_slots(ents, x + w * 0.25, z + 24, w * 0.5, 10, d + dep, p[:black], 3, 16)
    end

    # ------------------------------------------------------------------ coffee machine
    def coffee(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      box(ents, x, d, z, w, dep - 20, h, p[:body])
      slab(ents, x + 2, z + 2, w - 4, h - 4, d + dep, 20, p[:black])
      slab(ents, x + 2, z + 2, w - 4, 6, d + dep, 22, p[:steel_dk])
      slab(ents, x + 2, z + h - 8, w - 4, 6, d + dep, 22, p[:steel_dk])
      slab(ents, x + w * 0.5 - 60, z + h - 90, 120, 44, d + dep, 3, p[:blue], -1)
      3.times { |i| knob(ents, x + w * (0.16 + i * 0.09), d + dep, z + h - 68, 11, p[:steel_dk]) }
      3.times { |i| knob(ents, x + w * (0.66 + i * 0.09), d + dep, z + h - 68, 11, p[:steel_dk]) }
      box(ents, x + w * 0.5 - 42, d + dep - 60, z + h * 0.34, 84, 72, 46, p[:steel_dk])       # spout block
      box(ents, x + w * 0.5 - 3, d + dep + 8, z + h * 0.34 - 14, 6, 6, 14, p[:chrome])         # nozzle
      box(ents, x + w * 0.5 - 80, d + dep - 40, z + 30, 160, 60, 5, p[:steel_dk])              # cup tray
      box(ents, x + w * 0.5 - 76, d + dep - 36, z + 24, 152, 52, 6, p[:grey_dk])
    end

    # ------------------------------------------------------------------ warming drawer
    def warming_drawer(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      box(ents, x, d, z, w, dep - 22, h, p[:body])
      slab(ents, x + 2, z + 2, w - 4, h - 4, d + dep, 22, p[:steel_dk])
      slab(ents, x + 8, z + h - 30, w - 16, 20, d + dep, 3, p[:black], -1)
      slab(ents, x + w * 0.5 - 28, z + h - 24, 56, 6, d + dep, 3, p[:blue], -4)
      hbar(ents, x + w * 0.16, x + w * 0.84, z + h * 0.4, d + dep, p[:chrome], 26, 6)
    end

    # ------------------------------------------------------------------ wine cooler
    def wine_cooler(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      box(ents, x, d, z, w, dep - 30, h, p[:body])
      4.times { |i| box(ents, x + 12, d + 12, z + 40 + i * ((h - 100) / 3.5), w - 24, dep - 60, 4, p[:wood]) } # shelves behind glass
      slab(ents, x + 2, z + 2, w - 4, h - 4, d + dep, 30, p[:steel_dk])
      slab(ents, x + 12, z + 12, w - 24, h - 24, d + dep, 3, p[:smoke], -1)
      slab(ents, x + w * 0.5 - 30, z + h - 20, 60, 4, d + dep, 3, p[:blue], -4)
      vbar(ents, x + w - 20, z + h * 0.25, z + h * 0.75, d + dep, p[:chrome], 26, 6)
    end

    # ------------------------------------------------------------------ sink (hollow bowls + rim + drain + tap)
    def sink(ents, x, d, z, w, dep, h, cfg = {})
      p = pal
      double = cfg.key?('sink_double') ? cfg['sink_double'] : w > 700
      rim_h = 3.0 # stainless lip lying on the worktop (about 3 mm proud)
      m = 15.0 # rim width around the opening
      bowls = double ? [[m, w * 0.55 - m - 6], [w * 0.55 + 6, w * 0.45 - m - 6]] : [[m, w - 2 * m]]
      depth = 170.0
      t = 3.0
      y0 = d + m
      yd = dep - 2 * m
      # rim frame around the openings (top surface stays open so the bowls are visible)
      box(ents, x, d, z, w, m, rim_h, p[:basin])
      box(ents, x, d + dep - m, z, w, m, rim_h, p[:basin])
      edges = [0.0] + bowls.flat_map { |bx, bw| [bx, bx + bw] } + [w]
      edges.each_slice(2) { |a, b| box(ents, x + a, y0, z, b - a, yd, rim_h, p[:basin]) if b - a > 0.5 }
      bowls.each_with_index do |(bx, bw), i|
        gx = x + bx
        box(ents, gx, y0, z - depth, bw, yd, t, p[:basin])                            # bottom
        box(ents, gx, y0, z - depth, t, yd, depth, p[:basin])                         # left wall
        box(ents, gx + bw - t, y0, z - depth, t, yd, depth, p[:basin])                # right wall
        box(ents, gx, y0, z - depth, bw, t, depth, p[:basin])                         # back wall
        box(ents, gx, y0 + yd - t, z - depth, bw, t, depth, p[:basin])                # front wall
        cyl(ents, gx + bw * 0.5, y0 + yd * 0.5, z - depth + t, 24, 2, p[:steel_dk], :z, 16)
        cyl(ents, gx + bw * 0.5, y0 + yd * 0.5, z - depth + t + 2, 9, 1, p[:black], :z, 12) if i.zero?
      end
      if double
        box(ents, x + w * 0.55 - 6, y0, z - depth, 12, yd, depth, p[:basin]) # divider
      end
      tapx = x + w * 0.5
      cyl(ents, tapx, d + m * 0.5, z + rim_h, 11, 130, p[:tap], :z, 16)
      cyl(ents, tapx, d + m * 0.5, z + rim_h + 118, 9, 95, p[:tap], :y, 16)
      cyl(ents, tapx, d + m * 0.5 + 92, z + rim_h + 100, 7, 20, p[:tap], :z, 12)
      cyl(ents, tapx, d + m * 0.5, z + rim_h, 11, 6, p[:tap], :z, 16)                    # tap base flange
      cyl(ents, tapx + 11, d + m * 0.5, z + rim_h + 62, 3.2, 38, p[:tap], :x, 8)         # single lever handle
      cyl(ents, tapx + 78, d + 20, z + rim_h, 13, 8, p[:steel_dk], :z, 12)          # soap dispenser base
      cyl(ents, tapx + 78, d + 20, z + rim_h + 8, 4, 62, p[:tap], :z, 8)            # dispenser column
      cyl(ents, tapx + 78, d + 34, z + rim_h + 62, 2.6, 14, p[:tap], :y, 8)   # dispenser spout
      box(ents, x + w * 0.5 - 40, d + dep - 40, z + rim_h, 80, 30, 3, p[:wood]) if cfg['sink_board']
    end
  end
end
