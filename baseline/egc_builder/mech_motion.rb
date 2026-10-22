# frozen_string_literal: true

module EGC
  # Shared motion profiles. A moving assembly stores an 'egc/move' JSON; this file knows how to turn it into a
  # transformation for t in 0..1 (all coordinates are builder space: x along the wall, d toward the room, z up).
  #   lin     { v:[dx,dd,dz] }                       straight slide
  #   rot     { pivot, axis, deg }                   hinge / pivot rotation
  #   rotlin  { pivot, axis, deg, v }                rotation + translation together (swing-out)
  #   seq     { steps:[move,...] }                   staged compound motion: each step carries its own 'phase';
  #                                                  result = step0 * step1 * ... (last step is applied first)
  #   pose    { pivot, axis, keys:[[t,dd,dz,deg]] } planar rigid motion sampled from a solved linkage (arms)
  # Every move accepts optional 'phase' => [t0, t1].
  module Mechanisms
    class << self
      def move_transform(m, t)
        return seq_transform(m, t) if m['type'] == 'seq'

        tt = phase(m, t)
        case m['type']
        when 'lin' then lin_tr(m['v'], tt)
        when 'rotlin' then lin_tr(m['v'], tt) * rot_tr(m, tt)
        when 'pose' then pose_tr(m, tt)
        when 'hinge_arm' then hinge_arm_tr(m, tt)
        when 'hinge_ik' then hinge_ik_tr(m, tt)
        else rot_tr(m, tt)
        end
      end

      # The arm geometry is authored in a CANONICAL local frame: origin (0,0,0) at the plate pivot, pointing
      # along local +x, length m['len0'] (the real closed-pose plate-to-cup distance). Every frame it is
      # re-aimed + re-scaled so its far end (local x = len0) lands exactly on the cup's CURRENT position -
      # the cup itself swings with the door (same pivot/axis/deg the door's own 'rot' spec uses, duplicated
      # here as dpivot/daxis/ddeg) - so the two hinge halves never visibly separate at any point in the
      # opening, unlike a rigid copy of the door's own rotation (which would swing the arm's far end away
      # from the fixed plate). Not identity at t=0 (unlike every other move type here), so the caller poses
      # the group once at build time too (Cabinet#door_plates).
      def hinge_arm_tr(m, tt)
        plate = Geo.p3(*m['plate'])
        cup0 = Geo.p3(*m['cup'])
        door_t = Geom::Transformation.rotation(Geo.p3(*m['dpivot']), Geom::Vector3d.new(m['daxis'][0], -m['daxis'][1], m['daxis'][2]),
                                                (m['ddeg'].to_f * tt).degrees)
        cup_now = door_t * cup0
        vtx, vty = (cup_now.x - plate.x).to_mm, (cup_now.y - plate.y).to_mm
        theta = Math.atan2(vty, vtx) * 180.0 / Math::PI
        s = Math.hypot(vtx, vty) / m['len0'].to_f
        pv = Geom::Vector3d.new(plate.x, plate.y, plate.z)
        Geom::Transformation.translation(pv) *
          Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), theta.degrees) *
          Geom::Transformation.scaling(s)
      end

      # Two articulated hinge links with CONSTANT lengths (no scaling): link 0 pivots on the fixed plate, link 1
      # on the cup clevis (which swings with the door). The elbow is solved every frame in the plan plane by
      # MotionProfiles.two_link, so the pair always spans plate -> cup. Each link is authored along local +x.
      def hinge_ik_tr(m, tt)
        plate = Geo.p3(*m['plate'])
        cup0 = Geo.p3(*m['cup'])
        door_t = if m['dslide'] # the door is drawn back while it turns (concealed hinge): the arm follows the cup there too
                   rot_tr({ 'pivot' => m['dpivot'], 'axis' => m['daxis'], 'deg' => m['ddeg'], 'slide' => m['dslide'] }, tt)
                 else
                   Geom::Transformation.rotation(Geo.p3(*m['dpivot']), Geom::Vector3d.new(m['daxis'][0], -m['daxis'][1], m['daxis'][2]),
                                                 (m['ddeg'].to_f * tt).degrees)
                 end
        cup = door_t * cup0
        s = [plate.x.to_mm, plate.y.to_mm]
        a = [cup.x.to_mm, cup.y.to_mm]
        l1 = m['l1'].to_f
        l2 = m['l2'].to_f
        el = MotionProfiles.two_link(s, a, l1, l2, m['side'].to_f)
        unless el
          dist = Math.hypot(a[0] - s[0], a[1] - s[1])
          k = [l1, dist].min / dist
          el = [s[0] + (a[0] - s[0]) * k, s[1] + (a[1] - s[1]) * k]
        end
        from, to = m['link'].to_i.zero? ? [s, el] : [el, a]
        theta = Math.atan2(to[1] - from[1], to[0] - from[0]) * 180.0 / Math::PI
        Geom::Transformation.translation(Geom::Vector3d.new(from[0].mm, from[1].mm, plate.z)) *
          Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), theta.degrees)
      end

      def lin_tr(v, tt)
        Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(v[0] * tt), -Geo.mm(v[1] * tt), Geo.mm(v[2] * tt)))
      end

      def rot_tr(m, tt)
        pv = m['pivot']
        ax = m['axis']
        r = Geom::Transformation.rotation(Geo.p3(pv[0], pv[1], pv[2]), Geom::Vector3d.new(ax[0], -ax[1], ax[2]), (m['deg'].to_f * tt).degrees)
        # CONCEALED-HINGE DOOR: the pivot is not fixed. While the door turns it is drawn back toward the carcass ('slide', mm in x / depth / z,
        # reached at 90 degrees and growing as 1 - cos(angle)), so the open door ends close to the carcass front instead of a board thickness
        # away from it - and its inner corner never cuts the carcass edge on the way.
        s = m['slide']
        return r unless s

        k = 1.0 - Math.cos((m['deg'].to_f * tt).degrees)
        Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(s[0] * k), -Geo.mm(s[1] * k), Geo.mm(s[2] * k))) * r
      end

      def seq_transform(m, t)
        m['steps'].map { |s| move_transform(s, t) }.reduce { |a, b| a * b }
      end

      def pose_tr(m, tt)
        keys = m['keys']
        a = keys.first
        b = keys.last
        keys.each_cons(2) do |k0, k1|
          next unless tt >= k0[0] && tt <= k1[0]

          a = k0
          b = k1
          break
        end
        f = b[0] == a[0] ? 0.0 : (tt - a[0]) / (b[0] - a[0])
        f = [[f, 0.0].max, 1.0].min
        dd = a[1] + (b[1] - a[1]) * f
        dz = a[2] + (b[2] - a[2]) * f
        deg = a[3] + (b[3] - a[3]) * f
        pv = m['pivot']
        ax = m['axis'] || [1, 0, 0]
        # plane 'xd' (top view): keys are [t, dx, dd, deg] and the rotation is about the vertical axis
        tv = m['plane'] == 'xd' ? Geom::Vector3d.new(Geo.mm(dd), -Geo.mm(dz), 0) : Geom::Vector3d.new(0, -Geo.mm(dd), Geo.mm(dz))
        Geom::Transformation.translation(tv) *
          Geom::Transformation.rotation(Geo.p3(pv[0], pv[1], pv[2]), Geom::Vector3d.new(ax[0], -ax[1], ax[2]), deg.degrees)
      end
    end
  end

  # Named profiles: each returns the move hash (or a list of them) that a family binds to its moving parts.
  module MotionProfiles
    module_function

    NAMES = %w[LINEAR_SLIDE TELESCOPIC_SLIDE HINGE_ROTATE LIFT FOLD_LIFT ROTATE SWING_OUT CORNER_COMPOUND].freeze

    def linear_slide(v, phase = nil)
      mv = { 'type' => 'lin', 'v' => v }
      mv['phase'] = phase if phase
      mv
    end

    # -> [mid_stage_move, moving_member_move] (the mid stage of a 3-part slide runs at half speed)
    def telescopic_slide(travel, phase = nil)
      [linear_slide([0, travel * 0.5, 0], phase), linear_slide([0, travel, 0], phase)]
    end

    def hinge_rotate(pivot, deg, phase = nil, axis = [0, 0, 1])
      mv = { 'type' => 'rot', 'pivot' => pivot, 'axis' => axis, 'deg' => deg }
      mv['phase'] = phase if phase
      mv
    end

    # top-hinged flap (positive deg opens up and back)
    def lift(pivot, deg, phase = nil)
      hinge_rotate(pivot, deg, phase, [1, 0, 0])
    end

    def rotate(pivot, deg, phase = nil)
      hinge_rotate(pivot, deg, phase, [0, 0, 1])
    end

    def swing_out(pivot, deg, v, phase = nil)
      mv = { 'type' => 'rotlin', 'pivot' => pivot, 'axis' => [0, 0, 1], 'deg' => deg, 'v' => v }
      mv['phase'] = phase if phase
      mv
    end

    # staged steps, each { move + 'phase' }
    def compound(*steps)
      { 'type' => 'seq', 'steps' => steps }
    end

    # planar keyframed pose (arms of a solved linkage)
    def pose(pivot, keys)
      { 'type' => 'pose', 'pivot' => pivot, 'axis' => [1, 0, 0], 'keys' => keys }
    end

    # top-view planar rigid motion (rotation about the vertical axis + translation in x/d): keys [t, dx, dd, deg(CCW seen from above)]
    def pose_xd(pivot, keys)
      { 'type' => 'pose', 'plane' => 'xd', 'pivot' => pivot, 'axis' => [0, 0, 1], 'keys' => keys }
    end

    # ---- 2-D kinematics in the (d,z) plane, matching the 'rot' move convention about builder +x ---------------
    # a positive angle turns (dd,dz) -> (dd cos + dz sin, -dd sin + dz cos): a flap hanging below its pivot swings up and back.
    def rot2(p, c, deg)
      th = deg * Math::PI / 180.0
      dx = p[0] - c[0]
      dz = p[1] - c[1]
      [c[0] + dx * Math.cos(th) + dz * Math.sin(th), c[1] - dx * Math.sin(th) + dz * Math.cos(th)]
    end

    def angle_deg(v)
      Math.atan2(v[1], v[0]) * 180.0 / Math::PI
    end

    # elbow of a two-link arm from s to a (link lengths l1, l2); side = +1 / -1 picks the bend direction
    def two_link(s, a, l1, l2, side)
      dx = a[0] - s[0]
      dz = a[1] - s[1]
      dist = Math.hypot(dx, dz)
      return nil if dist > l1 + l2 - 0.5 || dist < (l1 - l2).abs + 0.5 || dist < 1e-6

      aa = (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
      h = Math.sqrt([l1 * l1 - aa * aa, 0.0].max)
      mx = s[0] + aa * dx / dist
      mz = s[1] + aa * dz / dist
      [mx - side * h * dz / dist, mz + side * h * dx / dist]
    end
  end
end
