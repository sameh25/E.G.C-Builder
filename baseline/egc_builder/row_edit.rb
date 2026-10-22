# frozen_string_literal: true

require 'digest'

module EGC
  # Shared implementation behind Kitchen.cascade_resize: dialog, Replace and drag
  # resize use the same operation, neighbor movement and persistence contract.
  module RowEdit
    module_function

    def upper?(g)
      %w[wall hood].include?(g.get_attribute('egc', 'kind').to_s) ||
        (g.get_attribute('egc', 'part') == 'filler' && g.name.match?(/_w[12]_filler\z/))
    end

    # A kind edit (base -> tall ...) is a family conversion, not a height edit:
    # the upper column keeps its own Z and the slab is re-planned around the
    # tower instead of travelling with the unit.
    def conversion_edit?(g, edit)
      return false unless edit.is_a?(Hash) && edit['kind']

      edit['kind'].to_s != g.get_attribute('egc', 'kind').to_s
    end

    def members(g)
      g.parent.entities.grep(Sketchup::Group).select do |q|
        q.get_attribute('egc', 'spec') || q.get_attribute('egc', 'role') == 'appliance' || q.get_attribute('egc', 'part') == 'filler'
      end
    end

    def peers(g)
      [{ g: g, x0: 0.0, w: g.get_attribute('egc', 'w').to_f }] +
        Kitchen.x_aligned(g, members(g).reject { |q| q == g })
    end

    # Explicit row-selection command only. Applying an edit never substitutes a
    # different target behind the form's back.
    def choose(g, scope)
      raise 'Invalid row scope' unless %w[upper lower both].include?(scope)
      return g if scope == 'both' || upper?(g) == (scope == 'upper')

      peers(g).find do |p|
        p[:g].get_attribute('egc', 'spec') && upper?(p[:g]) == (scope == 'upper') &&
          p[:x0].abs < 1 && (p[:w] - g.get_attribute('egc', 'w').to_f).abs < 2
      end&.fetch(:g)
    end

    def apply(g, edit, cfg, scope: 'both')
      raise 'Invalid row scope' unless %w[upper lower both].include?(scope)
      if scope != 'both' && upper?(g) != (scope == 'upper')
        raise 'Selection changed. Select the intended row again before applying dimensions.'
      end
      owner = Kitchen.find_owner_group(g)
      run = owner if owner && owner.get_attribute('egc', 'run') && !owner.get_attribute('egc', 'worktop_wrap')
      old_w = g.get_attribute('egc', 'w').to_f
      new_w = edit['w'].to_f.positive? ? edit['w'].to_f : old_w
      delta = new_w - old_w
      old_h = g.get_attribute('egc', 'h').to_f
      new_h = edit['h'].to_f.positive? ? edit['h'].to_f : old_h
      height_delta = new_h - old_h
      old_x = g.transformation.origin.x.to_mm
      pool = peers(g).select { |p| scope == 'both' || upper?(p[:g]) == (scope == 'upper') }
      targets = [g]
      if delta.abs >= 0.01
        targets = pool.select { |p| p[:g].get_attribute('egc', 'spec') && p[:x0].abs < 1 && (p[:w] - old_w).abs < 2 }.map { |p| p[:g] }
        axis = Snap.world_of(g).xaxis
        pool.select { |p| p[:x0] >= old_w - 1 }.each do |p|
          Snap.move_world(p[:g], Geom::Transformation.translation(Snap.scaled(axis, delta.mm)))
        end
      end
      # A changed lower height moves the upper column as one dependency.  The
      # worktop/fillers are regenerated below, after the new lower geometry is
      # known, rather than leaving the old vertical coordinates in place.
      if height_delta.abs >= 0.01 && !upper?(g) && !conversion_edit?(g, edit)
        pool.select { |p| upper?(p[:g]) && p[:x0].abs < 1.0 && (p[:w] - old_w).abs < 2.0 }.each do |p|
          Snap.move_world(p[:g], Geom::Transformation.translation(Geom::Vector3d.new(0, 0, height_delta.mm)))
        end
      end
      fresh = targets.map do |q|
        Kitchen.rebuild_cabinet(q, q == g ? edit : { 'w' => new_w }, cfg,
                                manage_operation: false, skip_exposure: true, refresh_geometry: false)
      end
      if run
        if scope == 'both' && delta.abs >= 0.01
          old_len = run.get_attribute('egc', 'len').to_f
          run.entities.grep(Sketchup::Group).select do |p|
            p.get_attribute('egc', 'part') == 'end_panel' && p.transformation.origin.x.to_mm >= old_len - 1
          end.each { |p| p.transform!(Geom::Transformation.translation([delta.mm, 0, 0])) }
          Kitchen.sync_resized_column(run, old_x, old_w, new_w)
        end
        refresh_run(run, cfg)
      else
        fresh.select { |q| Kitchen.base_kind?(q) }.each do |q|
          Kitchen.refresh_worktop_after_edit(q, cfg)
          Kitchen.refresh_plinth_after_edit(q, cfg)
        end
      end
      Exposure.refresh(cfg, Sketchup.active_model, own_op: false)
      capture(run, cfg) if run
      Sketchup.active_model.selection.clear
      fresh.select(&:valid?).each { |q| Sketchup.active_model.selection.add(q) }
      fresh
    end

    def refresh_run(run, cfg)
      all = run.entities.grep(Sketchup::Group)
      units = all.select { |q| q.get_attribute('egc', 'spec') || q.get_attribute('egc', 'role') == 'appliance' }
      # Filler pieces may be direct run children rather than cabinet specs.
      spans = units.map do |q|
        q.transformation.origin.x.to_mm - q.get_attribute('egc', 'slot_inset_x', 0).to_f +
          q.get_attribute('egc', 'slot_w', q.get_attribute('egc', 'w', q.definition.bounds.width.to_mm)).to_f
      end
      spans.concat(all.select { |q| q.get_attribute('egc', 'part') == 'filler' }.map { |q| q.bounds.max.x.to_mm })
      len = spans.max || run.get_attribute('egc', 'len').to_f
      run.set_attribute('egc', 'len', len)
      fascias = all.select { |q| q.get_attribute('egc', 'part') == 'fascia' }
      unless fascias.empty?
        fascias.each(&:erase!)
        Kitchen.fascia(run.entities, run.name + '_fascia', len, cfg, Config.top_line(cfg))
      end
      bases = units.select { |q| Kitchen.base_kind?(q) }
      refresh_tops(run, bases, cfg)
      # Recreate the same baseline plinth geometry only after all placements are
      # final. This also restores lone eligible cabinets after a chain splits.
      all.select { |q| q.valid? && q.get_attribute('egc', 'part') == 'plinth' }.each(&:erase!)
      bases.each do |q|
        spec = Cabinet.spec_from_json(q.get_attribute('egc', 'spec'))
        q.entities.grep(Sketchup::Group).select { |p| p.get_attribute('egc', 'part') == 'plinth' }.each(&:erase!)
        next unless spec[:plinth].to_f.positive? && !spec[:floor]

        # Exact baseline Cabinet#plinth_board board parameters; existing legs and
        # hardware remain on the cabinet. Do not build a second cabinet/assembly.
        t = cfg['thk'].to_f
        Panel.add(q.entities, spec[:name], 'plinth', 0,
                  spec[:d].to_f - cfg['front_thk'].to_f - t, 0,
                  spec[:w].to_f, t, spec[:plinth].to_f, 'plinth', cfg,
                  grain: :x, eb: [1, 0], eb_t: 2.0, code: q.get_attribute('egc', 'code'))
      end
      Kitchen.join_plinth_run(run.entities, run.name, cfg) unless run.get_attribute('egc', 'island')
    end

    def refresh_tops(run, bases, cfg)
      # Keep the established special corner builder. Straight spans include the
      # full reserved appliance/filler slot, not only the wooden cabinets.
      if bases.any? { |q| Kitchen.corner_unit?(q) }
        bases.each { |q| Kitchen.rebuild_local_countertop(q, cfg) }
        return
      end
      all = run.entities.grep(Sketchup::Group)
      return unless all.any? { |q| q.get_attribute('egc', 'part') == 'countertop' }
      # Towers (tall kind OR a base converted to tall via `converted_from_code`)
      # can NEVER push the marble: dropping them here stops the worktop from
      # spanning a fridge-/pantry-/oven-tower column inside a generated run.
      supported = all.select do |q|
        k = q.get_attribute('egc', 'kind').to_s
        next false if k == 'tall' || %w[wall hood].include?(k)
        next false if q.get_attribute('egc', 'converted_from_code')
        next false if q.get_attribute('egc', 'slot_under') &&
          (bases.none? { |b| b.transformation.origin.x.to_mm <= q.transformation.origin.x.to_mm + 1.0 &&
                           (b.transformation.origin.x.to_mm + b.get_attribute('egc', 'w', 0).to_f) >= q.transformation.origin.x.to_mm - 1.0 })
        bases.include?(q) || q.get_attribute('egc', 'slot_under') ||
          (q.get_attribute('egc', 'part') == 'filler' && !upper?(q))
      end.map do |q|
        x = q.transformation.origin.x.to_mm - q.get_attribute('egc', 'slot_inset_x', 0).to_f
        w = q.get_attribute('egc', 'slot_w', q.get_attribute('egc', 'w', q.definition.bounds.width.to_mm)).to_f
        {g:q,x:x,finish:x+w}
      end.sort_by { |p| p[:x] }
      spans = []
      supported.each do |p|
        if spans.empty? || (spans.last.last[:finish] - p[:x]).abs > 1
          spans << [p]
        else
          spans.last << p
        end
      end
      Kitchen.erase_top_pieces(run.entities, -1_000_000, 1_000_000)
      spans.each_with_index do |span, i|
        holes = span.filter_map { |p| Kitchen.cutout_for(p[:g], cfg) if bases.include?(p[:g]) }
        options = run.get_attribute('egc', 'island') ? {back:cfg['island_overhang'].to_f} : {}
        Kitchen.countertop(run.entities, "#{run.name}_top_r#{i}",
                           {start:span.first[:x],end:span.last[:finish],holes:holes},
                           cfg.merge('base_h'=>Kitchen.slab_reference_h(span.map { |p| p[:g] }, cfg)), span.drop(1).map { |p| p[:x] }, options)
      end
    end

    def canonical(value)
      case value
      when Hash then value.keys.sort.to_h { |k| [k, canonical(value[k])] }
      when Array then value.map { |v| canonical(v) }
      else value
      end
    end

    def signature(params, run_name, cfg)
      dims = %w[ceiling plinth base_h top_thk top_overhang base_d gap_h w1_h w1_d hood_d hood_open_h w2_enabled w2_h w2_d fascia_thk thk back_thk front_thk gap drawer_thk]
      plan = params.reject { |k, _| %w[row_state row_overrides origin rot runs].include?(k) }
      plan['run'] = (params['runs'] || {})[run_name.downcase]
      Digest::SHA256.hexdigest(JSON.generate(canonical([plan, cfg.slice(*dims)])))
    end

    def capture(run, cfg)
      root = Kitchen.find_owner_group(run)
      return unless root && root.get_attribute('egc', 'kitchen')

      params = JSON.parse(root.get_attribute('egc', 'params', '{}'))
      params.delete('row_overrides')
      params['row_state'] ||= {}
      records = run.entities.grep(Sketchup::Group).filter_map do |q|
        next unless q.get_attribute('egc', 'spec') || q.get_attribute('egc', 'role') == 'appliance' || q.get_attribute('egc', 'part') == 'filler'

        { 'code' => q.get_attribute('egc', 'code'), 'name' => q.name,
          'spec' => q.get_attribute('egc', 'spec'), 'transform' => q.transformation.to_a }
      end
      params['row_state'][run.name] = { 'schema' => 1, 'signature' => signature(params, run.name, cfg), 'records' => records }
      root.set_attribute('egc', 'params', JSON.generate(params))
    end

    def restore(root, params, cfg)
      states = params['row_state'] || {}
      states.keys.each do |name|
        state = states[name]
        unless state['schema'] == 1 && state['signature'] == signature(params, name, cfg)
          states.delete(name) # the explicitly changed plan/dimensions win
          next
        end
        run = root.entities.grep(Sketchup::Group).find { |q| q.name == name && q.get_attribute('egc', 'run') }
        next unless run

        pool = run.entities.grep(Sketchup::Group)
        state['records'].each do |r|
          q = pool.find { |p| p.valid? && (r['code'] ? p.get_attribute('egc', 'code') == r['code'] : p.name == r['name']) }
          next unless q

          if r['spec']
            replacement = Cabinet.build(run.entities, Cabinet.spec_from_json(r['spec']), cfg)
            q.erase!
            q = replacement
          end
          q.transformation = Geom::Transformation.new(r['transform'])
        end
        refresh_run(run, cfg)
      end
      params.delete('row_overrides')
      root.set_attribute('egc', 'params', JSON.generate(params))
    end
  end
end
