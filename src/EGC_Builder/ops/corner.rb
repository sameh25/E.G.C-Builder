# encoding: UTF-8
# frozen_string_literal: true
#
# corner (§5) - L-shaped / corner run resolution.
#
# Two runs meeting at a corner either overlap by a cabinet's width (blind
# corner) or leave a gap (needs a filler). This module computes the filler
# required and never modifies any cabinet dimension - it only reports the
# gap and proposes a filler PART of exactly that size.

module EGC
  module Ops
    module Corner
      C = EGC::Constants

      module_function

      # Detects corners between two axis-aligned runs.
      # run_a occupies X, run_b occupies Y (an L). Returns corner descriptors.
      def detect(doc, opts = {})
        tol = opts.fetch(:tolerance, C::WORKTOP_BUTT_TOLERANCE)
        corners = []

        sorted = doc.cabinets.sort_by { |c| c.x_min }
        sorted.combination(2) do |a, b|
          next unless perpendicular?(a, b, tol)
          next unless near_corner?(a, b, tol)
          corners << describe(a, b, tol)
        end

        { :corners => corners, :count => corners.length }
      end

      def perpendicular?(a, b, tol)
        # a's depth run crosses b's width run
        a_spans_x = (a.x_max - a.x_min) > tol
        b_spans_x = (b.x_max - b.x_min) > tol
        a_spans_x != b_spans_x
      end

      def near_corner?(a, b, tol)
        gap = EGC::Geom.box_gap(a.bounding_box, b.bounding_box)
        gap <= tol + C::CORNER_FILLER_MAX
      end

      def describe(a, b, tol)
        gap = EGC::Geom.box_gap(a.bounding_box, b.bounding_box)
        filler = if gap <= tol
                   0.0
                 elsif gap < C::CORNER_FILLER_MIN
                   C::CORNER_FILLER_MIN
                 else
                   gap
                 end

        {
          :a => a.id, :b => b.id,
          :a_name => a.name, :b_name => b.name,
          :gap_mm => gap.round(2),
          :filler_required => filler.positive?,
          :filler_size_mm => filler.round(2),
          :filler_within_limits => filler <= C::CORNER_FILLER_MAX,
          :overlapping => gap <= tol,
          :kind => (filler.positive? ? :filler_needed : :blind_corner)
        }
      end

      # Generates a filler part for a corner descriptor (no cabinet mutation).
      def filler_part(corner, height:, depth:, material: nil)
        size = corner[:filler_size_mm]
        return nil unless corner[:filler_required] && size.positive?
        EGC::Model::Part.new(
          EGC::Model::Part::ROLE_FILLER,
          :length => height, :width => size, :thickness => depth,
          :material => material || EGC::Model::Materials::DEFAULT,
          :edgeband => EGC::Model::EdgeBand.of(:front),
          :label => "Corner filler #{size.round}mm",
          :orientation => :normal_x
        )
      end

      def validate(corners)
        errors = []
        corners[:corners].each do |c|
          if c[:filler_size_mm] > C::CORNER_FILLER_MAX
            errors << "corner #{c[:a_name]}/#{c[:b_name]} needs #{c[:filler_size_mm]}mm filler (max #{C::CORNER_FILLER_MAX})"
          end
        end
        { :ok => errors.empty?, :errors => errors }
      end
    end
  end
end
