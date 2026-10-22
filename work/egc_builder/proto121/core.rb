# frozen_string_literal: true

module EGC
  # E.G.C 1.21.0 MECHANISM REFERENCE PROTOTYPES - shared core.
  # Standalone review scenes (hinge / bi-fold / iMove). Nothing here touches normal cabinet generation.
  # Frame used by every prototype (mm): x = across, d = depth toward the ROOM (model y = -d), z = up.
  module Proto121
    module_function

    # ---- points / materials ------------------------------------------------------------------------
    def pt(x, d, z)
      Geom::Point3d.new(x.to_f.mm, -d.to_f.mm, z.to_f.mm)
    end

    def vec(x, d, z)
      Geom::Vector3d.new(x.to_f.mm, -d.to_f.mm, z.to_f.mm)
    end

    PALETTE = {
      panel: [214, 200, 170], door: [196, 160, 112], door_back: [150, 118, 78], door_up: [232, 200, 150], door_low: [206, 170, 120],
      zinc: [172, 176, 182], steel: [120, 124, 130], dark: [36, 38, 42], chrome: [205, 208, 212], red: [200, 60, 50],
      green: [60, 150, 80], blue: [60, 110, 190], yellow: [230, 190, 40], glass: [150, 200, 220], tray: [225, 226, 228],
      anth: [58, 60, 66], white: [240, 240, 240], floor: [190, 190, 195]
    }.freeze

    def mat(key)
      model = Sketchup.active_model
      name = "P121_#{key}"
      m = model.materials[name] || model.materials.add(name)
      m.color = Sketchup::Color.new(*PALETTE.fetch(key)) unless m.color.to_a[0, 3] == PALETTE[key]
      m.alpha = 0.35 if key == :glass
      m
    end

    # ---- raw solids -----------------------------------------------------------------------------------
    AXV = { x: [1, 0, 0], d: [0, -1, 0], z: [0, 0, 1] }.freeze

    def paint_new(e, before, material)
      (e.to_a - before).each do |ent|
        next unless ent.is_a?(Sketchup::Face)

        ent.material = material
        ent.back_material = material
      end
    end

    # polygon extruded from plane coordinate c by len.  :xd pts (x,d) along z | :dz pts (d,z) along x | :xz pts (x,z) along d
    def poly(e, pts, plane, c, len, material)
      before = e.to_a
      pp = pts.map do |a, b|
        case plane
        when :xd then pt(a, b, c)
        when :dz then pt(c, a, b)
        else pt(a, c, b)
        end
      end
      f = e.add_face(pp)
      return nil unless f&.valid?

      dirv = Geom::Vector3d.new(*AXV[{ xd: :z, dz: :x, xz: :d }[plane]])
      sign = f.normal.dot(dirv) >= 0 ? 1 : -1
      f.pushpull(sign * len.abs.mm * (len.negative? ? -1 : 1))
      paint_new(e, before, material)
      f
    end

    def cyl(e, cx, cd, cz, r, len, axis, material, segs = 16)
      before = e.to_a
      n = Geom::Vector3d.new(*AXV[axis])
      edges = e.add_circle(pt(cx, cd, cz), n, r.mm, segs)
      f = edges.first.faces.min_by(&:area) || e.add_face(edges)
      return nil unless f&.valid?

      sign = f.normal.dot(n) >= 0 ? 1 : -1
      f.pushpull(sign * len.abs.mm * (len.negative? ? -1 : 1))
      paint_new(e, before, material)
      (e.to_a - before).each { |ent| ent.soft = ent.smooth = true if ent.is_a?(Sketchup::Edge) && ent.line[1].parallel?(n) }
      f
    end

    def box(e, x, d, z, sx, sd, sz, material)
      pts = [[x, d], [x + sx, d], [x + sx, d + sd], [x, d + sd]]
      poly(e, pts, :xd, z, sz, material)
    end

    def arc_pts(cx, cy, r, a0, a1, step = 20)
      n = [((a1 - a0).abs / step.to_f).ceil, 1].max
      (0..n).map { |i| a = (a0 + (a1 - a0) * i / n.to_f) * Math::PI / 180.0; [cx + r * Math.cos(a), cy + r * Math.sin(a)] }
    end

    def circle_pts(cx, cy, r, n = 14)
      (0...n).map { |i| a = 2 * Math::PI * i / n; [cx + r * Math.cos(a), cy + r * Math.sin(a)] }
    end

    def hull2d(pts)
      pts = pts.uniq.sort
      cross = ->(o, a, b) { (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]) }
      lower = []
      pts.each { |p| lower.pop while lower.size >= 2 && cross.call(lower[-2], lower[-1], p) <= 0; lower << p }
      upper = []
      pts.reverse_each { |p| upper.pop while upper.size >= 2 && cross.call(upper[-2], upper[-1], p) <= 0; upper << p }
      lower[0...-1] + upper[0...-1]
    end

    # a bar (stadium) between two plan points, thickness along z
    def stadium(e, p0, p1, r, z0, th, material, seg = 12)
      ang = Math.atan2(p1[1] - p0[1], p1[0] - p0[0]) * 180.0 / Math::PI
      pts = arc_pts(p0[0], p0[1], r, ang + 90, ang + 270, 180.0 / seg) + arc_pts(p1[0], p1[1], r, ang - 90, ang + 90, 180.0 / seg)
      poly(e, pts, :xd, z0, th, material)
    end

    # a bar (stadium) in the (d,z) plane between two points, thickness along x at x0
    def stadium_dz(e, p0, p1, r, x0, th, material, seg = 12)
      ang = Math.atan2(p1[1] - p0[1], p1[0] - p0[0]) * 180.0 / Math::PI
      pts = arc_pts(p0[0], p0[1], r, ang + 90, ang + 270, 180.0 / seg) + arc_pts(p1[0], p1[1], r, ang - 90, ang + 90, 180.0 / seg)
      poly(e, pts, :dz, x0, th, material)
    end

    # ---- groups -----------------------------------------------------------------------------------------
    def group(parent, name)
      g = parent.add_group
      g.name = name
      # a hidden guide point keeps the still-empty group alive when the next group is added outside a model operation (a prototype built inside a
      # production cabinet: SketchUp drops an empty definition there)
      g.entities.add_cpoint(Geom::Point3d.new(0, 0, 0)).hidden = true
      g
    end

    # cut a round hole: circle drawn on an existing face, the inner disc erased
    def punch(ents, centre, normal, r, segs = 24)
      edges = ents.add_circle(centre, normal, r.mm, segs)
      inner = edges.first.faces.min_by(&:area)
      inner&.erase!
    end

    # push/pull a face by dist (mm) toward model-space direction dirv (array), whatever its normal
    def push(face, dirv, dist)
      return nil unless face&.valid?

      sign = face.normal.dot(Geom::Vector3d.new(*dirv)) >= 0 ? 1 : -1
      face.pushpull(sign * dist.to_f.mm)
    end

    # ---- state rig -------------------------------------------------------------------------------------
    # Each entry: moving entity + lambda(t) -> Geom::Transformation (motion RELATIVE to the closed pose).
    class Rig
      attr_reader :name, :t

      def initialize(name)
        @name = name
        @items = []
        @t = 0.0
        @on_state = nil
      end

      def add(entity, label = nil, &fn)
        @items << { e: entity, base: entity.transformation, fn: fn, label: label }
        entity
      end

      def on_state(&blk)
        @on_state = blk
      end

      def items
        @items
      end

      def apply(t, model = Sketchup.active_model)
        @t = [[t.to_f, 0.0].max, 1.0].min
        model.start_operation("#{@name} #{(@t * 100).round}%", true, false, @applied)
        @applied = true
        @items.each do |it|
          next unless it[:e].valid?

          it[:e].transformation = it[:fn].call(@t) * it[:base]
        end
        @on_state&.call(@t)
        model.commit_operation
        @t
      end
    end

    @rigs = {}

    class << self
      attr_reader :rigs
    end

    def register_rig(rig)
      @rigs[rig.name] = rig
    end

    # rotation about a vertical axis through plan point (x,d) by `deg` measured CCW in the (x -> d) plane (builder frame)
    def rot_xd(x, d, deg)
      Geom::Transformation.rotation(pt(x, d, 0), Geom::Vector3d.new(0, 0, 1), -deg.to_f.degrees)
    end

    # rotation about the model x-axis through plane point (d, z); rho CCW in the (d -> z) plane
    def rot_dz(center, rho_deg)
      Geom::Transformation.rotation(pt(0, center[0], center[1]), Geom::Vector3d.new(1, 0, 0), -rho_deg.to_f.degrees)
    end

    def move_xdz(dx, dd, dz)
      Geom::Transformation.translation(vec(dx, dd, dz))
    end

    # ---- camera ------------------------------------------------------------------------------------------
    def camera(kind, center, dist = 900.0)
      c = pt(*center)
      eye, up =
        case kind
        when :front then [c.offset(Geom::Vector3d.new(0, -dist.mm, 0)), [0, 0, 1]]
        when :side then [c.offset(Geom::Vector3d.new(dist.mm, 0, 0)), [0, 0, 1]]
        when :side_l then [c.offset(Geom::Vector3d.new(-dist.mm, 0, 0)), [0, 0, 1]]
        when :top then [c.offset(Geom::Vector3d.new(0, 0, dist.mm)), [0, 1, 0]]
        else [c.offset(Geom::Vector3d.new(dist.mm * 0.7, -dist.mm * 0.8, dist.mm * 0.55)), [0, 0, 1]]
        end
      cam = Sketchup::Camera.new(eye, c, Geom::Vector3d.new(*up))
      Sketchup.active_model.active_view.camera = cam
      Sketchup.active_model.active_view.zoom_extents if false
      cam
    end
  end
end
