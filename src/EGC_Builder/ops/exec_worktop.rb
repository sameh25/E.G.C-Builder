# encoding: UTF-8
# frozen_string_literal: true
#
# exec_worktop (§1) - Worktop plane isolation & tall-unit clamping.
#
# THE DEFECT THIS REPLACES
# ------------------------
# The legacy generator computed the counter top as `run.map(&:bounds).max_by(&:max.z).max.z`
# i.e. it queried `bounds.max.z` across the whole run. A base cabinet that had
# been edited/scaled above counter height (or a tower tagged as base) pushed
# that maximum up, so the counter was extruded at the TALL unit's height and
# speared through the room.
#
# THE NEW CONTRACT
# ----------------
# 1. Eligibility never looks at a bounding box maximum. It reads the derived
#    classification:
#        cabinet.effective_tag == :base  AND  cabinet.height <= TALL_UNIT_THRESHOLD
#    So a >1100mm cabinet is excluded regardless of the tag it was created
#    with, and Cabinet#effective_tag reclassifies edited units to :tall.
# 2. The extrusion plane is a CONSTANT: STANDARD_COUNTER_HEIGHT. It is never
#    derived from geometry. `top_z` is clamped to it, always.
# 3. A run stops cleanly at any tower's side gable (butt termination): the
#    segment ends on the gable plane with no overhang and no pass-through.

module EGC
  module Ops
    module ExecWorktop
      C = EGC::Constants

      module_function

      # ---- eligibility (§1 rules 1) -------------------------------------
      # Derived from classification, NEVER from bounds.max.z.
      def worktop_eligible?(cabinet)
        return false if cabinet.nil?
        return false if cabinet.height.to_f > C::TALL_UNIT_THRESHOLD
        return false unless cabinet.accepts_worktop?
        cabinet.effective_tag == :base
      end

      # Cabinets that block a run. Anything reclassified as tall acts as a
      # hard stop, even if it was originally created as a base unit.
      def tower?(cabinet)
        return false if cabinet.nil?
        cabinet.height.to_f > C::TALL_UNIT_THRESHOLD || cabinet.effective_tag == :tall
      end

      # ---- the clamped plane (§1 rule 2) ---------------------------------
      # Constant, not geometry-derived.
      def top_z
        C::STANDARD_COUNTER_HEIGHT
      end

      def slab_bottom_z
        C::STANDARD_COUNTER_HEIGHT - C::COUNTER_THICKNESS
      end

      # Asserts the invariant. Returns the clamped value; raises on violation
      # so a regression can never silently ship a floating counter.
      def clamp_plane!(value)
        if value.to_f > C::STANDARD_COUNTER_HEIGHT + 1e-6
          raise EGC::IntegrityError,
                "worktop plane #{value} exceeds STANDARD_COUNTER_HEIGHT (#{C::STANDARD_COUNTER_HEIGHT})"
        end
        value.to_f
      end

      # ---- run detection ---------------------------------------------------
      # Groups eligible base cabinets that actually abut on the X axis and
      # share a front plane. Towers terminate runs.
      def plan(doc, _opts = {})
        cabinets = doc.cabinets
        eligible = cabinets.select { |c| worktop_eligible?(c) }
        towers   = cabinets.select { |c| tower?(c) }
        blocked  = cabinets.reject { |c| worktop_eligible?(c) || tower?(c) }

        runs = build_runs(eligible, towers)
        segments = runs.flat_map { |run| segment_run(run, towers) }
        segments = segments.reject { |s| s[:width] < C::WORKTOP_MIN_SEGMENT }

        {
          :plane_top_z => top_z,
          :plane_bottom_z => slab_bottom_z,
          :thickness => C::COUNTER_THICKNESS,
          :runs => runs,
          :segments => segments,
          :excluded => {
            :tall => towers.map { |c| c.summary },
            :other => blocked.map { |c| c.summary }
          },
          :eligible_count => eligible.length,
          :tower_count => towers.length
        }
      end

      # Chains worktop_eligible cabinets into contiguous runs.
      def build_runs(eligible, towers)
        sorted = eligible.sort_by { |c| c.x_min }
        runs = []
        current = []
        sorted.each do |cab|
          if current.empty?
            current = [cab]
            next
          end
          prev = current.last
          if contiguous?(prev, cab, towers)
            current << cab
          else
            runs << current
            current = [cab]
          end
        end
        runs << current unless current.empty?
        runs.map { |r| r.sort_by { |c| c.x_min } }
      end

      # Two cabinets continue the same run when they touch (within the butt
      # tolerance), share the front plane, and nothing tall sits between.
      def contiguous?(prev, cab, towers)
        gap = cab.x_min - prev.x_max
        return false if gap > C::WORKTOP_BUTT_TOLERANCE
        return false if gap < -C::WORKTOP_BUTT_TOLERANCE
        return false if (prev.front_y - cab.front_y).abs > C::WORKTOP_BUTT_TOLERANCE
        # a tower strictly between them breaks the run
        towers.none? do |t|
          t.x_min > prev.x_max - C::WORKTOP_BUTT_TOLERANCE &&
            t.x_max < cab.x_min + C::WORKTOP_BUTT_TOLERANCE
        end
      end

      # ---- segment generation (§1 rule 3) ---------------------------------
      # Produces one slab segment per contiguous stretch, terminated exactly on
      # the neighbouring tower's side gable (butt), never overlapping it.
      def segment_run(run, towers)
        return [] if run.empty?
        first = run.first
        last  = run.last

        # Left termination: butt against a tower's right gable if one abuts.
        x0 = first.x_min
        left_tower = towers.find { |t| (t.x_max - x0).abs <= C::WORKTOP_BUTT_TOLERANCE }
        if left_tower
          x0 = left_tower.x_max          # butt: no overhang
          left_termination = :butt
        else
          x0 -= C::WORKTOP_SIDE_OVERHANG
          left_termination = :free
        end

        # Right termination: butt against a tower's left gable if one abuts.
        x1 = last.x_max
        right_tower = towers.find { |t| (t.x_min - x1).abs <= C::WORKTOP_BUTT_TOLERANCE }
        if right_tower
          x1 = right_tower.x_min         # butt: no overhang
          right_termination = :butt
        else
          x1 += C::WORKTOP_SIDE_OVERHANG
          right_termination = :free
        end

        # front edge gets the standard overhang
        y0 = run.map(&:origin).map(&:y).min
        y1 = run.map(&:front_y).max + C::WORKTOP_OVERHANG_FRONT

        z_top = clamp_plane!(top_z)
        z_bot = slab_bottom_z

        [
          {
            :x0 => x0.round(2), :x1 => x1.round(2),
            :y0 => y0.round(2), :y1 => y1.round(2),
            :z0 => z_bot.round(2), :z1 => z_top.round(2),
            :width => (x1 - x0).round(2),
            :depth => (y1 - y0).round(2),
            :thickness => C::COUNTER_THICKNESS,
            :top_z => z_top,
            :left_termination => left_termination,
            :right_termination => right_termination,
            :termination_gables => {
              :left => left_tower ? left_tower.id : nil,
              :right => right_tower ? right_tower.id : nil
            },
            :cabinet_ids => run.map(&:id),
            :box => EGC::Geom::Box.new(
              EGC::Geom::Vec3.new(x0, y0, z_bot),
              EGC::Geom::Vec3.new(x1, y1, z_top)
            )
          }
        ]
      end

      # ---- worktop parts / cutlist integration ------------------------------
      # Converts planned segments into Model::Part records so they flow into
      # the cutlist, nesting and CAM like any other panel.
      def to_parts(plan_result, material: EGC::Model::Materials::DEFAULT_WORKTOP)
        plan_result[:segments].each_with_index.map do |seg, i|
          EGC::Model::Part.new(
            :worktop,
            :length => seg[:width], :width => seg[:depth],
            :thickness => seg[:thickness],
            :material => material,
            :edgeband => EGC::Model::EdgeBand.all,
            :cabinet_id => nil,
            :label => "Worktop segment #{i + 1}",
            :position => EGC::Geom::Vec3.new(seg[:x0], seg[:y0], seg[:z0]),
            :orientation => :normal_z
          )
        end
      end

      # ---- validation --------------------------------------------------------
      # Proves the two §1 invariants after generation.
      def validate(plan_result)
        errors = []

        plan_result[:segments].each do |seg|
          if seg[:z1] > C::STANDARD_COUNTER_HEIGHT + 1e-6
            errors << "segment z1 #{seg[:z1]} exceeds standard counter height"
          end
          if seg[:z1] != top_z
            errors << "segment top #{seg[:z1]} is not clamped to #{top_z}"
          end
        end

        # No segment may overlap a tower's footprint.
        plan_result[:excluded][:tall].each do |t|
          tbox = EGC::Geom::Box.new(
            EGC::Geom::Vec3.new(t[:origin][0], t[:origin][1], t[:origin][2]),
            EGC::Geom::Vec3.new(t[:origin][0] + t[:width], t[:origin][1] + t[:depth], t[:origin][2] + t[:height])
          )
          plan_result[:segments].each do |seg|
            if seg[:box].overlaps?(tbox, C::INTERFERENCE_TOLERANCE)
              errors << "segment #{seg[:x0]}..#{seg[:x1]} intersects tower #{t[:name]}"
            end
          end
        end

        { :ok => errors.empty?, :errors => errors }
      end
    end
  end
end
