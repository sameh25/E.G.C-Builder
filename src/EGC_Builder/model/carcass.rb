# encoding: UTF-8
# frozen_string_literal: true
#
# CarcassBuilder: pure function Cabinet -> Array<Part>.
#
# Every dimension used here comes from EGC::Constants. Nothing is hard-coded.
# Panels are positioned in world space so that Interference / Snap / Corner
# operate on real geometry rather than on abstract sizes.
#
# Panel arrangement (base unit, looking at the FRONT):
#
#   z1 +---------------------------+   <- top rail (100mm deep, set to front)
#      | L |                     | R |
#      |   |     inner void      |   |   <- gables full height
#      |   |                     |   |
#   z0 +---------------------------+   <- bottom deck (full width)
#      y0 (back)                 y1 (front)
#
# Gables: full height, full depth.  Deck/rail: between the gables.

module EGC
  module Model
    module CarcassBuilder
      C = EGC::Constants

      module_function

      def build(cabinet)
        parts = []
        w = cabinet.width
        h = cabinet.height
        d = cabinet.depth
        ox = cabinet.origin.x
        oy = cabinet.origin.y
        oz = cabinet.origin.z
        t = C::PANEL_THICKNESS

        gable_w = d                     # gable panel "width" runs front-back
        gable_l = h                     # gable panel "length" runs vertically
        inner_w = w - 2 * t             # clear width between gables
        back_depth = C::BACK_RECESS

        # ---- 1. side gables (thickness in X, span in Y/Z) ----------------
        # Left gable: outer face banded, front edge banded (visible).
        parts << Part.new(
          Part::ROLE_GABLE_L,
          :length => gable_l, :width => gable_w, :thickness => t,
          :material => cabinet.material,
          :edgeband => EdgeBand.of(:left, :right, :front),
          :cabinet_id => cabinet.id, :label => 'Left gable',
          :position => EGC::Geom::Vec3.new(ox, oy, oz),
          :orientation => :normal_x
        )
        parts << Part.new(
          Part::ROLE_GABLE_R,
          :length => gable_l, :width => gable_w, :thickness => t,
          :material => cabinet.material,
          :edgeband => EdgeBand.of(:left, :right, :front),
          :cabinet_id => cabinet.id, :label => 'Right gable',
          :position => EGC::Geom::Vec3.new(ox + w - t, oy, oz),
          :orientation => :normal_x
        )

        # ---- 2. bottom deck (full width, between nothing - sits under) ---
        parts << Part.new(
          Part::ROLE_BOTTOM,
          :length => inner_w, :width => d, :thickness => t,
          :material => cabinet.material,
          :edgeband => EdgeBand.of(:left, :right, :front),
          :cabinet_id => cabinet.id, :label => 'Bottom deck',
          :position => EGC::Geom::Vec3.new(ox + t, oy, oz),
          :orientation => :normal_z
        )

        # ---- 3. top: rail for base units, full top for wall/tall --------
        if cabinet.accepts_worktop?
          rail_h = [C::TOP_RAIL_HEIGHT, h - 2 * t].min
          # A rail is an ordinary 18mm board: its 100mm dimension is its
          # vertical WIDTH, never its thickness. Passing rail_h as thickness
          # produced a solid 100mm block that also polluted nesting with a
          # phantom material group.
          parts << Part.new(
            Part::ROLE_TOP_RAIL,
            :length => inner_w, :width => rail_h, :thickness => t,
            :material => cabinet.material,
            :edgeband => EdgeBand.of(:front),
            :cabinet_id => cabinet.id, :label => 'Top rail',
            :position => EGC::Geom::Vec3.new(ox + t, oy + d - t, oz + h - rail_h),
            :orientation => :normal_y
          )
          # rear stretcher closing the top, sitting just IN FRONT of the back
          # panel so the two never interpenetrate
          rear_y = oy + back_depth + C::BACK_THICKNESS
          parts << Part.new(
            Part::ROLE_STRETCHER,
            :length => inner_w, :width => rail_h, :thickness => t,
            :material => cabinet.material,
            :edgeband => EdgeBand.none,
            :cabinet_id => cabinet.id, :label => 'Rear stretcher',
            :position => EGC::Geom::Vec3.new(ox + t, rear_y, oz + h - rail_h),
            :orientation => :normal_y
          )
        else
          parts << Part.new(
            Part::ROLE_TOP_RAIL,
            :length => inner_w, :width => d, :thickness => t,
            :material => cabinet.material,
            :edgeband => EdgeBand.of(:left, :right, :front),
            :cabinet_id => cabinet.id, :label => 'Top panel',
            :position => EGC::Geom::Vec3.new(ox + t, oy, oz + h - t),
            :orientation => :normal_z
          )
        end

        # ---- 4. back panel ----------------------------------------------
        # Sits INSIDE the gables and in the rebate, so it never intersects
        # either gable or the bottom deck.
        if cabinet.options[:has_back]
          parts << Part.new(
            Part::ROLE_BACK,
            :length => inner_w, :width => h - 2 * t, :thickness => C::BACK_THICKNESS,
            :material => Materials::DEFAULT_BACK,
            :edgeband => EdgeBand.none,
            :cabinet_id => cabinet.id, :label => 'Back panel',
            :position => EGC::Geom::Vec3.new(ox + t, oy + back_depth, oz + t),
            :orientation => :normal_y
          )
        end

        # ---- 5. plinth ---------------------------------------------------
        if cabinet.plinth && cabinet.base?
          plinth_h = C::TOE_KICK_HEIGHT
          parts << Part.new(
            Part::ROLE_PLINTH,
            :length => w, :width => plinth_h, :thickness => t,
            :material => Materials::DEFAULT,
            :edgeband => EdgeBand.of(:left, :right, :front),
            :cabinet_id => cabinet.id, :label => 'Plinth',
            :position => EGC::Geom::Vec3.new(ox, oy + d - C::TOE_KICK_SETBACK - t, oz - plinth_h),
            :orientation => :normal_y
          )
        end

        # ---- 6. shelves & dividers ---------------------------------------
        cabinet.shelves.each do |s|
          case s[:type]
          when :fixed, :adjustable
            slack = s[:type] == :adjustable ? C::ADJUSTABLE_SHELF_CLEARANCE : 0.0
            shelf_d = (d - s[:inset] - C::SHELF_DEPTH_REDUCTION).clamp(10.0, d)
            parts << Part.new(
              Part::ROLE_SHELF,
              :length => inner_w - slack, :width => shelf_d,
              :thickness => C::SHELF_THICKNESS,
              :material => cabinet.material,
              :edgeband => EdgeBand.of(:front, :left, :right),
              :cabinet_id => cabinet.id,
              :label => (s[:type] == :fixed ? 'Fixed shelf' : 'Adjustable shelf'),
              :position => EGC::Geom::Vec3.new(
                ox + t + slack / 2.0,
                oy + s[:inset] + C::SHELF_DEPTH_REDUCTION,
                s[:z] - C::SHELF_THICKNESS / 2.0
              ),
              :orientation => :normal_z
            )
          when :divider
            inner_h = h - 2 * t
            div_d = (d - s[:inset] - C::SHELF_DEPTH_REDUCTION).clamp(10.0, d)
            parts << Part.new(
              Part::ROLE_DIVIDER,
              :length => inner_h, :width => div_d, :thickness => t,
              :material => cabinet.material,
              :edgeband => EdgeBand.of(:front),
              :cabinet_id => cabinet.id, :label => 'Vertical divider',
              :position => EGC::Geom::Vec3.new(s[:x] - t / 2.0, oy + s[:inset] + C::SHELF_DEPTH_REDUCTION, oz + t),
              :orientation => :normal_x
            )
          end
        end

        # ---- 7. doors -----------------------------------------------------
        parts.concat(DoorBuilder.build(cabinet)) unless cabinet.doors.empty?

        # ---- 8. drawers ---------------------------------------------------
        parts.concat(DrawerBuilder.build(cabinet)) unless cabinet.drawers.empty?

        # ---- 9. hanging rod ------------------------------------------------
        if cabinet.rod_config
          parts << Part.new(
            Part::ROLE_ROD,
            :length => inner_w, :width => C::HANGING_ROD_DIAMETER,
            :thickness => C::HANGING_ROD_DIAMETER,
            :material => Materials::DEFAULT,
            :edgeband => EdgeBand.none,
            :cabinet_id => cabinet.id, :label => 'Hanging rod',
            :position => EGC::Geom::Vec3.new(ox + t, cabinet.rod_config[:y], cabinet.rod_config[:z]),
            :orientation => :normal_x
          )
        end

        parts
      end
    end
  end
end
