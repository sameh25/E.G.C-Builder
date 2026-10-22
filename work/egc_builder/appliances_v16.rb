# frozen_string_literal: true

module EGC
  # TEST_16 appliance geometry pass (original E.G.C geometry; no manufacturer CAD). Loaded after appliances_v3:
  #   * sink: rounded-corner bowls (real hollow solids, 3 mm steel wall), a single rim plate with rounded openings,
  #     drain strainer + overflow slot, bowl depth 170 mm below the rim (rim = worktop level)
  #   * chimney hood: telescopic two-part chimney (visible seam), front control strip and canopy edge lip
  module Appliances
    module_function

    # rounded rectangle outline in builder coordinates (x, d) at height z; corner arcs are `seg` segments
    def rr_pts(x, d, z, w, dep, r, seg = 5)
      r = [[r, w / 2.0 - 0.1].min, dep / 2.0 - 0.1].min
      pts = []
      [[x + w - r, d + r, -90.0], [x + w - r, d + dep - r, 0.0], [x + r, d + dep - r, 90.0], [x + r, d + r, 180.0]].each do |cx, cd, a0|
        (0..seg).each do |i|
          a = (a0 + 90.0 * i / seg) * Math::PI / 180.0
          pts << Geo.p3(cx + r * Math.cos(a), cd + r * Math.sin(a), z)
        end
      end
      pts
    end

    # hollow rounded bowl: outline (x, d, bw, bd) at the rim z, `depth` below it, wall thickness t, outer corner radius r
    def sink_bowl(ents, x, d, z_top, bw, bd, depth, t, r, material)
      g = ents.add_group
      e = g.entities
      f = e.add_face(rr_pts(x, d, z_top - depth, bw, bd, r))
      raise 'sink bowl outline failed' unless f

      f.pushpull(f.normal.z >= 0 ? Geo.mm(depth) : -Geo.mm(depth))
      inner = e.add_face(rr_pts(x + t, d + t, z_top, bw - 2 * t, bd - 2 * t, r - t))
      raise 'sink bowl opening failed' unless inner

      inner.pushpull(inner.normal.z >= 0 ? -Geo.mm(depth - t) : Geo.mm(depth - t))
      g.material = material
      g
    end

    # round tube along a path of builder points [x, d, z] (mm)
    def tube(ents, pts, r, material)
      g = ents.add_group
      e = g.entities
      ps = pts.map { |px, pd, pz| Geo.p3(px, pd, pz) }
      path = e.add_curve(ps)
      f = e.add_face(e.add_circle(ps[0], ps[0].vector_to(ps[1]), Geo.mm(r), 14))
      f&.followme(path)
      g.material = material
      g
    rescue StandardError
      g.erase! if g&.valid?
      cyl(ents, pts[0][0], pts[0][1], pts[0][2], r, (pts.map { |q| q[2] }.max - pts[0][2]).abs, material, :z, 14)
    end

    # mixer tap with a swan neck: base plate, body with a side lever, neck arching `reach` mm along dir = [ux, ud], aerator pointing down
    def swan_tap(ents, tx, td, tz, dir, material, reach = 156.0, rise = 230.0)
      rr = reach / 2.0
      cyl(ents, tx, td, tz, 24, 4, material, :z, 24)
      cyl(ents, tx, td, tz + 4, 17, 46, material, :z, 20)
      arc = (0..12).map do |i|
        a = Math::PI * (1.0 - i / 12.0 * 1.12)
        s = rr + rr * Math.cos(a)
        [tx + dir[0] * s, td + dir[1] * s, tz + rise + rr * Math.sin(a)]
      end
      tube(ents, [[tx, td, tz + 50]] + arc, 9.5, material)
      cyl(ents, arc.last[0], arc.last[1], arc.last[2] - 14, 11, 16, material, :z, 16)
      cyl(ents, tx - dir[1] * 16 - (dir[1].abs > 0.5 ? 0 : 0), td + dir[0] * 16, tz + 30, 3.2, 34, material, dir[1].abs > 0.5 ? :x : :y, 8) # lever on the side
    end

    # FULLY ROUND sink: a round lip on the worktop, a round bowl under it; the tap stands on the worktop beside it
    def sink_round(ents, x, d, z, w, dep, cfg, p)
      rad = [w, dep].min / 2.0
      cx = x + w / 2.0
      cd = d + dep / 2.0
      depth = 170.0
      t = 3.0
      ring(ents, cx, cd, z, rad, rad - 16, 3.0, p[:basin], :z, 48)                       # lip on the worktop
      rb = rad - 14.0
      bowl = sink_bowl(ents, cx - rb, cd - rb, z, 2 * rb, 2 * rb, depth, t, rb - 0.2, p[:basin]) # round bowl (the proven rounded-outline builder at full radius)
      bowl.entities.grep(Sketchup::Edge).each { |ed| ed.soft = ed.smooth = true if ed.line[1].z.abs > 0.99 } # one smooth round wall, no facets
      ring(ents, cx, cd, z - depth + t, 30, 22, 2, p[:steel_dk], :z, 20)
      cyl(ents, cx, cd, z - depth + t, 22, 3, p[:chrome], :z, 20)
      6.times { |k| a = k * Math::PI / 3.0; cyl(ents, cx + 11 * Math.cos(a), cd + 11 * Math.sin(a), z - depth + t + 3, 2.4, 1, p[:black], :z, 8) }
      k = 0.80                                                                           # tap: on the worktop in the rear corner of the sink's square, spout towards the centre
      tx = cx + rad * k
      td = cd - rad * k
      swan_tap(ents, tx, td, z, [-0.7071, 0.7071], p[:tap], [rad * 1.0, 150.0].max)
    end

    def sink(ents, x, d, z, w, dep, _h, cfg = {})
      p = pal
      double = cfg.key?('sink_double') ? cfg['sink_double'] : w > 700
      rim_h = 3.0 # stainless lip lying on the worktop (about 3 mm proud)
      m = 15.0
      depth = 170.0
      t = 3.0
      r = 30.0
      model = (cfg['sink_model'] || (double ? 'double' : 'single')).to_s
      return sink_round(ents, x, d, z, w, dep, cfg, p) if model == 'round'
      m = cfg['sink_flange'].to_f if model.start_with?('smart') && cfg['sink_flange'].to_f.positive? # product sink: the bowl stays inside the opening of the unit
      y0 = d + m
      yd = dep - 2 * m
      split = model == 'one_half' ? 0.62 : 0.55
      bowls = case model
              when 'double', 'one_half' then [[m, w * split - m - 6], [w * split + 6, w * (1 - split) - m - 6]]
              when 'drainer' then [[m, w * 0.5 - m]]                       # one bowl, the other half is the ribbed drainer
              when 'round' then [[(w - yd) / 2.0, yd]]
              else [[m, w - 2 * m]]
              end
      double = %w[double one_half].include?(model)
      r = yd / 2.0 - 0.2 if model == 'round'
      smart = model.start_with?('smart') # 'smart' (SMG 800 x 490) and 'smart75' (the usual 750 x 450 of this kind of sink)
      deck = smart ? 78.0 : 50.0 # behind the bowl: the deck of the smart sink / the tap ledge of an ordinary sink (the tap stands ON the sink, not on its edge)
      by0 = y0 + deck
      byd = yd - deck
      depth = 200.0 if smart
      r = 12.0 if smart
      # one rim plate (flat steel lip) with a rounded opening per bowl
      g = ents.add_group
      e = g.entities
      face = e.add_face([[0, 0], [w, 0], [w, dep], [0, dep]].map { |px, pd| Geo.p3(x + px, d + pd, z) })
      bowls.each do |bx, bw|
        hole = e.add_face(rr_pts(x + bx + t, by0 + t, z, bw - 2 * t, byd - 2 * t, r - t))
        hole.erase! if hole&.valid?
      end
      face = e.grep(Sketchup::Face).find { |q| q.normal.z.abs > 0.9 && q.loops.size > 1 } || face
      face.pushpull(face.normal.z >= 0 ? Geo.mm(rim_h) : -Geo.mm(rim_h))
      skin = smart ? mat('Sink Nano', [50, 52, 56]) : p[:basin] # the smart sink is dark (nano coated)
      g.material = skin
      bowls.each_with_index do |(bx, bw), i|
        sink_bowl(ents, x + bx, by0, z, bw, byd, depth, t, r, skin)
        cx = x + bx + bw * (smart ? 0.84 : 0.5) # the product sink has a side drain (its exact position is not published)
        cd = by0 + byd * 0.5
        next if smart # its drain set is built below as separate accessories

        ring(ents, cx, cd, z - depth + t, 30, 22, 2, p[:steel_dk], :z, 20)       # strainer flange
        cyl(ents, cx, cd, z - depth + t, 22, 3, p[:chrome], :z, 20)               # strainer basket cover
        6.times { |k| a = k * Math::PI / 3.0; cyl(ents, cx + 11 * Math.cos(a), cd + 11 * Math.sin(a), z - depth + t + 3, 2.4, 1, p[:black], :z, 8) }
        box(ents, cx - 18, y0 + yd - t - 2, z - 55, 36, 2, 7, p[:steel_dk]) if i.zero? # overflow slot on the front wall
      end
      if smart
        # SMG 107501706 component list (supplier page). Each accessory is its own named group ('egc' / 'accessory') so it can be told
        # apart, hidden or counted. Sizes and positions of the accessories are NOT published: they are laid out so that nothing blocks
        # anything else (checked by the test), not copied from a drawing.
        bx, bw = bowls[0]
        acc = lambda do |name, &blk|
          ag = ents.add_group
          ag.name = "sink_acc_#{name}"
          ag.set_attribute('egc', 'accessory', name)
          blk.call(ag.entities)
          ag
        end
        ix = x + bx + t
        iw = bw - 2 * t
        iy = by0 + t
        idp = byd - 2 * t
        rail_z = z - 42.0
        [iy, iy + idp - 10].each { |ly| box(ents, ix, ly, rail_z, iw, 10, 4, skin) }                                     # the rail the board and the small bowl slide on
        [iy, iy + idp - 6].each { |ly| box(ents, ix, ly, rail_z - 46, iw, 6, 4, skin) }                                    # second (lower) step of the bowl
        # the deck is a black glass control panel: piano keys, temperature display and a soap pump stand on it (look of this kind of sink;
        # none of it is a published dimension)
        pd0 = y0 + deck / 2.0
        box(ents, x + m + 3, y0 + 7, z + rim_h, w - 2 * m - 6, deck - 16, 1.6, p[:black])
        4.times { |k| box(ents, x + w * 0.42 + k * 17.0, pd0 - 9, z + rim_h + 1.6, 14, 18, 3.5, p[:chrome]) }
        box(ents, x + w * 0.42 + 4 * 17.0 + 6, pd0 - 7, z + rim_h + 1.6, 30, 14, 0.5, p[:blue] || p[:steel_dk])
        spx = x + w * 0.25
        dark0 = mat('Tap Gunmetal', [70, 72, 76])
        cyl(ents, spx, pd0, z + rim_h + 1.6, 15, 6, dark0, :z, 16)
        cyl(ents, spx, pd0, z + rim_h + 7.6, 6, 38, dark0, :z, 12)
        box(ents, spx - 5, pd0 - 5, z + rim_h + 45.6, 10, 34, 7, dark0)
        acc.call('veg_bowl') do |e2|                                                                                      # vegetable-washing bowl with its own drain and plug
          vw = iw * 0.26
          sink_bowl(e2, ix + 12, iy + 12, rail_z + 4, vw, idp - 24, 105, 2, 8, p[:steel_dk])
          box(e2, ix + 8, iy + 2, rail_z + 4, vw + 8, 10, 3, p[:steel_dk])
          box(e2, ix + 8, iy + idp - 12, rail_z + 4, vw + 8, 10, 3, p[:steel_dk])
          cyl(e2, ix + 12 + vw / 2.0, iy + idp / 2.0, rail_z + 4 - 105 + 2, 14, 3, p[:chrome], :z, 16)
          5.times { |a| 8.times { |b| cyl(e2, ix + 12 + vw * (0.16 + 0.17 * a), iy + 12 + (idp - 24) * (0.11 + 0.111 * b), rail_z + 4 - 105 + 2, 3.2, 0.6, p[:black], :z, 8) } } # perforated bottom (colander)
        end
        acc.call('chopping_board') { |e2| box(e2, ix + iw * 0.36, iy + 2, rail_z + 4, iw * 0.22, idp - 4, 16, p[:wood]) }
        # (no drip basket: the owner took the triangular corner basket out - 1.28.55)
        dcx = x + bx + bw * 0.84
        dcd = by0 + byd * 0.5
        acc.call('drain_strainer') do |e2|
          ring(e2, dcx, dcd, z - depth + t, 45, 34, 2, p[:steel_dk], :z, 20)
          cyl(e2, dcx, dcd, z - depth + t, 34, 3, p[:chrome], :z, 20)
        end
        acc.call('drain_cover') { |e2| box(e2, dcx - 44, dcd - 44, z - depth + t + 4, 88, 88, 2, skin); cyl(e2, dcx, dcd, z - depth + t + 6, 12, 5, p[:chrome], :z, 16) } # square cover with its lift knob
        deck_y = y0 + deck / 2.0
        acc.call('drain_control') { |e2| cyl(e2, x + w * 0.88, deck_y, z + rim_h, 14, 22, p[:chrome], :z, 16) }           # drain regulator on the deck
        acc.call('glass_rinser') do |e2|
          rx = x + w * 0.11
          rw = 72.0
          rd = [deck - 22.0, 40.0].max
          box(e2, rx - rw / 2.0, deck_y - rd / 2.0, z + rim_h, rw, rd, 4, p[:steel_dk])                                  # rectangular ribbed tray at the end of the deck
          9.times { |k| box(e2, rx - rw / 2.0 + 4 + k * ((rw - 10) / 8.0), deck_y - rd / 2.0 + 3, z + rim_h + 4, 2, rd - 6, 2.5, p[:chrome]) }
          cyl(e2, rx, deck_y, z + rim_h + 4, 7, 8, p[:black], :z, 12)                                                    # spray nozzle
        end
        acc.call('waterfall') do |e2|                                                                                     # waterfall blade on the wall of the bowl under the deck
          box(e2, x + w * 0.28, by0 + t, z - 10, w * 0.36, 12, 11, p[:black])
          box(e2, x + w * 0.28, by0 + t + 12, z - 10, w * 0.36, 6, 3, p[:black])                                         # lip the water runs off
        end
        acc.call('tap') do |e2|                                                                                           # pull-out tap, standing on the deck
          tx0 = x + w * 0.72
          dark = mat('Tap Gunmetal', [70, 72, 76])
          swan_tap(e2, tx0, deck_y - 8, z + rim_h, [0.0, 1.0], dark, 190.0, 270.0)                                       # tall pull-out mixer
          tip = [tx0, deck_y - 8 + 190.0 * (0.5 + 0.5 * Math.cos(Math::PI * (1.0 - 1.12)))]
          cyl(e2, tip[0], tip[1], z + rim_h + 270 + 95 * Math.sin(Math::PI * (1.0 - 1.12)) - 58, 15, 44, dark, :z, 16)   # pull-out spray head
        end
      end
      box(ents, x + w * split - 6, y0, z - depth, 12, yd, depth, p[:basin]) if double
      if model == 'drainer'
        n = ((w * 0.5 - m - 30) / 24.0).floor
        n.times { |k| box(ents, x + w * 0.5 + 18 + k * 24.0, y0 + 20, z + rim_h, 8, yd - 40, 3, p[:basin]) } # drainer ribs
      end
      unless smart # the product sink carries its own tap as an accessory
        tapx = x + w * 0.5
        td = d + (m + deck) / 2.0                                                        # centre of the ledge behind the bowl
        swan_tap(ents, tapx, td, z + rim_h, [0.0, 1.0], p[:tap])
        if w > 420
          cyl(ents, tapx + 92, td, z + rim_h, 13, 8, p[:steel_dk], :z, 12)               # soap dispenser on the same ledge
          cyl(ents, tapx + 92, td, z + rim_h + 8, 4, 62, p[:tap], :z, 8)
          cyl(ents, tapx + 92, td + 14, z + rim_h + 62, 2.6, 14, p[:tap], :y, 8)
        end
      end
      box(ents, x + w * 0.5 - 40, d + dep - 40, z + rim_h, 80, 30, 3, p[:wood]) if cfg['sink_board']
    end

    def hood_chimney(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      body_h = 260.0
      cw = 200.0
      cd = 160.0
      cx = x + w * 0.5 - cw / 2.0
      cdp = d + dep * 0.5 - cd / 2.0
      upper_h = [h - body_h, 100].max
      lower_h = upper_h * 0.55
      box(ents, cx, cdp, z + body_h, cw, cd, lower_h, p[:body])                                       # inner (lower) chimney section
      box(ents, cx - 3, cdp - 3, z + body_h + lower_h * 0.45, cw + 6, cd + 6, upper_h - lower_h * 0.45, p[:body]) # outer telescopic section (overlaps -> visible seam)
      box(ents, cx - 5, cdp - 5, z + body_h + lower_h * 0.45 - 2, cw + 10, cd + 10, 3, p[:steel_dk])  # seam trim
      box(ents, x, d, z, w, dep, 70, p[:body])
      box(ents, x - 2, d - 2, z + 70, w + 4, dep + 4, 4, p[:steel_dk])                                 # canopy edge lip
      frustum(ents, x, d, z + 74, w, dep, cw, cd, body_h - 74, p[:body])
      box(ents, cx - 4, cdp - 4, z + body_h - 4, cw + 8, cd + 8, 8, p[:steel_dk])                       # chimney collar
      slab(ents, x + w * 0.06, z + 14, w * 0.88, 60, d + dep, 4, p[:black], -1)                         # front glass / filter fascia
      3.times { |i| slab(ents, x + w * 0.5 - 24 + i * 24, z + 6, 10, 6, d + dep, 3, p[:led], -1) }
      4.times { |i| slab(ents, x + w * 0.5 - 30 + i * 20, z + 82, 10, 5, d + dep - 4, 3, p[:grey_dk], -1) } # control keys on the canopy face
      box(ents, x + 20, d + 20, z - 2, w - 40, dep - 40, 2, p[:steel_dk])
      grille(ents, x + 30, d + 30, z - 4, w - 60, dep - 60, p[:steel_dk], 9)                           # filter grille under the canopy
      [x + 60, x + w - 60].each { |lx| cyl(ents, lx, d + dep * 0.5, z - 5, 9, 3, p[:led], :z, 12) }   # downlights
    end
  end
end
