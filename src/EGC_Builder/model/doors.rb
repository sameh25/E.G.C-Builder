# encoding: UTF-8
# frozen_string_literal: true
#
# Door + drawer-front generation.
#
# Doors are always derived from the DOOR OPENING (the front plane of the
# carcass) - never from a stored "door face" object. That keeps doorless
# units fully computable (§4).

module EGC
  module Model
    module DoorBuilder
      C = EGC::Constants

      module_function

      # Number of door openings for a cabinet.
      def opening_count(cabinet)
        return 0 if cabinet.doors.empty?
        cabinet.doors.sum { |d| d[:side] == :double ? 2 : 1 }
      end

      # The front elevation rectangle of the carcass, in world X/Z.
      def front_elevation(cabinet)
        {
          :x0 => cabinet.origin.x,
          :x1 => cabinet.origin.x + cabinet.width,
          :z0 => cabinet.origin.z,
          :z1 => cabinet.origin.z + cabinet.height,
          :y  => cabinet.origin.y + cabinet.depth
        }
      end

      # Each door leaf gets an equal share of the opening minus gaps.
      def leaf_rects(cabinet)
        leaves = opening_count(cabinet)
        return [] if leaves.zero?
        elev = front_elevation(cabinet)
        total_w = elev[:x1] - elev[:x0]
        gap = C::DOOR_GAP
        leaf_w = (total_w - gap * (leaves + 1)) / leaves
        leaf_h = (elev[:z1] - elev[:z0]) - gap * 2
        (0...leaves).map do |i|
          x = elev[:x0] + gap + i * (leaf_w + gap)
          { :x => x, :z => elev[:z0] + gap, :w => leaf_w, :h => leaf_h, :y => elev[:y] }
        end
      end

      def build(cabinet)
        rects = leaf_rects(cabinet)
        return [] if rects.empty?
        rects.each_with_index.map do |r, i|
          # Door is banded on all four edges (visible front panel).
          Part.new(
            Part::ROLE_DOOR,
            :length => r[:h], :width => r[:w], :thickness => C::DOOR_THICKNESS,
            :material => cabinet.material,
            :edgeband => EdgeBand.all,
            :cabinet_id => cabinet.id,
            :label => "Door #{i + 1}",
            :position => EGC::Geom::Vec3.new(r[:x], r[:y], r[:z]),
            :orientation => :normal_y
          )
        end
      end
    end

    module DrawerBuilder
      C = EGC::Constants

      module_function

      # Box width = internal width - 2 * side clearance (frozen constant).
      def box_width(cabinet)
        cabinet.internal_width - 2 * C::DRAWER_BOX_SIDE_GAP
      end

      def box_depth(cabinet, runner)
        runner ? [runner.length, cabinet.internal_depth - C::DRAWER_BOX_BACK_CLEARANCE].min : cabinet.internal_depth
      end

      def box_height(drawer)
        drawer[:height]
      end

      def build(cabinet)
        parts = []
        cabinet.drawers.each_with_index do |dr, i|
          bw = box_width(cabinet)
          bd = box_depth(cabinet, dr[:runner])
          bh = box_height(dr)
          ox = cabinet.origin.x + C::PANEL_THICKNESS + C::DRAWER_BOX_SIDE_GAP
          oy = cabinet.origin.y + cabinet.depth - bd - C::DRAWER_BOX_BACK_CLEARANCE
          oz = cabinet.origin.z + dr[:z]

          # drawer sides (2)
          [0, bw - C::DRAWER_BOX_THICKNESS].each_with_index do |dx, s|
            parts << Part.new(
              Part::ROLE_DRAWER_SIDE,
              :length => bd, :width => bh, :thickness => C::DRAWER_BOX_THICKNESS,
              :material => Materials::DEFAULT_DRAWER_BOX,
              :edgeband => EdgeBand.of(:front),
              :cabinet_id => cabinet.id,
              :label => "Drawer #{i + 1} side #{s + 1}",
              :position => EGC::Geom::Vec3.new(ox + dx, oy, oz),
              :orientation => :normal_x
            )
          end

          # drawer back / front rails
          inner_bw = bw - 2 * C::DRAWER_BOX_THICKNESS
          parts << Part.new(
            Part::ROLE_DRAWER_BACK,
            :length => inner_bw, :width => bh, :thickness => C::DRAWER_BOX_THICKNESS,
            :material => Materials::DEFAULT_DRAWER_BOX,
            :edgeband => EdgeBand.of(:back),
            :cabinet_id => cabinet.id, :label => "Drawer #{i + 1} back",
            :position => EGC::Geom::Vec3.new(ox + C::DRAWER_BOX_THICKNESS, oy, oz),
            :orientation => :normal_x
          )

          # bottom
          parts << Part.new(
            Part::ROLE_DRAWER_BOTTOM,
            :length => bw, :width => bd, :thickness => C::DRAWER_BOTTOM_THICKNESS,
            :material => Materials::DEFAULT_DRAWER_BASE,
            :edgeband => EdgeBand.none,
            :cabinet_id => cabinet.id, :label => "Drawer #{i + 1} bottom",
            :position => EGC::Geom::Vec3.new(ox, oy, oz + C::DRAWER_BOTTOM_GROOVE),
            :orientation => :normal_z
          )

          # drawer front (from elevation, same gap rules as doors)
          parts << Part.new(
            Part::ROLE_DRAWER_FRONT,
            :length => bh + 2 * C::DRAWER_FRONT_GAP,
            :width => bw + 2 * C::DRAWER_BOX_SIDE_GAP - 2 * C::DOOR_GAP,
            :thickness => C::DOOR_THICKNESS,
            :material => cabinet.material,
            :edgeband => EdgeBand.all,
            :cabinet_id => cabinet.id, :label => "Drawer #{i + 1} front",
            :position => EGC::Geom::Vec3.new(ox, cabinet.origin.y + cabinet.depth, oz - C::DRAWER_FRONT_GAP),
            :orientation => :normal_y
          )
        end
        parts
      end
    end
  end
end
