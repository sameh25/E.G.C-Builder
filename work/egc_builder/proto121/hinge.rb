# frozen_string_literal: true

module EGC
  module Proto121
    # PROTOTYPE A - EGC_REAL_HINGE_REFERENCE (R3, rebuilt from scratch from the real concealed-hinge block Component_1.skp)
    # SOURCE (measured in SketchUp from the block, two poses of the same hinge: closed #7 and open #5; hinge frame X = across the hinge width,
    #   y = along the arm (door side at small y), z = away from the mounting plane):
    #   * mounting plate d1: cruciform sheet, 52 x 42 mm, two 32 mm screw slots, on the carcass side panel (z = 0);
    #   * arm d2: stamped INVERTED-U channel 16 mm wide, 66 mm long, cranked (tail z 3..13, tip z 8..22.6), two pivot pins A (y 26.1, z 19.4) and B (y 37.4, z 14.4);
    #   * cup: bowl D 29.7 x 10.7 deep + one-sided flange 53 x 15.3 x 2.1 with two screws; the arm tip + links sit INSIDE the bowl.
    #   * poses: the cup turns EXACTLY +90 deg about the instant centre (18.2, 8.7) between closed and open (hole pairs on the cup matched).
    # AXES (all four measured on the block): arm pins A (y 26.09, z 19.43), B (37.43, 14.43); cup axes P (17.04, 8.2), Q (21.7, 5.2) in the closed pose.
    #   Both measured poses were checked: the cup is rigid (P-Q = 5.54 mm in both) and turns +90 deg; P is only 1.3 mm from the instant centre, i.e. the cup
    #   turns about its own axis P while P is carried by the link A-P (length 14.4 mm, swings 7 deg between the poses).
    #   The constant-length test A-P / B-Q over the two poses gives 14.42 -> 14.0 mm and 18.24 -> 15.89 mm: B-Q is NOT a rigid link in the CAD (the curved
    #   leaf between B and the cup flexes), so only A-P is modelled as a link; B and Q are drawn as real axes. Coupling law: link swing proportional to the cup
    #   angle (the CAD gives only the two end poses). Door edge = cup rim - 3 mm (minimum drilling distance); overlay/inset follows from that.
    # This block is an INSET-type crank (door edge ~ at the plate plane). Other overlays need another arm crank (future).
    module Hinge6
      module_function

      A = [26.1, 19.43].freeze     # (y, z)
      B = [37.43, 14.43].freeze
      P = [17.04, 8.2].freeze      # real cup axis carried by link A-P
      Q = [21.7, 5.2].freeze       # real second cup axis
      YB = 23.6                    # door back face
      DOOR_T = 18.0
      ZE = -0.8                    # door hinge edge = cup rim (z 2.2) - 3 mm
      XC = 26.5                    # hinge mid X
      CUP_Z = 17.07                # cup axis height above the plate plane
      CUP_R = 14.84
      ANG_END = 90.0

      def circ(c1, r1, c2, r2, prev)
        dx = c2[0] - c1[0]
        dy = c2[1] - c1[1]
        d = Math.hypot(dx, dy)
        return nil if d > r1 + r2 || d < (r1 - r2).abs || d < 1e-9

        a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
        h = Math.sqrt([r1 * r1 - a * a, 0.0].max)
        mx = c1[0] + a * dx / d
        my = c1[1] + a * dy / d
        p1 = [mx + h * dy / d, my - h * dx / d]
        p2 = [mx - h * dy / d, my + h * dx / d]
        Math.hypot(p1[0] - prev[0], p1[1] - prev[1]) < Math.hypot(p2[0] - prev[0], p2[1] - prev[1]) ? p1 : p2
      end

      def l1 = Math.hypot(A[0] - P[0], A[1] - P[1])
      PSI0 = Math.atan2(P[1] - A[1], P[0] - A[0])
      PSI1 = Math.atan2(7.54 - A[1], 18.70 - A[0]) # link direction in the measured open pose
      PHI_TOT = PSI1 - PSI0

      # rows: [door angle deg, offy, offz, link swing rad] ; cup/door point p -> R(ang) (p - P) + P(phi)  = R p + off
      def table
        @table ||= (0..ANG_END.to_i).map do |deg|
          th = deg * Math::PI / 180.0
          phi = PHI_TOT * deg / ANG_END
          pp = [A[0] + l1 * Math.cos(PSI0 + phi), A[1] + l1 * Math.sin(PSI0 + phi)]
          r = [P[0] * Math.cos(th) - P[1] * Math.sin(th), P[0] * Math.sin(th) + P[1] * Math.cos(th)]
          [deg.to_f, pp[0] - r[0], pp[1] - r[1], phi]
        end
      end

      def pose(alpha)
        rows = table
        a = [[alpha, 0.0].max, rows.last[0]].min
        rows.each_cons(2) do |r0, r1|
          next unless a >= r0[0] - 1e-9 && a <= r1[0] + 1e-9

          f = r1[0] == r0[0] ? 0.0 : (a - r0[0]) / (r1[0] - r0[0])
          return r0.each_index.map { |i| r0[i] + (r1[i] - r0[i]) * f }
        end
        rows.last
      end

      def alpha_of(t) = ANG_END * t
      def max_alpha = table.last[0]
    end

    module HingeProto
      module_function

      Y0 = 28.0         # panel front edge (hinge y): 1 mm clear of the open door
      ZH = 110.0        # builder height of the hinge mid-plane (X = XC)
      DOOR_W = 300.0
      DOOR_H = 160.0
      PANEL_D = 300.0

      # ---- outlines measured on the block (CAD silhouettes) -----------------------------------------------------
      ARM_SIDE = [[74.1, 3.2], [79.7, 3.2], [81.0, 3.8], [82.5, 6.2], [82.8, 11.1], [44.5, 13.0], [42.6, 14.3], [40.0, 20.2], [38.3, 21.3], [32.8, 21.5], [32.2, 22.3],
                  [31.0, 22.6], [23.1, 22.6], [19.8, 19.7], [17.8, 13.8], [17.2, 8.0], [19.0, 9.0], [20.7, 14.8], [24.3, 15.6], [32.6, 16.6], [34.3, 15.6], [37.1, 8.0], [40.6, 5.3]].freeze
      ARM_TOP_EDGE = [[17.8, 13.8], [19.8, 19.7], [23.1, 22.6], [31.0, 22.6], [32.8, 21.5], [38.3, 21.3], [40.0, 20.2], [42.6, 14.3], [44.5, 13.0], [82.8, 11.1]].freeze
      PLATE = [[16.5, 40.8], [36.4, 40.8], [36.8, 56.0], [38.3, 56.8], [51.2, 56.8], [52.3, 57.7], [52.4, 75.5], [51.8, 76.6], [37.8, 76.8], [36.4, 78.3], [36.4, 82.8], [16.5, 82.8],
               [16.5, 78.5], [15.2, 76.8], [1.5, 76.8], [0.9, 76.3], [0.8, 57.5], [1.5, 56.8], [14.7, 56.8], [16.2, 56.0]].freeze   # (X, y)
      PLATE_HOLES = [[[7.4, 65.0], [16.0, 65.0], [16.7, 65.8], [16.7, 67.7], [16.0, 68.6], [7.4, 68.6], [6.8, 68.0], [6.8, 65.6]],
                     [[36.9, 65.0], [45.5, 65.0], [46.2, 65.6], [46.2, 68.0], [45.5, 68.6], [36.9, 68.6], [36.3, 67.8], [36.3, 65.7]]].freeze
      FLANGE = [[0.4, 16.4], [52.6, 16.4], [53.0, 17.2], [53.0, 30.5], [52.5, 31.4], [1.3, 31.7], [0.4, 31.2], [0.0, 30.5], [0.0, 17.2]].freeze  # (X, z)

      def solid(e, outer, holes, plane, c, len, mat)
        g = Proto121
        before = e.to_a
        mk = lambda do |pts|
          pts.map { |a, b| plane == :xd ? g.pt(a, b, c) : (plane == :dz ? g.pt(c, a, b) : g.pt(a, c, b)) }
        end
        f = e.add_face(mk.call(outer))
        return nil unless f&.valid?

        holes.each { |h| e.add_face(mk.call(h))&.erase! }
        dirv = Geom::Vector3d.new(*Proto121::AXV[{ xd: :z, dz: :x, xz: :d }[plane]])
        sign = f.normal.dot(dirv) >= 0 ? 1 : -1
        f.pushpull(sign * len.abs.mm)
        g.paint_new(e, before, mat)
        f
      end

      # affine transform of the hinge (y, z) plane (rotation by ang CCW about the origin + offset), for hand s, panel x xp
      def aff(s, xp, ang, off)
        c = Math.cos(ang)
        sn = Math.sin(ang)
        m11 = c            # x' <- x
        m12 = s * sn       # x' <- y_m
        m21 = s * -sn      # y_m' <- x
        m22 = c            # y_m' <- y_m
        tx = xp - c * xp + s * sn * Y0 + s * off[1]
        ty = c * Y0 + s * sn * xp + off[0] - Y0
        arr = [m11, m21, 0, 0, m12, m22, 0, 0, 0, 0, 1, 0, tx.mm, ty.mm, 0, 1]
        Geom::Transformation.new(arr)
      end

      def rot_about(s, xp, ang, c)
        r = [c[0] * Math.cos(ang) - c[1] * Math.sin(ang), c[0] * Math.sin(ang) + c[1] * Math.cos(ang)]
        aff(s, xp, ang, [c[0] - r[0], c[1] - r[1]])
      end

      # one hinge assembly; s = +1 (left panel, door to +x) / -1 (right panel, mirrored); xp = x of the panel inner face
      def build_hand(model, root, s, xp, name, rig)
        g = Proto121
        h6 = Hinge6
        grp = g.group(root.entities, name)
        ge = grp.entities
        bx = ->(z) { xp + s * z }
        bd = ->(y) { Y0 - y }
        bz = ->(xh) { ZH + (xh - h6::XC) }
        # (y,z) polygon -> :xd plane polygon in builder, extruded along hinge X
        yz = ->(pts) { pts.map { |y, z| [bx.call(z), bd.call(y)] } }
        ext = lambda do |ents, pts, x0, x1, mat, holes = []|
          solid(ents, yz.call(pts), holes.map { |h| yz.call(h) }, :xd, bz.call(x0), x1 - x0, mat)
        end
        # ---- carcass side panel (fixed) ----
        pnl = g.group(ge, "#{name}_side_panel")
        xa, xb = [bx.call(-18.0), bx.call(0.0)].minmax
        g.box(pnl.entities, xa, -PANEL_D + 0.0, bz.call(-120.0), xb - xa, PANEL_D, 300.0, g.mat(:panel))
        # panel front edge at d = 0 (box spans d -300..0)
        # ---- mounting plate (fixed) ----
        fix = g.group(ge, "#{name}_plate_and_arm")
        fe = fix.entities
        pl_xy = ->(pts) { pts.map { |xh, y| [bd.call(y), bz.call(xh)] } }
        z0, z1 = [0.0, 1.6]
        cx = s.positive? ? bx.call(z0) : bx.call(z1)
        solid(fe, pl_xy.call(PLATE), PLATE_HOLES.map { |h| pl_xy.call(h) }, :dz, cx, z1 - z0, g.mat(:zinc))
        px = s.positive? ? bx.call(1.6) : bx.call(3.2)
        solid(fe, pl_xy.call([[17.0, 44.0], [36.0, 44.0], [36.0, 82.8], [17.0, 82.8]]), [], :dz, px, 1.6, g.mat(:zinc))
        [[11.7, 66.8], [41.3, 66.8]].each { |xh, y| g.cyl(fe, bx.call(1.6), bd.call(y), bz.call(xh), 4.0, s * 3.4, :x, g.mat(:chrome), 14) }
        # ---- arm: two side walls (inverted U) + top web following the crank, pivots A / B ----
        ext.call(fe, ARM_SIDE, 18.5, 19.5, g.mat(:zinc))
        ext.call(fe, ARM_SIDE, 33.4, 34.4, g.mat(:zinc))
        web = ARM_TOP_EDGE + ARM_TOP_EDGE.reverse.map { |y, z| [y, z - 1.2] }
        ext.call(fe, web, 19.5, 33.4, g.mat(:zinc))
        [h6::A, h6::B].each do |y, z|
          g.cyl(fe, bx.call(z), bd.call(y), bz.call(18.0), 2.0, 17.0, :z, g.mat(:chrome), 14)
          g.cyl(fe, bx.call(z), bd.call(y), bz.call(34.4), 2.8, 0.8, :z, g.mat(:chrome), 14)
        end
        # ---- door + cup (moving) ----
        door = g.group(ge, "#{name}_door")
        de = door.entities
        xe = bx.call(h6::ZE)
        dx0, dx1 = [xe, bx.call(h6::ZE + DOOR_W)].minmax
        g.box(de, dx0, bd.call(h6::YB), bz.call(h6::XC - DOOR_H / 2.0), dx1 - dx0, h6::DOOR_T, DOOR_H, g.mat(:door))
        de.grep(Sketchup::Face).each { |f| f.back_material = g.mat(:door_back) if f.normal.y > 0.9 }
        cxw = bx.call(h6::CUP_Z)
        czw = bz.call(h6::XC)
        bore = de.add_circle(g.pt(cxw, bd.call(h6::YB), czw), Geom::Vector3d.new(0, 1, 0), h6::CUP_R.mm, 32)
        bf = bore.first.faces.min_by(&:area)
        g.push(bf, [0, -1, 0], h6::YB - 14.0) if bf
        # cup bowl (hollow) + bottom + rim, flange with screws
        cup = g.group(de, "#{name}_cup")
        ce = cup.entities
        ring = ce.add_face(ce.add_circle(g.pt(cxw, bd.call(24.7), czw), Geom::Vector3d.new(0, 1, 0), h6::CUP_R.mm, 32))
        g.punch(ce, g.pt(cxw, bd.call(24.7), czw), Geom::Vector3d.new(0, 1, 0), h6::CUP_R - 1.0, 32)
        g.push(ring, [0, -1, 0], 24.7 - 14.0) if ring
        ce.grep(Sketchup::Face).each { |f| f.material = f.back_material = g.mat(:zinc) }
        bot = ce.add_face(ce.add_circle(g.pt(cxw, bd.call(15.0), czw), Geom::Vector3d.new(0, 1, 0), (h6::CUP_R - 0.9).mm, 32))
        g.push(bot, [0, -1, 0], 1.0) if bot
        fl = g.group(ce, "#{name}_flange")
        fpts = FLANGE.map { |xh, z| [bx.call(z), bz.call(xh)] }
        solid(fl.entities, fpts, [], :xz, bd.call(25.7), 2.1, g.mat(:chrome))
        [6.3, 46.8].each { |xh| g.cyl(fl.entities, bx.call(23.9), bd.call(25.7), bz.call(xh), 4.0, -1.2, :d, g.mat(:zinc), 12) }
        # carrier plates (hold D1 / D2) inside the bowl, two cheeks
        car = g.group(ce, "#{name}_carrier")
        ctr = Proto121.hull2d(g.circle_pts(h6::P[0], h6::P[1], 3.0, 10) + g.circle_pts(h6::Q[0], h6::Q[1], 3.0, 10) + [[21.0, 3.2], [21.0, 12.0]])
        [21.2, 31.0].each { |x0| ext.call(car.entities, ctr, x0, x0 + 1.2, g.mat(:steel)) }
        [h6::P, h6::Q].each { |y, z| g.cyl(car.entities, bx.call(z), bd.call(y), bz.call(21.0), 1.6, 12.4, :z, g.mat(:chrome), 12) }
        rig.add(door, "#{name} door") do |t|
          p = h6.pose(h6.alpha_of(t))
          aff(s, xp, p[0] * Math::PI / 180.0, [p[1], p[2]])
        end
        # ---- link A -> P (real axes), two plates between the arm walls and the carrier cheeks ----
        lg = g.group(ge, "#{name}_link_1")
        link_pts = Proto121.hull2d(g.circle_pts(h6::A[0], h6::A[1], 2.4, 12) + g.circle_pts(h6::P[0], h6::P[1], 2.4, 12))
        [20.0, 32.2].each { |x0| ext.call(lg.entities, link_pts, x0, x0 + 1.0, g.mat(:steel)) }
        rig.add(lg, "#{name} link 1") do |t|
          p = h6.pose(h6.alpha_of(t))
          rot_about(s, xp, p[3], h6::A)
        end
        grp
      end

      # horizontal section through the hinge mid-plane (plan view of the mechanism); on=false hides it
      def section(on, model = Sketchup.active_model)
        @plane = nil unless @plane&.valid?
        begin; model.rendering_options['SectionDefaultFillColor'] = Sketchup::Color.new(150, 150, 156); rescue StandardError; end
        @plane ||= model.entities.add_section_plane([0, 0, (ZH + 0.3).mm], [0, 0, -1])
        @plane.visible = false
        on ? @plane.activate : model.entities.grep(Sketchup::SectionPlane).each { |p| p.deactivate if p.respond_to?(:deactivate) }
      rescue StandardError => e
        warn "section: #{e.message}"
      end

      def build(model = Sketchup.active_model)
        model.start_operation('E.G.C prototype A - hinge', true)
        root = model.entities.add_group
        root.name = 'EGC_REAL_HINGE_REFERENCE'
        rig = Proto121::Rig.new('EGC_REAL_HINGE_REFERENCE')
        build_hand(model, root, 1, 0.0, 'HINGE_LEFT', rig)
        build_hand(model, root, -1, 900.0, 'HINGE_RIGHT', rig)
        Proto121.register_rig(rig)
        model.commit_operation
        rig.apply(0.0, model)
        rig
      end
    end
  end
end
