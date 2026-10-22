# encoding: UTF-8
# frozen_string_literal: true
#
# space_tool (§1D / §4) - in-cavity placement tool.
#
# Single-click on any internal cavity must:
#   * resolve the hit to an open cavity WITHOUT dereferencing a door face
#   * highlight that void
#   * permit insertion of: fixed shelf, adjustable shelf, vertical divider,
#     hanging rod (with bracket drilling) and a drawer module (with correct
#     runner clearances).
#
# The hit test works on world-space boxes derived from cabinet.cavity_zones,
# which in turn come from Wardrobe.detect_inner_void - a door-free path.

module EGC
  module Ops
    module SpaceTool
      C = EGC::Constants

      INSERTIONS = [:fixed_shelf, :adjustable_shelf, :divider, :hanging_rod, :drawer].freeze

      module_function

      # ---- hit testing ------------------------------------------------------
      # point: EGC::Geom::Vec3 in world mm.
      # Returns { cabinet:, cavity:, box: } or nil.
      def hit_test(doc, point)
        doc.cabinets.each do |cab|
          next unless cav = cavity_at(cab, point)
          return { :cabinet => cab, :cavity => cav, :box => cav[:box] }
        end
        nil
      end

      # Resolves the specific cavity inside a cabinet that contains `point`.
      def cavity_at(cabinet, point)
        zones = cabinet.cavity_zones
        zones.find { |z| point_in_box?(point, z[:box]) }
      rescue EGC::CabinetError
        nil
      end

      def point_in_box?(p, box)
        p.x >= box.min.x - 1e-6 && p.x <= box.max.x + 1e-6 &&
          p.y >= box.min.y - 1e-6 && p.y <= box.max.y + 1e-6 &&
          p.z >= box.min.z - 1e-6 && p.z <= box.max.z + 1e-6
      end

      # Highlights a cavity. Returns the geometry descriptor the UI should
      # draw; in SketchUp this becomes a translucent preview face.
      def highlight(cavity_hit)
        return nil if cavity_hit.nil?
        box = cavity_hit[:box]
        {
          :kind => :cavity_highlight,
          :cabinet_id => cavity_hit[:cabinet].id,
          :box => box,
          :corners => box.corners,
          :center => box.center,
          :volume_litres => (box.volume / 1_000_000.0).round(2)
        }
      end

      # ---- insertion --------------------------------------------------------
      # Returns a result hash describing what was inserted. Never raises for a
      # valid cavity; raises InsertionError for an unsupported combination.
      def insert(cavity_hit, kind, params = {})
        raise EGC::InsertionError, 'no cavity under cursor' if cavity_hit.nil?
        kind = kind.to_sym
        unless INSERTIONS.include?(kind)
          raise EGC::InsertionError, "unsupported insertion #{kind.inspect} (allowed: #{INSERTIONS.inspect})"
        end

        cab = cavity_hit[:cabinet]
        cav = cavity_hit[:cavity]

        case kind
        when :fixed_shelf, :adjustable_shelf
          insert_shelf(cab, cav, kind, params)
        when :divider
          insert_divider(cab, cav, params)
        when :hanging_rod
          insert_rod(cab, cav, params)
        when :drawer
          insert_drawer(cab, cav, params)
        end
      end

      # ---- shelf ------------------------------------------------------------
      def insert_shelf(cab, cav, kind, params)
        type = (kind == :fixed_shelf ? :fixed : :adjustable)
        z = params[:z] || (cav[:z0] + cav[:z1]) / 2.0
        unless z > cav[:z0] + C::SHELF_THICKNESS && z < cav[:z1] - C::SHELF_THICKNESS
          raise EGC::InsertionError, "shelf at z=#{z} does not fit cavity #{cav[:z0]}..#{cav[:z1]}"
        end

        entry = cab.add_shelf(:type => type, :z => z, :inset => params.fetch(:inset, C::SHELF_SETBACK))
        refresh(cab)

        # The part origin sits half a shelf thickness BELOW the centreline z.
        shelf = cab.parts.find do |p|
          p.role == EGC::Model::Part::ROLE_SHELF &&
            (p.position.z + C::SHELF_THICKNESS / 2.0 - z).abs < 1.0
        end
        {
          :kind => kind, :cabinet_id => cab.id, :entry => entry,
          :part_id => shelf && shelf.id,
          :length => shelf && shelf.length, :width => shelf && shelf.width,
          :z => z
        }
      end

      # ---- divider ------------------------------------------------------------
      def insert_divider(cab, cav, params)
        x = params[:x] || (cav[:box].min.x + cav[:box].max.x) / 2.0
        unless x > cav[:box].min.x + C::PANEL_THICKNESS && x < cav[:box].max.x - C::PANEL_THICKNESS
          raise EGC::InsertionError, "divider at x=#{x} does not fit the cavity"
        end
        entry = cab.add_divider(:x => x, :inset => params.fetch(:inset, C::SHELF_SETBACK))
        refresh(cab)
        {
          :kind => :divider, :cabinet_id => cab.id, :entry => entry, :x => x,
          :height => cab.internal_height
        }
      end

      # ---- hanging rod ---------------------------------------------------------
      # Places the rod at HANGING_ROD_HEIGHT_BELOW_TOP unless overridden, and
      # emits bracket drilling positions from the frozen drill constants.
      def insert_rod(cab, cav, params)
        z = params[:z] || ([cav[:z0] + C::HANGING_ROD_HEIGHT_BELOW_TOP,
                            cav[:z1] - C::HANGING_ROD_DIAMETER].min)
        unless z > cav[:z0] && z < cav[:z1]
          raise EGC::InsertionError, "rod at z=#{z} does not fit cavity"
        end
        config = cab.add_hanging_rod(:z => z)
        refresh(cab)

        # bracket drilling: one per gable, at the rod centreline
        void = cab.detect_inner_void
        drills = EGC::CAM.rod_bracket_holes(z, void.min.x, void.max.x)

        {
          :kind => :hanging_rod, :cabinet_id => cab.id,
          :z => config[:z], :y => config[:y], :diameter => config[:diameter],
          :span => (void.max.x - void.min.x).round(2),
          :brackets => drills,
          :bracket_count => drills.length
        }
      end

      # ---- drawer module ---------------------------------------------------------
      # Runner selection uses Hardware.runner_for_depth, which only READS the
      # frozen clearances; it never adjusts them to make a drawer fit.
      def insert_drawer(cab, cav, params)
        height = params[:height] || [(cav[:z1] - cav[:z0]) - C::DRAWER_BOX_BACK_CLEARANCE, 120.0].min
        z = params[:z] || cav[:z0]
        if z + height > cav[:z1] + 1e-6
          raise EGC::InsertionError, "drawer of height #{height} does not fit cavity"
        end

        runner = EGC::Model::Hardware.runner_for_depth(cab.internal_depth)
        raise EGC::InsertionError, "cabinet depth #{cab.internal_depth.round} too shallow for any runner" if runner.nil?

        entry = cab.add_drawer(:z => z, :height => height, :runner => runner)
        refresh(cab)

        {
          :kind => :drawer, :cabinet_id => cab.id, :entry => entry,
          :z => z, :height => height,
          :runner => runner.key, :runner_length => runner.length,
          :clearances => EGC::Model::Hardware.runner_clearances,
          :box_width => cab.internal_width - 2 * C::DRAWER_BOX_SIDE_GAP
        }
      end

      # ---- refresh ----------------------------------------------------------------
      # Any insertion changes the part set, so the same sync funnel applies.
      def refresh(cab)
        cab.rebuild!
        EGC::Model::Wardrobe.apply_exposed_edgeband!(cab) if cab.doorless?
        EGC::Ops::ProductionSync.after_structural_change(cab, :space_tool_insert)
      end
    end
  end
end
