# frozen_string_literal: true

module EGC
  # Family builders (mixed into Cabinet). They read the cabinet's REAL clear box (Cabinet#bnd) and derive the
  # variant from it: slide length from the depth, number of baskets from the height, basket width from the width.
  # All hardware is built from MechParts (cached components) and driven by MotionProfiles.
  module FamilyBuilders
    SL_W = 12.7 # side clearance a ball-bearing slide needs per side
    SL_H = 45.7
    SL_T = 1.5

    def mpm
      MechParts.m
    end

    def tgt
      @cur || @e
    end

    def hw_tag(inst, part)
      return inst unless inst

      inst.name = "#{@name}_#{part}"
      inst.set_attribute('egc', 'role', 'hw')
      inst.set_attribute('egc', 'part', part)
      inst.set_attribute('egc', 'cab', @name)
      begin
        inst.layer = Geo.tag('EGC Hardware')
      rescue StandardError
        nil
      end
      inst
    end

    def h_rod(part, x, d, z, axis, len, dia, mat = :chrome, segs = 8)
      hw_tag(MechParts.rod(tgt, x, d, z, axis, len, dia, mpm[mat], segs), part)
    end

    def h_slab(part, x, d, z, sx, sd, sz, mat = :zinc)
      hw_tag(MechParts.slab(tgt, x, d, z, sx, sd, sz, mpm[mat]), part)
    end

    def h_chan(part, x, d, z, len, wx, hz, t, open, mat = :zinc)
      hw_tag(MechParts.channel(tgt, x, d, z, len, wx, hz, t, open, mpm[mat]), part)
    end

    def h_basket(part, x, d, z, w, dep, h, mat = :chrome, wire = 4.0)
      hw_tag(MechParts.wire_basket(tgt, x, d, z, w, dep, h, mpm[mat], wire), part)
    end

    def h_tray(part, x, d, z, w, dep, h, t = 1.5, mat = :steel)
      hw_tag(MechParts.tray(tgt, x, d, z, w, dep, h, t, mpm[mat]), part)
    end

    def h_bin(part, x, d, z, w, dep, h, mat = :plastic)
      hw_tag(MechParts.bin(tgt, x, d, z, w, dep, h, mpm[mat]), part)
    end

    def h_bar(part, x, p0, p1, w, t, mat = :zinc)
      hw_tag(MechParts.bar(tgt, x, p0, p1, w, t, mpm[mat]), part)
    end

    # round tube / rod between two points of the (d,z) plane, centred on x (cached ComponentDefinition per length / diameter)
    def h_tube(part, xc, p0, p1, dia, mat = :zinc)
      hw_tag(MechParts.rod_between(tgt, [xc, p0[0], p0[1]], [xc, p1[0], p1[1]], dia, mpm[mat]), part)
    end

    def h_brk(part, x, d, z, a, b, t, wd, mat = :zinc, front: false)
      hw_tag(MechParts.l_bracket(tgt, x, d, z, a, b, t, wd, mpm[mat], front: front), part)
    end

    def h_damper(part, x, d, z, len)
      hw_tag(MechParts.damper(tgt, x, d, z, len, mpm[:damper]), part)
    end

    def h_between(part, a, b, dia, mat = :chrome)
      hw_tag(MechParts.rod_between(tgt, a, b, dia, mpm[mat]), part)
    end

    def h_disc(part, cx, cd, z, r, deg, start, wire, mat = :chrome, lip = 40)
      hw_tag(MechParts.wire_disc(tgt, cx, cd, z, r, deg, start, wire, mpm[mat], lip), part)
    end

    def h_pin(part, x, d, z, r, len, mat = :chrome)
      hw_tag(MechParts.pivot(tgt, x, d, z, r, len, mpm[mat]), part)
    end

    # ---- 3-part telescopic slides (real C sections, 12.7 mm side clearance) -----------------------------------
    # Slides are front-referenced: the pull-out starts where its front is and any spare depth is left at the BACK of the carcass (a mechanism
    # mounted from the back left up to 50 mm of air between itself and its own front). attached = the front travels with the pull-out.
    def front_anchor(b, len, attached = true)
      b.merge(d0: [@cd - (attached ? 8.0 : 30.0) - len, b[:d0]].max, d1: attached ? @cd - 4.0 : b[:d1])
    end

    def rail_len(avail)
      [[((avail - 30) / 50.0).floor * 50, 250].max, 600].min
    end

    # outer channels + mid stage (moves at half travel). Call in the PARENT context of the moving assembly.
    def slide_fixed_mid(x0, x1, d0, z, len, travel, phase = nil)
      [[x0, 1], [x1, -1]].each do |edge, s|
        h_chan('slide_outer', s == 1 ? edge : edge - SL_W, d0, z, len, SL_W, SL_H, SL_T, s)
        # mounting plates (front + rear) that bolt the slide to the side panel, with screw heads
        [d0 + 4, d0 + len - 34].each do |pd|
          h_slab('slide_mount', s == 1 ? edge - 3 : edge, pd, z + 2, 3, 30, SL_H - 4, :zinc)
          [8, 22].each { |o| h_rod('screw', s == 1 ? edge - 4.5 : edge + 3, pd + o, z + SL_H / 2.0 - 2, :x, 1.5, 5, :chrome, 8) }
        end
      end
      mid = asm('slide_mid', MotionProfiles.telescopic_slide(travel, phase)[0])
      mid.set_attribute('egc', 'link', @link_to) if @link_to # the middle rail belongs to ONE drawer: it travels with that drawer only
      in_asm(mid) do
        [[x0, 1], [x1, -1]].each do |edge, s|
          wx = 10.6
          h_chan('slide_mid', s == 1 ? edge + 1.8 : edge - 1.8 - wx, d0, z + 1.8, len - 6, wx, SL_H - 3.6, 1.2, s)
        end
      end
      mid
    end

    # moving member - build it INSIDE the moving assembly
    def slide_inner(x0, x1, d0, z, len)
      [[x0, 1], [x1, -1]].each do |edge, s|
        wx = 8.2
        h_chan('slide_inner', s == 1 ? edge + 3.3 : edge - 3.3 - wx, d0 + 3, z + 3.3, len - 6, wx, SL_H - 6.6, 1.2, s, :steel)
      end
    end

    # soft-close: fixed damper on the back panel + striker plate on the moving frame (call inside the moving asm for the striker)
    def damper_fixed(x0, x1, d0, z)
      h_damper('softclose_damper', (x0 + x1) / 2.0 - 7, d0, z, 62)
      h_slab('damper_bracket', (x0 + x1) / 2.0 - 14, d0 - 2, z - 6, 28, 3, 28, :zinc)
    end

    def damper_striker(x0, x1, d0, z)
      h_slab('damper_striker', (x0 + x1) / 2.0 - 12, d0 + 66, z - 4, 24, 4, 22, :zinc)
    end

    def front_connectors(x0, x1, z)
      [x0 + 8, x1 - 8 - 26].each { |xc| h_brk('front_connector', xc, @cd - 34, z, 34, 30, 2.5, 26, :zinc, front: true) }
    end

    def finish_key
      @c['mech_finish'].to_s == 'chrome' ? :chrome : :anth # dark anthracite metal by default (matches the reference kitchens)
    end

    # ------------------------------------------------------------------------------------------------ PULL_OUT_BASKET
    def pull_levels(o, avail_h, pitch_min)
      want = o[:levels] || 3
      [[want, (avail_h / pitch_min).floor].min, 1].max
    end

    def fam_pullout(o)
      return fam_wire_p1(o) if o[:item] == :wire && @s[:mech].to_s == 'PULLOUT_BASKET'

      b = bnd
      zf, hf = full_front
      cw = b[:x1] - b[:x0]
      cd = b[:d1] - b[:d0]
      len = rail_len(cd + 30)
      b = front_anchor(b, len, (o[:mode] || :attached) == :attached) # the mechanism is mounted from the FRONT: it ends right behind its front, the spare depth stays at the back
      travel = len * 0.92
      sz = b[:z0] + 6
      pos = @kind == :tall ? :side_r : :top
      pos = :bottom if @kind == :wall
      swing = (o[:mode] || :attached) == :swing
      under=@s[:mech].to_s=='WIRE_DRAWER'
      slide_fixed_mid(b[:x0], b[:x1], b[:d0], sz, len, travel, swing ? [0.4, 1.0] : nil) unless under
      damper_fixed(b[:x0], b[:x1], b[:d0], sz + 8)
      if swing # hinged door opens first, then the frame runs out on the slides (the common "basket behind a door" pull-out)
        da = asm('door', MotionProfiles.hinge_rotate([@gap / 2.0, @cd + @ft, 0], -90, [0.0, 0.4]).merge(door_slide ? { 'slide' => door_slide } : {}))
        in_asm(da) do
          front('door', @gap / 2.0, @w - @gap, zf, hf, pos, grain: :z)
          with_hand('L') { door_hinges(0,1,@gap/2.0,@w-@gap,zf,hf) }
        end
        with_hand('L') { door_plates(0, 1, @gap / 2.0, @w - @gap, zf, hf) }
        @hw['hinge'] += hinge_count(hf)
      end
      a = asm('pullout', MotionProfiles.linear_slide([0, travel, 0], swing ? [0.4, 1.0] : nil))
      in_asm(a) do
        if under
          @link_to=a.name
          runners_under(b[:x0]+14,cw-28,b[:d0],len,sz+SL_H+2,travel)
          @link_to=nil
        else
          slide_inner(b[:x0], b[:x1], b[:d0], sz, len)
        end
        damper_striker(b[:x0], b[:x1], b[:d0], sz + 8)
        front('door', @gap / 2.0, @w - @gap, zf, hf, pos, grain: :z) unless swing
        carriage_tubes(b, sz + SL_H - 14, len)
        pull_contents(o, b, sz + SL_H + 2, len)
        front_connectors(b[:x0] + 12, b[:x1] - 12, sz + SL_H + 4) unless swing
      end
      @hw[under ? 'undermount_slide' : 'slide_pair'] += 1
    end

    # the moving carriage: two cross tubes tying the inner slide members together under the load (rear + front)
    def carriage_tubes(b, z, len)
      x0 = b[:x0] + 11.5
      x1 = b[:x1] - 11.5
      [b[:d0] + 14, b[:d0] + len - 44].each { |pd| h_slab('carriage_tube', x0, pd, z, x1 - x0, 16, 16, :steel) }
      h_slab('carriage_tube', x0, b[:d0] + len / 2.0 - 8, z + 2, x1 - x0, 14, 12, :steel) if len > 400
    end

    def pull_posts(bx, bw, bd, bdep, z0, z1, dia = 8)
      [[bx + 3, bd + 4], [bx + bw - 3 - dia, bd + 4], [bx + 3, bd + bdep - 8], [bx + bw - 3 - dia, bd + bdep - 8]].each do |px, pd|
        h_rod('post', px, pd, z0, :z, z1 - z0, dia)
      end
    end

    def pull_contents(o, b, z0, len)
      cw = b[:x1] - b[:x0]
      ztop = b[:z1] - 8
      bx = b[:x0] + 14
      bw = cw - 28
      bd = b[:d0] + 6
      bdep = [len - 12, b[:d1] - bd].min
      case o[:item]
      when :wire
        n = pull_levels(o, ztop - z0, 105)
        pitch = (ztop - z0) / n.to_f
        bh = [pitch - 26, 105].min
        n.times { |i| h_basket('basket', bx, bd, z0 + i * pitch, bw, bdep, bh, finish_key) }
        [b[:x0] + 11.5, b[:x1] - 14].each { |px| [bd + 50, bd + bdep - 90].each { |pd| h_slab('basket_bracket', px, pd, z0 - 12, 2.5, 30, 24, :zinc) } }
        pull_posts(bx, bw, bd, bdep, z0, z0 + (n - 1) * pitch + bh) if n > 1
        @hw['basket'] += n
      when :spice
        n = pull_levels(o, ztop - z0, 95)
        pitch = (ztop - z0) / n.to_f
        n.times do |i|
          zz = z0 + i * pitch
          h_tray('spice_shelf', bx, bd + 6, zz, bw, bdep - 12, 34, 1.5, :steel)
          h_rod('spice_rail', bx, bd + bdep - 16, zz + 34, :x, bw, 4)
          h_rod('spice_rail_back', bx, bd + 10, zz + 34, :x, bw, 4)
          # spice jars (reusable cylinders) standing in a row along the shelf
          jd = 40.0
          cnt = [((bdep - 30) / (jd + 6)).floor, 1].max
          cnt.times { |k| h_rod('spice_jar', bx + (bw - jd) / 2.0, bd + 18 + k * ((bdep - 36 - jd) / [cnt - 1, 1].max), zz + 2, :z, 56, jd, :white, 12) }
        end
        # open wire frame instead of a solid plate: four corner posts through every shelf
        top = z0 + (n - 1) * pitch + 60
        [[bx - 1, bd + 8], [bx + bw - 5, bd + 8], [bx - 1, bd + bdep - 14], [bx + bw - 5, bd + bdep - 14]].each { |px, pd| h_rod('spice_post', px, pd, z0, :z, top - z0, 5) }
        [[z0 + 2], [top - 4]].each { |(zz)| [bd + 8, bd + bdep - 14].each { |pd| h_rod('spice_rim', bx - 1, pd, zz, :x, bw + 1, 4) } }
        @hw['spice_shelf'] += n
      when :tray
        # TRAY UNIT: baking trays / boards stand upright between tall wire dividers that run front to back (not bottle pegs)
        h_tray('tray_base', bx, bd + 6, z0, bw, bdep - 12, 22, 1.5, :steel)
        dh = [[ztop - z0 - 60, 460.0].min, 180.0].max
        cols = [((bw - 30) / 70.0).floor, 1].max
        (cols + 1).times do |c|
          xx = bx + 12 + c * ((bw - 30) / cols.to_f)
          [bd + 26, bd + bdep - 32].each { |pd| h_rod('tray_divider_post', xx, pd, z0 + 22, :z, dh, 6, :chrome, 8) }
          h_rod('tray_divider_rail', xx, bd + 26, z0 + 22 + dh - 6, :d, bdep - 52, 6, :chrome, 8)
          h_rod('tray_divider_rail', xx, bd + 26, z0 + 22 + dh * 0.5, :d, bdep - 52, 6, :chrome, 8)
        end
        h_rod('tray_front_rod', bx, bd + bdep - 20, z0 + 90, :x, bw, 5)
      when :trolley
        n = o[:levels] || 3
        pitch = (ztop - z0 - 40) / n.to_f
        n.times { |i| h_basket('basket', bx + 10, bd + 8, z0 + i * pitch, bw - 20, bdep - 16, [pitch - 30, 70].min, finish_key) }
        [[bx + 4, bd + 4], [bx + bw - 18, bd + 4], [bx + 4, bd + bdep - 18], [bx + bw - 18, bd + bdep - 18]].each do |px, pd|
          h_rod('trolley_post', px, pd, z0 - 4, :z, (n - 1) * pitch + 90, 14)
        end
        h_rod('trolley_handle', bx + 4, bd + bdep - 18, z0 + (n - 1) * pitch + 86, :x, bw - 8, 14)
        @hw['basket'] += n
      when :box
        n = o[:levels] || 2
        pitch = (ztop - z0) / n.to_f
        n.times { |i| h_tray('box', bx, bd + 8, z0 + i * pitch, bw, bdep - 16, [pitch - 30, 140].min, 2.0, :white) }
      when :laundry
        h_slab('laundry_frame_base', bx + 4, bd + 10, z0, bw - 8, bdep - 20, 6, :chrome)
        [[bx + 8, bd + 14], [bx + bw - 14, bd + 14], [bx + 8, bd + bdep - 20], [bx + bw - 14, bd + bdep - 20]].each do |px, pd|
          h_rod('laundry_post', px, pd, z0 + 6, :z, [(ztop - z0) * 0.72, 480].min, 6)
        end
        h_tray('laundry_bag', bx + 12, bd + 18, z0 + 10, bw - 24, bdep - 36, [(ztop - z0) * 0.68, 460].min, 1.0, :white)
        bagh = [(ztop - z0) * 0.68, 460].min
        ptop = z0 + 6 + [(ztop - z0) * 0.72, 480].min
        [bd + 14, bd + bdep - 20].each { |pd| h_rod('laundry_rim', bx + 8, pd, ptop - 3, :x, bw - 16, 6) } # top rim of the frame
        [bx + 8, bx + bw - 14].each { |px| h_rod('laundry_rim_side', px, bd + 14, ptop - 3, :d, bdep - 34, 6) }
        h_rod('laundry_handle', bx + 20, bd + bdep - 20, ptop + 14, :x, bw - 40, 10)
        [bx + 20, bx + bw - 30].each { |px| h_rod('laundry_handle_post', px, bd + bdep - 20, ptop - 3, :z, 17, 10) }
        h_rod('laundry_hoop', bx + 12, bd + 18, z0 + 10 + bagh - 2, :x, bw - 24, 5, :steel)
      when :plate
        # PLATE AND CUP PULL-OUT (the two-level wire basket of that name): plates stand on edge in a row of wire dividers on the lower level;
        # cups and glasses stand upside down over wire pegs on the upper level; a drip tray under each level; four posts carry the upper level.
        x0 = bx + 8
        iw = bw - 16
        d0 = bd + 14
        idep = bdep - 28
        # ---- lower level: plate rack
        h_tray('drip_tray', x0, d0, z0, iw, idep, 16, 1.5, :steel)
        zr = z0 + 22
        [d0, d0 + idep - 5].each { |dd| h_rod('rack_rim', x0, dd, zr, :x, iw, 5) }
        [x0, x0 + iw - 5].each { |xx| h_rod('rack_rim', xx, d0, zr, :d, idep, 5) }
        pdia = [[iw - 70, 270.0].min, 150.0].max                      # plate diameter the dividers are spaced for
        dvh = [pdia * 0.5, 110.0].min
        pitch = 30.0
        slots = [((idep - 30) / pitch).floor, 2].max
        (slots + 1).times do |k|
          dd = d0 + 12 + k * ((idep - 28) / slots.to_f)
          [x0 + iw * 0.22, x0 + iw * 0.78 - 4].each { |xx| h_rod('plate_divider', xx, dd, zr, :z, dvh, 4) }
          h_rod('plate_divider', x0 + iw * 0.22, dd, zr + dvh - 4, :x, iw * 0.56, 4)
          h_rod('plate_rest', x0 + 4, dd, zr - 2, :x, iw - 8, 4)
        end
        slots.times do |k|
          next unless k.even?

          dd = d0 + 12 + (k + 0.5) * ((idep - 28) / slots.to_f)
          h_rod('plate', x0 + (iw - pdia) / 2.0, dd - 2, zr + 3, :d, 4, pdia, :white, 24)
        end
        # ---- upper level: cup / glass rack
        zu = zr + pdia + 40.0
        if zu + 150 < bnd[:z1]
          [[x0, d0], [x0 + iw - 8, d0], [x0, d0 + idep - 8], [x0 + iw - 8, d0 + idep - 8]].each { |px, pd| h_rod('holder_post', px, pd, zr, :z, zu - zr + 60, 8, :chrome, 10) }
          h_tray('drip_tray', x0 + 8, d0 + 8, zu, iw - 16, idep - 16, 14, 1.5, :steel)
          zc = zu + 20
          [d0, d0 + idep - 5].each { |dd| h_rod('rack_rim', x0, dd, zc + 40, :x, iw, 5) }
          [x0, x0 + iw - 5].each { |xx| h_rod('rack_rim', xx, d0, zc + 40, :d, idep, 5) }
          cup = 78.0
          cols = [((iw - 20) / (cup + 14)).floor, 1].max
          rows = [((idep - 20) / (cup + 14)).floor, 1].max
          cols.times do |c|
            cx = x0 + iw * (c + 0.5) / cols
            h_rod('cup_rest', cx - 2, d0 + 4, zc, :d, idep - 8, 4)
            rows.times do |r|
              cdp = d0 + idep * (r + 0.5) / rows
              h_rod('cup_peg', cx - 2, cdp - 2, zc, :z, 70, 4)
              next unless (c + r).even?

              h_rod('cup', cx - cup / 2.0, cdp - cup / 2.0, zc + 6, :z, 86, cup, :white, 18) # a cup turned over its peg
            end
          end
          rows.times { |r| h_rod('cup_rest', x0 + 4, d0 + idep * (r + 0.5) / rows - 2, zc, :x, iw - 8, 4) }
        end
      end
    end

    # ------------------------------------------------------------------------------------------------ TALL_LARDER
    def larder_frame(fx0, fx1, fd0, fd1, zb, zt, levels, pitch, bh)
      t = 20.0
      h_slab('frame_carriage', fx0 - 6, fd0 - 4, zb - 12, fx1 - fx0 + 12, fd1 - fd0 + 8, 6, :steel)
      [[fx0 - 6, fd0 + 30], [fx1 - 6, fd0 + 30]].each { |px, pd| h_slab('carriage_tube', px, pd, zb - 26, 12, fd1 - fd0 - 60, 14, :steel) }
      [[fx0, fd0], [fx1 - t, fd0], [fx0, fd1 - t], [fx1 - t, fd1 - t]].each { |px, pd| h_slab('frame_upright', px, pd, zb, t, t, zt - zb, :chrome) }
      [[fx0, fd0], [fx1 - t, fd0]].each { |px, pd| h_between('frame_brace', [px + t / 2.0, pd + t / 2.0, zb + t], [px + t / 2.0, pd + t / 2.0 + (fd1 - fd0) * 0.6, zt - t], 5) }
      [zb, zt - t].each do |zz|
        h_slab('frame_bar', fx0, fd0, zz, fx1 - fx0, t, t, :chrome)
        h_slab('frame_bar', fx0, fd1 - t, zz, fx1 - fx0, t, t, :chrome)
        h_slab('frame_bar', fx0, fd0, zz, t, fd1 - fd0, t, :chrome)
        h_slab('frame_bar', fx1 - t, fd0, zz, t, fd1 - fd0, t, :chrome)
      end
      levels.times do |i|
        zz = zb + 30 + i * pitch
        [fx0 + 3, fx1 - 3 - 5].each { |sx| h_rod('basket_support', sx, fd0 + 10, zz - 6, :d, fd1 - fd0 - 20, 5) }
        h_basket('basket', fx0 + t + 3, fd0 + t + 3, zz, fx1 - fx0 - 2 * t - 6, fd1 - fd0 - 2 * t - 6, bh, finish_key)
      end
    end

    def door_baskets(dx0, dx1, zb, zt, levels)
      pitch = (zt - zb - 60) / levels.to_f
      bh = [pitch - 60, 90].min
      levels.times do |i|
        zz = zb + 40 + i * pitch
        h_basket('door_basket', dx0 + 30, @cd - 96, zz, dx1 - dx0 - 60, 92, bh, finish_key)
        [dx0 + 34, dx1 - 34 - 12].each { |px| h_brk('door_bracket', px, @cd - 30, zz - 4, 30, 30, 2.5, 12, :zinc, front: true) }
      end
    end

    def fam_larder(o)
      b = bnd
      zf, hf = full_front
      cw = b[:x1] - b[:x0]
      cd = b[:d1] - b[:d0]
      len = rail_len(cd + 30)
      b = front_anchor(b, len, (o[:mode] || :attached) == :attached) # the mechanism is mounted from the FRONT: it ends right behind its front, the spare depth stays at the back
      travel = len * 0.92
      mode = o[:mode] || :attached
      levels = [[o[:levels] || 5, ((b[:z1] - b[:z0]) / 260).floor].min, 2].max
      zb = b[:z0] + SL_H + 14
      zt = b[:z1] - 20
      pitch = (zt - zb - 150) / [levels - 1, 1].max
      fdep = mode == :attached ? [len - 20, cd - 6].min : cd - 120
      fx0 = b[:x0] + 16
      fx1 = b[:x1] - 16
      fd0 = b[:d0] + 6
      pos = :side_r
      if mode == :attached
        slide_fixed_mid(b[:x0], b[:x1], b[:d0], b[:z0] + 6, len, travel)
        h_chan('top_guide', b[:x0] + 20, b[:d0], b[:z1] - 20, len, 16, 22, 1.5, 1, :zinc)
        a = asm('pullout', MotionProfiles.linear_slide([0, travel, 0]))
        in_asm(a) do
          slide_inner(b[:x0], b[:x1], b[:d0], b[:z0] + 6, len)
          h_slab('top_carriage', b[:x0] + 22, b[:d0] + 40, b[:z1] - 16, 12, 60, 18, :zinc)
          [b[:d0] + 55, b[:d0] + 95].each { |rd| h_rod('top_roller', b[:x0] + 20, rd, b[:z1] - 20, :x, 16, 20, :dark, 14) }
          larder_frame(fx0, fx1, fd0, fd0 + fdep, zb, zt, levels, pitch, 110)
          front('door', @gap / 2.0, @w - @gap, zf, hf, pos, grain: :z)
          front_connectors(b[:x0] + 12, b[:x1] - 12, zb + 4)
        end
        @hw['slide_pair'] += 1
      else
        slide_frame = o[:frame] == :slide
        da = asm('door', MotionProfiles.hinge_rotate([@gap / 2.0, @cd + @ft, 0], -90, slide_frame ? [0.0, 0.4] : [0.0, 1.0]).merge(door_slide ? { 'slide' => door_slide } : {}))
        in_asm(da) do
          front('door', @gap / 2.0, @w - @gap, zf, hf, pos, grain: :z)
          door_baskets(@gap / 2.0, @w - @gap / 2.0, zb, zt, [levels, 5].min) unless slide_frame # door baskets only when the frame stays fixed
          @cd && door_hinges(0, 1, @gap / 2.0, @w - @gap, zf, hf)
        end
        door_plates(0, 1, @gap / 2.0, @w - @gap, zf, hf)
        if slide_frame
          slide_fixed_mid(b[:x0], b[:x1], b[:d0], b[:z0] + 6, len, travel, [0.4, 1.0])
          fa = asm('frame', MotionProfiles.linear_slide([0, travel, 0], [0.4, 1.0]))
          in_asm(fa) do
            slide_inner(b[:x0], b[:x1], b[:d0], b[:z0] + 6, len)
            larder_frame(fx0, fx1, fd0, fd0 + [fdep, len - 120].min, zb, zt, levels, pitch, 110)
          end
        else
          larder_frame(fx0, fx1, fd0, fd0 + fdep, zb, zt, levels, pitch, 110)
        end
        @hw['hinge'] += hinge_count(hf)
      end
      @hw['basket'] += levels
    end

    # ------------------------------------------------------------------------------------------------ WASTE_PULL_OUT
    def fam_waste(o)
      b = bnd
      zf, hf = full_front
      cw = b[:x1] - b[:x0]
      cd = b[:d1] - b[:d0]
      len = rail_len(cd + 30)
      b = front_anchor(b, len, (o[:mode] || :attached) == :attached) # the mechanism is mounted from the FRONT: it ends right behind its front, the spare depth stays at the back
      travel = len * 0.92
      sz = b[:z0] + 6
      swing = (o[:mode] || :attached) == :swing
      n = cw > 400 ? 2 : 1
      slide_fixed_mid(b[:x0], b[:x1], b[:d0], sz, len, travel, swing ? [0.4, 1.0] : nil)
      damper_fixed(b[:x0], b[:x1], b[:d0], sz + 8)
      da = nil
      if swing
        da = asm('door', MotionProfiles.hinge_rotate([@gap / 2.0, @cd + @ft, 0], -90, [0.0, 0.4]).merge(door_slide ? { 'slide' => door_slide } : {}))
        in_asm(da) do
          front('door', @gap / 2.0, @w - @gap, zf, hf, :top, grain: :z)
          door_hinges(0,1,@gap/2.0,@w-@gap,zf,hf)
        end
        door_plates(0, 1, @gap / 2.0, @w - @gap, zf, hf)
        @hw['hinge'] += hinge_count(hf)
      end
      a = asm('pullout', MotionProfiles.linear_slide([0, travel, 0], swing ? [0.4, 1.0] : nil))
      in_asm(a) do
        slide_inner(b[:x0], b[:x1], b[:d0], sz, len)
        front('door', @gap / 2.0, @w - @gap, zf, hf, :top, grain: :z) unless swing
        front_connectors(b[:x0] + 12, b[:x1] - 12, sz + SL_H + 4) unless swing
        zb = sz + SL_H + 2
        bx = b[:x0] + 14
        bw_all = cw - 28
        h_tray('bin_carrier', bx, b[:d0] + 6, zb, bw_all, [len - 12, cd - 6].min, 14, 2.0, :steel)
        # two bins stand ONE BEHIND THE OTHER along the depth (each as wide as the carrier), never side by side across the width
        gap = 12.0
        bw = bw_all
        bdep_all = [len - 60, 440].min
        bdep = (bdep_all - (n - 1) * gap) / n
        bh = [[(b[:z1] - zb) * 0.66, 250.0].max, 400.0].min
        n.times do |i|
          xx = bx
          dd = b[:d0] + 24 + i * (bdep + gap)
          h_bin('bin', xx, dd, zb + 14, bw, bdep, bh)
          lid = asm("lid#{i + 1}", MotionProfiles.lift([xx + bw / 2.0, dd + 3, zb + 14 + bh], -62, swing ? [0.84, 1.0] : [0.66, 1.0]))
          in_asm(lid) do
            h_slab('bin_lid', xx - 3, dd + 3, zb + 14 + bh, bw + 6, bdep - 1, 3, :plastic) # starts at the hinge axis: nothing behind it to swing into the bin
            h_rod('lid_grip', xx + bw * 0.3, dd + bdep - 6, zb + 14 + bh + 3, :x, bw * 0.4, 8, :plastic)
          end
          h_slab('bin_hinge', xx + bw * 0.2, dd - 4, zb + 14 + bh - 10, 22, 6, 18, :dark)
          h_slab('bin_hinge', xx + bw * 0.8 - 22, dd - 4, zb + 14 + bh - 10, 22, 6, 18, :dark)
        end
        @hw['waste_bin_unit'] += n
      end
      @hw['slide_pair'] += 1
    end

    # ------------------------------------------------------------------------------------------------ DISH_RACK
    # two-level wire rack: side rods, base rods, plate loops, drip tray, side rail + damper
    def dish_rack_body(b, levels = 2, inset = 6)
      w = b[:x1] - b[:x0]
      dep = b[:d1] - b[:d0]
      h = b[:z1] - b[:z0]
      x0 = b[:x0] + inset
      x1 = b[:x1] - inset
      d0 = b[:d0] + 14
      d1 = b[:d1] - 14
      pitch = (h - 70) / levels
      levels.times do |k|
        z = b[:z0] + 50 + k * pitch
        [x0, x1 - 5].each { |xx| h_rod('rack_side', xx, d0, z, :d, d1 - d0, 5) }
        n = ((d1 - d0) / 55.0).floor
        (n + 1).times { |i| h_rod('rack_base', x0, d0 + i * ((d1 - d0 - 4) / n.to_f), z - 4, :x, x1 - x0, 4) }
        step = 44.0
        m = ((x1 - x0 - 20) / step).floor
        m.times do |i|
          xx = x0 + 12 + i * ((x1 - x0 - 24) / [m - 1, 1].max)
          h_rod('rack_loop', xx, d0 + 6, z, :z, 78, 4)
          h_rod('rack_loop', xx, d1 - 10, z, :z, 78, 4)
          h_rod('rack_loop_top', xx, d0 + 6, z + 74, :d, d1 - d0 - 16, 4)
        end
        h_rod('rack_rim', x0, d0, z + 30, :x, x1 - x0, 5)
        h_rod('rack_rim', x0, d1 - 5, z + 30, :x, x1 - x0, 5)
      end
      h_tray('drip_tray', x0 + 2, d0 + 4, b[:z0] + 14, x1 - x0 - 4, d1 - d0 - 8, 14, 1.5, :steel)
    end

    # fixed side rails + soft-close dampers that the rack runs on (stay with the cabinet)
    def dish_rack_fixed(b, inset = 6, rails: true, dampers: true)
      h = b[:z1] - b[:z0]
      x0 = b[:x0] + inset
      x1 = b[:x1] - inset
      d0 = b[:d0] + 14
      d1 = b[:d1] - 14
      if rails
        [x0 - 2, x1 - 2].each { |xx| h_slab('rack_rail', xx, d0 - 4, b[:z0] + h * 0.55, 4, d1 - d0 + 8, 30, :steel) }
      end
      return unless dampers

      [x0 + 10, x1 - 34].each { |xx| h_damper('rack_damper', xx, d0 + 6, b[:z0] + h * 0.86, [(d1 - d0) - 120, 200].min) }
    end

    # Pull-down dish rack behind a glass flap: TWO independent mechanisms.
    #  1. the glass flap: awning flap on its own telescopic lever arms (flap_arms), opens first (phase 0..0.35);
    #  2. the rack: hung on a PARALLELOGRAM of two equal arms per side, pivoted on a fixed side plate at the front-top. The arms swing
    #     down and the carrier (a tall side rail that holds the rack) translates without tilting, so the rack comes down and out of the
    #     front level. Arm length / angles are solved from the wanted travel; carrier and arms use the same angle every frame.
    DISH_ARM_START = 35.0 # degrees behind the vertical (rack stored)
    DISH_ARM_END = 120.0  # degrees in front of the vertical (rack down in front of the cabinet)

    # pull-down single tray: figures of the supplier drawing (clear depth, tray above the bottom, height of the swing gear, load)
    IMOVE_TRAY = { min_depth: 270.0, z_min: 25.0, gear_h: 380.0, load_kg: 8 }.freeze

    def fam_dish(o)
      b = bnd
      zf, hf = full_front
      if o[:flap]
        # PULL-DOWN ON SWING ARMS (as a pull-down shelf lift): the rack hangs on two equal parallel arms per side, pivoted on a plate fixed to the
        # side panel. The arms swing forward over the top, so the rack travels on a CIRCULAR ARC - a little up, out through the front, then down
        # in front of the cabinet - and stays level all the way (parallelogram). Arm length and start angle are solved from the cabinet depth:
        # the arc is back at its starting height only when the whole rack is clear of the carcass front, so the rack never drops inside the box.
        rad = Math::PI / 180.0
        dep = b[:d1] - b[:d0]
        phi0 = DISH_ARM_START                                        # arm angle behind the vertical with the rack stored
        th1 = DISH_ARM_END                                           # arm angle in front of the vertical with the rack down
        r = (dep + 10.0) / (2.0 * Math.sin(phi0 * rad))
        rise = r * (1.0 - Math.cos(phi0 * rad))
        rb = b.merge(z1: b[:z1] - rise - 12.0)                       # head room for the top of the arc
        if o[:tray]
          # SINGLE TRAY (iMove type): the unit keeps its bottom; the tray rests IMOVE_TRAY[:z_min] above it and the swing gear is IMOVE_TRAY[:gear_h] high
          raise MechanismError.new(:too_shallow, "the pull-down tray needs #{IMOVE_TRAY[:min_depth].round} mm clear inside depth (this unit: #{(@cd - @bk).round}) | رف السحب لأسفل يحتاج عمق داخلي #{IMOVE_TRAY[:min_depth].round} مم") if @cd - @bk < IMOVE_TRAY[:min_depth] - 0.5

          rb = rb.merge(z0: b[:z0] + IMOVE_TRAY[:z_min] - 12.0, z1: [b[:z0] + IMOVE_TRAY[:z_min] - 12.0 + IMOVE_TRAY[:gear_h], rb[:z1]].min)
        else
          dish_rack_fixed(rb, 56, rails: false, dampers: false)
        end
        ja = [b[:d0] + 50.0, rb[:z1] - 70.0]                         # upper-rear arm joint on the rack (depth, height), rack stored
        pv = [ja[0] + r * Math.sin(phi0 * rad), ja[1] - r * Math.cos(phi0 * rad)] # its fixed pivot on the side plate
        second = 70.0                                                # the second arm stands this far in front of the first, parallel to it
        n = 41
        samples = (0...n).map { |i| i / (n - 1.0) }
        angs = samples.map { |u| -phi0 + (phi0 + th1) * Mechanisms.phase({ 'phase' => [0.35, 1.0] }, u) }
        keys_r = samples.each_index.map { |i| [samples[i], pv[0] + r * Math.sin(angs[i] * rad) - ja[0], pv[1] + r * Math.cos(angs[i] * rad) - ja[1], 0] }
        @dish_dbg = { r: r.round(1), rise: rise.round(1), out: keys_r.map { |k| k[1] }.max.round(1), down: (-keys_r.last[2]).round(1), end_out: keys_r.last[1].round(1) }
        # lanes from the side panel: the flap's own lift-arm hardware occupies roughly 3-27 mm; plate, arms and carrier start at 40+
        x_pl = ix0 + 38.0
        x_arm = ix0 + 44.0
        x_car = ix0 + 54.0
        mir = ->(x, wd) { ix1 - (x - ix0) - wd }
        [x_pl, mir.call(x_pl, 4.0)].each_with_index do |xp, si|
          h_slab('rack_side_plate', xp, pv[0] - 30, pv[1] - 34, 4, second + 60, 68, :zinc)
          [pv[0] - 18, pv[0] + second + 2].each do |dd|
            start = si.zero? ? ix0 : xp + 4
            span = si.zero? ? xp - ix0 : ix1 - (xp + 4)
            h_slab('rack_mount_standoff', start, dd, pv[1] - 8, span, 16, 16, :zinc)
          end
        end
        [x_arm, mir.call(x_arm, 8.0)].each_with_index do |xa, si|
          [0.0, second].each_with_index do |od, k|
            arm = asm("rack_arm#{si}#{k}", MotionProfiles.pose([xa + 4, pv[0] + od, pv[1]], samples.each_index.map { |i| [samples[i], 0, 0, angs[i] + phi0] }))
            in_asm(arm) do
              h_between('rack_arm', [xa + 4, pv[0] + od, pv[1]], [xa + 4, ja[0] + od, ja[1]], 14, :steel)
              h_rod('rack_arm_pin', xa - 2, pv[0] + od - 6, pv[1] - 6, :x, 12, 12, :dark, 12)
            end
          end
        end
        ra = asm('rack', MotionProfiles.pose([@w / 2.0, ja[0], ja[1]], keys_r))
        in_asm(ra) do
          if o[:tray]
            tx0 = x_car + 6
            tw = mir.call(x_car, 6.0) - tx0
            h_slab('tray', tx0, b[:d0] + 8, rb[:z0], tw, b[:d1] - b[:d0] - 16, 4, :zinc)
            h_slab('tray_rim', tx0, b[:d0] + 8, rb[:z0] + 4, tw, 3, 56, :zinc)
            h_rod('tray_rail', tx0, b[:d1] - 14, rb[:z0] + 46, :x, tw, 10, :chrome, 12)
            h_slab('tray_handle', @w / 2.0 - 30, b[:d1] - 22, rb[:z0] - 70, 60, 16, 74, :dark)
          else
            dish_rack_body(rb, 2, 62)
            dish_decor(rb, 2)
          end
          [x_car, mir.call(x_car, 6.0)].each do |xc|
            h_slab('rack_carrier', xc, ja[0] - 22, rb[:z0] + 30, 6, second + 44, rb[:z1] - rb[:z0] - 60, :steel)
            [0.0, second].each { |od| h_rod('rack_arm_pin', xc - 8, ja[0] + od - 6, ja[1] - 6, :x, 14, 12, :dark, 12) }
          end
          (o[:tray] ? 0 : 2).times do |k|
            zl = rb[:z0] + 50 + k * ((rb[:z1] - rb[:z0] - 70) / 2.0) + 6
            [[x_car + 6, ix0 + 65.0], [ix1 - 65.0, mir.call(x_car, 6.0)]].each { |xa, xb| h_slab('rack_hanger', [xa, xb].min, ja[0] + 10, zl - 4, (xb - xa).abs, 28, 8, :steel) }
          end
          h_rod('rack_pull', ix0 + 90, b[:d1] - 16, rb[:z0] + 36, :x, ix1 - ix0 - 180, 12, :dark, 12) unless o[:tray]
        end
        flap_arms(zf, hf, single: true, phase: [0.0, 0.35])
        a = asm('flap', MotionProfiles.pose([@w / 2.0, @cd + @ft, zf + hf], flap_keys(*flap_path([0.0, 0.35]))))
        in_asm(a) { front('flap', @gap / 2.0, @w - @gap, zf, hf, :bottom, grain: :z, glass: !o[:tray]) } # glass-front dish cabinet; a plain flap in front of the tray
        @hw['lift_up'] += 1
      else
        dish_rack_fixed(b, 6)
        dish_rack_body(b, 2)
        dish_decor(b, 2)
        doors({ t: :doors }, zf, hf, false)
      end
      @hw[o[:hw] || 'dish_rack'] += 1
    end

    # ------------------------------------------------------------------------------------------------ WARDROBE_PULL_OUT
    def fam_trouser(_o)
      b = bnd
      cd = b[:d1] - b[:d0]
      len = rail_len(cd + 30)
      travel = len * 0.92
      z = b[:z0] + [(b[:z1] - b[:z0]) * 0.38, 900.0].max
      z = [z, b[:z1] - 260].min
      # a trouser rack lives BEHIND the wardrobe doors: the doors open first, then the rack runs out between them (no loose front of its own)
      zf, hf = full_front
      @door_phase = [0.0, 0.3]
      doors({ t: :doors }, zf, hf, false)
      @door_phase = nil
      ph = [0.35, 1.0]
      slide_fixed_mid(b[:x0], b[:x1], b[:d0] + 10, z, len - 10, travel, ph)
      a = asm('trouser_rack', MotionProfiles.linear_slide([0, travel, 0], ph))
      in_asm(a) do
        slide_inner(b[:x0], b[:x1], b[:d0] + 10, z, len - 10)
        h_rod('rack_pull', b[:x0] + 40, b[:d0] + len - 22, z + SL_H + 20, :x, b[:x1] - b[:x0] - 80, 14, :dark, 16)
        bx0 = b[:x0] + 14
        bx1 = b[:x1] - 14
        h_slab('rack_side_plate', bx0, b[:d0] + 16, z + SL_H, 3, len - 30, 62, :steel)
        h_slab('rack_side_plate', bx1 - 3, b[:d0] + 16, z + SL_H, 3, len - 30, 62, :steel)
        d = b[:d0] + 40
        while d < b[:d0] + len - 30
          h_rod('trouser_bar', bx0, d, z + SL_H + 44, :x, bx1 - bx0, 8, :chrome)
          d += 44
        end
      end
      @hw['slide_pair'] += 1
    end

    def fam_liftrail(_o)
      b = bnd
      w = b[:x1] - b[:x0]
      top = b[:z1] - 60
      pivot_d = b[:d0] + 50
      dep = b[:d1] - pivot_d - 30
      [b[:x0], b[:x1] - 16].each { |xx| h_brk('lift_bracket', xx, b[:d0], top - 60, 30, 70, 2.5, 16, :zinc) }
      [b[:x0] + 6, b[:x1] - 16].each { |xx| h_pin('lift_pivot', xx, pivot_d, top - 12, 8, 10) }
      keys = [[0.0, 0, 0, 0], [1.0, 0, 0, 32]]
      a = asm('lift_rail', MotionProfiles.lift([(b[:x0] + b[:x1]) / 2.0, pivot_d, top], 32))
      in_asm(a) do
        [b[:x0] + 10, b[:x1] - 20].each do |xx|
          h_slab('lift_arm', xx, pivot_d - 10, top - 26, 10, dep, 24, :zinc)
          h_slab('lift_arm_rib', xx + (xx < b[:x0] + 40 ? 10 : -3), pivot_d - 10, top - 26, 3, dep, 8, :zinc)
        end
        h_rod('lift_rail_bar', b[:x0] + 8, b[:d1] - 60, top - 45, :x, w - 16, 25, :chrome, 12)
      end
      _ = keys
      h_damper('lift_damper', b[:x0] + 24, pivot_d + 20, top - 10, 100)
    end
  end
end
