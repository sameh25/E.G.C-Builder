# frozen_string_literal: true

Sketchup.require(File.join(File.dirname(__FILE__), 'runner_data'))

module EGC
  module Proto121
    # PROTOTYPE D - EGC_RUNNER_UNDER_REFERENCE : multi-member telescopic runner measured on the reference models (review scene, not integrated).
    # SOURCES: Basket+slides+latest/model.dae (3-member ball/roller slide: outer rail 12 x 46, intermediate rail 9.2 x 35, inner rail 7 x 24, cage 176 long,
    #   L-bracket 20 x 42 carrying the drawer, section loops copied as measured); Aramado+Gaveta/model.dae (cross-check: outer / liner / I-section cage / inner rail,
    #   members 455 / 450 / 427 / 450 long, cage at half travel); Maxi front fixing STEP (46.8 x 29.7 x 18.2 block, two dowels on a 32 mm pitch).
    # MOTION (kinematic rule, not prescribed paths): inner rail + bracket + drawer travel s, the intermediate rail s/2 (synchronised telescoping), the cage between
    #   intermediate and inner rail rolls at the mean of its neighbours, 3/4 s. Outer rail fixed to the cabinet side.
    # INFERRED: how the bracket/Maxi block sit on the E.G.C drawer (arm under the 8 mm drawer bottom, block behind the front at the corners); real drilling not modelled.
    module RunnerProto
      module_function

      W_IN = 564.0        # cabinet inner width (600 module)
      PANEL_T = 18.0
      CAB_D = 450.0
      CAB_H = 520.0
      SLIDE = 375.0       # measured nominal slide length
      DRAWER_T = 18.0     # approved drawer board thickness
      BOTTOM_T = 8.0
      BOX_H = 110.0
      FRONT_H = 160.0
      ZB = 70.0           # drawer bottom underside = top of the bracket arm
      TRAVEL = ((RunnerData::CAGE[:y0] - RunnerData::INNER[:y0]) / 0.25).round(1) # cage stop: the cage (mean speed 3/4 s) must stay behind the inner rail rear end -> s <= 272.5 mm

      def build(model = Sketchup.active_model)
        g = Proto121
        model.start_operation('E.G.C prototype D - runner', true)
        root = model.entities.add_group
        root.name = 'EGC_RUNNER_UNDER_REFERENCE'
        re = root.entities
        rig = Proto121::Rig.new('EGC_RUNNER_UNDER_REFERENCE')
        ps = lambda do |nm, x, d, z, sx, sd, sz|
          pg = g.group(re, nm)
          g.box(pg.entities, x, d, z, sx, sd, sz, g.mat(:panel))
        end
        ps.call('panel_L', -PANEL_T, 0, 0, PANEL_T, CAB_D, CAB_H)
        ps.call('panel_R', W_IN, 0, 0, PANEL_T, CAB_D, CAB_H)
        ps.call('panel_bottom', 0, 0, 0, W_IN, CAB_D, PANEL_T)
        d_rear = CAB_D - SLIDE
        failed = 0
        member = lambda do |nm, key, mat, k|
          part = RunnerData.const_get(key)
          [[1.0, 'L'], [-1.0, 'R']].map do |sx, side|
            grp = g.group(re, "#{nm}_#{side}")
            part[:loops].each do |lp|
              pts = lp.map { |u, v| [sx.positive? ? u : W_IN - u, ZB + v] }
              begin
                f = g.poly(grp.entities, pts, :xz, d_rear + part[:y0], part[:y1] - part[:y0], mat)
                failed += 1 unless f
              rescue StandardError
                failed += 1
              end
            end
            rig.add(grp, "#{nm} #{side}") { |u| Proto121.move_xdz(0, k * TRAVEL * u, 0) } unless k.nil?
            grp
          end
        end
        member.call('runner_outer', :OUTER, g.mat(:zinc), nil)
        member.call('runner_strip_top', :STRIP_TOP, g.mat(:steel), nil)
        member.call('runner_strip_bottom', :STRIP_BOT, g.mat(:steel), nil)
        member.call('runner_mid', :MID, g.mat(:chrome), 0.5)
        member.call('runner_mid_liner', :MID_LINER, g.mat(:steel), 0.5)
        member.call('runner_cage', :CAGE, g.mat(:dark), 0.75)
        member.call('runner_inner', :INNER, g.mat(:zinc), 1.0)
        member.call('runner_bracket', :BRACKET, g.mat(:chrome), 1.0)
        # ---- drawer (moves with the inner rail): 18 mm boards, 8 mm bottom ----
        bx = RunnerData::BRACKET[:loops].flatten(1).map(&:first).min # bracket outer edge from the cabinet side (u)
        dw0 = bx - 0.0
        dw = W_IN - 2 * dw0
        dr = g.group(re, 'drawer')
        de = dr.entities
        d0 = CAB_D - SLIDE
        g.box(de, dw0, d0, ZB, DRAWER_T, SLIDE, BOX_H, g.mat(:door_up))
        g.box(de, dw0 + dw - DRAWER_T, d0, ZB, DRAWER_T, SLIDE, BOX_H, g.mat(:door_up))
        g.box(de, dw0 + DRAWER_T, d0, ZB, dw - 2 * DRAWER_T, DRAWER_T, BOX_H, g.mat(:door_up))
        g.box(de, dw0, d0, ZB, dw, SLIDE, BOTTOM_T, g.mat(:door_low))
        fr = g.group(re, 'drawer_front')
        g.box(fr.entities, 2.0, CAB_D, ZB - 10, W_IN - 4, DRAWER_T, FRONT_H, g.mat(:door))
        # Maxi-type front fixing blocks (46.8 x 29.7 x 18.2, two dowels on 32 mm pitch) behind the front at both side boards
        mx = g.group(re, 'front_connector')
        [dw0 + DRAWER_T + 23.4 + 2.0, dw0 + dw - DRAWER_T - 23.4 - 2.0].each do |cx|
          g.box(mx.entities, cx - 23.4, CAB_D - 29.7, ZB + BOTTOM_T, 46.8, 29.7, 18.2, g.mat(:dark))
          [-16.0, 16.0].each { |o| g.cyl(mx.entities, cx + o, CAB_D, ZB + BOTTOM_T + 9.1, 4.25, 8.0, :d, g.mat(:chrome), 12) }
        end
        [dr, fr, mx].each_with_index { |grp, i| rig.add(grp, grp.name) { |u| Proto121.move_xdz(0, TRAVEL * u, 0) } }
        Proto121.register_rig(rig)
        model.commit_operation
        rig.apply(0.0, model)
        { rig: rig, failed: failed }
      end
    end
  end
end
