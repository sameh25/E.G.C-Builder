# encoding: UTF-8
# frozen_string_literal: true
#
# Hardware library: runners, hinges, handles, shelf pins, rod brackets.
# Every entry carries the frozen drilling values by reference - it never
# stores its own copy, so a drill diameter can never drift per-record.

module EGC
  module Model
    class HardwareItem
      attr_reader :key, :name, :kind, :length, :unit_cost

      def initialize(key, name, kind, length: nil, unit_cost: 0.0)
        @key = key.to_sym
        @name = name
        @kind = kind.to_sym
        @length = length
        @unit_cost = unit_cost.to_f
        freeze
      end

      def [](k)
        case k.to_sym
        when :key then @key
        when :name then @name
        when :kind then @kind
        when :length then @length
        when :unit_cost then @unit_cost
        end
      end

      def inspect
        "#<HardwareItem #{@key}>"
      end
    end

    module Hardware
      C = EGC::Constants

      DRAWER_RUNNERS = {
        :runner_250 => HardwareItem.new(:runner_250, 'Ball-bearing runner 250', :runner, :length => 250.0, :unit_cost => 3.2),
        :runner_300 => HardwareItem.new(:runner_300, 'Ball-bearing runner 300', :runner, :length => 300.0, :unit_cost => 3.8),
        :runner_350 => HardwareItem.new(:runner_350, 'Ball-bearing runner 350', :runner, :length => 350.0, :unit_cost => 4.4),
        :runner_400 => HardwareItem.new(:runner_400, 'Ball-bearing runner 400', :runner, :length => 400.0, :unit_cost => 5.1),
        :runner_450 => HardwareItem.new(:runner_450, 'Ball-bearing runner 450', :runner, :length => 450.0, :unit_cost => 5.8),
        :runner_500 => HardwareItem.new(:runner_500, 'Ball-bearing runner 500', :runner, :length => 500.0, :unit_cost => 6.5)
      }.freeze

      HINGES = {
        :hinge_110 => HardwareItem.new(:hinge_110, 'Clip-on hinge 110deg', :hinge, :unit_cost => 1.9),
        :hinge_165 => HardwareItem.new(:hinge_165, 'Wide-angle hinge 165deg', :hinge, :unit_cost => 3.4)
      }.freeze

      HANDLES = {
        :handle_bar_128  => HardwareItem.new(:handle_bar_128, 'Bar handle 128cc', :handle, :length => 128.0, :unit_cost => 2.6),
        :handle_bar_160  => HardwareItem.new(:handle_bar_160, 'Bar handle 160cc', :handle, :length => 160.0, :unit_cost => 3.0),
        :handle_knob     => HardwareItem.new(:handle_knob, 'Knob', :handle, :unit_cost => 1.4)
      }.freeze

      ACCESSORIES = {
        :shelf_pin     => HardwareItem.new(:shelf_pin, 'Shelf pin 5mm', :pin, :unit_cost => 0.05),
        :rod_bracket   => HardwareItem.new(:rod_bracket, 'Rod bracket', :bracket, :unit_cost => 0.9),
        :hanging_rod   => HardwareItem.new(:hanging_rod, 'Hanging rod 25mm', :rod, :unit_cost => 7.5),
        :cam_lock      => HardwareItem.new(:cam_lock, 'Cam lock 15mm', :cam, :unit_cost => 0.22),
        :dowel         => HardwareItem.new(:dowel, 'Dowel 8mm', :dowel, :unit_cost => 0.04)
      }.freeze

      ALL = DRAWER_RUNNERS.merge(HINGES).merge(HANDLES).merge(ACCESSORIES).freeze

      module_function

      def get(key)
        ALL[key.to_sym] if key.respond_to?(:to_sym)
      end

      def runners
        DRAWER_RUNNERS
      end

      # Picks the longest runner that fits the given internal cabinet depth
      # WITHOUT changing the runner clearance constants.
      def runner_for_depth(internal_depth_mm)
        usable = internal_depth_mm - C::DRAWER_BOX_BACK_CLEARANCE
        candidates = DRAWER_RUNNERS.values.select { |r| r.length <= usable }
        return nil if candidates.empty?
        candidates.max_by { |r| r.length }
      end

      # Runner clearance diagnostics, used by drawer modules (§4).
      def runner_clearances
        {
          :side => C::RUNNER_CLEARANCE_SIDE,
          :back => C::DRAWER_BOX_BACK_CLEARANCE,
          :bottom_groove => C::DRAWER_BOTTOM_GROOVE,
          :height_offset => C::DRAWER_RUNNER_HEIGHT_OFFSET
        }
      end
    end
  end
end
