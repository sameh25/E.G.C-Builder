# encoding: UTF-8
# frozen_string_literal: true
#
# Edge-banding policy.
#
# A panel has four edges:
#   :left / :right  -> the two ends of its LENGTH axis
#   :front / :back  -> the two edges running ALONG the length axis
#
# `EdgeBand` is an immutable value object describing which of the four edges
# receive banding, plus the derived cut oversize. Exposed (visible) edges get
# banding; hidden edges (against a gable, against a wall) do not.

module EGC
  module Model
    class EdgeBand
      SIDES = [:left, :right, :front, :back].freeze

      attr_reader :sides

      def initialize(sides = {})
        @sides = {}
        SIDES.each { |s| @sides[s] = !!(sides[s] || sides[s.to_s]) }
        freeze
      end

      def self.none
        new({})
      end

      def self.all
        new(SIDES.each_with_object({}) { |s, h| h[s] = true })
      end

      def self.of(*list)
        new(list.flatten.each_with_object({}) { |s, h| h[s.to_sym] = true })
      end

      # Build from a compact code such as "L,R,F" or "LR" / "---".
      def self.parse(code)
        return none if code.nil?
        s = code.to_s.upcase
        sides = []
        sides << :left  if s.include?('L') || s.include?('1')
        sides << :right if s.include?('R') || s.include?('2')
        sides << :front if s.include?('F') || s.include?('3')
        sides << :back  if s.include?('B') || s.include?('4')
        of(*sides)
      end

      def [](side)
        @sides[side.to_sym]
      end

      def edged?(side)
        !!@sides[side.to_sym]
      end

      def any?
        @sides.values.any?
      end

      def none?
        !any?
      end

      def count
        @sides.values.count(true)
      end

      # Oversize along the LENGTH axis (left+right edges banded).
      def length_oversize(allowance = EGC::Constants::EDGEBAND_TRIM_ALLOWANCE)
        (edged?(:left) ? allowance : 0.0) + (edged?(:right) ? allowance : 0.0)
      end

      # Oversize along the WIDTH axis (front+back edges banded).
      def width_oversize(allowance = EGC::Constants::EDGEBAND_TRIM_ALLOWANCE)
        (edged?(:front) ? allowance : 0.0) + (edged?(:back) ? allowance : 0.0)
      end

      def merge(other)
        return self if other.nil?
        combined = {}
        SIDES.each { |s| combined[s] = edged?(s) || other.edged?(s) }
        EdgeBand.new(combined)
      end

      def with(*list)
        merge(EdgeBand.of(*list))
      end

      def without(*list)
        drop = list.flatten.map(&:to_sym)
        combined = {}
        SIDES.each { |s| combined[s] = edged?(s) && !drop.include?(s) }
        EdgeBand.new(combined)
      end

      def to_code
        out = +''
        out << (edged?(:left) ? 'L' : '-')
        out << (edged?(:right) ? 'R' : '-')
        out << (edged?(:front) ? 'F' : '-')
        out << (edged?(:back) ? 'B' : '-')
        out
      end

      def to_h
        @sides.dup
      end

      def ==(o)
        o.is_a?(EdgeBand) && o.to_h == to_h
      end
      alias eql? ==

      def hash
        to_h.hash
      end

      def inspect
        "#<EdgeBand #{to_code}>"
      end
    end
  end
end
