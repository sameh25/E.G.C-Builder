# frozen_string_literal: true

Sketchup.require(File.join(File.dirname(__FILE__), 'proto121', 'basket_data'))

module EGC
  # Production wire-basket pull-out (P1 geometry measured on Component_54.skp): one telescopic side slide per tier on the RIGHT side, tiers joined by
  # flat posts, wire baskets hanging on the slides. Parts are cached definitions; local d = 0 is the REAR end (members extrude toward the front),
  # x is measured from the right inner face (<0 toward the cabinet), z from the slide / basket base. Closed pose; the builder's asm moves the moving parts +d.
  module P1Basket
    module_function

    REF_LEN = 450.0     # measured fixed-rail length (cabinet 560 deep)
    FRONT_Y = 30.3      # fixed rail front, mm behind the carcass front plane
    TIER_Z = [13.2, 456.2].freeze   # slide base z above the inner floor (reference 129.2 / 572.2)
    X_RIGHT = 284.0     # reference x of the right inner face
    WIRE = 4.0
    BASKET_H = 118.0

    def g
      Proto121
    end

    def len_for(cd)
      [[((cd - 100) / 50.0).floor * 50.0, 250.0].max, REF_LEN].min
    end

    def member_def(key, len, mat_key)
      part = Proto121::BasketData.const_get(key)
      mlen = part[:y1] - part[:y0] - (REF_LEN - len)
      MechParts.defn("p1_#{key}_#{len.round}") do |e|
        part[:loops].each do |lp|
          pts = lp.map { |u, v| [260.8 + u - X_RIGHT, v] }
          g.poly(e, pts, :xz, 0.0, mlen, g.mat(mat_key))
        end
      end
    end

    def bracket_def
      MechParts.defn('p1_bracket') { |e| g.box(e, 0, 0, 0, 29.0, 15.0, 30.3, g.mat(:dark)) }
    end

    def post_def(h)
      MechParts.defn("p1_post_#{h.round}") { |e| g.box(e, 0, 0, 0, 24.0, 6.0, h, g.mat(:steel)) }
    end

    # basket origin: min corner (x left, d rear, z floor); w x dep outer size
    def basket_def(w, dep)
      MechParts.defn("p1_basket_#{w.round(1)}_#{dep.round(1)}") do |e|
        m = g.mat(:chrome)
        wr = ->(x, d, z, ax, len) { g.cyl(e, x, d, z, WIRE / 2.0, len, ax, m, 8) }
        xa = 2.0
        xb = w - 2.0
        da = 2.0
        db = dep - 2.0
        [2.0, 27.5, 51.5, 75.5, 116.5].each do |dz|
          wr.call(xa, da, dz, :x, xb - xa)
          wr.call(xa, db, dz, :x, xb - xa)
          wr.call(xa, da, dz, :d, db - da)
          wr.call(xb, da, dz, :d, db - da)
        end
        [xa, xb].each { |x| [da, db].each { |d| wr.call(x, d, 0.0, :z, BASKET_H) } }
        n = [((dep - 101.0) / 24.0 + 0.001).floor + 1, 1].max
        n.times { |k| wr.call(xa, dep - 50.7 - 24.0 * k, 2.0, :x, xb - xa) }
      end
    end
  end

  module FamilyBuilders
    # Wire-basket pull-out on measured side slides (item :wire). Closed-pose build; asm 'pullout' slides +d by `travel`.
    def fam_wire_p1(o)
      b = bnd
      zf, hf = full_front
      fl = @z0 + @t
      xr = @w - @t
      cd = @cd
      len = P1Basket.len_for(cd)
      cut = P1Basket::REF_LEN - len
      travel = len - 115.0
      tiers = (b[:z1] - fl) >= 520 ? [(o[:levels] || 2), 2].min : 1
      tz = P1Basket::TIER_Z.first(tiers)
      bz = [12.5, 355.5].first(tiers)
      fy = P1Basket::FRONT_Y
      pos = @kind == :tall ? :side_r : :top
      pos = :bottom if @kind == :wall
      put = ->(df, x, d, z, part) { hw_tag(MechParts.put(tgt, df, x, d, z), part) }
      tz.each { |zt| put.call(P1Basket.member_def(:FIXED, len, :zinc), xr, cd - fy - len, fl + zt, 'slide_outer') }
      a = asm('pullout', MotionProfiles.linear_slide([0, travel, 0], nil))
      in_asm(a) do
        tz.each do |zt|
          z = fl + zt
          put.call(P1Basket.member_def(:MOVING_OUTER, len, :chrome), xr, cd - fy - len - 5.0, z, 'slide_inner')
          put.call(P1Basket.member_def(:LINER, len, :steel), xr, cd - fy - len, z, 'slide_inner')
          put.call(P1Basket.member_def(:CAGE, len, :dark), xr, cd - 46.3 - (427.5 - cut), z, 'slide_cage')
          put.call(P1Basket.bracket_def, xr - 39.6, cd - 44.3, z, 'slide_bracket')
          put.call(P1Basket.bracket_def, xr - 39.6, cd - 36.3 - len, z, 'slide_bracket')
        end
        bw = b[:x1] - b[:x0] - 41.6
        bdep = len - 13.0
        bz.each { |z0| put.call(P1Basket.basket_def(bw, bdep), xr - 24.2 - bw, cd - 39.3 - bdep, fl + z0, 'basket') }
        if tiers > 1
          [398.4, 349.4, 138.4, 89.4].each do |yc|
            yy = yc > 200 ? yc - cut : yc
            put.call(P1Basket.post_def(461.0), xr - 52.3, cd - yy - 6.0, fl + 12.5, 'basket_post')
          end
        end
        front('door', @gap / 2.0, @w - @gap, zf, hf, pos, grain: :z)
      end
      @hw['basket'] += tiers
      @hw['slide_pair'] += 1
    end
  end
end
