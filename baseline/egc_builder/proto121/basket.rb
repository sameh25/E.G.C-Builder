# frozen_string_literal: true

Sketchup.require(File.join(File.dirname(__FILE__), 'basket_data'))

module EGC
  module Proto121
    # PROTOTYPE P1 - EGC_WIRE_BASKET_PULLOUT (review scene, not integrated). Everything below is read from Component_54.skp (two-tier wire-basket tower on a 300 x 560 base unit):
    #   * ONE telescopic side slide per tier on the RIGHT side only (top tier slide at the basket top, bottom tier slide at the basket bottom), both joined by four flat vertical
    #     posts (24 x 6 x 461 mm) - the whole tower is a cantilever carried by the two slides;
    #   * slide members (3 stages + end brackets): fixed rail 6 x 26 x 450 on the cabinet, cage 9 x 18 x 427 (I-section), moving outer rail 10 x 28 x 455 + liner 6 x 26 x 450,
    #     brackets 29 x 15 x 30 at both ends of the moving rail; profile loops copied from the model section;
    #   * wire baskets 220 x 437 x 118 (wire D 4): floor perimeter + 15 cross wires on a 24 mm pitch, four wall levels + rim, corner verticals.
    # POSES: the model is saved with the tower EXTENDED (moving rail front at y = -304.7 against the cabinet front y = 0): 335 mm of travel from the closed position, where the
    #   moving rail front coincides with the fixed rail front (y = 30.3) and the basket sits 39 mm behind the front plane.  Only these two poses are proven; members are
    #   interpolated linearly, the cage is kept at its measured offset inside the moving rail (staging between the poses NOT proven).
    # NOT MODELLED (not visible/measurable in the reference): soft-close, locks, clips, drilling, the flared basket ends, rounded wire corners.
    module BasketProto
      module_function

      TRAVEL = 335.0
      CAB_W = 300.0
      CAB_D = 560.0
      PANEL_T = 16.0
      Z_OFF = 100.0       # reference z of the carcass bottom (legs below, not modelled)
      WIRE_D = 4.0

      def dd(y) = CAB_D - y   # reference y (0 at the front plane, + into the cabinet) -> builder d (toward the room)

      def build(model = Sketchup.active_model)
        g = Proto121
        model.start_operation('E.G.C prototype P1 - wire basket', true)
        root = model.entities.add_group
        root.name = 'EGC_WIRE_BASKET_PULLOUT'
        re = root.entities
        rig = Proto121::Rig.new('EGC_WIRE_BASKET_PULLOUT')
        zb = ->(z) { z - Z_OFF }
        ps = lambda do |nm, x, d, z, sx, sd, sz|
          pg = g.group(re, nm)
          g.box(pg.entities, x, d, z, sx, sd, sz, g.mat(:panel))
        end
        ps.call('panel_L', 0, 0, 0, PANEL_T, CAB_D, 750.0)
        ps.call('panel_R', CAB_W - PANEL_T, 0, 0, PANEL_T, CAB_D, 750.0)
        ps.call('panel_bottom', PANEL_T, 0, 0, CAB_W - 2 * PANEL_T, CAB_D, PANEL_T)
        ps.call('panel_top', PANEL_T, 0, 734.0, CAB_W - 2 * PANEL_T, CAB_D, PANEL_T)
        moving = []
        failed = 0
        # ---- slides: lower (z 129.2) and upper (z 572.2) ----
        [[129.2, 'low'], [572.2, 'up']].each do |zbase, tier|
          [[:FIXED, 'fixed', g.mat(:zinc), false, 0.0], [:MOVING_OUTER, 'moving_outer', g.mat(:chrome), true, TRAVEL], [:LINER, 'liner', g.mat(:steel), true, TRAVEL], [:CAGE, 'cage', g.mat(:dark), true, TRAVEL]].each do |key, nm, mat, mv, shift|
            part = BasketData.const_get(key)
            grp = g.group(re, "slide_#{nm}_#{tier}")
            part[:loops].each do |lp|
              pts = lp.map { |u, v| [260.8 + u, zb.call(zbase + v)] }
              f = (g.poly(grp.entities, pts, :xz, dd(part[:y1] + shift), part[:y1] - part[:y0], mat) rescue nil)
              failed += 1 unless f
            end
            moving << grp if mv
          end
          # end brackets of the moving rail
          [[-305.7, 15.0], [136.3, 15.0]].each_with_index do |(y0, l), i|
            bg = g.group(re, "slide_bracket_#{i == 0 ? 'front' : 'rear'}_#{tier}")
            g.box(bg.entities, 244.4, dd(y0 + l + TRAVEL), zb.call(zbase), 29.0, l, 30.3, g.mat(:dark))
            moving << bg
          end
        end
        # ---- vertical posts joining the two tiers (flat 24 x 6 x 461), four stations ----
        posts = g.group(re, 'tower_posts')
        [63.4, 14.4, -196.6, -245.6].each { |y0| g.box(posts.entities, 231.7, dd(y0 + 6.0 + TRAVEL), zb.call(128.5), 24.0, 6.0, 461.0, g.mat(:steel)) }
        moving << posts
        # ---- wire baskets ----
        wire = lambda do |ents, x0, d0, z0, ax, len|
          g.cyl(ents, x0, d0, z0, WIRE_D / 2.0, len, ax, g.mat(:chrome), 8)
        end
        [128.5, 471.5].each_with_index do |zbase, ti|
          bk = g.group(re, "basket_#{ti == 0 ? 'low' : 'up'}")
          e = bk.entities
          xa = 39.4 + 2.0
          xb = 259.8 - 2.0
          ya = -295.7 + 2.0 + TRAVEL
          yb = 141.3 - 2.0 + TRAVEL
          ([2.0, 27.5, 51.5, 75.5, 116.5]).each do |dz|
            z = zb.call(zbase + dz)
            wire.call(e, xa, dd(yb), z, :x, xb - xa)
            wire.call(e, xa, dd(ya), z, :x, xb - xa)
            wire.call(e, xa, dd(yb), z, :d, yb - ya)
            wire.call(e, xb, dd(yb), z, :d, yb - ya)
          end
          [xa, xb].each { |x| [ya, yb].each { |y| wire.call(e, x, dd(y), zb.call(zbase), :z, 116.5 + 2.0) } }
          15.times do |k|
            y = -245.0 + 24.0 * k + TRAVEL
            wire.call(e, xa, dd(y), zb.call(zbase + 2.0), :x, xb - xa)
          end
          moving << bk
        end
        moving.each { |grp| rig.add(grp, grp.name) { |u| Proto121.move_xdz(0, TRAVEL * u, 0) } }
        Proto121.register_rig(rig)
        model.commit_operation
        rig.apply(0.0, model)
        { rig: rig, failed: failed }
      end
    end
  end
end
