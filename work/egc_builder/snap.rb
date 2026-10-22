# frozen_string_literal: true

module EGC
  # Snap / align of E.G.C units, all in the unit's OWN axes (so it works after Rotate, on rotated runs, inside transformed groups):
  #   Snap.wall(unit)          - turn the unit so its back faces the wall in front of that back, then push it until the back touches it
  #   Snap.side(unit, :left)   - move the unit along its own X until it touches the nearest neighbour on that side (back planes flushed)
  # Walls are whatever the USER drew: the first face hit behind the back (E.G.C never builds walls). Nothing but the snapped unit moves.
  module Snap
    module_function

    MAX_YAW = 35.0   # deg: a unit turned more than this is not "almost parallel" to the wall - refuse instead of guessing
    MAX_SIDE_YAW = 2.0
    ATTR = 'egc'

    def unit?(g)
      g.is_a?(Sketchup::Group) && !!g.get_attribute(ATTR, 'spec')
    end

    def world_of(ent)
      tr = ent.transformation
      owner = Kitchen.find_owner_group(ent)
      while owner
        tr = owner.transformation * tr
        owner = Kitchen.find_owner_group(owner)
      end
      tr
    end

    def parent_world(ent)
      owner = Kitchen.find_owner_group(ent)
      owner ? world_of(owner) : Geom::Transformation.new
    end

    # apply a WORLD transformation to a unit that may live inside a transformed parent
    def move_world(unit, tw)
      pw = parent_world(unit)
      unit.transform!(pw.inverse * tw * pw)
    end

    def dims(unit)
      [unit.get_attribute(ATTR, 'w').to_f.mm, unit.get_attribute(ATTR, 'd').to_f.mm, unit.get_attribute(ATTR, 'h').to_f.mm]
    end

    # ------------------------------------------------------------------ back to wall
    def wall(unit)
      raise 'select an E.G.C unit' unless unit?(unit)

      model = Sketchup.active_model
      wg = world_of(unit)
      w, _d, h = dims(unit)
      p0 = wg * Geom::Point3d.new(w / 2.0, 0, h / 2.0)   # centre of the back plane
      b = wg.yaxis.normalize                            # local +y = toward the wall behind the unit
      b = Geom::Vector3d.new(b.x, b.y, 0).normalize
      hit = nil
      p = p0.offset(b, -5.mm)
      8.times do
        res = model.raytest([p, b], false)
        break unless res

        pt, path = res
        insts = (path || []).select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
        if insts.any? { |e| unit?(e) }                # ignore E.G.C units themselves (this one and neighbours)
          p = pt.offset(b, 1.mm)
          next
        end
        face = path.reverse.find { |e| e.is_a?(Sketchup::Face) }
        break unless face

        tr = Geom::Transformation.new
        insts.each { |i| tr *= i.transformation }
        n = (tr * face.normal).normalize
        hit = { pt: pt, n: Geom::Vector3d.new(n.x, n.y, 0).normalize } if n.z.abs < 0.3
        break
      end
      raise 'no wall found behind this unit' unless hit
      raise 'the wall face does not face the unit' if hit[:n].dot(b) > -0.2

      want = hit[:n].reverse
      ang = Math.atan2(b.cross(want).z, b.dot(want)) * 180.0 / Math::PI
      raise "the unit is turned #{ang.abs.round} deg from the wall - rotate it first" if ang.abs > MAX_YAW

      EGC.safe_op(model, 'E.G.C Snap to wall') do
        move_world(unit, Geom::Transformation.rotation(p0, Geom::Vector3d.new(0, 0, 1), ang.degrees)) unless ang.abs < 0.01
        wg2 = world_of(unit)
        p1 = wg2 * Geom::Point3d.new(w / 2.0, 0, h / 2.0)
        b2 = Geom::Vector3d.new(wg2.yaxis.x, wg2.yaxis.y, 0).normalize
        gap = (hit[:pt] - p1).dot(b2)
        move_world(unit, Geom::Transformation.translation(scaled(b2, gap))) if gap.abs > 0.01.mm
        Exposure.refresh(nil, model, own_op: false)
      end
      unit
    end

    # ------------------------------------------------------------------ side to neighbour
    def side(unit, dir)
      raise 'select an E.G.C unit' unless unit?(unit)

      model = Sketchup.active_model
      wg = world_of(unit)
      inv = wg.inverse
      w, d, h = dims(unit)
      others = (unit.parent.respond_to?(:entities) ? unit.parent.entities : model.entities).grep(Sketchup::Group).select { |g| g != unit && unit?(g) }
      cands = []
      others.each do |o|
        l = inv * world_of(o)                       # the neighbour in THIS unit's frame
        ox = l.xaxis.normalize
        yaw = Math.atan2(ox.y, ox.x) * 180.0 / Math::PI
        yaw -= 180.0 * (yaw.positive? ? 1 : -1) if yaw.abs > 90.0
        next if yaw.abs > MAX_SIDE_YAW               # not lined up with this unit: never guess

        ow, od, oh = dims(o)
        same = ox.x >= 0
        org = l.origin
        x0 = same ? org.x : org.x - ow
        ys = same ? [org.y - od, org.y] : [org.y, org.y + od]
        next if [ys.max, 0.0].min - [ys.min, -d].max < 50.mm                # depth overlap
        next if [org.z + oh, h].min - [org.z, 0.0].max < 50.mm               # height overlap

        cands << { o: o, x0: x0, x1: x0 + ow, same: same, back: org.y, z: org.z, h: oh, kind: o.get_attribute('egc', 'kind').to_s }
      end
      pick = if dir == :right
               cands.select { |c| (c[:x0] + c[:x1]) / 2.0 > w / 2.0 }.min_by { |c| c[:x0] }
             else
               cands.select { |c| (c[:x0] + c[:x1]) / 2.0 < w / 2.0 }.max_by { |c| c[:x1] }
             end
      raise 'no aligned neighbouring unit on that side (rotate / place it in line first)' unless pick

      shift = dir == :right ? pick[:x0] - w : pick[:x1]
      dy = pick[:same] ? pick[:back] : 0.0          # flush the back planes (same-way-round neighbours only, within 150 mm)
      EGC.safe_op(model, 'E.G.C Snap to neighbour') do
        v = Geom::Vector3d.new(0, 0, 0)
        v += scaled(wg.xaxis, shift) if shift.abs > 0.001.mm
        v += scaled(wg.yaxis, dy) if dy.abs > 0.5.mm && dy.abs < 150.mm
        # LEVEL: a neighbour of the same kind (upper beside upper, base beside base) is matched exactly in height too - bottoms flush when the two
        # are equally tall or stand on the floor, otherwise tops flush for hung units (one top line); only small errors (< 150 mm) are corrected
        if pick[:kind] == unit.get_attribute('egc', 'kind').to_s
          dz = (pick[:h] - h).abs < 1.mm || pick[:kind] != 'wall' ? pick[:z] : pick[:z] + pick[:h] - h
          v += scaled(wg.zaxis, dz) if dz.abs > 0.05.mm && dz.abs < 150.mm
        end
        move_world(unit, Geom::Transformation.translation(v)) if v.length > 0.01.mm
        Exposure.refresh(nil, model, own_op: false)
      end
      unit
    end

    # free run-space on each side, in the unit's own X (mm), for Replace's fit warning: how much the
    # new unit could grow before it would overlap the nearest ALIGNED neighbour. nil = no neighbour found.
    def neighbor_gaps(unit)
      return [nil, nil] unless unit?(unit)

      wg = world_of(unit)
      inv = wg.inverse
      w, d, h = dims(unit)
      others = (unit.parent.respond_to?(:entities) ? unit.parent.entities : Sketchup.active_model.entities).grep(Sketchup::Group).select { |g| g != unit && unit?(g) }
      cands = []
      others.each do |o|
        l = inv * world_of(o)
        ox = l.xaxis.normalize
        yaw = Math.atan2(ox.y, ox.x) * 180.0 / Math::PI
        yaw -= 180.0 * (yaw.positive? ? 1 : -1) if yaw.abs > 90.0
        next if yaw.abs > MAX_SIDE_YAW

        ow, od, oh = dims(o)
        same = ox.x >= 0
        org = l.origin
        x0 = same ? org.x : org.x - ow
        ys = same ? [org.y - od, org.y] : [org.y, org.y + od]
        next if [ys.max, 0.0].min - [ys.min, -d].max < 50.mm
        next if [org.z + oh, h].min - [org.z, 0.0].max < 50.mm

        cands << { x0: x0, x1: x0 + ow }
      end
      left = cands.select { |c| c[:x1] <= w / 2.0 }.map { |c| c[:x1] }.max
      right = cands.select { |c| c[:x0] >= w / 2.0 }.map { |c| c[:x0] }.min
      [left ? (0 - left).to_mm.round : nil, right ? (right - w).to_mm.round : nil]
    end

    def scaled(vec, len)
      u = vec.normalize
      Geom::Vector3d.new(u.x * len, u.y * len, u.z * len)
    end

    # ------------------------------------------------------------------ placing a NEW unit
    # Every unit standing in the model (also the ones inside a generated kitchen / run), with its world frame. Sizes in mm.
    def standing_units(model = Sketchup.active_model)
      out = []
      walk = lambda do |ents, tr|
        ents.grep(Sketchup::Group).each do |g|
          next unless g.valid?

          t = tr * g.transformation
          if unit?(g)
            out << { g: g, tr: t, w: g.get_attribute(ATTR, 'w').to_f, d: g.get_attribute(ATTR, 'd').to_f, h: g.get_attribute(ATTR, 'h').to_f, kind: g.get_attribute(ATTR, 'kind').to_s }
          elsif g.get_attribute(ATTR, 'kitchen') || g.get_attribute(ATTR, 'run')
            walk.call(g.entities, t)
          elsif g.get_attribute(ATTR, 'role').to_s == 'appliance' || g.get_attribute(ATTR, 'device')
            # an appliance (placed alone or standing in a slot of a kitchen): its box is read off its own geometry; a slot keeps its full slot width
            lb = g.entities.parent.bounds
            sw = g.get_attribute(ATTR, 'slot_w').to_f
            x0 = sw.positive? ? -g.get_attribute(ATTR, 'slot_inset_x').to_f : lb.min.x.to_mm
            ww = sw.positive? ? sw : lb.width.to_mm
            y0 = sw.positive? ? SLOT_BACK_GAP : 0.0 # a slot appliance stands SLOT_BACK_GAP in front of the back line of its row
            ta = t * Geom::Transformation.translation(Geom::Vector3d.new(x0.mm, y0.mm, 0))
            out << { g: g, tr: ta, w: ww, d: y0 - lb.min.y.to_mm, h: lb.max.z.to_mm, kind: t.origin.z.to_mm > 300 ? 'wall' : 'base' }
          end
        end
      end
      walk.call(model.entities, Geom::Transformation.new)
      out.select { |u| u[:w].positive? && u[:d].positive? && u[:h].positive? && u[:tr].zaxis.z > 0.999 }
    end

    SLOT_BACK_GAP = 10.0 # mm (Kitchen places slot appliances 10 mm off the back line)
    PLACE_REACH = 250.0 # mm: how far outside the snapped footprint the cursor may be

    # Where a NEW unit (nw x nd x nh mm, kind 'base' | 'wall' | 'tall') goes when the cursor is at world point pt:
    #   beside a unit of the same class - touching it exactly, backs on one line, same level (hung units of different heights: tops on one line);
    #   over / under a unit of the other class (an upper over a base unit) - backs on one line, left or right edges on one line, at its own height.
    # hang = the height a hung unit is placed at above the floor. Returns { tr:, how:, unit: } or nil (nothing near: free placement).
    def place_pose(units, pt, nw, nd, nh, nkind, hang = 0.0)
      ground = ->(k) { k != 'wall' }
      floor = units.select { |u| ground.call(u[:kind]) }.map { |u| u[:tr].origin.z.to_mm }.min
      best = nil
      units.each do |u|
        lp = u[:tr].inverse * pt
        lx = lp.x.to_mm
        ly = lp.y.to_mm
        uz = u[:tr].origin.z.to_mm
        same = ground.call(u[:kind]) == ground.call(nkind)
        if same
          zrel = ground.call(nkind) || (u[:h] - nh).abs < 1.0 ? 0.0 : u[:h] - nh
          xs = [[u[:w], :right], [-nw, :left]]
        else
          zrel = (floor || (ground.call(u[:kind]) ? uz : uz - hang)) + (ground.call(nkind) ? 0.0 : hang) - uz
          xs = [[0.0, :over_left], [u[:w] - nw, :over_right]].uniq { |x, _| x.round(1) }
        end
        # L-SHAPED CORNER UNIT: its second arm runs forward along one side. The next unit of the other run stands at the END of that arm, turned
        # 90 degrees with its back on the side wall - never beside the corner on the wall side, where the wall is.
        if same && (hand = corner_hand(u))
          left = hand == 'L'
          xs = xs.reject { |_, how| how == (left ? :left : :right) }
          tr2, ccx, ccy = corner_arm_pose(u, hand, nw, nd, zrel)
          dist = Math.hypot(lx - ccx, ly - ccy)
          if dist <= PLACE_REACH + [nw, nd].max / 2.0 && !(best && best[:score] <= dist)
            lg = l_gap
            best = { tr: tr2, how: :corner_arm, unit: u[:g], score: dist, filler: lg.positive? ? { x: left ? nw : -lg, w: lg } : nil } unless place_blocked?(units, tr2, nw, nd, nh)
          end
          # along the main wall the next unit stands l_gap (0: right against it) away from the corner unit
          if l_gap.positive?
            xs = xs.map { |x, how| [how == :right ? x + l_gap : x - l_gap, how, { x: how == :right ? -l_gap : nw, w: l_gap }] }
          end
        end
        # BLIND CORNER: the return run stands in front of the blind lane, turned a quarter turn, its side against the front of this unit and
        # its FRONTS one filler width (50 mm) past the edge of the door - the visible strip of the fixed filler that lets the door and the
        # first front of the return run open past each other.
        if same && ground.call(nkind) && ground.call(u[:kind]) && (bl = blind_edge(u))
          right, fe = bl
          bcx = right ? fe + corner_gap + nd / 2.0 : fe - corner_gap - nd / 2.0
          bcy = -(u[:d] + nw / 2.0)
          dist = Math.hypot(lx - bcx, ly - bcy)
          if dist <= PLACE_REACH + [nw, nd].max / 2.0 && !(best && best[:score] <= dist)
            rot = Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), (right ? -90 : 90).degrees)
            org = right ? Geom::Vector3d.new((fe + corner_gap + nd).mm, -u[:d].mm, zrel.mm) : Geom::Vector3d.new((fe - corner_gap - nd).mm, -(u[:d] + nw).mm, zrel.mm)
            tr3 = u[:tr] * Geom::Transformation.translation(org) * rot
            best = { tr: tr3, how: :blind_return, unit: u[:g], score: dist } unless place_blocked?(units, tr3, nw, nd, nh)
          end
        end
        xs.each do |x, how, fil|
          dx = [(lx - (x + nw / 2.0)).abs - nw / 2.0, 0.0].max
          dy = [(ly + nd / 2.0).abs - nd / 2.0, 0.0].max
          next if dx > [PLACE_REACH, u[:w] / 2.0 + 50.0].max || dy > PLACE_REACH # pointing at the unit itself counts: the nearer side wins

          score = Math.hypot(lx - (x + nw / 2.0), ly + nd / 2.0) + (same ? 0.0 : 120.0) # beside a unit of its own class wins a tie
          next if best && best[:score] <= score

          tr = u[:tr] * Geom::Transformation.translation(Geom::Vector3d.new(x.mm, 0, zrel.mm))
          next if place_blocked?(units, tr, nw, nd, nh)

          best = { tr: tr, how: how, unit: u[:g], score: score }
          best[:filler] = fil if fil
        end
      end
      best
    end

    def corner_gap
      Kitchen::CORNER_AUTO_FILLER
    end

    def l_gap
      Kitchen::CORNER_L_FILLER
    end

    # A unit with a BLIND lane (blind-corner fittings, the blind corner unit): the side its fixed filler is on and where that filler meets
    # the door, read off the built unit (unit frame, mm) -> [blind lane on the right?, x of the door-side edge of the filler] or nil
    def blind_edge(u)
      g = u[:g]
      return nil unless g && g.valid? && g.get_attribute(ATTR, 'spec').to_s =~ /"blind"|"mech":"(LEMANS|MAGIC_CORNER)/

      fl = g.entities.grep(Sketchup::Group).find { |x| x.get_attribute(ATTR, 'part').to_s == 'filler' }
      return nil unless fl

      f0 = fl.bounds.min.x.to_mm
      f1 = fl.bounds.max.x.to_mm
      raw = g.get_attribute(ATTR, 'spec').to_s
      strip = raw =~ /"blind_strip":[1-9]/ # the cover panel was left out (a unit stands in front): only the strip by the door is there
      return nil if !strip && f1 - f0 < corner_gap + 20.0

      right = strip ? raw !~ /"mech":"[A-Z_]+_L"/ : (u[:w] - f1) < f0
      [right, right ? f0 : f1]
    end

    # The place at the END of the second arm of an L-shaped corner unit, in the corner unit's OWN frame (so it is right however the corner
    # stands in the model): the new unit is turned a quarter turn relative to the corner, its back on the corner's side face, one side
    # touching the end of the arm. -> [world transformation, centre x, centre y (corner frame, mm)]
    def corner_arm_pose(u, hand, nw, nd, zrel)
      arm = u[:w]
      gap = l_gap # the same gap the kitchen generator leaves at the arm of an L corner unit (none since 1.28.48)
      left = hand == 'L'
      rot = Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), (left ? 90 : -90).degrees)
      org = left ? Geom::Vector3d.new(0, -(arm + gap + nw).mm, zrel.mm) : Geom::Vector3d.new(arm.mm, -(arm + gap).mm, zrel.mm)
      [u[:tr] * Geom::Transformation.translation(org) * rot, left ? nd / 2.0 : arm - nd / 2.0, -(arm + gap + nw / 2.0)]
    end

    # Why the cursor point is NOT a place for the new unit although it points at a corner unit - asked by the tool only when #place_pose
    # found nothing, so that it can refuse instead of dropping the unit loose at the cursor:
    #   :corner_wall_side - the side of the corner unit where the side wall is;
    #   :corner_no_room   - the end of its second arm is taken.
    # -> { how:, unit: } or nil (the cursor is not at a corner unit: free placement as before)
    def place_reject(units, pt, nw, nd, nh, nkind)
      ground = ->(k) { k != 'wall' }
      out = nil
      units.each do |u|
        next unless ground.call(u[:kind]) == ground.call(nkind) && (hand = corner_hand(u))

        lp = u[:tr].inverse * pt
        lx = lp.x.to_mm
        ly = lp.y.to_mm
        left = hand == 'L'
        zrel = ground.call(nkind) || (u[:h] - nh).abs < 1.0 ? 0.0 : u[:h] - nh
        tr2, ccx, ccy = corner_arm_pose(u, hand, nw, nd, zrel)
        dist = Math.hypot(lx - ccx, ly - ccy)
        if dist <= PLACE_REACH + [nw, nd].max / 2.0 && place_blocked?(units, tr2, nw, nd, nh) && (out.nil? || dist < out[:score])
          out = { how: :corner_no_room, unit: u[:g], score: dist }
        end
        x = left ? -nw : u[:w]
        dx = [(lx - (x + nw / 2.0)).abs - nw / 2.0, 0.0].max
        dy = [(ly + nd / 2.0).abs - nd / 2.0, 0.0].max
        score = Math.hypot(lx - (x + nw / 2.0), ly + nd / 2.0)
        out = { how: :corner_wall_side, unit: u[:g], score: score } if dx <= [PLACE_REACH, u[:w] / 2.0 + 50.0].max && dy <= PLACE_REACH && (out.nil? || score < out[:score])
      end
      out
    end

    REJECT_TEXT = {
      corner_wall_side: 'E.G.C: this side of the corner unit is the wall - point at the end of its other arm or along the main wall  |  هذه الجهة من وحدة الزاوية هي الحائط - أشر عند نهاية الضلع الآخر أو بجوارها على الحائط الرئيسي',
      corner_no_room: 'E.G.C: no room at the end of the corner unit here - a unit already stands there  |  لا يوجد مكان عند نهاية ضلع وحدة الزاوية - توجد وحدة هناك'
    }.freeze

    # 'L' / 'R' when the unit is an L-shaped corner unit (which side its second arm is on), else nil
    def corner_hand(u)
      g = u[:g]
      return nil unless g && g.valid? && u[:w] > 700

      raw = g.get_attribute('egc', 'spec').to_s
      return nil unless raw.include?('"corner":true')

      raw =~ /"hand":"R"/ ? 'R' : 'L'
    end

    # the new unit would stand inside a unit that is already there
    def place_blocked?(units, tr, nw, nd, nh)
      inv = tr.inverse
      units.any? do |o|
        l = inv * o[:tr]
        bb = Geom::BoundingBox.new
        [0, o[:w]].each { |x| [0, -o[:d]].each { |y| [0, o[:h]].each { |z| bb.add(l * Geom::Point3d.new(x.mm, y.mm, z.mm)) } } }
        ox = [bb.max.x.to_mm, nw].min - [bb.min.x.to_mm, 0.0].max
        oy = [bb.max.y.to_mm, 0.0].min - [bb.min.y.to_mm, -nd].max
        oz = [bb.max.z.to_mm, nh].min - [bb.min.z.to_mm, 0.0].max
        ox > 2.0 && oy > 2.0 && oz > 2.0
      end
    end

    # back against a wall face the cursor is on: n = the outward normal of that face (world). The unit is centred on the cursor along the wall.
    def wall_pose(pt, n, nw, z)
      return nil if n.z.abs > 0.3

      y = Geom::Vector3d.new(-n.x, -n.y, 0).normalize
      x = y * Geom::Vector3d.new(0, 0, 1)
      o = Geom::Point3d.new(pt.x, pt.y, z.mm).offset(x, -(nw / 2.0).mm)
      Geom::Transformation.axes(o, x, y, Geom::Vector3d.new(0, 0, 1))
    end
  end
end
