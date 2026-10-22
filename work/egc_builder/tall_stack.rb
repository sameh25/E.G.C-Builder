# frozen_string_literal: true

require 'json'

module EGC
  # Stacked tall cabinets. A tall unit whose carcass side / back would exceed the configured carcass stock length becomes TWO real
  # carcass modules (lower + upper) that assemble vertically. The split is placed on a boundary between internal cells (never through an
  # appliance opening, drawer or mechanism); fronts stay per cell, they are NOT cut at the carcass joint.
  # Data link (not naming): both module groups carry  tall_assembly / tall_role / tall_lower / tall_upper / tall_joint_z.
  module TallStack
    module_function

    # usable sheet length for a carcass part (sheet length minus both edge trims)
    def stock_limit(cfg)
      sheet = (cfg['sheets'] && cfg['sheets']['carcass']) || [cfg['sheet_l'], cfg['sheet_w']]
      sheet[0].to_f - 2 * cfg['trim'].to_f
    end

    # laid-out cells of the FULL tall unit: the SAME arithmetic as Cabinet#cells (pure, builds no geometry), absolute z in mm from the floor
    def layout(spec, cfg)
      cab = Cabinet.new(spec, cfg)
      cab.instance_variable_set(:@s, spec)
      t = cfg['thk'].to_f
      plinth = spec[:plinth].to_f
      hc = spec[:h].to_f - plinth - (spec[:kind] == :base ? cfg['top_thk'].to_f : 0.0)
      raw = spec[:cells]
      oven_i = raw.find_index { |c| c[:t] == :appliance && c[:app].to_s == 'oven' }
      if oven_i&.positive? && !spec[:no_oven_lower]
        prev = raw[oven_i - 1]
        if prev[:h]
          raw = raw.dup
          raw[oven_i - 1] = prev.merge(h: [prev[:h].to_f - Cabinet::OVEN_LOWER_MM, 50.0].max)
        else
          raw = raw[0..oven_i] + [{ t: :trim, h: Cabinet::OVEN_LOWER_MM - t }] + raw[(oven_i + 1)..]
        end
      end
      list = raw.map { |c| c[:t] == :appliance && (dv = cab.send(:device_for, c[:app])) ? c.merge(h: [dv[:h].to_f + 4, hc - 2 * t - 150].min) : c }
      n = list.size
      z_in0 = plinth + (spec[:no_bottom] ? 0 : t)
      z_in1 = plinth + hc - t
      inner = z_in1 - z_in0
      fixed = Num.sum(list) { |x| x[:h].to_f }
      free = list.count { |x| x[:h].nil? }
      rem = inner - (n - 1) * t - fixed
      each = free.positive? ? rem / free : 0
      z = z_in0
      list.each_with_index.map do |cell, i|
        ch = cell[:h] || each
        ch += rem if free.zero? && i == n - 1
        r = cell.merge(z0: z, h: ch)
        z += ch + t
        r
      end
    end

    # STANDARD SPLIT: the lower module is LOWER_H high from the floor (it carries the appliances), whatever is left up to the top line is a
    # separate upper module with its own doors. cfg 'tall_lower_h' overrides the height.
    LOWER_H = 2200.0
    MIN_UPPER = 250.0

    def lower_h(cfg)
      v = cfg['tall_lower_h'].to_f
      v.positive? ? v : LOWER_H
    end

    # tall pull-out fittings that stand on the bottom of the unit and are made for a body height of at most ~2300 mm
    # (Kesseboehmer Dispensa / Dispensa 90: body heights 1200-1600, 1600-2000, 1900-2300): above that the unit is two modules -
    # the lower one carries the fitting, the upper one is a plain door box.
    SPLIT_MECHS = %i[larder broom].freeze

    def split_mech?(spec)
      return true unless spec[:mech]

      it = Mechanisms.item(spec[:mech])
      it && SPLIT_MECHS.include?(it[:mb])
    end

    def fixed_split?(spec, cfg)
      spec[:kind] == :tall && split_mech?(spec) && !spec[:no_bottom] && !spec[:housing] && spec[:h].to_f - lower_h(cfg) >= MIN_UPPER - 0.01 &&
        lower_h(cfg) - spec[:plinth].to_f <= stock_limit(cfg) + 0.01
    end

    def needed?(spec, cfg)
      forced = spec[:force_stack] && spec[:kind] == :tall && split_mech?(spec) &&
               spec[:h].to_f - lower_h(cfg) >= MIN_UPPER - 0.01
      forced || fixed_split?(spec, cfg) || (spec[:kind] == :tall && split_mech?(spec) && (spec[:h].to_f - spec[:plinth].to_f) > stock_limit(cfg) + 0.01)
    end

    # => the same hash as #plan, or nil when the cells of the unit do not fit a lower module of that height
    def plan_fixed(spec, cfg, code)
      lh = lower_h(cfg)
      laid = layout(spec.merge(h: lh), cfg)
      return nil if laid.any? { |c| c[:h].to_f < (c[:t] == :trim ? 5 : 150) }

      cells = laid.map do |c|
        c = c.dup
        c.delete(:z0)
        c
      end
      uh = spec[:h].to_f - lh
      lower = spec.merge(code: "#{code}L", name: "#{spec[:name]}_L", h: lh, cells: cells, no_oven_lower: true, top_strip: nil)
      upper = spec.merge(code: "#{code}U", name: "#{spec[:name]}_U", h: uh, plinth: 0.0, cells: [{ t: :doors, shelves: uh > 450 ? 1 : 0 }], no_oven_lower: true, no_oven_below: true)
      if spec[:mech] # the fitting stays in the lower module; the upper one is a door box
        upper = upper.reject { |k, _| %i[mech mech_n].include?(k) }.merge(type: 'doors')
      end
      { lower: lower, upper: upper, joint_z: lh, assembly: code }
    end

    # => { lower:, upper:, joint_z:, assembly:, boundary: } or raises TALL_SPLIT_ERROR
    def plan(spec, cfg, code)
      limit = stock_limit(cfg)
      t = cfg['thk'].to_f
      laid = layout(spec, cfg)
      best = nil
      (0...(laid.size - 1)).each do |i|
        zs = laid[i][:z0] + laid[i][:h] + t # lower module top (carries its own top board)
        h_l = zs
        h_u = spec[:h].to_f - zs
        next if h_l - spec[:plinth].to_f > limit || h_u > limit || h_u < 3 * t + 100 || h_l < spec[:plinth].to_f + 3 * t + 100

        score = (h_l - h_u).abs
        best = { i: i, zs: zs, h_l: h_l, h_u: h_u, score: score } if best.nil? || score < best[:score]
      end
      unless best
        raise "TALL_SPLIT_ERROR: tall unit #{code} (#{spec[:h].round} mm) cannot be split between internal cells within the #{limit.round} mm carcass stock; " \
              'add an internal cell boundary (e.g. a drawer / appliance / door zone) or reduce the unit height.'
      end
      clean = lambda do |c|
        c = c.dup
        c.delete(:z0)
        c
      end
      low_cells = laid[0..best[:i]].map { |c| clean.call(c) }
      up_cells = laid[(best[:i] + 1)..].map { |c| clean.call(c) }
      up_cells.last.delete(:h) if up_cells.last # the last (free) upper cell absorbs the remainder
      lower = spec.merge(code: "#{code}L", h: best[:h_l], cells: low_cells, no_oven_lower: true, top_strip: nil)
      upper = spec.merge(code: "#{code}U", name: "#{spec[:name]}_U", h: best[:h_u], plinth: 0.0, cells: up_cells, no_oven_lower: true, no_oven_below: true)
      lower[:name] = "#{spec[:name]}_L"
      { lower: lower, upper: upper, joint_z: best[:zs], assembly: code }
    end

    # Builds the unit (single carcass or two stacked modules) inside `ents`; returns the array of module groups (lower first).
    def build(ents, spec, cfg)
      code = spec[:code] || Cabinet.new(spec, cfg).send(:derive_code, spec[:name])
      return [Cabinet.build(ents, spec, cfg)] unless needed?(spec, cfg)

      pl = ((fixed_split?(spec, cfg) || spec[:force_stack]) && plan_fixed(spec, cfg, code)) || plan(spec, cfg, code)
      lo = Cabinet.build(ents, pl[:lower], cfg)
      up = Cabinet.build(ents, pl[:upper], cfg)
      up.transform!(Geom::Transformation.translation(Geom::Vector3d.new(0, 0, Geo.mm(pl[:joint_z]))))
      [[lo, 'lower'], [up, 'upper']].each do |g, role|
        g.set_attribute('egc', 'tall_assembly', code)
        g.set_attribute('egc', 'tall_role', role)
        g.set_attribute('egc', 'tall_lower', "#{code}L")
        g.set_attribute('egc', 'tall_upper', "#{code}U")
        g.set_attribute('egc', 'tall_joint_z', pl[:joint_z])
        g.set_attribute('egc', 'tall_total_h', spec[:h].to_f)
      end
      [lo, up]
    end

    # assemblies present in the model: { code => { lower: g, upper: g } }
    def assemblies(groups)
      out = {}
      groups.each do |g|
        a = g.get_attribute('egc', 'tall_assembly')
        next unless a

        (out[a] ||= {})[g.get_attribute('egc', 'tall_role').to_sym] = g
      end
      out
    end
  end
end
