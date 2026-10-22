# frozen_string_literal: true

Sketchup.require(File.join(File.dirname(__FILE__), 'imove_data'))

module EGC
  module Proto121
    # PROTOTYPE C - EGC_REAL_IMOVE_REFERENCE  (Kesseboehmer iMove Double Tray 600) - R3: the four pivots are measured INDEPENDENTLY on the STEP.
    # MEASURED hole centres of the CAD arm plates (closed pose; z = depth from the front, y = height from the unit bottom, mm):
    #   arm 1: Hb (70.3, 16.2) housing, Pb (116.9, 287.2) side plate, Hh (13.2, 358.6) tail;   arm 2: H2 (140.2, 86.2) housing, Pa (186.5, 357.4) side plate.
    #   lengths 275.0 / 275.1; housing pivots (69.9, 70.0) apart, plate pivots (69.6, 70.2) apart: equal within 0.4 mm, so the loop housing -> arm 1 -> rigid
    #   side plate (+ trays) -> arm 2 -> housing is a (near) parallelogram. It is SOLVED here as a general four-bar from the measured numbers (nothing is
    #   forced): the plate rotation / tray tilt is a result (tenths of a degree).
    # DRIVE: arm 1 angle, swept until the plate has dropped the official 340 mm (Kesseboehmer data). Arm 1 is rigid with the handle bracket (tail Hh -> bar),
    #   so the handle bar follows ARM 1 (lever arm ~ 365 mm), not the plate; the grip hangs from the bar (pendant). NOT MODELLED: spring, cam, lock.
    module IMoveProto
      module_function

      D_U = 267.0
      H_U = 565.0
      DROP = 340.0
      CAB_H = 710.0
      CAB_W_IN = 565.0 # STEP skin planes x = 5 and 570 (565 apart) sit on the cabinet side panels
      CAB_D = 282.0
      PT = 18.0
      # The fitting stands ON the cabinet bottom (its housings are the lowest part of the manufacturer's model): the trays then come out
      # and end the published 340 mm lower, in front of and BELOW the cabinet. The free height stays above it (lift fittings, hinges).
      Z0 = PT

      def dx(x_ac) = x_ac - 287.5
      def dd(z_ac) = D_U - z_ac
      def dz(y_ac) = y_ac + Z0

      PLATE = [[267, 247], [267, 565], [31, 565], [30, 495], [40, 478], [120, 475], [119, 450], [57, 345], [44, 323], [30, 296], [30, 253], [38, 237], [52, 229], [240, 232], [262, 247]].freeze
      HOUSING = [[67, 1], [200, 1], [226, 36], [261, 110], [261, 202], [244, 216], [190, 216], [170, 238], [127, 246], [109, 202], [107, 146], [93, 97], [68, 57], [58, 36], [58, 10]].freeze
      GRIP = [[8, 371], [28, 371], [34, 355], [38, 300], [30, 262], [22, 242], [10, 242], [6, 262], [4, 300], [2, 345]].freeze
      HB = [70.3, 16.2].freeze
      PB = [116.9, 287.2].freeze
      HH = [13.2, 358.6].freeze
      H2 = [140.2, 86.2].freeze
      PA = [186.5, 357.4].freeze
      BAR = [15.05, 357.35].freeze # handle bar axis (z, y): bar shell bbox z 8.2..21.9, y 349.2..365.5 on the STEP = 2.2 mm from the arm-1 tail hole Hh (the bar runs through the tails of both arm-1 plates)
      L1 = Math.hypot(PB[0] - HB[0], PB[1] - HB[1])
      L2 = Math.hypot(PA[0] - H2[0], PA[1] - H2[1])
      CPL = Math.hypot(PA[0] - PB[0], PA[1] - PB[1])
      ARM1 = [[68.0, 6.0], [83.0, 13.5], [118.0, 90.0], [132.5, 144.0], [132.5, 186.0], [151.0, 235.0], [155.0, 255.0], [149.5, 275.0], [138.0, 288.5], [22.0, 369.0], [8.0, 368.5], [3.0, 361.0], [3.5, 353.0], [119.5, 271.0], [129.5, 255.0], [115.5, 219.5], [107.0, 187.5], [107.0, 146.0], [93.5, 97.0], [59.0, 21.5], [60.5, 11.5]].freeze
      ARM2 = [[107.5, 20.5], [119.5, 43.0], [149.0, 77.0], [159.5, 102.0], [154.0, 114.5], [163.0, 152.5], [181.0, 193.0], [203.5, 275.5], [204.5, 321.0], [199.5, 360.5], [189.5, 370.0], [174.0, 364.5], [176.5, 347.0], [179.5, 314.0], [177.5, 273.0], [157.5, 203.0], [137.0, 156.0], [127.5, 94.5], [109.5, 62.5], [95.5, 26.5]].freeze

      def ease(u)
        u = [[u, 0.0].max, 1.0].min
        u * u * (3 - 2 * u)
      end

      def rotv(v, rho_deg)
        r = rho_deg * Math::PI / 180.0
        [v[0] * Math.cos(r) - v[1] * Math.sin(r), v[1] * Math.cos(r) + v[0] * Math.sin(r)]
      end

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

      # rows [rho1 deg (arm 1, forward = +), pbz, pby (plate pivot Pb), phi deg (plate), rho2 deg (arm 2)] from the measured four-bar
      def table
        @table ||= begin
          base = Math.atan2(PA[1] - PB[1], PA[0] - PB[0])
          a2_0 = Math.atan2(PA[1] - H2[1], PA[0] - H2[0])
          rows = [[0.0, PB[0], PB[1], 0.0, 0.0]]
          prev = PA.dup
          (1..1600).each do |k|
            rho = k * 0.1
            pb = rotv([PB[0] - HB[0], PB[1] - HB[1]], rho).then { |v| [HB[0] + v[0], HB[1] + v[1]] }
            pa = circ(H2, L2, pb, CPL, prev) or break
            prev = pa
            phi = Math.atan2(pa[1] - pb[1], pa[0] - pb[0]) - base
            a2 = Math.atan2(pa[1] - H2[1], pa[0] - H2[0]) - a2_0
            rows << [rho, pb[0], pb[1], phi * 180.0 / Math::PI, a2 * 180.0 / Math::PI]
            break if PB[1] - pb[1] >= DROP
          end
          rows
        end
      end

      def rho_end = table.last[0]

      def pose(u)
        rows = table
        x = ease(u) * (rows.size - 1)
        i = [x.floor, rows.size - 2].min
        f = x - i
        a = rows[i]
        b = rows[i + 1]
        a.each_index.map { |k| a[k] + (b[k] - a[k]) * f }
      end

      def rho(u) = pose(u)[0]

      # builder-frame (forward d, up z) translation of the plate pivot Pb, plate rotation, handle bar displacement
      def plate_move(u)
        p = pose(u)
        [-(p[1] - PB[0]), p[2] - PB[1]]
      end

      def handle_move(u)
        v = rotv([BAR[0] - HB[0], BAR[1] - HB[1]], pose(u)[0])
        [-(HB[0] + v[0] - BAR[0]), HB[1] + v[1] - BAR[1]]
      end

      def poly_holes(e, outer, holes, plane, c, len, mat)
        g = Proto121
        before = e.to_a
        pp = outer.map { |a, b| plane == :dz ? g.pt(c, a, b) : g.pt(a, b, c) }
        f = e.add_face(pp)
        return nil unless f&.valid?

        holes.each do |h|
          hp = h.map { |a, b| plane == :dz ? g.pt(c, a, b) : g.pt(a, b, c) }
          e.add_face(hp)&.erase!
        end
        dirv = plane == :dz ? [1, 0, 0] : [0, 0, 1]
        sign = f.normal.dot(Geom::Vector3d.new(*dirv)) >= 0 ? 1 : -1
        f.pushpull(sign * len.abs.mm * (len.negative? ? -1 : 1))
        g.paint_new(e, before, mat)
        f
      end

      def inset(poly, k)
        cx = poly.sum { |p| p[0] } / poly.size
        cy = poly.sum { |p| p[1] } / poly.size
        poly.map do |x, y|
          vx = cx - x
          vy = cy - y
          l = Math.hypot(vx, vy)
          [x + vx / l * k, y + vy / l * k]
        end
      end

      def build(model = Sketchup.active_model)
        g = Proto121
        model.start_operation('E.G.C prototype C - iMove', true)
        root = model.entities.add_group
        root.name = 'EGC_REAL_IMOVE_REFERENCE'
        re = root.entities
        rig = Proto121::Rig.new('EGC_REAL_IMOVE_REFERENCE')
        hw = CAB_W_IN / 2.0
        panel = lambda do |nm, x, d, z, sx, sd, sz|
          pg = g.group(re, nm)
          g.box(pg.entities, x, d, z, sx, sd, sz, g.mat(:panel))
        end
        panel.call('panel_L', -hw - PT, 0, 0, PT, CAB_D, CAB_H)
        panel.call('panel_R', hw, 0, 0, PT, CAB_D, CAB_H)
        panel.call('panel_bottom', -hw, 0, 0, CAB_W_IN, CAB_D, PT)
        panel.call('panel_top', -hw, 0, CAB_H - PT, CAB_W_IN, CAB_D, PT)
        panel.call('panel_back', -hw, -8, PT, CAB_W_IN, 8, CAB_H - 2 * PT)
        mod = []
        [[-1.0, 'L'], [1.0, 'R']].each do |sx, side|
          xin = sx * hw
          xs = ->(off) { xin - sx * off }
          hg = g.group(re, "housing_#{side}")
          md = IMoveData
          m2 = ->(pts) { pts.map { |zz, yy| [dd(zz), dz(yy)] } }
          xr = ->(o0, o1) { [xs.call(o0), xs.call(o1)].min }
          # open housing frame (STEP slabs x 5-30: rim wall with pivot-boss holes) + thin back skin; the mechanism inside is left visible
          poly_holes(hg.entities, m2.call(md::RIM), [m2.call(md::RIM_INNER)] + md::RIM_HOLES.map { |h| m2.call(h) }, :dz, xr.call(0.0, 25.0), 25.0, g.mat(:anth))
          g.poly(hg.entities, m2.call(md::RIM), :dz, xr.call(0.0, 0.6), 0.6, g.mat(:steel))
          # visible mechanism parts measured on the STEP (x 12-18 slab): perforated rack strip, bent wire spring, cam lever
          poly_holes(hg.entities, m2.call(md::RACK), md::RACK_HOLES.map { |h| m2.call(h) }, :dz, xr.call(7.0, 9.0), 2.0, g.mat(:zinc))
          g.poly(hg.entities, m2.call(md::WIRE), :dz, xr.call(9.0, 11.5), 2.5, g.mat(:chrome))
          g.poly(hg.entities, m2.call(md::CAM), :dz, xr.call(7.0, 9.5), 2.5, g.mat(:chrome))
          [HB, H2].each { |hz, hy| g.cyl(hg.entities, xr.call(20.0, 36.0), dd(hz), dz(hy), 4.5, 16.0, :x, g.mat(:chrome), 14) }
          cg = g.group(re, "housing_cover_#{side}")
          g.poly(cg.entities, m2.call(md::COVER), :dz, xr.call(36.0, 38.6), 2.6, g.mat(:anth))
          pg = g.group(re, "plate_#{side}")
          po = PLATE.map { |zz, yy| [dd(zz), dz(yy)] }
          g.poly(pg.entities, po, :dz, xr.call(33.5, 35.0), 1.5, g.mat(:zinc))
          [PB, PA].each { |hz, hy| g.cyl(pg.entities, xr.call(28.0, 36.0), dd(hz), dz(hy), 4.5, 8.0, :x, g.mat(:chrome), 14) }
          mod << pg
          [[ARM1, HB, [PB, HH], 1], [ARM2, H2, [PA], 2]].each do |poly_ac, hub, others, k|
            ag = g.group(re, "arm#{k}_#{side}")
            outl = poly_ac.map { |zz, yy| [dd(zz), dz(yy)] }
            xa = xr.call(28.0, 32.5)
            holes = ([hub] + others).map { |hz, hy| g.circle_pts(dd(hz), dz(hy), 5.5, 14) }
            poly_holes(ag.entities, outl, holes, :dz, xa, 4.5, g.mat(:zinc))
            [hub, *others].each { |hz, hy| g.cyl(ag.entities, xr.call(27.0, 35.0), dd(hz), dz(hy), 4.0, 8.0, :x, g.mat(:chrome), 12) }
            ctr = [dd(hub[0]), dz(hub[1])]
            rig.add(ag, "arm #{k} #{side}") { |u| Proto121.rot_dz(ctr, -(k == 1 ? pose(u)[0] : pose(u)[4])) }
          end
        end
        [[247.0, 'lower'], [486.0, 'upper']].each do |y0, nm|
          tg = g.group(re, "tray_#{nm}")
          te = tg.entities
          x0 = -247.5
          wd = 495.0
          d0 = dd(259.0)
          dl = 259.0 - 37.0
          z = dz(y0)
          g.box(te, x0, d0, z, wd, dl, 3.0, g.mat(:tray))
          g.box(te, x0, d0, z, 4.0, dl, 16.0, g.mat(:tray))
          g.box(te, x0 + wd - 4.0, d0, z, 4.0, dl, 16.0, g.mat(:tray))
          g.box(te, x0, d0 + dl - 4.0, z, wd, 4.0, 16.0, g.mat(:tray))
          g.box(te, x0, d0, z, wd, 4.0, 16.0, g.mat(:tray))
          [d0 + 2.0, d0 + dl - 2.0].each { |rd| g.cyl(te, x0, rd, z + 42.0, 3.0, wd, :x, g.mat(:chrome), 10) } # gallery rails, front and back (as on the manufacturer's model)
          mod << tg
        end
        # handle: cross bar on the arm-1 handle pivots + pendant grip (rigid with arm 1's pivot motion)
        hnd = g.group(re, 'handle')
        he = hnd.entities
        g.cyl(he, -249.5, dd(BAR[0]), dz(BAR[1]), 7.0, 499.0, :x, g.mat(:chrome), 14)
        g.poly(he, GRIP.map { |zz, yy| [dd(zz), dz(yy)] }, :dz, -60.0, 120.0, g.mat(:anth))
        pbc = [dd(PB[0]), dz(PB[1])]
        mod.each do |grp|
          rig.add(grp, grp.name) do |u|
            f, up = plate_move(u)
            Proto121.move_xdz(0, f, up) * Proto121.rot_dz(pbc, -pose(u)[3])
          end
        end
        rig.add(hnd, 'handle') do |u|
          f, up = handle_move(u)
          Proto121.move_xdz(0, f, up)
        end
        Proto121.register_rig(rig)
        model.commit_operation
        rig.apply(0.0, model)
        rig
      end
    end
  end
end
