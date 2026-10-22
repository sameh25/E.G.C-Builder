# encoding: UTF-8
# frozen_string_literal: true
#
# snap (§5) - magnetic snapping.
#
# Snapping SUGGESTS a legal neighbour position; it never mutates a dimension
# or a clearance. All snap targets derive from the frozen SNAP_TOLERANCE and
# the SYSTEM32 grid.

module EGC
  module Ops
    module Snap
      C = EGC::Constants

      module_function

      # Snap a raw X coordinate to the nearest neighbouring cabinet face
      # (side-gable to side-gable) within tolerance.
      def snap_x(doc, x, tol = C::SNAP_TOLERANCE)
        snap_axis(x_targets(doc), x, tol)
      end

      # Full snap resolution for a proposed cabinet placement.
      # Returns { x:, y:, z:, snapped_x:, snapped_y:, snapped_z:, deltas: }
      def resolve(doc, position, tol = C::SNAP_TOLERANCE)
        x, y, z = position
        sx = snap_axis(x_targets(doc), x, tol)
        sy = snap_axis(y_targets(doc), y, tol)
        sz = snap_levels(doc, z, tol)

        {
          :x => sx, :y => sy, :z => sz,
          :snapped_x => (sx - x).abs > 1e-9,
          :snapped_y => (sy - y).abs > 1e-9,
          :snapped_z => (sz - z).abs > 1e-9,
          :deltas => { :x => (sx - x).round(3), :y => (sy - y).round(3), :z => (sz - z).round(3) },
          :tolerance => tol
        }
      end

      # Candidate X planes derived from existing cabinets (never stored state).
      def x_targets(doc)
        out = []
        doc.cabinets.each { |c| out << c.x_min << c.x_max }
        out
      end

      # Candidate Y planes derived from existing cabinets.
      def y_targets(doc)
        out = []
        doc.cabinets.each { |c| out << c.origin.y << c.front_y }
        out
      end

      def snap_axis(targets, value, tol)
        return value if targets.empty?
        best = targets.min_by { |v| (v - value).abs }
        (best - value).abs <= tol ? best : value
      end

      # Vertical snap levels: floor, plinth top, counter plane, and any
      # existing cabinet top/bottom within tolerance.
      def snap_levels(doc, z, tol)
        levels = [0.0, C::TOE_KICK_HEIGHT, C::STANDARD_COUNTER_HEIGHT]
        doc.cabinets.each { |c| levels << c.bottom_z << c.top_z }
        snap_axis(levels, z, tol)
      end

      # Grid snap on the 32mm system pitch (used for shelf pin rows).
      def snap_system32(z)
        EGC::Geom.snap_to(z, C::SYSTEM32_PITCH, C::SNAP_TOLERANCE)
      end

      # Validates that a snapped placement does not create interference.
      def validate(doc, position, width, height, depth, tol = C::SNAP_TOLERANCE)
        b = EGC::Geom::Box.from_whd(EGC::Geom::Vec3.new(*position), width, height, depth)
        clashes = doc.cabinets.select do |c|
          b.overlap_volume(c.bounding_box, C::INTERFERENCE_TOLERANCE) > 0.0
        end
        { :ok => clashes.empty?, :clashes => clashes.map(&:id), :tolerance => tol }
      end
    end
  end
end
