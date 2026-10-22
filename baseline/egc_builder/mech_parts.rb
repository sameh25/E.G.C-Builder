# frozen_string_literal: true

module EGC
  # Shared hardware parts library (original geometry, medium detail, real relative metal thickness).
  # Every part is a cached ComponentDefinition ("EGC_MP_<key>"), so a pantry with five identical wire
  # baskets stores ONE basket and five light instances. Local frame (mm): x width, d depth from the
  # back toward the room, z up; every part's origin is its minimum corner (rods: start point).
  module MechParts
    module_function

    STEEL_T = 1.5 # sheet steel thickness used by channels / brackets (mm)

    def model
      Sketchup.active_model
    end

    # ---- materials ----------------------------------------------------------------------------
    def m
      @m = nil unless @m && @m[:chrome]&.valid?
      @m ||= begin
        p = Appliances.pal
        { chrome: Appliances.mat('Wire Chrome', [150, 155, 162]), steel: p[:body], dark: p[:steel_dk], black: p[:black], rubber: p[:rubber], white: p[:white],
          anth: Appliances.mat('Anthracite', [38, 40, 44]), zinc: Appliances.mat('Zinc Bracket', [172, 176, 180]),
          plastic: Appliances.mat('Bin Plastic', [206, 208, 210]), damper: Appliances.mat('Damper', [34, 36, 40]) }
      end
    end

    def reset_materials
      @m = nil
    end

    # ---- component cache --------------------------------------------------------------------------
    def defn(key)
      name = "EGC_MP_#{key}"
      d = model.definitions[name]
      return d if d && d.entities.size.positive?

      d ||= model.definitions.add(name)
      # SketchUp drops an EMPTY definition when the next one is added: a composite part (basket) that creates its rods first would lose
      # itself ("reference to deleted Entities" on the first insert in a model). A guide point keeps it alive while it is being filled.
      keep = d.entities.add_cpoint(Geom::Point3d.new(0, 0, 0))
      yield d.entities
      keep.erase! if keep.valid?
      d
    end

    def offset(x, d, z)
      Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), -Geo.mm(d), Geo.mm(z)))
    end

    def put(ents, definition, x, d, z, material = nil, tr = nil)
      t = offset(x, d, z)
      t *= tr if tr
      inst = ents.add_instance(definition, t)
      inst.material = material if material
      inst
    end

    ROT_D = Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), -90.degrees) # +x -> +d
    ROT_Z = Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 1, 0), -90.degrees) # +x -> +z

    def axis_tr(axis)
      { x: nil, d: ROT_D, z: ROT_Z }[axis]
    end

    def r1(v)
      v.to_f.round(1)
    end

    # ---- primitives -----------------------------------------------------------------------------
    # round rod / cylinder starting at (x,d,z) running `len` along +axis
    def rod(ents, x, d, z, axis, len, dia, material, segs = 8)
      return nil if len <= 0.05

      df = defn("rod_#{r1(len)}_#{r1(dia)}_#{segs}") do |e|
        f = e.add_face(e.add_circle(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(1, 0, 0), Geo.mm(dia / 2.0), segs))
        f.pushpull((f.normal.x >= 0 ? 1 : -1) * Geo.mm(len)) if f
      end
      r = dia / 2.0
      ox, od, oz = { x: [0, r, r], d: [r, 0, r], z: [r, r, 0] }[axis]
      put(ents, df, x + ox, d + od, z + oz, material, axis_tr(axis))
    end

    def disc(ents, x, d, z, axis, len, dia, material, segs = 12)
      rod(ents, x, d, z, axis, len, dia, material, segs)
    end

    # solid block (cached by size)
    def slab(ents, x, d, z, sx, sd, sz, material)
      return nil if sx <= 0.05 || sd <= 0.05 || sz <= 0.05

      df = defn("box_#{r1(sx)}_#{r1(sd)}_#{r1(sz)}") { |e| Geo.box(e, 0, 0, 0, sx, sd, sz) }
      put(ents, df, x, d, z, material)
    end

    # extruded polygon: pts are [a,b] pairs in the plane spanned by the two axes; extruded `len` along the third.
    #   plane :xz (extrude along +d)  |  :dz (extrude along +x)  |  :xd (extrude along +z)
    def prism(ents, key, x, d, z, plane, pts, len, material)
      df = defn("prism_#{key}_#{plane}_#{r1(len)}") do |e|
        pp = pts.map do |a, b|
          case plane
          when :xz then Geo.p3(a, 0, b)
          when :dz then Geo.p3(0, a, b)
          else Geo.p3(a, b, 0)
          end
        end
        f = e.add_face(pp)
        if f
          dir = case plane
                when :xz then f.normal.y <= 0 ? 1 : -1 # toward +d = world -y
                when :dz then f.normal.x >= 0 ? 1 : -1
                else f.normal.z >= 0 ? 1 : -1
                end
          f.pushpull(dir * Geo.mm(len))
        end
      end
      put(ents, df, x, d, z, material)
    end

    # C-section sheet-steel channel running `len` along +d (slides, rails). open: +1 = opening toward +x
    def channel(ents, x, d, z, len, wx, hz, t, open, material)
      pts = if open >= 0
              [[0, 0], [wx, 0], [wx, t], [t, t], [t, hz - t], [wx, hz - t], [wx, hz], [0, hz]]
            else
              [[0, 0], [wx, 0], [wx, hz], [0, hz], [0, hz - t], [wx - t, hz - t], [wx - t, t], [0, t]]
            end
      prism(ents, "ch#{open}_#{r1(wx)}_#{r1(hz)}_#{r1(t)}", x, d, z, :xz, pts, len, material)
    end

    # L bracket: horizontal leg `a` (along d), vertical leg `b` (along z), `wd` wide along x
    def l_bracket(ents, x, d, z, a, b, t, wd, material, front: false)
      pts = front ? [[0, 0], [a, 0], [a, b], [a - t, b], [a - t, t], [0, t]] : [[0, 0], [a, 0], [a, t], [t, t], [t, b], [0, b]]
      prism(ents, "lb#{front ? "f" : ""}_#{r1(a)}_#{r1(b)}_#{r1(t)}", x, d, z, :dz, pts, wd, material)
    end

    # flat bar between two points of the (d,z) plane at x; width w (in-plane), thickness t (along x)
    def bar(ents, x, p0, p1, w, t, material)
      dd = p1[0] - p0[0]
      dz = p1[1] - p0[1]
      len = Math.hypot(dd, dz)
      return nil if len < 0.5

      df = defn("bar_#{r1(len)}_#{r1(w)}_#{r1(t)}") { |e| Geo.box(e, 0, -w / 2.0, 0, len, w, t) }
      dir = Geom::Vector3d.new(0, -dd, dz).normalize
      zax = Geom::Vector3d.new(1, 0, 0)
      yax = zax * dir
      tr = Geom::Transformation.axes(Geom::Point3d.new(Geo.mm(x), -Geo.mm(p0[0]), Geo.mm(p0[1])), dir, yax, zax)
      inst = ents.add_instance(df, tr)
      inst.material = material
      inst
    end

    # pivot pin / rivet head along x
    def pivot(ents, x, d, z, r, len, material)
      rod(ents, x, d, z, :x, len, r * 2, material, 10)
    end

    # ---- composite parts ---------------------------------------------------------------------------
    # wire basket: bottom grid + rim + posts + mid rails (rods of `wire` mm); origin = min corner.
    def wire_basket(ents, x, d, z, w, dep, h, material, wire = 4.0)
      df = defn("basket_#{r1(w)}_#{r1(dep)}_#{r1(h)}_#{r1(wire)}") do |e|
        mt = material
        pitch = [[(w / (w / 32.0).round), 26.0].max, 44.0].min
        nx = [(w / pitch).round, 2].max
        gx = (w - wire) / nx
        (nx + 1).times { |i| rod(e, i * gx, 0, wire, :d, dep, wire, mt, 6) }          # long wires under
        ny = [(dep / 60.0).round, 2].max
        gy = (dep - wire) / ny
        (ny + 1).times { |j| rod(e, 0, j * gy, 0, :x, w, wire, mt, 6) }              # cross wires
        levels = h > 70 ? [h, h * 0.5] : [h]
        levels.each do |zz|
          rod(e, 0, 0, zz - wire, :x, w, wire, mt, 6)
          rod(e, 0, dep - wire, zz - wire, :x, w, wire, mt, 6)
          rod(e, 0, 0, zz - wire, :d, dep, wire, mt, 6)
          rod(e, w - wire, 0, zz - wire, :d, dep, wire, mt, 6)
        end
        [[0, 0], [w - wire, 0], [0, dep - wire], [w - wire, dep - wire]].each { |px, pd| rod(e, px, pd, 0, :z, h, wire, mt, 6) }
        # a few vertical wires on the front/back to read as mesh
        n = [(w / 90.0).floor, 1].max
        n.times { |k| rod(e, (k + 1) * w / (n + 1.0), 0, wire, :z, h - wire, wire * 0.8, mt, 6) } if h > 70
      end
      put(ents, df, x, d, z, material)
    end

    # thin-walled tray (solid sides) - bottom + 4 walls
    def tray(ents, x, d, z, w, dep, h, t, material)
      df = defn("tray_#{r1(w)}_#{r1(dep)}_#{r1(h)}_#{r1(t)}") do |e|
        Geo.box(e, 0, 0, 0, w, dep, t)
        Geo.box(e, 0, 0, t, w, t, h - t)
        Geo.box(e, 0, dep - t, t, w, t, h - t)
        Geo.box(e, 0, t, t, t, dep - 2 * t, h - t)
        Geo.box(e, w - t, t, t, t, dep - 2 * t, h - t)
      end
      put(ents, df, x, d, z, material)
    end

    # open plastic bin (tapered walls) with a rim lip and a front grip notch
    def bin(ents, x, d, z, w, dep, h, material)
      df = defn("bin_#{r1(w)}_#{r1(dep)}_#{r1(h)}") do |e|
        t = 2.5
        Geo.box(e, 2, 2, 0, w - 4, dep - 4, t)
        Geo.box(e, 0, 0, t, w, t, h - t)
        Geo.box(e, 0, dep - t, t, w, t, h - t)
        Geo.box(e, 0, t, t, t, dep - 2 * t, h - t)
        Geo.box(e, w - t, t, t, t, dep - 2 * t, h - t)
        Geo.box(e, -3, -3, h - 4, w + 6, 5, 4)             # rim lip front
        Geo.box(e, -3, dep - 2, h - 4, w + 6, 5, 4)         # rim lip back
        Geo.box(e, -3, 2, h - 4, 5, dep - 4, 4)
        Geo.box(e, w - 2, 2, h - 4, 5, dep - 4, 4)
      end
      put(ents, df, x, d, z, material)
    end

    # damper / soft-close cylinder along d
    def damper(ents, x, d, z, len, material)
      rod(ents, x, d, z, :d, len, 14, material, 10)
      rod(ents, x + 4, d + len, z + 4, :d, len * 0.55, 6, m[:chrome], 8)
    end

    # Reusable visible mounting plate for a generic concealed hinge. Its geometry is visual only;
    # the two screw heads are not drilling coordinates or a manufacturer mounting pattern.
    def hinge_mount_plate(ents, x, d, z)
      zinc = m[:zinc]
      dark = m[:dark]
      df = defn('concealed_hinge_mount_plate_v15') do |e|
        # Folded mounting plate: full base, raised stepped slide block, and stamped side cheeks.
        Geo.box(e, 0, 0, 0, 2.2, 40, 42)
        Geo.box(e, 2.0, 7, 7, 2.4, 26, 28)
        Geo.box(e, 3.8, 11, 10, 2.2, 18, 22)
        prism(e, 'hinge_plate_cheek', 0, 0, 0, :xz, [[0, 0], [4, 0], [4, 8], [2.5, 12], [2.5, 30], [4, 34], [4, 42], [0, 42]], 2.0, zinc)
        prism(e, 'hinge_plate_cheek_mirror', 0, 38, 0, :xz, [[0, 0], [4, 0], [4, 8], [2.5, 12], [2.5, 30], [4, 34], [4, 42], [0, 42]], 2.0, zinc)
        [7, 33].each { |off| rod(e, 2.7, off - 2.5, 18.5, :x, 1.5, 5, dark, 10) } # visual fasteners only
        slab(e, 5.4, 17, 18, 1.2, 6, 6, m[:chrome])
        rod(e, 0.5, 17, 18.5, :x, 6.5, 6, m[:chrome], 12)
      end
      put(ents, df, x, d, z, zinc)
    end

    # concealed cup hinge cup + body (reusable): 35 mm cup with rim flange, hinge body - the part that is
    # screwed INTO the door and must move rigidly with it. Origin = cup centre on the door's back plane
    # (d = 0); d grows toward the room. The arm + mounting plate are a SEPARATE assembly (Cabinet#door_hinges
    # in mechanisms.rb): the plate stays fixed to the carcass side panel while the arm re-aims each frame to
    # keep its far end exactly on this cup, so the two never visibly detach as the door swings open - a rigid
    # copy of the whole hinge moving with the door (the old design) would swing the arm's far end away from
    # the plate instead.
    def cup_hinge(ents, xc, cd, zc, side)
      df = defn("cuphinge_v15_#{side}") do |e|
        # Recessed cup, rolled flange, cup wall and rear boss. All dimensions are visual only.
        Appliances.ring(e, -17.5, -1.1, -17.5, 18.2, 14.5, 1.4, m[:chrome], :y, 24)
        Appliances.ring(e, -17.5, -0.2, -17.5, 15.0, 12.8, 7.5, m[:zinc], :y, 24)
        rod(e, -17.5, 6.4, -17.5, :d, 3.0, 25.6, m[:dark], 20)
        # Offset two-ear clevis to make the arm connection read as an articulated joint.
        slab(e, -9.5, 6.0, -4.0, 7.0, 5.0, 8.0, m[:zinc])
        slab(e, 2.5, 6.0, -4.0, 7.0, 5.0, 8.0, m[:zinc])
        rod(e, -1.5, 4.5, 0, :x, 15.0, 5.0, m[:chrome], 12)
      end
      put(ents, df, xc, cd, zc)
    end

    # Lightweight two-web articulated silhouette for generic concealed hinges. Dimensions are visual only;
    # drilling and manufacturer fit remain unavailable until a selected hinge profile is supplied.
    def hinge_arm(ents, len, material = nil)
      return nil if len.to_f < 24

      steel = material || m[:zinc]
      df = defn("concealed_hinge_arm_v15_#{r1(len)}") do |e|
        # Stamped dog-leg arm with broad cup shoulder, waisted bridge, forked plate end and two real pivots.
        outline = [[0, -7], [len * 0.18, -6.2], [len * 0.31, -3.4], [len * 0.65, -2.5],
                   [len * 0.83, -5.2], [len, -4.5], [len, 4.5], [len * 0.83, 5.2],
                   [len * 0.65, 2.5], [len * 0.31, 3.4], [len * 0.18, 6.2], [0, 7]]
        prism(e, "hinge_arm_stamp_a_#{r1(len)}", 0, -2.5, 0, :xz, outline, 1.8, steel)
        prism(e, "hinge_arm_stamp_b_#{r1(len)}", 0, 0.7, 0, :xz, outline, 1.8, steel)
        # Pressed reinforcing spine with a shallow offset around the articulated waist.
        prism(e, "hinge_arm_rib_#{r1(len)}", len * 0.20, -0.6, 0, :xz,
              [[0, -2.2], [len * 0.16, -3.1], [len * 0.40, -1.6], [len * 0.16, 3.1], [0, 2.2]], 1.2, m[:chrome])
        slab(e, len * 0.40, -1.8, -2.8, len * 0.20, 3.6, 5.6, m[:dark])
        rod(e, 0, -2.2, -2.2, :d, 5.4, 5.6, m[:chrome], 12)
        rod(e, len - 2.2, -2.2, -2.2, :d, 5.4, 5.6, m[:chrome], 12)
        rod(e, len * 0.52 - 2.0, -2.0, -2.0, :d, 4.0, 4.8, m[:dark], 12)
      end
      put(ents, df, 0, 0, 0, steel)
    end

    # One flat stamped strap link of a two-link concealed-hinge arm, lying in the horizontal plane, origin at
    # its first pivot, running along local +x. layer 0/1 stacks the two links at different heights.
    # Visual only: no manufacturer data.
    def hinge_link(ents, len, layer)
      steel = m[:zinc]
      z0 = layer.zero? ? -2.6 : -0.6
      df = defn("hinge_link_v17_#{r1(len)}_#{layer}") do |e|
        pts = [[-5, -3], [-3, -5.5], [len + 3, -5.5], [len + 5, -3], [len + 5, 3], [len + 3, 5.5], [-3, 5.5], [-5, 3]]
        prism(e, "hinge_link_strap_#{layer}", 0, 0, z0, :xd, pts, 1.8, steel)
        prism(e, "hinge_link_bead_#{layer}", 0, 0, z0 + 1.8, :xd,
              [[2, -2.2], [len - 2, -2.2], [len - 2, 2.2], [2, 2.2]], 0.7, m[:chrome])
        [0, len].each do |px|
          pin = [[-2.2, 0], [-1.5, -1.5], [0, -2.2], [1.5, -1.5], [2.2, 0], [1.5, 1.5], [0, 2.2], [-1.5, 1.5]]
          prism(e, "hinge_link_pin_#{layer}_#{px.zero? ? 0 : 1}", px, 0, z0 - 0.8, :xd,
                pin.map { |a, b| [a, b] }, 3.8, m[:chrome])
        end
      end
      put(ents, df, 0, 0, 0, steel)
    end

    # rail-mounted sleeve for a front (door / drawer front connector): plate + two screws
    def front_connector(ents, x, d, z, material)
      l_bracket(ents, x, d, z, 34, 28, 2.5, 26, material)
      2.times { |i| rod(ents, x + 6 + i * 14, d + 34, z + 8, :d, 4, 4, m[:chrome], 6) }
    end

    # rectangular tube (uses a hollow-looking prism: outer tube with a slightly recessed centre line)
    def tube(ents, x, d, z, axis, len, a, b, material)
      case axis
      when :z then slab(ents, x, d, z, a, b, len, material)
      when :d then slab(ents, x, d, z, a, len, b, material)
      else slab(ents, x, d, z, len, a, b, material)
      end
    end

    # 3/4 or full round wire shelf (turning basket): arc rim + spokes + hub. deg: sector size, start: first spoke angle
    # centre (cx,cd); angles in the (x,d) plane, 0 = +x, counter-clockwise toward +d
    def wire_disc(ents, cx, cd, z, r, deg, start, wire, material, lip_h = 40)
      df = defn("disc_bored_#{r1(r)}_#{r1(deg)}_#{r1(start)}_#{r1(wire)}_#{r1(lip_h)}") do |e|
        n = [(deg / 18.0).ceil, 4].max
        step = deg / n
        pts = (0..n).map { |i| a = (start + i * step).degrees; [r * Math.cos(a), r * Math.sin(a)] }
        pts.each_cons(2) do |(x0, y0), (x1, y1)|
          rod_between(e, [x0, y0, 0], [x1, y1, 0], wire, material)                  # rim (bottom ring)
          rod_between(e, [x0, y0, lip_h], [x1, y1, lip_h], wire, material)           # rim (top ring)
        end
        pts.each { |px, py| rod(e, px - wire / 2.0, py - wire / 2.0, 0, :z, lip_h, wire, material, 6) }
        (0..n).step(2) do |i|
          px,py=pts[i]
          rod_between(e, [px*26/r, py*26/r, 0], pts[i] + [0], wire * 1.1, material)
        end
        Appliances.ring(e,0,0,0,32,21,lip_h*0.5,material,:z)
      end
      put(ents, df, cx, cd, z, material)
    end

    # rod between two 3D points given in the local frame (x, d, z); cached by length
    def rod_between(ents, a, b, dia, material)
      dx = b[0] - a[0]
      dd = b[1] - a[1]
      dz = b[2] - a[2]
      len = Math.sqrt(dx * dx + dd * dd + dz * dz)
      return nil if len < 0.5

      df = defn("rod_#{r1(len)}_#{r1(dia)}_8") do |e|
        f = e.add_face(e.add_circle(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(1, 0, 0), Geo.mm(dia / 2.0), 8))
        f.pushpull((f.normal.x >= 0 ? 1 : -1) * Geo.mm(len)) if f
      end
      dir = Geom::Vector3d.new(dx, -dd, dz).normalize
      up = dir.parallel?(Geom::Vector3d.new(0, 0, 1)) ? Geom::Vector3d.new(1, 0, 0) : Geom::Vector3d.new(0, 0, 1)
      yax = (up * dir).normalize
      zax = (dir * yax).normalize
      tr = Geom::Transformation.axes(Geom::Point3d.new(Geo.mm(a[0]), -Geo.mm(a[1]), Geo.mm(a[2])), dir, yax, zax)
      inst = ents.add_instance(df, tr)
      inst.material = material
      inst
    end
  end
end
