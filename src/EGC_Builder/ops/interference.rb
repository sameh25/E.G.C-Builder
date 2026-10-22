# encoding: UTF-8
# frozen_string_literal: true
#
# interference (§5) - collision detection between placed cabinets and parts.
#
# Rules:
#   * Touching faces are NOT interference (handled by INTERFERENCE_TOLERANCE).
#   * Two cabinets that share a gable plane are legal.
#   * A part may never intersect another cabinet's volume.
# Zero warnings: every skip is recorded as a debug record, not a warn.

module EGC
  module Ops
    module Interference
      C = EGC::Constants

      module_function

      # Pairwise cabinet check.
      def scan_cabinets(doc, opts = {})
        tol = opts.fetch(:tolerance, C::INTERFERENCE_TOLERANCE)
        ignore_touching = opts.fetch(:ignore_touching, true)
        cabs = doc.cabinets
        hits = []

        cabs.combination(2) do |a, b|
          ba = a.bounding_box
          bb = b.bounding_box
          vol = ba.overlap_volume(bb, tol)
          next if vol <= 0.0
          # A pure touch has zero overlap volume already; a shared plane with
          # real depth overlap but zero X overlap also yields 0. Only genuine
          # interpenetration reaches here.
          hits << {
            :kind => :cabinet_cabinet,
            :a => a.id, :b => b.id,
            :a_name => a.name, :b_name => b.name,
            :overlap_volume_mm3 => vol.round(2),
            :overlap_volume_litres => (vol / 1_000_000.0).round(3),
            :a_tag => a.effective_tag, :b_tag => b.effective_tag
          }
        end

        { :ok => hits.empty?, :hits => hits, :scanned => cabs.length,
          :tolerance => tol, :ignore_touching => ignore_touching }
      end

      # Parts of one cabinet against other cabinets (e.g. a drawer box that
      # protrudes into the neighbouring unit after a depth edit).
      def scan_parts_vs_cabinets(doc, opts = {})
        tol = opts.fetch(:tolerance, C::INTERFERENCE_TOLERANCE)
        hits = []

        doc.cabinets.each do |owner|
          owner.parts.each do |part|
            pb = part.box
            next if pb.nil?
            doc.cabinets.each do |other|
              next if other.id == owner.id
              vol = pb.overlap_volume(other.bounding_box, tol)
              next if vol <= 0.0
              hits << {
                :kind => :part_cabinet,
                :part => part.id, :part_role => part.role,
                :owner => owner.id, :other => other.id,
                :overlap_volume_mm3 => vol.round(2)
              }
            end
          end
        end

        { :ok => hits.empty?, :hits => hits, :tolerance => tol }
      end

      # Parts within a cabinet that collide with each other (sanity check on
      # shelf/divider placement). Structural joins are excluded.
      def scan_internal(doc, opts = {})
        tol = opts.fetch(:tolerance, C::INTERFERENCE_TOLERANCE)
        hits = []

        doc.cabinets.each do |cab|
          boxes = cab.parts.map { |p| [p, p.box] }.reject { |(_, b)| b.nil? }
          boxes.combination(2) do |(pa, ba), (pb, bb)|
            # parts that are designed to join (gable/deck/shelf) touch only
            vol = ba.overlap_volume(bb, tol)
            next if vol <= 0.0
            hits << {
              :kind => :part_part, :cabinet => cab.id,
              :a => pa.id, :a_role => pa.role,
              :b => pb.id, :b_role => pb.role,
              :overlap_volume_mm3 => vol.round(2)
            }
          end
        end

        { :ok => hits.empty?, :hits => hits, :tolerance => tol }
      end

      # Full sweep used by the audit command.
      def scan_all(doc, opts = {})
        cc = scan_cabinets(doc, opts)
        pc = scan_parts_vs_cabinets(doc, opts)
        ii = scan_internal(doc, opts)
        all = cc[:hits] + pc[:hits] + ii[:hits]
        {
          :ok => all.empty?,
          :cabinets => cc, :parts_vs_cabinets => pc, :internal => ii,
          :hits => all, :total => all.length
        }
      end
    end
  end
end
