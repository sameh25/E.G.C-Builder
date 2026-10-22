# frozen_string_literal: true

module EGC
  # Per-appliance AUTO clearance policy - ONE table, ONE resolver (no per-appliance copies).
  #   * fridge rows keep the EXISTING approved project keys (config.rb:
  #     fridge_side_clear / fridge_top_clear / fridge_back_clear, defaults 2 / 50 / 50)
  #     so current behaviour is unchanged; the resolver just reads them through here.
  #   * hood / microwave / oven add the same style of configurable defaults.
  # Every value is project-editable: the key "app_clear_<appliance>_<field>" in the
  # project config overrides the default below (and the legacy fridge keys still work).
  # Sources of the defaults (this codebase, not invented):
  #   microwave side 2 / top 4 : the built-in niche the builder already leaves
  #                              (TallStack.layout: appliance cell h = device h + 4;
  #                              MICRO_38 595 mm in a 600 tower = 2.5 mm per side)
  #   vent_back 30 / oven top 5: the documented informational clearance example
  #                              (appliances.rb user-model sidecar: top 5, sides 2, back 30)
  #   hood above_hob_min       : follows the project 'gap_h' standard (600) - the clear
  #                              zone the generator already keeps above the countertop
  #                              (w1z = base_h + gap_h, kitchen.rb build_run)
  module ApplianceClearances
    DEFAULTS = {
      'hood'      => { 'above_hob_min' => :gap_h, 'side_overhang_max' => 50.0 },
      'microwave' => { 'side' => 2.0, 'top' => 4.0, 'vent_back' => 30.0 },
      'oven'      => { 'side' => 2.0, 'top' => 5.0, 'vent_back' => 30.0 },
      'fridge'    => { 'side' => 2.0, 'top' => 50.0, 'back' => 50.0 } # == config.rb fridge defaults
    }.freeze

    # existing project keys keep working (Settings / Ruby console)
    LEGACY_KEYS = {
      'fridge' => { 'side' => 'fridge_side_clear', 'top' => 'fridge_top_clear', 'back' => 'fridge_back_clear' }
    }.freeze

    module_function

    def key_for(app, field)
      "app_clear_#{app}_#{field}"
    end

    # resolution order: app_clear_<app>_<field> > legacy key (fridge) > :gap_h follow > table default
    def get(cfg, app, field)
      field = field.to_s
      v = cfg[key_for(app, field)]
      v = cfg[(LEGACY_KEYS[app] || {})[field]] if v.nil? && LEGACY_KEYS[app]
      v = DEFAULTS[app] && DEFAULTS[app][field] if v.nil?
      v = cfg['gap_h'] if v == :gap_h
      v.to_f
    end

    # full table for reports: { appliance => { field => value } }
    def table(cfg)
      DEFAULTS.each_with_object({}) do |(app, fields), out|
        out[app] = fields.keys.map { |f| [f, get(cfg, app, f)] }.to_h
      end
    end

    def report(cfg)
      table(cfg).map { |app, fs| "#{app}: " + fs.map { |f, v| "#{f}=#{v}" }.join(', ') }
    end

    # ---- hood (above the hob) -------------------------------------------------
    # hob surface: the hob device sits on the countertop (base_h); its own 50 mm
    # body is the trim above it (HOB_60 z=854 + h=50 ~= base_h 900).
    def hob_top_z(cfg)
      cfg['base_h'].to_f
    end

    # hood underside in a generated run: the wall tier starts at base_h + gap_h (kitchen.rb w1z)
    def hood_bottom_z(cfg, tier_z: nil)
      tier_z.to_f.positive? ? tier_z.to_f : cfg['base_h'].to_f + cfg['gap_h'].to_f
    end

    # actual vertical gap between the hob top and the hood underside
    def hob_to_hood_gap(cfg, tier_z: nil)
      hood_bottom_z(cfg, tier_z: tier_z) - hob_top_z(cfg)
    end

    # -> { gap:, min:, gap_ok:, width_ok: } for the hood over a hob of hob_w under a hood of hood_w
    def hood_report(cfg, hood_w, hob_w, tier_z: nil)
      gap = hob_to_hood_gap(cfg, tier_z: tier_z)
      min = get(cfg, 'hood', 'above_hob_min')
      { 'gap' => gap.round(1), 'min' => min, 'gap_ok' => (gap + 0.01 >= min),
        'hood_w' => hood_w.to_f, 'hob_w' => hob_w.to_f,
        'side_overhang_max' => get(cfg, 'hood', 'side_overhang_max'),
        'width_ok' => hob_w.to_f <= hood_w.to_f + get(cfg, 'hood', 'side_overhang_max') }
    end

    # ---- built-in niche (microwave / oven in a tower or wall niche) ------------
    # the niche the cabinet must leave around a device: device + the auto gaps
    def niche_for(cfg, app, dev_w, dev_h, dev_d)
      s = get(cfg, app, 'side')
      t = get(cfg, app, 'top')
      b = get(cfg, app, 'vent_back')
      { w: (dev_w.to_f + 2 * s).round(1), h: (dev_h.to_f + t).round(1), d: (dev_d.to_f + b).round(1),
        side: s, top: t, vent_back: b }
    end

    # catalogue record enrichment (catalog.rb profile): the per-appliance clearance set
    def installation_clearance_mm(kind)
      case kind.to_s
      when 'microwave' then { 'side' => get({}, 'microwave', 'side'), 'top' => get({}, 'microwave', 'top'), 'back' => get({}, 'microwave', 'vent_back') }
      when 'oven'      then { 'side' => get({}, 'oven', 'side'),      'top' => get({}, 'oven', 'top'),      'back' => get({}, 'oven', 'vent_back') }
      when 'fridge'    then { 'side' => get({}, 'fridge', 'side'),    'top' => get({}, 'fridge', 'top'),    'back' => get({}, 'fridge', 'back') }
      when 'hood', 'hood_chimney', 'hood_slim' then { 'above_hob_min' => get({ 'gap_h' => 600 }, 'hood', 'above_hob_min') }
      end
    end
  end
end
