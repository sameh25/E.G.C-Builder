# frozen_string_literal: true

require 'json'
require 'digest'

module EGC
  # CONVERSATIONAL EDITING (Arabic + English).
  # A sentence is resolved to ONE explicit, structured edit; nothing is applied until the user has seen the PREVIEW (what / why / affected units /
  # expected result) and pressed Apply. Every applied edit is a single SketchUp operation (Undo). Edits touch the normal E.G.C units: a unit-level change
  # rebuilds only the units concerned; a structural change regenerates the assistant's kitchen from its plan and says so - a kitchen with hand-made changes
  # needs an explicit confirmation before it is regenerated.
  module AssistantEdit
    module_function

    AR_DIGITS = { '٠' => '0', '١' => '1', '٢' => '2', '٣' => '3', '٤' => '4', '٥' => '5', '٦' => '6', '٧' => '7', '٨' => '8', '٩' => '9' }.freeze

    def norm(text)
      s = text.to_s.dup
      AR_DIGITS.each { |a, l| s.gsub!(a, l) }
      s.gsub!(/[ً-ْـ]/, '') # tashkeel / tatweel
      s.gsub!(/[إأآ]/, 'ا')
      s.gsub!('ى', 'ي')
      s.gsub!('ة', 'ه')
      s.downcase.strip
    end

    def to_mm(num, unit)
      v = num.to_f
      u = unit.to_s
      (u =~ /cm|سم/ ? v * 10 : (u =~ /mm|مم/ ? v : (v < 10 ? v * 1000 : (v <= 300 ? v * 10 : v)))).round(1)
    end

    UNIT = '(?:cm|mm|سم|مم)?'

    # -> { 'cmd' => symbol, ... } or nil
    def parse(text)
      t = norm(text)
      if t =~ /(?:غير|بدل|خلي|اجعل|make|change|set).{0,12}(?:الثلاجه|fridge|refrigerator).{0,20}?(?:الي|ل|to|=)\s*(\d+(?:\.\d+)?)\s*(cm|mm|سم|مم)?/
        return { 'cmd' => 'fridge_size', 'mm' => to_mm(Regexp.last_match(1), Regexp.last_match(2)) }
      end
      return { 'cmd' => 'sink_under_window' } if t =~ /(?:خلي|ضع|حط|اجعل|put|place|move).{0,12}(?:الحوض|sink).{0,12}(?:تحت|under|below).{0,8}(?:الشباك|النافذه|window)/
      return { 'cmd' => 'drawers_right_of_hob' } if t =~ /(?:زود|اضف|زوّد|add).{0,14}(?:ادراج|drawers).{0,20}(?:يمين|right).{0,14}(?:البوتاجاز|البوتجاز|الفرن|hob|cooker|stove)/
      return { 'cmd' => 'uppers_glass', 'all' => !(t =~ /كل|جميع|all|both|الدورين/).nil? } if t =~ /(?:استبدل|بدل|غير|replace|change|make).{0,12}(?:الوحدات العلويه|العلوي|upper|wall).{0,25}(?:زجاج|glass)/
      return { 'cmd' => 'no_handles' } if t =~ /(?:بدون|من غير|without|no|remove).{0,4}(?:مقابض|handles?)|handle-?less/
      if t =~ /(?:الجزيره|island).{0,20}?(\d+(?:\.\d+)?)\s*(cm|mm|سم|مم)?\s*(?:اضيق|narrower|smaller|less)/
        return { 'cmd' => 'island_narrower', 'mm' => to_mm(Regexp.last_match(1), Regexp.last_match(2)) }
      end
      if t =~ /(?:اضيق|ضيق|narrow|reduce).{0,22}?(\d+(?:\.\d+)?)\s*(cm|mm|سم|مم)?/ && t =~ /(?:الجزيره|island)/
        return { 'cmd' => 'island_narrower', 'mm' => to_mm(Regexp.last_match(1), Regexp.last_match(2)) }
      end
      if t =~ /(?:الجزيره|island).{0,20}(?:اضيق|narrower).{0,10}?(\d+(?:\.\d+)?)\s*(cm|mm|سم|مم)?/
        return { 'cmd' => 'island_narrower', 'mm' => to_mm(Regexp.last_match(1), Regexp.last_match(2)) }
      end
      nil
    end

    EXAMPLES = ['غير الثلاجة إلى 90 سم', 'خلي الحوض تحت الشباك', 'زود أدراج يمين البوتاجاز', 'استبدل الوحدات العلوية بزجاج', 'خلي الواجهة بدون مقابض', 'اعمل الجزيرة أضيق 100 مم',
                'change the fridge to 90 cm', 'put the sink under the window', 'add drawers right of the hob', 'replace the upper units with glass', 'make the fronts without handles',
                'make the island 100 mm narrower'].freeze

    # ------------------------------------------------------------------ helpers
    def kitchens(model)
      model.entities.grep(Sketchup::Group).select { |g| g.get_attribute('egc', 'assistant') }
    end

    def units_in(root)
      Exposure.collect(Sketchup.active_model)[:units].select { |u| ancestor?(u.g, root) }
    end

    def ancestor?(g, root)
      p = g.parent
      while p.respond_to?(:instances) && (i = p.instances.first)
        return true if i == root

        p = i.parent
      end
      false
    end

    # signature of what the assistant generated (unit names + specs): a difference later means somebody edited the kitchen by hand
    def signature(root)
      us = units_in(root).map do |u|
        sp = (JSON.parse(u.g.get_attribute('egc', 'spec').to_s) rescue {})
        sp.delete('exp_auto') # the exposure engine rewrites this itself; it is not a hand edit
        [u.g.name, JSON.generate(sp), u.tr.origin.to_a.map { |v| v.to_mm.round(1) }]
      end.sort_by(&:first)
      Digest::MD5.hexdigest(JSON.generate(us))
    end

    def stamp(root)
      root.set_attribute('egc', 'assistant_sig', signature(root))
    end

    def hand_edited?(root)
      (s = root.get_attribute('egc', 'assistant_sig')) && s != signature(root)
    end

    def root_params(root)
      JSON.parse(root.get_attribute('egc', 'params', '{}'))
    end

    def fridge_devices
      Catalog::DEVICES.select { |d| d[:kind] == 'fridge' && d[:h] > 1500 }
    end

    def find_col(params, type)
      (params['runs'] || {}).each do |rk, run|
        (run['cols'] || []).each_with_index { |c, i| return [rk, run, c, i] if c['t'] == type }
      end
      nil
    end

    # regenerate one kitchen from modified params (same origin / rotation), inside the caller's operation
    def regenerate(root, params, cfg)
      model = Sketchup.active_model
      fresh = Kitchen.generate(params, cfg, manage_operation: false)
      fresh.set_attribute('egc', 'assistant', true)
      fresh.set_attribute('egc', 'assistant_idx', root.get_attribute('egc', 'assistant_idx'))
      root.erase!
      Exposure.refresh(cfg, model, own_op: false)
      stamp(fresh)
      fresh
    end

    # ------------------------------------------------------------------ preview
    # -> { 'ok'=>bool, 'title', 'what', 'why', 'affected'=>[], 'expected', 'needs_confirm'=>bool, 'message' (when not ok), 'edit'=>{...} }
    # ---------------------------------------------------------------------------------------------------------------- one unit, addressed by its U-ID
    # "عدّل الوحدة 4 وخليها غسالة أطباق" / "Change Unit 4 to dishwasher" / "U04 width 800" / "unit 3 add drawer" / "mirror unit 2" / "move U05 50 mm right"
    TYPE_WORDS = [[/غساله\s*(?:ال)?اطباق|dish\s*washer/, 'dishwasher_bi'], [/غساله\s*(?:ال)?ملابس|washing\s*machine|washer/, 'washer_bi'],
                  [/بوتاجاز\s*و\s*فرن|بوتجاز\s*و\s*فرن|hob\s*(?:and|\+|&)\s*oven/, 'hob_oven'], [/بوتاجاز|بوتجاز|\bhob\b|cooktop/, 'hob'], [/فرن|\boven\b/, 'oven'],
                  [/حوض|\bsink\b/, 'sink'], [/ادراج|drawers?/, 'drawers3'], [/ضلف|\bdoors?\b|shelves/, 'doors'], [/مفتوح|\bopen\b/, 'open'], [/زجاج|glass/, 'glass'],
                  [/قلاب|\bflap\b/, 'flap'], [/دولاب\s*طويل|مخزن|pantry/, 'pantry']].freeze

    def parse_unit(text)
      code = Numbering.resolve(text)
      return nil unless code

      t = norm(text)
      num = ->(re) { m = t.match(re); m && to_mm(m[1], m[2]) }
      edit = {}
      w = num.call(/(?:عرض|عرضها|width|wide)\D{0,14}?(\d+(?:\.\d+)?)\s*(cm|mm|سم|مم)?/)
      edit['w'] = w if w
      h = num.call(/(?:ارتفاع|ارتفاعها|height|high)\D{0,14}?(\d+(?:\.\d+)?)\s*(cm|mm|سم|مم)?/)
      edit['h'] = h if h
      d = num.call(/(?:عمق|عمقها|depth|deep)\D{0,14}?(\d+(?:\.\d+)?)\s*(cm|mm|سم|مم)?/)
      edit['d'] = d if d
      if edit.empty? && (m = t.match(/(?:resize|size|مقاس)\D{0,10}(\d+)\s*[x×*]\s*(\d+)(?:\s*[x×*]\s*(\d+))?/))
        edit['w'] = m[1].to_f
        edit['h'] = m[2].to_f
        edit['d'] = m[3].to_f if m[3]
      end
      return { 'cmd' => 'unit', 'code' => code, 'op' => 'mirror' } if t =~ /mirror|اعكس|عكس|مرايه/
      if (m = t.match(/(?:move|حرك|انقل)\D{0,20}?(\d+(?:\.\d+)?)\s*(cm|mm|سم|مم)?\s*(left|right|يمين|شمال|يسار)?/))
        dx = to_mm(m[1], m[2]) * (m[3].to_s =~ /left|شمال|يسار/ ? -1 : 1)
        return { 'cmd' => 'unit', 'code' => code, 'op' => 'move', 'dx' => dx }
      end
      return { 'cmd' => 'unit', 'code' => code, 'op' => 'drawer', 'delta' => 1 } if t =~ /(?:add|زود|اضف).{0,8}(?:drawer|درج)/
      return { 'cmd' => 'unit', 'code' => code, 'op' => 'drawer', 'delta' => -1 } if t =~ /(?:remove|شيل|احذف|الغي).{0,8}(?:drawer|درج)/

      mm = t.match(/(?:mechanism|ميكانيزم)\s*[:=]?\s*([a-z][a-z_0-9]+)/i)
      edit['mech'] = mm[1].upcase if mm
      if edit.empty?
        tw = TYPE_WORDS.find { |re, _| t =~ re }
        edit['type'] = tw[1] if tw
      end
      return { 'cmd' => 'unit', 'code' => code, 'op' => 'material' } if edit.empty? && t =~ /material|خامه|لون/
      return { 'cmd' => 'unit', 'code' => code, 'op' => 'front' } if edit.empty? && t =~ /\bfront\b|واجه/
      return nil if edit.empty?

      { 'cmd' => 'unit', 'code' => code, 'op' => 'edit', 'edit' => edit }
    end

    DRAWER_STEP = { 1 => { 'doors' => 'drawer_doors', 'drawers2' => 'drawers3', 'drawers3' => 'drawers4' }, -1 => { 'drawers4' => 'drawers3', 'drawers3' => 'drawers2', 'drawer_doors' => 'doors' } }.freeze

    def preview_unit(cmd, model)
      g = Numbering.find(model, cmd['code'])
      return refuse('UNIT_NOT_FOUND', "#{cmd['code']} does not exist in this model") unless g

      cur = { 'type' => g.get_attribute('egc', 'type'), 'w' => g.get_attribute('egc', 'w'), 'h' => g.get_attribute('egc', 'h'), 'd' => g.get_attribute('egc', 'd'), 'kind' => g.get_attribute('egc', 'kind') }
      case cmd['op']
      when 'material', 'front'
        return refuse('REQUIRES_SPECIFICATION', "#{cmd['code']}: a per-unit #{cmd['op']} change is not an E.G.C unit parameter yet - set the material / front style in the project settings (it applies to every unit)")
      when 'mirror'
        edit = { 'hand' => g.get_attribute('egc', 'hand').to_s == 'R' ? 'L' : 'R' }
      when 'drawer'
        nt = DRAWER_STEP[cmd['delta']][cur['type'].to_s]
        return refuse('NOT_POSSIBLE', "#{cmd['code']} (#{cur['type']}) has no drawer variant with #{cmd['delta'].positive? ? 'one more' : 'one less'} drawer") unless nt

        edit = { 'type' => nt }
      when 'move'
        edit = nil
      else
        edit = cmd['edit']
      end
      if edit && edit['type']
        lib = cur['kind'] == 'tall' ? Library::TALL : (%w[wall hood].include?(cur['kind']) ? Library::WALL : Library::BASE)
        return refuse('TYPE_NOT_AVAILABLE', "#{cmd['code']} is a #{cur['kind']} unit: #{edit['type']} is not a #{cur['kind']} unit type") unless lib.key?(edit['type'])
      end
      what = edit ? edit.map { |k, v| "#{k} #{cur[k].is_a?(Numeric) ? cur[k].round : cur[k]} -> #{v.is_a?(Numeric) ? v.round : v}" }.join(', ') : "move #{cmd['dx'].round} mm"
      { 'ok' => true, 'what' => "#{cmd['code']}: #{what}", 'expected' => 'only this unit is rebuilt; the units to its right shift by a width change', 'title' => "#{cmd['code']}: #{what}", 'target' => { 'code' => cmd['code'], 'edit' => edit, 'dx' => cmd['dx'] }, 'affected' => [cmd['code']],
        'why' => 'unit edit addressed by its permanent ID', 'expect' => 'only this unit is rebuilt (a width change shifts the units to its right by the same amount)' }
    end

    # applies the unit edit through the same code path as Edit Unit / Quick Actions, and reports the CHANGE IMPACT from the master data
    def apply_unit(t, cfg, model)
      before = ProductionModel.capture(cfg, model)
      g = Numbering.find(model, t['code'])
      raise "#{t['code']} not found" unless g

      if t['edit']
        Kitchen.cascade_resize(g, t['edit'], cfg, manage_operation: false)
      else
        v = g.transformation.xaxis
        v.length = t['dx'].to_f.abs.mm
        v.reverse! if t['dx'].to_f.negative?
        g.transform!(Geom::Transformation.translation(v))
      end
      after = ProductionModel.capture(cfg, model)
      ProductionModel.impact(before, after, t['code'], t['edit'] ? t['edit'].to_s : "moved #{t['dx']} mm")
    end

    def preview(text, cfg, proj = nil, model = Sketchup.active_model)
      ucmd = parse_unit(text)
      return preview_unit(ucmd, model).merge('edit' => ucmd, 'text' => text) if ucmd

      cmd = parse(text)
      return { 'ok' => false, 'code' => 'NOT_UNDERSTOOD', 'message' => 'I could not resolve this sentence to a known edit.', 'examples' => EXAMPLES } unless cmd

      ks = kitchens(model)
      return { 'ok' => false, 'code' => 'NO_DESIGN', 'message' => 'There is no assistant-generated kitchen in the model yet.' } if ks.empty?

      send("prev_#{cmd['cmd']}", cmd, cfg, proj || Assistant.load(model), ks, model).merge('edit' => cmd, 'text' => text)
    end

    def refuse(code, msg, extra = {})
      { 'ok' => false, 'code' => code, 'message' => msg }.merge(extra)
    end

    def prev_fridge_size(cmd, cfg, _proj, ks, _model)
      want = cmd['mm']
      dv = fridge_devices.min_by { |d| (d[:w] - want).abs }
      return refuse('NO_SUCH_FRIDGE', "No refrigerator model in the catalogue matches #{want.round} mm.", 'options' => fridge_devices.map { |d| "#{d[:id]} #{d[:w]} mm" }) if dv.nil? || (dv[:w] - want).abs > 60

      ks.each do |root|
        pr = root_params(root)
        hit = find_col(pr, 'fridge_open')
        next unless hit

        rk, run, col, idx = hit
        new_w = Kitchen.fridge_open_min_w(cfg, dv[:id]).ceil(-1)
        delta = new_w - col['w'].to_f
        takes = [] # [[column index, mm taken]] - the door units nearest the refrigerator give width first, none below the minimum unit width
        if delta.positive?
          need = delta
          (run['cols'] || []).each_with_index.select { |c, i| i != idx && c['t'] == 'doors' }.sort_by { |_c, i| (i - idx).abs }.each do |c, i|
            give = [c['w'].to_f - AssistantDesign::STD_MIN, need].min
            next unless give > 0.5

            takes << [i, give]
            need -= give
            break if need < 0.5
          end
          return refuse('RUN_LENGTH', "The refrigerator housing grows by #{delta.round} mm but the door units can only give #{(delta - need).round} mm (none may drop below #{AssistantDesign::STD_MIN.round} mm).") if need > 0.5
        end

        edited = hand_edited?(root)
        return { 'ok' => true, 'title' => 'Change refrigerator', 'what' => "Refrigerator #{col['dev'] || 'FRIDGE_TALL'} -> #{dv[:id]} (#{dv[:w]} mm), housing #{col['w'].round} -> #{new_w} mm",
                 'why' => "you asked for a #{want.round} mm refrigerator", 'affected' => [root.name] + takes.map { |i, g| "door unit #{i + 1} gives #{g.round} mm" },
                 'expected' => 'the kitchen is regenerated from its plan with the new housing; the run length stays the same', 'needs_confirm' => edited,
                 'warning' => (edited ? 'this kitchen was edited by hand: those edits will be lost' : nil), 'target' => { 'root' => root.persistent_id, 'run' => rk, 'idx' => idx, 'dev' => dv[:id], 'w' => new_w, 'takes' => takes, 'delta' => delta } }
      end
      refuse('NO_FRIDGE_HOUSING', 'The kitchen has no refrigerator open housing.')
    end

    def apply_fridge_size(t, cfg, model)
      root = model.find_entity_by_persistent_id(t['root'])
      pr = root_params(root)
      col = pr['runs'][t['run']]['cols'][t['idx']]
      col['dev'] = t['dev']
      col['w'] = t['w']
      (t['takes'] || []).each { |i, g| c = pr['runs'][t['run']]['cols'][i]; c['w'] = (c['w'].to_f - g).round(1) }
      regenerate(root, pr, cfg)
    end

    def prev_sink_under_window(_cmd, cfg, proj, ks, _model)
      ws = Assistant.walls(proj)
      ks.each do |root|
        pr = root_params(root)
        run = (pr['runs'] || {})['a']
        next unless run

        rot = Math.atan2(root.transformation.xaxis.y, root.transformation.xaxis.x) * 180 / Math::PI
        oc = [root.transformation.origin.x.to_mm, root.transformation.origin.y.to_mm]
        cands = ws.select { |w| ((w['rot'] - rot + 540) % 360 - 180).abs < 1.0 } # the run's direction = the wall's direction
        wall = (cands.empty? ? ws : cands).min_by { |w| Assistant.dist_to_wall(w, oc) }
        win = proj['openings'].find { |o| o['type'] == 'window' && o['wall'] == wall['id'] }
        return refuse('NO_WINDOW', "There is no window on wall #{wall['id']} in the constraints.") unless win

        o0 = (Geom::Point3d.new(root.transformation.origin.x.to_mm.mm, root.transformation.origin.y.to_mm.mm, 0))
        start = (o0.x.to_mm - wall['p0'][0]) * wall['dir'][0] + (o0.y.to_mm - wall['p0'][1]) * wall['dir'][1]
        center = win['off'] + win['w'] / 2.0 - start
        fr = (run['cols'].first || {})['t'] == 'fridge_open' ? 'start' : ((run['cols'].last || {})['t'] == 'fridge_open' ? 'end' : nil)
        r = AssistantDesign.plan_columns(run['len'].to_f, cfg, { 'fridge' => fr, 'window_center' => center, 'dishwasher' => run['cols'].any? { |c| c['t'] == 'dishwasher_bi' } })
        return refuse(r['error'] || 'CANNOT_CENTRE', 'The run cannot be re-planned with the sink under the window.') if r['error']

        cols = AssistantDesign.clear_uppers_for_windows(r['cols'], proj, wall['id'], start)
        err = r['sink_error'].to_f
        edited = hand_edited?(root)
        return { 'ok' => true, 'title' => 'Sink under the window', 'what' => "re-plan run A: sink centred on window #{win['id']} (error #{err.round} mm)", 'why' => 'you asked for the sink under the window',
                 'affected' => [root.name, "#{run['cols'].size} columns"], 'expected' => "sink centre within #{err.round} mm of the window centre; run length unchanged",
                 'needs_confirm' => edited, 'warning' => (edited ? 'this kitchen was edited by hand: those edits will be lost' : nil), 'target' => { 'root' => root.persistent_id, 'cols' => cols } }
      end
      refuse('NO_RUN', 'No run A found.')
    end

    def apply_sink_under_window(t, cfg, model)
      root = model.find_entity_by_persistent_id(t['root'])
      pr = root_params(root)
      pr['runs']['a']['cols'] = t['cols']
      regenerate(root, pr, cfg)
    end

    def prev_drawers_right_of_hob(_cmd, _cfg, _proj, ks, _model)
      ks.each do |root|
        us = units_in(root).select { |u| u.kind == 'base' }.sort_by { |u| [u.tr.origin.y.round(-1), u.tr.origin.x] }
        hob = us.find { |u| u.g.get_attribute('egc', 'type').to_s =~ /hob/ }
        next unless hob

        right = us.select { |u| u.g.get_attribute('egc', 'type').to_s !~ /hob/ }.find do |u|
          (u.tr.origin - (hob.tr * Geom::Point3d.new(hob.w.mm, 0, 0))).length.to_mm < 15
        end
        return refuse('NO_RIGHT_NEIGHBOUR', 'There is no base unit directly to the right of the hob.') unless right

        typ = right.g.get_attribute('egc', 'type').to_s
        return refuse('NOT_A_DOOR_UNIT', "The unit on the right of the hob is a '#{typ}' unit, not a plain door unit; I will not replace it silently.") unless typ == 'doors'

        return { 'ok' => true, 'title' => 'Drawers right of the hob', 'what' => "#{right.g.name}: doors -> 3 drawers (same width #{right.w.round} mm)", 'why' => 'you asked for drawers to the right of the hob',
                 'affected' => [right.g.name], 'expected' => 'only that unit is rebuilt; nothing else moves', 'needs_confirm' => false, 'target' => { 'unit' => right.g.persistent_id } }
      end
      refuse('NO_HOB', 'There is no hob unit in the kitchen.')
    end

    def apply_drawers_right_of_hob(t, cfg, model)
      Kitchen.rebuild_cabinet(model.find_entity_by_persistent_id(t['unit']), { 'type' => 'drawers3' }, cfg, manage_operation: false)
    end

    def prev_uppers_glass(cmd, _cfg, _proj, ks, _model)
      tiers = cmd['all'] ? [1, 2] : [1]
      list = ks.flat_map { |r| units_in(r) }.select do |u|
        d = u.g.attribute_dictionary('egc')
        u.kind == 'wall' && d['type'].to_s == 'doors' && !d['mech'] && tiers.include?((d['tier'] || (u.g.name.end_with?('_W2') ? 2 : 1)).to_i)
      end
      return refuse('NO_UPPERS', 'There are no upper door units to change.') if list.empty?

      { 'ok' => true, 'title' => 'Glass upper doors', 'what' => "#{list.size} upper unit(s): door -> glass door", 'why' => 'you asked for glass uppers', 'affected' => list.map { |u| u.g.name },
        'expected' => cmd['all'] ? 'Upper 1 and Upper 2 get glass doors' : 'Upper 1 gets glass doors (say "all" to include Upper 2)', 'needs_confirm' => false, 'target' => { 'units' => list.map { |u| u.g.persistent_id } } }
    end

    def apply_uppers_glass(t, cfg, model)
      t['units'].each do |pid|
        g = model.find_entity_by_persistent_id(pid)
        Kitchen.rebuild_cabinet(g, { 'type' => 'glass' }, cfg, manage_operation: false) if g && g.valid?
      end
    end

    def prev_no_handles(_cmd, cfg, _proj, ks, _model)
      return refuse('ALREADY', 'The fronts already have no handles.') if cfg['handle'] == 'none'

      list = ks.flat_map { |r| units_in(r) }
      { 'ok' => true, 'title' => 'No handles', 'what' => "handle style #{cfg['handle']} -> none on #{list.size} units", 'why' => 'you asked for handle-less fronts', 'affected' => list.map { |u| u.g.name },
        'expected' => 'all fronts are rebuilt without handles / profiles; the setting is saved (it also applies to future units)', 'needs_confirm' => false, 'target' => { 'units' => list.map { |u| u.g.persistent_id } } }
    end

    def apply_no_handles(t, cfg, model)
      Config.save({ 'handle' => 'none' })
      c2 = Config.build(Config.saved)
      t['units'].each do |pid|
        g = model.find_entity_by_persistent_id(pid)
        Kitchen.rebuild_cabinet(g, {}, c2, manage_operation: false) if g && g.valid?
      end
      Exposure.refresh(c2, model, own_op: false)
    end

    def prev_island_narrower(cmd, cfg, _proj, ks, _model)
      ks.each do |root|
        pr = root_params(root)
        next unless pr['layout'] == 'island' && pr['runs']['c']

        depth = (pr['island_depth'] || cfg['base_d']).to_f
        nd = depth - cmd['mm']
        return refuse('TOO_NARROW', "An island of #{nd.round} mm is below the 300 mm minimum.") if nd < 300

        edited = hand_edited?(root)
        return { 'ok' => true, 'title' => 'Narrower island', 'what' => "island depth #{depth.round} -> #{nd.round} mm", 'why' => "you asked for the island #{cmd['mm'].round} mm narrower", 'affected' => [root.name, 'island run'],
                 'expected' => 'the island front stays where it is, the back moves toward it; the aisle in front of it is unchanged', 'needs_confirm' => edited,
                 'warning' => (edited ? 'this kitchen was edited by hand: those edits will be lost' : nil), 'target' => { 'root' => root.persistent_id, 'depth' => nd } }
      end
      refuse('NO_ISLAND', 'There is no island in the design.')
    end

    def apply_island_narrower(t, cfg, model)
      root = model.find_entity_by_persistent_id(t['root'])
      pr = root_params(root)
      pr['island_depth'] = t['depth']
      regenerate(root, pr, cfg)
    end

    # ------------------------------------------------------------------ apply (ONE operation = one Undo)
    def apply(prev, cfg, model = Sketchup.active_model, confirm: false)
      return refuse('NOT_OK', 'nothing to apply') unless prev['ok']
      return refuse('CONFIRM_REQUIRED', prev['warning'] || 'confirmation required') if prev['needs_confirm'] && !confirm

      cmd = prev['edit']['cmd']
      edited_before = kitchens(model).select { |r| hand_edited?(r) }.map(&:persistent_id) # hand-made changes made BEFORE this edit stay flagged
      model.start_operation("E.G.C Assistant: #{prev['title']}", true)
      begin
        res = send("apply_#{cmd}", prev['target'], cfg, model)
        kitchens(model).each { |r| stamp(r) unless edited_before.include?(r.persistent_id) } unless cmd == 'unit'
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      { 'ok' => true, 'title' => prev['title'], 'impact' => cmd == 'unit' ? res : nil }
    end
  end
end
