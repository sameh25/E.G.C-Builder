# encoding: UTF-8
# frozen_string_literal: true
#
# appliances (§5) - appliance bay validation.
#
# An appliance bay is a base cabinet whose interior must accept a given
# appliance respecting the frozen service clearances. This module only
# CHECKS and REPORTS; it never resizes a cabinet to make an appliance fit.

module EGC
  module Ops
    module Appliances
      C = EGC::Constants

      CATALOGUE = {
        :oven_single   => { :name => 'Single oven',      :width => 595.0, :height => 595.0, :depth => 550.0 },
        :oven_double   => { :name => 'Double oven',      :width => 595.0, :height => 880.0, :depth => 550.0 },
        :dishwasher    => { :name => 'Dishwasher',       :width => 598.0, :height => 818.0, :depth => 550.0 },
        :fridge_tall   => { :name => 'Tall fridge',      :width => 600.0, :height => 1850.0, :depth => 560.0 },
        :microwave     => { :name => 'Microwave',        :width => 495.0, :height => 285.0, :depth => 380.0 },
        :hob           => { :name => 'Hob',              :width => 580.0, :height => 20.0,  :depth => 510.0 }
      }.freeze

      module_function

      def catalogue
        CATALOGUE
      end

      # Required bay envelope for an appliance, including clearances.
      def required_bay(key)
        app = CATALOGUE[key.to_sym]
        return nil if app.nil?
        {
          :width => app[:width] + 2 * C::APPLIANCE_SIDE_CLEARANCE,
          :height => app[:height] + C::APPLIANCE_TOP_CLEARANCE,
          :depth => app[:depth] + C::APPLIANCE_REAR_CLEARANCE,
          :appliance => app
        }
      end

      # Checks one cabinet against one appliance.
      def check(cabinet, key)
        req = required_bay(key)
        raise ArgumentError, "unknown appliance #{key.inspect}" if req.nil?

        iw = cabinet.internal_width
        ih = cabinet.internal_height
        id = cabinet.internal_depth

        fits_w = iw >= req[:width] - 1e-6
        fits_h = ih >= req[:height] - 1e-6
        fits_d = id >= req[:depth] - 1e-6

        {
          :cabinet => cabinet.id, :cabinet_name => cabinet.name,
          :appliance => key, :appliance_name => req[:appliance][:name],
          :fits => (fits_w && fits_h && fits_d),
          :fits_width => fits_w, :fits_height => fits_h, :fits_depth => fits_d,
          :internal => { :width => iw.round(1), :height => ih.round(1), :depth => id.round(1) },
          :required => { :width => req[:width].round(1), :height => req[:height].round(1), :depth => req[:depth].round(1) },
          :shortfall => {
            :width => [req[:width] - iw, 0.0].max.round(1),
            :height => [req[:height] - ih, 0.0].max.round(1),
            :depth => [req[:depth] - id, 0.0].max.round(1)
          }
        }
      end

      # Validates every appliance assignment in a document.
      # assignments: { cabinet_id => :appliance_key }
      def validate(doc, assignments)
        results = assignments.map do |cab_id, key|
          cab = doc.find(cab_id)
          next nil if cab.nil?
          check(cab, key)
        end.compact

        failures = results.reject { |r| r[:fits] }
        { :ok => failures.empty?, :results => results, :failures => failures }
      end

      # Reports cabinets whose effective tag is :tall - these are the legal
      # hosts for freestanding appliance towers.
      def tower_candidates(doc)
        doc.cabinets.select { |c| c.tall? }.map(&:summary)
      end
    end
  end
end
