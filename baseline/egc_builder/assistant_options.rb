# frozen_string_literal: true

module EGC
  # What the configured AI provider can really do. Nothing here pretends to understand images: a plan/sketch is
  # only ever read by a registered vision-capable provider; otherwise the user traces + scales it by hand
  # (those values are then INFERRED until confirmed) and the dialog says a vision provider is required.
  module AssistantProviders
    module_function

    @providers = {}

    # register(name, vision: true, analyze: ->(path, proj) { { 'detected' => {...} } })
    def register(name, vision: false, analyze: nil)
      @providers[name.to_s] = { 'name' => name.to_s, 'vision' => vision && analyze ? true : false, 'analyze' => analyze }
    end

    def vision_provider
      @providers.values.find { |p| p['vision'] }
    end

    def capabilities
      vp = vision_provider
      { 'vision' => !vp.nil?, 'provider' => vp && vp['name'], 'registered' => @providers.keys,
        'status' => vp ? 'VISION_AVAILABLE' : 'VISION_PROVIDER_REQUIRED',
        'note' => vp ? nil : 'No vision-capable AI provider is configured: plan/image analysis is NOT performed. Trace and scale the image manually (values stay INFERRED until confirmed).' }
    end

    # Detected values are tagged DETECTED and never promoted to confirmed automatically.
    def analyze_image(path, proj)
      vp = vision_provider
      return { 'ok' => false, 'code' => 'VISION_PROVIDER_REQUIRED', 'message' => capabilities['note'] } unless vp

      r = vp['analyze'].call(path, proj)
      { 'ok' => true, 'provider' => vp['name'], 'status' => 'DETECTED', 'detected' => r['detected'] }
    end
  end

  # A / B / C design proposals built from the SAME planner the generator uses (no geometry is created here).
  # Appliances are the standard generic E.G.C profiles unless the user override says otherwise.
  module AssistantOptions
    module_function

    STANDARD = %w[standard_refrigerator standard_dishwasher standard_oven standard_hob standard_hood standard_sink].freeze

    VARIANTS = [
      { 'id' => 'A', 'label' => 'Refrigerator at the start', 'opts' => { 'fridge_side' => 'start' } },
      { 'id' => 'B', 'label' => 'Refrigerator at the end', 'opts' => { 'fridge_side' => 'end' } },
      { 'id' => 'C', 'label' => 'Compact: no dishwasher', 'opts' => { 'fridge_side' => 'start', 'dishwasher' => false } }
    ].freeze

    LAYOUT_NAMES = { 'straight' => 'one wall', 'L' => 'L (left corner)', 'L_right' => 'L (right corner)', 'U' => 'U', 'parallel' => 'two parallel runs', 'island' => 'run + island' }.freeze

    # deterministic candidates: every layout the room allows x refrigerator at either end x with / without dishwasher. Each is planned with the same
    # rules the builder uses, scored (Proposals.score) and drawn; the three best DIFFERENT buildable designs become A / B / C. No randomness.
    def candidates(proj, base_opts)
      wanted = base_opts.slice('layout', 'fridge_side', 'dishwasher').reject { |k, v| v.nil? || (k == 'layout' && v.to_s == 'auto') }
      layouts = wanted['layout'] ? [wanted['layout']] : %w[auto straight L L_right U parallel island]
      sides = wanted['fridge_side'] ? [wanted['fridge_side']] : %w[start end]
      dws = wanted.key?('dishwasher') ? [wanted['dishwasher']] : [true, false]
      list = []
      if base_opts['mode'] == 'ai' && proj['vision'] && proj['vision']['design']
        list << [{ 'from_vision' => true }, 'AI: the client design image, fitted to the real wall']
      end
      layouts.product(sides, dws).each { |l, sd, dw| list << [{ 'layout' => l, 'fridge_side' => sd, 'dishwasher' => dw }, nil] }
      [list, wanted]
    end

    def build(proj, cfg, base_opts = {})
      mode = base_opts['mode'] == 'ai' ? 'ai' : 'standard'
      rm = proj['room_model']
      if rm.is_a?(Hash) && rm['ready'] == false
        return { 'options' => [], 'mode' => mode, 'considered' => 0, 'rejected' => [],
                 'note' => 'ROOM_MODEL_INCOMPLETE: detected room measurements are missing or require confirmation.',
                 'room_status' => rm['status'], 'room_pending' => Array(rm['pending']), 'room_questions' => Array(rm['questions']) }
      end

      list, wanted = candidates(proj, base_opts.merge('mode' => mode))
      seen = {}
      scored = []
      rejected = []
      list.each do |o, label|
        opts = base_opts.reject { |k, _| %w[mode layout fridge_side dishwasher].include?(k) }.merge(o)
        plan = AssistantDesign.propose(proj, cfg, opts)
        next if plan['kitchens'].empty?

        runs = plan['kitchens'].map { |k| k['params']['runs'].transform_values { |r| { 'len' => r['len'], 'cols' => r['cols'].map { |c| [c['t'], c['w'].to_f.round] } } } }
        sig = JSON.generate([plan['layout'], runs])
        next if seen[sig]

        seen[sig] = true
        sc = Proposals.score(proj, plan, cfg, opts, wanted)
        # ENGINEERING VALIDATION of the solved layout: a candidate with an overlap, a unit outside the room, a bad corner, a floating unit, a duplicate
        # position or something in front of an opening is never shown - the next solved candidate takes its place
        val = Proposals.validate(proj, plan, sc['units'], cfg)
        unless val['ok']
          rejected << "#{opts['layout']}/#{opts['fridge_side']}: #{val['checks'].select { |c| c['result'] == 'FAIL' }.map { |c| "#{c['code']} (#{c['detail']})" }.join(', ')}"
          next
        end
        buildable = plan['problems'].none? { |p| (p['severity'] || 'error') == 'error' }
        scored << { opts: opts, plan: plan, sc: sc, buildable: buildable, label: label, runs: runs, ai: o['from_vision'] == true }
      end
      # buildable designs first, the AI design (when asked for) always shown, then by score
      ranked = scored.sort_by { |x| [x[:buildable] ? 0 : 1, x[:ai] ? 0 : 1, -x[:sc]['total']] }
      pick = []
      # the best design of every DIFFERENT layout the room allows comes first (straight / L / U / parallel / island), then variants of the same layout
      ranked.each { |x| pick << x if pick.size < 3 && x[:buildable] && pick.none? { |p| p[:plan]['layout'] == x[:plan]['layout'] } }
      ranked.each do |x|
        break if pick.size >= 3
        next if pick.include?(x)
        next if pick.any? { |p| p[:plan]['layout'] == x[:plan]['layout'] && p[:opts]['fridge_side'] == x[:opts]['fridge_side'] } && ranked.count { |r| r[:buildable] } > 3

        pick << x
      end
      ranked.each { |x| pick << x if pick.size < 3 && !pick.include?(x) }
      pick.sort_by! { |x| ranked.index(x) }
      # where the refrigerator really stands in the solved plan (on an L / U it may be at the far end of a side run)
      fridge_at = lambda do |x|
        x[:plan]['kitchens'].each do |k|
          k['params']['runs'].each do |rid, r|
            real = r['cols'].reject { |c| c['t'] == 'filler' }
            i = real.index { |c| c['t'] == 'fridge_open' } or next
            return rid == 'a' ? (i.zero? ? 'start' : 'end') : 'end of the side run'
          end
        end
        x[:opts]['fridge_side'] || 'start'
      end
      sm = Assistant.summary(proj, 'en')
      open_items = sm['lines'].select { |l| l[:st] != Assistant::CONFIRMED }.map { |l| "#{l[:label]}: #{l[:value]} (#{l[:st]})" }
      best = pick.map { |x| x[:sc]['total'] }.max
      out = pick.each_with_index.map do |x, i|
        p = x[:sc]['parts']
        top = p.max_by { |_, v| v }
        reason = if i.zero? then "highest score (#{x[:sc]['total']}/100): strongest on #{top[0]} (#{top[1]})"
                 else "alternative (#{x[:sc]['total']}/100, #{best - x[:sc]['total']} below the best): #{p.select { |k, v| v > (pick[0][:sc]['parts'][k] || 0) }.keys.join(', ').then { |t| t.empty? ? 'a different arrangement' : "better on #{t}" }}"
                 end
        lay = x[:plan]['layout']
        { 'id' => %w[A B C][i], 'label' => x[:label] || "#{LAYOUT_NAMES[x[:opts]['layout'].to_s] || LAYOUT_NAMES[lay] || lay}, refrigerator at the #{fridge_at.call(x)}#{x[:opts]['dishwasher'] == false ? ', no dishwasher' : ''}",
          'mode' => x[:ai] ? 'ai' : 'standard', 'opts' => x[:opts], 'layout' => lay, 'runs' => x[:runs], 'score' => x[:sc]['total'], 'scores' => p, 'why' => [reason] + x[:sc]['why'],
          'preview' => Proposals.preview(proj, x[:plan], cfg, x[:sc]), 'problems' => x[:plan]['problems'], 'assumptions' => x[:plan]['notes'],
          'appliances' => STANDARD.reject { |a| a == 'standard_dishwasher' && x[:opts]['dishwasher'] == false },
          'unresolved' => x[:plan]['problems'].map { |q| q['message'] } + open_items + ['Appliance manufacturer / model not selected: generic family profiles are used (REQUIRES MODEL CONFIRMATION)'],
          'buildable' => x[:buildable], 'temporary' => true }
      end
      note = mode == 'ai' && !(proj['vision'] && proj['vision']['design']) ? 'AI DESIGN: no design image has been read by the AI provider yet - the proposals below come from the standard rules.' : nil
      { 'options' => out, 'mode' => mode, 'considered' => scored.size, 'rejected' => rejected, 'note' => note, 'provider' => AssistantProviders.capabilities }
    end

    # one proposal re-planned with the user's edits (opts['edits']): still a temporary preview, nothing is built; accepting it builds exactly this.
    def edit(proj, cfg, opts, id)
      rm = proj['room_model']
      raise 'ROOM_MODEL_INCOMPLETE: confirm the detected room measurements before editing a design proposal.' if rm.is_a?(Hash) && rm['ready'] == false

      plan = AssistantDesign.propose(proj, cfg, opts)
      raise 'PROPOSAL_EMPTY: the edited proposal has no units' if plan['kitchens'].empty?

      sc = Proposals.score(proj, plan, cfg, opts, {})
      runs = plan['kitchens'].map { |k| k['params']['runs'].transform_values { |r| { 'len' => r['len'], 'cols' => r['cols'].map { |c| [c['t'], c['w'].to_f.round] } } } }
      ed = plan['notes'].grep(/\Aedited: /)
      { 'id' => id.to_s, 'label' => "#{id} - edited (#{ed.size} change#{ed.size == 1 ? '' : 's'})", 'mode' => opts['from_vision'] ? 'ai' : 'standard', 'opts' => opts, 'layout' => plan['layout'],
        'runs' => runs, 'score' => sc['total'], 'scores' => sc['parts'], 'why' => ed + sc['why'], 'preview' => Proposals.preview(proj, plan, cfg, sc),
        'problems' => plan['problems'], 'assumptions' => plan['notes'], 'appliances' => STANDARD.reject { |a| a == 'standard_dishwasher' && opts['dishwasher'] == false },
        'unresolved' => plan['problems'].map { |q| q['message'] } + ['Appliance manufacturer / model not selected: generic family profiles are used (REQUIRES MODEL CONFIRMATION)'],
        'buildable' => plan['problems'].none? { |p| (p['severity'] || 'error') == 'error' } && Proposals.validate(proj, plan, sc['units'], cfg)['ok'], 'temporary' => true, 'edited' => true }
    end
  end
end
