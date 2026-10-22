# frozen_string_literal: true

require 'json'

module EGC
  module Kitchen
    ATTR = 'egc'
    module_function

    def sym(h)
      h.each_with_object({}) { |(k, v), o| o[k.to_sym] = v }
    end

    # ---- auto plan -------------------------------------------------------
    # Builds a sensible column list for a run of `len` mm.
    def auto_columns(len, opts = {})
      fridge = opts.fetch('fridge', true)
      cfg0 = opts['cfg']
      tower  = opts.fetch('oven_tower', false)
      cols = []
      rest = len.to_f
      if fridge
        fw = fridge_open_min_w(cfg0 || Config.build(Config.saved)).ceil(-1) # open housing sized from the refrigerator record + clearances
        cols << { 't' => 'fridge_open', 'w' => fw }
        rest -= fw
      end
      if tower
        cols << { 't' => 'oven_tower', 'w' => 600 }
        rest -= 600
      end
      specials = [{ 't' => 'drawers3', 'w' => 600 }, { 't' => 'hob_oven', 'w' => 600 }, { 't' => 'sink', 'w' => 800 }]
      sp_w = EGC::Num.sum(specials) { |c| c['w'] }
      fill = rest - sp_w
      n = fill > 0 ? (fill / 600.0).ceil : 0
      n = 1 if n.zero? && fill > 200
      ww = n.positive? ? ((fill / n) / 5.0).floor * 5 : 0
      before = (n / 2.0).ceil
      after = n - before
      cols << specials[0]
      cols << specials[1]
      before.times { cols << { 't' => 'doors', 'w' => ww } }
      cols << specials[2]
      after.times { cols << { 't' => 'doors', 'w' => ww } }
      # absorb rounding difference into the last regular unit
      diff = len.to_f - EGC::Num.sum(cols) { |c| c['w'].to_f }
      if diff.abs > 0.01
        last = cols.reverse.find { |c| c['t'] == 'doors' } || cols.last
        last['w'] = (last['w'].to_f + diff).round(1)
      end
      cols
    end

    # ---- one run -----------------------------------------------------------
    # top_trim [start, end] mm: the worktop stops short of that end of the run by so much - the side run of an L / U whose corner is NOT
    # an L corner unit (a blind corner): the main run's worktop already covers the corner, overhang included (no slab over slab)
    def build_run(ents, run, cfg, name, reverse: false, ends: [false, false], island: false, top_trim: [0.0, 0.0])
      cols = (run['cols'] || []).map { |c| c.dup }
      len = run['len'].to_f
      total = EGC::Num.sum(cols) { |c| c['w'].to_f }
      cols << { 't' => 'filler', 'w' => (len - total) } if len - total > 0.9
      cols = cols.reverse if reverse
      g = ents.add_group
      g.name = name
      e = g.entities
      x = 0.0
      span = nil
      spans = []
      w1z = cfg['base_h'].to_f + cfg['gap_h'].to_f
      w2z = w1z + cfg['w1_h'].to_f
      tall_h = Config.top_line(cfg)
      idx = 0
      bounds = []
      cols.each do |col|
        idx += 1
        w = col['w'].to_f
        type = col['t'].to_s
        nm = "#{name}_#{idx}_#{type}"
        if type == 'filler'
          filler(e, nm, x, w, cfg, tall_h) unless col['void'] # a dead corner behind the other run: no board, the worktop runs over it
          if span
            span[:end] = x + w
          else
            span = { start: x, end: x + w, holes: [] }
          end
          x += w
          bounds << x
          next
        end
        if type.start_with?('mech:')
          mit = Mechanisms.item(type.sub('mech:', ''))
          ms = mech_spec({ 'mech' => type.sub('mech:', ''), 'w' => w, 'name' => nm, 'hand' => col['hand'] || (mit && mit[:mb] == :carousel ? (idx == 1 ? 'L' : 'R') : nil) }, cfg)
          ms[:blind_strip] = col['blind_strip'].to_f if col['blind_strip']
          TallStack.build(e, ms, cfg).each { |mg| mg.transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), 0, 0))) } # a tall fitting over the stock length: two modules
          corner_top(e, nm, x, w, ms[:hand], cfg) if ms[:corner]
          if ms[:kind] == :tall
            if span
              spans << span
              span = nil
            end
          elsif ms[:kind] == :base
            span ||= { start: x, end: x, holes: [] }
            span[:end] = x + w
            unless island
              ms[:corner] ? corner_uppers(e, nm, x, w, ms[:hand], col, cfg, w1z, w2z) : wall_rows(e, nm, x, w, 'doors', col, cfg, w1z, w2z)
            end
          end
        elsif Library.slot_type?(type)
          sd = Library::SLOT[type]
          device = Appliances.place(e, nm, sd[:app], x + 2, 10, 0, w - 4, cfg['base_d'].to_f * sd[:d] - 10,
                                    sd[:under] ? cfg['base_h'].to_f - cfg['top_thk'].to_f - 5 : sd[:h], cfg)
          device.set_attribute(ATTR, 'slot_w', w)
          device.set_attribute(ATTR, 'slot_inset_x', 2.0)
          device.set_attribute(ATTR, 'slot_under', !!sd[:under])
          if sd[:tall]
            if span
              spans << span
              span = nil
            end
            over_h = tall_h - sd[:h] - 100
            if over_h > 150
              Cabinet.build(e, { name: "#{nm}_over", kind: :wall, type: 'doors', w: w, h: over_h,
                                 d: cfg['base_d'], plinth: 0, cells: Library::WALL['doors'][:cells] }, cfg)
                     .transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), 0, Geo.mm(sd[:h] + 100))))
            end
          else
            span ||= { start: x, end: x, holes: [] }
            span[:end] = x + w
            wall_rows(e, nm, x, w, type, col, cfg, w1z, w2z) unless island
          end
        elsif %w[fridge_open fridge_empty].include?(type)
          fs = fridge_open_spec(nm, w, cfg, col['dev'], type)
          ffl, ffr = tall_finish_sides(cols, idx - 1, cfg, island)
          fexp = {}
          fexp[:l] = 'exposed' if ffl
          fexp[:r] = 'exposed' if ffr
          fs[:exp] = fexp unless fexp.empty?
          Cabinet.build(e, fs, cfg).transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), 0, 0)))
          over_h = tall_h - fs[:h]
          if over_h > 150 # the deliberate upper arrangement above the housing
            Cabinet.build(e, { name: "#{nm}_over", kind: :wall, type: 'doors', w: fs[:w], h: over_h, d: fs[:d], plinth: 0, cells: Library::WALL['doors'][:cells] }, cfg)
                   .transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), 0, Geo.mm(fs[:h]))))
          end
          if span
            spans << span
            span = nil
          end
        elsif Library.tall_type?(type)
          fin_l, fin_r = tall_finish_sides(cols, idx - 1, cfg, island)
          texp = {} # the sides the eye sees above the lower units (or at an open end) are cut from the finish board
          texp[:l] = 'exposed' if fin_l
          texp[:r] = 'exposed' if fin_r
          TallStack.build(e, { name: nm, kind: :tall, type: type, w: w, h: tall_h, d: cfg['base_d'],
                               plinth: cfg['plinth'], cells: Library::TALL[type][:cells], hand: col['hand'] }.merge(texp.empty? ? {} : { exp: texp }), cfg)
                   .each { |tg| tg.transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), 0, 0))) }
          if span
            spans << span
            span = nil
          end
        else
          def_ = Library::BASE[type] || Library::BASE['doors']
          floor = def_[:floor]
          hand = col['hand'] || (def_[:corner] ? (idx == 1 ? 'L' : 'R') : nil)
          bspec = { name: nm, kind: :base, type: type, w: w, h: cfg['base_h'], d: cfg['base_d'],
                    plinth: floor ? 0 : cfg['plinth'], floor: floor, cells: def_[:cells], hand: hand, corner: def_[:corner] }
          bspec[:device_id] = col['dev'] || def_[:dev] if col['dev'] || def_[:dev]
          bspec[:device_id2] = col['dev2'] || def_[:dev2] if col['dev2'] || def_[:dev2]
          Cabinet.build(e, bspec, cfg)
             .transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), 0, 0)))
          corner_top(e, nm, x, w, hand, cfg) if def_[:corner]
          span ||= { start: x, end: x, holes: [] }
          span[:end] = x + w
          if def_[:cutout]
            span[:holes] << cutout_rect(def_[:cutout], x, w, cfg)
          end
          unless island
            def_[:corner] ? corner_uppers(e, nm, x, w, hand, col, cfg, w1z, w2z) : wall_rows(e, nm, x, w, type, col, cfg, w1z, w2z)
          end
        end
        x += w
        bounds << x
      end
      spans << span if span
      unless spans.empty?
        spans.first[:start] += top_trim[0].to_f if spans.first[:start].abs < 0.5
        spans.last[:end] -= top_trim[1].to_f if (spans.last[:end] - x).abs < 0.5
      end
      if top_trim.any? { |v| v.to_f.positive? } # kept for every later worktop rebuild of this run (edit, new thickness ...)
        g.set_attribute(ATTR, 'top_trim', JSON.generate(top_trim.map(&:to_f)))
        g.set_attribute(ATTR, 'run_len', x.round(1))
      end
      spans.each_with_index { |sp, i| countertop(e, "#{name}_top#{i + 1}", sp, cfg, bounds, island ? { back: cfg['island_overhang'].to_f } : {}) }
      fascia(e, "#{name}_fascia", x, cfg, tall_h) unless island
      # run-level end panels removed: Cabinet#side_finish_panels now adds one exterior finish panel per
      # exposed unit side automatically (Exposure default), so a separate run-level board here duplicated it.
      join_plinth_run(e, name, cfg) unless island
      g.set_attribute(ATTR, 'run', true)
      g.set_attribute(ATTR, 'len', x)
      g.set_attribute(ATTR, 'cfg', JSON.generate(cfg))
      g.set_attribute(ATTR, 'island', true) if island
      g
    end

    # ---- refrigerator open housing ---------------------------------------------------------------------------------------------------------
    # The housing is a real tall unit (left / right side, header) around a SEPARATE refrigerator. Its inside width / height come from the refrigerator's
    # own device record + configurable clearances (cfg fridge_side_clear / fridge_top_clear / fridge_back_clear - REQUIRES_CONFIRMATION until confirmed).
    def fridge_device(id)
      Catalog.device(id || 'FRIDGE_TALL')
    end

    def fridge_open_min_w(cfg, dev_id = nil)
      dv = fridge_device(dev_id) || Catalog.device('FRIDGE_TALL')
      dv[:w].to_f + 2 * ApplianceClearances.get(cfg, 'fridge', 'side') + 2 * cfg['thk'].to_f
    end

    def fridge_open_spec(nm, w, cfg, dev_id = nil, type = 'fridge_open')
      dev_id ||= 'FRIDGE_TALL'
      dv = fridge_device(dev_id)
      raise "Unknown refrigerator #{dev_id}" unless dv && dv[:kind].to_s == 'fridge'

      # the housing is made to the refrigerator (owner, 1.28.55): at least its width + the side clearances + the gables, its height + the top
      # clearance, its depth + the back clearance - a narrower housing grows to fit instead of refusing; a wider one asked for is kept
      need = fridge_open_min_w(cfg, dev_id)
      w = [w.to_f, need].max
      d = [cfg['base_d'].to_f, dv[:d].to_f + ApplianceClearances.get(cfg, 'fridge', 'back')].max

      { name: nm, kind: :tall, type: type, w: w, h: dv[:h].to_f + ApplianceClearances.get(cfg, 'fridge', 'top') + cfg['thk'].to_f, d: d, plinth: 0,
        floor: true, cells: Library::TALL[type][:cells], device_id: dev_id, housing: 'fridge' }.merge(Library::TALL[type][:flags])
    end

    def corner_top(e, nm, x, w, hand, cfg)
      td = cfg['base_d'].to_f + cfg['top_overhang'].to_f
      th = cfg['top_thk'].to_f
      return if w <= td

      xs = hand == 'R' ? x + w - td : x
      Panel.add(e, "#{nm}_cornertop", 'countertop', xs, td, cfg['base_h'].to_f - th, td, w - td, th, 'top', cfg,
                grain: :x, eb: [1, 0], eb_t: 2.0)
    end

    # SINK KINDS (cfg 'sink_model'): generic inset sinks with typical worktop openings - the real cut-out always comes from the template of the
    # sink that is bought. 'auto' = the earlier behaviour (one bowl under 800 mm, two bowls from 800 mm).
    SINK_MODELS = { 'single' => 500.0, 'double' => 780.0, 'one_half' => 620.0, 'drainer' => 860.0, 'round' => 450.0, 'smart' => 800.0, 'smart75' => 750.0 }.freeze
    SINK_MIN_UNIT = { 'double' => 760.0, 'one_half' => 660.0, 'drainer' => 760.0, 'smart' => 800.0, 'smart75' => 800.0 }.freeze

    # PRODUCT SINKS: a sink kind that stands for one real product carries that product's published data and nothing more.
    # 'smart' = SMG 107501706 (supplier product page): overall 800 x 490, stainless steel 304, the listed components. The page gives NO
    # worktop cut-out, no bowl size, no bowl depth and no drain position - none of them is invented here:
    #   * the cut-out is taken from cfg 'sink_smart_cut_w' / 'sink_smart_cut_d' (the template of the sink that is bought) when both are
    #     entered; until then the opening drawn in the slab is INDICATIVE and every output says REQUIRES CUTOUT SPECIFICATION;
    #   * what cannot be checked without those figures is reported as such by #sink_report, not passed.
    CUTOUT_REQUIRED = 'REQUIRES CUTOUT SPECIFICATION'
    SINK_PROFILES = {
      'smart' => { product: 'SMG 107501706', overall: [800.0, 490.0], material: 'Stainless steel 304', unit_min: 800.0,
                   accessories: %w[veg_bowl chopping_board drain_strainer drain_cover drain_control glass_rinser tap waterfall],
                   source: 'hanimex.net/shop/107501706 (product page: size, material, component list)', view_inset: 20.0 }.freeze,
      # the usual size of this kind of sink at several makers (750 x 450 overall, 215 high, bowl about 700 x 350): a size CLASS, not one
      # product - cut-out, bowl depth and drain position come from the sink that is bought, exactly as for the SMG one.
      'smart75' => { product: 'Smart waterfall sink 750 x 450 (generic size class)', overall: [750.0, 450.0], material: 'Stainless steel 304 (typical)', unit_min: 800.0,
                     accessories: %w[veg_bowl chopping_board drain_strainer drain_cover drain_control glass_rinser tap waterfall],
                     source: 'typical overall size of waterfall smart sinks (e.g. 750 x 450 x 215 mm listings)', view_inset: 20.0 }.freeze
    }.freeze

    def sink_profile(model)
      SINK_PROFILES[model.to_s]
    end

    # [w, d] of the worktop opening entered for a product sink, or nil while it has not been given
    def sink_cut_data(model, cfg)
      pr = sink_profile(model) or return nil
      cw = cfg["sink_#{model}_cut_w"].to_f
      cd = cfg["sink_#{model}_cut_d"].to_f
      cw.positive? && cd.positive? && cw <= pr[:overall][0] && cd <= pr[:overall][1] ? [cw, cd] : nil
    end

    # where a product sink sits on the worktop above a unit: [x, d0 (from the wall), w, d] - centred on the unit and on the slab depth
    def sink_overall_rect(x, w, cfg)
      model = sink_model(w, cfg)
      pr = sink_profile(model) or return nil
      td = cfg['base_d'].to_f + cfg['top_overhang'].to_f
      [x + (w - pr[:overall][0]) / 2.0, (td - pr[:overall][1]) / 2.0, pr[:overall][0], pr[:overall][1]]
    end

    # What can and cannot be confirmed for the sink of a unit -> [{ 'item' =>, 'status' => PASS / FAIL / REQUIRES CUTOUT SPECIFICATION, 'note' => }]
    def sink_report(w, type, cfg)
      model = sink_model(w, cfg)
      asked = (cfg['sink_model'] || 'auto').to_s
      pr = sink_profile(model)
      unless pr
        apr = sink_profile(asked)
        return [] unless apr

        return [{ 'item' => 'unit width', 'status' => 'FAIL', 'note' => "#{apr[:product]} is #{apr[:overall][0].round} mm wide: it needs a sink unit of at least #{apr[:unit_min].round} mm, this one is #{w.round} - a single bowl is built instead" }]
      end
      t = cfg['thk'].to_f
      td = cfg['base_d'].to_f + cfg['top_overhang'].to_f
      o = sink_overall_rect(0, w, cfg)
      cut = sink_cut_data(model, cfg)
      rail_back = cfg['base_d'].to_f - cfg['front_thk'].to_f - t # rear face of the front rail, measured from the wall
      need = ->(what) { { 'item' => what, 'status' => CUTOUT_REQUIRED, 'note' => "not published for #{pr[:product]}: enter the cut-out from the sink's template" } }
      out = []
      out << { 'item' => 'unit width', 'status' => w >= pr[:unit_min] - 0.5 ? 'PASS' : 'FAIL', 'note' => "unit #{w.round} / needs #{pr[:unit_min].round}" }
      out << { 'item' => 'sink on the worktop', 'status' => o[1] >= 0 && o[1] + o[3] <= td ? 'PASS' : 'FAIL', 'note' => "#{o[2].round} x #{o[3].round} on a #{td.round} deep top: #{o[1].round} mm strip behind and in front" }
      out << { 'item' => 'front rail', 'status' => o[1] + o[3] <= rail_back + 0.5 ? 'PASS' : 'FAIL', 'note' => "front edge of the sink #{(o[1] + o[3]).round} from the wall, rail starts at #{rail_back.round}" }
      if cut
        out << { 'item' => 'worktop cut-out', 'status' => 'PASS', 'note' => "#{cut[0].round} x #{cut[1].round} as entered (USER CUTOUT DATA)" }
        out << { 'item' => 'cut-out between the cabinet sides', 'status' => cut[0] <= w - 2 * t + 0.5 ? 'PASS' : 'FAIL', 'note' => "cut-out #{cut[0].round} / clear inside #{(w - 2 * t).round}" }
      else
        out << need.call('worktop cut-out')
        out << need.call('bowl between the cabinet sides')
      end
      out << if type.to_s == 'sink_drawer'
               need.call('drawer under the bowl (bowl depth and side-drain position)')
             else
               { 'item' => 'space under the bowl', 'status' => 'PASS', 'note' => 'door unit without shelf or drawer under the sink' }
             end
      out << need.call('trap / waste position (side drain)')
      out
    end

    # HOB KINDS (cfg 'hob_model'): generic built-in hobs. body = what lies on the worktop, cut = the TYPICAL worktop opening of that size
    # class (60 and 70 cm hobs: 560 x 490 at most makers; the 30, 80 and 90 cm openings differ from maker to maker). The real opening
    # always comes from the template of the hob that is bought. 'auto' = the hob of the unit's own appliance (60 cm, gas or electric).
    HOB_MODELS = {
      'el_30' => { kind: 'hob', body: [290.0, 520.0], cut: [270.0, 490.0], style: 'ceramic', en: 'Domino hob 30 (electric)', ar: 'بوتجاز دومينو 30 كهرباء' },
      'el_60' => { kind: 'hob', body: [590.0, 520.0], cut: [560.0, 490.0], style: 'ceramic', en: 'Hob 60 (electric)', ar: 'بوتجاز مسطح 60 كهرباء' },
      'ind_60' => { kind: 'hob', body: [590.0, 520.0], cut: [560.0, 490.0], style: 'induction', en: 'Induction hob 60', ar: 'بوتجاز إنداكشن 60' },
      'ind_80' => { kind: 'hob', body: [780.0, 520.0], cut: [750.0, 490.0], style: 'induction', en: 'Induction hob 80', ar: 'بوتجاز إنداكشن 80' },
      'ind_90' => { kind: 'hob', body: [900.0, 520.0], cut: [880.0, 490.0], style: 'induction', en: 'Induction hob 90', ar: 'بوتجاز إنداكشن 90' },
      'gas_30' => { kind: 'hob_gas', body: [290.0, 520.0], cut: [270.0, 490.0], style: 'steel', en: 'Domino hob 30 (gas, 2 burners)', ar: 'بوتجاز دومينو 30 غاز (2 شعلة)' },
      'gas_60' => { kind: 'hob_gas', body: [590.0, 520.0], cut: [560.0, 490.0], style: 'steel', en: 'Gas hob 60 (4 burners)', ar: 'بوتجاز غاز 60 (4 شعلة)' },
      'gas_70' => { kind: 'hob_gas', body: [700.0, 520.0], cut: [560.0, 490.0], style: 'steel', en: 'Gas hob 70 (5 burners)', ar: 'بوتجاز غاز 70 (5 شعلة)' },
      'gas_90' => { kind: 'hob_gas', body: [880.0, 520.0], cut: [840.0, 490.0], style: 'steel', en: 'Gas hob 90 (5 burners)', ar: 'بوتجاز غاز 90 (5 شعلة)' },
      'gas_glass_60' => { kind: 'hob_gas', body: [590.0, 520.0], cut: [560.0, 490.0], style: 'glass', en: 'Gas on glass hob 60', ar: 'بوتجاز غاز زجاج أسود 60' },
      'gas_glass_90' => { kind: 'hob_gas', body: [880.0, 520.0], cut: [840.0, 490.0], style: 'glass', en: 'Gas on glass hob 90', ar: 'بوتجاز غاز زجاج أسود 90' }
    }.freeze
    # the unit width a hob asks for: its body to the next 100 mm (30 / 60 / 70 / 80 / 90 cm); a hob over an oven never below the oven's 600
    def hob_unit_w(model, type = 'hob')
      hm = HOB_MODELS[model.to_s]
      return nil unless hm

      w = (hm[:body][0] / 100.0).ceil * 100.0
      type.to_s == 'hob_oven' ? [w, 600.0].max : w
    end

    HOB_CUT_NOTE = 'TYPICAL OPENING - cut from the template of the hob that is bought'

    # the hob kind this unit really gets: the asked one when its opening stays inside the unit, otherwise 'auto'
    def hob_model(w, cfg)
      m = (cfg['hob_model'] || 'auto').to_s
      pr = HOB_MODELS[m]
      pr && pr[:cut][0] + 20.0 <= w.to_f ? m : 'auto'
    end

    def hob_profile(w, cfg)
      HOB_MODELS[hob_model(w, cfg)]
    end

    def sink_model(w, cfg)
      m = (cfg['sink_model'] || 'auto').to_s
      m = w.to_f >= 800.0 ? 'double' : 'single' unless SINK_MODELS.key?(m)
      m = 'single' if SINK_MIN_UNIT[m] && w.to_f < SINK_MIN_UNIT[m] # too narrow for that kind: a single bowl
      m
    end

    def cutout_rect(kind, x, w, cfg)
      td = cfg['base_d'].to_f + cfg['top_overhang'].to_f
      m = [cfg['cutout_margin'].to_f, 0.0].max
      if kind == :sink
        model = sink_model(w, cfg)
        if (pr = sink_profile(model)) # a product sink: the opening is the entered template size, or an indicative one that is labelled as such
          o = sink_overall_rect(x, w, cfg)
          cut = sink_cut_data(model, cfg)
          # indicative opening: inside the sink's outline and inside the clear width of the unit (so the picture is coherent) - not a cutting size
          cw, cdp = cut || [[o[2] - 2 * pr[:view_inset], w - 2 * cfg['thk'].to_f - 4.0].min, o[3] - 2 * pr[:view_inset]]
          note = cut ? "sink #{pr[:product]} cutout #{cw.round}x#{cdp.round} (USER CUTOUT DATA)" : "sink #{pr[:product]} #{o[2].round}x#{o[3].round} overall: #{CUTOUT_REQUIRED} - the opening drawn is indicative, do not cut from it"
          return [o[0] + (o[2] - cw) / 2.0, o[1] + (o[3] - cdp) / 2.0, cw, cdp, 'sink', note, cut ? 'USER CUTOUT DATA' : CUTOUT_REQUIRED]
        end
        nominal = SINK_MODELS[model] || 780.0                         # worktop opening width of that kind of sink (generic size)
        sw = [[[w - 80, nominal].min, 300].max + 2 * m, w - 20].min
        sd = (model == 'round' ? [sw - 2 * m, 440.0].min : 440.0) + 2 * m
        return [x + (w - sw) / 2.0, [90.0 - m, 20].max, sw, sw, 'sink', "ROUND sink cutout dia #{sw.round}", nil, 'round'] if model == 'round' && sw <= sd + 12

        [x + (w - sw) / 2.0, [90.0 - m, 20].max, sw, sd, 'sink']
      else
        pr = hob_profile(w, cfg)
        cw0, cd0 = pr ? pr[:cut] : [560.0, 490.0]
        hw = [cw0 + 2 * m, w - 20].min
        hd = cd0 + 2 * m
        return [x + (w - hw) / 2.0, [(td - hd) / 2.0, 40].max, hw, hd, 'hob', "hob #{hob_model(w, cfg)} cutout #{hw.round}x#{hd.round}: #{HOB_CUT_NOTE}"] if pr

        [x + (w - hw) / 2.0, [(td - hd) / 2.0, 40].max, hw, hd, 'hob']
      end
    end

    def resolve_wall(type, col, level)
      key = level == 1 ? 'w1' : 'w2'
      v = (col[key] || 'auto').to_s
      return v unless v == 'auto'

      if level == 1
        %w[hob hob_oven].include?(type) ? 'hood' : 'doors'
      else
        'doors'
      end
    end

    def wall_rows(e, nm, x, w, type, col, cfg, w1z, w2z)
      t1 = resolve_wall(type, col, 1)
      unless t1 == 'none'
        if t1.start_with?('mech:')
          spec = mech_spec({ 'mech' => t1.sub('mech:', ''), 'w' => w, 'name' => "#{nm}_W1" }, cfg)
        elsif t1 == 'hood'
          spec = { name: "#{nm}_W1", kind: :hood, type: 'hood', w: w, h: cfg['w1_h'], d: cfg['hood_d'], plinth: 0,
                   cells: [{ t: :hood, h: cfg['hood_open_h'].to_f }, { t: :doors, shelves: 0 }] }
        else
          def_ = Library::WALL[t1] || Library::WALL['doors']
          spec = { name: "#{nm}_W1", kind: :wall, type: t1, w: w, h: cfg['w1_h'], d: cfg['w1_d'], plinth: 0,
                   cells: def_[:cells], led_off: cfg['w1_led_off'], hand: col['hand'], tier: 1 }
        end
        Cabinet.build(e, spec, cfg).transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), 0, Geo.mm(w1z))))
      end
      return unless cfg['w2_enabled']

      t2 = resolve_wall(type, col, 2)
      return if t2 == 'none'

      def2 = Library::WALL[t2] || Library::WALL['doors']
      led = cfg['w2_led_off'] # standard: tier 2 is grooved (450 from the back) whatever stands under it
      spec = { name: "#{nm}_W2", kind: :wall, type: t2, w: w, h: cfg['w2_h'], d: cfg['w2_d'], plinth: 0,
               cells: def2[:cells].map { |c| c.merge(shelves: 0) }, led_off: led, tier: 2 }
      spec[:exp_auto] = { 'b' => false, 'bv' => true } unless t1 == 'none' # initial hint only (it stands on tier 1): Exposure.refresh re-checks it from the real geometry and corrects it
      Cabinet.build(e, spec, cfg).transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), 0, Geo.mm(w2z))))
    end

    # ---- finish panel beside a tall unit ------------------------------------------------------------------------------------------------
    # A tall unit stands higher and deeper than what is next to it, so its carcass side shows above the lower units. That side is cut from the FINISH board, not clad (see Cabinet#side_mat). Older wording:
    # PANEL (external material, floor to top line, flush with the door faces) - a real board in the cut list. Rules, per side:
    #   next to a lower unit / appliance -> panel;  next to another tall unit -> none;  at the end of the run -> panel only when the end is
    #   open (settings: end panels on, or an island) - an end that closes against a wall needs none.
    TALL_FINISH = %w[pantry oven_tower oven_tall microwave_tower fridge_bi fridge_open fridge_empty].freeze

    def tallish_col?(c)
      return false unless c

      t = c['t'].to_s
      Library.tall_type?(t) || t == 'fridge'
    end

    # [left, right] in the order of cols
    def tall_finish_sides(cols, i, cfg, island = false)
      return [false, false] unless cols[i] && TALL_FINISH.include?(cols[i]['t'].to_s) && cfg['tall_finish'] != false && cfg['front_thk'].to_f.positive?

      open_end = island || (cfg['end_panels'] ? true : false)
      [i - 1, i + 1].map do |j|
        nb = j.negative? ? nil : cols[j]
        if nb.nil? then open_end
        elsif nb['t'].to_s == 'filler' then j.positive? && j < cols.size - 1 # a filler at the very end closes the run against the wall
        else !tallish_col?(nb)
        end
      end
    end

    # everything the generator settles before it builds: corner units, then room for the finish panels of the tall units
    def ensure_layout(params, cfg)
      ensure_blind_corners(ensure_corners(params, cfg), cfg)
    end

    # BLIND CORNER UNITS (LeMans / magic corner) at a corner of an L / U kitchen. The other run stands in front of the blind lane, so
    # (1) the blind lane must face the corner - the hand is set from where the unit stands, and (2) the blind lane must be at least as
    # wide as the other run is deep (+ BLIND_CLEAR for its door and handle): when it is narrower (LeMans: unit 1000 / door 600 = 400 blind)
    # the unit is pulled away from the side wall and the space behind the other run stays an empty dead corner under the worktop
    # (a 'filler' column with 'void' => true: no board, the worktop runs over it). The width is taken from the plain units of the run.
    BLIND_PAIRS = { 'LEMANS' => %w[LEMANS_L LEMANS], 'LEMANS_L' => %w[LEMANS_L LEMANS],
                    'MAGIC_CORNER' => %w[MAGIC_CORNER_L MAGIC_CORNER], 'MAGIC_CORNER_L' => %w[MAGIC_CORNER_L MAGIC_CORNER] }.freeze
    BLIND_CLEAR = 50.0

    # WIDE MAGIC CORNER (1.28.49, owner): a corner unit with a unit on both sides - 1200 wide, so the return run standing in front of its
    # blind lane never closes over the door: the opening is what is left after the other run's depth + BLIND_CLEAR, within the fitting's
    # door range 450 - 600 (Kesseboehmer MagicCorner). Narrower units keep the 64 % opening.
    MAGIC_WIDE = 1100.0

    def magic_door_w(w, cfg)
      return nil if w.to_f < MAGIC_WIDE

      (w.to_f - cfg['base_d'].to_f - BLIND_CLEAR).clamp(450.0, 600.0)
    end

    def blind_lane_w(id, w, cfg)
      return w - LemansKin.variant('600')[:door] if id.start_with?('LEMANS')
      return w - magic_door_w(w, cfg) if magic_door_w(w, cfg)

      t = cfg['thk'].to_f
      w - 0.64 * (w - 2 * t - 6) # magic corner: the opening is 64 % of the inside width (see HardwareRevision#fam_magic)
    end

    def ensure_blind_corners(params, cfg)
      layout = (params['layout'] || 'straight').to_s
      return params unless %w[L U].include?(layout) && !params['as_drawn']

      p = JSON.parse(JSON.generate(params))
      runs = p['runs'] || {}
      a = runs['a']
      return params unless a && a['cols'].is_a?(Array) && a['cols'].size > 1

      ends = []
      ends << true if (layout == 'U' || (p['l_side'] || 'left').to_s == 'left') && runs['b']
      ends << false if (layout == 'U' || (p['l_side'] || 'left').to_s == 'right') && runs['c']
      ends.each do |first|
        cols = a['cols']
        col = first ? cols.first : cols.last
        id = col['t'].to_s.sub('mech:', '')
        pair = col['t'].to_s.start_with?('mech:') && BLIND_PAIRS[id]
        next unless pair

        id = first ? pair[0] : pair[1]
        col['t'] = "mech:#{id}" # the blind lane toward the corner
        col['blind_strip'] = CORNER_AUTO_FILLER # the other run stands in front of the blind lane: no cover panel, the strip by the door only
        nb = first ? cols[1] : cols[-2]
        next if nb && nb['void']

        pull = (cfg['base_d'].to_f + BLIND_CLEAR - blind_lane_w(id, col['w'].to_f, cfg)).ceil.to_f
        next if pull < 1

        rest = corner_consume(first ? cols[1..] : cols[0..-2], pull, first)
        next unless rest

        void = { 't' => 'filler', 'w' => pull, 'void' => true }
        a['cols'] = first ? [void, col] + rest : rest + [col, void]
      end
      p
    end

    # A unit was placed in front of the blind lane of a blind corner unit (blind_return): the corner unit loses its fixed cover panel there,
    # keeping only the strip between its door and the new unit (the 50 mm the door and the new fronts open past).
    def blind_cover_off(g, cfg)
      return unless g&.valid? && g.get_attribute('egc', 'spec').to_s.include?('"mech"')

      rebuild_cabinet(g, { 'blind_strip' => CORNER_AUTO_FILLER }, cfg)
    rescue StandardError => e
      warn "E.G.C blind cover: #{e.message}"
    end

    # The filler between a corner unit and a unit that was ADDED beside it with the placement tool (Snap leaves CORNER_AUTO_FILLER there,
    # as the generator does for a whole kitchen): a front-board strip in the plane of the new unit's fronts, cut list / edge band like the
    # generator's fillers. tr = the new unit's frame, fil = { x:, w: } in that frame, box = the new unit's size / class.
    def place_corner_filler(tr, fil, box, cfg)
      model = Sketchup.active_model
      model.start_operation('E.G.C corner filler', true)
      g = model.entities.add_group
      g.name = 'EGC_corner_filler'
      g.set_attribute(ATTR, 'corner_filler', true)
      ft = cfg['front_thk'].to_f
      wall = box[:kind].to_s == 'wall'
      z0 = wall ? 0.0 : cfg['plinth'].to_f
      h = if wall then box[:h]
          elsif box[:kind].to_s == 'base' then cfg['base_h'].to_f - cfg['plinth'].to_f - cfg['top_thk'].to_f
          else box[:h] - cfg['plinth'].to_f
          end
      Panel.add(g.entities, 'EGC_corner_filler', 'filler', fil[:x], box[:d] - ft, z0, fil[:w], ft, h, 'front', cfg, grain: :z, eb: [2, 0])
      g.transform!(tr)
      model.commit_operation
      g
    rescue StandardError
      model.abort_operation
      raise
    end

    def filler(e, nm, x, w, cfg, tall_h)
      ft = cfg['front_thk'].to_f
      d = cfg['base_d'].to_f - ft
      Panel.add(e, nm, 'filler', x, d, cfg['plinth'], w, ft, cfg['base_h'].to_f - cfg['plinth'].to_f - cfg['top_thk'].to_f,
                'front', cfg, grain: :z, eb: [2, 0])
      w1z = cfg['base_h'].to_f + cfg['gap_h'].to_f
      d1 = cfg['w1_d'].to_f - ft
      Panel.add(e, nm + '_w1', 'filler', x, d1, w1z, w, ft, cfg['w1_h'], 'front', cfg, grain: :z, eb: [2, 0])
      return unless cfg['w2_enabled']

      Panel.add(e, nm + '_w2', 'filler', x, cfg['w2_d'].to_f - ft, w1z + cfg['w1_h'].to_f, w, ft, cfg['w2_h'], 'front',
                cfg, grain: :z, eb: [2, 0])
    end

    def countertop(e, nm, span, cfg, cuts = [], opts = {})
      total = span[:end] - span[:start]
      return if total < 1

      maxl = cfg['top_max_len'].to_f
      maxl = 1_000_000 if maxl <= 0
      pieces = []
      start = span[:start]
      while span[:end] - start > maxl + 0.5
        limit = start + maxl
        cut = cuts.select { |c| c > start + 300 && c <= limit }.max || limit
        pieces << [start, cut]
        start = cut
      end
      pieces << [start, span[:end]]
      up = cfg['upstand_h'].to_f
      pieces.each_with_index do |(a, b), i|
        pn = pieces.size > 1 ? "#{nm}#{('a'.ord + i).chr}" : nm
        slab(e, pn, a, b, span[:holes].select { |h| h[0] >= a - 0.5 && h[0] + h[2] <= b + 0.5 }, cfg, opts, pieces.size > 1)
        next unless up > 0

        Panel.add(e, "#{pn}_up", 'upstand', a, 0, cfg['base_h'].to_f, b - a, cfg['top_thk'].to_f, up, 'top', cfg, grain: :x, eb: [1, 0], eb_t: 2.0)
      end
      return unless cfg['splash_on']

      z0 = cfg['base_h'].to_f + up
      h = cfg['base_h'].to_f + cfg['gap_h'].to_f - z0
      Panel.add(e, "#{nm}_splash", 'backsplash', span[:start], 0, z0, total, cfg['splash_thk'].to_f, h, 'splash', cfg, grain: :x) if h > 10
    end

    # Drop lip: a strip glued under the front edge of the slab, so the edge reads thicker (th + lip_h).
    def add_drop_lip(ents, len, td, lip_w, lip_h)
      strip = ents.add_face([Geo.p3(0, td - lip_w, 0), Geo.p3(len, td - lip_w, 0), Geo.p3(len, td, 0), Geo.p3(0, td, 0)])
      strip = ents.grep(Sketchup::Face).find do |f|
        f.valid? && f.normal.z < -0.99 && (f.area - Geo.mm(len) * Geo.mm(lip_w)).abs < 1e-3
      end || strip
      strip.pushpull(strip.normal.z < 0 ? Geo.mm(lip_h) : -Geo.mm(lip_h)) if strip
    end

    def slab(e, nm, a, b, holes, cfg, opts, joint)
      len = b - a
      back = opts[:back].to_f
      td = cfg['base_d'].to_f + cfg['top_overhang'].to_f + back
      lip_h = cfg['top_lip'].to_f
      lip_w = [cfg['top_lip_w'].to_f, 10.0].max
      th = cfg['top_thk'].to_f
      solid = lambda do |ents|
        outer = [Geo.p3(0, 0, 0), Geo.p3(len, 0, 0), Geo.p3(len, td, 0), Geo.p3(0, td, 0)]
        face = ents.add_face(outer)
        holes.each do |hx, hd, hw, hdd, _k, _n, _s, shape|
          lx = hx - a
          if shape == 'round' # a round sink: a round opening
            rr = [hw, hdd].min / 2.0
            c2 = ents.add_face((0...48).map { |i| a = i * Math::PI / 24.0; Geo.p3(lx + hw / 2.0 + rr * Math.cos(a), hd + back + hdd / 2.0 + rr * Math.sin(a), 0) })
            c2.erase! if c2&.valid?
            next
          end
          f2 = ents.add_face([Geo.p3(lx, hd + back, 0), Geo.p3(lx + hw, hd + back, 0), Geo.p3(lx + hw, hd + back + hdd, 0),
                              Geo.p3(lx, hd + back + hdd, 0)])
          f2.erase! if f2 && f2.valid?
        end
        face = ents.grep(Sketchup::Face).find { |f| f.valid? } || face
        face.pushpull((face.normal.z >= 0 ? 1 : -1) * Geo.mm(th)) if face
        add_drop_lip(ents, len, td, lip_w, lip_h) if lip_h > 0
      end
      notes = holes.map { |h| h[5] || "#{h[4]} cutout #{h[2].round}x#{h[3].round}" }
      notes << 'joint' if joint
      notes << "drop lip #{lip_w.round}x#{lip_h.round}" if lip_h > 0
      Panel.add(e, nm, 'countertop', a, -back, cfg['base_h'].to_f - th, len, td, th, 'top', cfg,
                grain: :x, eb: [1, 0], eb_t: 2.0, solid: solid, notes: (notes.empty? ? nil : notes.join('; ')))
    end


    def fascia(e, nm, len, cfg, top_line)
      fh = Config.fascia_h(cfg)
      return if fh < 1 || len < 1

      depth = cfg['w2_enabled'] ? cfg['w2_d'].to_f : cfg['w1_d'].to_f
      th = cfg['fascia_thk'].to_f
      # a full-width fascia is longer than a sheet: split it into equal pieces that fit
      stock = Config.stock_dimensions(cfg, (cfg['ext_mat'] || 'front').to_s, cfg['front_thk'])
      raise 'STOCK_SIZE_REQUIRED: configure external/finish-board stock in Project Pricing before generating fascia.' unless stock
      max_len = stock[0] - 2 * cfg['trim'].to_f - 20
      n = (len / max_len).ceil
      seg = len / n
      n.times do |i|
        Panel.add(e, n > 1 ? "#{nm}#{i + 1}" : nm, 'fascia', i * seg, depth - th, top_line, seg, th, fh, (cfg['ext_mat'] || 'front').to_s, cfg,
                  grain: :x, eb: [2, 0], eb_t: 2.0)
      end
    end

    PLINTH_MAX_LEN = 3000.0

    # One continuous plastic plinth profile across a run - real trim stock, one length wherever
    # possible, joined only where PLINTH_MAX_LEN forces a cut (never at every cabinet boundary).
    # Front face flush with the carcass front, matching Cabinet#plinth_board's standalone version.
    def plinth_run(e, nm, start_x, end_x, cfg, cuts = [])
      total = end_x - start_x
      return if total < 1

      ph = cfg['plinth'].to_f
      return if ph <= 0

      t = cfg['thk'].to_f
      d_param = cfg['base_d'].to_f - cfg['front_thk'].to_f - t
      maxl = PLINTH_MAX_LEN
      pieces = []
      start = start_x
      while end_x - start > maxl + 0.5
        limit = start + maxl
        cut = cuts.select { |c| c > start + 300 && c <= limit }.max || limit
        pieces << [start, cut]
        start = cut
      end
      pieces << [start, end_x]
      pieces.each_with_index do |(a, b), i|
        part_nm = pieces.size > 1 ? "#{nm}#{i + 1}" : nm
        Panel.add(e, part_nm, 'plinth', a, d_param, 0, b - a, t, ph, 'plinth', cfg, grain: :x, eb: [1, 0], eb_t: 2.0)
      end
    end

    def erase_run_plinth(e, start_x, end_x)
      e.grep(Sketchup::Group).each do |g|
        next unless g.valid? && g.get_attribute(ATTR, 'part') == 'plinth'

        ox = g.transformation.origin.x.to_mm
        len = g.get_attribute(ATTR, 'len').to_f
        g.erase! if ox < end_x - 0.5 && ox + len > start_x + 0.5
      end
    end

    # Every base cabinet builds its OWN plinth board by default (Cabinet#plinth_board - needed for a
    # standalone unit). Here, right after a run is built (or re-shaped by a resize), every 2+
    # plinth-eligible cabinets standing touching each other have their board(s) erased and replaced
    # with ONE continuous run (a floor-mounted appliance with no plinth of its own, e.g. washer_bi,
    # breaks the run for real). Eligibility comes from the cabinet's own stored spec (spec[:plinth] >
    # 0), not from whether it currently still owns a physical board - safe to call again after a
    # resize, when some cabinets in the run were already joined into a previous continuous piece.
    def join_plinth_run(e, name, cfg)
      bases = e.grep(Sketchup::Group).select { |g| g.valid? && base_kind?(g) }.sort_by { |x| x.transformation.origin.x.to_mm }
      groups = []
      cur = []
      bases.each do |g|
        spec = Cabinet.spec_from_json(g.get_attribute(ATTR, 'spec'))
        eligible = spec[:plinth].to_f > 0
        x0 = g.transformation.origin.x.to_mm
        x1 = x0 + g.get_attribute(ATTR, 'w').to_f
        if eligible && (cur.empty? || (x0 - cur.last[:x1]).abs < 1.0)
          cur << { g: g, x0: x0, x1: x1 }
        else
          groups << cur if cur.size > 1
          cur = eligible ? [{ g: g, x0: x0, x1: x1 }] : []
        end
      end
      groups << cur if cur.size > 1
      groups.each do |grp|
        start_x = grp.first[:x0]
        end_x = grp.last[:x1]
        cuts = grp[1..].map { |m| m[:x0] }
        grp.each { |m| m[:g].entities.grep(Sketchup::Group).select { |p| p.get_attribute(ATTR, 'part') == 'plinth' }.each(&:erase!) }
        erase_run_plinth(e, start_x, end_x)
        plinth_run(e, "#{name}_plinth_r#{start_x.round}", start_x, end_x, cfg, cuts)
      end
    end

    # ---- corner units are never left out -----------------------------------
    # An L / U kitchen whose main run does not start (end) with a corner unit would hide a blind, unusable corner behind the side run.
    # Wherever a side run meets the main run and no corner unit stands there, the plain units at that end make room for an L-shaped corner base
    # (CORNER_AUTO_W square, with its L-shaped corner wall units on both tiers - see corner_uppers) and a filler on each side for the doors.
    # The far ends of all runs stay where they were. An appliance, sink / hob or tall unit that stood in the corner moves along the run, past the corner unit.
    CORNER_AUTO_W = 900.0
    CORNER_AUTO_FILLER = 50.0 # blind corners: the fixed filler strip the door and the return run open past
    # L-shaped corner unit: NO filler on its arms (1.28.48). Its bi-fold pack turns on a zero-protrusion line and stands, open, inside the
    # unit's own width; the second door folds away from the other arm - the units on both arms open freely right against it.
    CORNER_L_FILLER = 0.0
    CORNER_PLAIN = %w[doors drawers2 drawers3 drawers4 drawer_doors pots open blind_corner filler].freeze

    def corner_unit_col?(col)
      return false unless col

      t = col['t'].to_s
      return true if t == 'corner_l'

      return true if t.start_with?('mech:') && BLIND_PAIRS.key?(t.sub('mech:', '')) # a blind corner unit IS the corner unit (the other run stands in front of its blind lane)

      it = t.start_with?('mech:') && Mechanisms.item(t.sub('mech:', ''))
      !!(it && it[:mb] == :carousel)
    end

    # takes need mm off the plain units nearest to the corner end of cols (first: the corner is at the start). Appliances, sink / hob and tall
    # units are stepped over: they keep their size and order and simply stand further along the run. nil when the plain units cannot give it.
    def corner_consume(cols, need, first)
      list = cols.map(&:dup)
      list.reverse! unless first
      i = 0
      while need > 0.5
        c = list[i]
        return nil unless c

        unless CORNER_PLAIN.include?(c['t'].to_s)
          i += 1
          next
        end
        w = c['w'].to_f
        if w <= need + 0.5
          list.delete_at(i)
          need -= w
        elsif w - need >= 300 || c['t'].to_s == 'filler'
          c['w'] = w - need
          need = 0
        else
          list.delete_at(i)                # what is left of it would be too narrow for a unit: it goes to the next plain unit, or stays a filler
          rest = w - need
          need = 0
          nx = list[i]
          if nx && CORNER_PLAIN.include?(nx['t'].to_s) && nx['t'].to_s != 'filler'
            nx['w'] = nx['w'].to_f + rest
          else
            list.insert(i, { 't' => 'filler', 'w' => rest })
          end
        end
      end
      list.reverse! unless first
      list
    end

    def ensure_corners(params, cfg)
      layout = (params['layout'] || 'straight').to_s
      return params unless %w[L U].include?(layout) && params['auto_corner'] != false && !params['as_drawn']

      p = JSON.parse(JSON.generate(params))
      runs = p['runs'] || {}
      a = runs['a']
      return params unless a && a['cols'].is_a?(Array) && a['cols'].any?

      grow = CORNER_AUTO_W - cfg['base_d'].to_f
      sides = []
      sides << ['b', true] if layout == 'U' || (p['l_side'] || 'left').to_s == 'left'
      sides << ['c', false] if layout == 'U' || (p['l_side'] || 'left').to_s == 'right'
      sides.each do |rid, first|
        side = runs[rid]
        next unless side && side['cols'].is_a?(Array) && side['cols'].any? && grow >= 0
        next if corner_unit_col?(first ? a['cols'].first : a['cols'].last)

        main = corner_consume(a['cols'], CORNER_AUTO_W + CORNER_L_FILLER, first)
        sc = corner_consume(side['cols'], grow + CORNER_L_FILLER, true)
        next unless main && sc && main.any? && sc.any?

        fil = CORNER_L_FILLER.positive? ? [{ 't' => 'filler', 'w' => CORNER_L_FILLER }] : []
        corner = [{ 't' => 'corner_l', 'w' => CORNER_AUTO_W }] + fil
        a['cols'] = first ? corner + main : main + corner.reverse
        side['cols'] = fil + sc
        side['len'] = side['len'].to_f - grow if side['len']
      end
      p
    end

    # ---- whole kitchen -----------------------------------------------------
    # params: 'layout' straight|L|U, 'l_side' left|right, 'runs' {a:,b:,c:}, 'origin'=>[x,y] mm
    class Cancelled < StandardError; end

    def purge_disabled_w2(root)
      return if root.nil? || !root.respond_to?(:entities)
      queue = root.entities.to_a
      until queue.empty?
        e = queue.shift
        if e.respond_to?(:get_attribute) && e.get_attribute(ATTR, 'tier').to_i == 2 && e.get_attribute(ATTR, 'kind').to_s == 'wall'
          e.erase! if e.valid?
          next
        end
        queue.concat(e.entities.to_a) if e.respond_to?(:entities)
      end
    end

    def generate(params, cfg, manage_operation: true, check_overlap: false)
      params = ensure_layout(params, cfg)
      model = Sketchup.active_model
      layout = (params['layout'] || 'straight').to_s
      runs = params['runs'] || {}
      model.start_operation('E.G.C Kitchen', true) if manage_operation
      Panel.reset_ids
      root = model.entities.add_group
      root.name = 'E.G.C Kitchen'
      re = root.entities
      a = runs['a'] || { 'len' => 4000, 'cols' => auto_columns(4000) }
      ends = cfg['end_panels'] ? true : false
      lside = (params['l_side'] || 'left')
      a_ends = case layout
               when 'L' then lside == 'left' ? [false, ends] : [ends, false]
               when 'U' then [false, false]
               else [ends, ends]
               end
      ga = build_run(re, a, cfg, 'A', ends: a_ends)
      c = cfg['base_d'].to_f
      room_w = a['len'].to_f
      a_cols = a['cols'] || []
      lcorner = ->(col) { col && (col['t'] == 'corner_l' || (corner_unit_col?(col) && !BLIND_PAIRS.key?(col['t'].to_s.sub('mech:', '')))) } # L corner / carousel: square
      c_left = lcorner.call(a_cols.first) ? a_cols.first['w'].to_f : c
      c_right = lcorner.call(a_cols.last) ? a_cols.last['w'].to_f : c
      ov = cfg['top_overhang'].to_f # a side run meeting a run end that is NOT an L corner unit stops its worktop at the main worktop's front edge
      rot = ->(deg) { Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), deg.degrees) }
      if layout == 'L' || layout == 'U'
        left = layout == 'U' || lside == 'left'
        right = layout == 'U' || lside == 'right'
        if left && runs['b']
          lb = runs['b']['len'].to_f
          gb = build_run(re, runs['b'], cfg, 'B', reverse: true, ends: [ends, false], top_trim: [0.0, lcorner.call(a_cols.first) ? 0.0 : ov])
          gb.transform!(Geom::Transformation.translation(Geom::Vector3d.new(0, -Geo.mm(c_left + lb), 0)) * rot.call(90))
        end
        if right && runs['c']
          gc = build_run(re, runs['c'], cfg, 'C', ends: [false, ends], top_trim: [lcorner.call(a_cols.last) ? 0.0 : ov, 0.0])
          gc.transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(room_w), -Geo.mm(c_right), 0)) * rot.call(-90))
        end
      elsif (layout == 'parallel' || layout == 'island') && runs['c']
        aisle = (params['aisle'] || cfg['aisle']).to_f
        lc = runs['c']['len'].to_f
        off = (params['c_offset'] || 0).to_f
        if layout == 'parallel'
          gc = build_run(re, runs['c'], cfg, 'C', ends: [ends, ends])
          wall_y = -(c + aisle + c)
        else
          di = (params['island_depth'] || c).to_f # island depth (the assistant can make it narrower): its FRONT stays where it was
          gc = build_run(re, runs['c'], cfg.merge('base_d' => di), 'C', island: true)
          wall_y = -(c + aisle + c) + (c - di)
        end
        gc.transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(off + lc), Geo.mm(wall_y), 0)) * rot.call(180))
      end
      root.set_attribute(ATTR, 'kitchen', true)
      root.set_attribute(ATTR, 'params', JSON.generate(params))
      RowEdit.restore(root, params, cfg) if params['row_state']
      o = params['origin']
      root.transform!(placement(o, params['rot'])) if o
      raise Cancelled, "cancelled" if check_overlap && resolve_overlap(root, model, (App.lang rescue "en")) == :cancel
      Numbering.apply(model) # permanent U-IDs for the new units (floor units first, layout order), cascaded to every board ID
      Exposure.refresh(cfg, model, own_op: false)
      model.commit_operation if manage_operation
      root
    rescue StandardError
      model.abort_operation if manage_operation
      raise
    end

    # ---- upper corner ----
    # Over a corner base stands an L-SHAPED CORNER WALL UNIT per tier (tier 1 and tier 2): the same square plan as the corner base, its two legs as
    # deep as that tier's wall units, bi-fold doors in the inside corner. Nothing of the two walls above the corner is left empty or blind.
    # corner_upper_spans gives the footprints (used by the proposal drawings); corner_uppers builds them.
    def corner_upper_spans(_side, s, _post, cfg)
      tiers = [[1, cfg['w1_d'].to_f]]
      tiers << [2, cfg['w2_d'].to_f] if cfg['w2_enabled']
      tiers.select { |_, d| s >= d + 150 }.map { |tier, d| { tier: tier, d: d, s: s } }
    end

    def corner_uppers(e, nm, x, w, hand, col, cfg, w1z, w2z)
      plain = !col['cu'] # an assistant corner ('cu') always carries its corner uppers; otherwise the column's own w1 / w2 choice decides
      corner_upper_spans(nil, w, 0, cfg).each do |sp|
        tier = sp[:tier]
        next if plain && col[tier == 1 ? 'w1' : 'w2'].to_s == 'none'
        next if tier == 2 && plain && col['w1'].to_s == 'none'

        spec = { name: "#{nm}_W#{tier}", kind: :wall, type: 'corner_l', w: w, h: tier == 2 ? cfg['w2_h'] : cfg['w1_h'], d: sp[:d], plinth: 0, hand: hand, corner: true,
                 cells: [{ t: :doors, shelves: tier == 2 ? 0 : 1 }], led_off: tier == 2 ? cfg['w2_led_off'] : cfg['w1_led_off'], tier: tier }
        spec[:exp_auto] = { 'b' => false, 'bv' => true } if tier == 2
        Cabinet.build(e, spec, cfg).transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), 0, Geo.mm(tier == 2 ? w2z : w1z))))
      end
    end

    def corner_post(run)
      c = (run['cols'] || []).first
      c && c['t'] == 'filler' ? c['w'].to_f : 0.0
    end

    def corner_wall(e, nm, x, w, cfg, tier, blind)
      z = cfg['base_h'].to_f + cfg['gap_h'].to_f + (tier == 2 ? cfg['w1_h'].to_f : 0.0)
      cell = { t: :doors, shelves: tier == 2 ? 0 : 1 }
      cell[:blind] = blind if blind
      spec = { name: "#{nm}_W#{tier}", kind: :wall, type: blind ? 'blind' : 'doors', w: w, h: tier == 2 ? cfg['w2_h'] : cfg['w1_h'], d: tier == 2 ? cfg['w2_d'] : cfg['w1_d'], plinth: 0,
               cells: [cell], led_off: tier == 2 ? cfg['w2_led_off'] : cfg['w1_led_off'], tier: tier }
      spec[:exp_auto] = { 'b' => false, 'bv' => true } if tier == 2
      Cabinet.build(e, spec, cfg).transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), 0, Geo.mm(z))))
    end

    # ---- duplicates ---------------------------------------------------------
    # "Generate at origin" (or Place) over a kitchen that is already standing on the same spot silently stacks TWO kitchens: coplanar boards fight
    # (an LED groove is closed by the old flat underside, an exposed end shows the old carcass board), old and new units become false
    # neighbours of each other, and every quantity is doubled. Before a generated kitchen is kept, every other generated kitchen that occupies
    # the same footprint is found and the user decides (replace / keep both / cancel). Automated runs set Kitchen.overlap_policy.
    def self.overlap_policy
      @overlap_policy
    end

    def self.overlap_policy=(v)
      @overlap_policy = v
    end

    def overlapping_kitchens(fresh, model = Sketchup.active_model)
      fb = fresh.bounds
      farea = [(fb.max.x - fb.min.x) * (fb.max.y - fb.min.y), 1.0].max
      model.entities.grep(Sketchup::Group).select do |g|
        next false if g.equal?(fresh) || !g.valid? || !g.get_attribute(ATTR, 'kitchen')

        b = g.bounds
        ox = [fb.max.x, b.max.x].min - [fb.min.x, b.min.x].max
        oy = [fb.max.y, b.max.y].min - [fb.min.y, b.min.y].max
        oz = [fb.max.z, b.max.z].min - [fb.min.z, b.min.z].max
        next false unless ox > 0 && oy > 0 && oz > 0

        area = [(b.max.x - b.min.x) * (b.max.y - b.min.y), 1.0].max
        ox * oy / [area, farea].min > 0.25
      end
    end

    # -> :ok (nothing overlapped, or the user chose keep / replace) or :cancel. Replace erases the overlapped kitchens (inside the caller's
    # operation, so one Undo brings them back).
    def resolve_overlap(fresh, model, lang = 'en')
      dups = overlapping_kitchens(fresh, model)
      return :ok if dups.empty?

      choice = overlap_policy
      if choice.nil?
        r = ::UI.messagebox(I18n.t('overlap_ask', lang), MB_YESNOCANCEL)
        choice = { IDYES => :replace, IDNO => :keep }[r] || :cancel
      end
      case choice
      when :replace then dups.each { |g| g.erase! if g.valid? }
      when :cancel then return :cancel
      end
      :ok
    end

    # Keep Load/Replace in agreement with a resized, recognized plan column.
    # Custom groups and independently edited layouts are left untouched.
    def sync_resized_column(run, x, old_width, new_width)
      root = find_owner_group(run)
      return false unless root && root.get_attribute(ATTR, 'kitchen')

      params = JSON.parse(root.get_attribute(ATTR, 'params', '{}'))
      key = run.name.downcase
      plan = (params['runs'] || {})[key]
      return false unless plan && plan['cols']

      columns = plan['cols'].each_with_index.to_a
      columns.reverse! if key == 'b' && %w[L U].include?(params['layout'])
      pos = 0.0
      match = columns.find do |col, _index|
        hit = (pos - x).abs < 1.0 && (col['w'].to_f - old_width).abs < 1.0
        pos += col['w'].to_f
        hit
      end
      return false unless match

      plan['cols'][match[1]]['w'] = new_width
      plan['len'] = plan['len'].to_f + new_width - old_width
      root.set_attribute(ATTR, 'params', JSON.generate(params))
      true
    end

    def placement(o, rot)
      t = Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(o[0]), Geo.mm(o[1]), Geo.mm(o[2] || 0)))
      t *= Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), rot.to_f.degrees) if rot.to_f != 0
      t
    end

    # ---- single units ------------------------------------------------------
    def mech_spec(p, cfg)
      it = Mechanisms.item(p['mech'])
      raise "Unknown mechanism #{p['mech']}" unless it

      kind = { 'wall' => :wall, 'tall' => :tall }[it[:host]] || :base
      tier = kind == :wall && p['tier'].to_i == 2 ? 2 : 1
      h = { wall: (tier == 2 ? cfg['w2_h'] : cfg['w1_h']), tall: Config.top_line(cfg), base: cfg['base_h'] }[kind]
      d = { wall: (tier == 2 ? cfg['w2_d'] : cfg['w1_d']), tall: cfg['base_d'], base: cfg['base_d'] }[kind]
      if (fx = it[:o][:fix]) # a reference mechanism measured at one size: the unit is built at that size
        p = p.merge('w' => it[:w], 'h' => fx[:h], 'd' => fx[:cd] + cfg['front_thk'].to_f)
      end
      Families.check!(it[:id], kind, (p['w'] || it[:w]).to_f, (p['h'] || h).to_f, (p['d'] || d).to_f, cfg, kind == :wall ? 0 : cfg['plinth'])
      room = nil
      if it[:id] == 'AVENTOS_HF'
        hh = (p['h'] || h).to_f
        room = cfg['ceiling'].to_f - default_z(p, cfg) - hh
        h1 = (hh - cfg['gap'].to_f) / 2.0
        ft = cfg['front_thk'].to_f
        need = Cabinet::HF_ANGLES.map { |a| [a, Cabinet.allocate.hf_pack_above(a, h1, ft)] }.last[1]
        raise "Bi-fold lift: configured ceiling leaves only #{room.round} mm above the unit, the folded fronts need #{need.round} mm even at the 83 degree stop. lower the unit or use another mechanism" if room < need
      end
      spec = { name: p['name'] || "EGC_#{it[:id]}", kind: kind, type: it[:id].downcase, w: (p['w'] || it[:w]).to_f,
               h: (p['h'] || h).to_f, d: (p['d'] || d).to_f, plinth: kind == :wall ? 0 : cfg['plinth'], cells: [],
               mech: it[:id], mech_n: (p['n'] || it[:o][:n]), hand: p['hand'], room_above: room, led_off: kind == :wall ? (tier == 2 ? cfg['w2_led_off'] : cfg['w1_led_off']) : nil, tier: (kind == :wall ? tier : nil) }.compact
      # a carousel belongs in the L-shaped corner base (square plan, two corner doors), never behind one wide door of a straight unit
      spec.merge!(corner: true, w: [spec[:w], spec[:d] + 300.0].max, hand: p['hand'] || 'L') if it[:mb] == :carousel
      spec[:no_bottom] = true if it[:o][:open_bottom] # the fitting travels out through the underside of the unit
      # a BLIND corner unit is used in the corner, the other run in front of its blind lane: no fixed cover panel there - carcass depth
      # like any unit, only the 50 mm strip by the door (owner, 1.28.51)
      spec[:blind_strip] = CORNER_AUTO_FILLER if BLIND_PAIRS.key?(it[:id].to_s)
      spec
    end

    def unit_spec(p, cfg)
      spec = unit_spec_base(p, cfg)
      if p['dev'] && !p['mech']
        dvk = (Catalog.device(p['dev']) || {})[:kind].to_s
        if spec[:type].to_s == 'hob_oven' && dvk =~ /hob/ then spec[:device_id2] = p['dev'] else spec[:device_id] = p['dev'] end
      end
      spec[:device_id2] = p['dev2'] if p['dev2'] && !p['mech']
      spec[:custom_id] = p['custom_id'] if p['custom_id']
      spec[:custom_name] = p['custom_name'] if p['custom_name']
      if p['cells'].is_a?(Array) && !p['cells'].empty? && !p['mech']
        spec[:cells] = Cabinet.normalize_cells(p['cells'])
        spec[:type] = 'custom'
        ids = Cabinet.device_ids_for_cells(spec[:cells])
        spec[:device_id] ||= ids[0]
        spec[:device_id2] ||= ids[1]
        Cabinet.check_cells!(spec, cfg)
      end
      spec
    end

    def unit_spec_base(p, cfg)
      return mech_spec(p, cfg) if p['mech']

      kind = p['kind'].to_s
      type = p['type'].to_s
      w = p['w'].to_f
      name = p['name'] || "EGC_#{kind}#{p['tier'].to_i == 2 ? '2' : ''}_#{type}"
      case kind
      when 'wall'
        tier = p['tier'].to_i == 2 ? 2 : 1
        h = (p['h'] || (tier == 2 ? cfg['w2_h'] : cfg['w1_h'])).to_f
        if type == 'hood'
          { name: name, kind: :hood, type: 'hood', w: w, h: h, d: (p['d'] || cfg['hood_d']).to_f, plinth: 0,
            cells: [{ t: :hood, h: cfg['hood_open_h'].to_f }, { t: :doors, shelves: 0 }] }
        else
          df = Library::WALL[type] || Library::WALL['doors']
          if df[:corner] # L-shaped corner wall unit: square plan, at least its depth + 150 wide
            return { name: name, kind: :wall, type: 'corner_l', w: [w, 600.0].max, h: h, d: (p['d'] || (tier == 2 ? cfg['w2_d'] : cfg['w1_d'])).to_f, plinth: 0, tier: tier, corner: true, hand: p['hand'],
                     cells: [{ t: :doors, shelves: tier == 2 ? 0 : 1 }], led_off: (tier == 2 ? cfg['w2_led_off'] : cfg['w1_led_off']) }
          end
          { name: name, kind: :wall, type: type, w: w, h: h, d: (p['d'] || (tier == 2 ? cfg['w2_d'] : cfg['w1_d'])).to_f, plinth: 0, tier: tier,
            cells: (tier == 2 ? df[:cells].map { |c| c.merge(shelves: 0) } : df[:cells]), led_off: (tier == 2 ? cfg['w2_led_off'] : cfg['w1_led_off']) }
        end
      when 'tall'
        return fridge_open_spec(name, w, cfg, p['dev'], type) if %w[fridge_open fridge_empty].include?(type)

        df = Library::TALL[type] || Library::TALL['pantry']
        { name: name, kind: :tall, type: type, w: w, h: (p['h'] || Config.top_line(cfg)).to_f,
          d: (p['d'] || cfg['base_d']).to_f, plinth: cfg['plinth'], cells: df[:cells] }
      else
        df = Library::BASE[type] || Library::BASE['doors']
        { name: name, kind: :base, type: type, w: w, h: (p['h'] || cfg['base_h']).to_f,
          d: (p['d'] || cfg['base_d']).to_f, plinth: df[:floor] ? 0 : cfg['plinth'], floor: df[:floor],
          cells: df[:cells], cutout: df[:cutout], corner: df[:corner], hand: p['hand'] || (df[:corner] ? 'L' : nil),
          device_id: df[:dev], device_id2: df[:dev2] }.compact
      end
    end

    def default_z(p, cfg)
      return p['z'].to_f if p['z'] && p['z'].to_s != ''

      wall = p['kind'].to_s == 'wall' || (p['mech'] && Mechanisms.item(p['mech'])[:host] == 'wall')
      return cfg['base_h'].to_f + cfg['gap_h'].to_f + cfg['w1_h'].to_f if wall && p['tier'].to_i == 2

      wall ? cfg['base_h'].to_f + cfg['gap_h'].to_f : 0.0
    end

    def tag_device(g, dv, w, h, d)
      g.set_attribute(ATTR, 'device', dv[:id])
      g.set_attribute(ATTR, 'dkind', dv[:kind])
      g.set_attribute(ATTR, 'dw', w)
      g.set_attribute(ATTR, 'dh', h)
      g.set_attribute(ATTR, 'dd', d)
    end

    # Rebuild a device at a new size from its own parametric builder (fixed-size details are re-created, never stretched).
    def rebuild_device(g, edit, cfg, manage_operation: true)
      model = Sketchup.active_model
      id = g.get_attribute(ATTR, 'device')
      dv = Catalog.device(id)
      raise 'not a device' unless dv

      w = (edit['w'] || g.get_attribute(ATTR, 'dw')).to_f
      h = (edit['h'] || g.get_attribute(ATTR, 'dh')).to_f
      d = (edit['d'] || g.get_attribute(ATTR, 'dd')).to_f
      raise 'size' if w < 100 || h < 20 || d < 100

      model.start_operation('Edit E.G.C appliance', true) if manage_operation
      t = g.transformation
      ng = Appliances.place(g.parent.entities, "EGC_#{dv[:id]}", dv[:kind], 0, 0, 0, w, d, h, Catalog.dev_cfg(dv, cfg))
      ng.transform!(t)
      tag_device(ng, dv, w, h, d)
      g.erase!
      model.selection.clear
      model.selection.add(ng)
      model.commit_operation if manage_operation
      ng
    rescue StandardError
      model.abort_operation if manage_operation
      raise
    end

    # next free manual Unit ID in the model
    def next_manual_code(model)
      used = []
      stack = model.entities.to_a
      until stack.empty?
        e = stack.shift
        next unless e.is_a?(Sketchup::Group)

        c = e.get_attribute(ATTR, 'code').to_s
        used << c[/\AM(\d+)/, 1].to_i if c =~ /\AM\d+/
        stack.concat(e.entities.to_a)
      end
      format('M%02d', (used.max || 0) + 1)
    end

    # at: a ready world transformation of the unit frame (the snapped pose of the placement tool) - it replaces origin / rot / default height
    def place_unit(p, cfg, origin, rot, at: nil)
      model = Sketchup.active_model
      model.start_operation('E.G.C Unit', true)
      z = origin[2].to_f + default_z(p, cfg)
      t = at || placement([origin[0], origin[1], z], rot)
      if p['kind'].to_s == 'device'
        dv = Catalog.device(p['dev'])
        w = (p['w'] || dv[:w]).to_f
        h = (p['h'] || dv[:h]).to_f
        d = (p['d'] || dv[:d]).to_f
        g = Appliances.place(model.entities, "EGC_#{dv[:id]}", dv[:kind], 0, 0, 0, w, d, h, Catalog.dev_cfg(dv, cfg))
        g.transform!(t)
        tag_device(g, dv, w, h, d)
      elsif p['kind'].to_s == 'slot'
        sd = Library::SLOT[p['type'].to_s] || Library::SLOT['washer']
        w = p['w'].to_f
        h = sd[:under] ? cfg['base_h'].to_f - cfg['top_thk'].to_f - 5 : (p['h'] || sd[:h]).to_f
        g = Appliances.place(model.entities, "EGC_#{p['type']}", sd[:app], 0, 10, 0, w - 4, cfg['base_d'].to_f * sd[:d] - 10, h, cfg)
        g.transform!(t * Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(2), 0, 0)))
        g.set_attribute(ATTR, 'slot_w', w)
        g.set_attribute(ATTR, 'slot_inset_x', 2.0)
      else
        spec = unit_spec(p, cfg)
        spec[:own_top] = true if spec[:kind] == :base && %w[sink sink_drawer hob hob_oven].include?(spec[:type].to_s) && !spec[:mech]
        spec[:code] ||= Numbering.plan_next(model) # permanent Unit ID (next free U-number) for a manually placed unit
        if cfg['unit_fascia'] != false && cfg['unit_fascia_h'].to_f.positive? && !spec[:corner] &&
           (spec[:kind] == :tall || (spec[:kind] == :wall && default_z(p, cfg) + spec[:h].to_f >= Config.top_line(cfg) - 1.0))
          spec[:top_strip] = cfg['unit_fascia_h'].to_f # the unit stands alone: it carries its own finish strip on top
        end
        mods = TallStack.build(model.entities, spec, cfg)
        mods.each { |mg| mg.transform!(t) }
        g = mods.first
      end
      Numbering.apply(model)
      model.selection.clear
      model.selection.add(g)
      placed_name = g.name
      Exposure.refresh(cfg, model, own_op: false)
      unless g.valid? # the exposure pass rebuilt the unit (LED groove / finish): hand back, and keep selected, the unit that stands there now
        g = model.entities.grep(Sketchup::Group).select { |x| x.name == placed_name && x.get_attribute(ATTR, 'spec') }.last || g
        model.selection.add(g) if g.valid?
      end
      model.commit_operation
      place_stack(p, cfg, origin, rot, at, g) if p['stack'].is_a?(Array) && !p['stack'].empty?
      place_fridge_box(g, cfg, origin, rot) if %w[fridge_open fridge_empty].include?(p['type'].to_s) && p['over'] != false && g.valid?
      g
    rescue StandardError => e
      model.abort_operation
      Diag.log("place_unit", p.is_a?(Hash) ? p.slice("kind", "type", "mech", "dev", "w", "h", "d") : {}, error: e, state: e.is_a?(MechanismError) ? "refused" : "failed")
      raise
    end

    # A COLUMN SET from the library (base + upper 1 + upper 2, one width): the base is placed where the user clicks, the uppers go straight
    # above it - same left edge, backs on the same line, each at its own height (Kitchen.default_z) - every one a normal unit with its own ID.
    # a refrigerator housing placed on its own gets the box above the refrigerator up to the top line, as in a generated kitchen
    # (its own unit: own ID, same width and depth as the housing)
    def place_fridge_box(g, cfg, origin, rot)
      h = g.get_attribute(ATTR, 'h').to_f
      over_h = Config.top_line(cfg) - h
      return if over_h <= 150

      sp = { 'kind' => 'wall', 'type' => 'doors', 'w' => g.get_attribute(ATTR, 'w').to_f, 'h' => over_h, 'd' => g.get_attribute(ATTR, 'd').to_f }
      place_unit(sp, cfg, origin, rot, at: g.transformation * Geom::Transformation.translation(Geom::Vector3d.new(0, 0, h.mm)))
      Sketchup.active_model.selection.add(g) if g.valid?
    end

    def place_stack(p, cfg, origin, rot, at, base_g)
      bt = at || placement([origin[0], origin[1], origin[2].to_f + default_z(p, cfg)], rot)
      floor = bt.origin.z.to_mm - default_z(p, cfg)
      it = p['mech'] && Mechanisms.item(p['mech'].to_s)
      corner = p['type'].to_s == 'corner_l' || (it && it[:mb] == :carousel) # an L corner base carries L corner wall units, same hand
      p['stack'].each do |sp|
        sp = sp.merge('w' => sp['w'] || p['w'])
        sp = sp.merge('type' => 'corner_w', 'hand' => p['hand'] || 'L') if corner && sp['type'].to_s != 'hood'
        dz = floor + default_z(sp, cfg) - bt.origin.z.to_mm
        place_unit(sp, cfg, origin, rot, at: Geom::Transformation.translation(Geom::Vector3d.new(0, 0, dz.mm)) * bt)
      end
      model = Sketchup.active_model
      model.selection.add(base_g) if base_g.valid?
    end

    # Smart front replace: flat | shaker | bevel (routed pocket) | glass (door cells become glass) | auto (follow config)
    # Sizes of the handle-free profile a unit may carry on its own: the PROFILE section (what is bought). The carcass is not notched for the
    # profile in this model (the front rail is set back and the fronts are cut shorter), so there is no separate notch size to store.
    GOLA_LIMITS = { 'l_h' => [30.0, 120.0], 'l_d' => [15.0, 60.0], 'c_h' => [40.0, 150.0], 'c_d' => [15.0, 60.0], 'gap' => [15.0, 60.0] }.freeze # gap = the finger space the fronts are cut back by

    # -> the checked override ({} = none). Refuses zero / negative / out-of-range sizes and sizes that leave no room for the fronts.
    def gola_override(raw, spec, cfg)
      return {} if raw.nil? || raw.to_s == 'auto' || (raw.is_a?(Hash) && raw.empty?)
      raise 'gola: sizes expected | مقاسات البروفايل غير صحيحة' unless raw.is_a?(Hash)

      names = { 'l_h' => ['L profile height', 'ارتفاع بروفايل L'], 'l_d' => ['L profile depth', 'عمق بروفايل L'], 'c_h' => ['C profile height', 'ارتفاع بروفايل C'], 'c_d' => ['C profile depth', 'عمق بروفايل C'], 'gap' => ['finger gap', 'فتحة الإصبع'] }
      out = {}
      raw.each do |k, v|
        k = k.to_s
        lim = GOLA_LIMITS[k] or next
        x = v.to_f
        unless x.positive? && x.between?(lim[0], lim[1])
          raise "#{names[k][0]} #{v.inspect}: must be between #{lim[0].round} and #{lim[1].round} mm | #{names[k][1]} #{v}: لازم يكون بين #{lim[0].round} و #{lim[1].round} مم"
        end

        out[k.to_sym] = x
      end
      eff = ->(k) { out[k.to_sym] || cfg["gola_#{k}"].to_f }
      depth = spec[:d].to_f - cfg['front_thk'].to_f
      if [eff.call('l_d'), eff.call('c_d')].max > depth / 3.0
        raise "profile depth #{[eff.call('l_d'), eff.call('c_d')].max.round} is too much for a #{depth.round} mm deep carcass | عمق البروفايل أكبر من المسموح لعمق الوحدة #{depth.round} مم"
      end
      body = spec[:h].to_f - spec[:plinth].to_f - (spec[:kind].to_s == 'base' ? cfg['top_thk'].to_f : 0.0)
      if spec[:kind].to_s == 'base' && eff.call('l_h') + 2 * eff.call('c_h') > body - 300.0
        raise "the profiles (L #{eff.call('l_h').round} + C #{eff.call('c_h').round}) leave no room for the fronts of a #{body.round} mm high unit | البروفايلات لا تترك مكاناً للواجهات في وحدة ارتفاعها #{body.round} مم"
      end
      out
    end

    def apply_style_edit(spec, style)
      style = style.to_s
      glassify = lambda do |cells, on|
        cells.each do |c|
          if c[:t] == :doors
            if on
              c[:glass] = true
            elsif spec[:glass_all]
              c.delete(:glass)
            end
          end
          glassify.call(c[:cols], on) if c[:cols].is_a?(Array)
        end
      end
      if style == 'glass'
        if spec[:mech] # a mechanism unit has no cells: its door fronts become glass when it is built (Cabinet#front)
          spec[:glass_all] = true
          return
        end

        glassify.call(spec[:cells] || [], true)
        spec[:glass_all] = true
      else
        glassify.call(spec[:cells] || [], false) if spec[:glass_all] && !spec[:mech]
        spec.delete(:glass_all)
        if style == 'auto' || style.empty?
          spec.delete(:style)
        elsif %w[flat shaker bevel].include?(style)
          spec[:style] = style
        end
      end
    end

    # Build a real replacement when the cabinet family changes.  A type edit
    # inside one family can use the regular rebuild below; a kind edit cannot:
    # base/wall/tall have different plinths, cells, fronts and worktop duties.
    # The old unit code is retained as the logical tall assembly code, while
    # TallStack assigns its two physical modules the established <code>L/U IDs.
    def conversion_spec(old, target, cfg, edit)
      type = old[:type].to_s
      type = case target
             when :base then Library::BASE.key?(type) ? type : 'doors'
             when :wall then Library::WALL.key?(type) ? type : 'doors'
             when :tall then Library::TALL.key?(type) ? type : 'pantry'
             end
      p = { 'kind' => target.to_s, 'type' => type, 'w' => (edit['w'] || old[:w]).to_f,
            'name' => old[:name], 'tier' => (target == :wall ? 1 : nil) }
      p['h'] = edit['h'] if edit['h'].to_f.positive?
      p['d'] = edit['d'] if edit['d'].to_f.positive?
      spec = unit_spec(p, cfg)
      # Converting a lower into a tall is an explicit production request for
      # two stacked carcasses, even when the current stock setting would allow
      # one long side panel.  TallStack validates the available upper height.
      spec[:force_stack] = true if target == :tall
      %i[code exp mats style handle handle_pos gola hand].each { |k| spec[k] = old[k] if old.key?(k) && !old[k].nil? }
      spec
    end

    def rebuild_converted_cabinet(grp, edit, cfg, manage_operation:, skip_exposure:, refresh_geometry:)
      model = Sketchup.active_model
      old = Cabinet.spec_from_json(grp.get_attribute(ATTR, 'spec'))
      target = edit['kind'].to_s
      raise 'Unit type must be base, wall, or tall.' unless %w[base wall tall].include?(target)
      target = target.to_sym
      return rebuild_cabinet(grp, edit.reject { |k, _| k == 'kind' }, cfg, manage_operation: manage_operation,
                             skip_exposure: skip_exposure, refresh_geometry: refresh_geometry) if old[:kind] == target

      model.start_operation('Convert E.G.C unit', true) if manage_operation
      parent = grp.parent.entities
      old_parts = Numbering.part_keys(grp)
      old_code = old[:code] || grp.get_attribute(ATTR, 'code')
      spec = conversion_spec(old, target, cfg, edit)
      spec[:code] = old_code
      t = grp.transformation
      target_z = target == :wall ? cfg['base_h'].to_f + cfg['gap_h'].to_f : 0.0
      t = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, (target_z - t.origin.z.to_mm).mm)) * t
      built = target == :tall ? TallStack.build(parent, spec, cfg) : [Cabinet.build(parent, spec, cfg)]
      built.each { |ng| ng.transform!(t) }
      Numbering.keep_part_ids(old_parts, built.first) if built.size == 1
      built.each do |ng|
        ng.set_attribute(ATTR, 'converted_from_code', old_code)
        ng.set_attribute(ATTR, 'unit_type', Numbering::TYPE[ng.get_attribute(ATTR, 'kind').to_s])
      end
      grp.erase!
      primary = built.first
      # A generated run is refreshed by RowEdit after this method returns.  For
      # a free run, remove/rebuild the continuous top now so a former base can
      # never leave a slab embedded in a tall or upper unit.
      if refresh_geometry && target != :base
        tx0 = primary.transformation.origin.x.to_mm
        tx1 = tx0 + primary.get_attribute(ATTR, 'w').to_f
        p_ents = primary.parent.respond_to?(:entities) ? primary.parent.entities : Sketchup.active_model.entities
        owner = find_owner_group(primary)
        if owner && owner.get_attribute(ATTR, 'run') && !owner.get_attribute(ATTR, 'worktop_wrap')
          # Generated run: the slab must NEVER rise with the converted tower -
          # drop every countertop / upstand / backsplash piece over this column
          # AND every wall/hood group sitting above the tower (otherwise the
          # upper row keeps floating mid-air on top of the tower, which reads
          # exactly like "marble riding up" when the wall fronts are dark).
          erase_top_pieces(owner.entities, tx0, tx1)
          strip_upper_over_span!(owner.entities, tx0, tx1)
          # Free chain: strip the old slab over the tower span in every wrap's
          # own frame, then rebuild the slab of EVERY remaining base chain at
          # the BASE units' height - never at the tower's.
          strip_top_over_span_world!(p_ents, tx0, tx1)
          rebuilt = []
          p_ents.grep(Sketchup::Group).select { |q| q.valid? && base_kind?(q) }.each do |seed|
            sx = seed.transformation.origin.x.to_mm
            next if rebuilt.any? { |(a, b)| sx >= a - 1.0 && sx <= b + 1.0 }

            chain = connected_run(seed)
            next if chain.empty?

            rebuilt << [chain.map { |q| q.transformation.origin.x.to_mm }.min,
                        chain.map { |q| q.transformation.origin.x.to_mm + q.get_attribute(ATTR, 'w').to_f }.max]
            rebuild_free_worktop(chain, cfg)
          end
        end
        # The generator never hangs an upper over a full-height tower.
        strip_upper_over_span!(p_ents, tx0, tx1) if target == :tall
      end
      Exposure.refresh(cfg, model, own_op: false) unless skip_exposure
      model.selection.clear
      model.selection.add(primary) if primary.valid?
      model.commit_operation if manage_operation
      primary
    rescue StandardError
      model.abort_operation if manage_operation
      raise
    end

    def rebuild_cabinet(grp, edit, cfg, manage_operation: true, skip_exposure: false, refresh_geometry: true, partner: true)
      old_kind = Cabinet.spec_from_json(grp.get_attribute(ATTR, 'spec'))[:kind].to_s
      if edit['kind'] && edit['kind'].to_s != old_kind
        return rebuild_converted_cabinet(grp, edit, cfg, manage_operation: manage_operation,
                                         skip_exposure: skip_exposure, refresh_geometry: refresh_geometry)
      end
      model = Sketchup.active_model
      op_started = false
      spec = Cabinet.spec_from_json(grp.get_attribute('egc', 'spec'))
      %w[w h d].each { |k| spec[k.to_sym] = edit[k].to_f if edit[k] && edit[k].to_f > 0 }
      spec[:hand] = edit['hand'] if edit['hand']
      if edit.key?('exp') # per-face override of the automatic exposure: auto | exposed | hidden (auto = not stored)
        ex = edit['exp'].is_a?(Hash) ? edit['exp'].each_with_object({}) { |(k, v), o| o[k.to_sym] = v.to_s if %w[exposed hidden].include?(v.to_s) && %w[l r b t].include?(k.to_s) } : {}
        ex.empty? ? spec.delete(:exp) : spec[:exp] = ex
      end
      apply_style_edit(spec, edit['style']) if edit['style']
      if edit['handle'] # the unit's own handle type ('auto' = follow the project setting again)
        edit['handle'].to_s == 'auto' ? spec.delete(:handle) : spec[:handle] = edit['handle'].to_s
      end
      if edit['handle_pos'] # where the handle sits on this unit's doors: top | bottom | side ('auto' = by the unit kind)
        %w[top bottom side].include?(edit['handle_pos'].to_s) ? spec[:handle_pos] = edit['handle_pos'].to_s : spec.delete(:handle_pos)
      end
      if edit.key?('mats') # the unit's OWN materials { 'front' => swatch code, 'carcass' => code } ({} / nil = follow the kitchen again)
        m = (spec[:mats] || {}).transform_keys(&:to_s).merge((edit['mats'] || {}).transform_keys(&:to_s))
        m = m.reject { |k, v| v.to_s.empty? || v.to_s == 'auto' || !%w[front carcass].include?(k) }
        edit['mats'].nil? || edit['mats'].empty? || m.empty? ? spec.delete(:mats) : spec[:mats] = m
      end
      if edit.key?('gola') # the unit's own handle-free profile sizes (nil / {} / 'auto' = follow the kitchen settings again)
        ov = gola_override(edit['gola'], spec, cfg)
        ov.empty? ? spec.delete(:gola) : spec[:gola] = ov
      end
      if edit['sink_model'] # the unit's own sink kind ('auto' = follow the project setting again)
        raise 'This unit has no sink. | الوحدة دي مفيهاش حوض.' unless Cabinet::SINK_TYPES.include?(spec[:type].to_s)

        edit['sink_model'].to_s == 'auto' ? spec.delete(:sink_model) : spec[:sink_model] = edit['sink_model'].to_s
      end
      if edit.key?('blind_strip') # a unit stands in front of the blind lane: the fixed cover panel goes, the visible strip by the door stays
        v = edit['blind_strip'].to_f
        v.positive? ? spec[:blind_strip] = v : spec.delete(:blind_strip)
      end
      if edit.key?('top_strip') # the finish strip on top of a unit standing on its own (unit panel: on / off)
        v = edit['top_strip'].to_f
        v.positive? ? spec[:top_strip] = v : spec.delete(:top_strip)
      end
      if edit['hob_model'] # the unit's own hob kind ('auto' = follow the project setting again)
        raise 'This unit has no hob. | الوحدة دي مفيهاش بوتجاز.' unless %w[hob hob_oven].include?(spec[:type].to_s)

        edit['hob_model'].to_s == 'auto' ? spec.delete(:hob_model) : spec[:hob_model] = edit['hob_model'].to_s
      end
      if edit.key?('notch')
        nt = edit['notch']
        if nt.is_a?(Hash) && nt['w'].to_f > 0 && nt['d'].to_f > 0 && %w[l r].include?(nt['side'].to_s)
          raise I18n.t('notch_no_mech') if spec[:mech]

          spec[:notch] = { side: nt['side'].to_s, w: nt['w'].to_f, d: nt['d'].to_f }
        else
          spec.delete(:notch)
        end
      end
      spec[:extras] = Array(edit["extras"]).map { |e| e.each_with_object({}) { |(k, v), o| o[k.to_sym] = v } } if edit.key?("extras")
      if edit['cells'].is_a?(Array) && !edit['cells'].empty?
        spec.delete(:mech)
        spec[:cells] = Cabinet.normalize_cells(edit['cells'])
        spec[:type] = 'custom'
        ids = Cabinet.device_ids_for_cells(spec[:cells])
        spec[:device_id] = ids[0]
        spec[:device_id2] = ids[1]
        Cabinet.check_cells!(spec, cfg)
      end
      if edit['mech']
        if edit['mech'] == 'none'
          spec.delete(:mech)
          df = Library::BASE[spec[:type].to_s] || Library::TALL[spec[:type].to_s] || Library::WALL[spec[:type].to_s]
          spec[:cells] = (df ? df[:cells] : Library::WALL['doors'][:cells])
          spec[:type] = 'doors' unless df
        else
          spec[:mech] = edit['mech']
          spec[:mech_n] = edit['n'] if edit['n']
          spec[:cells] = []
        end
      end
      if edit['type'] && edit['type'].to_s != spec[:type].to_s
        old_notch = spec[:notch]
        old_dev = spec[:device_id]
        old_code = spec[:code]
        ns = unit_spec({ 'kind' => spec[:kind].to_s == 'hood' ? 'wall' : spec[:kind].to_s, 'type' => edit['type'],
                         'w' => spec[:w], 'h' => spec[:h], 'd' => spec[:d], 'name' => spec[:name], 'tier' => spec[:tier] }, cfg)
        spec = ns
        spec[:code] = old_code if old_code # a manually placed unit keeps its Unit ID (M01 ...) through Replace
        spec[:notch] = old_notch if old_notch && !ns[:mech]
      end
      if spec[:mech]
        Families.check!(spec[:mech], spec[:kind].to_s == 'hood' ? 'wall' : spec[:kind].to_s, spec[:w], spec[:h], spec[:d], cfg, spec[:plinth])
      end
      model.start_operation('Edit E.G.C unit', true) if manage_operation
      op_started = true
      parent = grp.parent.entities
      t = grp.transformation
      spec[:code] ||= grp.get_attribute(ATTR, 'code') # the unit keeps its permanent ID through every rebuild
      old_parts = Numbering.part_keys(grp)
      ng = Cabinet.build(parent, spec, cfg)
      ng.transform!(t)
      Numbering.keep_part_ids(old_parts, ng) # unchanged boards keep their Part IDs, new boards get new numbers
      ng.set_attribute(ATTR, 'unit_type', Numbering::TYPE[ng.get_attribute(ATTR, 'kind').to_s])
      sp = grp.get_attribute(ATTR, "space_pt")
      ng.set_attribute(ATTR, "space_pt", sp) if sp # the Space tool lock follows the unit through every rebuild (resize, edit, ...)
      # a tall unit built as two stacked modules: the rebuilt module stays part of its assembly, and what the user sets for the unit as a whole
      # (finish of the sides, handle, front style) is applied to the other module as well
      asm_code = grp.get_attribute(ATTR, 'tall_assembly')
      mate = nil
      if asm_code
        %w[tall_assembly tall_role tall_lower tall_upper tall_joint_z tall_total_h].each { |k| (v = grp.get_attribute(ATTR, k)).nil? || ng.set_attribute(ATTR, k, v) }
        shared = edit.select { |k, _| %w[exp handle style].include?(k.to_s) }
        if partner && !shared.empty?
          mate = parent.grep(Sketchup::Group).find do |x|
            x != grp && x != ng && x.valid? && x.get_attribute(ATTR, 'tall_assembly') == asm_code && x.get_attribute(ATTR, 'tall_role') != grp.get_attribute(ATTR, 'tall_role') &&
              (x.transformation.origin.x - t.origin.x).abs < 1.mm && (x.transformation.origin.y - t.origin.y).abs < 1.mm
          end
        end
      end
      grp.erase!
      rebuild_cabinet(mate, shared, cfg, manage_operation: false, skip_exposure: true, refresh_geometry: false, partner: false) if mate
      refresh_worktop_after_edit(ng, cfg) if refresh_geometry && spec[:kind] == :base
      refresh_plinth_after_edit(ng, cfg) if refresh_geometry && spec[:kind] == :base
      model.selection.clear
      model.selection.add(ng)
      built_name = ng.name
      Exposure.refresh(cfg, model, own_op: false) unless skip_exposure
      unless ng.valid? # the exposure pass rebuilt the unit once more: go on with (and keep selected) the unit that stands there now
        ng = parent.grep(Sketchup::Group).select { |x| x.name == built_name && x.get_attribute(ATTR, 'spec') }.last || ng
        model.selection.add(ng) if ng.valid?
      end
      if refresh_geometry && !edit.empty?
        owner = find_owner_group(ng)
        RowEdit.capture(owner, cfg) if owner && owner.get_attribute(ATTR, 'run')
      end
      model.commit_operation if manage_operation
      ng
    rescue StandardError
      model.abort_operation if manage_operation && op_started
      raise
    end

    # Sketchup::Entity#parent returns the owning ComponentDefinition, not the Group instance that
    # holds it - and a Group's own attributes live on the instance, not the definition - so it
    # cannot tell us "which group contains this cabinet". Find it the only reliable way: search.
    def find_owner_group(target, scope = Sketchup.active_model.entities)
      scope.each do |e|
        next unless e.is_a?(Sketchup::Group)

        list = e.entities.to_a
        return e if list.include?(target)

        found = find_owner_group(target, e.entities)
        return found if found
      end
      nil
    end

    # After a base cabinet is resized in place, rebuild the countertop (+ upstand/backsplash) that
    # used to rest on it, so "growing/shrinking a unit moves the slab above it" without touching
    # any neighbour. Grows to cover the full original extent of every slab piece it touches first
    # (a resize can make the cabinet overlap or gap its neighbour instead of just abutting it), so
    # no part of the old slab is left erased without a replacement.
    # Called after any Edit/Replace/Resize on a base unit: keeps whatever worktop already exists over
    # it in sync (Move/Resize/Replace/Apply/Save-Reload all just rebuild geometry through here). Never
    # creates a worktop that wasn't there before - a plain edit on a unit nobody has run Worktop on
    # stays exactly that, a plain edit.
    # The worktop thickness is part of every base unit (carcass = total height - worktop): units built for another thickness are rebuilt,
    # or a thicker slab would sit IN the drawer / door tops and handles (a thinner one would float) and the cut list would keep the old
    # gables. -> { old group => new group } for the units that were rebuilt.
    def fit_units_to_top(units, cfg)
      th = cfg['top_thk'].to_f
      out = {}
      units.each do |u|
        next unless u.valid?

        spec = Cabinet.spec_from_json(u.get_attribute(ATTR, 'spec'))
        next unless spec[:kind] == :base

        gab = u.entities.grep(Sketchup::Group).find { |x| %w[side_l side_r].include?(x.get_attribute(ATTR, 'part').to_s) }
        next unless gab
        next if (gab.bounds.max.z.to_mm - (spec[:h].to_f - th)).abs < 0.6

        ng = rebuild_cabinet(u, {}, cfg, manage_operation: false, skip_exposure: true, refresh_geometry: false, partner: false)
        out[u] = ng if ng
      end
      out
    end

    def refresh_worktop_after_edit(ng, cfg)
      run = find_owner_group(ng)
      if run && run.get_attribute(ATTR, 'run') && !run.get_attribute(ATTR, 'worktop_wrap')
        rebuild_local_countertop(ng, cfg)
        return
      end

      parent_ents = ng.parent.respond_to?(:entities) ? ng.parent.entities : Sketchup.active_model.entities
      wg = Snap.world_of(ng)
      w = ng.get_attribute(ATTR, 'w').to_f
      return unless find_free_wrap(parent_ents, wg, 0.0, w)

      chain = connected_run(ng)
      rebuild_free_worktop(chain, cfg) unless chain.empty?
    end

    # Any rebuild of a base cabinet inside a generated run (Edit, Replace, style, exp, mechanism...)
    # would otherwise leave it holding a fresh standalone plinth board directly under/overlapping the
    # still-standing continuous run piece from before - re-join right after, same as the worktop.
    # Falls back to the free-chain path (manually placed/snapped touching units) exactly like
    # refresh_worktop_after_edit does, so a manual run gets one continuous plinth too.
    def refresh_plinth_after_edit(ng, cfg)
      run = find_owner_group(ng)
      if run && run.get_attribute(ATTR, 'run') && !run.get_attribute(ATTR, 'worktop_wrap')
        join_plinth_run(run.entities, run.name, cfg)
        return
      end

      chain = connected_run(ng)
      rebuild_free_plinth(chain, cfg) if chain.size > 1
    end

    def rebuild_local_countertop(cab, cfg)
      run = find_owner_group(cab)
      return unless run && run.get_attribute(ATTR, 'run')

      ents = run.entities
      bases = ents.grep(Sketchup::Group).select { |g| base_kind?(g) }
      return if bases.empty?

      cx0 = cab.transformation.origin.x.to_mm
      cx1 = cx0 + cab.get_attribute(ATTR, 'w').to_f
      tops = ents.grep(Sketchup::Group).select { |g| %w[countertop upstand backsplash].include?(g.get_attribute(ATTR, 'part')) }
      bases = bases.reject { |g| g.get_attribute(ATTR, 'converted_from_code') || g.get_attribute(ATTR, 'kind').to_s == 'tall' }
      return if bases.empty?
      lo, hi = grow_to_cover(tops, cx0, cx1)

      span_group = bases.select do |g|
        x0 = g.transformation.origin.x.to_mm
        x1 = x0 + g.get_attribute(ATTR, 'w').to_f
        x0 < hi - 0.5 && x1 > lo + 0.5
      end.sort_by { |g| g.transformation.origin.x.to_mm }
      return if span_group.empty?

      start_x = span_group.map { |g| g.transformation.origin.x.to_mm }.min
      end_x = span_group.map { |g| g.transformation.origin.x.to_mm + g.get_attribute(ATTR, 'w').to_f }.max
      if (tt = (JSON.parse(run.get_attribute(ATTR, 'top_trim').to_s) rescue nil)) # the corner end of a side run (see build_run top_trim)
        rl = run.get_attribute(ATTR, 'run_len').to_f
        start_x += tt[0].to_f if start_x.abs < 0.5
        end_x -= tt[1].to_f if (end_x - rl).abs < 0.5
      end
      holes = span_group.filter_map { |g| cutout_for(g, cfg) }
      top_h = slab_reference_h(span_group, cfg)
      cuts = span_group[1..].map { |g| g.transformation.origin.x.to_mm }
      opts = run.get_attribute(ATTR, 'island') ? { back: cfg['island_overhang'].to_f } : {}
      erase_top_pieces(ents, start_x, end_x)
      countertop(ents, "#{run.name}_top_r#{start_x.round}", { start: start_x, end: end_x, holes: holes }, cfg.merge('base_h' => top_h), cuts, opts)
    end

    def grow_to_cover(tops, lo, hi)
      loop do
        grown = false
        tops.each do |g|
          ox = g.transformation.origin.x.to_mm
          len = g.get_attribute(ATTR, 'len').to_f
          next unless ox < hi - 0.5 && ox + len > lo + 0.5

          if ox < lo - 0.01
            lo = ox
            grown = true
          end
          if ox + len > hi + 0.01
            hi = ox + len
            grown = true
          end
        end
        break unless grown
      end
      [lo, hi]
    end

    def base_kind?(g)
      Cabinet.spec_from_json(g.get_attribute(ATTR, 'spec'))[:kind] == :base
    rescue StandardError
      false
    end

    WORKTOP_PARTS = %w[countertop upstand backsplash fascia end_panel plinth].freeze

    # A click that lands on the shared worktop / fascia / end-panel covering a run still means
    # "the unit under this point" to the user - those parts are siblings of the cabinets inside
    # the run (or, for a free-standing connected chain, siblings living next to it), never nested
    # inside any one cabinet's own group, so a plain ray-path ancestor walk (RadialMenuTool#find_unit,
    # Space.unit_in_path) never resolves to a spec group for them and the click silently does nothing.
    def unit_under_worktop(part_group, hit_pt)
      owner = find_owner_group(part_group)
      return nil unless owner

      if owner.get_attribute(ATTR, 'worktop_wrap')
        parent_ents = owner.parent.respond_to?(:entities) ? owner.parent.entities : Sketchup.active_model.entities
        inv = Snap.world_of(owner).inverse
        local_x = (inv * hit_pt).x.to_mm
        parent_ents.grep(Sketchup::Group).select { |g| g.valid? && g != owner && base_kind?(g) }.find do |g|
          l = inv * Snap.world_of(g)
          next false if l.xaxis.normalize.x < 0.98
          x0 = l.origin.x.to_mm
          x1 = x0 + g.get_attribute(ATTR, 'w').to_f
          local_x >= x0 - 0.5 && local_x <= x1 + 0.5
        end
      elsif owner.get_attribute(ATTR, 'run')
        local_x = (owner.transformation.inverse * hit_pt).x.to_mm
        owner.entities.grep(Sketchup::Group).select { |g| base_kind?(g) }.find do |g|
          x0 = g.transformation.origin.x.to_mm
          x1 = x0 + g.get_attribute(ATTR, 'w').to_f
          local_x >= x0 - 0.5 && local_x <= x1 + 0.5
        end
      end
    end

    def cutout_for(g, cfg)
      cutout_for_at(g, g.transformation.origin.x.to_mm, cfg)
    end

    def cutout_for_at(g, local_x, cfg)
      spec = Cabinet.spec_from_json(g.get_attribute(ATTR, 'spec'))
      df = Library::BASE[spec[:type].to_s]
      return nil unless df && df[:cutout]

      cfg = cfg.merge('sink_model' => spec[:sink_model].to_s) unless spec[:sink_model].to_s.empty? # the worktop opening follows the unit's own sink
      cfg = cfg.merge('hob_model' => spec[:hob_model].to_s) unless spec[:hob_model].to_s.empty?    # ... and its own hob
      cutout_rect(df[:cutout], local_x, g.get_attribute(ATTR, 'w').to_f, cfg)
    rescue StandardError
      nil
    end

    def erase_top_pieces(ents, start_x, end_x)
      n = 0
      ents.grep(Sketchup::Group).each do |g|
        part = g.get_attribute(ATTR, 'part')
        next unless %w[countertop upstand backsplash].include?(part)

        ox = g.transformation.origin.x.to_mm
        len = g.get_attribute(ATTR, 'len').to_f
        if ox < end_x - 0.5 && ox + len > start_x + 0.5
          g.erase!
          n += 1
        end
      end
      n
    end

    # SLAB Z REFERENCE - the single source of the countertop height: the TOP of
    # the BASE carcass carrying the slab, minus the slab thickness. A converted
    # tower / upper unit must never enter this reference (a tall h=2700 would
    # otherwise lift the slab to 2700 - th and the marble "rides up" with it).
    def slab_reference_h(groups, cfg)
      # Tower / converted-to-tall units must NEVER vote on slab height; otherwise a
      # base unit just converted to tall lifts the marble to ~2700 mm.
      hs = groups.select do |g|
        g.valid? && base_kind?(g) &&
          !g.get_attribute(ATTR, 'converted_from_code') &&
          g.get_attribute(ATTR, 'kind').to_s != 'tall'
      end.map { |g| g.get_attribute(ATTR, 'h').to_f }
      hs.max.to_f.positive? ? hs.max : cfg['base_h'].to_f
    end

    def slab_z(cfg, base_h = nil)
      (base_h || cfg['base_h']).to_f - cfg['top_thk'].to_f
    end

    # Erase worktop pieces overlapping the WORLD-x span [wx0, wx1] wherever they
    # live: directly in `parent_ents` or inside a free worktop wrap (whose pieces
    # sit in the wrap's own frame - converted here). Returns the erased count.
    def strip_top_over_span_world!(parent_ents, wx0, wx1)
      erased = 0
      parent_ents.grep(Sketchup::Group).each do |g|
        next unless g.valid? && g.get_attribute(ATTR, 'worktop_wrap')

        inv = Snap.world_of(g).inverse
        lx0 = (inv * Geom::Point3d.new(Geo.mm(wx0), 0, 0)).x.to_mm
        lx1 = (inv * Geom::Point3d.new(Geo.mm(wx1), 0, 0)).x.to_mm
        erased += erase_top_pieces(g.entities, [lx0, lx1].min, [lx0, lx1].max)
      end
      erased + erase_top_pieces(parent_ents, wx0, wx1)
    end

    # The generator never hangs an upper over a full-height tower: after a base
    # -> tall conversion drop wall/hood units whose own column is the tower's
    # (aligned x, same width - the same match RowEdit uses). Returns erased groups.
    def strip_upper_over_span!(parent_ents, wx0, wx1)
      dropped = []
      parent_ents.grep(Sketchup::Group).each do |g|
        next unless g.valid?

        k = g.get_attribute(ATTR, 'kind').to_s
        next unless %w[wall hood].include?(k)

        gx = g.transformation.origin.x.to_mm
        gw = g.get_attribute(ATTR, 'w').to_f
        dropped << g if gx >= wx0 - 1.0 && (gx + gw) <= wx1 + 1.0
      end
      dropped.each(&:erase!)
      dropped
    end

    # every worktop piece of one generated run made again (all its spans + the second-arm piece of its L corner units)
    def rebuild_run_tops(run, cfg)
      ents = run.entities
      bases = ents.grep(Sketchup::Group).select { |g| base_kind?(g) }.sort_by { |g| g.transformation.origin.x.to_mm }
      bases.each { |b| rebuild_local_countertop(b, cfg) if b.valid? }
      bases.each do |g|
        next unless g.valid?

        spec = Cabinet.spec_from_json(g.get_attribute(ATTR, 'spec'))
        next unless spec[:corner] && spec[:kind] == :base

        x = g.transformation.origin.x.to_mm
        w = g.get_attribute(ATTR, 'w').to_f
        ents.grep(Sketchup::Group).select { |q| q.name.to_s.end_with?('_cornertop') && (q.transformation.origin.x.to_mm - x).between?(-1, w + 1) }.each(&:erase!)
        corner_top(ents, g.name, x, w, spec[:hand], cfg.merge('base_h' => g.get_attribute(ATTR, 'h').to_f))
      end
    end

    def corner_unit?(g)
      spec = Cabinet.spec_from_json(g.get_attribute(ATTR, 'spec'))
      df = Library::BASE[spec[:type].to_s]
      !!(df && df[:corner])
    rescue StandardError
      false
    end

    FREE_TOUCH_TOL = 8.0 # mm - a neighbour must actually abut (small real-world gap/overlap allowed) to count as "connected"

    # Every OTHER base-kind unit in `pool` that shares `unit`'s aligned axis (Snap's own MAX_SIDE_YAW
    # tolerance - the exact same adjacency test Snap.side / Add Left-Right already rely on), with its
    # local x0/x1 expressed in `unit`'s own frame. "Connected" means the same thing here it means
    # everywhere else in the app - no "generated run" metadata involved.
    def aligned_siblings(unit, pool)
      wg = Snap.world_of(unit)
      inv = wg.inverse
      w, d, h = Snap.dims(unit) # Length-typed (.mm) - o.origin below is Length-typed too, never mix that with a plain mm Float
      out = []
      pool.each do |o|
        next if o == unit

        l = inv * Snap.world_of(o)
        ox = l.xaxis.normalize
        yaw = Math.atan2(ox.y, ox.x) * 180.0 / Math::PI
        yaw -= 180.0 * (yaw.positive? ? 1 : -1) if yaw.abs > 90.0
        next if yaw.abs > Snap::MAX_SIDE_YAW

        ow, od, oh = Snap.dims(o)
        same = ox.x >= 0
        org = l.origin
        x0 = same ? org.x : org.x - ow
        ys = same ? [org.y - od, org.y] : [org.y, org.y + od]
        next if [ys.max, 0.0].min - [ys.min, -d].max < 50.mm
        next if [org.z + oh, h].min - [org.z, 0.0].max < 50.mm

        out << { g: o, x0: x0.to_mm, x1: (x0 + ow).to_mm }
      end
      out
    end

    # Walks left and right from `seed` through actually-touching, aligned base units - works whether
    # they share a Kitchen.generate "run" wrapper or not (manually placed adjacent units, Add Left/
    # Right, Replace, a single inserted unit). Stops at a real gap/turn, or at a corner unit (its
    # worktop shape is special-cased, so it is never silently absorbed into a straight slab).
    def connected_run(seed)
      return [] unless seed && base_kind?(seed)
      return [seed] if corner_unit?(seed)

      parent_ents = seed.parent.respond_to?(:entities) ? seed.parent.entities : Sketchup.active_model.entities
      pool = parent_ents.grep(Sketchup::Group).select { |g| g.valid? && g != seed && base_kind?(g) && !corner_unit?(g) }
      chain = [seed]
      loop do
        grew = false
        left = chain.first
        lc = aligned_siblings(left, pool - chain).select { |c| c[:x1].abs <= FREE_TOUCH_TOL }.min_by { |c| c[:x1].abs }
        if lc
          chain.unshift(lc[:g])
          grew = true
        end
        right = chain.last
        rw = right.get_attribute(ATTR, 'w').to_f
        rc = aligned_siblings(right, pool - chain).select { |c| (c[:x0] - rw).abs <= FREE_TOUCH_TOL }.min_by { |c| (c[:x0] - rw).abs }
        if rc
          chain.push(rc[:g])
          grew = true
        end
        break unless grew
      end
      chain
    end

    def new_free_wrap(parent_ents, seed)
      wrap = parent_ents.add_group
      wrap.transformation = seed.transformation
      wrap.name = "#{seed.name}_worktop"
      wrap.set_attribute(ATTR, 'run', true)
      wrap.set_attribute(ATTR, 'worktop_wrap', true)
      wrap
    end

    # An existing free-standing worktop wrapper (from a previous Worktop Apply on this same chain),
    # found by real overlap in `wg`'s frame - reused in place instead of stacking a second slab, the
    # same way rebuild_local_countertop reuses the run group it finds.
    def find_free_wrap(parent_ents, wg, start_x, end_x)
      inv = wg.inverse
      parent_ents.grep(Sketchup::Group).find do |g|
        next false unless g.valid? && g.get_attribute(ATTR, 'worktop_wrap')

        l = inv * Snap.world_of(g)
        next false if l.xaxis.normalize.x < 0.98 # must be (almost) unrotated relative to wg - a real reuse candidate

        ox = l.origin.x.to_mm
        tops = g.entities.grep(Sketchup::Group).select { |t| %w[countertop upstand backsplash plinth].include?(t.get_attribute(ATTR, 'part')) }
        tops.any? do |t|
          tx0 = ox + t.transformation.origin.x.to_mm
          len = t.get_attribute(ATTR, 'len').to_f
          tx0 < end_x - 0.5 && tx0 + len > start_x + 0.5
        end
      end
    end

    # Free-standing counterpart to rebuild_local_countertop: builds (or rebuilds, if one already
    # exists) the worktop for a chain of base units that do NOT necessarily share a "run" wrapper
    # group. Used whenever the selected unit isn't inside a Kitchen.generate run.
    def rebuild_free_worktop(chain, cfg)
      return nil if chain.empty?

      seed = chain.first
      parent_ents = seed.parent.respond_to?(:entities) ? seed.parent.entities : Sketchup.active_model.entities
      wg = Snap.world_of(seed)
      inv = wg.inverse

      # A standalone sink/hob/hob_oven unit (own_top: true - see place_unit) carries its OWN small
      # countertop nested INSIDE its own group, built before it was ever connected to a run. Once the
      # chain is unified into one continuous slab in `wrap`, that old nested piece must be cleared too,
      # or it is left behind as an overlapping ghost duplicate under the new slab.
      chain.each { |g| erase_top_pieces(g.entities, -1_000_000, 1_000_000) }

      if corner_unit?(seed) && chain.size == 1
        spec = Cabinet.spec_from_json(seed.get_attribute(ATTR, 'spec'))
        w = seed.get_attribute(ATTR, 'w').to_f
        wrap = find_free_wrap(parent_ents, wg, 0.0, w) || new_free_wrap(parent_ents, seed)
        erase_top_pieces(wrap.entities, -1_000_000, 1_000_000)
        # a lone L corner unit: the whole L - the slab along the main wall (as on a run) + the piece over the second arm
        ccfg = cfg.merge('base_h' => seed.get_attribute(ATTR, 'h').to_f)
        countertop(wrap.entities, "#{wrap.name}_top_r0", { start: 0.0, end: w, holes: [] }, ccfg, [])
        corner_top(wrap.entities, wrap.name, 0.0, w, spec[:hand], ccfg)
        return wrap
      end

      members = chain.map do |g|
        l = inv * Snap.world_of(g)
        ow = g.get_attribute(ATTR, 'w').to_f
        same = l.xaxis.normalize.x >= 0
        x0 = (same ? l.origin.x.to_mm : l.origin.x.to_mm - ow)
        { g: g, x0: x0, x1: x0 + ow }
      end.sort_by { |mm| mm[:x0] }

      start_x = members.map { |mm| mm[:x0] }.min
      end_x = members.map { |mm| mm[:x1] }.max
      holes = members.filter_map { |mm| cutout_for_at(mm[:g], mm[:x0], cfg) }
      top_h = slab_reference_h(members.map { |mm| mm[:g] }, cfg)
      cuts = members[1..].map { |mm| mm[:x0] }

      wrap = find_free_wrap(parent_ents, wg, start_x, end_x) || new_free_wrap(parent_ents, seed)
      erase_top_pieces(wrap.entities, start_x, end_x)
      countertop(wrap.entities, "#{wrap.name}_top_r#{start_x.round}", { start: start_x, end: end_x, holes: holes }, cfg.merge('base_h' => top_h), cuts)
      wrap
    end

    # Free-standing counterpart to join_plinth_run: one continuous plastic plinth profile across a
    # chain of base units that do NOT necessarily share a "run" wrapper group (manually placed/snapped
    # units, Add Left/Right...). Segments at any non-eligible unit (floor-standing appliance, no
    # plinth) exactly like join_plinth_run, and only joins a segment of 2+ touching eligible units -
    # a lone one simply keeps the standalone board Cabinet#plinth_board already gave it. Reuses the
    # same free wrap group as the worktop (find_free_wrap/new_free_wrap already look for 'plinth'
    # children too), so a chain that also has a worktop gets both in one shared sibling group.
    def rebuild_free_plinth(chain, cfg)
      return nil if chain.empty?

      seed = chain.first
      parent_ents = seed.parent.respond_to?(:entities) ? seed.parent.entities : Sketchup.active_model.entities
      wg = Snap.world_of(seed)
      inv = wg.inverse

      members = chain.map do |g|
        l = inv * Snap.world_of(g)
        ow = g.get_attribute(ATTR, 'w').to_f
        same = l.xaxis.normalize.x >= 0
        x0 = (same ? l.origin.x.to_mm : l.origin.x.to_mm - ow)
        { g: g, x0: x0, x1: x0 + ow }
      end.sort_by { |mm| mm[:x0] }

      groups = []
      cur = []
      members.each do |mm|
        spec = Cabinet.spec_from_json(mm[:g].get_attribute(ATTR, 'spec'))
        eligible = spec[:plinth].to_f > 0
        if eligible && (cur.empty? || (mm[:x0] - cur.last[:x1]).abs < 1.0)
          cur << mm
        else
          groups << cur if cur.size > 1
          cur = eligible ? [mm] : []
        end
      end
      groups << cur if cur.size > 1
      return nil if groups.empty?

      wrap = find_free_wrap(parent_ents, wg, members.first[:x0], members.last[:x1]) || new_free_wrap(parent_ents, seed)
      groups.each do |grp|
        start_x = grp.first[:x0]
        end_x = grp.last[:x1]
        cuts = grp[1..].map { |m| m[:x0] }
        grp.each { |m| m[:g].entities.grep(Sketchup::Group).select { |p| p.get_attribute(ATTR, 'part') == 'plinth' }.each(&:erase!) }
        erase_run_plinth(wrap.entities, start_x, end_x)
        plinth_run(wrap.entities, "#{wrap.name}_plinth_r#{start_x.round}", start_x, end_x, cfg, cuts)
      end
      wrap
    end

    # Like aligned_siblings, but X-position/yaw only - no depth/height overlap requirement. An upper
    # (wall/hood) unit is deliberately at a different Z and depth from the base column under it, yet
    # must still be found and moved with that column on resize. `unit`'s own dims are irrelevant here.
    def x_aligned(unit, pool)
      wg = Snap.world_of(unit)
      inv = wg.inverse
      out = []
      pool.each do |o|
        next if o == unit

        l = inv * Snap.world_of(o)
        ox = l.xaxis.normalize
        yaw = Math.atan2(ox.y, ox.x) * 180.0 / Math::PI
        yaw -= 180.0 * (yaw.positive? ? 1 : -1) if yaw.abs > 90.0
        next if yaw.abs > Snap::MAX_SIDE_YAW

        out << { g: o, x0: l.origin.x.to_mm, w: o.get_attribute(ATTR, 'w').to_f }
      end
      out
    end

    # Resize-aware rebuild: `edit` is the same hash rebuild_cabinet takes (w/h/d/type/notch/style/...).
    # If `edit['w']` actually changes the width, whatever is touching cab's old right edge shifts by
    # the exact delta (no overlap, no gap), and the upper (wall/hood) unit above it resizes/shifts the
    # same way Live Resize always has - Edit Unit/Quick Actions/Replace now share that one behavior
    # instead of just moving cab in place. Any OTHER edits in the same hash (h, d, type, notch...)
    # still apply, in the same single rebuild, to cab itself only. No width change: plain rebuild,
    # untouched. Works whether cab is inside a Kitchen.generate run or was placed/connected manually.
    def cascade_resize(cab, edit, cfg, manage_operation: true, row_scope: 'both')
      perform = -> { RowEdit.apply(cab, edit, cfg, scope: row_scope) }
      return perform.call unless manage_operation

      EGC.safe_op(Sketchup.active_model, 'Edit E.G.C unit') { perform.call }
    end

    # Exposure.refresh can rebuild (erase + recreate) ANY unit in the model whose exposure changed -
    # including a sibling still queued in this function's own loops. Every rebuild_cabinet call made
    # while the cascade is mid-flight skips it (skip_exposure: true); one full refresh runs at the end,
    # once the run is geometrically stable, so no loop here ever iterates a stale/erased reference.
    def cascade_resize_run(cab, edit, run, old_w, new_w, delta, cfg)
      x0 = cab.transformation.origin.x.to_mm
      old_x1 = x0 + old_w
      siblings = run.entities.grep(Sketchup::Group).select { |g| g != cab && g.get_attribute(ATTR, 'spec') }

      # Units that start after this column move with the resized column (bases AND uppers alike).
      siblings.each do |g|
        next unless g.valid?

        gx = g.transformation.origin.x.to_mm
        g.transform!(Geom::Transformation.translation(Geom::Vector3d.new(delta.mm, 0, 0))) if gx >= old_x1 - 1.0
      end

      # The upper unit occupying the same original column follows its new width.
      uppers = siblings.select do |g|
        next false unless g.valid?

        k = g.get_attribute(ATTR, 'kind').to_s
        gx = g.transformation.origin.x.to_mm
        gw = g.get_attribute(ATTR, 'w').to_f
        (k == 'wall' || k == 'hood') && gx < old_x1 - 0.5 && (gx + gw) > x0 + 0.5
      end
      uppers.each do |g|
        next unless g.valid?

        gx = g.transformation.origin.x.to_mm
        next unless (gx - x0).abs < 1.0 && (g.get_attribute(ATTR, 'w').to_f - old_w).abs < 2.0

        rebuild_cabinet(g, { 'w' => new_w }, cfg, manage_operation: false, skip_exposure: true)
      end

      old_len = run.get_attribute(ATTR, 'len').to_f
      new_len = old_len + delta
      parts = run.entities.grep(Sketchup::Group)
      parts.select { |g| g.get_attribute(ATTR, 'part') == 'end_panel' && g.transformation.origin.x.to_mm >= old_len - 1.0 }
           .each { |g| g.transform!(Geom::Transformation.translation([delta.mm, 0, 0])) }
      fascias = parts.select { |g| g.get_attribute(ATTR, 'part') == 'fascia' }
      unless fascias.empty?
        fascias.each(&:erase!)
        fascia(run.entities, "#{run.name}_fascia", new_len, cfg, Config.top_line(cfg))
      end
      run.set_attribute(ATTR, 'len', new_len)
      sync_resized_column(run, x0, old_w, new_w)
      cab = cab.valid? ? cab : run.entities.grep(Sketchup::Group).find { |g| g.valid? && g.get_attribute(ATTR, 'spec') && (g.transformation.origin.x.to_mm - x0).abs < 1.0 && g.get_attribute(ATTR, 'w').to_f == old_w }
      rebuild_cabinet(cab, edit, cfg, manage_operation: false, skip_exposure: true) if cab
      Exposure.refresh(cfg, Sketchup.active_model, own_op: false)
    end

    # Manually placed / connected units: no run wrapper, no stored plan, no run-level end panels or
    # fascia to move - just the cabinets themselves (found by real adjacency, same as connected_run)
    # and whatever worktop already covers them.
    def cascade_resize_free(cab, edit, old_w, new_w, delta, cfg)
      parent_ents = cab.parent.respond_to?(:entities) ? cab.parent.entities : Sketchup.active_model.entities
      pool = parent_ents.grep(Sketchup::Group).select { |g| g.valid? && g != cab && g.get_attribute(ATTR, 'spec') }
      candidates = x_aligned(cab, pool)

      candidates.select { |c| c[:x0] >= old_w - 1.0 }.each do |c|
        Snap.move_world(c[:g], Geom::Transformation.translation(Snap.scaled(Snap.world_of(cab).xaxis, delta.mm)))
      end

      upper = candidates.find do |c|
        k = c[:g].get_attribute(ATTR, 'kind').to_s
        (k == 'wall' || k == 'hood') && c[:x0].abs < 1.0 && (c[:w] - old_w).abs < 2.0
      end
      rebuild_cabinet(upper[:g], { 'w' => new_w }, cfg, manage_operation: false, skip_exposure: true) if upper && upper[:g].valid?

      rebuild_cabinet(cab, edit, cfg, manage_operation: false, skip_exposure: true) if cab.valid?
      Exposure.refresh(cfg, Sketchup.active_model, own_op: false)
    end
  end
end
