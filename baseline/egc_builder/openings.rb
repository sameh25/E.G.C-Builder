# frozen_string_literal: true

require 'json'

module EGC
  # Doors & Windows on walls the USER drew (no room / wall building here - by design).
  #   * click a wall face (loose faces, or inside a group / component) with the OpeningTool
  #   * the wall's plane and direction are read from the picked face, so it works on any wall angle
  #   * a REAL hole is cut through the wall (draw the rectangle on the face, push-pull it through)
  #   * a framed door / window (with motion) is built inside the hole, tagged and editable:
  #     resize / change type / move / delete re-open the hole ("fill then re-cut"), one undo step each
  # Local frame of an opening group (builder convention, same as cabinets): x along the wall,
  # d toward the viewer (room side, d = 0 is the wall face), z up; the frame lives at d in [-t, 0].
  module Openings
    ATTR = 'egc'
    TAG = 'EGC Openings'
    MIN_MM = 250.0
    MARGIN_MM = 20.0

    TYPES = {
      'fixed'          => { kind: 'window', en: 'Fixed window', ar: 'شباك ثابت', w: 1200, h: 1200, sill: 900 },
      'fixed_grid'     => { kind: 'window', en: 'Grid window', ar: 'شباك شبكي', w: 1200, h: 1200, sill: 900 },
      'casement_1'     => { kind: 'window', en: 'Casement (single)', ar: 'شباك مفصلي مفرد', w: 700, h: 1200, sill: 900 },
      'casement_2'     => { kind: 'window', en: 'Casement (double)', ar: 'شباك مفصلي مزدوج', w: 1200, h: 1200, sill: 900 },
      'awning'         => { kind: 'window', en: 'Awning (top hung)', ar: 'شباك قلاب', w: 900, h: 600, sill: 1500 },
      'sliding_2'      => { kind: 'window', en: 'Sliding window (2)', ar: 'شباك سحاب 2', w: 1400, h: 1200, sill: 900 },
      'sliding_3'      => { kind: 'window', en: 'Sliding window (3)', ar: 'شباك سحاب 3', w: 2000, h: 1200, sill: 900 },
      'hung'           => { kind: 'window', en: 'Vertical sliding', ar: 'شباك معلق', w: 900, h: 1300, sill: 900 },
      'door_1'         => { kind: 'door', en: 'Door (single)', ar: 'باب مفرد', w: 900, h: 2100, sill: 0 },
      'door_2'         => { kind: 'door', en: 'Door (double)', ar: 'باب مزدوج', w: 1500, h: 2100, sill: 0 },
      'door_sliding_2' => { kind: 'door', en: 'Sliding door (2)', ar: 'باب سحاب 2', w: 1800, h: 2100, sill: 0 }
    }.freeze

    module_function

    def payload
      TYPES.map { |id, s| { 'id' => id, 'kind' => s[:kind], 'en' => s[:en], 'ar' => s[:ar], 'w' => s[:w], 'h' => s[:h], 'sill' => s[:sill] } }
    end

    def opening?(g)
      g.is_a?(Sketchup::Group) && g.get_attribute(ATTR, 'opening') == true
    end

    def params_of(g)
      { 'type' => g.get_attribute(ATTR, 'otype'), 'w' => g.get_attribute(ATTR, 'w').to_f, 'h' => g.get_attribute(ATTR, 'h').to_f,
        'sill' => g.get_attribute(ATTR, 'sill').to_f, 't' => g.get_attribute(ATTR, 't').to_f }
    end

    # ------------------------------------------------------------------ locating a wall under the cursor
    # Returns a hash describing the wall face / frame under (x, y), or { error: '...' }.
    def locate(view, x, y)
      model = Sketchup.active_model
      ray = view.pickray(x, y)
      res = model.raytest(ray, false)
      return { error: 'no_wall' } unless res

      pt, path = res
      face = path.reverse.find { |e| e.is_a?(Sketchup::Face) }
      return { error: 'no_wall' } unless face

      insts = path.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
      return { error: 'no_wall' } if insts.any? { |i| opening?(i) } # never cut into an existing frame

      tr = Geom::Transformation.new
      insts.each { |i| tr *= i.transformation }
      ents = insts.empty? ? model.entities : entities_of(insts.last)
      return { error: 'no_wall' } unless ents && ents.parent == face.parent

      nw = (tr * face.normal).normalize
      return { error: 'not_vertical' } if nw.z.abs > 0.25

      nw = Geom::Vector3d.new(nw.x, nw.y, 0).normalize
      nw = nw.reverse if nw.dot(ray[1]) > 0 # face the viewer
      xw = Geom::Vector3d.new(0, 0, 1).cross(nw).normalize
      wpts = face.vertices.map { |v| tr * v.position }
      bottom = wpts.map(&:z).min
      { face: face, ents: ents, tr: tr, nw: nw, xw: xw, p: pt, bottom: bottom, insts: insts, model: model }
    end

    def entities_of(inst)
      inst.is_a?(Sketchup::Group) ? inst.entities : inst.definition.entities
    end

    # wall thickness measured along -nw from the hit point to the back face
    def thickness(loc)
      model = loc[:model]
      start = loc[:p].offset(loc[:nw].reverse, 0.3.mm)
      res = model.raytest([start, loc[:nw].reverse], false)
      return nil unless res

      back = res[1].reverse.find { |e| e.is_a?(Sketchup::Face) }
      return nil unless back

      dist = (res[0] - loc[:p]).dot(loc[:nw].reverse)
      dist > 5.mm && dist < 1500.mm ? dist : nil
    end

    # corners of the opening rectangle on the wall face (world), left-bottom first, CCW seen from the viewer
    def rect_world(loc, w, h, zb, center: nil)
      c = center || loc[:p]
      xw = loc[:xw]
      o = Geom::Point3d.new(c.x, c.y, zb)
      lb = o.offset(xw, -w.mm / 2.0)
      rb = o.offset(xw, w.mm / 2.0)
      [lb, rb, rb.offset(Geom::Vector3d.new(0, 0, 1), h.mm), lb.offset(Geom::Vector3d.new(0, 0, 1), h.mm)]
    end

    # -> nil when it fits, else an error code
    def check_fit(loc, corners, skip = nil)
      overlap_with_openings(loc, corners, skip) || inside_face(loc, corners, skip)
    end

    # skip: the opening being moved - its own (still open) hole counts as wall, so a move that overlaps the old position is valid
    def inside_face(loc, corners, skip = nil)
      inv = loc[:tr].inverse
      face = loc[:face]
      own = skip && (loc[:tr] * skip.transformation).inverse
      own_w = skip && skip.get_attribute(ATTR, "w").to_f
      own_h = skip && skip.get_attribute(ATTR, "h").to_f
      mid = Geom::Point3d.new(EGC::Num.sum(corners, &:x) / 4.0, EGC::Num.sum(corners, &:y) / 4.0, EGC::Num.sum(corners, &:z) / 4.0)
      corners.each do |c|
        # nudge 0.3 mm toward the centre so a door standing on the wall's bottom edge still counts as inside
        cl = inv * c.offset(mid - c, 0.3.mm)
        next if own && (p = own * c.offset(mid - c, 0.3.mm)) && p.x.to_mm.between?(-0.3, own_w + 0.3) && p.z.to_mm.between?(-0.3, own_h + 0.3)

        return 'outside' unless face.classify_point(cl) == Sketchup::Face::PointInside
      end
      nil
    end

    def overlap_with_openings(loc, corners, skip)
      cxy = Geom::Point3d.new(EGC::Num.sum(corners, &:x) / 4.0, EGC::Num.sum(corners, &:y) / 4.0, EGC::Num.sum(corners, &:z) / 4.0)
      w1 = (corners[1] - corners[0]).length
      h1 = (corners[3] - corners[0]).length
      loc[:ents].grep(Sketchup::Group).each do |g|
        next unless opening?(g) && !g.equal?(skip)

        w2 = g.get_attribute(ATTR, 'w').to_f.mm
        h2 = g.get_attribute(ATTR, 'h').to_f.mm
        c2 = loc[:tr] * (g.transformation * Geom::Point3d.new(w2 / 2.0, 0, h2 / 2.0))
        dv = c2 - cxy
        next if dv.dot(loc[:nw]).abs > 600.mm

        return 'overlap' if dv.dot(loc[:xw]).abs < (w1 + w2) / 2.0 + MARGIN_MM.mm && dv.z.abs < (h1 + h2) / 2.0
      end
      nil
    end

    # ------------------------------------------------------------------ cutting / filling the hole
    # Draw the rectangle on the wall face and push-pull it through the wall (SketchUp turns that into a
    # real through-hole when the far face is parallel). `into` = world direction pointing into the wall.
    # `thk` is the wall thickness in real (world) mm; the push distance is converted along the pushed direction in the CONTAINER's own
    # units (its rotation, uniform or non-uniform scale and mirror all change that factor - a single xscale is wrong).
    # exact: true = `thk` is already a container-local length in mm.
    def cut_hole(ents, tr, corners, thk, into, exact: false)
      inv = tr.inverse
      inner = ents.add_face(corners.map { |c| inv * c })
      raise 'Could not draw the opening on the wall face.' unless inner && inner.valid?

      nin = (inv * into).normalize
      dir = inner.normal.dot(nin) >= 0 ? 1 : -1
      local = if exact
                thk.mm
              else
                vec = into.normalize
                vec.length = thk
                (inv * vec).length
              end
      inner.pushpull(dir * local)
      true
    end

    # The 8 hole corners of an existing opening group in its container's coordinates.
    def hole_points(og)
      p = params_of(og)
      t = p['t']
      tr = og.transformation
      front = [[0, 0], [p['w'], 0], [p['w'], p['h']], [0, p['h']]].map { |x, z| tr * Geo.p3(x, 0, z) }
      back = [[0, 0], [p['w'], 0], [p['w'], p['h']], [0, p['h']]].map { |x, z| tr * Geo.p3(x, -t, z) }
      [front, back]
    end

    def near?(a, b)
      a.distance(b) < 0.2.mm
    end

    # Close the hole again (front + back face) and merge the patches into the wall faces.
    # Notes learned the hard way: Entities#add_face on an existing hole loop returns the WALL face instead
    # of a patch (erasing an edge of it then deletes the wall!) - Edge#find_faces creates the patch; and one
    # Edge#erase! between coplanar faces merges the whole patch, so the remaining ring edges only need
    # clean-up if they are left dangling inside the merged face.
    def fill_hole(og)
      ents = og.parent.entities
      front, back = hole_points(og)
      all = front + back
      at = ->(ring, pt) { ring.any? { |c| near?(c, pt) } }
      jambs = ents.grep(Sketchup::Face).select do |f|
        vs = f.vertices
        vs.size == 4 && vs.all? { |v| all.any? { |c| near?(c, v.position) } }
      end
      jambs.each { |f| f.erase! if f.valid? }
      # dangling corner-to-corner edges of the old jambs
      ents.grep(Sketchup::Edge).each do |e|
        next unless e.valid? && e.faces.empty?

        s = e.start.position
        t = e.end.position
        e.erase! if (at.call(front, s) && at.call(back, t)) || (at.call(back, s) && at.call(front, t))
      end
      rings = [front, back]
      ring_edges = ->(ring) { ents.grep(Sketchup::Edge).select { |e| e.valid? && at.call(ring, e.start.position) && at.call(ring, e.end.position) } }
      # A door hole that starts at the wall's bottom edge left no ring edge along the floor (and no floor
      # face under the doorway): draw the missing ring edges so find_faces can close front, back AND floor patch.
      rings.each do |ring|
        4.times do |i|
          a = ring[i]
          b = ring[(i + 1) % 4]
          next if ents.grep(Sketchup::Edge).any? { |e| e.valid? && ((near?(e.start.position, a) && near?(e.end.position, b)) || (near?(e.start.position, b) && near?(e.end.position, a))) }

          ents.add_line(a, b)
        end
      end
      rings.each { |ring| ring_edges.call(ring).each { |e| e.find_faces if e.valid? } }
      # the doorway floor (bottom of a door hole): patch between the two floor edges
      front.each_index do |i|
        fa = front[i]
        fb = front[(i + 1) % 4]
        ba = back[i]
        bb = back[(i + 1) % 4]
        next unless (fa.z - fb.z).abs < 0.01.mm && (fa.z - ba.z).abs < 0.01.mm
        next if ents.grep(Sketchup::Face).any? { |f| f.valid? && f.vertices.size >= 4 && [fa, fb, ba, bb].all? { |c| f.vertices.any? { |v| near?(v.position, c) } } && f.normal.z.abs > 0.99 }

        ents.add_face(fa, fb, bb, ba) rescue nil
      end
      # merge the depth edges (front corner - back corner) left between coplanar faces
      ents.grep(Sketchup::Edge).each do |e|
        next unless e.valid? && ((at.call(front, e.start.position) && at.call(back, e.end.position)) || (at.call(back, e.start.position) && at.call(front, e.end.position)))

        fs = e.faces
        e.erase! if fs.size == 2 && fs[0].normal.parallel?(fs[1].normal) && fs[0].material == fs[1].material
      end
      rings.each do |ring|
        ring_edges.call(ring).each do |e|
          next unless e.valid?

          fs = e.faces
          if fs.size == 2
            a, b = fs
            e.erase! if a.normal.parallel?(b.normal) && a.material == b.material
          elsif fs.size == 1 && fs.first.loops.none? { |l| l.edges.include?(e) }
            e.erase!
          end
        end
      end
      # find_faces may have re-created a jamb (lintel / sill) from the edges that were left: sweep once more
      ents.grep(Sketchup::Face).each do |f|
        next unless f.valid? && f.vertices.size == 4 && f.vertices.all? { |v| all.any? { |c| near?(c, v.position) } }

        f.erase!
      end
      ents.grep(Sketchup::Edge).each do |e|
        next unless e.valid? && e.faces.empty?

        s = e.start.position
        t = e.end.position
        e.erase! if all.any? { |c| near?(c, s) } && all.any? { |c| near?(c, t) }
      end
      # whatever is left of the ring inside the merged face carries no face any more
      rings.each { |ring| ring_edges.call(ring).each { |e| e.erase! if e.valid? && e.faces.empty? } }
      true
    end

    # ------------------------------------------------------------------ building the door / window
    def mat(name, rgb, alpha = nil)
      Appliances.mat(name, rgb, alpha)
    end

    def bx(ents, x, d, z, sx, sd, sz, material)
      return nil if sx <= 0.05 || sd <= 0.05 || sz <= 0.05

      g = ents.add_group
      Geo.box(g.entities, 0, 0, 0, sx, sd, sz)
      g.transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), -Geo.mm(d), Geo.mm(z))))
      g.material = material
      g
    end

    def asm(ents, name, move)
      g = ents.add_group
      g.name = name
      g.set_attribute(ATTR, 'move', JSON.generate(move)) if move
      g
    end

    # glazed sash: 4 border bars + glass (+ handle); all in the given entities at absolute coordinates
    def sash(ents, x, z, w, h, d_mid, depth, handle_side, m)
      b = 38.0
      d0 = d_mid - depth / 2.0
      bx(ents, x, d0, z + h - b, w, depth, b, m[:frame])
      bx(ents, x, d0, z, w, depth, b, m[:frame])
      bx(ents, x, d0, z, b, depth, h, m[:frame])
      bx(ents, x + w - b, d0, z, b, depth, h, m[:frame])
      bx(ents, x + b, d_mid - 3, z + b, w - 2 * b, 6, h - 2 * b, m[:glass])
      return unless handle_side

      hx = handle_side == :right ? x + w - b * 0.5 - 6 : x + b * 0.5 - 6
      bx(ents, hx, d0 + depth, z + h * 0.5 - 40, 12, 6, 80, m[:steel])
      bx(ents, hx + 2, d0 + depth + 6, z + h * 0.5 - 30, 8, 26, 60, m[:chrome])
    end

    def build_unit(og, type, w, h, t)
      spec = TYPES[type] or raise "Unknown opening type #{type}"
      door = spec[:kind] == 'door'
      e = og.entities
      m = { frame: mat('Opening Frame', [236, 236, 232]), glass: mat('Opening Glass', [176, 208, 226], 0.35),
            steel: mat('Opening Steel', [112, 116, 120]), chrome: mat('Opening Chrome', [214, 217, 220]),
            leaf: mat('Opening Leaf', [214, 196, 160]) }
      fw = 50.0
      fd = [[t - 20.0, 60.0].max, 110.0].min
      d_back = -t + (t - fd) / 2.0 # frame sits centred in the wall thickness
      dm = d_back + fd / 2.0
      # fixed frame
      bx(e, 0, d_back, h - fw, w, fd, fw, m[:frame])
      bx(e, 0, d_back, 0, fw, fd, h, m[:frame])
      bx(e, w - fw, d_back, 0, fw, fd, h, m[:frame])
      bx(e, 0, d_back, 0, w, fd, door ? 20.0 : fw, m[:frame])
      bx(e, -30, 0, -20, w + 60, 45, 20, m[:frame]) unless door # sill board proud of the wall face
      ix = fw
      iz = door ? 20.0 : fw
      iw = w - 2 * fw
      ih = h - fw - iz
      sd = fd - 12.0
      hang = ->(name, gx, gz, gw, gh, hs, deg, pivot_x) do
        a = asm(e, name, { 'type' => 'rot', 'pivot' => [pivot_x, dm, gz], 'axis' => [0, 0, 1], 'deg' => deg })
        leaf(a.entities, door, gx, gz, gw, gh, dm, sd, hs, m)
      end
      case type
      when 'fixed'
        bx(e, ix, dm - 3, iz, iw, 6, ih, m[:glass])
      when 'fixed_grid'
        bx(e, ix, dm - 3, iz, iw, 6, ih, m[:glass])
        [1, 2].each { |i| bx(e, ix + iw * i / 3.0 - 15, d_back, iz, 30, fd, ih, m[:frame]) }
        [1, 2].each { |i| bx(e, ix, d_back, iz + ih * i / 3.0 - 15, iw, fd, 30, m[:frame]) }
      when 'casement_1', 'door_1'
        hang.call(door ? 'Door leaf' : 'Sash', ix, iz, iw, ih, :right, -95.0, ix)
      when 'casement_2', 'door_2'
        sw = iw / 2.0
        hang.call('Leaf L', ix, iz, sw, ih, :right, -95.0, ix)
        hang.call('Leaf R', ix + sw, iz, sw, ih, :left, 95.0, ix + iw)
      when 'awning'
        a = asm(e, 'Sash', { 'type' => 'rot', 'pivot' => [ix, dm, iz + ih], 'axis' => [1, 0, 0], 'deg' => 35.0 })
        sash(a.entities, ix, iz, iw, ih, dm, sd, :right, m)
      when 'hung'
        hh = ih / 2.0 + 20.0
        sash(e, ix, iz + ih - hh, iw, hh, dm - 12, sd * 0.5, nil, m)
        a = asm(e, 'Lower sash', { 'type' => 'lin', 'v' => [0, 0, ih - hh - 20.0] })
        sash(a.entities, ix, iz, iw, hh, dm + 12, sd * 0.5, :right, m)
      when 'sliding_2', 'door_sliding_2'
        pw = (iw + 30.0) / 2.0
        sash(e, ix + pw - 30, iz, pw, ih, dm + 12, sd * 0.45, nil, m)
        a = asm(e, 'Slider', { 'type' => 'lin', 'v' => [pw - 30.0, 0, 0] })
        sash(a.entities, ix, iz, pw, ih, dm - 12, sd * 0.45, :right, m)
      when 'sliding_3'
        pw = (iw + 60.0) / 3.0
        sash(e, ix + pw - 30, iz, pw, ih, dm + 12, sd * 0.45, nil, m)
        a = asm(e, 'Slider L', { 'type' => 'lin', 'v' => [pw - 30.0, 0, 0] })
        sash(a.entities, ix, iz, pw, ih, dm - 12, sd * 0.45, :right, m)
        c = asm(e, 'Slider R', { 'type' => 'lin', 'v' => [-(pw - 30.0), 0, 0] })
        sash(c.entities, ix + 2 * (pw - 30), iz, pw, ih, dm - 12, sd * 0.45, :left, m)
      end
      og
    end

    def leaf(ents, door, x, z, w, h, dm, depth, handle_side, m)
      if door
        b = 38.0
        d0 = dm - depth / 2.0
        bx(ents, x, d0, z, w, depth, h, m[:leaf])
        hx = handle_side == :right ? x + w - 70 : x + 50
        bx(ents, hx, d0 + depth, z + h * 0.5 - 40, 24, 10, 80, m[:steel])
        bx(ents, hx + 4, d0 + depth + 10, z + h * 0.5 - 30, 16, 40, 20, m[:chrome])
        b
      else
        sash(ents, x, z, w, h, dm, depth, handle_side, m)
      end
    end

    # ------------------------------------------------------------------ high level operations
    # in a wall when there is one to cut through; standing on its own otherwise (empty space, or a face with nothing behind it)
    def place(loc, type, w, h, sill)
      return add_free(loc, type, w, h, sill) if loc[:free]
      return add_free(loc.merge(free: true), type, w, h, sill) unless thickness(loc)

      add(loc, type, w, h, sill)
    end

    def add(loc, type, w, h, sill)
      spec = TYPES[type] or raise "Unknown opening type #{type}"
      w = [w.to_f, MIN_MM].max
      h = [h.to_f, MIN_MM].max
      sill = spec[:kind] == 'door' ? 0.0 : [sill.to_f, 0.0].max
      thk = thickness(loc)
      raise 'wall_thickness' unless thk

      zb = loc[:bottom] + sill.mm
      corners = rect_world(loc, w, h, zb)
      err = check_fit(loc, corners)
      raise err if err

      og = nil
      EGC.safe_op(loc[:model], "E.G.C #{spec[:en]}") do
        cut_hole(loc[:ents], loc[:tr], corners, thk, loc[:nw].reverse)
        og = loc[:ents].add_group
        og.name = "EGC_#{spec[:kind]}_#{type}_#{w.round}x#{h.round}"
        build_unit(og, type, w, h, thk.to_mm)
        world = Geom::Transformation.axes(corners[0], loc[:xw], loc[:nw].reverse, Geom::Vector3d.new(0, 0, 1))
        og.transformation = loc[:tr].inverse * world
        og.set_attribute(ATTR, 'opening', true)
        og.set_attribute(ATTR, 'otype', type)
        og.set_attribute(ATTR, 'kind', spec[:kind])
        og.set_attribute(ATTR, 'w', w)
        og.set_attribute(ATTR, 'h', h)
        og.set_attribute(ATTR, 'sill', sill)
        og.set_attribute(ATTR, 't', thk.to_mm)
        og.layer = Geo.tag(TAG)
      end
      og
    end

    FREE_THK = 120.0 # frame depth of a door / window that stands on its own (no wall to measure)

    # A door / window WITHOUT a wall: the framed unit alone, standing where it was clicked (on the ground, or against a face that has
    # no thickness to cut through). Nothing is cut. It is tagged like any other opening ('free' => true) and can be edited, moved, deleted.
    # loc: { p:, xw:, nw:, bottom:, model: } (world)
    def add_free(loc, type, w, h, sill)
      spec = TYPES[type] or raise "Unknown opening type #{type}"
      w = [w.to_f, MIN_MM].max
      h = [h.to_f, MIN_MM].max
      sill = spec[:kind] == 'door' ? 0.0 : [sill.to_f, 0.0].max
      corners = rect_world(loc, w, h, loc[:bottom] + sill.mm)
      og = nil
      EGC.safe_op(loc[:model], "E.G.C #{spec[:en]}") do
        og = loc[:model].entities.add_group
        og.name = "EGC_#{spec[:kind]}_#{type}_#{w.round}x#{h.round}"
        build_unit(og, type, w, h, FREE_THK)
        og.transformation = Geom::Transformation.axes(corners[0], loc[:xw], loc[:nw].reverse, Geom::Vector3d.new(0, 0, 1))
        { 'opening' => true, 'free' => true, 'otype' => type, 'kind' => spec[:kind], 'w' => w, 'h' => h, 'sill' => sill, 't' => FREE_THK }.each { |k, v| og.set_attribute(ATTR, k, v) }
        og.layer = Geo.tag(TAG)
      end
      og
    end

    def free?(og)
      og.get_attribute(ATTR, 'free') == true
    end

    # where a free-standing opening goes for a click on empty space: the point of the ground (z = 0) under the cursor, facing the
    # viewer, squared to the model axes
    def locate_free(view, x, y)
      ray = view.pickray(x, y)
      pt = Geom.intersect_line_plane(ray, [ORIGIN, Z_AXIS])
      return { error: 'no_wall' } unless pt && (pt - ray[0]).dot(ray[1]).positive? && pt.distance(ORIGIN) < 200_000.mm

      v = ray[1].reverse
      nw = v.x.abs >= v.y.abs ? Geom::Vector3d.new(v.x.positive? ? 1 : -1, 0, 0) : Geom::Vector3d.new(0, v.y.positive? ? 1 : -1, 0)
      { free: true, p: pt, nw: nw, xw: Z_AXIS.cross(nw).normalize, bottom: 0.0.mm, model: Sketchup.active_model }
    end

    # ------------------------------------------------------------------ validation of an EDIT (before anything is touched)
    # The opening group's own frame is in real millimetres (its transformation carries the container's rotation / scale / mirror), so the
    # request is validated in that frame: wall face bounds, overlap with the OTHER openings, depth/orientation. Nothing in the model is
    # changed until everything passed; a rejected request leaves the wall and the old opening exactly as they were.
    def host_face(og)
      tr = og.transformation
      nrm = tr.yaxis.normalize
      front, _back = hole_points(og)
      og.parent.entities.grep(Sketchup::Face).find do |f|
        f.normal.parallel?(nrm) && (f.vertices.first.position - tr.origin).dot(nrm).abs < 0.2.mm &&
          front.all? { |c| f.vertices.any? { |v| near?(v.position, c) } }
      end
    end

    def poly_contains?(poly, x, z)
      inside = false
      j = poly.size - 1
      poly.each_index do |i|
        xi, zi = poly[i]
        xj, zj = poly[j]
        inside = !inside if ((zi > z) != (zj > z)) && (x < (xj - xi) * (z - zi) / (zj - zi + 1e-12) + xi)
        j = i
      end
      inside
    end

    # rect = [x0, z0, w, h] in the opening's own frame (mm). Returns nil or an error code.
    def validate_rect(og, rect, skip_self: true)
      tr = og.transformation
      inv = tr.inverse
      face = host_face(og)
      return 'no_host_face' unless face

      to_local = ->(pt) { p = inv * pt; [p.x.to_mm, p.z.to_mm] }
      outer = face.outer_loop.vertices.map { |v| to_local.call(v.position) }
      old = params_of(og)
      x0, z0, w, h = rect
      pts = [[x0, z0], [x0 + w, z0], [x0 + w, z0 + h], [x0, z0 + h], [x0 + w / 2.0, z0], [x0 + w / 2.0, z0 + h], [x0, z0 + h / 2.0], [x0 + w, z0 + h / 2.0]]
      cx = x0 + w / 2.0
      cz = z0 + h / 2.0
      inside_old = ->(x, z) { skip_self && x >= -0.3 && x <= old['w'] + 0.3 && z >= -0.3 && z <= old['h'] + 0.3 }
      pts.each do |x, z|
        nx = x + (cx - x).clamp(-0.3, 0.3) # nudge toward the centre: a door standing on the wall's bottom edge is still inside
        nz = z + (cz - z).clamp(-0.3, 0.3)
        return 'outside' unless poly_contains?(outer, nx, nz) || inside_old.call(nx, nz)
      end
      # other openings (same wall): compared in mm in the frame of this opening
      og.parent.entities.grep(Sketchup::Group).each do |g|
        next unless opening?(g) && !g.equal?(og)

        gt = inv * g.transformation.origin
        next if gt.y.to_mm.abs > 600.0

        gx = g.transformation.xaxis.normalize.dot(tr.xaxis.normalize)
        next if gx.abs < 0.5 # a different wall

        w2 = g.get_attribute(ATTR, 'w').to_f
        h2 = g.get_attribute(ATTR, 'h').to_f
        ox0 = gx > 0 ? gt.x.to_mm : gt.x.to_mm - w2
        oz0 = gt.z.to_mm
        return 'overlap' if x0 < ox0 + w2 + MARGIN_MM && x0 + w > ox0 - MARGIN_MM && z0 < oz0 + h2 && z0 + h > oz0
      end
      nil
    end

    # Re-open + re-cut an existing opening with new parameters (resize / change type / shift on the wall).
    # dx_mm shifts along the wall (+ = to the right as seen from the room), sill_mm sets the sill height.
    def edit(og, type: nil, w: nil, h: nil, sill: nil, dx: 0.0)
      raise 'not_opening' unless opening?(og)

      old = params_of(og)
      type ||= old['type']
      spec = TYPES[type] or raise "Unknown opening type #{type}"
      w = [(w || old['w']).to_f, MIN_MM].max
      h = [(h || old['h']).to_f, MIN_MM].max
      sill = spec[:kind] == 'door' ? 0.0 : (sill || old['sill']).to_f
      if free?(og) # no wall behind it: only the unit itself is rebuilt, about its centre
        EGC.safe_op(Sketchup.active_model, 'E.G.C edit opening') do
          og.entities.to_a.each { |x| x.erase! if x.valid? }
          build_unit(og, type, w, h, old['t'])
          og.transformation = og.transformation * Geom::Transformation.translation(Geo.p3(dx.to_f + old['w'] / 2.0 - w / 2.0, 0, sill - old['sill']))
          { 'otype' => type, 'kind' => spec[:kind], 'w' => w, 'h' => h, 'sill' => sill }.each { |k, v| og.set_attribute(ATTR, k, v) }
          og.name = "EGC_#{spec[:kind]}_#{type}_#{w.round}x#{h.round}"
        end
        return og
      end
      model = Sketchup.active_model
      tr_old = og.transformation
      thk = old['t']
      # requested opening, in the opening's own (mm) frame: keep the centre, apply dx and the sill change
      ox = dx.to_f + old['w'] / 2.0 - w / 2.0
      oz = sill - old['sill']
      err = validate_rect(og, [ox, oz, w, h])
      raise err if err

      tr_new = tr_old * Geom::Transformation.translation(Geo.p3(ox, 0, oz)) # keeps rotation, scale and mirror of the container exactly
      ents = og.parent.entities
      EGC.safe_op(model, 'E.G.C edit opening') do
        fill_hole(og)
        front = [[0, 0], [w, 0], [w, h], [0, h]].map { |x, z| tr_new * Geo.p3(x, 0, z) }
        into = tr_new.yaxis # +y local = into the wall
        cut_hole(ents, Geom::Transformation.new, front, (tr_new * Geom::Vector3d.new(0, Geo.mm(thk), 0)).length.to_mm, into, exact: true)
        og.entities.to_a.each { |x| x.erase! if x.valid? }
        build_unit(og, type, w, h, thk)
        og.transformation = tr_new
        og.set_attribute(ATTR, 'otype', type)
        og.set_attribute(ATTR, 'kind', spec[:kind])
        og.set_attribute(ATTR, 'w', w)
        og.set_attribute(ATTR, 'h', h)
        og.set_attribute(ATTR, 'sill', sill)
        og.name = "EGC_#{spec[:kind]}_#{type}_#{w.round}x#{h.round}"
      end
      og
    end

    def remove(og)
      raise 'not_opening' unless opening?(og)

      EGC.safe_op(Sketchup.active_model, 'E.G.C remove opening') do
        fill_hole(og) unless free?(og)
        og.erase!
      end
      true
    end
  end

  # Click a wall to insert the chosen door / window; `move:` re-places an existing opening.
  class OpeningTool
    def initialize(type, w, h, sill, move: nil)
      @type = type
      @w = w.to_f
      @h = h.to_f
      @sill = sill.to_f
      @move = move
      @loc = nil
      @err = nil
    end

    def activate
      Sketchup.status_text = 'E.G.C: click a wall face to cut the opening into it - or click empty ground to stand the door / window on its own  |  Esc = cancel'
      App.enter_placement if defined?(App)
    end

    def deactivate(view)
      App.exit_placement if defined?(App)
      view.invalidate
    end

    def onCancel(_r, _v)
      Sketchup.active_model.select_tool(nil)
    end

    def preview(view, x, y)
      @loc = Openings.locate(view, x, y)
      @loc = Openings.locate_free(view, x, y) if @loc[:error] == 'no_wall' # nothing drawn under the cursor: the unit stands on its own
      @corners = nil
      @err = nil
      if @loc[:error]
        @err = @loc[:error]
        return
      end
      spec = Openings::TYPES[@type]
      sill = spec[:kind] == 'door' ? 0 : @sill
      @corners = Openings.rect_world(@loc, @w, @h, @loc[:bottom] + sill.mm)
      @err = @loc[:free] ? nil : Openings.check_fit(@loc, @corners, @move)
    end

    def onMouseMove(_f, x, y, view)
      preview(view, x, y)
      view.invalidate
    end

    def draw(view)
      return unless @corners

      view.drawing_color = @err ? Sketchup::Color.new(200, 60, 50) : Sketchup::Color.new(40, 150, 90)
      view.line_width = 3
      view.draw(GL_LINE_LOOP, @corners)
      if @err
        pt = view.screen_coords(@corners[2])
        view.draw_text(Geom::Point2d.new(pt.x + 10, pt.y), I18n.t("op_err_#{@err}", App.lang), { size: 12, bold: true, color: Sketchup::Color.new(200, 60, 50) }) rescue nil
      end
    end

    def onLButtonDown(_f, x, y, view)
      preview(view, x, y)
      if @err
        msg = I18n.t("op_err_#{@err}", App.lang)
        ::UI.messagebox(msg)
        return
      end
      last = @loc[:free] ? nil : @loc[:insts].last
      if last && last.definition.instances.size > 1 # cutting a shared definition would cut every copy
        Sketchup.active_model.start_operation('E.G.C make wall unique', true)
        last.make_unique
        Sketchup.active_model.commit_operation
        preview(view, x, y)
        return ::UI.messagebox(I18n.t("op_err_#{@err}", App.lang)) if @err
      end
      loc = @loc
      begin
        if @move
          Sketchup.active_model.start_operation('E.G.C move opening', true)
          params = Openings.params_of(@move)
          Openings.remove(@move) # merging the old hole away replaces faces: locate the wall again
          loc = Openings.locate(view, x, y)
          loc = Openings.locate_free(view, x, y) if loc[:error] == 'no_wall'
          raise loc[:error] if loc[:error]

          Openings.place(loc, @type, params['w'], params['h'], params['sill'])
          Sketchup.active_model.commit_operation
        else
          Openings.place(loc, @type, @w, @h, @sill)
        end
        Sketchup.active_model.select_tool(nil)
        App.notify('placed') if defined?(App)
      rescue StandardError => e
        Sketchup.active_model.abort_operation if @move
        ::UI.messagebox(I18n.t("op_err_#{e.message}", App.lang).sub(/^op_err_.*$/, e.message))
        Sketchup.active_model.select_tool(nil)
      end
    end
  end
end
