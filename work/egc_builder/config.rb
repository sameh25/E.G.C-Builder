# frozen_string_literal: true

require 'json'

module EGC
  module Config
    DEFAULTS = {
      # ---- kitchen heights (mm) ----
      'ceiling'      => 2800,
      'plinth'       => 100,
      'base_h'       => 900,   # floor -> top of countertop
      'top_thk'      => 20,    # marble / countertop
      'top_overhang' => 20,
      'base_d'       => 600,   # overall depth incl. door
      'gap_h'        => 600,   # clear zone above countertop
      'w1_h'         => 700,
      'w1_d'         => 400,
      'hood_d'       => 600,
      'hood_open_h'  => 300,
      'w2_enabled'   => true,
      'w2_h'         => 500,
      'w2_d'         => 600,
      'fascia_thk'   => 18,
      'unit_fascia'  => true,        # a unit placed on its own (tall, or a wall unit up to the top line) gets a finish strip on top
      'unit_fascia_h' => 100,        # height of that strip (mm)
      # ---- materials thickness ----
      'thk'          => 18,
      'back_thk'     => 6,
      'front_thk'    => 18,
      'gap'          => 3,
      # Approved standard drawer-box stock. Material identity/finish remains project-configurable.
      'drawer_thk'   => 18,
      'drawer_box_material' => 'Counter Melamine 18mm',
      'drawer_box_finish' => nil,
      # Approved inset back construction. The values are project-editable and affect generated geometry.
      'drawer_bottom_thk' => nil,
      'back_groove_depth' => 10,
      'back_groove_offset' => 5,
      'back_clearance' => 0,
      # ---- LED profile groove ----
      'led'          => true,
      'prod_hw_bores' => false, # owner 1.28.52-53: production outputs carry the boards + LED / back grooves - no drilling at all
      'ext_mat'      => 'front',   # EXTERNAL finish material key (visible sides / undersides). Default = the fronts' material; any material key may be set
      'led_w'        => 10,
      'led_depth'    => 10,
      'w1_led_off'   => 35,   # approved project value
      'cfg_rev'      => 7,
      'w2_led_off'   => 450,
      # ---- handles ----
      'handle'       => 'profile',   # profile | bar | pull | knob | cup | edge | flush | jpull | gola | push | none
      'sink_model'   => 'auto',      # auto | single | double | one_half | drainer | round
      'hob_model'    => 'auto',      # auto | one of Kitchen::HOB_MODELS (el_30 ... gas_glass_90)
      'handle_orient' => 'auto',     # auto | horizontal | vertical (bar / pull)
      'handle_pos'   => 'auto',      # auto | center | top | bottom | side
      'handle_offset' => 0,          # mm from the front edge to the handle (0 = type default)
      'profile_h'    => 35,          # edge grip profile: how much it adds to the door edge = how much shorter the board is cut (reference block: 35)
      # handle-free (gola) profiles: the section the gables are notched for. L = under the worktop, C = between two fronts. Enter the sizes of the profile that is bought.
      # Defaults: FOP sections (supplier drawings): L 27 x 56, C 26 x 72.7, wall unit 20 x 20, vertical single grip 48.25 x 36.6.
      'gola_brand' => 'fop', 'gola_l_h' => 56, 'gola_l_d' => 27, 'gola_c_h' => 72.7, 'gola_c_d' => 26,
      'gola_w_h' => 20, 'gola_w_d' => 20,        # wall unit profile: let into the front edge of the bottom panel
      'gola_v_w' => 48.25, 'gola_v_d' => 36.6,   # vertical single grip profile of a tall unit: on the gable, beside the door
      'gola_v2_w' => 66.5,                       # vertical DOUBLE grip profile (between the two doors of a tall unit)
      'gola_led' => false,                       # profiles with an LED strip: the strip is counted by the metre with each profile
      'gola_v_gap' => 18,                        # how much narrower the tall door is on its opening side (the grip slot)
      'gola_gap' => 30,                          # finger gap above a base front (how much shorter the front is)
      'front_style'  => 'flat',
      'kitchen_style' => 'custom',   # the style card last applied in the window (it only fills handle / front style / colours)
      'sink_smart_cut_w' => 0, 'sink_smart_cut_d' => 0, # worktop cut-out of the product sink SMG 107501706, from its template (0 = not given yet)
      'top_lip'      => 0,
      'front_strip_on' => false,     # optional upright front strip under the flat front rail of door base units (the strip the door closes onto)
      'front_rail_h' => 70,          # its height, mm
      'top_lip_w'    => 20,
      # ---- colours ----
      'carcass_color' => '#f1f0ea',
      'front_color'   => '#d9caae',
      'top_color'     => '#17171a',
      'back_color'    => '#e6e1d4',
      'profile_color' => '#111111',
      'plinth_color'  => '#141414',
      # ---- material names (cut list) ----
      'mat_names' => {
        'carcass' => 'Counter Melamine 18mm',
        'front'   => 'MDF Laminated 18mm',
        'back'    => 'MDF 6mm',
        'drawer'  => 'Counter Melamine 18mm',
        'top'     => 'Granite Black 20',
        'glass'   => 'Glass 4',
        'splash'  => 'Backsplash 10',
        'plinth'  => 'PVC Plinth Profile Black'
      },
      # ---- sheets / nesting ----
      'company' => { 'name' => '', 'phone' => '', 'address' => '' },
      'quote' => { 'margin_pct' => 20, 'vat_pct' => 14, 'discount_pct' => 0, 'valid_days' => 15 },
      # refrigerator open housing clearances (mm): NOT manufacturer data - REQUIRES_CONFIRMATION until the user confirms them for the real appliance
      'fridge_side_clear' => 2, 'fridge_top_clear' => 50, 'fridge_back_clear' => 50, 'fridge_clear_confirmed' => false, 'hob_oven_min_clear' => 40,
      'top_max_len' => 3000, 'splash_color' => '#e8e6df', 'upstand_h' => 0, 'splash_on' => false, 'splash_thk' => 10,
      # extra clearance added around every sink/hob worktop cutout beyond the nominal opening size,
      # so the real appliance (incl. its rim/frame) always drops in cleanly - matches the old tool's
      # per-appliance WORKTOP_CUTOUT_MARGIN_MM concept, kept as one global default (no new UI field).
      'cutout_margin' => 10,
      'end_panels' => false, 'island_overhang' => 300, 'aisle' => 1200,
      # Legacy/general dimensions describe the internal sheet; actual nesting uses the per-material map below.
      'sheet_l' => 2400, 'sheet_w' => 1200, 'kerf' => 4, 'trim' => 10,
      'grain_lock' => { 'front' => true, 'top' => true },
      # approved project stock dimensions [length, width] in mm; no generic nesting fallback
      'sheets' => { 'carcass' => [2400, 1200], 'front' => [2800, 1220], 'back' => [2400, 1200] },
      # ---- project price inputs (blank until supplied for this design) ----
      'currency' => 'EGP',
      'price_sheet' => {},
      'price_edge_m' => { '0.5' => nil, '2' => nil },
      'price_hw' => (%w[push_opener gola_m hinge hinge_bifold vent_grille imove_single_tray door_bin broom_pullout chef_table table_pullout electric_lift lemans_set gola_l_m gola_c_m gola_w_m gola_v_m gola_v2_m gola_led_m hinge_softclose hinge_push slide_pair undermount_slide slide_wheel handle profile_m leg plinth_clip plinth_m shelf_pin lift_up led_m rod_m rod_bracket slide_track_m basket basket_set spice_rack tray_rack waste_bin waste_bin_unit pantry_pullout pantry_fixed trolley box_unit wire_drawer laundry_bag plate_holder bifold_lift dish_rack cutlery_tray trouser_rack pulldown_rail]).to_h { |key| [key, nil] },
      # Device prices are supplied per project; absent entries remain visibly unpriced.
      'price_app' => %w[fridge oven microwave hob hob_gas hood hood_chimney hood_slim dishwasher washer dryer coffee wine_cooler warming sink freezer wall_rail].to_h { |key| [key, nil] },
      # top/glass/splash can be priced by area, length, or piece using project measurements.
      'material_pricing' => { 'top' => { 'basis' => 'unset', 'price' => nil }, 'glass' => { 'basis' => 'unset', 'price' => nil }, 'splash' => { 'basis' => 'unset', 'price' => nil } },
      # additional costs: kind pct (of the subtotal) | fixed | per_m2 (of board area). value nil = NOT SET (reported, never silently 0)
      'extra_costs' => [
        { 'name' => 'Manufacturing', 'kind' => 'pct', 'value' => nil }, { 'name' => 'Installation', 'kind' => 'pct', 'value' => nil },
        { 'name' => 'Transport', 'kind' => 'fixed', 'value' => nil }, { 'name' => 'Overhead', 'kind' => 'pct', 'value' => nil }
      ],
      'labor_pct' => 0
    }.freeze

    PROJECT_KEYS = %w[company quote mat_names currency drawer_thk drawer_box_material drawer_box_finish drawer_bottom_thk back_groove_depth back_groove_offset back_clearance sheet_l sheet_w sheets kerf trim grain_lock price_sheet price_m2 price_edge_m price_hw price_app material_pricing extra_costs labor_pct].freeze

    module_function

    def deep_dup(o)
      case o
      when Hash  then o.each_with_object({}) { |(k, v), h| h[k] = deep_dup(v) }
      when Array then o.map { |v| deep_dup(v) }
      else o
      end
    end

    def merge(base, over)
      out = deep_dup(base)
      (over || {}).each do |k, v|
        k = k.to_s
        out[k] = (v.is_a?(Hash) && out[k].is_a?(Hash)) ? merge(out[k], v) : v
      end
      out
    end

    def build(overrides = nil)
      c = merge(DEFAULTS, overrides)
      # Saved-settings migration (cfg_rev < 3). Two things older builds wrote into the user's saved settings are NOT user choices and must
      # not override the E.G.C standard: the old optional "2700" preset (ceiling 2700 + worktop 40 + upper depths 350/350) and the old tier-1 LED
      # default 30. Any other value the user typed is left alone.
      if overrides.is_a?(Hash) && overrides['cfg_rev'].to_i < 3
        if overrides['ceiling'].to_f == 2700 && overrides['top_thk'].to_f == 40 && overrides['w1_d'].to_f == 350 && overrides['w2_d'].to_f == 350
          c['ceiling'] = 2800
          c['top_thk'] = 20
          c['w1_d'] = 400
          c['w2_d'] = 600
        end
        c['w1_led_off'] = 35 if overrides['w1_led_off'].to_f == 30.0
      end
      # cfg_rev < 4: the previous DEFAULT back groove (10 deep, 5 from the rear edge) and the previous default material names are replaced by the
      # current standard (8 deep, 18 from the rear edge; Counter Melamine / MDF Laminated / MDF). A value the user typed himself is left alone.
      if overrides.is_a?(Hash) && overrides['cfg_rev'].to_i < 4
        { 'carcass' => 'Melamine White 18', 'front' => 'Front Beige Gloss 18', 'back' => 'HDF 6' }.each do |k, old|
          c['mat_names'][k] = DEFAULTS['mat_names'][k] if c['mat_names'].is_a?(Hash) && c['mat_names'][k] == old
        end
        c['cfg_rev'] = DEFAULTS['cfg_rev']
      end
      if overrides.is_a?(Hash) && overrides['cfg_rev'].to_i < 5 # previous default rear gap of the refrigerator (10 mm) -> 50 mm ventilation gap
        c['fridge_back_clear'] = 50 if overrides['fridge_back_clear'].to_f == 10
        c['cfg_rev'] = DEFAULTS['cfg_rev']
      end
      if overrides.is_a?(Hash) && overrides['cfg_rev'].to_i < 6 # delivery specification 2026-10-06: back groove 10 deep, 5 from the rear edge (the 8 / 18 default of 1.25 - 1.27 goes back)
        if c['back_groove_depth'].to_f == 8 && c['back_groove_offset'].to_f == 18
          c['back_groove_depth'] = 10
          c['back_groove_offset'] = 5
        end
        c['cfg_rev'] = DEFAULTS['cfg_rev']
      end
      if overrides.is_a?(Hash) && overrides['cfg_rev'].to_i < 7 # the previous DEFAULT profile height (20) -> the reference edge grip profile (35); a typed value is left alone
        c['profile_h'] = 35 if overrides['profile_h'].to_f == 20
        c['cfg_rev'] = DEFAULTS['cfg_rev']
      end
      migrate_drawer_defaults!(c)
    end

    # Sketchup.read_default evals the stored value, so raw JSON (with quotes) breaks it.
    # Values are stored base64-encoded instead.
    def read_json(key, default = {})
      raw = Sketchup.read_default('EGC_Builder', key, nil)
      return default if raw.nil?

      JSON.parse(raw.to_s.unpack1('m0'))
    rescue StandardError, ScriptError
      default
    end

    def write_json(key, obj)
      Sketchup.write_default('EGC_Builder', key, [JSON.generate(obj)].pack('m0'))
    rescue StandardError, ScriptError
      nil
    end

    def saved
      read_json('settings_b64', {})
    end

    def save(cfg)
      global = deep_dup(cfg || {})
      PROJECT_KEYS.each { |key| global.delete(key) }
      write_json('settings_b64', global)
    end

    # Commercial terms and stock/pricing belong to the active SketchUp model, not machine-wide defaults.
    def project_data(model = Sketchup.active_model)
      raw = model && model.get_attribute('egc_project', 'pricing_json', nil)
      raw ? JSON.parse(raw.to_s) : {}
    rescue StandardError, ScriptError
      {}
    end

    def for_project(cfg, model = Sketchup.active_model)
      out = deep_dup(cfg || DEFAULTS)
      stored = project_data(model)
      PROJECT_KEYS.each do |key|
        out[key] = deep_dup(stored.key?(key) ? stored[key] : DEFAULTS[key])
      end
      migrate_stock_defaults!(out)
      out
    end

    # TEST_10 stored the global 2800x2070 default per material. Migrate only that known bad pair;
    # preserve project-entered non-default dimensions and all prices.
    def migrate_stock_defaults!(cfg)
      approved = { 'front' => [2800, 1220], 'carcass' => [2400, 1200], 'back' => [2400, 1200] }
      wrong = [2800.0, 2070.0]
      stock = deep_dup(DEFAULTS['sheets']).merge(deep_dup(cfg['sheets'] || {}))
      stock.keys.each do |key|
        dims = Array(stock[key]).map(&:to_f)
        next unless dims == wrong

        material = key.to_s.split(':', 2).first
        if approved[material]
          stock[key] = approved[material].dup
        else
          stock.delete(key) # unknown material requires a project-specific stock declaration
        end
      end
      cfg['sheets'] = stock
      if cfg['sheet_l'].to_f == wrong[0] && cfg['sheet_w'].to_f == wrong[1]
        cfg['sheet_l'], cfg['sheet_w'] = DEFAULTS.values_at('sheet_l', 'sheet_w')
      end
      cfg['mat_names'] ||= {}
      migrate_drawer_defaults!(cfg)
      cfg
    end

    # TEST_13 treated an unset value as a placement blocker. The approved standard is now 18 mm.
    # A valid explicit project override is preserved; the unsupported legacy 16 mm default is migrated.
    def migrate_drawer_defaults!(cfg)
      thickness = cfg['drawer_thk'].to_f
      cfg['drawer_thk'] = 18 unless thickness.positive? && thickness != 16.0
      cfg['mat_names'] ||= {}
      # Production standard: drawer boxes use the SAME 18 mm carcass board; legacy separate drawer-board settings are ignored.
      cfg['mat_names']['drawer'] = cfg['mat_names']['carcass'] || DEFAULTS['mat_names']['carcass']
      cfg['drawer_box_material'] = cfg['mat_names']['drawer']
      cfg['drawer_box_finish'] = nil
      cfg['back_groove_depth'] = 10 if cfg['back_groove_depth'].nil?
      cfg['back_groove_offset'] = 5 if cfg['back_groove_offset'].nil?
      cfg['back_clearance'] = 0 if cfg['back_clearance'].nil?
      cfg
    end

    def drawer_thickness!(cfg)
      thickness = cfg['drawer_thk'].to_f
      return thickness if thickness.positive?
      18.0
    end

    def drawer_spec(cfg)
      material = (cfg.dig('mat_names', 'carcass') || DEFAULTS['mat_names']['carcass']).to_s
      bottom = cfg['back_thk'].to_f
      { material_key: 'carcass', material_name: material, finish: nil, thickness: drawer_thickness!(cfg),
        stock: stock_dimensions(cfg, 'carcass', drawer_thickness!(cfg)), bottom_thickness: bottom }
    end

    def back_groove_ready?(cfg)
      cfg['back_thk'].to_f.positive? && cfg['back_groove_depth'].to_f.positive? && cfg['back_groove_offset'].to_f >= 0 && cfg['back_clearance'].to_f >= 0
    end

    def back_groove_status(cfg)
      back_groove_ready?(cfg) ? 'GROOVE_GEOMETRY_APPLIED' : 'REQUIRES CONSTRUCTION PARAMETER'
    end

    def back_groove_spec(cfg)
      return nil unless back_groove_ready?(cfg)

      { depth: cfg['back_groove_depth'].to_f, offset: cfg['back_groove_offset'].to_f,
        width: cfg['back_thk'].to_f + cfg['back_clearance'].to_f, thickness: cfg['back_thk'].to_f,
        clearance: cfg['back_clearance'].to_f }
    end

    def stock_dimensions(cfg, material, thickness = nil)
      stock = cfg['sheets'] || {}
      key = thickness.nil? ? nil : "#{material}:#{thickness}"
      dims = (key && stock[key]) || stock[material.to_s]
      return nil unless dims.is_a?(Array) && dims.length >= 2 && dims[0].to_f.positive? && dims[1].to_f.positive?

      dims.first(2).map(&:to_f)
    end

    def save_project(model, cfg)
      data = PROJECT_KEYS.each_with_object({}) { |key, h| h[key] = deep_dup(cfg[key]) if cfg.key?(key) }
      model.set_attribute('egc_project', 'pricing_json', JSON.generate(data))
      data
    end

    # geometry helpers derived from config
    def top_line(c)
      c['base_h'].to_f + c['gap_h'].to_f + c['w1_h'].to_f + (c['w2_enabled'] ? c['w2_h'].to_f : 0.0)
    end

    def fascia_h(c)
      [c['ceiling'].to_f - top_line(c), 0.0].max
    end

    def validate(c)
      w = []
      w << 'ceiling_low' if c['ceiling'].to_f < top_line(c)
      w << 'led_hidden' if c['w2_enabled'] && c['w2_led_off'].to_f < c['w1_d'].to_f && c['led']
      w
    end
  end
end
