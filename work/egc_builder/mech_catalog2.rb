# frozen_string_literal: true

module EGC
  # Second set of family builders (mixed into Cabinet like the first): fittings that kitchen hardware suppliers list and the library did
  # not have. Generic geometry sized from the cabinet's real clear box; every size that belongs to a bought fitting is a named constant.
  module FamilyBuilders
    DOOR_BIN = { from_hinge: 90.0, depth: 160.0, max_w: 240.0 }.freeze # bin hung on the door: far enough from the hinge and shallow enough to swing out between the sides

    # ---------------------------------------------------------------------------------------------- bin on the door
    # A hinged door with ONE bin hung on its inside: the bin comes out with the door, then its lid lifts.
    def fam_doorbin(_o)
      b = bnd
      zf, hf = full_front
      bw = [[@w - 2 * @t - DOOR_BIN[:from_hinge] - 60, 160.0].max, DOOR_BIN[:max_w]].min
      bd = DOOR_BIN[:depth]
      bh = [[(b[:z1] - b[:z0]) * 0.5, 240.0].max, 330.0].min
      bx = @gap / 2.0 + DOOR_BIN[:from_hinge]
      bz = zf + 150
      da = asm('door', MotionProfiles.hinge_rotate([@gap / 2.0, @cd + @ft, 0], -90, [0.0, 0.7]).merge(door_slide ? { 'slide' => door_slide } : {}))
      in_asm(da) do
        front('door', @gap / 2.0, @w - @gap, zf, hf, :top, grain: :z)
        with_hand('L') { door_hinges(0, 1, @gap / 2.0, @w - @gap, zf, hf) }
        h_slab('bin_bracket', bx - 6, @cd - 8, bz + bh - 46, bw + 12, 8, 46, :steel)
        h_bin('bin', bx, @cd - 8 - bd, bz, bw, bd, bh)
        lid = asm('lid1', MotionProfiles.lift([bx + bw / 2.0, @cd - 8 - bd + 3, bz + bh], -58, [0.7, 1.0]))
        in_asm(lid) do
          h_slab('bin_lid', bx - 3, @cd - 8 - bd + 3, bz + bh, bw + 6, bd - 4, 3, :plastic)
          h_rod('lid_grip', bx + bw * 0.3, @cd - 20, bz + bh + 3, :x, bw * 0.4, 8, :plastic)
        end
      end
      with_hand('L') { door_plates(0, 1, @gap / 2.0, @w - @gap, zf, hf) }
      shelves({ t: :doors, shelves: 1, z0: @z0 + @t, h: @hc - 2 * @t, front_clear: bd + 40 })
      @hw['hinge'] += hinge_count(hf)
    end

    # ---------------------------------------------------------------------------------------------- broom / cleaning pull-out column
    # Narrow tall unit: the whole front pulls out on a floor slide and a top slide; a frame carries hook rails and a basket.
    def fam_broom(_o)
      b = bnd
      zf, hf = full_front
      cd = b[:d1] - b[:d0]
      len = rail_len(cd + 30)
      bb = front_anchor(b, len, true)
      travel = len.to_f # full extension: the whole column, baskets included, stands in front of the carcass
      zs = [b[:z0] + 6, b[:z1] - SL_H - 14]
      zs.each { |sz| slide_fixed_mid(bb[:x0], bb[:x1], bb[:d0], sz, len, travel) }
      a = asm('pullout', MotionProfiles.linear_slide([0, travel, 0]))
      in_asm(a) do
        zs.each { |sz| slide_inner(bb[:x0], bb[:x1], bb[:d0], sz, len) }
        front('door', @gap / 2.0, @w - @gap, zf, hf, :top, grain: :z)
        # The frame stands at ONE side of the column (as on the real fittings) and everything hangs off it across the unit:
        # a bottom tray for the broom head and bottles, two baskets over the REAR half only (the front half stays free, floor to top,
        # for long handles), two rails of spring clips that grip the handles, a top rail of hooks and a saddle for the vacuum hose.
        # Layout of a generic broom column - not one maker's dimensions.
        fh = b[:z1] - b[:z0] - 2 * SL_H - 60
        fz = b[:z0] + SL_H + 26
        fx = b[:x0] + 4
        aw = b[:x1] - 4 - (fx + 20)
        da = bb[:d0] + 14
        flen = @cd - 34 - da + 20
        [da, @cd - 34].each { |dd| h_slab('broom_frame', fx, dd, fz, 20, 20, fh, :steel) }
        [fz, fz + fh - 16].each { |z| h_slab('broom_frame', fx, da, z, 20, flen, 16, :steel) }
        if aw >= 50
          h_tray('broom_tray', fx + 20, da, fz + 16, aw, flen, 45)
          [0.28, 0.50].each { |f| h_basket('broom_basket', fx + 20, da + 4, fz + fh * f, aw, flen * 0.5 - 8, 110) }
        end
        [0.66, 0.84].each do |f|
          z = fz + fh * f
          h_slab('broom_rail', fx, da, z, 16, flen, 14, :steel)
          2.times do |k|
            c0 = da + flen * 0.56 + k * [flen * 0.2, 90.0].min
            [0, 27].each { |o| h_slab('broom_clip', fx + 16, c0 + o, z - 5, [aw * 0.55, 38].min, 5, 24, :zinc) } # one clip = two sprung jaws
          end
        end
        zt = fz + fh * 0.95
        h_slab('broom_rail', fx, da, zt, 16, flen, 14, :steel)
        3.times { |k| h_rod('broom_hook', fx + 16, da + 40 + k * ((flen - 90) / 2.0), zt + 3, :x, [aw * 0.6, 46].min, 8, :chrome, 10) }
        hz = fz + fh * 0.74
        h_slab('hose_holder', fx + 16, da + 30, hz, [aw * 0.7, 60].min, 90, 6, :zinc)
        [0, 84].each { |o| h_slab('hose_holder', fx + 16, da + 30 + o, hz + 6, [aw * 0.7, 60].min, 6, 28, :zinc) }
      end
      @hw['slide_pair'] += 2
    end

    # flat plate of any outline (plan points [x, d]) at height z - for tray shapes the cached box parts cannot make
    def h_poly(part, pts, z, thk, mat = :steel)
      g = tgt.add_group
      face = g.entities.add_face(pts.map { |x, d| Geo.p3(x, d, z) })
      face&.pushpull((face.normal.z >= 0 ? 1 : -1) * Geo.mm(thk))
      g.material = mpm[mat]
      hw_tag(g, part)
    end

    # ---------------------------------------------------------------------------------------------- blind corner swing-out trays (LeMans II type)
    # Planning sizes: supplier sheet for the DOOR 600 variant (LemansKin::VARIANTS). The door hangs on the post between the opening and
    # the blind lane; the column stands behind the fixed filler beside that post. Each tray hangs on a swing arm that turns about the
    # column and turns on the pivot at the end of the arm; it leaves through the opening and ends in front of the cabinet, 706 mm out
    # and past the cabinet side (supplier plan view). The path is solved and checked for interference in LemansKin. The arm and the tray
    # outline are NOT the manufacturer's: LemansKin::LINKAGE_STATUS.
    LEMANS = { post_w: 45.0, col_in: 36.0, col_back: 59.0, levels: [0.10, 0.55], tray_thk: 18.0 }.freeze
    LEMANS_TURN_SIGN = -1.0 # a positive plan angle of the motion engine is clockwise in the builder's (x, d) plane

    def lemans_geometry(key, right)
      v = LemansKin.variant(key)
      open = LemansKin.opening_for(key, @t)
      ih = @hc - 2 * @t
      need = []
      need << "carcass board #{v[:side].map(&:round).join('-')} mm | سمك الجنب #{v[:side].map(&:round).join('-')} مم" unless open
      need << "inside width >= #{LemansKin.inner_min(key, @t).round} mm | العرض الداخلي #{LemansKin.inner_min(key, @t).round} مم على الأقل" if @w - 2 * @t < LemansKin.inner_min(key, @t) - 0.5
      need << "inside depth >= #{v[:depth_min].round} mm | العمق الداخلي #{v[:depth_min].round} مم على الأقل" if @cd - @bk < v[:depth_min] - 0.5
      need << "inside height #{v[:height].map(&:round).join('-')} mm | الارتفاع الداخلي #{v[:height].map(&:round).join('-')} مم" unless ih.between?(v[:height][0] - 0.5, v[:height][1] + 0.5)
      unless need.empty?
        raise MechanismError.new(:too_small, "swing-out corner trays (door #{v[:door].round}) need: #{need.map { |n| n.split(' | ')[0] }.join(', ')} | صواني الركنة (ضلفة #{v[:door].round}) تحتاج: #{need.map { |n| n.split(' | ')[1] }.join('، ')}")
      end

      edge = @t + open
      { variant: key, xi0: @t, xi1: @w - @t, db: @bk, cd: @cd, ft: @ft, t: @t, edge: edge, post_w: LEMANS[:post_w],
        hx: v[:door] - @gap / 2.0, dw: v[:door] - @gap, col: [@t + v[:axle_x], @cd - v[:axle_back]] } # the axle where the mounting instruction puts it
    end

    # FIXING BORES from the mounting instruction (Kesseboehmer MA 405519): the profile on the opening-side gable - 5 mm pilot bores
    # 52 mm from the front edge, the first 28 mm above the bottom, then every 64 mm (8 for the 500 profile) - and the bore of the
    # axle foot in the bottom (5 mm, 13 deep, 53 mm from the front edge, X from the gable). Called when the unit is finished.
    def lemans_mount_bores
      v, right = @lemans_mount
      find = ->(part) { @e.to_a.find { |q| q.respond_to?(:get_attribute) && q.get_attribute('egc', 'part').to_s == part } }
      put = lambda do |inst, add|
        old = begin; JSON.parse(inst.get_attribute('egc', 'bore').to_s); rescue StandardError; []; end
        inst.set_attribute('egc', 'bore', JSON.generate(old + add))
      end
      if (side = find.call(right ? 'side_l' : 'side_r'))
        put.call(side, (0...8).map do |i|
          { 't' => 'LeMans profile', 'x' => v[:rail_back], 'y' => (@t + v[:rail_first] + i * v[:rail_pitch]).round(1), 'dia' => 5, 'depth' => 13,
            'ref' => 'inner face; x from front edge, y from bottom; Kesseboehmer MA 405519' }
        end)
      end
      if (bot = find.call('bottom'))
        len = bot.get_attribute('egc', 'len').to_f
        x = (right ? @t + v[:axle_x] : @w - @t - v[:axle_x]) - (@w - len) / 2.0
        if x.between?(10.0, len - 10.0)
          put.call(bot, [{ 't' => 'LeMans axle foot', 'x' => x.round(1), 'y' => v[:axle_back], 'dia' => 5, 'depth' => 13,
                           'ref' => 'top face; x from the left end, y from the front edge; Kesseboehmer MA 405519' }])
        end
      end
    rescue StandardError
      nil
    end

    def fam_lemans(o)
      right = (o[:blind] || 'right').to_s == 'right' # blind lane on the right, opening on the left (the frame LemansKin works in)
      key = (o[:variant] || '600').to_s
      g = lemans_geometry(key, right)
      v = LemansKin.variant(key)
      k = LemansKin.solve_cached(g)
      unless k[:status] == :ok
        raise MechanismError.new(:no_path, "swing-out corner trays: no interference-free path in this carcass (#{k[:status]}) | صواني الركنة: لا يوجد مسار خروج بدون تصادم في هذه الوحدة")
      end

      b = bnd
      zf, hf = full_front
      h = b[:z1] - b[:z0]
      mx = ->(x) { right ? x : @w - x }                 # mirror an x coordinate for the left-hand unit
      sg = right ? 1.0 : -1.0
      edge = g[:edge]
      colm = [mx.call(g[:col][0]), g[:col][1]]
      h_rod('lemans_column', colm[0] - 13, colm[1] - 13, b[:z0], :z, h, 26, :chrome, 12)
      pts = k[:tray].map { |p| [mx.call(p[0]), p[1]] }
      pts.reverse! unless right
      pam = [mx.call(k[:pa][0]), k[:pa][1]]
      gam = [mx.call(k[:ga][0]), k[:ga][1]]            # bearing of the main swing arm (two-arm linkage: at the front of the opening-side gable)
      pbm = k[:pb] && [mx.call(k[:pb][0]), k[:pb][1]]   # where the second arm (from the column) holds the tray
      n = k[:poses].size - 1
      LEMANS[:levels].each_with_index do |f, i|
        z = b[:z0] + h * f
        p0 = 0.34 + i * 0.12                             # the door is open by 0.34; the upper tray follows the lower one
        p1 = [p0 + 0.50, 1.0].min
        at = ->(j) { p0 + (p1 - p0) * j / n.to_f }
        tkeys = [[0.0, 0, 0, 0]]
        akeys = [[0.0, 0, 0, 0]]
        bkeys = [[0.0, 0, 0, 0]]
        k[:poses].each_with_index do |pose, j|
          pw = LemansKin.apply(pose, k[:pa])            # where the arm-end pivot is: the tray turns about it and is carried by it
          tkeys << [at.call(j), sg * (pw[0] - k[:pa][0]), pw[1] - k[:pa][1], sg * LEMANS_TURN_SIGN * pose[0]]
          akeys << [at.call(j), 0, 0, sg * LEMANS_TURN_SIGN * k[:arm][j]]
          bkeys << [at.call(j), 0, 0, sg * LEMANS_TURN_SIGN * k[:arm_b][j]] if pbm
        end
        [tkeys, akeys, bkeys].each { |ks| ks << [1.0, *ks.last[1..]] if ks.last[0] < 1.0 }
        tr = asm("tray#{i + 1}", MotionProfiles.pose_xd([pam[0], pam[1], z], tkeys))
        in_asm(tr) do
          h_poly('lemans_tray', pts, z, LEMANS[:tray_thk], :steel)
          h_rod('lemans_pivot', pam[0] - 11, pam[1] - 11, z - 12, :z, 12, 22, :dark, 12)
          h_rod('lemans_pivot', pbm[0] - 11, pbm[1] - 11, z - 34, :z, 34, 22, :dark, 12) if pbm
        end
        arm = asm("tray_arm#{i + 1}", MotionProfiles.pose_xd([gam[0], gam[1], z], akeys))
        in_asm(arm) { h_between('lemans_arm', [gam[0], gam[1], z - 22], [pam[0], pam[1], z - 22], 18, :zinc) }
        if pbm
          h_slab('lemans_bearing', gam[0] - 12, gam[1] - 12, z - 44, 24, 24, 44, :dark)
          link = asm("tray_link#{i + 1}", MotionProfiles.pose_xd([colm[0], colm[1], z], bkeys))
          crank = LemansKin.arm_line(k[:gb], k[:pb], k[:crank_b].to_f).map { |p| [mx.call(p[0]), p[1]] } # the axle arm is cranked: it goes round the post
          in_asm(link) do
            segs = crank.each_cons(2).to_a
            segs.each_with_index { |(p, q), si| h_between(si == segs.size - 1 ? 'lemans_arm' : 'lemans_arm_crank', [p[0], p[1], z - 44], [q[0], q[1], z - 44], 14, :zinc) }
          end
        end
        h_slab('lemans_bearing', colm[0] - 26, colm[1] - 26, z - 50, 52, 52, 18, :dark)
      end
      # mounting profile of the swing arms on the opening-side gable (500 long, 52 mm behind the front edge, 28 mm above the bottom)
      h_slab('lemans_rail', right ? @t : @w - @t - 8.0, @cd - v[:rail_back] - 13.0, @z0 + @t + v[:rail_first] - 14.0, 8, 26, 500, :zinc)
      @lemans_mount = [v, right]
      # fixed post between the opening and the blind lane: the door hangs on it
      pw = LEMANS[:post_w]
      post_x = right ? edge : @w - edge - @t
      pn('vdivider', post_x, @cd - pw, @z0 + @t, @t, pw, @hc - 2 * @t, 'carcass', grain: :z, eb: [1, 0])
      dw = g[:dw]
      fw = @w - v[:door] - @gap                         # fixed filler over the blind lane
      dx0 = right ? @gap / 2.0 : @w - v[:door] + @gap / 2.0
      hx = right ? dx0 + dw : dx0                       # hinge edge of the door: at the post
      da = asm('door', MotionProfiles.hinge_rotate([hx, @cd + @ft, 0], right ? v[:swing] : -v[:swing], [0.0, 0.34]).merge(door_slide ? { 'slide' => door_slide } : {}))
      # the hinges sit on the POST, not on a gable: the hinge helpers take the post face as the side they mount on
      on_post = lambda do |&blk|
        o0 = @sx0
        o1 = @sx1
        right ? @sx1 = edge : @sx0 = @w - edge
        begin
          with_hand(right ? 'R' : 'L', &blk)
        ensure
          @sx0 = o0
          @sx1 = o1
        end
      end
      in_asm(da) do
        front('door', dx0, dw, zf, hf, :top, grain: :z)
        on_post.call { door_hinges(0, 1, dx0, dw, zf, hf) }
      end
      fx = right ? v[:door] + @gap / 2.0 : @gap / 2.0
      pn('filler', fx, @cd, zf, fw, @ft, hf, 'front', grain: :z, eb: [2, 2], eb_t: 2.0)
      on_post.call { door_plates(0, 1, dx0, dw, zf, hf) }
      @hw['hinge'] += hinge_count(hf)
    end

    # ---------------------------------------------------------------------------------------------- swing-out work table (ChefsTable type)
    # Supplier drawing: behind a hinged door, a table board hangs on two parallel swing arms per side. Pulled forward it swings OUT of the
    # cabinet and comes to rest level with the worktop, in front of it. It does not rise out of a drawer. Clear width 362-568, depth >= 480,
    # height >= 535 (supplier figures). load_kg is the RATING of the fitting (what may stand on the table: 16 kg in the product title and
    # feature list; one sentence of the same page says 19) - it is not the weight of the modelled board and is not derived from it.
    CHEF_TABLE = { top_thk: 25.0, arm_start: 215.0, arm_end: 80.0, cw: [362.0, 568.0], min_cd: 480.0, min_ch: 535.0, load_kg: 16 }.freeze

    def fam_cheftable(_o)
      b = bnd
      zf, hf = full_front
      if @cd - @bk < CHEF_TABLE[:min_cd] - 0.5 || @hc - 2 * @t < CHEF_TABLE[:min_ch] - 0.5
        raise MechanismError.new(:too_small, "the swing-out table needs #{CHEF_TABLE[:min_cd].round} mm clear depth and #{CHEF_TABLE[:min_ch].round} mm clear height | ترابيزة الشغل تحتاج عمق داخلي #{CHEF_TABLE[:min_cd].round} وارتفاع #{CHEF_TABLE[:min_ch].round} مم")
      end

      cw = @w - 2 * @t
      unless cw.between?(CHEF_TABLE[:cw][0] - 0.5, CHEF_TABLE[:cw][1] + 0.5)
        raise MechanismError.new(cw < CHEF_TABLE[:cw][0] ? :too_small : :too_big, "the swing-out table fits a clear width of #{CHEF_TABLE[:cw].map(&:round).join('-')} mm (units 400-600), this one is #{cw.round} | ترابيزة الشغل تركب في عرض داخلي #{CHEF_TABLE[:cw].map(&:round).join('-')} مم (وحدات 40-60)، وهذه #{cw.round}")
      end

      if (@s[:handle] || @c['handle']).to_s == 'gola'
        # measured on the built model: swung out, the table carriers pass through the L profile that sits under the worktop of a
        # handle-free unit. The fitting is refused there - nothing is moved or cut to make it fit.
        raise MechanismError.new(:profile_clash, 'the swing-out table cannot be fitted behind handle-free (gola) fronts: its carriers run through the L profile under the worktop - give this unit another handle type | ترابيزة الشغل لا تركب مع واجهات بدون مقبض (جولا): حواملها تمر في بروفايل L تحت الرخامة - اختر نوع مقبض آخر لهذه الوحدة')
      end

      @door_phase = [0.0, 0.3]
      doors({ t: :doors, n: 1 }, zf, hf, false)
      @door_phase = nil
      rad = Math::PI / 180.0
      a0 = CHEF_TABLE[:arm_start]
      a1 = CHEF_TABLE[:arm_end]
      tl = [@cd - @bk - 70.0, 440.0].min                         # table length (front to back)
      tw = b[:x1] - b[:x0] - 70
      tx = b[:x0] + 35
      top_z = @z0 + @hc + @c['top_thk'].to_f                     # worktop surface
      ov = @c['top_overhang'].to_f                               # the worktop stands this far in front of the fronts: the table ends clear of it
      reach = tl + 30.0 + @ft + ov                                # the rear edge of the table ends this far in front of where it was
      r = reach / (Math.sin(a1 * rad) - Math.sin(a0 * rad))       # arm length from the horizontal travel
      second = 70.0
      jz1 = top_z - CHEF_TABLE[:top_thk] - 8                      # joint height with the table out
      pv = [@cd + @ft + ov + 10 + 60 - r * Math.sin(a1 * rad), jz1 - r * Math.cos(a1 * rad)] # fixed pivot (depth, height) on the side plate
      ja = [pv[0] + r * Math.sin(a0 * rad), pv[1] + r * Math.cos(a0 * rad)]             # joint on the table, stored
      n = 41
      samples = (0...n).map { |i| i / (n - 1.0) }
      angs = samples.map { |u| a0 + (a1 - a0) * Mechanisms.phase({ 'phase' => [0.3, 1.0] }, u) }
      keys_t = samples.each_index.map { |i| [samples[i], pv[0] + r * Math.sin(angs[i] * rad) - ja[0], pv[1] + r * Math.cos(angs[i] * rad) - ja[1], 0] }
      mir = ->(x, wd) { b[:x1] - (x - b[:x0]) - wd }
      [b[:x0] + 4, mir.call(b[:x0] + 4, 4.0)].each { |xp| h_slab('table_side_plate', xp, pv[0] - 30, pv[1] - 34, 4, second + 60, 68, :zinc) }
      [b[:x0] + 12, mir.call(b[:x0] + 12, 8.0)].each_with_index do |xa, si|
        [0.0, second].each_with_index do |od, k|
          arm = asm("table_arm#{si}#{k}", MotionProfiles.pose([xa + 4, pv[0] + od, pv[1]], samples.each_index.map { |i| [samples[i], 0, 0, angs[i] - a0] }))
          in_asm(arm) do
            h_between('table_arm', [xa + 4, pv[0] + od, pv[1]], [xa + 4, ja[0] + od, ja[1]], 16, :steel)
            h_rod('table_arm_pin', xa - 2, pv[0] + od - 6, pv[1] - 6, :x, 12, 12, :dark, 12)
          end
        end
      end
      ta = asm('table', MotionProfiles.pose([@w / 2.0, ja[0], ja[1]], keys_t))
      in_asm(ta) do
        h_slab('table_top', tx, ja[0] - 60, ja[1] + 8, tw, tl, CHEF_TABLE[:top_thk], :plastic)
        [b[:x0] + 24, mir.call(b[:x0] + 24, 6.0)].each { |xc| h_slab('table_carrier', xc, ja[0] - 22, ja[1] - 14, 6, second + 44, 22, :steel) }
        h_rod('table_grip', tx + tw * 0.3, ja[0] - 60 + tl - 14, ja[1] - 4, :x, tw * 0.4, 10, :dark, 10)
      end
      shelves({ t: :doors, shelves: 1, z0: @z0 + @t, h: [ja[1] - 90 - (@z0 + @t), 200.0].max })
    end

    # ---------------------------------------------------------------------------------------------- powered lift basket (wall unit, comes down out of the underside)
    # The unit has no bottom. Doors open, then the shelf set travels straight down on two rear guides to a reachable height.
    LIFT_BASKET = { travel: 420.0, shelf_gap: 220.0 }.freeze

    def fam_liftbasket(_o)
      b = bnd
      zf, hf = full_front
      @door_phase = [0.0, 0.3]
      doors({ t: :doors }, zf, hf, false)
      @door_phase = nil
      zlow = @z0 + 6
      bw = b[:x1] - b[:x0] - 40
      bd = [b[:d1] - b[:d0] - 40, 250.0].min
      bh = [[@hc - 150, 260.0].max, 480.0].min
      d0 = b[:d0] + 22
      [b[:x0] + 26, b[:x1] - 44].each { |x| h_slab('lift_guide', x, b[:d0] + 2, zlow + 20, 18, 16, @hc - 60, :zinc) }
      h_slab('lift_motor', @w / 2.0 - 110, b[:d0] + 2, @z0 + @hc - @t - 74, 220, 70, 64, :dark)
      a = asm('lift_basket', MotionProfiles.linear_slide([0, 0, -LIFT_BASKET[:travel]], [0.3, 1.0]))
      in_asm(a) do
        [b[:x0] + 20, b[:x1] - 24].each { |x| h_slab('lift_frame', x, d0, zlow, 4, bd, bh, :steel) }
        n = [(bh / LIFT_BASKET[:shelf_gap]).floor, 1].max
        (n + 1).times do |i|
          z = zlow + i * ((bh - 30) / n.to_f)
          next if i == n && n > 1 && bh - (z - zlow) < 60

          h_tray('lift_shelf', b[:x0] + 24, d0, z, bw - 8, bd, 28, 1.5, :steel)
        end
        h_rod('lift_rail', b[:x0] + 24, d0 + bd - 8, zlow + 70, :x, bw - 8, 8, :chrome, 10)
      end
    end

    # ---------------------------------------------------------------------------------------------- pull-out table behind a drawer front
    # The top front is the end of a table that runs out on double-extension slides; a folding leg drops under its outer end. Doors below.
    PULL_TABLE = { front_h: 150.0, top_thk: 22.0, out: 1.55 }.freeze

    def fam_pulltable(_o)
      b = bnd
      zf, hf = full_front
      th = PULL_TABLE[:front_h]
      dh = hf - th - @gap
      doors({ t: :doors }, zf, dh, false)
      shelves({ t: :doors, shelves: 1, z0: @z0 + @t, h: dh - @t })
      pn('divider', @t, @bk, zf + dh - @t / 2.0, @w - 2 * @t, @cd - @bk - 30, @t, 'carcass', grain: :x, eb: [1, 0])
      cd = b[:d1] - b[:d0]
      len = rail_len(cd + 30)
      travel = (len * PULL_TABLE[:out]).round
      tz = zf + dh + @gap + th - PULL_TABLE[:top_thk] - 14
      sz = tz - SL_H - 6
      slide_fixed_mid(b[:x0], b[:x1], @cd - 8 - len, sz, len, travel)
      leaf = [len - 10.0, @cd - @bk - 24.0].min                  # each leaf of the telescopic top stays inside the closed carcass
      travel = [travel, (leaf * 1.9).floor].min                  # the inner leaf (half travel) always overlaps the outer one
      md = asm('table_mid', MotionProfiles.linear_slide([0, travel / 2.0, 0], [0.0, 0.72]))
      in_asm(md) { h_slab('table_top', b[:x0] + 18, @cd - 6 - leaf, tz - PULL_TABLE[:top_thk] - 2, b[:x1] - b[:x0] - 36, leaf, PULL_TABLE[:top_thk], :plastic) }
      a = asm('table', MotionProfiles.linear_slide([0, travel, 0], [0.0, 0.72]))
      in_asm(a) do
        slide_inner(b[:x0], b[:x1], @cd - 8 - len, sz, len)
        front('drawer_front', @gap / 2.0, @w - @gap, zf + dh + @gap, th, :top, grain: :x)
        tx = b[:x0] + 18
        tw = b[:x1] - b[:x0] - 36
        h_slab('table_top', tx, @cd - 6 - leaf, tz, tw, leaf, PULL_TABLE[:top_thk], :plastic) # outer leaf: no longer than the carcass is deep
        leg_l = [len - 40.0, tz - 20.0].min
        ext = [tz - 6 - leg_l, 0.0].max
        lg = asm('table_leg', MotionProfiles.lift([@w / 2.0, @cd - 30, tz - 6], PULL_TABLE_LEG_DEG, [0.72, 0.92]))
        in_asm(lg) do
          h_slab('table_leg', @w / 2.0 - 20, @cd - 30 - leg_l, tz - 30, 40, leg_l, 24, :steel)
          if ext > 5
            le = asm('table_leg_ext', MotionProfiles.linear_slide([0, -ext, 0], [0.9, 1.0]))
            in_asm(le) { h_slab('table_leg', @w / 2.0 - 14, @cd - 30 - leg_l, tz - 27, 28, leg_l, 18, :chrome) }
          end
        end
      end
      @hw['hinge'] += 0
      @hw['slide_pair'] += 1
    end
    PULL_TABLE_LEG_DEG = -90
  end
end
