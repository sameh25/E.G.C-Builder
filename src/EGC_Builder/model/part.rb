# encoding: UTF-8
# frozen_string_literal: true
#
# A single machined panel. This is the atom the Cutlist, CAM and Nesting
# engines all consume, and it owns the EGC_PART attribute dictionary that §2
# requires to be refreshed synchronously on every cabinet edit.
#
# Dimensions are the FINISHED cut size (banding already accounted for).
# `cut_length` / `cut_width` are the raw blank size including banding trim.

require 'securerandom'

module EGC
  module Model
    class Part
      ROLE_GABLE_L   = :gable_left
      ROLE_GABLE_R   = :gable_right
      ROLE_TOP_RAIL  = :top_rail
      ROLE_BOTTOM    = :bottom
      ROLE_SHELF     = :shelf
      ROLE_DIVIDER   = :divider
      ROLE_BACK      = :back
      ROLE_DOOR      = :door
      ROLE_DRAWER_FRONT = :drawer_front
      ROLE_DRAWER_SIDE  = :drawer_side
      ROLE_DRAWER_BACK  = :drawer_back
      ROLE_DRAWER_BOTTOM = :drawer_bottom
      ROLE_STRETCHER = :stretcher
      ROLE_FILLER    = :filler
      ROLE_ROD       = :hanging_rod
      ROLE_PLINTH    = :plinth

      STRUCTURAL_ROLES = [
        ROLE_GABLE_L, ROLE_GABLE_R, ROLE_TOP_RAIL, ROLE_BOTTOM,
        ROLE_SHELF, ROLE_DIVIDER, ROLE_BACK, ROLE_STRETCHER
      ].freeze

      attr_reader :id, :role, :material, :length, :width, :thickness, :edgeband, :cabinet_id
      attr_accessor :quantity, :label, :drills, :room, :notes, :grain_axis, :position, :orientation

      def initialize(role, length:, width:, thickness:, material:, edgeband: nil,
                     cabinet_id: nil, id: nil, label: nil, quantity: 1, grain_axis: :length,
                     position: nil, orientation: :normal_z)
        @id          = id || "P#{SecureRandom.hex(5)}"
        @role        = role.to_sym
        @length      = length.to_f
        @width       = width.to_f
        @thickness   = thickness.to_f
        @material    = EGC::Model::Materials.normalise(material)
        @edgeband    = edgeband || EGC::Model::EdgeBand.none
        @cabinet_id  = cabinet_id
        @label       = label || @role.to_s
        @quantity    = quantity.to_i
        @drills      = []
        @room        = nil
        @notes       = nil
        @grain_axis  = grain_axis.to_sym
        @position    = position
        @orientation = orientation.to_sym
      end

      # World-space axis-aligned box for this part.
      # `orientation` names the axis the panel's THICKNESS runs along:
      #   :normal_x -> thickness in X, width in Y, length in Z  (gable, divider)
      #   :normal_y -> thickness in Y, length in X, width in Z  (back panel, plinth)
      #   :normal_z -> thickness in Z, length in X, width in Y  (deck, shelf, rail)
      def box
        return nil if @position.nil?
        p = @position
        case @orientation
        when :normal_x
          EGC::Geom::Box.new(p, p.offset(@thickness, @width, @length))
        when :normal_y
          EGC::Geom::Box.new(p, p.offset(@length, @thickness, @width))
        when :normal_z
          EGC::Geom::Box.new(p, p.offset(@length, @width, @thickness))
        else
          EGC::Geom::Box.new(p, p.offset(@length, @width, @thickness))
        end
      end

      # ---- derived -----------------------------------------------------
      def area_mm2
        @length * @width
      end

      def area_m2
        area_mm2 / 1_000_000.0
      end

      def volume_mm3
        area_mm2 * @thickness
      end

      def grain?
        @material.has_grain
      end

      # Rotation policy consumed by nesting (§3).
      def rotatable?
        !@material.has_grain
      end

      def cut_length
        (@length + @edgeband.length_oversize).round(2)
      end

      def cut_width
        (@width + @edgeband.width_oversize).round(2)
      end

      def code
        "#{@role}:#{EGC::Units.fmt_mm(@length)}x#{EGC::Units.fmt_mm(@width)}x#{EGC::Units.fmt_mm(@thickness)}"
      end

      # Structural key used for grouping identical parts in the cutlist.
      def group_key
        [@role, @thickness.round(2), [@length.round(2), @width.round(2)].sort,
         @material.key, @edgeband.to_code]
      end

      def add_drill(drill)
        @drills << drill
        drill
      end

      # Replaces the banding policy (used when an open unit must expose edges).
      def apply_edgeband(band)
        @edgeband = band.is_a?(EGC::Model::EdgeBand) ? band : EGC::Model::EdgeBand.parse(band)
      end

      def add_edgeband(*sides)
        @edgeband = @edgeband.with(*sides)
      end

      def with(**overrides)
        p = dup
        overrides.each { |k, v| p.instance_variable_set("@#{k}", v) }
        p
      end

      # ---- §2 attribute sync -------------------------------------------
      # Dict name is PER ENTITY, exactly like a SketchUp AttributeDictionary
      # attached to an entity. Using one shared "EGC_PART" key would make each
      # part overwrite the previous one.
      def dict_name
        "#{EGC::Scene::Document::PART}_#{@id}"
      end

      # Writes the canonical EGC_PART dictionary. Called on creation AND on
      # every resize, so the cutlist/CAM/nesting never see a stale size.
      def write_attributes(store, dict = nil, seq = nil)
        dict ||= dict_name
        store.set(dict, 'id', @id)
        store.set(dict, 'role', @role.to_s)
        store.set(dict, 'label', @label.to_s)
        store.set(dict, 'material', @material.key.to_s)
        store.set(dict, 'has_grain', @material.has_grain)
        store.set(dict, 'length', @length.round(2))
        store.set(dict, 'width', @width.round(2))
        store.set(dict, 'thickness', @thickness.round(2))
        store.set(dict, 'cut_length', cut_length)
        store.set(dict, 'cut_width', cut_width)
        store.set(dict, 'edgeband', @edgeband.to_code)
        store.set(dict, 'quantity', @quantity)
        store.set(dict, 'cabinet_id', @cabinet_id.to_s)
        store.set(dict, 'area_m2', area_m2.round(4))
        store.set(dict, 'drill_count', @drills.length)
        store.set(dict, 'revision_seq', seq) unless seq.nil?
        @id
      end

      # Reads a part back out of a store (round-trip verification in tests).
      def self.read_attributes(store, part_id, dict = nil)
        dict ||= "#{EGC::Scene::Document::PART}_#{part_id}"
        return nil unless store.get(dict, 'id') == part_id
        {
          :role => store.get(dict, 'role').to_sym,
          :length => store.get(dict, 'length'),
          :width => store.get(dict, 'width'),
          :thickness => store.get(dict, 'thickness'),
          :cut_length => store.get(dict, 'cut_length'),
          :cut_width => store.get(dict, 'cut_width'),
          :edgeband => store.get(dict, 'edgeband'),
          :material => store.get(dict, 'material'),
          :cabinet_id => store.get(dict, 'cabinet_id')
        }
      end

      def to_h
        {
          :id => @id, :role => @role, :label => @label, :material => @material.key,
          :length => @length.round(2), :width => @width.round(2),
          :thickness => @thickness.round(2), :quantity => @quantity,
          :edgeband => @edgeband.to_code, :area_m2 => area_m2.round(4),
          :cabinet_id => @cabinet_id
        }
      end

      def inspect
        format('#<Part %s %.1fx%.1fx%.1f %s>', @role, @length, @width, @thickness, @material.key)
      end
    end
  end
end
