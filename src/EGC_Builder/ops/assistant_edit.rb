# encoding: UTF-8
# frozen_string_literal: true
#
# assistant_edit (§1B) - the edit command surface.
#
# This is the ONLY sanctioned entry point for mutating a cabinet's
# dimensions. It guarantees the two-way sync contract:
#
#   set_dimensions / set_width / set_height / set_depth
#        -> Cabinet#resize!
#              -> rebuild! (gables, bottom, stretchers, back, shelves)
#              -> ProductionSync.after_resize!
#                    -> EGC_PART dictionaries rewritten for every part
#                    -> Cutlist.invalidate_cache!
#                    -> CAM.reset_toolpaths!
#
# There is no path that changes a dimension without going through resize!,
# which is what makes stale cutlists structurally impossible rather than a
# thing we remember to avoid.

module EGC
  module Ops
    module AssistantEdit
      module_function

      # ---- dimension edits ------------------------------------------------
      def set_width(cabinet, mm)
        validate_positive!(mm, 'width')
        cabinet.resize!(:width => mm)
      end

      def set_height(cabinet, mm)
        validate_positive!(mm, 'height')
        cabinet.resize!(:height => mm)
      end

      def set_depth(cabinet, mm)
        validate_positive!(mm, 'depth')
        cabinet.resize!(:depth => mm)
      end

      # Batch edit; a single rebuild + single cache flush for the whole batch.
      def set_dimensions(cabinet, width: nil, height: nil, depth: nil)
        validate_positive!(width, 'width') if width
        validate_positive!(height, 'height') if height
        validate_positive!(depth, 'depth') if depth

        before = snapshot(cabinet)
        cabinet.resize!(:width => width, :height => height, :depth => depth)
        after = snapshot(cabinet)

        report(cabinet, before, after)
      end

      # ---- structural edits -------------------------------------------------
      def add_shelf(cabinet, type: :fixed, z: nil)
        cabinet.add_shelf(:type => type, :z => z)
        after_structural(cabinet)
      end

      def add_divider(cabinet, x:)
        cabinet.add_divider(:x => x)
        after_structural(cabinet)
      end

      def add_door(cabinet, side: :single, hinge: :left)
        cabinet.add_door(:side => side, :hinge => hinge)
        after_structural(cabinet)
      end

      def add_drawer(cabinet, z:, height:)
        cabinet.add_drawer(:z => z, :height => height)
        after_structural(cabinet)
      end

      def add_hanging_rod(cabinet, z: nil)
        cabinet.add_hanging_rod(:z => z)
        after_structural(cabinet)
      end

      # ---- helpers ----------------------------------------------------------
      def after_structural(cabinet)
        cabinet.rebuild!
        # Open units must keep their exposed edge banding after any change.
        EGC::Model::Wardrobe.apply_exposed_edgeband!(cabinet) if cabinet.doorless?
        EGC::Ops::ProductionSync.after_structural_change(cabinet, :structure)
      end

      def validate_positive!(mm, name)
        raise ArgumentError, "#{name} must be a positive number, got #{mm.inspect}" if mm.nil?
        raise ArgumentError, "#{name} must be positive, got #{mm}" unless mm.to_f.positive?
      end

      def snapshot(cabinet)
        {
          :width => cabinet.width, :height => cabinet.height, :depth => cabinet.depth,
          :tag => cabinet.effective_tag, :parts => cabinet.parts.length
        }
      end

      def report(cabinet, before, after)
        {
          :cabinet => cabinet.id,
          :before => before,
          :after => after,
          :reclassified => (before[:tag] != after[:tag]),
          :effective_tag => after[:tag],
          :parts => after[:parts],
          :cutlist_generation => EGC::Cutlist.generation,
          :cam_generation => EGC::CAM.generation
        }
      end

      # ---- in-model edit (SketchUp instance edit) ---------------------------
      # Accepts a raw provider (e.g. an Entities object) whose transform
      # encodes a scale. Extracts the millimetre dimensions and routes through
      # the same resize pipeline.
      def apply_model_scale(cabinet, transform_scale)
        sw, sh, sd = transform_scale
        set_dimensions(cabinet,
                       :width => cabinet.width * sw,
                       :height => cabinet.height * sh,
                       :depth => cabinet.depth * sd)
      end
    end
  end
end
