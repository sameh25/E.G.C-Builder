# encoding: UTF-8
# frozen_string_literal: true
#
# Material registry. `has_grain` drives the nesting rotation policy (§3):
#   has_grain == true  -> part may NOT be rotated 90deg (grain must run along
#                         the strip direction of the sheet).
#   has_grain == false -> free rotation (plain / solid colours, MDF, HPL).
#
# Materials are hash-like ([ ] access, fetch, to_h) because the original
# codebase and the nesting engine both read them as hashes.

require 'json'

module EGC
  module Model
    class Material
      attr_reader :key, :name, :has_grain, :thickness, :color, :kind, :density

      def initialize(key, name, has_grain:, thickness: EGC::Constants::PANEL_THICKNESS,
                     color: '#CCCCCC', kind: :board, density: 0.72)
        @key       = key.to_sym
        @name      = name.to_s
        @has_grain = !!has_grain
        @thickness = thickness.to_f
        @color     = color.to_s
        @kind      = kind.to_sym
        @density   = density.to_f
        freeze
      end

      # Hash-compatible access (string or symbol keys).
      def [](key)
        k = key.to_sym
        return @has_grain if k == :has_grain
        return @name if k == :name
        return @thickness if k == :thickness
        return @color if k == :color
        return @kind if k == :kind
        return @density if k == :density
        return @key if k == :key
        nil
      end

      def fetch(key, default = nil)
        v = self[key]
        v.nil? ? default : v
      end

      def key?(key)
        !self[key].nil?
      end

      def grain?
        @has_grain
      end

      # Plain / solid-colour surfaces behave like grain-free boards.
      def rotation_allowed?
        !@has_grain
      end

      def to_h
        {
          :key => @key, :name => @name, :has_grain => @has_grain,
          :thickness => @thickness, :color => @color, :kind => @kind,
          :density => @density
        }
      end

      def ==(o)
        o.is_a?(Material) && o.key == key
      end
      alias eql? ==

      def hash
        key.hash
      end

      def inspect
        "#<Material #{@key} grain=#{@has_grain}>"
      end
    end

    module Materials
      # Built-in defaults. `load_from_json!` may overlay materials.json, but
      # the BUILT-IN table is authoritative for has_grain on the standard
      # boards - a data file can add materials, never silently flip the grain
      # policy of a known one.
      BUILTIN = {
        :white_melamine   => Material.new(:white_melamine,   'White Melamine',    :has_grain => false, :color => '#F2F2F2'),
        :grey_melamine    => Material.new(:grey_melamine,    'Grey Melamine',     :has_grain => false, :color => '#9A9A9A'),
        :oak_veneer       => Material.new(:oak_veneer,       'Oak Veneer',        :has_grain => true,  :color => '#C79A5B'),
        :walnut_veneer    => Material.new(:walnut_veneer,    'Walnut Veneer',     :has_grain => true,  :color => '#6B4423'),
        :hpl_plain        => Material.new(:hpl_plain,        'HPL Plain',         :has_grain => false, :color => '#3C6E71'),
        :mdf_plain        => Material.new(:mdf_plain,        'MDF Plain',         :has_grain => false, :color => '#C8B79A'),
        :back_hdf         => Material.new(:back_hdf,         'Back HDF 8mm',      :has_grain => false,
                                          :thickness => EGC::Constants::BACK_THICKNESS, :color => '#B0A489'),
        :drawer_birch     => Material.new(:drawer_birch,     'Birch Ply 16mm',    :has_grain => true,
                                          :thickness => EGC::Constants::DRAWER_BOX_THICKNESS, :color => '#E3C79A'),
        :drawer_base      => Material.new(:drawer_base,      'Drawer Base 8mm',   :has_grain => false,
                                          :thickness => EGC::Constants::DRAWER_BOTTOM_THICKNESS, :color => '#D9C6A1'),
        :counter_stone    => Material.new(:counter_stone,    'Engineered Stone',  :has_grain => false,
                                          :thickness => EGC::Constants::COUNTER_THICKNESS, :color => '#DDD8CE', :kind => :worktop),
        :counter_laminate => Material.new(:counter_laminate, 'Laminate Worktop',  :has_grain => true,
                                          :thickness => EGC::Constants::COUNTER_THICKNESS, :color => '#B9A58B', :kind => :worktop)
      }.freeze

      @registry = BUILTIN.dup
      @source = :builtin

      class << self
        attr_reader :source

        def all
          @registry
        end

        # Overlays materials.json. Existing keys keep their built-in
        # has_grain; new keys are added. Unknown/missing file is non-fatal.
        def load_from_json!(path)
          return false unless File.exist?(path)
          data = JSON.parse(File.read(path))
          added = 0
          Array(data['materials']).each do |m|
            key = m['key'].to_s.to_sym
            next if key.empty?
            if BUILTIN.key?(key)
              # keep built-in object: contract values win
              next
            end
            @registry[key] = Material.new(
              key, m['name'] || key.to_s,
              :has_grain => !!m['has_grain'],
              :thickness => (m['thickness'] || EGC::Constants::PANEL_THICKNESS),
              :color => m['color'] || '#CCCCCC',
              :kind => (m['kind'] || 'board').to_sym
            )
            added += 1
          end
          @source = path
          EGC::Log.debug("materials.json loaded: #{added} added, #{@registry.length} total")
          true
        rescue StandardError => e
          EGC::Log.warn("materials.json ignored (#{e.class}: #{e.message})")
          false
        end

        def reset!
          @registry = BUILTIN.dup
          @source = :builtin
        end
      end

      DEFAULT = :white_melamine
      DEFAULT_BACK = :back_hdf
      DEFAULT_DRAWER_BOX = :drawer_birch
      DEFAULT_DRAWER_BASE = :drawer_base
      DEFAULT_WORKTOP = :counter_stone

      module_function

      def get(key, fallback = DEFAULT)
        key = key.to_sym if key.is_a?(String)
        all[key] || all[fallback] || all[DEFAULT]
      end

      def exists?(key)
        all.key?(key.is_a?(String) ? key.to_sym : key)
      end

      def keys
        all.keys
      end

      def grain?(key)
        get(key).has_grain
      end

      def rotation_allowed?(key)
        get(key).rotation_allowed?
      end

      # Accepts a Material, a Symbol/String key, or a Hash ({has_grain: false}).
      def normalise(material)
        return material if material.is_a?(Material)
        if material.is_a?(Hash)
          hg = material.key?(:has_grain) ? material[:has_grain] : material['has_grain']
          name = material[:name] || material['name'] || 'Custom'
          return Material.new(:custom, name, :has_grain => !!hg,
                              :thickness => (material[:thickness] || material['thickness'] || EGC::Constants::PANEL_THICKNESS))
        end
        get(material)
      end
    end
  end
end
