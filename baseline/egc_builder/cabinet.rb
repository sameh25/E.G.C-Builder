# frozen_string_literal: true

require 'json'

module EGC
  # Unit type library: type name -> definition (cells are listed bottom -> top)
  module Library
    BASE = {
      'doors'        => { cells: [{ t: :doors, shelves: 1 }] },
      'drawers2'     => { cells: [{ t: :drawers, n: 2 }] },
      'drawers3'     => { cells: [{ t: :drawers, n: 3 }] },
      'drawers4'     => { cells: [{ t: :drawers, n: 4 }] },
      'drawer_doors' => { cells: [{ t: :doors, shelves: 1 }, { t: :drawers, n: 1, h: 200 }] },
      'sink'         => { cells: [{ t: :doors, shelves: 0 }], cutout: :sink },
      'hob'          => { cells: [{ t: :drawers, n: 3 }], cutout: :hob },
      # HOB + OVEN in ONE base cabinet: built exactly like the oven unit (drawer below, oven above) with the hob in the worktop over it.
      'hob_oven'     => { cells: [{ t: :vent }, { t: :appliance, app: 'oven', h: 600 }], cutout: :hob, dev2: 'HOB_60' }, # no own oven record: the oven is placed by the same rule, at the SAME height as in the 'oven' unit
      'oven'         => { cells: [{ t: :vent }, { t: :appliance, app: 'oven', h: 600 }] }, # under the oven: a FIXED panel with a ventilation grille (no drawer)
      # built-in appliances: cabinet with a door front hiding the machine
      'washer_bi'     => { cells: [{ t: :appliance, app: 'washer', front: true }], floor: true },
      'dishwasher_bi' => { cells: [{ t: :appliance, app: 'dishwasher', front: true }], floor: true },
      'open'         => { cells: [{ t: :open, shelves: 2 }] },
      'sink_drawer'  => { cells: [{ t: :drawers, n: 2, u: true }], cutout: :sink }, # two deep U-shaped drawers: the box is cut out around the waste and trap and stays below the bowl
      'pots'         => { cells: [{ t: :drawers, ratio: [2, 1, 1] }] },
      'blind_corner' => { cells: [{ t: :doors, shelves: 1, blind: 300 }] },
      'corner_l'     => { cells: [{ t: :doors, shelves: 1 }], corner: true }
    }.freeze

    # free-standing appliances: visible machine in its own slot (no carcass, no door)
    SLOT = {
      'washer'     => { app: 'washer', under: true, d: 0.97 },
      'dishwasher' => { app: 'dishwasher', under: true, d: 0.97 },
      'fridge'     => { app: 'fridge', h: 1800, d: 1.08, tall: true }
    }.freeze

    TALL = {
      # REFRIGERATOR OPEN HOUSING: real left / right sides + header around a separate, visible refrigerator (no front, no back board, stands on the floor).
      'fridge_open' => { cells: [{ t: :appliance, app: 'fridge', open: true }], flags: { no_back: true, no_bottom: true, no_plinth: true }, dev: 'FRIDGE_TALL' },
      'fridge_empty' => { cells: [{ t: :appliance, app: 'fridge', open: true, empty: true }], flags: { no_back: true, no_bottom: true, no_plinth: true }, dev: 'FRIDGE_TALL' }, # the housing alone: the client brings the refrigerator
      'fridge_bi'  => { cells: [{ t: :appliance, app: 'fridge', h: 1780, front: true }, { t: :doors, shelves: 1 }] },
      'pantry'     => { cells: [{ t: :doors, h: 1200, shelves: 3 }, { t: :doors, shelves: 4 }] },
      'oven_tower' => { cells: [{ t: :drawers, n: 1, h: 500, all_skip: true }, { t: :appliance, app: 'oven', h: 600 },
                                { t: :appliance, app: 'microwave', h: 400 }, { t: :doors, shelves: 2 }] },
      # built-in appliance housings (real carcass around the machine)
      'oven_tall' => { cells: [{ t: :drawers, n: 1, h: 350, all_skip: true }, { t: :appliance, app: 'oven', h: 600 }, { t: :doors, shelves: 2 }] },
      'microwave_tower' => { cells: [{ t: :doors, shelves: 1, h: 700 }, { t: :appliance, app: 'microwave', h: 400 }, { t: :doors, shelves: 2 }] }
    }.freeze

    WALL = {
      'doors' => { cells: [{ t: :doors, shelves: 1 }] },
      'glass' => { cells: [{ t: :doors, shelves: 1, glass: true }] },
      'flap'  => { cells: [{ t: :flap, shelves: 1 }] },
      'open'  => { cells: [{ t: :open, shelves: 1 }] },
      'blind' => { cells: [{ t: :doors, shelves: 1, blind: 200 }] },
      'corner_w' => { cells: [{ t: :doors, shelves: 1 }], corner: true } # L-shaped corner WALL unit (built as type corner_l)
    }.freeze

    module_function

    def base_type?(t)
      BASE.key?(t)
    end

    def tall_type?(t)
      TALL.key?(t)
    end

    def slot_type?(t)
      SLOT.key?(t)
    end

    def all_types
      { 'base' => BASE.keys, 'tall' => TALL.keys, 'slot' => SLOT.keys, 'wall' => WALL.keys + ['hood'] }
    end
  end

  class Cabinet
    ATTR = 'egc'

    # spec: :name :kind(:base/:wall/:tall/:hood) :type :w :h :d :cells :plinth :led_off :cutout
    def self.build(parent, spec, cfg)
      new(spec, cfg).build(parent)
    end

    def self.symbolize_cells(list)
      (list || []).map do |c|
        c = c.dup
        c[:t] = c[:t].to_sym if c[:t]
        c[:cols] = symbolize_cells(c[:cols]) if c[:cols]
        c
      end
    end

    # Cells coming from the dialog (string keys, strings for numbers) -> engine cells
    def self.normalize_cells(list)
      Array(list).map do |raw|
        c = raw.each_with_object({}) { |(k, v), o| o[k.to_sym] = v }
        t = c[:t].to_s
        t = 'doors' if t.empty?
        out = { t: t.to_sym }
        h = c[:h].to_f
        out[:h] = h if h > 0
        out[:n] = c[:n].to_i if c[:n].to_i > 0
        out[:shelves] = c[:shelves].to_i if c.key?(:shelves) && c[:shelves].to_s != ''
        out[:glass] = true if c[:glass] == true || c[:glass].to_s == 'true'
        out[:ratio] = c[:ratio].map(&:to_f) if c[:ratio].is_a?(Array) && c[:ratio].size > 1
        out[:insert] = true if c[:insert] == true || c[:insert].to_s == 'true'
        out[:style] = c[:style].to_sym if c[:style].to_s == 'under'
        out[:u] = true if c[:u] == true || c[:u].to_s == 'true'
        if out[:t] == :appliance # Internal Organizer: appliance zone (oven / microwave / coffee / warming drawer ...)
          out[:app] = (c[:app].to_s.empty? ? 'oven' : c[:app].to_s)
          out[:front] = true if c[:front] == true || c[:front].to_s == 'true'
        end
        if out[:t] == :cols || c[:cols].is_a?(Array)
          out[:t] = :cols
          out[:cols] = normalize_cells(c[:cols]).map { |cc| cc.delete(:h); cc[:w] = 0 unless cc[:w]; cc }
          Array(c[:cols]).each_with_index do |rc, i|
            w = (rc['w'] || rc[:w]).to_f
            out[:cols][i][:w] = w if w > 0
          end
        end
        out
      end
    end

    # default catalog device per appliance zone type (generic nominal profiles; manufacturer data stays unconfirmed)
    ZONE_DEVICE = { 'oven' => 'OVEN_60', 'microwave' => 'MICRO_38', 'coffee' => 'COFFEE_45', 'warming' => 'WARMING_DRAWER' }.freeze

    # up to two distinct appliance zones -> [device_id, device_id2]
    def self.device_ids_for_cells(cells)
      apps = Array(cells).select { |cc| cc[:t] == :appliance }.map { |cc| cc[:app].to_s }.uniq
      [ZONE_DEVICE[apps[0]], ZONE_DEVICE[apps[1]]]
    end

    # Internal Organizer validation: refuses layouts that cannot be built (overlapping shelves, negative / too small cells, appliance that
    # does not fit, columns wider than the unit). Raises ORGANIZER_INVALID with a readable reason; nothing is built.
    def self.check_cells!(spec, cfg)
      t = cfg['thk'].to_f
      cells = Array(spec[:cells])
      raise 'ORGANIZER_INVALID: the unit has no internal zone.' if cells.empty?

      hc = spec[:h].to_f - spec[:plinth].to_f - (spec[:kind] == :base ? cfg['top_thk'].to_f : 0.0)
      explicit = cells.map { |cc| cc[:t] == :appliance && !cc[:h] ? ((Catalog.device(ZONE_DEVICE[cc[:app].to_s]) || { h: 0 })[:h].to_f + 4) : cc[:h] }.compact.map(&:to_f)
      if cells.none? { |cc| cc[:h].nil? && cc[:t] != :appliance } && explicit.sum + (cells.size - 1) * t > hc - 2 * t + 0.5
        raise "ORGANIZER_INVALID: the zone heights (#{explicit.sum.round} mm + #{cells.size - 1} divider(s)) exceed the #{(hc - 2 * t).round} mm available inside the unit."
      end
      laid = TallStack.layout(spec.merge(cells: cells), cfg)
      laid.each_with_index do |cell, i|
        label = "zone #{i + 1} (#{cell[:t]})"
        raise "ORGANIZER_INVALID: #{label} has no usable height (#{cell[:h].round} mm). Reduce the other zones or the number of dividers." if cell[:h].to_f < 60.0
        if cell[:t] == :appliance
          dv = Catalog.device(ZONE_DEVICE[cell[:app].to_s])
          raise "ORGANIZER_INVALID: #{label} is #{cell[:h].round} mm high but the #{cell[:app]} needs #{(dv[:h] + 4).round} mm." if dv && cell[:h].to_f < dv[:h] + 3.9
        end
        k = cell[:shelves].to_i
        if k.positive? && %i[doors glass open flap].include?(cell[:t])
          sp = (cell[:h].to_f - k * t) / (k + 1.0)
          raise "ORGANIZER_INVALID: #{label}: #{k} shelf/shelves leave only #{sp.round} mm between boards (minimum 60 mm)." if sp < 60.0
        end
        if cell[:t] == :cols
          cw = Array(cell[:cols])
          inner = spec[:w].to_f - 2 * t
          fixed = Num.sum(cw) { |cc| cc[:w].to_f }
          nd = [cw.size - 1, 0].max
          raise "ORGANIZER_INVALID: #{label}: the fixed column widths (#{fixed.round} mm) do not fit the #{(inner - nd * t).round} mm available." if fixed > inner - nd * t + 0.01
          free = cw.count { |cc| cc[:w].to_f <= 0 }
          raise "ORGANIZER_INVALID: #{label}: a column would be narrower than 80 mm." if free.positive? && (inner - nd * t - fixed) / free < 80.0
        end
      end
      true
    end

    def self.spec_from_json(str)
      raw = JSON.parse(str, symbolize_names: true)
      raw[:kind] = raw[:kind].to_sym if raw[:kind]
      raw[:cells] = symbolize_cells(raw[:cells])
      raw
    end

    def initialize(spec, cfg)
      @s = spec
      # a unit may carry its OWN handle type (spec[:handle], set from the unit panel): it replaces the project setting for this unit only
      @c = spec[:handle].to_s.empty? ? cfg : cfg.merge('handle' => spec[:handle].to_s)
      @c = @c.merge('sink_model' => spec[:sink_model].to_s) unless spec[:sink_model].to_s.empty? # ... and its OWN sink kind (unit panel)
      @c = @c.merge('hob_model' => spec[:hob_model].to_s) unless spec[:hob_model].to_s.empty?    # ... and its OWN hob kind
      # ... and its OWN handle-free profile sizes (unit panel; checked by Kitchen.gola_override before they are stored)
      @c = @c.merge(spec[:gola].to_h { |k, v| ["gola_#{k}", v.to_f] }) if spec[:gola].is_a?(Hash) && !spec[:gola].empty?
      # ... and its OWN materials (front / carcass swatch codes) - the other units keep the kitchen's
      @c = @c.merge('unit_mats' => spec[:mats].to_h { |k, v| [k.to_s, v.to_s] }) if spec[:mats].is_a?(Hash) && !spec[:mats].empty?
    end

    def build(parent)
      s = @s
      @drawer_no = 0
      c = @c
      @t   = c['thk'].to_f
      @back_thk = c['back_thk'].to_f
      @back_groove = Config.back_groove_spec(c)
      # Internal components begin at the room-facing edge of the inset back.
      @bk  = if s[:no_back]
               0.0
             elsif @back_groove
               @back_groove[:offset] + @back_thk + @back_groove[:clearance].to_f
             else
               @back_thk
             end
      @ft  = c['front_thk'].to_f
      @gap = c['gap'].to_f
      @w   = s[:w].to_f
      @dd  = s[:d].to_f
      @cd  = s[:housing].to_s == 'fridge' ? @dd : @dd - @ft # door-less refrigerator housing: gables run the full depth, flush with the neighbouring door faces
      @kind = s[:kind]
      @name = s[:name]
      @plinth = s[:plinth].to_f
      @hc = s[:h].to_f - @plinth - (@kind == :base ? c['top_thk'].to_f : 0.0)
      @z0 = @plinth
      @hw = Hash.new(0)
      @g = parent.add_group
      @e = @g.entities
      @g.name = @name
      @code = s[:code] || derive_code(@name)
      Panel.reset_code(@name)
      Panel.reset_code(@code)

      @cur = nil
      carcass
      if @s[:mech]
        mech_build(@s[:mech].to_s)
      else
        cells
        extras
      end
      plinth_board
      top_strip if @s[:top_strip].to_f.positive?
      fixtures
      finish
      @g
    end

    # FINISH STRIP ON TOP of a unit placed on its own (Kitchen.place_unit, cfg 'unit_fascia'): a finish-board strip standing on the
    # carcass top, its face flush with the door faces. Longer than the finish board allows -> equal pieces (same rule as the run fascia).
    def top_strip
      h = @s[:top_strip].to_f
      th = @c['fascia_thk'].to_f.positive? ? @c['fascia_thk'].to_f : @ft
      mat = (@c['ext_mat'] || 'front').to_s
      stock = Config.stock_dimensions(@c, mat, @ft)
      max_len = stock ? stock[0].to_f - 2 * @c['trim'].to_f - 20 : @w
      n = [(@w / max_len).ceil, 1].max
      seg = @w / n
      n.times do |i|
        pn(n > 1 ? "top_strip#{i + 1}" : 'top_strip', i * seg, @cd + @ft - th, @z0 + @hc, seg, th, h, mat, grain: :x, eb: [2, 0], eb_t: 2.0,
           notes: "finish strip #{h.round} mm on top of the unit (setting: finish strip on units placed one by one)")
      end
    end

    SINK_TYPES = %w[sink sink_drawer].freeze
    SINK_MIN_W = 500.0
    SINK_RAIL_H = 60.0 # the two upright strips the worktop rests on in a sink unit: kept low so the bowl and its fittings stay clear
    SINK_DOUBLE_W = 800.0

    # Sink / hob units come complete: worktop opening (+ the slab itself for a standalone unit) AND the real fixture
    # positioned in it. The fixture is rebuilt from its parametric builder at whatever width the unit has (single or
    # double bowl) - it is never scaled - and the unit refuses a width the sink cannot fit.
    def fixtures
      return unless @kind == :base

      type = @s[:type].to_s
      kind = SINK_TYPES.include?(type) ? :sink : (%w[hob hob_oven].include?(type) ? :hob : nil)
      return unless kind

      if kind == :sink && @w < SINK_MIN_W
        raise "Sink unit needs at least #{SINK_MIN_W.round} mm width (got #{@w.round}). | وحدة الحوض تحتاج عرض #{SINK_MIN_W.round} مم على الأقل."
      end

      r = Kitchen.cutout_rect(kind, 0, @w, @c)
      top_z = @s[:h].to_f
      if @s[:own_top]
        Kitchen.slab(@e, "#{@name}_top", 0, @w, [r], @c.merge('base_h' => top_z), {}, false)
      end
      if kind == :sink
        ov = Kitchen.sink_overall_rect(0, @w, @c) # a product sink keeps its published overall size
        sx, sd, sw, sdd = ov || [r[0] - 12, r[1] - 12, r[2] + 24, r[3] + 24]
        g = Appliances.place(@e, "#{@name}_sink", 'sink', sx, sd, top_z, sw, sdd, 200, @c.merge('sink_flange' => (ov ? (sw - r[2]) / 2.0 + 1.0 : nil), 'sink_model' => Kitchen.sink_model(@w, @c), 'sink_double' => Kitchen.sink_model(@w, @c) == 'double'))
        if g
          g.set_attribute(ATTR, 'dev_id', @w >= SINK_DOUBLE_W ? 'SINK_800' : 'SINK_600')
          g.set_attribute(ATTR, 'sink_model', Kitchen.sink_model(@w, @c))
          g.set_attribute(ATTR, 'dev_src', 'default')
          op = { 'w' => r[2].round(1), 'h' => 0, 'd' => r[3].round(1), 'cutout' => true }
          op['shape'] = 'round' if r[7] == 'round'
          if (pr = Kitchen.sink_profile(Kitchen.sink_model(@w, @c)))
            op.merge!('rect' => r[0, 4].map { |q| q.round(1) }, 'status' => r[6], 'product' => pr[:product], 'overall' => pr[:overall])
            g.set_attribute(ATTR, 'sink_product', pr[:product])
            g.set_attribute(ATTR, 'cutout_status', r[6])
            g.set_attribute(ATTR, 'sink_accessories', JSON.generate(pr[:accessories]))
            @g.set_attribute(ATTR, 'sink_checks', JSON.generate(Kitchen.sink_report(@w, @s[:type], @c)))
          end
          g.set_attribute(ATTR, 'opening', JSON.generate(op))
        end
      else
        hdv = device_for('hob')
        hk = (hdv || {})[:kind] || 'hob'
        hm = Kitchen.hob_model(@w, @c)
        hpr = Kitchen::HOB_MODELS[hm] # a chosen hob kind: its own body size and look; 'auto' = the 60 cm hob of the unit's appliance
        bw, bd = hpr ? hpr[:body] : [590.0, 520.0]
        hk = hpr[:kind] if hpr
        g = Appliances.place(@e, "#{@name}_hob", hk, r[0] - (bw - r[2]) / 2.0, r[1] - (bd - r[3]) / 2.0, top_z - 46, bw, bd, 50, hpr ? @c.merge('hob_style' => hpr[:style]) : @c)
        if g
          g.set_attribute(ATTR, 'dev_id', hpr ? "HOB_M_#{hm.upcase}" : (hdv ? hdv[:id] : 'HOB_60'))
          g.set_attribute(ATTR, 'dev_src', hpr || hdv ? 'spec' : 'default')
          g.set_attribute(ATTR, 'hob_model', hm)
          g.set_attribute(ATTR, 'cutout_note', r[5].to_s) if r[5]
          g.set_attribute(ATTR, 'opening', JSON.generate({ 'w' => r[2].round(1), 'h' => 0, 'd' => r[3].round(1), 'cutout' => true }))
        end
      end
    end

    private

    def code
      @code
    end

    # Shelves / dividers added with the Space tool: they live in the spec (spec[:extras]), so rebuilds, copies, saves and the cut list
    # always agree. Positions are in the unit's own frame (mm); an extra that no longer fits inside the carcass is skipped.
    def extras
      Array(@s[:extras]).each do |e|
        t = (e[:type] || e["type"]).to_s
        depth = @cd - @bk - 20
        case t
        when "shelf"
          x0 = [e[:x0].to_f, ix0].max
          x1 = [e[:x1].to_f, ix1].min
          z = e[:z].to_f
          next if x1 - x0 < 60 || z < @z0 + @t || z + @t > @z0 + @hc - @t

          pn("shelf", x0 + 1, @bk, z, x1 - x0 - 2, depth, @t, "carcass", grain: :x, eb: [1, 0])
          @hw["shelf_pin"] += 4
        when "divider"
          x = e[:x].to_f
          z0 = [e[:z0].to_f, @z0 + @t].max
          z1 = [e[:z1].to_f, @z0 + @hc - @t].min
          next if z1 - z0 < 60 || x < ix0 || x + @t > ix1

          pn("divider", x, @bk, z0, @t, depth, z1 - z0, "carcass", grain: :z, eb: [1, 0])
        when "rail" # hanging rail across the space (oval 30 x 15, cut to length; two end supports)
          x0 = [e[:x0].to_f, ix0].max
          x1 = [e[:x1].to_f, ix1].min
          z = e[:z].to_f
          next if x1 - x0 < 200 || z < @z0 + @t || z + 30 > @z0 + @hc - @t

          pn('hanging_rail', x0 + 2, @bk + depth / 2.0 - 7.5, z, x1 - x0 - 4, 15, 30, 'profile', role: 'hw', notes: "hanging rail, cut to #{(x1 - x0 - 4).round} mm")
          @hw['hanging_rail'] += 1
        when "fill" # drawers or doors built into exactly that space (same builders as a column of the unit)
          fill_extra(e)
        end
      end
    end

    # builder code of a generated unit (<run letter><position>[W<tier>|over]) read from its group name; used where units of one column are matched
    def self.legacy_code(name)
      m = name.to_s.match(/\A([A-Z])_(\d+)_/)
      m ? "#{m[1]}#{m[2]}#{name[/_(W\d|over)\z/, 1]}" : name.to_s
    end

    def derive_code(name)
      m = name.match(/\A([A-Z])_(\d+)_/)
      return name unless m

      "#{m[1]}#{m[2]}#{name[/_(W\d|over)\z/, 1]}"
    end

    # ---- column / corner notch ---------------------------------------------------------------
    # spec[:notch] = { side: 'l'|'r', w:, d: } removes a rear corner of the carcass (a pillar or
    # pipe box behind the unit): horizontal boards become L-shaped (cut list keeps the bounding
    # rectangle + an "L-cut" note), the notched side board is shortened, the back is narrowed.
    NOTCH_H = %w[bottom top divider shelf top_rail_b].freeze

    def notch
      return @notch if defined?(@notch)

      n = @s[:notch]
      @notch = nil
      return unless n.is_a?(Hash) && n[:w].to_f > 0 && n[:d].to_f > 0
      return if @s[:mech] || !%i[base wall tall].include?(@kind)

      nw = [n[:w].to_f, @w - 2 * @t - 100].min
      nd = [[n[:d].to_f, @bk + 1].max, @cd - 150].min
      side = n[:side].to_s == 'r' ? 'r' : 'l'
      @notch = { side: side, w: nw, d: nd, x0: side == 'l' ? 0.0 : @w - nw, x1: side == 'l' ? nw : @w }
    end

    def notch_hits?(x0, x1)
      notch && x1 > notch[:x0] + 0.5 && x0 < notch[:x1] - 0.5
    end

    # Space tool: drawers / doors in one free space of the carcass. The space is given by the boards around it (unit frame, mm); the
    # fronts cover half of the boards they meet and the full carcass edge where the space reaches it - like the cells of the unit.
    def fill_extra(e)
      x0 = [e[:x0].to_f, @t].max
      x1 = [e[:x1].to_f, @w - @t].min
      z0 = [e[:z0].to_f, @z0 + @t].max
      z1 = [e[:z1].to_f, @z0 + @hc - @t].min
      return if x1 - x0 < 150 || z1 - z0 < 100

      n = e[:n].to_i
      cell = e[:cell].to_s == 'drawers' ? { t: :drawers, n: n.clamp(1, 6) } : { t: :doors, shelves: 0 }
      cell[:n] = n if cell[:t] == :doors && n.between?(1, 2)
      cell[:ratio] = Array(e[:ratio]).map(&:to_f) if cell[:t] == :drawers && Array(e[:ratio]).size.positive? # front heights from the bottom up
      @fx0 = (x0 - @t).abs < 1.0 ? 0.0 : x0 - @t / 2.0
      fb = (x1 - (@w - @t)).abs < 1.0 ? @w : x1 + @t / 2.0
      @fw = fb - @fx0
      @sx0 = x0
      @sx1 = x1
      fz0 = (z0 - (@z0 + @t)).abs < 1.0 ? @z0 : z0 - @t / 2.0
      fz1 = (z1 - (@z0 + @hc - @t)).abs < 1.0 ? @z0 + @hc - front_drop : z1 + @t / 2.0
      do_cell(cell.merge(z0: z0, h: z1 - z0), fz0 + @gap / 2.0, fz1 - fz0 - @gap)
    ensure
      @fx0 = @fw = @sx0 = @sx1 = nil
    end

    # build into the carcass itself, whatever moving assembly (door, drawer) is being filled at the moment
    def on_carcass
      old = @cur
      @cur = nil
      yield
    ensure
      @cur = old
    end

    def pn(part, x, d, z, sx, sd, sz, mat, o = {})
      if part == 'filler' && @s[:mech] && (bs = @s[:blind_strip].to_f).positive? && sx > bs + 1
        # BLIND CORNER with a unit in front of its blind lane: no fixed cover panel there (it would be hidden and wasted) - only the strip
        # next to the door stays, the part still seen between the door and the fronts of the unit in front
        x += sx - bs unless x + sx / 2.0 > @w / 2.0
        sx = bs
        o = o.merge(notes: 'blind corner: a unit stands in front of the blind lane - fixed cover panel left out, visible strip only')
      end
      n = notch
      if n && NOTCH_H.include?(part) && notch_hits?(x, x + sx) && d < n[:d]
        cx0 = [n[:x0] - x, 0.0].max
        cx1 = [n[:x1] - x, sx].min
        cd = [n[:d] - d, sd].min
        note = "L-cut #{n[:w].round}x#{(n[:d]).round} (#{n[:side] == 'l' ? 'left' : 'right'} rear)"
        o = o.merge(notes: [o[:notes], note].compact.join(' '))
        if cd >= sd - 0.5 # the cut swallows the whole depth: the board is simply narrower
          if cx0 <= 0.5
            x += cx1
            sx -= cx1
          else
            sx = cx0
          end
        else
          o = o.merge(solid: lambda { |ents|
            pts = [[0, 0], [cx0, 0], [cx0, cd], [cx1, cd], [cx1, 0], [sx, 0], [sx, sd], [0, sd]]
            pts = pts.each_with_index.reject { |p, i| p == pts[i - 1] }.map(&:first)
            f = ents.add_face(pts.map { |px, pd| Geo.p3(px, pd, 0) })
            f&.pushpull((f.normal.z >= 0 ? 1 : -1) * Geo.mm(sz)) if f
          })
        end
      end
      Panel.add(@cur || @e, @name, part, x, d, z, sx, sd, sz, mat, @c, o.merge(code: code))
    end

    # Back-board rebate, cut into the cabinet's inner side face. This is model geometry only;
    # manufacturing coordinates are exported separately and never inferred from hinge profiles.
    def back_groove_side_solid(side, thickness, depth, height, spec)
      lambda do |ents|
        pts = self.class.back_groove_outline(side, thickness, depth, spec)
        face = ents.add_face(pts.map { |px, pd| Geo.p3(px, pd, 0) })
        raise ArgumentError, 'BACK_GROOVE_ERROR: could not form cabinet side profile' unless face
        face.pushpull((face.normal.z >= 0 ? 1 : -1) * Geo.mm(height))
      end
    end

    def self.back_groove_outline(side, thickness, depth, spec)
      off, gw, gd = spec.values_at(:offset, :width, :depth)
      raise ArgumentError, 'BACK_GROOVE_ERROR: groove depth must be less than carcass thickness' unless gd.to_f.positive? && gd.to_f < thickness.to_f
      raise ArgumentError, 'BACK_GROOVE_ERROR: groove does not fit within the cabinet side depth' unless off.to_f >= 0 && off.to_f + gw.to_f < depth.to_f

      return [[0, 0], [thickness, 0], [thickness, depth], [0, depth], [0, off + gw], [gd, off + gw], [gd, off], [0, off]] if side.to_sym == :right

      [[0, 0], [thickness, 0], [thickness, off], [thickness - gd, off], [thickness - gd, off + gw],
       [thickness, off + gw], [thickness, depth], [0, depth]]
    end

    def back_groove_cnc_data
      { 'type' => 'back_panel_rebate', 'depth' => @back_groove[:depth], 'offset' => @back_groove[:offset],
        'width' => @back_groove[:width], 'reference' => 'rear_edge', 'status' => 'MODELED; CNC ORIENTATION REQUIRES VALIDATION' }
    end

    def carcass
      t = @t
      w = @w
      cdp = @cd - @bk
      z0 = @z0
      hc = @hc
      n = notch
      ndl = n && n[:side] == 'l' ? n[:d] : @bk
      ndr = n && n[:side] == 'r' ? n[:d] : @bk
      # Wall units: the bottom runs UNDER the sides (full width), so a row of units shows one flat underside with no 36 mm of side end-grain
      # between the units and the LED groove can run straight through every joint. The sides therefore start on top of the bottom.
      lift = under_sides? ? t : 0.0
      groove_sides = @back_groove && !n && !@s[:no_back] && @s[:back_open] != true
      left_opts = { grain: :z, eb: [1, 0], bore: pin_holes(@cd - (groove_sides ? 0 : ndl), hc - lift, lift) + joint_bores(@cd - (groove_sides ? 0 : ndl), hc - lift, lift, groove_sides ? @bk : 0.0), notes: (ndl > @bk ? 'shortened for column' : nil) }
      right_opts = { grain: :z, eb: [1, 0], bore: pin_holes(@cd - (groove_sides ? 0 : ndr), hc - lift, lift) + joint_bores(@cd - (groove_sides ? 0 : ndr), hc - lift, lift, groove_sides ? @bk : 0.0), notes: (ndr > @bk ? 'shortened for column' : nil) }
      if groove_sides
        left_opts[:solid] = back_groove_side_solid(:left, t, @cd, hc - lift, @back_groove)
        left_opts[:back_groove] = back_groove_cnc_data
        right_opts[:solid] = back_groove_side_solid(:right, t, @cd, hc - lift, @back_groove)
        right_opts[:back_groove] = back_groove_cnc_data
      end
      pn('side_l', 0, groove_sides ? 0 : ndl, z0 + lift, t, @cd - (groove_sides ? 0 : ndl), hc - lift, side_mat(:l), left_opts)
      pn('side_r', w - t, groove_sides ? 0 : ndr, z0 + lift, t, @cd - (groove_sides ? 0 : ndr), hc - lift, side_mat(:r), right_opts)
      side_finish_panels(groove_sides ? 0 : ndl, groove_sides ? 0 : ndr, z0 + lift, hc - lift)
      bx0 = groove_sides ? t - @back_groove[:depth] : (n && n[:side] == 'l' ? n[:w] : 0.0)
      back_w = groove_sides ? w - 2 * t + 2 * @back_groove[:depth] : w - (n ? n[:w] : 0.0)
      back_d = groove_sides ? @back_groove[:offset] : 0.0
      pn('back', bx0, back_d, z0, back_w, @back_thk, hc, 'back', grain: :z, eb: [0, 0],
         notes: groove_sides ? "inset groove: depth #{@back_groove[:depth]} mm, offset #{@back_groove[:offset]} mm" : (n ? 'narrowed for column' : nil)) unless @s[:no_back]
      bottom unless @kind == :hood || @s[:mech].to_s == 'DISH_RACK_FLAP' || @s[:no_bottom]
      if @kind == :base
        # the flat front rail the worktop rests on - always there
        sink = SINK_TYPES.include?(@s[:type].to_s)
        grd = @c['handle'].to_s == 'gola' ? gola_dims[:l_d] : 0.0 # handle-free: the front rail stands behind the L profile
        if sink
          # SINK UNIT: the two rails stand UPRIGHT at the very front and back, so no board crosses the sink opening (a flat rail showed inside the bowl)
          pn('top_rail_f', t, @cd - t - grd, z0 + hc - SINK_RAIL_H, w - 2 * t, t, SINK_RAIL_H, 'carcass', grain: :x, eb: [1, 0])
          pn('top_rail_b', t, @bk, z0 + hc - SINK_RAIL_H, w - 2 * t, t, SINK_RAIL_H, 'carcass', grain: :x, eb: [0, 0])
        else
          pn('top_rail_f', t, @cd - 100 - grd, z0 + hc - t, w - 2 * t, 100, t, 'carcass', grain: :x, eb: [1, 0])
        end
        if front_strip?
          # OPTIONAL UPRIGHT FRONT STRIP (its own board in the cut list): it hangs under the flat rail on the carcass front and the door closes onto
          # it, so a door shortened for a dropped worktop edge (top_lip) still has board behind its top edge instead of a gap.
          pn('front_strip', t, @cd - t, z0 + hc - t - front_strip_h, w - 2 * t, t, front_strip_h, 'carcass', grain: :x, eb: [1, 0])
        end
        pn('top_rail_b', t, @bk, z0 + hc - t, w - 2 * t, 100, t, 'carcass', grain: :x, eb: [0, 0]) unless sink
      else
        pn('top', t, @bk, z0 + hc - t, w - 2 * t, cdp, t, (@kind == :wall && hget(@s[:exp], :t).to_s == 'exposed' ? ext_mat : 'carcass'), grain: :x, eb: [1, 0])
      end
      return unless @kind == :wall || @kind == :base || @kind == :tall

      @hw['leg'] += (w > 800 ? 6 : 4) if @plinth > 0
      @hw['plinth_clip'] += (w > 800 ? 6 : 4) if @plinth > 0 # fixes the plastic plinth profile to each leg
      @hw['wall_hanger'] += 2 if @kind == :wall || @kind == :hood
    end

    # System-32 shelf pin holes (inner face): 37 mm from front and back edges, 32 mm pitch
    # ---- exposure (which faces the user can see): user override (spec[:exp]) > automatic detection (spec[:exp_auto]) > default
    # A visible face takes the EXTERNAL finish material (config 'ext_mat', default = the fronts' material); a hidden one stays carcass.
    EXPOSE_DEFAULT = { l: true, r: true, b: true, t: false }.freeze

    def hget(h, k)
      h.is_a?(Hash) ? (h.key?(k.to_sym) ? h[k.to_sym] : h[k.to_s]) : nil   # false must survive (never use ||)
    end

    def exposure(side)
      ov = hget(@s[:exp], side).to_s
      return true if ov == 'exposed'
      return false if ov == 'hidden'

      au = hget(@s[:exp_auto], side)
      au.nil? ? EXPOSE_DEFAULT[side] : au
    end

    # any patch of the underside the user can see (a deeper unit above a shallower one shows its front strip): external finish, groove only when FULLY free
    def under_visible?
      ov = hget(@s[:exp], :b).to_s
      return true if ov == 'exposed'
      return false if ov == 'hidden'

      au = hget(@s[:exp_auto], :bv)
      au.nil? ? exposure(:b) : (au || exposure(:b))
    end

    def ext_mat
      (@c['ext_mat'] || 'front').to_s
    end

    # The carcass side itself is always plain carcass board, at its usual thickness/position: exposure
    # never touches it, so the interior clear width never changes. Kept only for the shortened-for-column
    # note; callers no longer vary the material by exposure.
    def side_mat(side)
      hget(@s[:exp], side).to_s == 'exposed' ? ext_mat : 'carcass' # FINISH: the exposed side itself is cut from the finish board
    end

    # A user-marked exposed side gets a SEPARATE decorative finish panel fixed to the OUTSIDE of the
    # carcass side (real cabinetry practice: a cladding panel glued/screwed on, not a re-finished
    # structural board) - independent per side, adds no thickness to the carcass, changes no internal
    # dimension. Same thickness convention as the run-level end panels (cfg['front_thk']).
    def side_finish_panels(ndl, ndr, zf, hf)
      return unless %i[wall base tall hood].include?(@kind)

      ft = @c['front_thk'].to_f
      return if ft <= 0

      nil # no cladding board any more: the exposed side itself is made of the finish board (see #side_mat)
    end

    def under_sides?
      @kind == :wall && @s[:mech].to_s != 'DISH_RACK_FLAP' && !@s[:no_bottom]
    end

    # Carcass joints on the inner face of a gable: at the centre line of every horizontal board that butts against it (bottom, top / top rails)
    # one connecting-bolt bore (5 mm) 37 mm from the front edge and one 37 mm in front of the back panel, each with an 8 mm dowel 32 mm further in.
    # sd / sh = depth and height of the side board, lift = how far the side starts above the carcass bottom, rear = space taken by the back at the rear.
    JOINT_SETBACK = 37.0
    JOINT_PITCH = 32.0

    def joint_bores(sd, sh, lift, rear)
      return [] unless %i[base wall tall hood].include?(@kind) && sd >= 4 * JOINT_SETBACK + 2 * JOINT_PITCH

      ys = []
      ys << @t / 2.0 if lift.zero? && !(@kind == :hood || @s[:mech].to_s == 'DISH_RACK_FLAP' || @s[:no_bottom]) # wall units: the bottom runs under the sides (edge joint, not a face bore)
      ys << sh - @t / 2.0
      xf = JOINT_SETBACK
      xr = sd - rear - JOINT_SETBACK
      ref = 'inner face; x from front edge, y from bottom'
      ys.flat_map do |y|
        [{ 't' => 'cam bolt', 'x' => xf, 'y' => y.round(1), 'dia' => 5, 'depth' => 12, 'ref' => ref }, { 't' => 'dowel', 'x' => xf + JOINT_PITCH, 'y' => y.round(1), 'dia' => 8, 'depth' => 12, 'ref' => ref },
         { 't' => 'cam bolt', 'x' => xr.round(1), 'y' => y.round(1), 'dia' => 5, 'depth' => 12, 'ref' => ref }, { 't' => 'dowel', 'x' => (xr - JOINT_PITCH).round(1), 'y' => y.round(1), 'dia' => 8, 'depth' => 12, 'ref' => ref }]
      end
    end

    def pin_holes(cdp, hc, shift = 0.0)
      return [] unless @s[:cells].to_a.any? { |c| c[:shelves].to_i > 0 }

      out = []
      y = 96.0 - shift # same absolute pin heights whether or not the side starts on top of the bottom
      while y <= hc - 96
        [37.0, cdp - 37.0].each { |x| out << { 't' => 'shelf pin', 'x' => x.round(1), 'y' => y.round(1), 'dia' => 5, 'depth' => 12, 'ref' => 'inner face; x from front edge, y from bottom' } }
        y += 32
      end
      out
    end

    def bottom
      t = @t
      # HANDLE-FREE WALL UNIT: the grip profile (settings: gola_w_d x gola_w_h) is let into the FRONT EDGE of the bottom panel, behind the door;
      # the panel is that much shallower, so the unit keeps its height and depth and the door covers the profile.
      wg = @kind == :wall && @c['handle'].to_s == 'gola' && !@s[:corner] && !@s[:mech] ? gola_dims[:w_d] : 0.0
      fr = @cd - wg
      cdp = fr - @bk
      off = @s[:led_off]
      full = @kind == :wall                      # wall units: full-width bottom under the sides (see #carcass)
      x0 = full ? 0.0 : t
      width = full ? @w : @w - 2 * t
      mat = @kind == :wall && hget(@s[:exp], :b).to_s == 'exposed' ? ext_mat : 'carcass'   # any visible patch of an upper unit's underside: external finish (a deeper tier 2 shows a front strip over tier 1)
      ends = full ? [exposure(:l), exposure(:r)].count(true) : 0   # exposed short edges need banding
      if off && @kind == :wall && @c['led'] && !notch_hits?(x0, x0 + width)   # E.G.C standard: EVERY upper tier is grooved (tier 1 at 35, tier 2 at 450 from the back), visible or not
        lw = @c['led_w'].to_f
        ld = @c['led_depth'].to_f
        off = [off.to_f, @bk + 1].max
        off = fr - lw - 12 if off + lw > fr - 12   # shallow unit (e.g. 350 mm tier): keep the LED groove inside the panel, never past its front edge
        solid = lambda do |ents|
          pts = [[@bk, 0], [off, 0], [off, ld], [off + lw, ld], [off + lw, 0], [fr, 0], [fr, t], [@bk, t]]
          # profile in (d,z) plane at x = 0 (panel-local d starts at @bk), extruded along +X
          f = ents.add_face(pts.map { |d, z| Geo.p3(0, d - @bk, z) })
          if f
            f.pushpull((f.normal.x >= 0 ? 1 : -1) * Geo.mm(width))
            # the recess walls / ceiling get a pale tint so the real 10x10 channel can be SEEN in the shaded model (visual aid only: the groove is the geometry)
            tint = Geo.material('led_channel', @c)
            ents.grep(Sketchup::Face).each do |ff|
              zs = ff.vertices.map { |v| v.position.z.to_mm }
              ff.material = tint if zs.max > 0.01 && zs.max <= ld + 0.01
            end
          end
        end
        pn('bottom', x0, @bk, @z0, width, cdp, t, mat, grain: :x, eb: [1, ends], solid: solid,
                                                       groove: "#{lw.round}x#{ld.round}@#{off.round}",
                                                       groove_geo: { 'axis' => 'len', 'off' => (off - @bk).round(2), 'w' => lw, 'd' => ld, 'from' => 'panel back edge', 'ref' => 'wid0', 'face' => 'underside', 'route' => 'through' })
        @hw['led_mm'] += width
        @led = { 'off' => off.round(2), 'lw' => lw, 'ld' => ld, 'w' => @w, 'x0' => x0, 'width' => width }
      else
        pn('bottom', x0, @bk, @z0, width, cdp, t, mat, grain: :x, eb: [1, ends])
      end
      return unless wg.positive?

      gd = gola_dims
      ws = lambda do |ents| # hollow section open underneath: top wall + front and back walls
        tt = 2.0
        f = ents.add_face([[0, 0], [tt, 0], [tt, gd[:w_h] - tt], [wg - tt, gd[:w_h] - tt], [wg - tt, 0], [wg, 0], [wg, gd[:w_h]], [0, gd[:w_h]]].map { |dd, zz| Geo.p3(0, dd, zz) })
        f&.pushpull(f.normal.x >= 0 ? Geo.mm(width) : -Geo.mm(width))
      end
      pn('gola_profile', x0, fr, @z0, width, wg, gd[:w_h], 'profile', role: 'hw', solid: ws,
         notes: "handle-free WALL UNIT profile #{wg.round(1)} x #{gd[:w_h].round(1)}, knocked into the front edge of the bottom panel (panel #{wg.round} mm shallower)")
      # LED strip inside the wall-unit profile, under its top wall, shining down on the worktop (counted by the metre below)
      pn('gola_led', x0, fr + wg / 2.0 - 4.0, @z0 + gd[:w_h] - 4.5, width, 8.0, 2.0, 'profile', role: 'hw', notes: 'LED strip in the handle-free wall unit profile') if @c['gola_led'] && wg > 14 && gd[:w_h] > 8
      @hw['gola_w_m'] += width / 1000.0
      @hw['gola_led_m'] += width / 1000.0 if @c['gola_led']
      @wall_gola = true
    end

    # Oven position: the oven's z0 is entirely a function of the cell(s) BELOW it, so lowering it by
    # exactly 50 mm means taking 50 mm away from the cell directly below:
    #  - that cell has its OWN declared height (oven_tower's/oven_tall's drawer, h: 500 / 350): shrink
    #    it directly by 50 mm. It stays a real, functional drawer - no new part, no void.
    #  - that cell is free/auto-sized ('oven' type's drawer has no declared h): its natural size can't
    #    be reduced declaratively, so a real fixed trim panel (front-material, edge banded, on the cut
    #    list/cost) is inserted directly ABOVE the oven instead, redirecting exactly 50 mm of what that
    #    free cell would otherwise have absorbed - never an empty void. 50 mm is too short for a
    #    functional hinged door or drawer (real hardware needs far more clearance), so it is a fixed
    #    panel rather than a working front.
    # Either way, the oven itself, and everything already above it, keep their own exact declared size
    # and position. Only applies where the oven HAS a cell below it (drawer types: oven / oven_tower /
    # oven_tall) - hob_oven's oven is the cabinet's own floor-anchored bottom cell with nothing below
    # it to give up height, so it is left exactly as designed (lowering it would need a taller cabinet,
    # which changes the frozen spec).
    OVEN_LOWER_MM = 50.0

    def cells
      t = @t
      raw = @s[:cells]
      oven_i = raw.find_index { |c| c[:t] == :appliance && c[:app].to_s == 'oven' }
      if oven_i&.positive? && !@s[:no_oven_lower]
        prev = raw[oven_i - 1]
        if prev[:h]
          raw = raw.dup
          raw[oven_i - 1] = prev.merge(h: [prev[:h].to_f - OVEN_LOWER_MM, 50.0].max)
        else
          # the new trim cell also costs one extra divider (t) out of the same free cell that gives up
          # its own height, so the panel itself is OVEN_LOWER_MM - t: total drop = h + t = 50mm exactly.
          raw = raw[0..oven_i] + [{ t: :trim, h: OVEN_LOWER_MM - t }] + raw[(oven_i + 1)..]
        end
      end
      # a 60 cm built-in oven picked from the catalogue keeps the standard 600 niche, so the unit is built exactly like the one with the default oven
      list = raw.map do |c|
        dv = c[:t] == :appliance ? device_for(c[:app]) : nil
        next c unless dv
        next c if c[:app].to_s == 'oven' && c[:h] && dv[:h].to_f <= c[:h].to_f

        c.merge(h: [dv[:h].to_f + 4, @hc - 2 * @t - 150].min)
      end
      n = list.size
      z_in0 = @z0 + (@kind == :hood || @s[:no_bottom] ? 0 : t)
      z_in1 = @z0 + @hc - t
      inner = z_in1 - z_in0
      fixed = EGC::Num.sum(list) { |x| x[:h].to_f }
      free = list.count { |x| x[:h].nil? }
      rem = inner - (n - 1) * t - fixed
      each = free > 0 ? rem / free : 0
      z = z_in0
      laid = list.each_with_index.map do |cell, i|
        ch = cell[:h] || each
        ch += rem if free.zero? && i == n - 1
        r = cell.merge(z0: z, h: ch)
        z += ch + t
        r
      end
      laid.each_with_index do |cell, i|
        if i < n - 1
          pn('divider', t, @bk, cell[:z0] + cell[:h], @w - 2 * t, @cd - @bk, t, 'carcass', grain: :x, eb: [1, 0])
        end
        fz0 = i.zero? ? @z0 : cell[:z0] - t / 2.0
        fz1 = i == n - 1 ? @z0 + @hc - front_drop : cell[:z0] + cell[:h] + t / 2.0
        zf = fz0 + @gap / 2.0
        hf = fz1 - fz0 - @gap
        do_cell(cell, zf, hf)
      end
    end

    # the optional upright strip: switched on in the settings (front_strip_on), on door units and sink units only - in a drawer / pull-out /
    # appliance unit it would stand in the way of the top drawer box
    def front_strip?
      return false if SINK_TYPES.include?(@s[:type].to_s) # the sink unit's own front rail already stands upright there
      top = Array(@s[:cells]).last
      @c['front_strip_on'] && front_strip_h >= 20.0 && @kind == :base && !@s[:mech] && !@s[:corner] && @s[:cutout].to_s != 'hob' && top && top[:t].to_s == 'doors' && !top[:app]
    end

    def front_strip_h
      @c['front_rail_h'].to_f
    end

    # how much the fronts of a base unit stop short of the carcass top: the drop of the worktop's front edge
    def front_drop
      return 0.0 unless @kind == :base

      [[@c['top_lip'].to_f, 0.0].max, 80.0].min
    end

    def do_cell(cell, zf, hf)
      case cell[:t]
      when :doors then shelves(cell); doors(cell, zf, hf, false)
      when :flap  then shelves(cell); doors(cell, zf, hf, true)
      when :drawers then drawers(cell, zf, hf)
      when :open then shelves(cell)
      when :appliance then appliance(cell, zf, hf)
      when :hood then hood_cell(cell)
      when :cols then columns(cell, zf, hf)
      when :trim then trim_panel(zf, hf)
      when :vent then vent_panel(zf, hf)
      end
    end

    # A fixed, non-opening front panel filling a gap too short for real hardware (see OVEN_LOWER_MM) -
    # a real cut-list part (front board, edge banded), just without hinges.
    def trim_panel(zf, hf)
      pn('trim', cx0 + @gap / 2.0, @cd, zf, cw - @gap, @ft, hf, 'front', grain: :z, eb: [2, 2], eb_t: 2.0)
    end

    # FIXED PANEL UNDER A BUILT-IN OVEN: it does not open; a ventilation grille is let into it (cooling air for the oven). The grille size is
    # GENERIC - the cut-out and the free air section always follow the installation manual of the oven that is bought.
    VENT_GRILLE = { w: 520.0, h: 40.0 }.freeze # a slim brushed-steel grille across the panel (it read as a black hole before)

    def vent_panel(zf, hf)
      gw = [VENT_GRILLE[:w], cw - @gap - 60].min
      gh = [VENT_GRILLE[:h], hf - 50].min
      ok = gw >= 100 && gh >= 20
      note = ok ? "fixed panel under the oven (does not open); cut-out #{(gw - 10).round} x #{(gh - 10).round} in the centre for a ventilation grille - GENERIC, follow the oven manual" : 'fixed panel under the oven (does not open)'
      pn('trim', cx0 + @gap / 2.0, @cd, zf, cw - @gap, @ft, hf, 'front', grain: :x, eb: [2, 2], eb_t: 2.0, notes: note)
      return unless ok

      slats = lambda do |ents|
        Geo.box(ents, 0, 0, 0, gw, 1.5, gh)
        dark = Appliances.mat('Grille Slot', [26, 28, 31]) # the air slots: dark between the steel bars
        ents.grep(Sketchup::Face).each { |f| f.material = dark }
        [[0, 0, gw, 3.5], [0, gh - 3.5, gw, 3.5], [0, 0, 4, gh], [gw - 4, 0, 4, gh]].each { |x, z, w, h| Geo.box(ents, x, 1.5, z, w, 2.5, h) } # frame
        z = 7.0
        while z + 3 <= gh - 6
          Geo.box(ents, 4, 1.5, z, gw - 8, 2.0, 3.0)
          z += 6.5
        end
      end
      grille = pn('vent_grille', cx0 + (cw - gw) / 2.0, @cd + @ft, zf + (hf - gh) / 2.0, gw, 4.0, gh, 'profile', role: 'hw', solid: slats, notes: "generic ventilation grille #{gw.round} x #{gh.round}")
      grille.material = Appliances.pal[:body] if grille.respond_to?(:material=)
      @hw['vent_grille'] += 1
    end

    # A cell split into side-by-side columns (Space / Front Designer): each column is its own
    # mini-cell (doors, drawers, open, flap...) between vertical dividers.
    def columns(cell, zf, hf)
      cols = cell[:cols].to_a
      return if cols.empty?

      t = @t
      inner = @w - 2 * t
      nd = cols.size - 1
      fixed = EGC::Num.sum(cols) { |c| c[:w].to_f }
      free = cols.count { |c| c[:w].to_f <= 0 }
      each = free.positive? ? [(inner - nd * t - fixed) / free, 80.0].max : 0.0
      x = t
      cols.each_with_index do |col, i|
        cwid = col[:w].to_f.positive? ? col[:w].to_f : each
        cwid = [inner - nd * t - fixed - free * each, 0].max + cwid if i == cols.size - 1 && free.zero?
        xa = x
        xb = x + cwid
        fa = i.zero? ? 0.0 : xa - t / 2.0
        fb = i == cols.size - 1 ? @w : xb + t / 2.0
        @fx0 = fa
        @fw = fb - fa
        @sx0 = xa
        @sx1 = xb
        do_cell(col.merge(z0: cell[:z0], h: cell[:h]), zf, hf)
        pn('col_divider', xb, (notch_hits?(xb, xb + t) ? notch[:d] : @bk), cell[:z0], t, @cd - (notch_hits?(xb, xb + t) ? notch[:d] : @bk), cell[:h], 'carcass', grain: :z, eb: [1, 0]) if i < cols.size - 1
        x = xb + t
      end
    ensure
      @fx0 = @fw = @sx0 = @sx1 = nil
    end

    def shelves(cell)
      k = cell[:shelves].to_i
      return if k <= 0

      t = @t
      ch = cell[:h]
      sp = (ch - k * t) / (k + 1.0)
      k.times do |i|
        z = cell[:z0] + sp * (i + 1) + t * i
        lane = cell[:t] == :flap ? 26 : 0 # leave the lift-arm lanes free
        pn('shelf', ix0 + 1 + lane, @bk, z, (ix1 - ix0) - 2 - 2 * lane, @cd - @bk - [(cell[:front_clear] || 20), (@kind == :tall && @c['handle'].to_s == 'gola' ? gola_dims[:v_d] + 3 : 0)].max, t, 'carcass', grain: :x, eb: [1, 0])
        @hw['shelf_pin'] += 4
      end
    end

    def hinge_count(h)
      return 2 if h <= 900
      return 3 if h <= 1600
      return 4 if h <= 2000

      5
    end

    def door_pos(k, n, flap)
      return :bottom if flap
      case @s[:handle_pos].to_s # the unit's own handle place (unit panel / quick actions)
      when 'top' then return :top
      when 'bottom' then return :bottom
      when 'side' then return hinge_side(k, n)[0] ? :side_r : :side_l
      end
      return :bottom if @kind == :wall || @kind == :hood
      return :top if @kind == :base

      hinge_side(k, n)[0] ? :side_r : :side_l
    end

    def doors(cell, zf, hf, flap)
      blind = cell[:blind].to_f
      n = flap ? 1 : (cell[:n] || (cw - blind <= 610 ? 1 : 2))
      total = cw - @gap - blind
      if blind > 0
        pn('filler', cx0 + cw - blind - @gap / 2.0, @cd, zf, blind, @ft, hf, 'front', grain: :z, eb: [2, 2], eb_t: 2.0)
      end
      dw = (total - @gap * (n - 1)) / n
      n.times do |k|
        x = cx0 + @gap / 2.0 + k * (dw + @gap)
        a = asm(flap ? 'flap' : "door#{k + 1}", door_move(k, n, x, dw, zf, hf, flap))
        in_asm(a) do
          front(flap ? 'flap' : 'door', x, dw, zf, hf, door_pos(k, n, flap), single: (n == 1 && blind.zero?), pair: (n == 2 && blind.zero? && !flap ? k : nil), glass: cell[:glass], grain: :z, hs: (flap ? nil : hinge_side(k, n)),
                                                                           bore_abs: flap ? nil : hinge_abs(k, n, x, dw, zf, hf))
          door_hinges(k, n, x, dw, zf, hf) unless flap
        end
        door_plates(k, n, x, dw, zf, hf) unless flap
        if flap
          flap_stays(zf, hf)
          @hw['lift_up'] += 1
        else
          @hw['hinge'] += hinge_count(hf)
        end
      end
    end

    # EDGE GRIP PROFILE (the owner's reference handle block, section 20 x 36.6: it caps the door edge and adds 35 mm to the board):
    # a C channel as thick as the door, flush with both faces - a foot that sits on the board edge, a thin back wall, a rounded head and a short
    # lip hanging at the FRONT; the fingers go into the open front and pull on that lip. The board is cut shorter by the profile height.
    # prof = [x, z, width, height, length]; pos decides which edge it sits on.
    def j_profile(pos, prof)
      lambda do |ents|
        fr = @ft
        horiz = %i[top bottom].include?(pos)
        ph = horiz ? prof[3] : prof[2]
        foot = [3.6, ph * 0.18].min
        lip = [9.8, ph * 0.28].min
        wall = 1.2
        pts = [[0, 0], [fr, 0], [fr, ph], [0, ph], [0, ph - lip], [wall, ph - lip], [wall, ph - 3.5], [3.5, ph - wall], [fr - 3.5, ph - wall], [fr - wall, ph - 3.5],
               [fr - wall, foot + 2.5], [fr - 3.5, foot], [0, foot]]
        pts = pts.map { |d, z| [fr - d, z] }.reverse # the panel's local depth starts at the door's inner face: the open side goes to the room
        pts = pts.map { |d, z| [d, ph - z] } if pos == :bottom
        if horiz
          Geo.extrude(ents, pts.map { |d, z| Geo.p3(0, d, z) }, Geom::Vector3d.new(1, 0, 0), prof[2])
        else
          xy = pts.map { |d, z| pos == :side_r ? [z, d] : [ph - z, d] }
          Geo.extrude(ents, xy.map { |x, d| Geo.p3(x, d, 0) }, Geom::Vector3d.new(0, 0, 1), prof[3])
        end
      end
    end

    # Front styles (cfg 'front_style' or per unit spec[:style]): flat | shaker | bevel.
    # shaker = routed pocket (CNC MDF door): frame rim with a square-walled recessed panel.
    # bevel  = same pocket with 45 degree sloped walls. Glass/thin fronts stay flat.
    STYLES = { 'shaker' => { rim: 60.0, depth: 8.0, slope: false }, 'bevel' => { rim: 30.0, depth: 12.0, slope: true } }.freeze

    def front_style
      (@s[:style] || @c['front_style'] || 'flat').to_s
    end

    def style_solid(sx, sd, sz)
      st = STYLES[front_style]
      return nil unless st && sx >= 200 && sz >= 200 && sd >= st[:depth] + 6

      rim = [st[:rim], (([sx, sz].min - 60) / 2.0)].min
      depth = st[:depth]
      slope = st[:slope]
      lambda do |ents|
        Geo.box(ents, 0, 0, 0, sx, sd, sz)
        face = ents.grep(Sketchup::Face).find { |f| f.normal.y < -0.99 && (f.bounds.center.y + Geo.mm(sd)).abs < 0.01 }
        next unless face

        pts = [[rim, rim], [sx - rim, rim], [sx - rim, sz - rim], [rim, sz - rim]].map { |x, z| Geo.p3(x, sd, z) }
        inner = ents.add_face(pts)
        next unless inner

        inner = ents.grep(Sketchup::Face).find { |f| f.normal.y < -0.99 && f.vertices.size == 4 && (f.area - Geo.mm(sx - 2 * rim) * Geo.mm(sz - 2 * rim)).abs < 1e-3 } || inner
        inner.pushpull(inner.normal.y < 0 ? -Geo.mm(depth) : Geo.mm(depth))
        next unless slope

        bot = ents.grep(Sketchup::Face).find { |f| f.normal.y < -0.99 && (f.bounds.center.y + Geo.mm(sd - depth)).abs < 0.01 && f.vertices.size == 4 }
        next unless bot

        c = bot.bounds.center
        vecs = bot.vertices.map do |v|
          Geom::Vector3d.new(c.x > v.position.x ? Geo.mm(depth) : -Geo.mm(depth), 0, c.z > v.position.z ? Geo.mm(depth) : -Geo.mm(depth))
        end
        ents.transform_by_vectors(bot.vertices, vecs)
      end
    end

    # ---- handles: generic, lightweight geometry (cylinders / boxes), never a manufacturer model --------------------------------------------
    # returns [x, z, sx, sd, sz, solid_lambda] in front-local coordinates (d starts at the front face)
    def handle_layout(kind, pos, x, z, w, h, hs = nil)
      off = (@c['handle_offset'].to_f.positive? ? @c['handle_offset'].to_f : (kind == 'knob' ? 40.0 : 48.0))
      place = (@c['handle_pos'] || 'auto').to_s
      orient = (@c['handle_orient'] || 'auto').to_s
      where = case place
              when 'center' then :center
              when 'top' then :top
              when 'bottom' then :bottom
              when 'side' then (hs ? (hs[0] ? :side_r : :side_l) : (pos == :side_l ? :side_l : :side_r))
              else pos
              end
      where = :side_r if where.nil?
      horizontal = case orient
                   when 'horizontal' then true
                   when 'vertical' then false
                   else %i[top bottom center].include?(where)
                   end
      standoff = kind == 'pull' ? 24.0 : 30.0
      if kind == 'knob'
        head = 30.0
        kx = where == :side_l ? x + off : x + w - off - head
        kz = case where
             when :bottom then z + off
             when :center then z + h / 2.0 - head / 2.0
             else z + h - off - head
             end
        return [kx, kz, head, 36.0, head, handle_solid('knob', true, head, head, 22.0)]
      end
      horizontal = true if kind == 'cup' # a cup (shell) handle always lies across the front
      th = kind == 'pull' ? 26.0 : (kind == 'cup' ? 40.0 : 12.0)
      len = horizontal ? [[160.0, w * 0.35].max, [w - 70.0, 320.0].min].min : [[160.0, h * 0.25].max, [h - 70.0, 320.0].min].min
      len = [len, 64.0].max
      # the two fixing screws stand on a standard hole spacing (32 mm system: 64 / 96 / 128 / 160 / 192 / 224 / 256 / 288 / 320 centre to centre);
      # the handle is as long as that spacing + its two ends
      post = handle_post(kind)
      @handle_cc = HANDLE_CC.select { |c| c + 2 * post <= len + 0.01 }.max || HANDLE_CC.first
      @handle_cc = [@handle_cc, 96.0].min if kind == 'cup' # cup handles come with 64 or 96 mm hole centres
      len = @handle_cc + 2 * post
      if horizontal
        hz = case where
             when :bottom then z + off - th / 2.0
             when :center then z + h / 2.0 - th / 2.0
             else z + h - off - th / 2.0
             end
        [x + w / 2.0 - len / 2.0, hz, len, standoff + th, th, handle_solid(kind, true, len, th, standoff)]
      else
        hx = where == :side_l ? x + off - th / 2.0 : x + w - off - th / 2.0
        [hx, z + h / 2.0 - len / 2.0, th, standoff + th, len, handle_solid(kind, false, len, th, standoff)]
      end
    end

    HANDLE_CC = [64.0, 96.0, 128.0, 160.0, 192.0, 224.0, 256.0, 288.0, 320.0].freeze
    HANDLE_SCREW = { dia: 5.0, thread: 'M4' }.freeze # through hole for the handle's M4 machine screw

    FLUSH_PULL = { pocket: 35.5, depth: 11.5, plate: 40.0 }.freeze # generic recessed pull: a 40 x 40 plate over a round pocket
    J_PULL = { w: 22.0, depth: 10.0 }.freeze                       # generic routed finger groove

    def handle_post(kind)
      { 'pull' => 18.0, 'cup' => 16.0 }[kind] || 20.0
    end
    
    # EDGE PULL (lip / tab handle): a thin angle that sits on the opening edge of the front, its lip standing proud of the face; it is screwed
    # into the BACK of the front, so the face is not drilled. Lengths 100 / 150 / 200 / 300.
    # returns [x, z, sx, sd, sz, solid, back_holes, length]
    EDGE_PULL_LEN = [100.0, 150.0, 200.0, 300.0].freeze
    EDGE_PULL = { lip: 18.0, thk: 3.0, screw_dia: 3.0, screw_depth: 10.0, screw_in: 12.0 }.freeze
    
    def edge_pull(pos, x, z, w, h)
      pos = :top unless %i[top bottom side_l side_r].include?(pos)
      horiz = %i[top bottom].include?(pos)
      span = horiz ? w : h
      len = EDGE_PULL_LEN.select { |l| l <= span - 60 }.max || EDGE_PULL_LEN.first
      cc = ((len - 20) / 32.0).floor * 32.0
      t = EDGE_PULL[:thk]
      sd = @ft + EDGE_PULL[:lip]
      inn = EDGE_PULL[:screw_in]
      if horiz
        x0 = x + (w - len) / 2.0
        zz = pos == :top ? z + h : z - t
        hz = pos == :top ? z + h - inn : z + inn
        [x0, zz, len, sd, t, ->(e) { Geo.box(e, 0, 0, 0, len, sd, t) }, [[x0 + (len - cc) / 2.0, hz], [x0 + (len + cc) / 2.0, hz]], len]
      else
        z0 = z + (h - len) / 2.0
        xx = pos == :side_r ? x + w : x - t
        hx = pos == :side_r ? x + w - inn : x + inn
        [xx, z0, t, sd, len, ->(e) { Geo.box(e, 0, 0, 0, t, sd, len) }, [[hx, z0 + (len - cc) / 2.0], [hx, z0 + (len + cc) / 2.0]], len]
      end
    end

    # centres of the fixing holes of a handle laid out by #handle_layout (absolute x / z on the front)
    def handle_holes(kind, bar)
      return [[bar[0] + bar[2] / 2.0, bar[1] + bar[4] / 2.0]] if kind == 'knob'

      post = handle_post(kind)
      if bar[2] >= bar[4]
        [[bar[0] + post, bar[1] + bar[4] / 2.0], [bar[0] + bar[2] - post, bar[1] + bar[4] / 2.0]]
      else
        [[bar[0] + bar[2] / 2.0, bar[1] + post], [bar[0] + bar[2] / 2.0, bar[1] + bar[4] - post]]
      end
    end

    # solid builder (local coordinates: x width, d depth from the front face, z height)
    def handle_solid(kind, horizontal, len, th, standoff)
      lambda do |ents|
        case kind
        when 'cup'
          Geo.box(ents, 0, 0, 0, len, 3.0, th)                       # back plate on the face
          Geo.box(ents, 0, 3.0, th * 0.42, len, 23.0, th * 0.58)     # the shell: open underneath for the fingers
        when 'knob'
          Appliances.cyl(ents, th / 2.0, 0, th / 2.0, 4.0, standoff, nil, :y, 10)
          Appliances.cyl(ents, th / 2.0, standoff, th / 2.0, th / 2.0, 14.0, nil, :y, 16)
        when 'pull'
          if horizontal
            [18.0, len - 18.0].each { |px| Appliances.cyl(ents, px, 0, th / 2.0, 4.0, standoff + 2, nil, :y, 10) }
            Geo.box(ents, 0, standoff, 0, len, 10.0, th)
          else
            [18.0, len - 18.0].each { |pz| Appliances.cyl(ents, th / 2.0, 0, pz, 4.0, standoff + 2, nil, :y, 10) }
            Geo.box(ents, 0, standoff, 0, th, 10.0, len)
          end
        else
          if horizontal
            Appliances.cyl(ents, 0, standoff, th / 2.0, th / 2.0, len, nil, :x, 12)
            [20.0, len - 20.0].each { |px| Appliances.cyl(ents, px, 0, th / 2.0, 4.0, standoff + 2, nil, :y, 10) }
          else
            Appliances.cyl(ents, th / 2.0, standoff, 0, th / 2.0, len, nil, :z, 12)
            [20.0, len - 20.0].each { |pz| Appliances.cyl(ents, th / 2.0, 0, pz, 4.0, standoff + 2, nil, :y, 10) }
          end
        end
      end
    end

    # sizes of the handle-free profiles (settings; never below a workable minimum)
    def gola_dims
      num = ->(k, dflt, min) { v = @c[k].to_f; [v.positive? ? v : dflt, min].max }
      @gola_dims ||= { l_h: num.call('gola_l_h', 56.0, 30.0), l_d: num.call('gola_l_d', 27.0, 15.0), c_h: num.call('gola_c_h', 72.7, 40.0), c_d: num.call('gola_c_d', 26.0, 15.0),
                       w_h: num.call('gola_w_h', 20.0, 10.0), w_d: num.call('gola_w_d', 20.0, 10.0), v_w: num.call('gola_v_w', 48.25, 25.0), v_d: num.call('gola_v_d', 36.6, 15.0),
                       v_gap: num.call('gola_v_gap', 18.0, 8.0), gap: num.call('gola_gap', 30.0, 15.0), v2_w: num.call('gola_v2_w', 66.5, 30.0) }
    end

    # handle-free profile extruded along the front width (local: d from the back of the profile to the carcass front, z height).
    # :l = L section (back wall + bottom lip, under the worktop), :c = C section (back wall + top and bottom lips, between two fronts)
    def gola_solid(len, sd, sh, type = :c)
      lambda do |ents|
        t = 2.5
        pts = type == :l ? [[0, 0], [sd, 0], [sd, t], [t, t], [t, sh], [0, sh]] : [[0, 0], [sd, 0], [sd, t], [t, t], [t, sh - t], [sd, sh - t], [sd, sh], [0, sh]]
        f = ents.add_face(pts.map { |dd, zz| Geo.p3(0, dd, zz) })
        f&.pushpull(f.normal.x >= 0 ? Geo.mm(len) : -Geo.mm(len))
      end
    end

    # the front board with the J-pull rebate cut along its opening edge (local: x width, d from the back of the board to its face, z height)
    def j_pull_solid(edge, pw, phh)
      gw = J_PULL[:w]
      gd = [J_PULL[:depth], @ft - 6.0].min
      ft = @ft
      lambda do |ents|
        if %i[top bottom].include?(edge)
          pts = edge == :top ? [[0, 0], [ft, 0], [ft, phh - gw], [ft - gd, phh - gw], [ft - gd, phh], [0, phh]] : [[0, 0], [ft - gd, 0], [ft - gd, gw], [ft, gw], [ft, phh], [0, phh]]
          f = ents.add_face(pts.map { |dd, zz| Geo.p3(0, dd, zz) })
          f&.pushpull(f.normal.x >= 0 ? Geo.mm(pw) : -Geo.mm(pw))
        else
          pts = edge == :side_r ? [[0, 0], [pw, 0], [pw, ft - gd], [pw - gw, ft - gd], [pw - gw, ft], [0, ft]] : [[0, 0], [pw, 0], [pw, ft], [gw, ft], [gw, ft - gd], [0, ft - gd]]
          f = ents.add_face(pts.map { |px, dd| Geo.p3(px, dd, 0) })
          f&.pushpull(f.normal.z >= 0 ? Geo.mm(phh) : -Geo.mm(phh))
        end
      end
    end

    def front(part, x, w, z, h, pos, o = {})
      o = o.merge(glass: true) if @s[:glass_all] && @s[:mech] && part.to_s == 'door' && !o.key?(:glass) # glass style on a mechanism unit
      d = o[:d] || @cd
      mat = o[:glass] ? 'glass' : 'front'
      ph = @c['profile_h'].to_f
      px = x
      pz = z
      pw = w
      phh = h
      prof = nil
      vprof = nil
      bar = nil
      edge = nil
      flush = nil
      jpull = nil
      case @c['handle']
      when 'profile'
        case pos
        when :top    then phh = h - ph; prof = [x, z + h - ph, w, ph, w]
        when :bottom then pz = z + ph; phh = h - ph; prof = [x, z, w, ph, w]
        when :side_r then pw = w - ph; prof = [x + w - ph, z, ph, h, h]
        when :side_l then px = x + ph; pw = w - ph; prof = [x, z, ph, h, h]
        end
      when 'bar', 'pull', 'knob', 'cup'
        bar = handle_layout(@c['handle'], pos, x, z, w, h, o[:hs])
      when 'edge'
        edge = edge_pull(pos, x, z, w, h) unless o[:glass]
      when 'flush'
        # FLUSH (recessed) PULL: a small plate let into a pocket routed in the FACE of the front; nothing stands proud
        unless o[:glass]
          k = handle_layout('knob', pos, x, z, w, h, o[:hs])
          flush = [k[0] + k[2] / 2.0, k[1] + k[4] / 2.0]
        end
      when 'jpull'
        # J-PULL: no hardware at all - a finger groove routed along the opening edge of the front (the board keeps its full size)
        jpull = %i[bottom side_l side_r].include?(pos) ? pos : :top unless o[:glass]
      when 'gola'
        # construction system: a channel profile at the top edge of base fronts (access gap); generic geometry, profile specification required
        if pos == :top || @kind == :base
          gh = gola_dims[:gap]
          phh = h - gh
          gzc = z + h - gh / 2.0
          gd = gola_dims
          if gzc >= @z0 + @hc - gd[:l_h] # the front under the worktop: L profile in the top-front corner of the carcass
            prof = [x, @z0 + @hc - gd[:l_h], w, gd[:l_h], w, :gola, :l, gd[:l_d]]
          else                           # a front under another front: C profile between the two
            prof = [x, gzc - gd[:c_h] / 2.0, w, gd[:c_h], w, :gola, :c, gd[:c_d]]
          end
          (@gola_z ||= []) << gzc # centre height of the finger gap: the gables are notched there (see #finish)
        elsif @wall_gola && pos == :bottom
          nil # wall unit: the grip profile is let into the bottom panel behind this front (see #bottom); the front keeps its full size
        elsif @kind == :tall && %i[side_l side_r].include?(pos) && !o[:glass] && o[:single] && w > gola_dims[:v_w] + 150
          # TALL UNIT, one door: vertical single-grip profile on the gable beside the door; the door is narrower by the grip slot on its opening side
          gd = gola_dims
          pw = w - gd[:v_gap]
          px = x + gd[:v_gap] if pos == :side_l
          vprof = [pos == :side_r ? x + w - gd[:v_w] : x, z, gd[:v_w], h, gd[:v_d]]
        elsif @kind == :tall && %i[side_l side_r].include?(pos) && !o[:glass] && o[:pair] && w > gola_dims[:v_gap] + 150
          # TALL UNIT, two doors on one carcass: ONE vertical double-grip profile on the centre line; each door is narrower by the grip slot at the centre
          gd = gola_dims
          pw = w - gd[:v_gap]
          px = x + gd[:v_gap] if pos == :side_l
          vprof = [x + w + @gap / 2.0 - gd[:v2_w] / 2.0, z, gd[:v2_w], h, gd[:v_d], :double] if pos == :side_r # drawn once, with the left door
        else
          @hw['push_opener'] += 1 # no profile for this front (two doors on one carcass, corner unit): it opens by push
        end
      when 'push'
        @hw['push_opener'] += 1 # handleless push-to-open: no visible handle, one opener per front
      end
      bore = (o[:bore_abs] || []).map do |xc, zc|
        (@plate_marks ||= []) << [xc, zc] # the gable this door hangs on gets the mounting-plate bores at the same height (see #hinge_plate_bores)
        { 't' => 'hinge cup', 'x' => (xc - px).round(1), 'y' => (zc - pz).round(1), 'dia' => 35, 'depth' => 12,
          'ref' => 'generic visual hinge only; manufacturing location requires selected hinge specification', 'status' => 'REQUIRES_HINGE_SPECIFICATION' }
      end
      hnote = nil
      if flush
        bore << { 't' => 'flush pull pocket', 'x' => (flush[0] - px).round(1), 'y' => (flush[1] - pz).round(1), 'dia' => FLUSH_PULL[:pocket], 'depth' => FLUSH_PULL[:depth],
                  'ref' => 'pocket routed in the FRONT face; x from left edge, y from bottom edge' }
        hnote = "flush pull: pocket dia #{FLUSH_PULL[:pocket]} x #{FLUSH_PULL[:depth]} deep in the FACE"
      end
      hnote = "J-pull: finger groove routed along the #{{ top: 'top', bottom: 'bottom', side_l: 'left', side_r: 'right' }[jpull]} edge, full length (#{J_PULL[:w].round} wide, #{J_PULL[:depth].round} deep, in the FACE)" if jpull
      if edge
        bore += edge[6].map do |hx, hz|
          { 't' => 'edge pull screw', 'x' => (hx - px).round(1), 'y' => (hz - pz).round(1), 'dia' => EDGE_PULL[:screw_dia], 'depth' => EDGE_PULL[:screw_depth],
            'ref' => 'pilot hole in the BACK face (the face is not drilled); x from left edge, y from bottom edge' }
        end
        hnote = "edge pull #{edge[7].round} mm, 2 pilot holes in the back"
      end
      if bar && !o[:glass]
        # handle fixing holes: drilled through the front, on the cut list / CNC drilling like every other bore
        holes = handle_holes(@c['handle'], bar)
        bore += holes.map do |hx, hz|
          { 't' => 'handle screw', 'x' => (hx - px).round(1), 'y' => (hz - pz).round(1), 'dia' => HANDLE_SCREW[:dia], 'depth' => @ft,
            'ref' => "through hole, #{HANDLE_SCREW[:thread]} screw; x from left edge, y from bottom edge" }
        end
        hnote = @c['handle'] == 'knob' ? 'knob, 1 hole' : "#{@c['handle']} handle, holes #{@handle_cc.round} mm centre to centre"
      end
      ssolid = o[:glass] ? nil : style_solid(pw, @ft, phh)
      ssolid ||= j_pull_solid(jpull, pw, phh) if jpull
      pn(part, px, d, pz, pw, @ft, phh, mat, grain: o[:grain] || :z, eb: [2, 2], eb_t: 2.0,
                                               role: o[:glass] ? 'glass' : 'part', bore: bore, solid: ssolid,
                                               notes: [(ssolid ? "#{front_style} routed pocket" : nil), hnote, (prof && prof[5] != :gola ? "cut #{@c['profile_h'].to_f.round} mm shorter for the edge grip profile" : nil), (prof && prof[5] == :gola ? "cut #{gola_dims[:gap].round} mm shorter for the handle-free finger gap" : nil), (pw < w - 0.5 && @c['handle'].to_s == 'gola' && @kind == :tall ? "cut #{gola_dims[:v_gap].round} mm narrower for the vertical grip profile" : nil)].compact.join('; ').then { |s| s.empty? ? nil : s })
      if prof
        if prof[5] == :gola
          on_carcass do # a handle-free profile is screwed to the CARCASS: it stays where it is when the door / drawer opens
            pn('gola_profile', prof[0], d - prof[7], prof[1], prof[2], prof[7], prof[3], 'profile', role: 'hw', solid: gola_solid(prof[2], prof[7], prof[3], prof[6]),
               notes: "handle-free #{prof[6] == :l ? 'L' : 'C'} profile #{prof[7].round} x #{prof[3].round} (sizes from the settings - check against the profile that is bought)")
            # the LED strip of the profile, as a part of its own (counted by the metre in the hardware list)
            pn('gola_led', prof[0], d - prof[7] + 2.5, prof[1] + prof[3] - 11.0, prof[2], 2.0, 8.0, 'profile', role: 'hw', notes: 'LED strip in the handle-free profile') if @c['gola_led'] && prof[3] > 16 && prof[7] > 6
          end
        else
          pn('profile', prof[0], d, prof[1], prof[2], @ft, prof[3], 'profile', role: 'hw', solid: j_profile(pos, prof))
        end
        prof[5] == :gola ? @hw[prof[6] == :l ? 'gola_l_m' : 'gola_c_m'] += prof[4] / 1000.0 : @hw['profile_mm'] += prof[4]
        @hw['gola_led_m'] += prof[4] / 1000.0 if prof[5] == :gola && @c['gola_led']
      end
      if vprof
        vs = lambda do |ents| # U section open to the front: back wall + two side walls
          tt = 2.5
          f = ents.add_face([[0, 0], [vprof[2], 0], [vprof[2], vprof[4]], [vprof[2] - tt, vprof[4]], [vprof[2] - tt, tt], [tt, tt], [tt, vprof[4]], [0, vprof[4]]].map { |px2, dd| Geo.p3(px2, dd, 0) })
          f&.pushpull((f.normal.z >= 0 ? 1 : -1) * Geo.mm(vprof[3]))
        end
        on_carcass do
          pn('gola_profile', vprof[0], d - vprof[4], vprof[1], vprof[2], vprof[4], vprof[3], 'profile', role: 'hw', solid: vs,
             notes: "handle-free VERTICAL #{vprof[5] == :double ? 'double' : 'single'}-grip profile #{vprof[2].round(1)} x #{vprof[4].round(1)}, length #{vprof[3].round}; the door is #{gola_dims[:v_gap].round} mm narrower on its opening side")
          pn('gola_led', vprof[0] + vprof[2] / 2.0 - 4.0, d - vprof[4] + 2.5, vprof[1], 8.0, 2.0, vprof[3], 'profile', role: 'hw', notes: 'LED strip in the vertical handle-free profile') if @c['gola_led'] && vprof[2] > 12 && vprof[4] > 6
        end
        @hw[vprof[5] == :double ? 'gola_v2_m' : 'gola_v_m'] += vprof[3] / 1000.0
        @hw['gola_led_m'] += vprof[3] / 1000.0 if @c['gola_led']
        (@gola_v ||= []) << vprof
      end
      if flush
        sz = FLUSH_PULL[:plate]
        pn('handle', flush[0] - sz / 2.0, d + @ft - 1.0, flush[1] - sz / 2.0, sz, 2.0, sz, 'profile', role: 'hw', notes: 'generic flush pull')
        @hw['handle'] += 1
      end
      if jpull
        gw = J_PULL[:w]
        horiz = %i[top bottom].include?(jpull)
        jx = jpull == :side_r ? px + pw - gw : px
        jz = jpull == :top ? pz + phh - gw : pz
        pn('j_pull_groove', jx, d + @ft - [J_PULL[:depth], @ft - 6.0].min - 1.0, jz, horiz ? pw : gw, 1.0, horiz ? gw : phh, 'profile', role: 'hw', notes: 'routing, not a part: the finger groove of the J-pull')
      end
      if edge
        pn('handle', edge[0], d, edge[1], edge[2], edge[3], edge[4], 'profile', role: 'hw', solid: edge[5], notes: "generic edge pull #{edge[7].round} mm")
        @hw['handle'] += 1
      end
      if bar
        pn('handle', bar[0], d + @ft, bar[1], bar[2], bar[3], bar[4], 'profile', role: 'hw', solid: bar[5], notes: "generic #{@c['handle']} handle#{@c['handle'] == 'knob' ? '' : ", #{@handle_cc.to_f.round} mm hole centres"}")
        @hw['handle'] += 1
      end
    end

    # generic cut-out of a sink drawer: w wide, depth = share of the box length from the rear, each wing at least min_wing wide, box top under_top below the carcass top
    SINK_U = { w: 300.0, depth: 0.5, min_wing: 120.0, under_top: 185.0 }.freeze

    def drawers(cell, zf, hf)
      ratio = cell[:ratio] || Array.new(cell[:n] || 1, 1)
      n = ratio.size
      avail = hf - @gap * (n - 1)
      rsum = EGC::Num.sum(ratio).to_f
      zrun = zf
      drawer_spec = Config.drawer_spec(@c)
      dt = drawer_spec[:thickness]
      finish_note = drawer_spec[:finish].to_s.strip.empty? ? nil : "Drawer finish: #{drawer_spec[:finish]}"
      bw = (ix1 - ix0) - 26
      back_lim = notch_hits?(ix0 + 13, ix0 + 13 + bw) ? notch[:d] : @bk
      slide = (((@cd - back_lim - 30) / 50.0).floor * 50).clamp(250, 550)
      n.times do |i|
        fh = avail * ratio[i] / rsum
        z = zrun
        zrun += fh + @gap
        @drawer_no = (@drawer_no || 0) + 1 # numbered per cabinet: several drawer cells (e.g. the 3-drawer cutlery unit) never share a name, so each opens alone
        dasm = asm("drawer#{@drawer_no}", { 'type' => 'lin', 'v' => [0, slide * 0.9, 0] })
        @link_to = dasm.name
        # the drawer under an oven (oven towers): "open all" leaves it shut - the oven door drops down onto it (owner); a click opens it
        dasm.set_attribute('egc', 'all_skip', true) if cell[:all_skip]
        @cur = dasm.entities
        front('drawer_front', cx0 + @gap / 2.0, cw - @gap, z, fh, :top, grain: :x)
        # drawer box
        bh = [fh - 70 - (@c['handle'].to_s == 'gola' ? 16 : 0), 60.0].max # handle-free: the box stays below the profile above it
        d0 = @cd - 3 - slide
        bx = ix0 + 13
        bz = z + 25
        # U-SHAPED SINK DRAWER: the box stays under the bowl and is cut out at the rear centre, around the waste / trap / pipes
        unw = cell[:u] ? [SINK_U[:w], bw - 2 * dt - 2 * SINK_U[:min_wing]].min : 0.0
        ushape = unw >= 150
        bh = [[bh, @z0 + @hc - SINK_U[:under_top] - bz].min, 60.0].max if ushape
        travel = slide * 0.9
        if cell[:style] == :under
          runners_under(bx, bw, d0, slide, bz, travel)
        else
          runners_side(bx, d0, slide, bz + bh / 2.0 - 22, travel, ix0, ix1)
        end
        pn('drawer_side', bx, d0, bz, dt, slide, bh, 'carcass', grain: :d, eb: [1, 0], notes: finish_note)
        pn('drawer_side', bx + bw - dt, d0, bz, dt, slide, bh, 'carcass', grain: :d, eb: [1, 0], notes: finish_note)
        if ushape
          und = (slide * SINK_U[:depth]).round.to_f
          unx = bx + (bw - unw) / 2.0
          un = ['U-shaped sink drawer', finish_note].compact.join('; ')
          pn('drawer_back', bx + dt, d0, bz, unx - dt - (bx + dt), dt, bh, 'carcass', grain: :x, eb: [0, 0], notes: un)
          pn('drawer_back', unx + unw + dt, d0, bz, bx + bw - dt - (unx + unw + dt), dt, bh, 'carcass', grain: :x, eb: [0, 0], notes: un)
          pn('drawer_side', unx - dt, d0, bz, dt, und + dt, bh, 'carcass', grain: :d, eb: [1, 0], notes: "#{un}: inner wall of the cut-out")
          pn('drawer_side', unx + unw, d0, bz, dt, und + dt, bh, 'carcass', grain: :d, eb: [1, 0], notes: "#{un}: inner wall of the cut-out")
          pn('drawer_back', unx, d0 + und, bz, unw, dt, bh, 'carcass', grain: :x, eb: [1, 0], notes: "#{un}: cross wall of the cut-out")
        else
          pn('drawer_back', bx + dt, d0, bz, bw - 2 * dt, dt, bh, 'carcass', grain: :x, eb: [0, 0], notes: finish_note)
        end
        pn('drawer_subfront', bx + dt, d0 + slide - dt, bz, bw - 2 * dt, dt, bh, 'carcass', grain: :x, eb: [1, 0], notes: finish_note)
        if ushape
          bt = drawer_spec[:bottom_thickness].to_f
          a0 = unx - bx
          usolid = lambda do |ents|
            f = ents.add_face([[0, 0], [a0, 0], [a0, und], [a0 + unw, und], [a0 + unw, 0], [bw, 0], [bw, slide], [0, slide]].map { |px, pd| Geo.p3(px, pd, 0) })
            f&.pushpull((f.normal.z >= 0 ? 1 : -1) * Geo.mm(bt))
          end
          pn('drawer_bottom', bx, d0, bz + 8, bw, slide, bt, 'back', grain: :d, solid: usolid, notes: "U cut-out #{unw.round} x #{und.round} at the rear centre")
        else
          pn('drawer_bottom', bx, d0, bz + 8, bw, slide, drawer_spec[:bottom_thickness], 'back', grain: :d)
        end
        cutlery_insert(bx + dt, d0 + dt, bz + 14, bw - 2 * dt, slide - 2 * dt) if cell[:insert]
        @cur = nil
        @hw[cell[:style] == :under ? 'undermount_slide' : 'slide_pair'] += 1
        @link_to = nil
      end
    end

    # The housing remembers the EXACT appliance variant the user picked (spec[:device_id], e.g. HOB_GAS_60, COMPACT_45, DISH_45):
    # the builder of that device is used, never a guess from the cabinet type.
    APP_FAMILY = { 'oven' => %w[oven], 'microwave' => %w[microwave], 'dishwasher' => %w[dishwasher], 'washer' => %w[washer dryer],
                   'fridge' => %w[fridge], 'hob' => %w[hob hob_gas] }.freeze

    def device_for(app)
      fam = APP_FAMILY[app.to_s] || [app.to_s]
      [@s[:device_id], @s[:device_id2]].compact.each do |id|
        dv = Catalog.device(id)
        return dv if dv && fam.include?(dv[:kind].to_s)
      end
      nil
    end

    def appliance(cell, zf, hf)
      app = cell[:app].to_s
      x = @t + 2
      w = @w - 2 * @t - 4
      behind = cell[:front] ? 40 : 0 # a door in front: keep the machine (and its handle) behind it
      dv = device_for(app)
      kind = (dv || {})[:kind] || app
      dep = @cd - @bk - 20 - behind
      ah = cell[:h] - 4
      w -= WASHER_HINGE_LANE if cell[:front] && %w[washer dryer].include?(kind.to_s) # the decor door's hinge plates (right side, 44 deep) keep their lane
      if dv # the device record is the source of truth: nominal width / depth / height, centred in the opening, never stretched
        ww = [dv[:w].to_f, w].min
        x += (w - ww) / 2.0
        w = ww
        dep = [dv[:d].to_f, dep].min
        ah = [dv[:h].to_f, ah].min # nominal height of the device record (e.g. dishwasher 820): the opening may be taller, the machine is not
      end
      yb = @bk + 20
      if cell[:open] # open housing: the appliance keeps its OWN nominal size (never squeezed to the carcass depth) and sits on the floor
        raise "The refrigerator #{dv[:id]} (#{dv[:w].round} mm wide) does not fit this housing (opening #{(@w - 2 * @t).round} mm). | الثلاجة لا تدخل في هذا البيت." if dv && @w - 2 * @t + 0.01 < dv[:w].to_f
        yb = @c['fridge_back_clear'].to_f
        dep = dv ? dv[:d].to_f : dep
        ah = dv ? dv[:h].to_f : ah
        return if cell[:empty] # housing only: nothing stands in the opening

        g = Appliances.place(@cur || @e, "#{@name}_#{kind}", kind, x, yb, @z0, w, dep, ah, Catalog.dev_cfg(dv, @c))
        mark_opening(g, dv, @w - 2 * @t, @hc, @cd - yb)
        return
      end
      rim = !cell[:front] && TRIM_KINDS.include?(kind.to_s) ? TRIM_T : 0.0 # built-in oven / microwave: its front sits on a thin rim in front of the wood
      yb = @cd + rim - dep if rim > 0 # the front on the rim, even when the device is shallower than the housing
      g = Appliances.place(@cur || @e, "#{@name}_#{kind}", kind, x, yb, cell[:z0] + 2, w, dep, ah, @c)
      mark_opening(g, dv, @w - 2 * @t, cell[:h], @cd - @bk)
      trim_rim(g, x, yb, cell[:z0] + 2, w, ah, zf, hf) if rim > 0 && g.respond_to?(:entities)
      return unless cell[:front]

      if kind.to_s == 'dishwasher'
        # the decor front is fixed to the dishwasher door with brackets and drops down WITH it (no hinges, no hinge-cup boring)
        a = asm('decor_front', { 'type' => 'rot', 'pivot' => [@w / 2.0, @cd + @ft, zf], 'axis' => [1, 0, 0], 'deg' => 90, 'phase' => [0.0, 0.5] })
        in_asm(a) { front('door', @gap / 2.0, @w - @gap, zf, hf, door_pos(0, 1, false), grain: :z) }
        @hw['appliance_front_bracket'] += 2
        return
      end
      # a washer / dryer behind a decor door: the door hangs on its own hinges, opening away from the machine's round door (hinged on
      # its left), so both open without meeting - the round door is then free to open as on the stand-alone machine
      dx = @gap / 2.0
      dw = @w - @gap
      with_hand('R') do
        a = asm('door1', door_move(0, 1, dx, dw, zf, hf, false))
        in_asm(a) do
          front('door', dx, dw, zf, hf, door_pos(0, 1, false), grain: :z, hs: hinge_side(0, 1), bore_abs: hinge_abs(0, 1, dx, dw, zf, hf))
          door_hinges(0, 1, dx, dw, zf, hf)
        end
        door_plates(0, 1, dx, dw, zf, hf)
      end
      @hw['hinge'] += hinge_count(hf)
    end

    # Built-in ovens / microwaves are wider at the front than their body: the frame (TRIM_T thin) lies on the carcass front and covers
    # the side and rail edges up to the front line of the doors, the way the real fascia covers the cut-out instead of sitting inside it.
    WASHER_HINGE_LANE = 18.0 # the hinge arm stands 16 mm off the side panel and 62 deep; a 600 machine then needs a 660 unit
    TRIM_KINDS = %w[oven microwave coffee warming].freeze
    TRIM_T = 2.0
    def trim_rim(g, ax, ad, az, aw, ah, zf, hf)
      e = g.entities
      m = Appliances.pal[:steel_dk]
      ox0 = @gap / 2.0 - ax
      ox1 = @w - @gap / 2.0 - ax
      oz0 = zf - az
      oz1 = zf + hf - az
      d = @cd - ad # local depth of the carcass front line (the rim lies from here to the appliance front)
      rails = [[ox0, oz0, -ox0, oz1 - oz0], [aw, oz0, ox1 - aw, oz1 - oz0], [0, oz0, aw, -oz0], [0, ah, aw, oz1 - ah]]
      rails.each do |rx, rz, sx, sz|
        r = Appliances.box(e, rx, d, rz, sx, TRIM_T, sz, m)
        r&.name = 'trim_rim'
      end
      g.set_attribute(ATTR, 'trim_rim', TRIM_T)
    end

    # the opening the housing leaves for the appliance + the device it was built for: read by the installation drawings (never guessed there)
    def mark_opening(g, dv, ow, oh, od)
      return unless g

      g.set_attribute(ATTR, 'opening', JSON.generate({ 'w' => ow.round(1), 'h' => oh.round(1), 'd' => od.round(1) }))
      g.set_attribute(ATTR, 'dev_id', dv[:id]) if dv
      g.set_attribute(ATTR, 'dev_src', dv ? 'spec' : 'default')
    end

    def hood_cell(cell)
      w = @w - 2 * @t - 4
      g = Appliances.place(@cur || @e, "#{@name}_hood", 'hood', @t + 2, @bk + 10, cell[:z0] + 20, w, @cd - @bk - 10, cell[:h] - 40, @c)
      if g
        g.set_attribute(ATTR, 'dev_id', 'HOOD_CHIMNEY')
        g.set_attribute(ATTR, 'dev_src', 'default')
      end
    end

    # A separate plastic plinth profile, not a carcass-material board: its front face sits flush with
    # the CARCASS front (doors still stand proud of it by the front thickness). Built per-cabinet by
    # default (needed for a standalone unit); Kitchen.build_run erases and re-joins these into one
    # continuous run-level profile (Kitchen.plinth_run), split only where PLINTH_MAX_LEN requires it.
    def plinth_board
      return if @plinth <= 0 || @s[:floor]

      pn('plinth', 0, @cd - @t, 0, @w, @t, @plinth, 'plinth', grain: :x, eb: [1, 0], eb_t: 2.0)
      legs
    end

    GOLA_NOTCH = { depth: 28.0, l_h: 56.0, c_h: 73.0 }.freeze # gable cut-out for the handle channel: L profile at the top-front corner, C profile between fronts

    # Notches for the gola channels, stored on both gables for the CNC export (x from the front edge, y from the bottom of the gable).
    def gola_notches
      return if @gola_z.to_a.empty?

      lift = under_sides? ? @t : 0.0
      sb = @z0 + lift
      sh = @hc - lift
      list = @gola_z.map { |z| z.round(1) }.uniq.sort.map do |zc|
        gd = gola_dims
        if zc >= sb + sh - gd[:l_h]
          { 'type' => 'L', 'x0' => 0.0, 'x1' => gd[:l_d], 'y0' => (sh - gd[:l_h]).round(1), 'y1' => sh.round(1) }
        else
          { 'type' => 'C', 'x0' => 0.0, 'x1' => gd[:c_d], 'y0' => (zc - sb - gd[:c_h] / 2.0).round(1), 'y1' => (zc - sb + gd[:c_h] / 2.0).round(1) }
        end
      end
      list = list.select { |n| n['y0'] >= 0 && n['y1'] <= sh + 0.01 }
      @e.grep(Sketchup::Group).each do |g|
        next unless %w[side_l side_r].include?(g.get_attribute(ATTR, 'part'))

        g.set_attribute(ATTR, 'cam_notch', JSON.generate(list))
        g.set_attribute(ATTR, 'cam_notch_3d', cut_gola_notches(g, list) ? 'cut' : 'NOT CUT IN 3D')
      end
    end

    # the same cut-outs, removed from the 3D gable (through the board, at its front edge). The board's bounding size does not change.
    def cut_gola_notches(g, list)
      sd = g.get_attribute(ATTR, 'wid').to_f
      list.each do |n|
        pts = [Geo.p3(0, sd - n['x1'], n['y0']), Geo.p3(0, sd - n['x0'], n['y0']), Geo.p3(0, sd - n['x0'], n['y1']), Geo.p3(0, sd - n['x1'], n['y1'])]
        f = g.entities.add_face(pts)
        return false unless f

        f.pushpull(f.normal.x.negative? ? -Geo.mm(@t) : Geo.mm(@t))
      end
      true
    rescue StandardError
      false
    end

    # HINGE MOUNTING PLATES on the gable a door hangs on: the System 32 line - two 5 mm bores 37 mm from the front edge, 32 mm apart,
    # centred on the height of each hinge cup (the fixing pattern shared by the cruciform plates of the usual makers). Only for doors
    # whose hinge edge lies on a gable of this unit. A shelf-pin bore of the front row that would run into a plate bore is dropped.
    PLATE_SETBACK = 37.0
    PLATE_PITCH = 32.0

    def hinge_plate_bores
      marks = (@plate_marks || []).uniq
      return if marks.empty? || !%i[base wall tall].include?(@kind)

      lift = under_sides? ? @t : 0.0
      sh = @hc - lift
      { 'side_l' => marks.select { |xc, _| xc < @t + 60.0 }, 'side_r' => marks.select { |xc, _| xc > @w - @t - 60.0 } }.each do |part, list|
        side = list.empty? ? nil : @e.to_a.find { |q| q.respond_to?(:get_attribute) && q.get_attribute(ATTR, 'part').to_s == part }
        next unless side

        ys = list.flat_map { |_, zc| [zc - @z0 - lift - PLATE_PITCH / 2.0, zc - @z0 - lift + PLATE_PITCH / 2.0] }.select { |y| y.between?(8.0, sh - 8.0) }.map { |y| y.round(1) }.uniq
        next if ys.empty?

        add = ys.map { |y| { 't' => 'hinge plate', 'x' => PLATE_SETBACK, 'y' => y, 'dia' => 5, 'depth' => 12, 'ref' => 'inner face; x from front edge, y from bottom; System 32 (37 / 32) - confirm with the hinge plate' } }
        old = begin; JSON.parse(side.get_attribute(ATTR, 'bore').to_s); rescue StandardError; []; end
        old.reject! { |h| h['t'] == 'shelf pin' && (h['x'].to_f - PLATE_SETBACK).abs < 12.0 && ys.any? { |y| (h['y'].to_f - y).abs < 12.0 && (h['y'].to_f - y).abs > 0.05 } }
        old.reject! { |h| h['t'] == 'shelf pin' && (h['x'].to_f - PLATE_SETBACK).abs < 0.05 && ys.any? { |y| (h['y'].to_f - y).abs <= 0.05 } } # the same bore: kept once, as the plate bore
        side.set_attribute(ATTR, 'bore', JSON.generate(old + add))
      end
    rescue StandardError
      nil
    end

    def finish
      gola_notches
      hinge_plate_bores
      lemans_mount_bores if @lemans_mount
      @g.set_attribute(ATTR, 'cab', true)
      @g.set_attribute(ATTR, 'code', @code)
      @g.set_attribute(ATTR, 'custom_id', @s[:custom_id]) if @s[:custom_id]
      @g.set_attribute(ATTR, 'custom_name', @s[:custom_name]) if @s[:custom_name]
      @g.set_attribute(ATTR, 'kind', @kind.to_s)
      @g.set_attribute(ATTR, 'type', @s[:type].to_s)
      @g.set_attribute(ATTR, 'w', @w)
      @g.set_attribute(ATTR, 'h', @s[:h])
      @g.set_attribute(ATTR, 'd', @dd)
      @hw.each { |k, v| @hw[k] = v.round(3) if v.is_a?(Float) } # metres of profile are sums of lengths: no float noise in the lists
      @g.set_attribute(ATTR, 'hw', JSON.generate(@hw))
      @g.set_attribute(ATTR, 'spec', JSON.generate(@s))
      @g.set_attribute(ATTR, 'led', JSON.generate(@led)) if @led
      @g.set_attribute(ATTR, 'exp', JSON.generate({ 'l' => exposure(:l), 'r' => exposure(:r), 'b' => exposure(:b), 'bv' => under_visible?, 't' => exposure(:t) })) if %i[wall base tall hood].include?(@kind)
      @g.set_attribute(ATTR, 'tier', @s[:tier]) if @s[:tier]
      @g.set_attribute(ATTR, 'housing', @s[:housing]) if @s[:housing]
      if @s[:housing] == 'fridge' && !@c['fridge_clear_confirmed'] # clearances are configurable defaults, not manufacturer data
        @g.set_attribute(ATTR, 'requires', JSON.generate([{ 'code' => 'REQUIRES_CONFIRMATION', 'item' => 'fridge clearances', 'detail' => "side #{@c['fridge_side_clear']} / top #{@c['fridge_top_clear']} / back #{@c['fridge_back_clear']} mm" }]))
      end
      @g.set_attribute(ATTR, 'mech', @s[:mech].to_s) if @s[:mech]
      @g.set_attribute(ATTR, 'verification', Mechanisms.verification(@s[:mech])) if @s[:mech]
    end
  end
end
