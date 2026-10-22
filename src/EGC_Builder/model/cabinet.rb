# encoding: UTF-8
# frozen_string_literal: true
#
# Cabinet: the unit of placement. Owns its tag classification (base / wall /
# tall), its bounding box, its generated parts, and the rebuild pipeline that
# keeps parts + attributes + caches in lock-step (§2).
#
# §1 CLASSIFICATION RULE
# ----------------------
# `effective_tag` is authoritative and is derived, never stored blindly:
#   * If height > TALL_UNIT_THRESHOLD (1100mm)  -> :tall, whatever the tag says
#   * Otherwise the declared tag is used (base / wall)
# This makes an edited/base cabinet that was scaled above 1100mm
# automatically a tower, so the worktop engine can never run into it.

require 'securerandom'

module EGC
  module Model
    class Cabinet
      TAGS = [:base, :wall, :tall].freeze
      C = EGC::Constants

      attr_reader :id, :declared_tag, :origin, :width, :height, :depth, :name
      attr_reader :parts, :shelves, :doors, :drawers, :rod_config
      attr_accessor :document, :material, :plinth, :options, :handle_type

      def initialize(tag = :base, width: 600.0, height: nil, depth: 560.0,
                     origin: nil, name: nil, material: nil, options: {})
        @id            = options.delete(:id) || "C#{SecureRandom.hex(5)}"
        @declared_tag  = validate_tag(tag)
        @width         = width.to_f
        @depth         = depth.to_f
        @height        = (height || default_height_for(@declared_tag)).to_f
        @origin        = origin || EGC::Geom::Vec3.new(0, 0, 0)
        @name          = name || "#{@declared_tag.to_s.capitalize}-#{@width.round}"
        @material      = EGC::Model::Materials.normalise(material || EGC::Model::Materials::DEFAULT)
        @options       = { :has_back => true, :has_plinth => true }.merge(options)
        @plinth        = @options[:has_plinth]
        @handle_type   = @options[:handle] || :handle_bar_128
        @parts         = []
        @shelves       = []       # Array<Hash{ type:, z:, inset:, id: }>
        @doors        = []        # Array<Hash{ leaf:, side:, hinge: }>
        @drawers      = []        # Array<Hash{ z:, height:, runner: }>
        @rod_config   = nil
        @document     = nil
        @revision     = 0
        @rebuild_count = 0
      end

      def validate_tag(t)
        sym = t.to_s.downcase.to_sym
        raise EGC::CabinetError, "unknown cabinet tag #{t.inspect} (expected #{TAGS.inspect})" unless TAGS.include?(sym)
        sym
      end

      # ---- classification (§1) -----------------------------------------
      # Derived, authoritative tag. Never trust the declared tag for geometry.
      def effective_tag
        return :tall if tall_by_height?
        return :wall if @declared_tag == :wall
        :base
      end

      def tall_by_height?
        @height > C::TALL_UNIT_THRESHOLD
      end

      # True when the unit was originally declared short but has grown into a
      # tower - surfaced in the audit report.
      def reclassified?
        tall_by_height? && @declared_tag != :tall
      end

      def base?
        effective_tag == :base
      end

      def wall?
        effective_tag == :wall
      end

      def tall?
        effective_tag == :tall
      end

      # A counter-top unit accepts a worktop. Towers and wall units do not.
      def accepts_worktop?
        base?
      end

      # ---- geometry -----------------------------------------------------
      def bounding_box
        EGC::Geom::Box.from_whd(@origin, @width, @height, @depth)
      end

      def top_z
        @origin.z + @height
      end

      def bottom_z
        @origin.z
      end

      def front_y
        @origin.y + @depth
      end

      def x_min
        @origin.x
      end

      def x_max
        @origin.x + @width
      end

      # Horizontal span [x0, x1] of the carcass, including an optional
      # overhang applied by subclasses.
      def span
        [x_min, x_max]
      end

      # Worktop contact planes (§1 butt termination): both vertical side
      # gables are valid termination faces for an abutting counter run.
      def side_gable_planes
        [x_min, x_max]
      end

      # ---- shelving / fronts --------------------------------------------
      def add_shelf(type: :fixed, z: nil, inset: C::SHELF_SETBACK)
        type = type.to_sym
        raise ArgumentError, "shelf type must be :fixed or :adjustable" unless [:fixed, :adjustable].include?(type)
        z = default_shelf_z if z.nil?
        entry = { :type => type, :z => z.to_f, :inset => inset.to_f, :id => "S#{SecureRandom.hex(4)}" }
        @shelves << entry
        entry
      end

      def add_divider(x:, inset: C::SHELF_SETBACK)
        entry = { :type => :divider, :x => x.to_f, :inset => inset.to_f, :id => "D#{SecureRandom.hex(4)}" }
        @shelves << entry
        entry
      end

      def add_door(side: :single, hinge: :left)
        entry = { :side => side.to_sym, :hinge => hinge.to_sym, :leaf => 1 }
        @doors << entry
        entry
      end

      def add_drawer(z:, height:, runner: nil)
        runner ||= EGC::Model::Hardware.runner_for_depth(internal_depth)
        raise EGC::CabinetError, 'cabinet too shallow for any runner' if runner.nil?
        entry = { :z => z.to_f, :height => height.to_f, :runner => runner }
        @drawers << entry
        entry
      end

      def add_hanging_rod(z: nil)
        z ||= internal_top_z - C::HANGING_ROD_HEIGHT_BELOW_TOP
        @rod_config = {
          :z => z.to_f,
          :y => front_y - C::HANGING_ROD_OFFSET_FROM_FRONT,
          :diameter => C::HANGING_ROD_DIAMETER
        }
        @rod_config
      end

      def doorless?
        @doors.empty?
      end

      def drawerless?
        @drawers.empty?
      end

      # ---- internal cavity (door-free, §4) ------------------------------
      # Derived ONLY from the inner faces of the left/right gables, the top
      # panel and the bottom deck. No reference to any door face - this is
      # what removes the nil:NilClass crash on doorless units.
      def inner_void
        EGC::Geom::Box.new(
          EGC::Geom::Vec3.new(inner_x0, inner_y0, internal_bottom_z),
          EGC::Geom::Vec3.new(inner_x1, inner_y1, internal_top_z)
        )
      end

      # ---- inner faces ----------------------------------------------------
      def inner_x0
        @origin.x + C::PANEL_THICKNESS
      end

      def inner_x1
        @origin.x + @width - C::PANEL_THICKNESS
      end

      # Front face of the back panel.
      def inner_y0
        @origin.y + C::BACK_RECESS + C::BACK_THICKNESS
      end

      # Open front plane.
      def inner_y1
        @origin.y + @depth
      end

      def internal_width
        @width - 2 * C::PANEL_THICKNESS
      end

      # Clear depth from the back-panel front face to the open front.
      def internal_depth
        @depth - C::BACK_RECESS - C::BACK_THICKNESS
      end

      # Height of the top obstruction: a base unit is closed by a front top
      # rail (TOP_RAIL_HEIGHT), everything else by an 18mm top panel.
      def top_obstruction_height
        return C::PANEL_THICKNESS unless accepts_worktop?
        [C::TOP_RAIL_HEIGHT, @height - 2 * C::PANEL_THICKNESS].min
      end

      def internal_top_z
        @origin.z + @height - top_obstruction_height
      end

      def internal_bottom_z
        @origin.z + C::PANEL_THICKNESS
      end

      def internal_height
        internal_top_z - internal_bottom_z
      end

      # Horizontal cavities between shelves, ordered bottom -> top.
      # Used by space_tool single-click zone detection (§4).
      def cavities
        bounds = [internal_bottom_z] + horizontal_shelf_levels + [internal_top_z]
        out = []
        bounds.each_cons(2) do |lo, hi|
          next if (hi - lo) <= 1.0
          out << { :z0 => lo, :z1 => hi, :height => hi - lo }
        end
        out
      end

      def horizontal_shelf_levels
        levels = @shelves.select { |s| s[:type] == :fixed || s[:type] == :adjustable }.map { |s| s[:z] }
        levels.select { |z| z > internal_bottom_z && z < internal_top_z }.sort
      end

      # ---- defaults ------------------------------------------------------
      def default_height_for(tag)
        case tag
        when :base then C::BASE_CARCASS_HEIGHT
        when :wall then C::WALL_UNIT_NOMINAL_HEIGHT
        when :tall then C::TALL_UNIT_NOMINAL_HEIGHT
        end
      end

      def default_shelf_z
        internal_bottom_z + internal_height / 2.0
      end

      # ---- attachment ----------------------------------------------------
      def attach(doc)
        @document = doc
      end

      # ---- detach -------------------------------------------------------
      def detach
        @document = nil
      end

      # ---- §2 resize pipeline -------------------------------------------
      # Single entry point for any dimensional change. Guarantees the exact
      # order required by the spec:
      #   1. update dimensions
      #   2. immediate internal component redraw (rebuild!)
      #   3. synchronously refresh EGC_PART dictionaries
      #   4. invalidate cutlist cache + reset CAM toolpaths
      def resize!(width: nil, height: nil, depth: nil)
        changed = {}
        changed[:width]  = width.to_f  if width  && (width.to_f  - @width).abs  > 1e-6
        changed[:height] = height.to_f if height && (height.to_f - @height).abs > 1e-6
        changed[:depth]  = depth.to_f  if depth  && (depth.to_f  - @depth).abs  > 1e-6
        return self if changed.empty?

        was_tall = tall?
        @width  = changed[:width]  if changed.key?(:width)
        @height = changed[:height] if changed.key?(:height)
        @depth  = changed[:depth]  if changed.key?(:depth)
        @revision += 1

        # (2) redraw internals
        rebuild!

        # (3) synchronous attribute refresh + (4) cache invalidation
        EGC::Ops::ProductionSync.after_resize(self, changed)

        if !was_tall && tall?
          EGC::Log.info("cabinet #{@name} reclassified to :tall (h=#{@height})", @id)
        end
        @document.touch!(:cabinet_changed) if @document
        self
      end

      def revision
        @revision
      end

      def rebuild_count
        @rebuild_count
      end

      # Regenerates every part from current dimensions. Idempotent.
      def rebuild!
        @parts = EGC::Model::CarcassBuilder.build(self)
        @rebuild_count += 1
        @document.reindex_parts!(self) if @document
        @parts
      end

      # Ensures parts exist before a read.
      def ensure_parts!
        rebuild! if @parts.empty?
        @parts
      end

      # ---- reporting -----------------------------------------------------
      def summary
        {
          :id => @id, :name => @name, :declared_tag => @declared_tag,
          :effective_tag => effective_tag, :reclassified => reclassified?,
          :width => @width.round(1), :height => @height.round(1), :depth => @depth.round(1),
          :origin => @origin.to_a.map { |v| v.round(1) },
          :doors => @doors.length, :drawers => @drawers.length, :shelves => @shelves.length,
          :parts => @parts.length
        }
      end

      def inspect
        format('#<Cabinet %s %s %.0fx%.0fx%.0f parts=%d>', @name, effective_tag, @width, @height, @depth, @parts.length)
      end
    end
  end
end
