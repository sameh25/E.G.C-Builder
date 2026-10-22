# encoding: UTF-8
# frozen_string_literal: true
#
# E.G.C Builder - Dimensional & Machining Constants
# ---------------------------------------------------------------------------
# CRITICAL: The numeric values in ::FROZEN are contractual. They are the
# single source of truth for every dimension, clearance, toolpath offset,
# kerf and drilling depth/diameter in the system.
#
# No code path may mutate them. Every entry is deep-frozen at load time and a
# SHA-256 fingerprint is computed over the canonical serialisation. Call
# EGC::Constants.verify! at boot (and in tests) to prove nothing drifted.
#
# Vertical stack (floor -> up):
#   0 ........................... floor
#   TOE_KICK_HEIGHT (150) ....... top of plinth
#   + BASE_CARCASS_HEIGHT (720) . top of carcass  = 870
#   + COUNTER_THICKNESS (30) .... top of worktop   = 900 = STANDARD_COUNTER_HEIGHT
# ---------------------------------------------------------------------------

require 'digest'

module EGC
  module Constants
    # ---- Carcass / panel ------------------------------------------------
    PANEL_THICKNESS            = 18.0   # mm, standard carcass board
    BACK_THICKNESS             = 8.0    # mm, back panel
    BACK_RECESS                = 20.0   # mm, back panel set in from rear
    DOOR_THICKNESS             = 18.0   # mm, door / front
    DRAWER_BOX_THICKNESS       = 16.0   # mm
    DRAWER_BOTTOM_THICKNESS    = 8.0    # mm

    # ---- Global vertical layout -----------------------------------------
    STANDARD_COUNTER_HEIGHT    = 900.0  # mm, finished worktop TOP surface
    COUNTER_THICKNESS          = 30.0   # mm, worktop slab
    TOE_KICK_HEIGHT            = 150.0  # mm
    TOE_KICK_SETBACK           = 50.0   # mm
    BASE_CARCASS_HEIGHT        = 720.0  # mm, carcass only, sits on plinth
    BASE_UNIT_NOMINAL_HEIGHT   = 870.0  # mm, floor -> top of carcass
    WALL_UNIT_NOMINAL_HEIGHT   = 720.0  # mm

    # ---- Rails (top open carcass for counter units) ---------------------
    TOP_RAIL_HEIGHT            = 100.0  # mm
    TOP_RAIL_DEPTH             = 100.0  # mm

    # ---- Tall-unit isolation (§1) ---------------------------------------
    TALL_UNIT_THRESHOLD        = 1100.0 # mm, anything above is a tower
    TALL_UNIT_NOMINAL_HEIGHT   = 2100.0 # mm
    WORKTOP_OVERHANG_FRONT     = 20.0   # mm
    WORKTOP_SIDE_OVERHANG      = 0.0    # mm, butt termination at gable
    WORKTOP_BUTT_TOLERANCE     = 0.5    # mm, contact detection for butt
    WORKTOP_MIN_SEGMENT        = 50.0   # mm, ignore slivers between towers

    # ---- Shelf / interior -----------------------------------------------
    SHELF_THICKNESS            = 18.0   # mm
    SHELF_SETBACK              = 20.0   # mm, from front edge of gable
    SHELF_DEPTH_REDUCTION      = 20.0   # mm, clearance to back
    ADJUSTABLE_SHELF_CLEARANCE = 2.0    # mm, total slack for lift-in

    # ---- Fronts / gaps ---------------------------------------------------
    DOOR_GAP                   = 2.0    # mm, per edge
    DOOR_REVEAL                = 3.0    # mm, to carcass
    DOOR_OVERLAY               = 16.0   # mm, full overlay
    DRAWER_FRONT_GAP           = 2.0    # mm

    # ---- Drawer runners (§4 clearances) ----------------------------------
    RUNNER_CLEARANCE_SIDE      = 12.5   # mm, per side, box to carcass
    DRAWER_BOX_SIDE_GAP        = 12.5   # mm
    DRAWER_BOX_BACK_CLEARANCE  = 10.0   # mm
    DRAWER_BOTTOM_GROOVE       = 8.0    # mm, up from box bottom
    DRAWER_RUNNER_HEIGHT_OFFSET = 20.0  # mm, first hole from box bottom

    # ---- Hanging rod ------------------------------------------------------
    HANGING_ROD_DIAMETER       = 25.0   # mm
    HANGING_ROD_OFFSET_FROM_FRONT = 300.0 # mm, centreline behind front
    HANGING_ROD_BRACKET_DRILL_DIAMETER = 5.0
    HANGING_ROD_HEIGHT_BELOW_TOP = 100.0 # mm

    # ---- Edge banding ----------------------------------------------------
    EDGEBAND_THICKNESS         = 1.0    # mm
    EDGEBAND_TRIM_ALLOWANCE    = 2.0    # mm, per edged side

    # ---- Nesting / machining (§3) ---------------------------------------
    SAW_KERF                   = 4.4    # mm, blade kerf - DO NOT ALTER
    BORDER_TRIM                = 10.0   # mm, sheet border trim - DO NOT ALTER
    SHEET_LENGTH               = 2440.0 # mm
    SHEET_WIDTH                = 1220.0 # mm
    SHEET_THICKNESS            = 18.0   # mm
    MIN_OFFCUT_USABLE          = 120.0  # mm, smallest reclaimed filler
    STRIP_GROUP_WIDTH_TOL      = 0.5    # mm, identical-width grouping tolerance

    # ---- Drilling (§ values frozen) -------------------------------------
    DRILL_HINGE_DIAMETER       = 35.0   # mm
    DRILL_HINGE_DEPTH          = 13.0   # mm
    DRILL_HINGE_EDGE_OFFSET    = 22.5   # mm, cup centre from door edge
    DRILL_SHELF_PIN_DIAMETER   = 5.0    # mm
    DRILL_SHELF_PIN_DEPTH      = 13.0   # mm
    DRILL_DOWEL_DIAMETER       = 8.0    # mm
    DRILL_DOWEL_DEPTH          = 12.0   # mm
    DRILL_CAM_DIAMETER         = 15.0   # mm
    DRILL_CAM_DEPTH            = 12.5   # mm
    DRILL_HANDLE_DIAMETER      = 5.0    # mm
    DRILL_HANDLE_DEPTH         = 13.0   # mm
    SYSTEM32_PITCH             = 32.0   # mm
    SYSTEM32_EDGE_OFFSET       = 37.0   # mm
    DRILL_SAFE_MARGIN          = 8.0    # mm, min material around a drilled hole

    # ---- Snap / tolerance ------------------------------------------------
    SNAP_TOLERANCE             = 10.0   # mm
    INTERFERENCE_TOLERANCE     = 0.1    # mm
    CORNER_FILLER_MIN          = 20.0   # mm
    CORNER_FILLER_MAX          = 120.0  # mm

    # ---- Appliance service clearances -----------------------------------
    APPLIANCE_SIDE_CLEARANCE   = 5.0    # mm
    APPLIANCE_TOP_CLEARANCE    = 10.0   # mm
    APPLIANCE_REAR_CLEARANCE   = 50.0   # mm

    # Canonical manifest. Keys are the authoritative names; values are the
    # contractual numbers above. Used for fingerprinting & drift detection.
    FROZEN = {
      :panel_thickness              => PANEL_THICKNESS,
      :back_thickness               => BACK_THICKNESS,
      :back_recess                  => BACK_RECESS,
      :door_thickness               => DOOR_THICKNESS,
      :drawer_box_thickness         => DRAWER_BOX_THICKNESS,
      :drawer_bottom_thickness      => DRAWER_BOTTOM_THICKNESS,
      :standard_counter_height      => STANDARD_COUNTER_HEIGHT,
      :counter_thickness            => COUNTER_THICKNESS,
      :toe_kick_height              => TOE_KICK_HEIGHT,
      :toe_kick_setback             => TOE_KICK_SETBACK,
      :base_carcass_height          => BASE_CARCASS_HEIGHT,
      :base_unit_nominal_height     => BASE_UNIT_NOMINAL_HEIGHT,
      :wall_unit_nominal_height     => WALL_UNIT_NOMINAL_HEIGHT,
      :top_rail_height              => TOP_RAIL_HEIGHT,
      :top_rail_depth               => TOP_RAIL_DEPTH,
      :tall_unit_threshold          => TALL_UNIT_THRESHOLD,
      :tall_unit_nominal_height     => TALL_UNIT_NOMINAL_HEIGHT,
      :worktop_overhang_front       => WORKTOP_OVERHANG_FRONT,
      :worktop_side_overhang        => WORKTOP_SIDE_OVERHANG,
      :worktop_butt_tolerance       => WORKTOP_BUTT_TOLERANCE,
      :worktop_min_segment          => WORKTOP_MIN_SEGMENT,
      :shelf_thickness              => SHELF_THICKNESS,
      :shelf_setback                => SHELF_SETBACK,
      :shelf_depth_reduction        => SHELF_DEPTH_REDUCTION,
      :adjustable_shelf_clearance   => ADJUSTABLE_SHELF_CLEARANCE,
      :door_gap                     => DOOR_GAP,
      :door_reveal                  => DOOR_REVEAL,
      :door_overlay                 => DOOR_OVERLAY,
      :drawer_front_gap             => DRAWER_FRONT_GAP,
      :runner_clearance_side        => RUNNER_CLEARANCE_SIDE,
      :drawer_box_side_gap          => DRAWER_BOX_SIDE_GAP,
      :drawer_box_back_clearance    => DRAWER_BOX_BACK_CLEARANCE,
      :drawer_bottom_groove         => DRAWER_BOTTOM_GROOVE,
      :drawer_runner_height_offset  => DRAWER_RUNNER_HEIGHT_OFFSET,
      :hanging_rod_diameter         => HANGING_ROD_DIAMETER,
      :hanging_rod_offset_from_front => HANGING_ROD_OFFSET_FROM_FRONT,
      :hanging_rod_bracket_drill_diameter => HANGING_ROD_BRACKET_DRILL_DIAMETER,
      :hanging_rod_height_below_top => HANGING_ROD_HEIGHT_BELOW_TOP,
      :edgeband_thickness           => EDGEBAND_THICKNESS,
      :edgeband_trim_allowance      => EDGEBAND_TRIM_ALLOWANCE,
      :saw_kerf                     => SAW_KERF,
      :border_trim                  => BORDER_TRIM,
      :sheet_length                 => SHEET_LENGTH,
      :sheet_width                  => SHEET_WIDTH,
      :sheet_thickness              => SHEET_THICKNESS,
      :min_offcut_usable            => MIN_OFFCUT_USABLE,
      :strip_group_width_tol        => STRIP_GROUP_WIDTH_TOL,
      :drill_hinge_diameter         => DRILL_HINGE_DIAMETER,
      :drill_hinge_depth            => DRILL_HINGE_DEPTH,
      :drill_hinge_edge_offset      => DRILL_HINGE_EDGE_OFFSET,
      :drill_shelf_pin_diameter     => DRILL_SHELF_PIN_DIAMETER,
      :drill_shelf_pin_depth        => DRILL_SHELF_PIN_DEPTH,
      :drill_dowel_diameter         => DRILL_DOWEL_DIAMETER,
      :drill_dowel_depth            => DRILL_DOWEL_DEPTH,
      :drill_cam_diameter           => DRILL_CAM_DIAMETER,
      :drill_cam_depth              => DRILL_CAM_DEPTH,
      :drill_handle_diameter        => DRILL_HANDLE_DIAMETER,
      :drill_handle_depth           => DRILL_HANDLE_DEPTH,
      :system32_pitch               => SYSTEM32_PITCH,
      :system32_edge_offset         => SYSTEM32_EDGE_OFFSET,
      :drill_safe_margin            => DRILL_SAFE_MARGIN,
      :snap_tolerance               => SNAP_TOLERANCE,
      :interference_tolerance       => INTERFERENCE_TOLERANCE,
      :corner_filler_min            => CORNER_FILLER_MIN,
      :corner_filler_max            => CORNER_FILLER_MAX,
      :appliance_side_clearance     => APPLIANCE_SIDE_CLEARANCE,
      :appliance_top_clearance      => APPLIANCE_TOP_CLEARANCE,
      :appliance_rear_clearance     => APPLIANCE_REAR_CLEARANCE
    }.freeze

    # Behavioural (non-geometric) flags. Changing these is allowed by design.
    GRAIN_ROTATION_DEFAULT = true
    CACHE_ENABLED          = true

    def self.canonical_source
      FROZEN.keys.map { |k| "#{k}=#{format('%.6f', FROZEN[k])}" }.join('|')
    end

    def self.fingerprint
      Digest::SHA256.hexdigest(canonical_source)
    end

    # Baseline captured at 1.28.67 release. verify! fails loudly on drift.
    EXPECTED_FINGERPRINT = '0a4c347975b826b427f848f73d5abb14516e718f14e46dccb819b097984b297f'

    def self.verify!
      actual = fingerprint
      return true if actual == EXPECTED_FINGERPRINT
      raise EGC::IntegrityError,
            "EGC dimensional constants drifted! expected #{EXPECTED_FINGERPRINT}, got #{actual}. " \
            'Values are contractual and must not be modified.'
    end

    # Deep-freeze every geometric value.
    FROZEN.each_value { |v| v.freeze }
  end
end
