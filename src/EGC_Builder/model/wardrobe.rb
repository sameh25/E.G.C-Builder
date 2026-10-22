# encoding: UTF-8
# frozen_string_literal: true
#
# Wardrobe / dressing-room engine (§4).
#
# ROOT CAUSE OF THE nil:NilClass CRASH
# ------------------------------------
# The legacy code derived the interior cavity from `doors.first.face`, so any
# doorless / open dressing unit raised NoMethodError on nil when a shelf or
# divider was inserted. Cavity computation is now PURELY derived from the
# carcass panels:
#     x: inner faces of the left & right gables
#     z: inner face of the bottom deck .. inner face of the top panel
#     y: front face of the back panel .. the open front plane
# No door object is dereferenced anywhere in this path.
#
# Open units additionally receive exposed edge banding on every front-facing
# edge (gables, deck, top, fixed shelves) because those edges are visible.

module EGC
  module Model
    module Wardrobe
      C = EGC::Constants

      module_function

      # ---- cavity derivation (door-independent) -------------------------
      # Returns an EGC::Geom::Box in world millimetres.
      #
      # Derived from cabinet.inner_void, which reads ONLY the inner faces of
      # the gables / deck / top. No door object is touched anywhere.
      def detect_inner_void(cabinet)
        raise EGC::CabinetError, 'cabinet is nil' if cabinet.nil?
        t = C::PANEL_THICKNESS
        w = cabinet.width.to_f
        h = cabinet.height.to_f
        d = cabinet.depth.to_f
        raise EGC::CabinetError, 'cabinet has degenerate dimensions' if w <= 2 * t || h <= 2 * t

        cabinet.inner_void
      end

      # Validates the void against the carcass envelope. Used by the audit.
      def void_valid?(cabinet)
        v = detect_inner_void(cabinet)
        v.width > 0 && v.height > 0 && v.depth > 0
      rescue EGC::CabinetError
        false
      end

      # ---- open-unit edge banding --------------------------------------
      # Every front-facing edge of a doorless unit must be banded, otherwise
      # the raw board core is visible.
      EXPOSED_ROLES = [
        Part::ROLE_GABLE_L, Part::ROLE_GABLE_R, Part::ROLE_BOTTOM,
        Part::ROLE_TOP_RAIL, Part::ROLE_SHELF, Part::ROLE_DIVIDER,
        Part::ROLE_STRETCHER
      ].freeze

      def open_unit?(cabinet)
        cabinet.doorless?
      end

      # Idempotent. Returns the number of parts that gained banding.
      def apply_exposed_edgeband!(cabinet, parts = nil)
        return 0 unless open_unit?(cabinet)
        target = parts || cabinet.parts
        touched = 0
        target.each do |part|
          next unless EXPOSED_ROLES.include?(part.role)
          before = part.edgeband.to_code
          part.add_edgeband(:front)
          touched += 1 if part.edgeband.to_code != before
        end
        touched
      end

      # Convenience: rebuild, then band exposed edges.
      def rebuild_open_unit!(cabinet)
        cabinet.rebuild!
        apply_exposed_edgeband!(cabinet)
        cabinet.parts
      end

      # ---- wardrobe-specific part generation ---------------------------
      # Adds the tall-unit extras on top of the standard carcass: a mid
      # fixed shelf for structural rigidity on towers, plus the wardrobe
      # plinth is omitted (wardrobes sit on adjustable feet).
      def build_parts(cabinet)
        parts = EGC::Model::CarcassBuilder.build(cabinet)
        if cabinet.tall? && cabinet.height >= 1800
          mid_z = cabinet.internal_bottom_z + cabinet.internal_height / 2.0
          already = parts.any? { |p| p.role == Part::ROLE_SHELF && (p.position.z - mid_z).abs < 5 }
          unless already
            shelf_d = (cabinet.depth - C::SHELF_SETBACK - C::SHELF_DEPTH_REDUCTION).clamp(10.0, cabinet.depth)
            parts << Part.new(
              Part::ROLE_SHELF,
              :length => cabinet.internal_width, :width => shelf_d,
              :thickness => C::SHELF_THICKNESS,
              :material => cabinet.material,
              :edgeband => EdgeBand.of(:front, :left, :right),
              :cabinet_id => cabinet.id, :label => 'Wardrobe mid shelf',
              :position => EGC::Geom::Vec3.new(
                cabinet.origin.x + C::PANEL_THICKNESS,
                cabinet.origin.y + C::SHELF_SETBACK + C::SHELF_DEPTH_REDUCTION,
                mid_z - C::SHELF_THICKNESS / 2.0
              ),
              :orientation => :normal_z
            )
          end
        end
        parts
      end
    end
  end
end

# Reopen Cabinet to expose the wardrobe API as instance methods.
module EGC
  module Model
    class Cabinet
      # Door-independent cavity. Safe on doorless units.
      def detect_inner_void
        EGC::Model::Wardrobe.detect_inner_void(self)
      end

      # Alias kept for call-sites that used the legacy name.
      def inner_void_safe
        detect_inner_void
      end

      def open_unit?
        EGC::Model::Wardrobe.open_unit?(self)
      end

      def apply_exposed_edgeband!
        EGC::Model::Wardrobe.apply_exposed_edgeband!(self)
      end

      # Cavities annotated with world-space boxes, for space_tool hit-testing.
      def cavity_zones
        v = detect_inner_void
        cavities.map do |c|
          box = EGC::Geom::Box.new(
            EGC::Geom::Vec3.new(v.min.x, v.min.y, c[:z0]),
            EGC::Geom::Vec3.new(v.max.x, v.max.y, c[:z1])
          )
          c.merge(:box => box)
        end
      end
    end
  end
end
