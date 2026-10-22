# frozen_string_literal: true

module EGC
  # L-shaped base corner unit (square plan S x S with a notch at the inside corner, two doors).
  # hand 'L': unit at the LEFT end of run A (notch at front-right); 'R': mirrored for the right end.
  class CornerCabinet < Cabinet
    private

    def fx(x, w = 0)
      @flip ? @w - x - w : x
    end

    def carcass
      @flip = @s[:hand].to_s == 'R'
      @w = [@w, @cd + 150].max
      t = @t
      bk = @bk
      s = @w
      cdp = @cd
      hc = @hc
      z0 = @z0
      pn('back', fx(0, s), 0, z0, s, bk, hc, 'back', grain: :z)
      pn('back', fx(0, bk), bk, z0, bk, s - bk, hc, 'back', grain: :z)
      pn('side_r', fx(s - t, t), bk, z0, t, cdp - bk, hc, 'carcass', grain: :z, eb: [1, 0])
      pn('side_f', fx(bk, cdp - bk), s - t, z0, cdp - bk, t, hc, 'carcass', grain: :z, eb: [1, 0])
      poly = [[bk, bk], [s - t, bk], [s - t, cdp], [cdp, cdp], [cdp, s - t], [bk, s - t]]
      pts = poly.map { |x, d| [fx(x), d] }
      pts.reverse! if @flip
      %w[bottom top].each do |part|
        z = part == 'bottom' ? z0 : z0 + hc - t
        x0 = pts.map(&:first).min
        d0 = pts.map(&:last).min
        side = pts.map(&:first).max - x0
        solid = lambda do |ents|
          f = ents.add_face(pts.map { |x, d| Geo.p3(x - x0, d - d0, 0) })
          f.pushpull((f.normal.z >= 0 ? 1 : -1) * Geo.mm(t)) if f
        end
        pn(part, x0, d0, z, side, pts.map(&:last).max - d0, t, 'carcass', grain: :x, eb: [1, 0], solid: solid, notes: "L-shaped (inner corner cut #{(s - t - cdp).round} x #{(s - t - cdp).round})")
      end
      unless @s[:mech] # a carousel turns where the fixed shelf would stand
        # the shelf follows the whole L of the unit (both legs), 20 mm behind the fronts, 1 mm clear of the boards
        sp = [[bk + 1, bk + 1], [s - t - 1, bk + 1], [s - t - 1, cdp - 20], [cdp - 20, cdp - 20], [cdp - 20, s - t - 1], [bk + 1, s - t - 1]].map { |x, d| [fx(x), d] }
        sp.reverse! if @flip
        sx0 = sp.map(&:first).min
        sd0 = sp.map(&:last).min
        ssolid = lambda do |ents|
          f = ents.add_face(sp.map { |x, d| Geo.p3(x - sx0, d - sd0, 0) })
          f.pushpull((f.normal.z >= 0 ? 1 : -1) * Geo.mm(t)) if f
        end
        pn('shelf', sx0, sd0, z0 + hc / 2.0, sp.map(&:first).max - sx0, sp.map(&:last).max - sd0, t, 'carcass', grain: :x, eb: [1, 0], solid: ssolid,
           notes: "L-shaped shelf (inner corner cut #{(s - t - cdp + 19).round} x #{(s - t - cdp + 19).round})")
      end
      @hw['shelf_pin'] += 4
      @hw['leg'] += 5 if @plinth > 0 && @kind == :base
    end

    CORNER_FOLD_GAP = 4.0 # mm between the two fronts when door 2 lies folded on door 1 (bumpers / handle)

    def cells
      s = @w
      cdp = @cd
      z0 = @z0
      hc = @hc
      zf = z0 + @gap / 2.0
      hf = hc - @gap
      wdt = s - cdp - @gap
      # BI-FOLD CORNER DOORS, as on the owner's reference video of an L corner unit: door 1 (front of arm 1) is hinged on the carcass at the
      # arm end; door 2 (front of arm 2) hangs on door 1's free edge at the inside corner and has NO hinge on the carcass.
      # Opening (the owner's video, frame by frame - 1.28.51): the pull on door 1 at the inside corner swings it out on its hinges and, at
      # the same time, door 2 folds in BEHIND it, back to back (the two backs together, the fronts outside). Both turn 90 degrees over the
      # same stroke, so door 2 never enters the carcass: it folds in only as far as door 1 has come out. The whole L-shaped opening is
      # free and the pack stands square at the end of arm 1.
      mech = @s[:mech] # with a carousel inside, the doors are fully open before it starts to turn (3/4 baskets included)
      # door 1 turns about its own front outer edge like any door; door 2 lies behind it, so the open pack stands inside the unit's width
      # Door 1 hangs on two concealed hinges like every other door (cup in the door, plate on the gable, articulated arm). Like a real
      # concealed hinge the door is drawn back while it turns ('slide'): open, the pack stands 3 mm off the carcass front, not floating.
      mv1 = { 'type' => 'rot', 'pivot' => [fx(s - @gap / 2.0), cdp + @ft, 0], 'axis' => [0, 0, 1], 'deg' => @flip ? -90 : 90, 'phase' => mech ? [0.0, 0.35] : [0.0, 1.0],
              'slide' => [0, -(@ft - DOOR_OPEN_GAP), 0] }
      a1 = asm('door1', mv1)
      hz = hinge_zs(zf, hf)
      d2 = s - (@dd) - @gap
      hpos = @kind == :wall ? :bottom : :top # the handle edge: under a wall unit's door, on top of a base unit's
      ph2 = @c['handle'] == 'profile' ? @c['profile_h'].to_f : 0.0 # door 2 carries the same edge profile: its board is shorter by the profile
      in_asm(a1) do
        # the two cups of the carcass hinges, at the arm-end edge of door 1 (the bi-fold hinges between the doors are bored to their own template)
        front('door', fx(cdp + @gap / 2.0, wdt), wdt, zf, hf, hpos, grain: :z, bore_abs: hz.map { |z| [fx(s - @gap / 2.0 - 21.5), z] })
        hz.each { |z| MechParts.cup_hinge(@cur, fx(s - @gap / 2.0 - 21.5) + (@flip ? 17.5 : 0.0), cdp, z, @flip ? :left : :right) } # the part is drawn off its put point toward -x: shifted so it stays on the door
        # the plates of the bi-fold hinges on the back of door 1, next to the inside corner
        hz.each { |z| h_slab('bifold_plate', fx(cdp + @gap / 2.0 + 8, 44), cdp - 4, z - 20, 44, 4, 40, :zinc) }
        fold = cdp - CORNER_FOLD_GAP / 2.0 # fold axis where the two BACKS meet: folded, the backs lie CORNER_FOLD_GAP apart
        a2 = asm('door2', { 'type' => 'rot', 'pivot' => [fx(fold), fold, 0], 'axis' => [0, 0, 1], 'deg' => @flip ? -90 : 90, 'phase' => mech ? [0.0, 0.35] : [0.0, 1.0] })
        in_asm(a2) do
          pn('door', @flip ? @w - cdp - @ft : cdp, @dd + @gap / 2.0, hpos == :bottom ? zf + ph2 : zf, @ft, [d2, 100].max, hf - ph2, 'front', grain: :z, eb: [2, 2], eb_t: 2.0)
          pn('profile', @flip ? @w - cdp - @ft : cdp, @dd + @gap / 2.0, hpos == :bottom ? zf : zf + hf - ph2, @ft, [d2, 100].max, ph2, 'profile', role: 'hw') if ph2.positive?
          # BI-FOLD HINGES between the two doors (corner bi-fold hinge, as Blum CLIP top 60 deg: the cup in door 2, the plate on door 1 -
          # paired with the carcass hinges of door 1): the cup let into the back of door 2 (nothing stands proud of it, folded or not)
          d2c = @dd + @gap / 2.0 + 24.0
          hz.each { |z| h_rod('bifold_cup', fx(cdp, 12), d2c - 17.5, z - 17.5, :x, 12, 35, :zinc, 20) }
        end
      end
      corner_hinge_arms(mv1, hz, s)
      @hw['hinge'] += 2
      @hw['hinge_bifold'] += 2
      @hw['profile_mm'] += d2 if ph2.positive? # door 1's profile is counted by #front
      @hw['corner_l'] += 1
    end

    # the carcass half of door 1's hinges: mounting plates on the arm-end gable + the two-link arms that follow the cup (as #door_plates)
    def corner_hinge_arms(mv, hz, s)
      left = @flip
      xs = left ? @t : s - @t
      xc = fx(s - @gap / 2.0 - 21.5)
      plate_x = left ? xs + 1.5 : xs - 1.5
      plate_d = @cd - 22
      hz.each_with_index do |zc, i|
        MechParts.hinge_mount_plate(@e, left ? xs : xs - 3, @cd - 44, zc - 21)
        pp = Geo.p3(plate_x, plate_d, zc)
        cup0 = Geo.p3(xc, @cd, zc)
        dmax = (0..10).map do |k|
          c = Mechanisms.move_transform(mv, k / 10.0) * cup0
          Math.hypot((c.x - pp.x).to_mm, (c.y - pp.y).to_mm)
        end.max
        ll = [dmax * 0.53, 14.0].max
        2.times do |li|
          spec = { 'type' => 'hinge_ik', 'link' => li, 'plate' => [plate_x, plate_d, zc], 'cup' => [xc, @cd, zc], 'l1' => ll, 'l2' => ll, 'side' => left ? 1.0 : -1.0, # elbow inside the unit
                   'dpivot' => mv['pivot'], 'daxis' => mv['axis'], 'ddeg' => mv['deg'], 'dslide' => mv['slide'], 'phase' => mv['phase'] }
          a = asm("hinge_arm0_#{i}_l#{li}", spec)
          in_asm(a) { MechParts.hinge_link(a.entities, ll, li) }
          a.transformation = Mechanisms.hinge_ik_tr(spec, 0.0)
        end
      end
    end

    # CORNER CAROUSEL (3/4 turning shelves): it lives in the L-shaped corner base, as on real corner units - a pole near the inner corner, 3/4
    # wire shelves whose missing quarter faces the door notch when closed, turning out through the open corner doors. Generic E.G.C geometry.
    def mech_build(id)
      it = Mechanisms.item(id)
      return super unless it && it[:mb] == :carousel

      cells
      o = it[:o]
      cc = @cd - 150.0
      cx = fx(cc)
      r = cc - @bk - 28.0
      zb = @z0 + @t + 12
      zt = @z0 + @hc - @t - 10
      h = zt - zb
      h_slab('pole_plate', cx - 45, cc - 45, zb, 90, 90, 4, :zinc)
      h_slab('pole_plate', cx - 45, cc - 45, zt - 4, 90, 90, 4, :zinc)
      h_rod('pole', cx - 20, cc - 20, zb + 4, :z, h - 8, 40, :chrome, 16)
      h_rod('pole_bearing', cx - 34, cc - 34, zb + 4, :z, 14, 68, :steel, 20)
      h_rod('pole_bearing', cx - 34, cc - 34, zt - 18, :z, 14, 68, :steel, 20)
      lv = [[o[:levels] || 2, (h / 200).floor].min, 1].max
      start = @flip ? 180 : 90
      a = asm('carousel', MotionProfiles.rotate([cx, cc, 0], @flip ? -180 : 180, [0.4, 1.0]))
      in_asm(a) do
        lv.times do |i|
          z = zb + 30 + (lv > 1 ? i * ((h - 120) / (lv - 1).to_f) : 0)
          h_disc('carousel_shelf', cx, cc, z, r, 270, start, 4.0, finish_key, 46)
          h_rod('carousel_hub', cx - 32, cc - 32, z, :z, 24, 64, :steel, 14)
          3.times { |k| ang = (start + 45 + k * 90).degrees; h_between('shelf_support', [cx + 36 * Math.cos(ang), cc + 36 * Math.sin(ang), z + 2], [cx + (r - 6) * Math.cos(ang), cc + (r - 6) * Math.sin(ang), z + 2], 7, :steel) }
        end
        h_rod('carousel_sleeve', cx - 28, cc - 28, zb + 6, :z, h - 12, 56, :steel, 16)
      end
      @hw['basket'] += lv
      @hw[o[:key]] += 1 if o[:key]
    end

    def plinth_board
      return if @plinth <= 0

      s = @w
      # the plinth follows the two FRONTS of the L only, its face flush with the carcass front (as Cabinet#plinth_board): one piece along
      # leg 1 from the inside corner to the end, one along leg 2 - they meet at the inside corner, nothing runs through under the unit.
      pd = @cd - @t
      pn('plinth', fx(pd, s - pd), pd, 0, s - pd, @t, @plinth, 'plinth', grain: :x, eb: [1, 0], eb_t: 2.0)
      pn('plinth', fx(pd, @t), @cd, 0, @t, s - @cd, @plinth, 'plinth', grain: :d, eb: [1, 0], eb_t: 2.0)
    end
  end

  class Cabinet
    class << self
      alias_method :build_plain, :build

      def build(parent, spec, cfg)
        klass = spec[:corner] ? CornerCabinet : self
        klass.new(spec, cfg).build(parent)
      end
    end
  end
end
