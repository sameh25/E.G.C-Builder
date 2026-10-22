# frozen_string_literal: true

module EGC
  # A mechanism that cannot be built safely for the requested size. Raised BEFORE the unit is committed (callers abort their operation).
  class MechanismError < StandardError
    attr_reader :code, :why

    def initialize(code, msg, why: nil)
      super(msg)
      @code = code
      @why = why
    end
  end

  # Compound-motion families: carousel / turning baskets, blind (magic) corner, lift-up and fold-lift.
  # Generic E.G.C mechanisms: the motion is correct and readable for the type, not a replica of any brand's linkage.
  module FamilyBuilders
    # ------------------------------------------------------------------------------------------------ ROTATING_CAROUSEL
    def fam_carousel(o)
      b = bnd
      zf, hf = full_front
      cw = b[:x1] - b[:x0]
      cd = b[:d1] - b[:d0]
      h = b[:z1] - b[:z0]
      full = (o[:shape] || :full) == :full
      r = [cw, cd].min / 2.0 - 26
      r = [r, 260.0].min if full
      cx = (b[:x0] + b[:x1]) / 2.0
      cdp = (b[:d0] + b[:d1]) / 2.0
      # fixed pole with floor / top bearing plates
      h_slab('pole_plate', cx - 45, cdp - 45, b[:z0], 90, 90, 4, :zinc)
      h_slab('pole_plate', cx - 45, cdp - 45, b[:z1] - 4, 90, 90, 4, :zinc)
      h_rod('pole', cx - 20, cdp - 20, b[:z0] + 4, :z, h - 8, 40, :chrome, 16)
      h_rod('pole_bearing', cx - 34, cdp - 34, b[:z0] + 4, :z, 14, 68, :steel, 20)
      h_rod('pole_bearing', cx - 34, cdp - 34, b[:z1] - 18, :z, 14, 68, :steel, 20)
      lv = [[o[:levels] || 2, (h / 200).floor].min, 1].max
      sweep = full ? 360 : 270
      a = asm('carousel', MotionProfiles.rotate([cx, cdp, 0], full ? 220 : 100, [0.2, 1.0]))
      in_asm(a) do
        lv.times do |i|
          z = b[:z0] + 30 + i * ((h - 120) / [lv - 1, 1].max.to_f) * (lv > 1 ? 1 : 0)
          h_disc('carousel_shelf', cx, cdp, z, r, sweep, 0, 4.0, finish_key, 46)
          h_rod('carousel_hub', cx - 32, cdp - 32, z, :z, 24, 64, :steel, 14)
          if full # a wire divider across the shelf so the rotation is readable
            # two wires: the fixed pole stands in the middle, so the divider is broken around it
            h_between('shelf_divider', [cx - r + 8, cdp, z + 92], [cx - 40, cdp, z + 92], 5, finish_key)
            h_between('shelf_divider', [cx + 40, cdp, z + 92], [cx + r - 8, cdp, z + 92], 5, finish_key)
            [-0.75, -0.4, 0.4, 0.75].each { |k| h_rod('shelf_divider_post', cx + k * r - 2, cdp - 2, z + 2, :z, 92, 5, finish_key, 6) }
          end
          3.times { |k| a = (k * 90 + 20).degrees; h_between('shelf_support', [cx + 36 * Math.cos(a), cdp + 36 * Math.sin(a), z + 2], [cx + (r - 6) * Math.cos(a), cdp + (r - 6) * Math.sin(a), z + 2], 7, :steel) }
        end
        h_rod('carousel_sleeve', cx - 28, cdp - 28, b[:z0] + 6, :z, h - 12, 56, :steel, 16)
        @hw['basket'] += lv
      end
      da = asm('door', MotionProfiles.hinge_rotate([@gap / 2.0, @cd + @ft, 0], -90, [0.0, 0.3]).merge(door_slide ? { 'slide' => door_slide } : {}))
      in_asm(da) do
        front('door', @gap / 2.0, @w - @gap, zf, hf, :top, grain: :z)
        with_hand('L') { door_hinges(0, 1, @gap / 2.0, @w - @gap, zf, hf) } # hinge cups turn with the door
      end
      with_hand('L') { door_plates(0, 1, @gap / 2.0, @w - @gap, zf, hf) }
      @hw['hinge'] += hinge_count(hf)
    end

    def with_hand(h)
      old = @s[:hand]
      @s[:hand] = h
      yield
    ensure
      @s[:hand] = old
    end

    # ------------------------------------------------------------------------------------------------ BLIND_CORNER
    # Compound sequence (collision-safe by construction):
    #   0.00-0.34  door swings open on its hinge (opening side)
    #   0.10-0.85  FRONT set swings out on a real pivoting arm hinged at the front (door-side) corner - a wide,
    #              visible arc through the open door, matching a real blind-corner swing-arm unit
    #   0.30-0.80  REAR set (blind lane) slides forward
    #   0.55-1.00  REAR set shifts across into the opening lane, right behind the front set -> the blind storage is revealed
    def fam_magic(o)
      right = (o[:blind] || 'right').to_s == 'right' # blind lane on the right, opening + hinge on the left
      sg = right ? 1.0 : -1.0
      b = bnd
      zf, hf = full_front
      cw = b[:x1] - b[:x0]
      cd = b[:d1] - b[:d0]
      h = b[:z1] - b[:z0]
      blind = (cw * 0.36).round
      wa = cw - blind                       # opening lane
      mxr = ->(x, w) { right ? x : @w - x - w } # mirror a box [x, x+w] for the left-hand variant
      fdep = (cd * 0.48).round
      rdep = (cd - fdep - 46).round
      sz = b[:z0] + 6
      fw = wa - 30
      # fixed floor rails: one pair under each lane
      lane_a = [b[:x0] + 10, b[:x0] + wa - 22].map { |x| mxr.call(x, 12) }
      lane_b = [b[:x0] + wa + 12, b[:x1] - 24].map { |x| mxr.call(x, 12) }
      (lane_a + lane_b).each { |x| h_chan('floor_rail', x, b[:d0] + 4, sz, cd - 20, 12, 12, 1.5, 1, :zinc) }
      levels = [(h / 230).floor, 2].min
      levels = [levels, 1].max
      pitch = (h - 150) / [levels, 1].max.to_f
      bh = 70.0
      tf = (cd * 1.05).round.to_f
      tr = (cd * 0.78).round.to_f
      sx = (wa * 0.55).round.to_f * -sg
      d_front = b[:d1] - fdep - 6
      # --- front set: a REAL parallelogram-style linkage, hinged at a FIXED bracket at the front (door-side)
      # corner of the opening lane. Two separate transforms:
      #   'swing_arm_link' (fixed pivot, real rotation)  - the visible arm bar, so the motion reads as a linked
      #      mechanism (matches the Hettich/Kesseböhmer reference), not a floating basket.
      #   'basket_front'   (orientation-compensated)      - the basket + carriage TRANSLATE along the exact same
      #      arc the arm's far end sweeps, but never rotate: like a Ferris-wheel gondola on a second, parallel
      #      link, the tray/basket stays visually straight and aligned throughout the travel (no diagonal yaw).
      car_x = mxr.call(b[:x0] + 10, 4) # same outer (hinge-side) corner as pivot_f, mirrored the same way
      car_d = d_front + 14
      pivot_f = [mxr.call(b[:x0] + 6, 4), b[:d0] + 16, 0] # pivot bracket at the BACK: swinging pulls the tray toward the hinge side AND toward the wall (away from the open door) at the same time
      swing_deg = -62.0 * sg
      swing_phase = [0.22, 0.85]
      n_key = 25
      samples = (0...n_key).map { |i| i / (n_key - 1.0) }
      r0x = car_x - pivot_f[0]
      r0d = car_d - pivot_f[1]
      keys_pos = samples.each_index.map do |i|
        tt = Mechanisms.phase({ 'phase' => swing_phase }, samples[i])
        th = (swing_deg * tt) * Math::PI / 180.0
        # builder (x,d) is a MIRRORED plane of world (x,y=-d): a SketchUp 'rot' about +z by `deg` moves a point
        # this way in (x,d) - matches rot_tr exactly, so the arm (real rotation) and the basket (translate-only,
        # same path) stay glued together at every t.
        rx = r0x * Math.cos(th) + r0d * Math.sin(th)
        rd = -r0x * Math.sin(th) + r0d * Math.cos(th)
        [samples[i], rx - r0x, rd - r0d, 0]
      end
      arm_top = sz + (levels - 1) * pitch + bh - 6
      arm_bot = sz + 20
      link = asm('swing_arm_link', MotionProfiles.rotate(pivot_f, swing_deg, swing_phase))
      in_asm(link) do
        [arm_bot, arm_top].each { |za| h_between('swing_arm', [pivot_f[0], pivot_f[1], za], [car_x, car_d, za], 11, :steel) }
        h_rod('swing_hinge', pivot_f[0] - 7, pivot_f[1] - 7, sz + 10, :z, arm_top - arm_bot + 20, 14, :chrome, 12)
      end
      fa = asm('basket_front', MotionProfiles.pose_xd(pivot_f, keys_pos))
      in_asm(fa) do
        set_baskets(mxr.call(b[:x0] + 14, fw), d_front, sz + 60, fw, fdep, levels, pitch, bh)
        carriage_frame(mxr.call(b[:x0] + 10, wa - 20), d_front + 14, sz + 13.5, wa - 20, fdep - 28)
      end
      # --- rear set
      rw = blind + 50
      d_rear = b[:d0] + 10
      ra = asm('basket_rear', MotionProfiles.compound(
        { 'type' => 'lin', 'v' => [0, tr, 0], 'phase' => [0.52, 0.94] },
        { 'type' => 'lin', 'v' => [sx, 0, 0], 'phase' => [0.6, 0.88] }
      ))
      in_asm(ra) do
        set_baskets(mxr.call(b[:x1] - rw - 6, rw), d_rear, sz + 60, rw, rdep, levels, pitch, bh)
        carriage_frame(mxr.call(b[:x1] - rw - 6, rw), d_rear + 14, sz + 13.5, rw, rdep - 28)
      end
      # --- door over the opening lane, fixed filler over the blind lane
      dw = @w - @gap - blind
      dx = right ? @gap / 2.0 : blind + @gap / 2.0
      hx = right ? @gap / 2.0 : @w - @gap / 2.0
      da = asm('door', MotionProfiles.hinge_rotate([hx, @cd + @ft, 0], right ? -90 : 90, [0.0, 0.34]).merge(door_slide ? { 'slide' => door_slide } : {}))
      in_asm(da) do
        front('door', dx, dw, zf, hf, :top, grain: :z)
        with_hand(right ? 'L' : 'R') { door_hinges(0, 1, dx, dw, zf, hf) } # hinge cups turn with the door
      end
      fx = right ? @w - blind - @gap / 2.0 : @gap / 2.0 - 0
      pn('filler', fx, @cd, zf, blind, @ft, hf, 'front', grain: :z, eb: [2, 2], eb_t: 2.0)
      with_hand(right ? 'L' : 'R') { door_plates(0, 1, dx, dw, zf, hf) }
      @hw['hinge'] += hinge_count(hf)
      @hw['basket'] += 2 * levels
      @hw['slide_pair'] += 2
    end

    # base carriage of a basket set: two runner bars + cross tubes + four riser blocks (reads as a frame on slides)
    def carriage_frame(x, d, z, w, dep)
      h_slab('carriage_bar', x, d, z, 14, dep, 12, :steel)
      h_slab('carriage_bar', x + w - 14, d, z, 14, dep, 12, :steel)
      [d, d + dep - 12].each { |pd| h_slab('carriage_cross', x, pd, z + 2, w, 12, 10, :steel) }
      [d + dep / 2.0 - 6].each { |pd| h_slab('carriage_cross', x, pd, z + 2, w, 12, 10, :steel) }
      [[x + 2, d + 6], [x + w - 12, d + 6], [x + 2, d + dep - 16], [x + w - 12, d + dep - 16]].each { |px, pd| h_slab('carriage_riser', px, pd, z + 12, 10, 10, 40, :zinc) }
    end

    def set_baskets(x, d, z0, w, dep, levels, pitch, bh)
      levels.times { |i| h_basket('basket', x, d, z0 + i * pitch, w, dep, bh, finish_key) }
      [[x + 3, d + 4], [x + w - 11, d + 4], [x + 3, d + dep - 12], [x + w - 11, d + dep - 12]].each do |px, pd|
        h_rod('post', px, pd, z0, :z, (levels - 1) * pitch + bh, 8)
      end
    end

    # ------------------------------------------------------------------------------------------------ LIFT / FOLD_LIFT
    # single flap: swings up and FORWARD (awning) so it never enters the carcass
    FLAP_DEG = -90.0 # single flap: swings up and FORWARD (awning) and stops HORIZONTAL (never beyond 90 deg) so it can never rise into a unit above
    FLAP_FWD = 16.0  # the hinge line of the front travels this far toward the room while it rotates (clears the carcass top-front edge and reveals)

    def seg_cross?(p, q, r, s)
      o = lambda { |a, b, c| (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) }
      d1 = o.call(p, q, r)
      d2 = o.call(p, q, s)
      d3 = o.call(r, s, p)
      d4 = o.call(r, s, q)
      d1 * d2 < 0 && d3 * d4 < 0
    end

    def seg_dist(p, q, r, s)
      return 0.0 if seg_cross?(p, q, r, s)

      pt = lambda do |a, b, c|
        dx = c[0] - b[0]
        dz = c[1] - b[1]
        l2 = dx * dx + dz * dz
        u = l2.zero? ? 0.0 : [[((a[0] - b[0]) * dx + (a[1] - b[1]) * dz) / l2, 0.0].max, 1.0].min
        Math.hypot(a[0] - (b[0] + u * dx), a[1] - (b[1] + u * dz))
      end
      [pt.call(p, r, s), pt.call(q, r, s), pt.call(r, p, q), pt.call(s, p, q)].min
    end

    # Lift-up path of the front (builder d,z plane): TRANSLATION of the hinge line + ROTATION about it, sampled together.
    # keys: [u, dd, dz, deg] (pose convention: translate THEN rotate about the pivot). The hinge line first moves toward the
    # room (a stay-lift front leaves the carcass edge before it turns), then the front rotates to the horizontal stop.
    # Returns [samples, thetas, dds, dzs]; dd/dz are the translation of the pivot at each sample.
    def flap_path(phase = nil, n = 41)
      sm = ->(x) { x = [[x, 0.0].max, 1.0].min; x * x * (3 - 2 * x) }
      samples = (0...n).map { |i| i / (n - 1.0) }
      e = samples.map { |u| phase ? Mechanisms.phase({ 'phase' => phase }, u) : u }
      thetas = e.map { |v| FLAP_DEG * sm.call(v) }
      dds = e.map { |v| FLAP_FWD * sm.call([v * 1.8, 1.0].min) }
      dzs = e.map { 0.0 }
      [samples, thetas, dds, dzs]
    end

    def flap_keys(samples, thetas, dds, dzs)
      samples.each_index.map { |i| [samples[i], dds[i], dzs[i], thetas[i]] }
    end

    # arms for a single top-hinged flap: the hinge line translates and rotates (see flap_path); the telescopic stay follows the front bracket
    def flap_arms(zf, hf, single: true, phase: nil)
      _ = single
      ztopl = zf + hf
      p0 = [@cd + @ft, ztopl]
      b = [hf * 0.5 + 45.0, hf - 60.0].min
      a0 = [@cd - 12.0, ztopl - b]
      samples, thetas, dds, dzs = flap_path(phase)
      mv = ->(pt, i) { [pt[0] + dds[i], pt[1] + dzs[i]] }
      apts = thetas.each_index.map { |i| mv.call(MotionProfiles.rot2(a0, p0, thetas[i]), i) }
      planes = thetas.each_index.map { |i| [[mv.call(MotionProfiles.rot2([@cd + @ft / 2.0, ztopl], p0, thetas[i]), i), mv.call(MotionProfiles.rot2([@cd + @ft / 2.0, zf], p0, thetas[i]), i)]] }
      sol = tele_solve!(samples, apts, planes)
      br = asm('flap_bracket', MotionProfiles.pose([@w / 2.0, p0[0], p0[1]], flap_keys(samples, thetas, dds, dzs)))
      in_asm(br) { [ix0 + 11, ix1 - 25].each { |bx| h_slab('leaf_arm_bracket', bx, @cd - 24, a0[1] - 22, 14, 24, 44, :zinc) } }
      tele_build(sol, samples, apts)
    end

    def flap_stays(zf, hf)
      flap_arms(zf, hf, single: true)
    end

    def fam_lift(_o)
      zf, hf = full_front
      shelves({ t: :flap, shelves: 1, z0: @z0 + @t, h: @hc - 2 * @t })
      a = asm('flap', MotionProfiles.pose([@w / 2.0, @cd + @ft, zf + hf], flap_keys(*flap_path)))
      in_asm(a) { front('flap', @gap / 2.0, @w - @gap, zf, hf, :bottom, grain: :z) }
      flap_arms(zf, hf, single: true)
      @hw['lift_up'] += 1
    end


    # E.G.C Bi-Fold Lift (GENERIC / reference-based, not a Blum model): full overlay, one continuous linkage. Only the arm-bracket rule below follows Blum HF planning info (arm mounting
    # position = 0.5 x top-front height + 45); the 104 / 83 deg stops are E.G.C settings. room_above = CONFIGURED ceiling clearance only (cfg ceiling), it does not detect geometry above the unit.
    #  - upper front: turns forward-up about its top outer edge (awning) and is carried by the telescopic lever arm, whose bracket
    #    sits on the upper front's inner face 0.5*h_upper + 45 below its top edge;
    #  - lower front: hangs from the centre hinge and folds onto the upper front's outer face WHILE the upper front rises
    #    (the schedule keeps it from ever dipping below its closed position);
    #  - the lever arm (outer tube fixed on the lift body, inner tube sliding) changes length and angle every frame; its pivot is
    #    solved so it never touches the carcass panels or either front. Nothing of the carcass is modified.
    HF_ANGLES = [160.0, 104.0, 83.0].freeze # end stop of the upper front: the first one whose folded pack fits under the ceiling
    HF_SLIDE = 30.0 # degrees of the upper front up to which the lower front still rides on the carcass front (the opening V)
    HF_HANG = 12.0  # tilt of the hanging lower front in mid travel
    HF_FINAL_V = 14.0 # angle left between the two fronts at the end stop: the arm reaches the lower front through this gap

    # height of the folded pack above the fronts' top edge (both fronts, thickness ft each)
    def hf_pack_above(th_deg, h1, ft)
      th = (th_deg - 90.0) * Math::PI / 180.0
      [h1 * Math.sin(th), 0.0].max + 2 * ft * Math.cos(th) - ft
    end

    # Telescopic lever arm pair (one per side): solves the lift-body pivot S against the panels and the given leaf planes, then builds
    # outer tube (fixed on the body) + inner tube (sliding) with pose keys so length AND angle change every frame.
    # Pure solver (no geometry): the best lift-body pivot, with the violations it still has. ok == no violation at all.
    def tele_solve(samples, apts, planes)
      ft = @ft
      top = @z0 + @hc
      z_lo = @z0 + @t + 40.0
      z_hi = top - @t - 30.0
      best = nil
      if z_hi < z_lo + 20.0 || (@cd - @bk) < 150.0
        return { ok: false, viol: 999, why: { unit_too_small: 1 }, s: nil, lens: [] }
      end
      # the lift body reaches 60 mm behind its pivot: the grid starts there so the body stays in front of the back board
      # the lift body sits HIGH on the side panel, lying back from its pivot (reference lift blocks): the upper zone is searched first, the whole
      # side only when no collision-free pivot exists up there
      [true, false].each do |high|
      break if best && best[:viol].zero?

      zl = high ? z_hi - (z_hi - z_lo) * 0.40 : z_lo
      dl = [@bk + (high ? 165.0 : 60.0), @cd - 60.0].min
      (0..16).each do |gi|
        (0..16).each do |gj|
          s = [dl + gi * ((@cd - 40.0 - dl) / 16.0), zl + gj * ((z_hi - zl) / 16.0)]
          lens = apts.map { |a| Math.hypot(a[0] - s[0], a[1] - s[1]) }
          viol = 0
          why = Hash.new(0)
          (viol += 30; why[:arm_stroke] += 1) if lens.max > 1.85 * lens.min - 20 || 2.0 * (lens.min - 28.0) < lens.max + 10.0
          (viol += 30; why[:arm_too_short] += 1) if lens.min < 120
          samples.each_index do |i|
            a = apts[i]
            l = lens[i]
            (0..12).each do |k|
              f = k / 12.0
              px = s[0] + (a[0] - s[0]) * f
              pz = s[1] + (a[1] - s[1]) * f
              (viol += 2; why[:top_panel] += 1) if px < @cd && pz > top - @t - 2.0
              (viol += 2; why[:bottom_panel] += 1) if pz < @z0 + @t + 4.0
            end
            k = 28.0 / [l, 60.0].max
            e = [a[0] + (s[0] - a[0]) * k, a[1] + (s[1] - a[1]) * k]
            planes[i].each { |p, q| (viol += 3; why[:front_leaf] += 1) if seg_dist(s, e, p, q) < ft / 2.0 + 4.0 }
          end
          score = viol * 1000 + (lens.max - lens.min) + lens.min * 0.05
          best = { s: s, lens: lens, viol: viol, score: score, why: why.dup, high: high } if best.nil? || score < best[:score]
        end
      end
      end
      best[:ok] = best[:viol].zero?
      best
    end

    def tele_build(best, samples, apts)
      s = best[:s]
      lens = best[:lens]
      l0 = lens.first
      lmin = lens.min
      lmax = lens.max
      dir0 = [apts[0][0] - s[0], apts[0][1] - s[1]]
      alpha0 = MotionProfiles.angle_deg(dir0)
      keys_out = []
      keys_in = []
      samples.each_index do |i|
        v = [apts[i][0] - s[0], apts[i][1] - s[1]]
        u = [v[0] / lens[i], v[1] / lens[i]]
        rot = alpha0 - MotionProfiles.angle_deg(v)
        keys_out << [samples[i], 0, 0, rot]
        keys_in << [samples[i], u[0] * (lens[i] - l0), u[1] * (lens[i] - l0), rot]
      end
      seg = [(lmax + 16.0) / 2.0, lmin - 28.0].min # outer tube stops 28 mm short of the front bracket at its shortest
      dirn = [dir0[0] / l0, dir0[1] / l0]
      outer_end = [s[0] + dirn[0] * seg, s[1] + dirn[1] * seg]
      inner_start = [s[0] + dirn[0] * (l0 - seg), s[1] + dirn[1] * (l0 - seg)]
      tip = [s[0] + dirn[0] * l0, s[1] + dirn[1] * l0]
      [[ix0, 1], [ix1, -1]].each do |edge, sgn|
        xa = sgn == 1 ? edge + 13 : edge - 13 - 7 # arms run on the INNER face of the lift body (never through it)
        xb = sgn == 1 ? edge + 11 : edge - 25 # bracket + tip pin share this 14 mm lane
        # lift body: a long low housing lying back from the pivot hub along the side panel (as the lift bodies of the reference blocks)
        back = [[s[0] - @bk - 8.0, 150.0].min, 54.0].max
        h_slab('lift_base', sgn == 1 ? edge : edge - 3, s[0] - back, s[1] - 22, 3, back + 24, 44, :zinc)
        h_slab('lift_body', sgn == 1 ? edge + 3 : edge - 3 - 7, s[0] - back + 4, s[1] - 17, 7, back + 2, 34, :steel)
        h_slab('lift_body_cap', sgn == 1 ? edge + 10 : edge - 10 - 2, s[0] - back + 10, s[1] - 13, 2, [back - 14, 20].max, 26, :dark)
        h_rod('lift_hub', sgn == 1 ? edge + 3 : edge - 3 - 9, s[0] - 17, s[1] - 17, :x, 9, 34, :dark, 20)
        h_pin('lift_pin', sgn == 1 ? edge + 3 : edge - 3 - 24, s[0] - 6, s[1] - 6, 6, 18)
        ao = asm('arm_outer', MotionProfiles.pose([edge, s[0], s[1]], keys_out))
        xt = sgn == 1 ? xa + 7 : xa # the telescopic arm is ONE round tube pair on a common axis (outer tube + sliding inner rod)
        in_asm(ao) do
          h_tube('lift_arm_outer', xt, s, outer_end, 14, :zinc)
          h_tube('lift_arm_guide', xt, [outer_end[0] - dirn[0] * 12, outer_end[1] - dirn[1] * 12], outer_end, 18, :chrome) # end guide ring of the outer tube
          # Twin pressed side webs and a cross-pin make the telescopic stay read as a load-bearing linkage;
          # they share the solver's pose, so they stay attached throughout flap travel.
          h_bar('lift_outer_web', xt - 5, s, outer_end, 13, 2.0, :zinc)
          h_bar('lift_outer_web', xt + 5, s, outer_end, 13, 2.0, :zinc)
          h_pin('lift_outer_joint', xt - 7, outer_end[0] - 6, outer_end[1] - 6, 6, 14)
        end
        ai = asm('arm_inner', MotionProfiles.pose([edge, s[0], s[1]], keys_in))
        in_asm(ai) do
          h_tube('lift_arm_inner', xt, inner_start, tip, 9, :chrome)
          h_bar('lift_inner_web', xt - 4, inner_start, tip, 8, 1.8, :chrome)
          h_bar('lift_inner_web', xt + 4, inner_start, tip, 8, 1.8, :chrome)
          h_slab('lift_front_clevis', xb - 4, tip[0] - 10, tip[1] - 8, 8, 20, 16, :zinc)
          h_pin('lift_tip', xb, tip[0] - 5, tip[1] - 5, 5, 14)
        end
      end
      { s: s, viol: best[:viol], lens: lens }
    end

    # solve, refuse (raise) when no valid solution exists, otherwise build
    def tele_arms(samples, apts, planes)
      sol = tele_solve!(samples, apts, planes)
      tele_build(sol, samples, apts)
    end

    def tele_solve!(samples, apts, planes)
      sol = tele_solve(samples, apts, planes)
      return sol if sol[:ok]

      raise MechanismError.new(:no_valid_linkage, "lever-arm linkage has no collision-free solution for this size (#{@w.round} x #{@hc.round} x #{@cd.round} mm); blocked by: #{sol[:why].keys.join(", ")}", why: sol[:why])
    end

    def fam_foldlift(_o)
      zf, hf = full_front
      ft = @ft
      w = @w - @gap
      h1 = hf * 0.5
      h2 = hf - h1
      zbot = zf
      ztopl = zf + hf
      fold_z = zbot + h2
      p0 = [@cd + ft, ztopl]
      # MOTION AS ON THE REFERENCE VIDEO (Blum SERVO-DRIVE for AVENTOS, a real HF cabinet):
      #  1. the two fronts break into a V, fold line out toward the room, lower front's bottom edge still near the carcass;
      #  2. the upper front (hinged on the carcass top edge) keeps turning up, the lower front HANGS from the fold, almost vertical;
      #  3. the upper front ends pointing up (HF end stop), the lower front folded in FRONT of it, inner faces together - one pack standing above the
      #     front of the cabinet, its bottom edge at the cabinet top.
      # The centre hinge is on the INNER faces. The telescopic arm goes from the lift body (high on the side panel) to a bracket on the LOWER front's
      # inner face - the only face the arm can reach in every pose (video: the arm meets the pack from behind).
      f0 = [@cd, fold_z]
      room = @s[:room_above]
      th_end = @c['hf_angle'] ? @c['hf_angle'].to_f : (HF_ANGLES.find { |a| room.nil? || hf_pack_above(a, h1, ft) <= room } || HF_ANGLES.last)
      n = 41
      samples = (0...n).map { |i| i / (n - 1.0) }
      sm = ->(x) { x = [[x, 0.0].max, 1.0].min; x * x * (3 - 2 * x) }
      thetas = samples.map { |u| -th_end * sm.call(u) }
      place = lambda do |q, phi, th|
        MotionProfiles.rot2(MotionProfiles.rot2(q, f0, phi), p0, th)
      end
      # absolute tilt of the lower front off the vertical (its bottom edge toward the carcass), by the upper front's angle a (degrees):
      #   riding the carcass front while a <= HF_SLIDE (the V), then easing to an almost vertical hang (HF_HANG) at 100 degrees, then closing onto
      #   the upper front at the end stop. Never more than the tilt that would put the bottom edge inside the carcass front.
      rad = Math::PI / 180.0
      ride = ->(a) { Math.asin([[h1 * Math.sin(a * rad) / h2, 1.0].min, 0.0].max) / rad }
      limit = ->(a) { a <= 90.0 ? ride.call(a) : [180.0 - a - HF_FINAL_V, 0.0].max }
      psi_end = [180.0 - th_end - HF_FINAL_V, 0.0].max
      tilt = lambda do |a|
        v = if a <= HF_SLIDE then ride.call(a)
            elsif a <= 100.0 then ride.call(HF_SLIDE) + (HF_HANG - ride.call(HF_SLIDE)) * sm.call((a - HF_SLIDE) / (100.0 - HF_SLIDE))
            else HF_HANG + (psi_end - HF_HANG) * sm.call((a - 100.0) / [th_end - 100.0, 1.0].max)
            end
        [v, limit.call(a)].min
      end
      q0 = [@cd, zbot]
      # the relative turn of the lower front is SEARCHED for the pose that puts its bottom edge where the tilt asks (no sign convention assumed),
      # so the two fronts stay hinged in every frame
      phis = samples.each_index.map do |i|
        a = thetas[i].abs
        c = MotionProfiles.rot2(f0, p0, thetas[i])
        t = tilt.call(a) * rad
        tgt = [c[0] - h2 * Math.sin(t), c[1] - h2 * Math.cos(t)]
        (-1800..1800).map { |k| k / 10.0 }.min_by { |p| pt = place.call(q0, p, thetas[i]); Math.hypot(pt[0] - tgt[0], pt[1] - tgt[1]) }
      end
      phis[0] = 0.0
      keys_u = samples.each_index.map { |i| [samples[i], 0, 0, thetas[i]] }
      keys_l = samples.each_index.map { |i| [samples[i], 0, 0, phis[i]] }
      pivot_x = @w / 2.0
      planes = samples.each_index.map do |i|
        up = [MotionProfiles.rot2([@cd + ft / 2.0, ztopl], p0, thetas[i]), MotionProfiles.rot2([@cd + ft / 2.0, fold_z], p0, thetas[i])]
        lo = [place.call([@cd + ft / 2.0, fold_z], phis[i], thetas[i]), place.call([@cd + ft / 2.0, zbot], phis[i], thetas[i])]
        [up, lo]
      end
      # ---- telescopic lever arms: solved FIRST; no valid linkage = the mechanism is refused before any part is built ------
      # bracket on the lower front's inner face, a fraction of its height below the fold (toward its bottom edge, where the two fronts stand apart at the end); the first position with a collision-free HIGH lift body
      # wins, then any collision-free one
      tries = [0.85, 0.75, 0.65, 0.5, 0.35].map { |k| [[h2 * k, h2 - 40.0].min, 40.0].max }.uniq.map do |bb|
        aa = [@cd - 12.0, fold_z - bb]
        ap = samples.each_index.map { |i| place.call(aa, phis[i], thetas[i]) }
        [aa, ap, tele_solve(samples, ap, planes)]
      end
      pick = tries.find { |_, _, sl| sl[:ok] && sl[:high] } || tries.find { |_, _, sl| sl[:ok] }
      unless pick
        why = tries.last[2][:why]
        raise MechanismError.new(:no_valid_linkage, "lever-arm linkage has no collision-free solution for this size (#{@w.round} x #{@hc.round} x #{@cd.round} mm); blocked by: #{why.keys.join(", ")}", why: why)
      end
      a0, apts, sol = pick
      a1 = asm('leaf_upper', MotionProfiles.pose([pivot_x, p0[0], p0[1]], keys_u))
      in_asm(a1) do
        front('flap_upper', @gap / 2.0, w, fold_z, h1, :none, grain: :z)
        [@w * 0.16, @w * 0.84 - 44].each { |hx| h_rod('fold_hinge', hx, f0[0] - 8, fold_z - 4, :x, 44, 8, :steel, 12) } # barrel on the centre-hinge axis, behind the inner faces
        a2 = asm('leaf_lower', MotionProfiles.pose([pivot_x, f0[0], f0[1]], keys_l))
        in_asm(a2) do
          front('flap_lower', @gap / 2.0, w, zbot, h2, :bottom, grain: :z)
          [ix0 + 11, ix1 - 25].each { |bx| h_slab('leaf_arm_bracket', bx, @cd - 24, a0[1] - 22, 14, 24, 44, :zinc) }
        end
      end
      arm = tele_build(sol, samples, apts)
      @fold_dbg = { s: arm[:s], viol: arm[:viol], lens: arm[:lens].map(&:round), phis: phis.map(&:round), th_end: th_end, above: hf_pack_above(th_end, h1, ft).round(1) }
      @hw['bifold_lift'] += 1
    end
  end
end

module EGC
  class Cabinet
    include FamilyBuilders
  end
end
