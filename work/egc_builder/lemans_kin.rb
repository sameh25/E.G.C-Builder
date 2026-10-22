# frozen_string_literal: true

module EGC
  # Plan-view kinematics of the blind-corner swing-out trays (LeMans II type). Pure Ruby - no SketchUp calls - so it is unit-tested on its own.
  #
  # VERIFIED (supplier planning sheet / product pages, Kesseboehmer LeMans II at Hanimex): the per-variant figures in VARIANTS.
  # NOT VERIFIED: the outline of the tray, the length of the swing arm, where it holds the tray and how the fitting couples the turn of
  # the tray to the turn of the arm. Here each tray hangs on ONE swing arm that turns about the column; the tray turns on the pivot at the
  # end of that arm. The pivot is placed so that the tray goes exactly from the stored position to the published swung-out position, and
  # the turn of the tray along the way is the route found to clear everything (checked along the whole path). It is a consistent,
  # collision-free mechanism - it is not the manufacturer's linkage: LINKAGE_STATUS says so and the model carries that label.
  #
  # Canonical frame: x across the carcass (0 = outer face of the gable on the OPENING side), d from the back (0) to the front, blind lane
  # at high x. Angles are counter-clockwise in (x, d). The left-hand unit is this frame mirrored in x by the builder.
  module LemansKin
    module_function

    LINKAGE_STATUS = 'REFERENCE REQUIRED'
    VARIANTS = {
      # door width 600: planning table A>=960 B>=500 C=561-568 D=16-19 H=600-900, plan view 1000 unit / 85 deg / 706 out / 270-330 sideways
      '600' => { door: 600.0, unit: 1000.0, inner_min: 960.0, depth_min: 500.0, opening: [561.0, 568.0], side: [16.0, 19.0],
                 height: [600.0, 900.0], out_front: 706.0, out_side: [270.0, 330.0], swing: 85.0, load_kg: 25,
                 axle_x: 626.0, axle_back: 53.0, rail_back: 52.0, rail_first: 28.0, rail_pitch: 64.0,
                 footprint: 'SUPPLIER PLAN VIEW', buildable: true }.freeze,
      # door width 450: product page - 900 unit, opening >= 418, inside depth >= 500, inside height 600-750. No plan view is published
      # for it (tray outline, swung-out footprint): it is NOT built from the 600 drawing - the variant stays REFERENCE REQUIRED.
      '450' => { door: 450.0, unit: 900.0, inner_min: nil, depth_min: 500.0, opening: [418.0, 425.0], side: [16.0, 19.0],
                 height: [600.0, 750.0], out_front: nil, out_side: nil, swing: 85.0, load_kg: 25,
                 footprint: 'REFERENCE REQUIRED', buildable: false }.freeze
    }.freeze
    COLUMN_R = 13.0
    STEPS = 48
    GRID_DEG = 5.0
    MARGINS = [14.0, 9.0, 5.0].freeze
    TRAY_TURN = -37.0 # stored -> swung out, read off the supplier plan view (not a published number)

    def variant(key)
      VARIANTS[key.to_s] or raise ArgumentError, "unknown LeMans variant #{key.inspect}"
    end

    # clear opening this carcass gives the variant (door width less the gable and the hinge-side allowance), nil when out of its range
    def opening_for(key, t)
      v = variant(key)
      c = v[:door] - 2 * t # the gable and the post, both of the carcass thickness (planning table: 568 at 16, 561-562 at 19)
      c.between?(v[:opening][0] - 0.01, v[:opening][1] + 0.01) ? c : nil
    end

    def inner_min(key, t)
      v = variant(key)
      v[:inner_min] || (v[:unit] - 2 * t)
    end

    # ---- small 2-D helpers -----------------------------------------------------------------------------------------------------
    def rot(p, deg)
      a = deg * Math::PI / 180.0
      [p[0] * Math.cos(a) - p[1] * Math.sin(a), p[0] * Math.sin(a) + p[1] * Math.cos(a)]
    end

    # pose = [deg, tx, td]: p -> R(deg) p + t
    def apply(pose, p)
      r = rot(p, pose[0])
      [r[0] + pose[1], r[1] + pose[2]]
    end

    def unapply(pose, q)
      rot([q[0] - pose[1], q[1] - pose[2]], -pose[0])
    end

    def dist(a, b)
      Math.hypot(a[0] - b[0], a[1] - b[1])
    end

    def seg_dist(p, a, b)
      vx = b[0] - a[0]
      vd = b[1] - a[1]
      l2 = vx * vx + vd * vd
      u = l2 < 1e-9 ? 0.0 : (((p[0] - a[0]) * vx + (p[1] - a[1]) * vd) / l2).clamp(0.0, 1.0)
      Math.hypot(p[0] - a[0] - u * vx, p[1] - a[1] - u * vd)
    end

    def inside?(poly, p)
      c = false
      j = poly.size - 1
      poly.each_index do |i|
        a = poly[i]
        b = poly[j]
        c = !c if ((a[1] > p[1]) != (b[1] > p[1])) && (p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0])
        j = i
      end
      c
    end

    def densify(poly, step = 12.0)
      out = []
      poly.each_index do |i|
        a = poly[i]
        b = poly[(i + 1) % poly.size]
        n = [(dist(a, b) / step).ceil, 1].max
        n.times { |k| out << [a[0] + (b[0] - a[0]) * k / n.to_f, a[1] + (b[1] - a[1]) * k / n.to_f] }
      end
      out
    end

    # ---- tray outline (stored) ---------------------------------------------------------------------------------------------------
    # Traced from the supplier plan view of the 600 variant (a drawing without tray dimensions): [across, depth] as fractions of the
    # reference carcass inside (across: 0 = blind gable, 1 = opening gable; depth: 0 = back, 1 = front). TRACE_POST is where the
    # opening ends in that drawing. The tray is sized from the variant's REFERENCE carcass - it does not stretch with a bigger unit.
    TRACE = [[0.022, 0.524], [0.040, 0.321], [0.108, 0.187], [0.254, 0.074], [0.707, 0.074], [0.841, 0.164], [0.939, 0.366], [0.982, 0.636],
             [0.982, 0.906], [0.951, 0.962], [0.853, 0.939], [0.682, 0.917], [0.560, 0.906], [0.517, 0.872], [0.487, 0.793], [0.450, 0.703],
             [0.413, 0.692], [0.352, 0.748], [0.267, 0.804], [0.193, 0.816], [0.108, 0.782], [0.053, 0.726]].freeze
    TRACE_POST = 0.411
    OUTLINE_STATUS = 'TRACED FROM THE SUPPLIER PLAN VIEW - NOT DIMENSIONED'

    # g: { xi0:, xi1: inner faces of the gables (xi0 = opening side), db: inner face of the back, cd: carcass front, ft:, t:,
    #      edge: opening/post boundary, post_w:, hx: hinge edge of the door, dw: door width, col: [x, d] column axis, variant: }
    def outline(g)
      v = variant(g[:variant])
      wr = inner_min(g[:variant], g[:t])
      dr = v[:depth_min]
      fo = (g[:edge] - g[:xi0]) / wr
      pts = TRACE.map do |xn, dn|
        across = xn >= TRACE_POST ? 1.0 - (1.0 - xn) / (1.0 - TRACE_POST) * fo : (1.0 - fo) * xn / TRACE_POST
        [g[:xi0] + (1.0 - across) * wr, g[:cd] - (1.0 - dn) * dr]
      end
      2.times do # round the corners of the traced polygon
        pts = pts.each_index.flat_map do |i|
          p = pts[i]
          q = pts[(i + 1) % pts.size]
          [[p[0] * 0.75 + q[0] * 0.25, p[1] * 0.75 + q[1] * 0.25], [p[0] * 0.25 + q[0] * 0.75, p[1] * 0.25 + q[1] * 0.75]]
        end
      end
      area = 0.0
      pts.each_index { |i| q = pts[(i + 1) % pts.size]; area += pts[i][0] * q[1] - q[0] * pts[i][1] }
      pts.reverse! if area.negative? # counter-clockwise in (x, d)
      { pts: pts, ref_w: wr, ref_d: dr }
    end

    def bbox(pts)
      xs = pts.map(&:first)
      ds = pts.map(&:last)
      [xs.min, xs.max, ds.min, ds.max]
    end

    # door leaf as built: closed it lies along the front from the hinge edge towards the opening side; open it stands forward of the hinge
    def door_segment(g, deg)
      a = [g[:hx], g[:cd] + g[:ft] / 2.0]
      piv = [g[:hx], g[:cd] + g[:ft]]
      tip = [g[:hx] - g[:dw], g[:cd] + g[:ft] / 2.0]
      turn = ->(p) { r = rot([p[0] - piv[0], p[1] - piv[1]], -deg); [r[0] + piv[0], r[1] + piv[1]] }
      [turn.call(a), turn.call(tip)]
    end

    # ---- interference: carcass (gables, back), post + blind filler + the return run in front of the blind lane, the cabinet beside the
    # opening, the open door and the column. -> nil when clear by at least m, else the name of what is hit
    def hit(g, world_pts, m, door)
      xl = g[:xi0] + m
      xr = g[:xi1] - m
      front = g[:cd] + g[:ft] + m
      post_d = g[:cd] - g[:post_w] - m
      world_pts.each do |x, d|
        return :back if d < g[:db] + m
        return :blind_gable if x > xr && d < g[:cd] + m
        return :opening_gable_or_neighbour if x < xl && d < front
        return :post if x > g[:edge] - m && x < g[:edge] + g[:t] + m && d > post_d
        return :filler_or_return_run if x > g[:edge] - m && d > g[:cd] - m
        return :door if seg_dist([x, d], door[0], door[1]) < g[:ft] / 2.0 + m
        return :column if columns(g).any? { |c, r| dist([x, d], c) < r + m }
      end
      nil
    end

    # fixed fittings standing in the carcass: [[axis, radius]...]
    def columns(g)
      g[:cols] || [[g[:col], COLUMN_R]]
    end

    def hit_pose(g, tray, pose, m, door)
      poly = tray.map { |p| apply(pose, p) }
      h = hit(g, densify(poly), m, door)
      return h if h

      probes = { column: columns(g).map(&:first), post: [[g[:edge], g[:cd] - g[:post_w]], [g[:edge] + g[:t], g[:cd] - g[:post_w]]], filler_or_return_run: [[g[:edge] + 40.0, g[:cd] + 60.0]],
                 opening_gable_or_neighbour: [[g[:xi0], g[:cd] + g[:ft]]],
                 door: (0..6).map { |i| [door[0][0] + (door[1][0] - door[0][0]) * i / 6.0, door[0][1] + (door[1][1] - door[0][1]) * i / 6.0] } }
      probes.each { |name, ps| return name if ps.any? { |p| inside?(poly, p) } }
      nil
    end

    # ---- where the tray ends up ----------------------------------------------------------------------------------------------------
    # Turned as in the supplier plan view, then pushed out so that it stands the published distance in front of the cabinet (706 for the
    # 600) and past its side by a value inside the published range (270-330) - the value of that range and the turn (within a few
    # degrees of the drawing) that leave the most room at the cabinet corner and at the open door.
    def deployed_pose(g, tray, door = nil)
      v = variant(g[:variant])
      door ||= door_segment(g, v[:swing])
      return nil unless v[:out_front]

      front = v[:out_front]
      sides = v[:out_side]
      face = g[:cd] + g[:ft]
      MARGINS.each do |m|
        [0.0, -3.0, 3.0, -6.0, 6.0].each do |dt|
          (0..6).each do |i|
            side = sides[0] + (sides[1] - sides[0]) * [3, 2, 4, 1, 5, 0, 6][i] / 6.0
            turned = tray.map { |p| rot(p, TRAY_TURN + dt) }
            bx = bbox(turned)
            pose = [TRAY_TURN + dt, -side - bx[0], face + front - bx[3]]
            return pose unless hit_pose(g, tray, pose, m, door)
          end
        end
      end
      nil
    end

    # coupler points that stay at one distance from the fixed pivot gp in BOTH end positions: a straight line in the tray (two-position
    # synthesis) -> [point, direction]
    def coupler_line(gp, dep)
      g2 = unapply(dep, gp)
      mid = [(gp[0] + g2[0]) / 2.0, (gp[1] + g2[1]) / 2.0]
      l = dist(gp, g2)
      [mid, [-(g2[1] - gp[1]) / l, (g2[0] - gp[0]) / l]]
    end

    def arm_pose(ga, la, e, alpha, theta)
      r = rot(e, theta)
      [theta, ga[0] + la * Math.cos(alpha) - r[0], ga[1] + la * Math.sin(alpha) - r[1]]
    end

    # a clear way from (stored) to (swung out) for one arm: straight in (arm angle, tray angle) when that is clear, otherwise the shortest
    # clear route over a grid, straightened afterwards. -> [[alpha, theta]...] way-points or nil
    def route(g, tray, door, ga, la, e, a0, da, turn, m)
      free = {}
      clear = lambda do |al, th|
        k = [(al * 1e4).round, (th * 100).round]
        free.fetch(k) { free[k] = hit_pose(g, tray, arm_pose(ga, la, e, al, th), m, door).nil? }
      end
      line = lambda do |p, q|
        n = [((q[1] - p[1]).abs / 2.5).ceil, ((q[0] - p[0]).abs / 0.04).ceil, 1].max
        (0..n).all? { |i| clear.call(p[0] + (q[0] - p[0]) * i / n.to_f, p[1] + (q[1] - p[1]) * i / n.to_f) }
      end
      s = [a0, 0.0]
      t = [a0 + da, turn]
      return nil unless clear.call(*s) && clear.call(*t)
      return [s, t] if line.call(s, t)

      na = 36
      th0 = -(([0.0, -turn].max + 50.0) / GRID_DEG).ceil * GRID_DEG
      nt = ((turn.abs + 100.0) / GRID_DEG).ceil + 1
      node = ->(i, j) { j > nt ? t : [a0 + da * i / na.to_f, th0 + j * GRID_DEG] } # the extra row holds the exact end position
      start = [0, (-th0 / GRID_DEG).round]
      goal = [na, nt + 1]
      came = { start => nil }
      cost = { start => 0.0 }
      open = [start]
      until open.empty?
        cur = open.min_by { |n| cost[n] + [(goal[0] - n[0]).abs, (goal[1] - n[1]).abs].max }
        break if cur == goal

        open.delete(cur)
        [-1, 0, 1].product([-1, 0, 1]).each do |di, dj|
          nx = [cur[0] + di, cur[1] + dj]
          next if (di.zero? && dj.zero?) || !nx[0].between?(0, na) || !nx[1].between?(0, nt)

          nx = goal if nx[0] == na && (node.call(*nx)[1] - t[1]).abs <= GRID_DEG

          c = cost[cur] + Math.hypot(di, dj) + (di.negative? ? 0.5 : 0.0)
          next if cost[nx] && cost[nx] <= c
          next unless clear.call(*node.call(*nx))

          cost[nx] = c
          came[nx] = cur
          open << nx unless open.include?(nx)
        end
      end
      return nil unless came.key?(goal)

      path = [goal]
      path.unshift(came[path.first]) while came[path.first]
      pts = path.map { |n| node.call(*n) }
      out = [pts.first]
      i = 0
      while i < pts.size - 1
        j = pts.size - 1
        j -= 1 while j > i + 1 && !line.call(pts[i], pts[j])
        return nil unless line.call(pts[i], pts[j])

        out << pts[j]
        i = j
      end
      out
    end

    # way-points -> STEPS + 1 evenly spaced configurations (corners rounded by sampling, each sample re-checked by the caller)
    def resample(way)
      w = ->(p, q) { Math.hypot((q[0] - p[0]) * 180.0 / Math::PI, q[1] - p[1]) }
      lens = way.each_cons(2).map { |p, q| w.call(p, q) }
      total = lens.sum
      (0..STEPS).map do |k|
        s = total * k / STEPS.to_f
        i = 0
        while i < lens.size - 1 && s > lens[i]
          s -= lens[i]
          i += 1
        end
        u = lens[i] < 1e-9 ? 0.0 : [s / lens[i], 1.0].min
        [way[i][0] + (way[i + 1][0] - way[i][0]) * u, way[i][1] + (way[i + 1][1] - way[i][1]) * u]
      end
    end

    # moving average over the route, end positions kept
    def smooth(cfgs, win)
      n = cfgs.size
      (0...n).map do |i|
        h = [win / 2, i, n - 1 - i].min
        seg = cfgs[(i - h)..(i + h)]
        [seg.sum { |c| c[0] } / seg.size, seg.sum { |c| c[1] } / seg.size]
      end
    end

    # ---- one solution per fitting, reused ---------------------------------------------------------------------------------------
    # The tray is sized from the variant's REFERENCE carcass and everything it meets on its way (opening, post, door, bearings) sits
    # at fixed distances from the opening-side gable and the carcass front. So the path is solved ONCE in a reference carcass (front
    # at REF_CD, the planning-table inside width and depth) and moved to the real one; a wider / deeper carcass only takes the back
    # and the blind gable further away. The solutions for the usual boards are shipped (lemans_table.json, made by
    # tools/gen_lemans_table.rb), so placing the unit does not search at all; any other board is searched once per session.
    REF_CD = 1000.0

    def ref_geometry(g)
      v = variant(g[:variant])
      g.merge(xi1: g[:xi0] + inner_min(g[:variant], g[:t]), cd: REF_CD, db: REF_CD - v[:depth_min], col: [g[:col][0], g[:col][1] - g[:cd] + REF_CD])
    end

    def ref_key(g)
      ([g[:variant]] + [g[:xi0], g[:t], g[:ft], g[:edge], g[:post_w], g[:hx], g[:dw], g[:col][0], g[:cd] - g[:col][1]].map { |q| q.round(2) }).join('|')
    end

    def table
      @table ||= begin
        require 'json'
        p = File.join(File.dirname(__FILE__), 'lemans_table.json')
        File.file?(p) ? JSON.parse(File.read(p)) : {}
      rescue StandardError
        {}
      end
    end

    TABLE_KEYS = %i[tray deployed door ga gb cols poses arm arm_b pa pb la lb clear overturn crank_b].freeze

    def freeze_result(r)
      TABLE_KEYS.to_h { |k| [k.to_s, r[k]] }
    end

    def thaw_result(h)
      TABLE_KEYS.to_h { |k| [k, h[k.to_s]] }.merge(status: :ok, linkage: :two_arms, corners: 0, from_table: true)
    end

    # the whole solution moved by dy along the depth
    def shift_result(r, dy)
      return r if dy.abs < 1e-6

      pt = ->(p) { [p[0], p[1] + dy] }
      pose = lambda do |p|
        a = p[0] * Math::PI / 180.0
        [p[0], p[1] + Math.sin(a) * dy, p[2] + dy - Math.cos(a) * dy]
      end
      r.merge(tray: r[:tray].map(&pt), ga: pt.call(r[:ga]), gb: pt.call(r[:gb]), pa: pt.call(r[:pa]), pb: pt.call(r[:pb]), door: r[:door].map(&pt),
              cols: r[:cols].map { |c, rad| [pt.call(c), rad] }, poses: r[:poses].map(&pose), deployed: pose.call(r[:deployed]))
    end

    def solve_cached(g)
      v = variant(g[:variant])
      return { status: :reference_required } unless v[:buildable]

      @solved ||= {}
      key = ref_key(g)
      ref = (@solved[key] ||= (table[key] ? thaw_result(table[key]) : solve(ref_geometry(g))))
      return solve(g) unless ref[:status] == :ok && ref[:linkage] == :two_arms

      out = shift_result(ref, g[:cd] - REF_CD)
      gg = g.merge(cols: out[:cols])
      clear = out[:poses].none? { |p| hit_pose(gg, out[:tray], p, 3.0, out[:door]) || arm_hit(g, out[:ga], apply(p, out[:pa]), 3.0) || arm_hit(g, out[:gb], apply(p, out[:pb]), 3.0, out[:crank_b].to_f) }
      clear ? out : solve(g) # never trusted blindly: the moved path is checked in the real carcass
    end

    # ---- two-arm linkage (four-bar) ---------------------------------------------------------------------------------------------
    # The supplier plan view shows TWO fixed bearings: one at the front of the opening-side gable and one at the post (the column).
    # Each tray hangs on an arm from each of them, so its whole path is fixed by the fitting (one degree of freedom) - nothing is
    # steered. Read off the drawing: where the two bearings stand. NOT published: the arm lengths and where they hold the tray; they
    # are the pair that takes the tray exactly from the stored to the published swung-out position with the largest clearance.
    # MANUFACTURER DATA (Kesseboehmer mounting instruction MA 405519, rev 2025-01-31, LeMans II): the mounting profile of the swing
    # arms is screwed to the opening-side gable 52 mm behind its front edge; the axle stands 53 mm behind the carcass front, X from the
    # inner face of that gable (626 for the LeMans 60) - see VARIANTS :axle_x / :axle_back. The arms on the axle are CRANKED (they go
    # round the post), the arms on the profile are straight. Both arms run UNDER the tray, so only the axle stands in the tray's way.
    # Still NOT published: the arm lengths, where they hold the tray, how far the arm joint stands off the profile (PIVOT_A[..][0]).
    PIVOT_A = [[30.0, 52.0], [26.0, 52.0], [34.0, 52.0]].freeze # [in from the gable face, back from the carcass front] - first that works
    CRANKS = [0.0, 60.0, -60.0, 90.0, -90.0].freeze # offset of the elbow of the axle arm, to either side - the first that clears everything
    PIVOT_A_R = 9.0
    BAR_STEP = 15.0

    def circles(c1, r1, c2, r2)
      d = dist(c1, c2)
      return [] if d > r1 + r2 || d < (r1 - r2).abs || d < 1e-9

      a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
      h = Math.sqrt([r1 * r1 - a * a, 0.0].max)
      m = [c1[0] + a * (c2[0] - c1[0]) / d, c1[1] + a * (c2[1] - c1[1]) / d]
      o = [-(c2[1] - c1[1]) / d * h, (c2[0] - c1[0]) / d * h]
      [[m[0] + o[0], m[1] + o[1]], [m[0] - o[0], m[1] - o[1]]]
    end

    # the tray driven by the arm at ga (angle a0 -> a0 + da): -> [poses, arm_b angles (deg from stored)] or nil when the linkage locks
    def fourbar_path(ga, gb, pa, pb, da, steps)
      la = dist(pa, ga)
      lb = dist(pb, gb)
      lc = dist(pa, pb)
      a0 = Math.atan2(pa[1] - ga[1], pa[0] - ga[0])
      c0 = Math.atan2(pb[1] - pa[1], pb[0] - pa[0])
      b0 = Math.atan2(pb[1] - gb[1], pb[0] - gb[0])
      prev = pb
      th = 0.0
      bt = 0.0
      poses = []
      arm_b = []
      (0..steps).each do |k|
        al = a0 + da * k / steps.to_f
        paw = [ga[0] + la * Math.cos(al), ga[1] + la * Math.sin(al)]
        pbw = circles(paw, lc, gb, lb).min_by { |c| dist(c, prev) }
        return nil if pbw.nil? || dist(pbw, prev) > 40.0

        prev = pbw
        turn = lambda do |now, ref, base|
          q = (now - base) * 180.0 / Math::PI
          q -= 360.0 while q - ref > 180.0
          q += 360.0 while q - ref < -180.0
          q
        end
        th = turn.call(Math.atan2(pbw[1] - paw[1], pbw[0] - paw[0]), th, c0)
        bt = turn.call(Math.atan2(pbw[1] - gb[1], pbw[0] - gb[0]), bt, b0)
        r = rot(pa, th)
        poses << [th, paw[0] - r[0], paw[1] - r[1]]
        arm_b << bt
      end
      [poses, arm_b]
    end

    # a swing arm (straight bar a -> b, under the tray) against the post, the filler / return run, the opening-side gable and the back
    # centre line of an arm: straight, or cranked (an elbow standing 'crank' mm to one side at the bearing end)
    def arm_line(a, b, crank = 0.0)
      l = dist(a, b)
      return [a, b] if crank.to_f.abs < 0.5 || l < 1e-6

      [a, [a[0] - (b[1] - a[1]) / l * crank, a[1] + (b[0] - a[0]) / l * crank], b]
    end

    def arm_hit(g, a, b, m, crank = 0.0)
      run = 0.0
      arm_line(a, b, crank).each_cons(2).any? do |p, q|
        len = dist(p, q)
        n = [(len / 15.0).ceil, 1].max
        hit = (0..n).any? do |i|
          next false if run + len * i / n < 40.0 # the bearing end of the arm stands beside the board it is fixed to

          x = p[0] + (q[0] - p[0]) * i / n.to_f
          d = p[1] + (q[1] - p[1]) * i / n.to_f
          (x > g[:edge] - m && x < g[:edge] + g[:t] + m && d > g[:cd] - g[:post_w] - m) || (x > g[:edge] - m && d > g[:cd] - m) ||
            (x < g[:xi0] + m && d < g[:cd] + g[:ft] + m) || d < g[:db] + m
        end
        run += len
        hit
      end
    end
    ARM_CLEAR = 13.0 # centre line of the bar: half its width (7 - 9) + 4 at least

    def solve_fourbar(g)
      v = variant(g[:variant])
      return nil unless v[:buildable]

      o = outline(g)
      tray = o[:pts]
      door = door_segment(g, v[:swing])
      gb = g[:col]
      found = PIVOT_A.map do |ain, aback|
        ga = [g[:xi0] + ain, g[:cd] - aback]
        gg = g.merge(cols: [[gb, COLUMN_R]])
        next if hit_pose(gg, tray, [0.0, 0.0, 0.0], MARGINS.last, door_segment(g, 0.0)) # stored: the tray must clear the axle

        dep = deployed_pose(gg, tray, door)
        next unless dep

        la_p, la_d = coupler_line(ga, dep)
        lb_p, lb_d = coupler_line(gb, dep)
        best = nil
        (-30..30).each do |i|
          pa = [la_p[0] + la_d[0] * i * BAR_STEP, la_p[1] + la_d[1] * i * BAR_STEP]
          next unless inside?(tray, pa) && dist(pa, ga) >= 60.0

          a0 = Math.atan2(pa[1] - ga[1], pa[0] - ga[0])
          pd = apply(dep, pa)
          d0 = Math.atan2(pd[1] - ga[1], pd[0] - ga[0]) - a0
          d0 += 2 * Math::PI while d0 <= 0
          (-30..30).each do |j|
            pb = [lb_p[0] + lb_d[0] * j * BAR_STEP, lb_p[1] + lb_d[1] * j * BAR_STEP]
            next unless inside?(tray, pb) && dist(pb, gb) >= 60.0 && dist(pa, pb) >= 120.0

            [d0, d0 - 2 * Math::PI].each do |da|
              next if da.abs > 1.3 * Math::PI

              poses, arm_b = fourbar_path(ga, gb, pa, pb, da, STEPS * 2)
              next unless poses

              fin = poses.last
              next unless (fin[0] - dep[0]).abs < 1.0 && (fin[1] - dep[1]).abs < 3.0 && (fin[2] - dep[2]).abs < 3.0
              next if poses.any? { |p| hit_pose(gg, tray, p, MARGINS.last, door) }
              next if poses.any? { |p| arm_hit(g, ga, apply(p, pa), ARM_CLEAR) } # the arms themselves pass nothing
              crank = CRANKS.find { |c| poses.none? { |p| arm_hit(g, gb, apply(p, pb), ARM_CLEAR, c) } }
              next unless crank

              m = MARGINS.find { |mm| mm == MARGINS.last || poses.none? { |p| hit_pose(gg, tray, p, mm, door) } }
              over = poses.map { |p| (p[0] - dep[0] * 0.5).abs }.max - dep[0].abs * 0.5 # how far the tray turns past its end positions on the way
              score = m * 100.0 - over - dist(pb, gb) * 0.02
              next unless best.nil? || score > best[:score]

              even = ->(a) { (0..STEPS).map { |k| a[k * 2] } }
              poses[-1] = dep
              best = { poses: even.call(poses), arm: even.call((0..STEPS * 2).map { |k| da * 180.0 / Math::PI * k / (STEPS * 2.0) }), arm_b: even.call(arm_b),
                       pa: pa, pb: pb, la: dist(pa, ga), lb: dist(pb, gb), clear: m, score: score, overturn: over, corners: 0, crank_b: crank }
            end
          end
        end
        next unless best

        { tray: tray, deployed: dep, door: door, outline: o, ga: ga, gb: gb, cols: gg[:cols], linkage: :two_arms, status: :ok }.merge(best)
      end
      found.compact.max_by { |r| r[:score] }
    end

    # -> { status:, tray:, poses: [[deg, tx, td]...], arm: [deg...] (arm angle from stored), ga:, pa:, la:, clear:, deployed:, door: }
    # ga = the column axis, pa = the pivot under the tray at the end of the swing arm. The pivot is searched along its line for the arm
    # whose whole path clears everything by the largest margin with the least turning.
    def solve(g)
      v = variant(g[:variant])
      return { status: :reference_required } unless v[:buildable]

      solve_fourbar(g) || solve_single(g).merge(linkage: :one_arm)
    end

    # one swing arm on the column, the tray steered on its pivot (used only where the two-arm linkage finds no clear path)
    def solve_single(g)
      v = variant(g[:variant])

      o = outline(g)
      tray = o[:pts]
      door = door_segment(g, v[:swing])
      dep = deployed_pose(g, tray, door)
      ga = g[:col]
      base = { tray: tray, deployed: dep, door: door, outline: o, ga: ga }
      return base.merge(status: :no_end_position) unless dep

      lp, ld = coupler_line(ga, dep)
      best = nil
      MARGINS.each do |m|
        (-24..24).each do |k|
          pa = [lp[0] + ld[0] * k * 20.0, lp[1] + ld[1] * k * 20.0]
          next unless inside?(tray, pa)

          la = dist(pa, ga)
          next if la < 90.0

          a0 = Math.atan2(pa[1] - ga[1], pa[0] - ga[0])
          pd = apply(dep, pa)
          d0 = Math.atan2(pd[1] - ga[1], pd[0] - ga[0]) - a0
          d0 += 2 * Math::PI while d0 <= 0
          [d0, d0 - 2 * Math::PI].each do |da|
              next if da.abs < 0.1 || da.abs > 1.2 * Math::PI

            way = route(g, tray, door, ga, la, pa, a0, da, dep[0], m)
            next unless way

            cfgs = resample(way)
            mk = ->(cs) { cs.map { |al, th| arm_pose(ga, la, pa, al, th) } }
            ok = ->(ps) { ps.none? { |p| hit_pose(g, tray, p, [m - 2.0, 3.0].max, door) } }
            [9, 5, 3].each do |win| # ease the corners of the route when the eased route is still clear
              sm = smooth(cfgs, win)
              next unless ok.call(mk.call(sm))

              cfgs = sm
              break
            end
            poses = mk.call(cfgs)
            next unless ok.call(poses)

            score = way.size * 40.0 + da.abs * 180.0 / Math::PI + la * 0.05
            next unless best.nil? || score < best[:score]

            best = { poses: poses, arm: cfgs.map { |al, _| (al - a0) * 180.0 / Math::PI }, pa: pa, la: la, clear: [m - 2.0, 3.0].max, score: score, corners: way.size - 2 }
          end
        end
        break if best
      end
      best ? base.merge(best).merge(status: :ok) : base.merge(status: :no_path)
    end
  end
end
