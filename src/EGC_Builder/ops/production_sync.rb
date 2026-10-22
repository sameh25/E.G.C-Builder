# encoding: UTF-8
# frozen_string_literal: true
#
# ProductionSync (§2) - the single funnel that keeps derived artefacts true.
#
# Any dimensional edit funnels through Cabinet#resize!, which calls
# ProductionSync.after_resize. That method is responsible for:
#
#   2  synchronously re-write every EGC_PART attribute dictionary
#   3  invalidate the cutlist cache and reset CAM toolpaths
#
# and it emits a :production_synced event so the nesting layout is rebuilt
# lazily but from fresh data. Ordering is contractual: parts first, then
# caches, so a cache rebuild can never read stale part sizes.

module EGC
  module Ops
    module ProductionSync
      module_function

      # Called immediately after Cabinet#rebuild! inside resize!.
      def after_resize(cabinet, changed = {})
        seq = cabinet.revision

        # (2) synchronous EGC_PART refresh for every part of this cabinet
        refreshed = refresh_part_attributes(cabinet, seq)

        # (3) drop derived caches
        invalidate_derived!(cabinet, :cabinet_resized)

        EGC::Log.info(
          "synced #{refreshed} parts after resize #{changed.keys.join('/')}",
          cabinet.id
        )

        notify(cabinet, :resize, changed, refreshed)
        { :parts_refreshed => refreshed, :seq => seq }
      end

      # Any structural change that is not a resize (shelf added, door added).
      def after_structural_change(cabinet, reason = :structure)
        refreshed = refresh_part_attributes(cabinet, cabinet.revision)
        invalidate_derived!(cabinet, reason)
        notify(cabinet, reason, {}, refreshed)
        refreshed
      end

      # Re-writes the attribute store for all parts. Returns the count written.
      def refresh_part_attributes(cabinet, seq = nil)
        doc = cabinet.document
        return 0 if doc.nil?
        cabinet.ensure_parts!
        cabinet.parts.each do |part|
          part.write_attributes(doc.attributes, part.dict_name, seq)
        end
        cabinet.parts.length
      end

      # Clears every cache that could hold a stale size.
      def invalidate_derived!(cabinet, reason = :unknown)
        EGC::Cutlist.invalidate_cache!(reason) if defined?(EGC::Cutlist)
        EGC::CAM.reset_toolpaths!(reason) if defined?(EGC::CAM)
        EGC::Nesting.invalidate_layout!(reason) if defined?(EGC::Nesting)

        doc = cabinet.document
        if doc
          doc.touch!(:production_synced)
          doc.notify(:production_synced, { :cabinet => cabinet, :reason => reason })
        end
        true
      end

      # Full-document resync, used by the audit command and after load.
      def resync_document!(doc)
        count = 0
        doc.cabinets.each do |cab|
          cab.ensure_parts!
          count += refresh_part_attributes(cab, cab.revision)
        end
        EGC::Cutlist.invalidate_cache!(:document_resync) if defined?(EGC::Cutlist)
        EGC::CAM.reset_toolpaths!(:document_resync) if defined?(EGC::CAM)
        EGC::Nesting.invalidate_layout!(:document_resync) if defined?(EGC::Nesting)
        doc.touch!(:production_synced)
        count
      end

      def notify(cabinet, reason, changed, refreshed)
        doc = cabinet.document
        return unless doc
        doc.notify(:cabinet_changed, {
                     :cabinet => cabinet, :reason => reason,
                     :changed => changed, :parts_refreshed => refreshed
                   })
      end
    end
  end
end
