# frozen_string_literal: true

module EGC
  module Proto121
    # PROTOTYPE B - EGC_REAL_BIFOLD_REFERENCE  (Blum AVENTOS HF style bi-fold lift) - R3: fronts follow the REFERENCE motion
    # Plane frame (d, z): d toward the room (model y = -d), z up.  Back of the carcass at d = 0, front plane at d = D.
    # FRONT MOTION (reference-controlled): hinge-axis path C(u), upper-front angle THETA(u) and lower-front tilt BETA(u) are laws measured from the
    #   Blum HF animations (kla033 / me161389): the lower front hangs from the centre hinge, the upper front swings over, the fronts fold flat
    #   (THETA + BETA = 180 deg at the end) into a compact pack in front of / above the cabinet. The fronts are NOT bent to suit the hardware.
    # HARDWARE (follows the fronts, constant link lengths): fixed lift body (pivot O) -> primary lever (LA) -> elbow J -> secondary lever (LB) -> bracket
    #   pivot P on the upper front; plus a coupling rod from the secondary lever to a pin-in-slot on the lower front (guides the folding).
    # INFERRED: pivot positions and lever lengths (offline fit, no collision with fronts / carcass); the real HF spring / power unit is not modelled.
    module BifoldProto
      module_function

      W = 800.0
      H = 560.0
      D = 320.0
      HC = H  # carcass height = fronts stack
      T = 18.0
      FT = 18.0
      GAP = 3.0
      FA = 16.0

      THETA = [[0.0, 0.0], [0.06, 3.0], [0.12, 10.0], [0.25, 44.0], [0.38, 84.0], [0.50, 118.0], [0.65, 148.0], [0.82, 163.0], [1.0, 167.0]].freeze
      CD = [[0.0, 304.0], [0.1, 360.9], [0.2, 433.8], [0.3, 520.2], [0.4, 606.1], [0.5, 594.5], [0.6, 564.6], [0.7, 519.7], [0.8, 477.2], [0.9, 450.7], [1.0, 432.0]].freeze
      CZ = [[0.0, 280.0], [0.1, 302.7], [0.2, 351.4], [0.3, 433.9], [0.4, 516.5], [0.5, 581.1], [0.6, 628.9], [0.7, 649.6], [0.8, 652.7], [0.9, 651.3], [1.0, 650.0]].freeze
      BETA = [[0.0, 0.0], [0.60, 0.0], [0.82, 7.0], [1.0, 13.0]].freeze

      # hardware (fitted offline): O body pivot, PL bracket pivot (upper-front local n, s), LA/LB lever lengths, K on the secondary lever, RL on the lower front
      O = [170.11, 253.64].freeze
      PL = [-6.8, 220.52].freeze
      LA = 136.85
      LB = 233.84
      ROD_F = 0.894
      RL = [-8.347, 25.383].freeze

      # monotone cubic Hermite (Fritsch-Carlson)
      def interp(keys, u)
        u = [[u, keys.first[0]].max, keys.last[0]].min
        n = keys.size
        dx = (0...n - 1).map { |i| keys[i + 1][0] - keys[i][0] }
        sl = (0...n - 1).map { |i| (keys[i + 1][1] - keys[i][1]) / dx[i] }
        m = Array.new(n)
        m[0] = sl[0]
        m[n - 1] = sl[n - 2]
        (1...n - 1).each { |i| m[i] = sl[i - 1] * sl[i] <= 0 ? 0.0 : (sl[i - 1] + sl[i]) / 2.0 }
        (0...n - 1).each do |i|
          next if sl[i].abs < 1e-12

          a = m[i] / sl[i]
          b = m[i + 1] / sl[i]
          s = a * a + b * b
          if s > 9
            tt = 3.0 / Math.sqrt(s)
            m[i] = tt * a * sl[i]
            m[i + 1] = tt * b * sl[i]
          end
        end
        i = (0...n - 1).find { |k| u <= keys[k + 1][0] } || n - 2
        h = dx[i]
        tt = (u - keys[i][0]) / h
        h00 = 2 * tt**3 - 3 * tt**2 + 1
        h10 = tt**3 - 2 * tt**2 + tt
        h01 = -2 * tt**3 + 3 * tt**2
        h11 = tt**3 - tt**2
        h00 * keys[i][1] + h10 * h * m[i] + h01 * keys[i + 1][1] + h11 * h * m[i + 1]
      end

      def smooth(x)
        x = [[x, 0.0].max, 1.0].min
        x * x * (3 - 2 * x)
      end

      # fixed lift body: real D-shaped housing outline measured on the Haefele lift-up block (HAFELE+lift-up+fitting+senso+3674.skp), (y from the front, z); hub at (20, 395)
      BODY_BLOCK = [[102.7, 266.2], [134.1, 266.2], [135.2, 269.4], [137.6, 288.5], [137.6, 377.5], [137.1, 400.4], [134.1, 421.4], [132.9, 424.5], [65.6, 424.5], [55.2, 422.5], [48.1, 420.5], [42.9, 417.5], [32.1, 411.5], [29.1, 408.5], [18.7, 399.0], [16.7, 395.9], [7.9, 382.7], [1.6, 364.9], [-0.5, 347.9], [-0.6, 343.7], [1.6, 325.9], [7.9, 308.2], [17.1, 294.4], [18.1, 292.4], [29.6, 281.7], [32.6, 278.7], [43.4, 272.7], [47.7, 269.9], [54.9, 267.9], [65.6, 266.9], [102.6, 266.9]].freeze
      BODY_HUB = [20.0, 395.0].freeze
      CZ0 = (H - GAP) / 2.0 + GAP / 2.0
      FH = (H - GAP) / 2.0
      C0 = [D - FA, CZ0].freeze

      def circ(c1, r1, c2, r2, sgn)
        dx = c2[0] - c1[0]
        dy = c2[1] - c1[1]
        d = Math.hypot(dx, dy)
        return nil if d > r1 + r2 || d < (r1 - r2).abs || d < 1e-9

        a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
        h = Math.sqrt([r1 * r1 - a * a, 0.0].max)
        mx = c1[0] + a * dx / d
        my = c1[1] + a * dy / d
        sgn.positive? ? [mx + h * dy / d, my - h * dx / d] : [mx - h * dy / d, my + h * dx / d]
      end

      def upper_pt(p, n, s)
        a = p[:theta] * Math::PI / 180.0
        [p[:c][0] + n * Math.cos(a) - s * Math.sin(a), p[:c][1] + n * Math.sin(a) + s * Math.cos(a)]
      end

      def lower_pt(p, n, s)
        b = p[:beta] * Math::PI / 180.0
        [p[:c][0] + n * Math.cos(b) - s * Math.sin(b), p[:c][1] - n * Math.sin(b) - s * Math.cos(b)]
      end

      # reference pose of the fronts + the hardware that follows them
      def pose(u)
        p = { theta: interp(THETA, u), c: [interp(CD, u), interp(CZ, u)], beta: interp(BETA, u) }
        p[:pw] = upper_pt(p, PL[0], PL[1])
        p[:j] = circ(O, LA, p[:pw], LB, 1)
        p[:kw] = [p[:j][0] + (p[:pw][0] - p[:j][0]) * ROD_F, p[:j][1] + (p[:pw][1] - p[:j][1]) * ROD_F]
        p[:rw] = lower_pt(p, RL[0], RL[1])
        p
      end

      def p_closed = pose(0.0)[:pw]
      def j_closed = pose(0.0)[:j]
      def k_closed = pose(0.0)[:kw]
      def r_closed = pose(0.0)[:rw]

      def rot_dz(center, rho_deg)
        Geom::Transformation.rotation(Proto121.pt(0, center[0], center[1]), Geom::Vector3d.new(1, 0, 0), -rho_deg.to_f.degrees)
      end

      def build(model = Sketchup.active_model)
        g = Proto121
        model.start_operation('E.G.C prototype B - bi-fold', true)
        root = model.entities.add_group
        root.name = 'EGC_REAL_BIFOLD_REFERENCE'
        re = root.entities
        rig = Proto121::Rig.new('EGC_REAL_BIFOLD_REFERENCE')
        # ---- carcass (open front, no wall / floor) ----
        panel = lambda do |nm, x, d, z, sx, sd, sz|
          pg = g.group(re, nm)
          g.box(pg.entities, x, d, z, sx, sd, sz, g.mat(:panel))
        end
        panel.call('panel_L', 0, 0, 0, T, D, HC)
        panel.call('panel_R', W - T, 0, 0, T, D, HC)
        panel.call('panel_bottom', T, 0, 0, W - 2 * T, D, T)
        panel.call('panel_top', T, 0, HC - T, W - 2 * T, D, T)
        panel.call('panel_back', T, 0, T, W - 2 * T, 8, HC - 2 * T)
        # ---- fronts ----
        fw = W - 4.0
        up = g.group(re, 'upper_front')
        lo = g.group(re, 'lower_front')
        g.box(up.entities, 2, D, CZ0 + GAP / 2.0, fw, FT, FH, g.mat(:door))
        g.box(lo.entities, 2, D, CZ0 - GAP / 2.0 - FH, fw, FT, FH, g.mat(:door))
        [up, lo].each { |q| q.entities.grep(Sketchup::Face).each { |f| f.back_material = g.mat(:door_back) if f.normal.y > 0.9 } }
        # ---- centre hinges: leaf on each front's inner face + barrel on the axis ----
        [W * 0.17, W * 0.83].each do |hx|
          [[up, 1.0], [lo, -1.0]].each do |grp, sg|
            ge = grp.entities
            g.box(ge, hx - 22, D - 3.0, CZ0 + sg * (GAP / 2.0 + 4.0) - (sg.positive? ? 0 : 36.0), 44, 3.0, 36.0, g.mat(:zinc))
            g.box(ge, hx - 22, D - FA, CZ0 + sg * 2.0 - 2.0, 44, FA - 2.0, 4.0, g.mat(:zinc)) # leaf reaching back to the axis
          end
          g.cyl(up.entities, hx - 22, D - FA, CZ0, 5.5, 44, :x, g.mat(:chrome), 16) # hinge barrel on the axis
        end
        # ---- lift mechanism (per side): body -> primary lever -> elbow -> secondary lever -> bracket; coupling rod to the lower front ----
        p0 = p_closed
        j0 = j_closed
        k0 = k_closed
        r0 = r_closed
        rl0 = Math.hypot(r0[0] - k0[0], r0[1] - k0[1])
        rod_end = [r0[0] + (r0[0] - k0[0]) / rl0 * 7.0, r0[1] + (r0[1] - k0[1]) / rl0 * 7.0] # slot allows a few mm of length change
        tube = lambda do |ents, a0, a1, r, x0, th, mat|
          ang = Math.atan2(a1[1] - a0[1], a1[0] - a0[0]) * 180.0 / Math::PI
          pts = g.arc_pts(a0[0], a0[1], r, ang + 90, ang + 270, 30) + g.arc_pts(a1[0], a1[1], r, ang - 90, ang + 90, 30)
          g.poly(ents, pts, :dz, x0, th, mat)
        end
        [[T, 1.0], [W - T, -1.0]].each_with_index do |(xin, sx), si|
          side = si.zero? ? 'L' : 'R'
          xo = ->(off) { xin + sx * off }
          xr = ->(o0, o1) { [xo.call(o0), xo.call(o1)].min }
          # fixed lift body: housing on the side panel carrying the pivot O
          fx = g.group(re, "lift_body_#{side}")
          fe = fx.entities
          body = BODY_BLOCK.map { |by, bz| [O[0] + (BODY_HUB[0] - by), O[1] + (bz - BODY_HUB[1])] }
          g.poly(fe, body, :dz, xr.call(0, 20), 20.0, g.mat(:anth))
          g.cyl(fe, xr.call(20, 36), O[0], O[1], 7.0, 16.0, :x, g.mat(:chrome), 16)
          # primary lever (O -> J)
          l1 = g.group(re, "lever_primary_#{side}")
          tube.call(l1.entities, O, j0, 7.0, xr.call(22, 28), 6.0, g.mat(:steel))
          g.cyl(l1.entities, xr.call(20, 38), j0[0], j0[1], 3.2, 18.0, :x, g.mat(:chrome), 12)
          # secondary lever (J -> P): outer tube + collar + inner rod
          l2 = g.group(re, "lever_secondary_#{side}")
          mid = [j0[0] + (p0[0] - j0[0]) * 0.55, j0[1] + (p0[1] - j0[1]) * 0.55]
          tube.call(l2.entities, j0, mid, 5.0, xr.call(30, 40), 10.0, g.mat(:anth))
          cl = [j0[0] + (p0[0] - j0[0]) * 0.50, j0[1] + (p0[1] - j0[1]) * 0.50]
          tube.call(l2.entities, cl, mid, 6.2, xr.call(29, 41), 12.0, g.mat(:chrome))
          tube.call(l2.entities, mid, p0, 3.4, xr.call(32, 38), 6.0, g.mat(:chrome))
          g.cyl(l2.entities, xr.call(28, 44), p0[0], p0[1], 3.2, 16.0, :x, g.mat(:chrome), 12)
          g.cyl(l2.entities, xr.call(42, 50), k0[0], k0[1], 3.0, 8.0, :x, g.mat(:chrome), 12)
          # coupling rod (K on the secondary lever -> pin-in-slot R on the lower front)
          cr = g.group(re, "coupling_rod_#{side}")
          tube.call(cr.entities, k0, rod_end, 4.0, xr.call(46, 50), 4.0, g.mat(:steel))
          # bracket on the upper front (pivot P) and pin bracket on the lower front (R)
          bk = g.group(up.entities, "bracket_#{side}")
          g.box(bk.entities, xr.call(26, 46), D - 2.0, CZ0 + PL[1] - 30.0, 20.0, 2.0, 60.0, g.mat(:zinc))
          [[xr.call(24, 30), 6.0], [xr.call(42, 48), 6.0]].each { |x0, th| tube.call(bk.entities, [D - 1.0, p0[1]], p0, 5.0, x0, th, g.mat(:zinc)) }
          lb = g.group(lo.entities, "bracket_lower_#{side}")
          g.box(lb.entities, xr.call(40, 56), D - 2.0, r0[1] - 22.0, 16.0, 2.0, 44.0, g.mat(:zinc))
          tube.call(lb.entities, [D - 1.0, r0[1]], r0, 5.0, xr.call(44, 52), 8.0, g.mat(:zinc))
          g.cyl(lb.entities, xr.call(42, 54), r0[0], r0[1], 2.6, 12.0, :x, g.mat(:chrome), 12)
          rig.add(l1, "primary lever #{side}") do |u|
            j = pose(u)[:j]
            rot_dz(O, (Math.atan2(j[1] - O[1], j[0] - O[0]) - Math.atan2(j0[1] - O[1], j0[0] - O[0])) * 180.0 / Math::PI)
          end
          rig.add(l2, "secondary lever #{side}") do |u|
            q = pose(u)
            a1 = Math.atan2(q[:pw][1] - q[:j][1], q[:pw][0] - q[:j][0]) - Math.atan2(p0[1] - j0[1], p0[0] - j0[0])
            Proto121.move_xdz(0, q[:j][0] - j0[0], q[:j][1] - j0[1]) * rot_dz(j0, a1 * 180.0 / Math::PI)
          end
          rig.add(cr, "coupling rod #{side}") do |u|
            q = pose(u)
            a1 = Math.atan2(q[:rw][1] - q[:kw][1], q[:rw][0] - q[:kw][0]) - Math.atan2(r0[1] - k0[1], r0[0] - k0[0])
            Proto121.move_xdz(0, q[:kw][0] - k0[0], q[:kw][1] - k0[1]) * rot_dz(k0, a1 * 180.0 / Math::PI)
          end
        end
        # ---- motion of the fronts ----
        rig.add(up, 'upper front') do |u|
          p = pose(u)
          Proto121.move_xdz(0, p[:c][0] - C0[0], p[:c][1] - C0[1]) * rot_dz(C0, p[:theta])
        end
        rig.add(lo, 'lower front') do |u|
          p = pose(u)
          Proto121.move_xdz(0, p[:c][0] - C0[0], p[:c][1] - C0[1]) * rot_dz(C0, -p[:beta])
        end
        Proto121.register_rig(rig)
        model.commit_operation
        rig.apply(0.0, model)
        rig
      end
    end
  end
end
