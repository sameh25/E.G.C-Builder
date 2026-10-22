# frozen_string_literal: true

require 'json'

module EGC
  # AUTOMATIC KITCHEN DESIGN from the constraint model.
  #
  # It only ever uses the normal E.G.C library: the design is a PLAN (layout + runs + columns) handed to Kitchen.generate, so every unit afterwards is
  # an ordinary E.G.C unit (select / move / resize / Add Left / Add Right / replace / rebuild / production / cost). Nothing here builds geometry itself.
  #
  # Rules used (all visible in the returned plan 'notes'):
  #   * the main wall is the longest wall whose FREE length (doors, columns and no-build zones removed) can hold a kitchen
  #   * layouts: straight | L | U | parallel | island - only when the room really allows it (never forced)
  #   * refrigerator open housing at the end away from a corner, sink centred under a window when there is one, hob + oven cabinet never touching the
  #     sink, dishwasher next to the sink, doors only where a real standard-width unit fits (no absurd 100 mm cabinets), fillers for the last few mm
  #   * uppers are dropped in front of a window / door span
  module AssistantDesign
    module_function

    STD_MIN = 250.0       # mm: narrowest cabinet the assistant will create (a 250 mm bottle pull-out is standard; nothing smaller)
    DOOR_CLEAR = 50.0     # mm kept free on both sides of a door span
    MIN_RUN = 1800.0      # mm: shortest run worth generating
    ISLAND_MIN_DEPTH = 3600.0
    AISLE_MIN = 900.0

    # ------------------------------------------------------------------ free length of a wall
    def blockers(proj, wall_id)
      out = []
      proj['openings'].each { |o| out << [o['off'] - DOOR_CLEAR, o['off'] + o['w'] + DOOR_CLEAR, 'door'] if o['wall'] == wall_id && o['type'] == 'door' }
      proj['columns'].each { |c| out << [c['off'], c['off'] + c['w'], 'column'] if c['wall'] == wall_id }
      proj['no_build'].each { |n| out << [n['off'], n['off'] + n['w'], 'no_build'] if n['wall'] == wall_id }
      out.sort_by(&:first)
    end

    # -> [[a, b], ...] free stretches of the wall (mm from its start)
    def free_segments(proj, wall)
      segs = []
      pos = 0.0
      blockers(proj, wall['id']).each do |a, b, _k|
        segs << [pos, a] if a - pos > 1
        pos = [pos, b].max
      end
      segs << [pos, wall['len']] if wall['len'] - pos > 1
      segs
    end

    def free_from_start(proj, wall)
      s = free_segments(proj, wall).find { |a, _b| a <= 1 }
      s ? s[1] : 0.0
    end

    def free_to_end(proj, wall)
      s = free_segments(proj, wall).find { |_a, b| (b - wall['len']).abs <= 1 }
      s ? wall['len'] - s[0] : 0.0
    end

    def windows_in(proj, wall_id, a, b)
      proj['openings'].select { |o| o['wall'] == wall_id && o['type'] == 'window' && o['off'] + o['w'] > a && o['off'] < b }
    end

    # ------------------------------------------------------------------ columns of one run
    def fridge_width(cfg, dev = nil)
      Kitchen.fridge_open_min_w(cfg, dev).ceil(-1)
    end

    # Fit a plain cabinet run without manufacturing a tiny filler just because the
    # preferred nominal width was 600 mm. A normal plain unit may absorb real
    # available width up to 900 mm; only a remainder below STD_MIN becomes a filler.
    # Examples: 650 -> one 650 unit, 900 -> one 900 unit, 1200 -> two 600 units.
    def fill_cols(x, type = 'doors')
      return [] if x < 1

      return [{ 't' => 'filler', 'w' => x.round(1) }] if x < STD_MIN

      n = (x / 900.0).ceil
      w = ((x / n) / 5.0).floor * 5.0
      w = STD_MIN if w < STD_MIN
      cols = Array.new(n) { { 't' => type, 'w' => w } }
      cols.last['w'] = (cols.last['w'] + (x - n * w)).round(1)
      cols
    end

    # opts: 'fridge' => nil | 'start' | 'end', 'dev' => fridge device, 'sink' => bool, 'sink_w', 'dishwasher' => bool, 'hob' => bool, 'drawers' => bool,
    #       'window_center' => mm from the run start (sink centred there)
    # ---- hard layout rules (mm, measured between cabinet edges along the run) ----
    HOB_SINK_MIN = 600.0   # clear worktop between the hob unit and the sink unit
    HOB_TALL_MIN = 400.0   # hob unit to a tall unit (fridge housing, tower) or to the wall the run ends at
    FRIDGE_WALL_GAP = 0.0  # no filler beside the refrigerator housing: the appliances keep their sizes and the cabinets of the run take up the difference
    CORNER_FILLER = 50.0   # corner post on each run that meets another run
    CORNER_UNIT_W = 900.0  # L-shaped corner base at the meeting point of two runs
    TALL_TYPES = %w[fridge_open pantry oven_tall oven_tower].freeze
    RULE_TEXT = { 'HOB_SINK_CLEARANCE' => "hob to sink: %d mm of worktop (minimum #{HOB_SINK_MIN.round})", 'HOB_TALL_CLEARANCE' => "hob to tall unit: %d mm (minimum #{HOB_TALL_MIN.round})",
                  'HOB_WALL_CLEARANCE' => "hob to the side wall: %d mm (minimum #{HOB_TALL_MIN.round})" }.freeze

    def hob_type?(t)
      t.to_s.include?('hob')
    end

    # seq = [[type, width], ...] of ONE run in order. Returns [[code, measured mm], ...] for every broken rule.
    def ergonomics(seq, start_wall: true, end_wall: true)
      out = []
      x = 0.0
      pos = seq.map { |t, w| r = [t.to_s, x, x + w.to_f]; x += w.to_f; r }
      total = x
      pos.select { |t, _, _| hob_type?(t) }.each do |_t, h0, h1|
        pos.each do |t, a0, a1|
          gap = [a0 - h1, h0 - a1].max
          next if gap < -0.5

          out << ['HOB_SINK_CLEARANCE', gap.round] if t.start_with?('sink') && gap < HOB_SINK_MIN - 0.5
          out << ['HOB_TALL_CLEARANCE', gap.round] if TALL_TYPES.include?(t) && gap < HOB_TALL_MIN - 0.5
        end
        out << ['HOB_WALL_CLEARANCE', h0.round] if start_wall && h0 < HOB_TALL_MIN - 0.5
        out << ['HOB_WALL_CLEARANCE', (total - h1).round] if end_wall && total - h1 < HOB_TALL_MIN - 0.5
      end
      out
    end

    # work flow of ONE run (soft preferences, never against a hard rule): store -> wash -> cook, i.e. the sink stands between the refrigerator and the
    # hob; a hob never stands in front of a window (its hood cannot hang there). seq as in ergonomics; x0 = where seq starts on the run.
    FLOW_ORDER = 100.0
    FLOW_HOB_WINDOW = 250.0 # below the 300 mm the sink may stand off its plumbing point
    def flow_penalty(seq, win = nil, x0 = 0.0)
      x = x0
      pos = seq.map { |t, w| r = [t.to_s, x, x + w.to_f]; x += w.to_f; r }
      mid = ->(r) { r && (r[1] + r[2]) / 2.0 }
      f = mid.call(pos.find { |t, _, _| t == 'fridge_open' })
      s = mid.call(pos.find { |t, _, _| t.start_with?('sink') })
      hr = pos.find { |t, _, _| hob_type?(t) }
      h = mid.call(hr)
      pen = 0.0
      pen += FLOW_ORDER if f && s && h && !s.between?(*[f, h].minmax)
      pen += FLOW_HOB_WINDOW if win && hr && [hr[2], win[1]].min - [hr[1], win[0]].max > 1.0
      pen
    end

    def rule_problems(viol, where)
      viol.uniq.map { |code, mm| { 'code' => code, 'severity' => 'error', 'message' => "#{where}: #{format(RULE_TEXT[code], mm)}" } }
    end

    # opts: 'fridge' => nil | 'start' | 'end', 'dev' => fridge device, 'sink' => bool, 'sink_w', 'dishwasher' => bool, 'hob' => bool, 'drawers' => bool,
    #       'window_center' => mm from the run start (sink centred there; a confirmed drain point is passed the same way),
    #       'start_wall' / 'end_wall' => false when that end of the run meets another run instead of a wall, 'fridge_wall' => true when the refrigerator end stands against a wall
    def plan_columns(len, cfg, o = {})
      fr = o['fridge']
      fw = fr ? fridge_width(cfg, o['dev']) : 0.0
      fgap = fr && o['fridge_wall'] ? FRIDGE_WALL_GAP : 0.0
      has_sink = o['sink'] != false
      sw = (o['sink_w'] || 800).to_f
      dwc = o['dishwasher'] ? 600.0 : 0.0
      hob = o['hob'] != false
      drw = o['drawers'] != false
      fixed_items = []
      fixed_items << ['drawers3', 600.0] if drw
      fixed_items << ['hob_oven', 600.0] if hob
      usable = len - fw - fgap
      lead = fr == 'start' ? fw + fgap : 0.0 # the sink position is measured from the run start
      sw_start = o['start_wall'] != false
      sw_end = o['end_wall'] != false
      head = fr == 'start' ? [['fridge_open', fw]] : []
      tail = fr == 'end' ? [['fridge_open', fw]] : []
      judge = ->(body) { ergonomics(head + body + tail, start_wall: sw_start && head.empty?, end_wall: sw_end && tail.empty?) }
      flow = ->(body) { flow_penalty(head + body + tail, o['window_span'], fr == 'start' ? fgap : 0.0) }
      expand = ->(items) { items.flat_map { |t, w| t == :fill ? fill_cols(w).map { |c| [c['t'], c['w']] } : [[t, w]] } }
      wrap = lambda do |body|
        cols = body.map { |t, w| { 't' => t, 'w' => w } }
        fc = fr ? fridge_col(fw, o) : nil
        gap = fgap.positive? ? [{ 't' => 'filler', 'w' => fgap }] : []
        fr == 'start' ? gap + [fc] + cols : (fr == 'end' ? cols + [fc] + gap : cols)
      end
      unless has_sink
        rest = usable - EGC::Num.sum(fixed_items) { |_t, w| w }
        return { 'cols' => [], 'error' => 'RUN_TOO_SHORT' } if rest < -1

        items = fixed_items + (rest > 0.5 ? [[:fill, rest]] : [])
        best = items.permutation.each_with_index.map { |pm, i| body = expand.call(pm); v = judge.call(body); [v.size * 3000 + flow.call(body) + i * 0.01, body, v] }.min_by(&:first)
        return { 'cols' => wrap.call(best[1]), 'notes' => [], 'rules' => best[2] }
      end
      best = nil
      # where do drawers / hob-oven go (before or after the sink), on which side of the sink is the dishwasher, and in which order do the units of each
      # side stand (the filling cabinets may go between the hob and the sink, or out to the end of the run) - the hard rules decide
      variants = [[fixed_items, []], [fixed_items[0, 1], fixed_items[1..] || []], [fixed_items[1..] || [], fixed_items[0, 1]], [[], fixed_items]].uniq
      rank = 0
      variants.each do |left0, right0|
        (dwc.positive? ? %i[right left] : %i[none]).each do |dws|
          left = left0.map(&:dup)
          right = right0.map(&:dup)
          fl = EGC::Num.sum(left) { |_t, w| w }
          fright = EGC::Num.sum(right) { |_t, w| w }
          free = usable - fl - fright - sw - dwc
          next if free < -1

          dl = dws == :left ? dwc : 0.0
          want0 = o['window_center'] ? o['window_center'] - lead - fl - dl - sw / 2.0 : free / 2.0
          [want0, free, 0.0, free / 2.0].uniq.each_with_index do |want, wi|
          left = left0.map(&:dup)
          right = right0.map(&:dup)
          fl = EGC::Num.sum(left) { |_t, w| w }
          fright = EGC::Num.sum(right) { |_t, w| w }
          lf = [[want, 0].max, free].min
          di = left.rindex { |t, _| t == 'drawers3' }
          if lf > 0.5 && lf < STD_MIN && di
            # a leftover below the minimum unit width widens a DRAWER unit (max +300) instead of making a tiny cabinet
            left[di][1] += lf
            fl += lf
            alloc = lf
            lf = 0.0
          else
            lf = snap_fill(lf, free)
            alloc = lf
          end
          rf = free - alloc
          rf = 0.0 if rf < 1
          if rf > 1 && rf < STD_MIN
            di = right.rindex { |t, _| t == 'drawers3' }
            next unless di

            right[di][1] += rf
            fright += rf
            rf = 0.0
          end
          center = lead + fl + dl + lf + sw / 2.0
          err = o['window_center'] ? (center - o['window_center']).abs : 0
          li = left + (lf > 0.5 ? [[:fill, lf]] : [])
          ri = right + (rf > 0.5 ? [[:fill, rf]] : [])
          li.permutation.each do |pl|
            ri.permutation.each do |pr|
              body = expand.call(pl)
              body << ['dishwasher_bi', dwc] if dws == :left
              body << ['sink', sw]
              body << ['dishwasher_bi', dwc] if dws == :right
              body += expand.call(pr)
              viol = judge.call(body)
              rank += 1
              cand = { err: err + viol.size * 3000 + flow.call(body) + rank * 0.001 + (o['window_center'] ? 0 : wi * 2.0), body: body, viol: viol, sink_err: err }
              best = cand if best.nil? || cand[:err] < best[:err]
            end
          end
          end
        end
      end
      return { 'cols' => [], 'error' => 'RUN_TOO_SHORT' } unless best

      notes = []
      notes << "sink centred on its target (error #{best[:sink_err].round} mm)" if o['window_center']
      { 'cols' => wrap.call(best[:body]), 'notes' => notes, 'sink_error' => best[:sink_err], 'rules' => best[:viol] }
    end

    # plan the main run; when the full appliance set does not fit, the dishwasher and then the drawer unit are dropped (noted), never the rules
    def plan_main(len, cfg, o, notes)
      r = plan_columns(len, cfg, o)
      [['dishwasher', 'dishwasher left out: the run is too short for it'], ['drawers', 'drawer unit left out: the run is too short for it']].each do |key, msg|
        break unless r['error'] || r['rules'].to_a.any?
        next if o[key] == false

        o2 = o.merge(key => false)
        r2 = plan_columns(len, cfg, o2)
        next if r2['error'] || (r['error'].nil? && r2['rules'].to_a.size >= r['rules'].to_a.size)

        o = o2
        r = r2
        notes << msg
      end
      r
    end

    def snap_fill(x, free)
      return 0.0 if x < 1
      return free if free - x < 1

      if x < STD_MIN
        x = x < STD_MIN / 2 ? 0.0 : STD_MIN
      end
      x
    end

    def fridge_col(fw, o)
      c = { 't' => 'fridge_open', 'w' => fw }
      c['dev'] = o['dev'] if o['dev']
      c
    end

    # every column that stands in front of a window gets no uppers (the window stays free)
    def clear_uppers_for_windows(cols, proj, wall_id, seg_start)
      x = seg_start
      cols.each do |c|
        x1 = x + c['w'].to_f
        if windows_in(proj, wall_id, x, x1).any? { |o| o['sill'] < 2700 }
          c['w1'] = 'none'
          c['w2'] = 'none'
        end
        x = x1
      end
      cols
    end

    # ------------------------------------------------------------------ layout choice
    def adjacent(ws, w, dir)
      i = ws.index { |x| x['id'] == w['id'] }
      ws[(i + (dir == :next ? 1 : -1)) % ws.size]
    end

    def perpendicular?(a, b)
      (a['dir'][0] * b['dir'][0] + a['dir'][1] * b['dir'][1]).abs < 0.02
    end

    def opposite(ws, w)
      ws.find { |x| x['id'] != w['id'] && (x['dir'][0] * w['dir'][0] + x['dir'][1] * w['dir'][1]) < -0.98 }
    end

    # perpendicular distance between wall w and the parallel wall o (room between)
    def gap(w, o)
      nx = w['dir'][1]
      ny = -w['dir'][0] # room side = right of the direction
      ((o['p0'][0] - w['p0'][0]) * nx + (o['p0'][1] - w['p0'][1]) * ny).abs
    end

    # how much of a wall's END is taken by an obstacle on the PERPENDICULAR wall that meets it there (a door swing or a column near the corner)
    def end_trim(proj, ws, wall, which, cfg)
      nb = adjacent(ws, wall, which == :start ? :prev : :next)
      return 0.0 unless perpendicular?(wall, nb)

      base_d = cfg['base_d'].to_f
      trim = 0.0
      near = lambda { |off, w| which == :start ? nb['len'] - (off + w) : off } # distance of the obstacle's nearest edge from the shared corner
      proj['openings'].each { |o| trim = [trim, o['w'] + 100].max if o['wall'] == nb['id'] && o['type'] == 'door' && near.call(o['off'], o['w']) < base_d + 50 }
      proj['columns'].each { |c| trim = [trim, c['d'] + 10].max if c['wall'] == nb['id'] && near.call(c['off'], c['w']) < base_d + 20 }
      trim
    end

    # the same trim for the FAR end of a perpendicular run (its other corner)
    def far_trim(proj, ws, wall, which, cfg)
      end_trim(proj, ws, wall, which, cfg)
    end

    # best free stretch of a wall for a run: [a, b]. start_corner: the run starts AT the wall start (another run attaches there); open ends lose the trim.
    def usable(proj, ws, wall, cfg, start_corner: false, end_corner: false)
      segs = free_segments(proj, wall).map do |a, b|
        a += end_trim(proj, ws, wall, :start, cfg) if a <= 1 && !start_corner
        b -= end_trim(proj, ws, wall, :end, cfg) if b >= wall['len'] - 1 && !end_corner
        [a, b]
      end.select { |a, b| b - a > 1 }
      segs = segs.select { |a, _b| a <= 1 } if start_corner
      segs.max_by { |a, b| b - a }
    end

    # -> { 'layout', 'notes' => [...], 'problems' => [...], 'kitchens' => [ { 'wall', 'origin', 'rot', 'params' } ] }
    # the planner's design + the user's edits of the PROPOSAL (opts['edits'], before anything is built). generate calls the same function with the
    # same opts, so the built units are exactly the edited proposal.
    def propose(proj, cfg, opts = {})
      rm = proj['room_model']
      if rm.is_a?(Hash) && rm['ready'] == false
        return { 'layout' => nil, 'kitchens' => [], 'notes' => [],
                 'problems' => [{ 'code' => 'ROOM_MODEL_INCOMPLETE', 'severity' => 'error',
                                  'message' => "detected room measurements need confirmation: #{Array(rm['pending']).join(' | ')}" }] }
      end

      plan = propose_rules(proj, cfg, opts)
      apply_edits(plan, proj, cfg, opts['edits']) if opts['edits'].is_a?(Array) && opts['edits'].any? && plan['kitchens'].any?
      plan
    end

    STORAGE_TYPES = %w[doors drawers2 drawers3 drawers4 open].freeze

    # edits = [{ 'id' => 'U04', 'w' => 800 } | { 'id' => 'U04', 't' => 'drawers3' }]. A width change is taken from / given to a filler of the same run
    # (the run length never changes); an appliance width comes from its profile and is not edited here; a type change is limited to storage types.
    # An edit that cannot be applied is a blocking problem, never a silent change.
    def apply_edits(plan, proj, cfg, edits)
      plan['kitchens'] = Marshal.load(Marshal.dump(plan['kitchens']))
      us = Proposals.units(plan, cfg)
      touched = {}
      edits.each do |e|
        id = e['id'].to_s.upcase
        u = us.find { |x| x['n'] && Proposals.code(x['n']) == id }
        bad = ->(code, m) { plan['problems'] << { 'code' => code, 'severity' => 'error', 'message' => "#{id}: #{m}" } }
        next bad.call('EDIT_UNKNOWN_UNIT', 'no such unit in this proposal') unless u

        cols = plan['kitchens'][u['k']]['params']['runs'][u['run'].downcase]['cols']
        touched[[u['k'], u['run'].downcase]] = cols
        col = cols[u['idx']]
        if e['t']
          t = e['t'].to_s
          next bad.call('EDIT_TYPE', "#{col['t']} -> #{t}: only storage types (#{STORAGE_TYPES.join(', ')}) can replace a storage unit here; appliances are changed after building (REQUIRES MODEL CONFIRMATION)") unless STORAGE_TYPES.include?(t) && STORAGE_TYPES.include?(col['t'])

          plan['notes'] << "edited: #{id} #{col['t']} -> #{t}"
          col['t'] = t
        end
        next unless e['w']

        w = e['w'].to_f
        next bad.call('EDIT_APPLIANCE_WIDTH', "#{col['t']} width comes from the appliance profile (REQUIRES MODEL CONFIRMATION)") if Proposals::APPS[col['t']] || col['t'] == 'corner_l'
        next bad.call('EDIT_WIDTH_RANGE', "#{w.round} mm is outside 150 - 1200 mm") unless w.between?(150, 1200)

        dw = w - col['w'].to_f
        fill = cols.each_index.select { |i| cols[i]['t'] == 'filler' && cols[i]['w'].to_f - dw >= 0 }.max_by { |i| cols[i]['w'].to_f }
        if !fill && dw <= -0.5 && cols.none? { |c| c['t'] == 'filler' } # narrower and no filler in the run: the freed width becomes one
          cols.insert(u['idx'] + 1, { 't' => 'filler', 'w' => 0.0 })
          fill = u['idx'] + 1
        end
        next bad.call('EDIT_NO_ROOM', "#{col['w'].to_f.round} -> #{w.round} mm needs #{dw.round} mm more than the run's fillers have; narrow a neighbour first") unless fill || dw.abs < 0.5

        plan['notes'] << "edited: #{id} width #{col['w'].to_f.round} -> #{w.round} mm (filler #{cols[fill]['w'].to_f.round} -> #{(cols[fill]['w'].to_f - dw).round} mm)" if fill
        cols[fill]['w'] = (cols[fill]['w'].to_f - dw).round(1) if fill
        col['w'] = w
        cols.delete_at(fill) if fill && cols[fill]['w'].to_f < 0.5
        us = Proposals.units(plan, cfg)
      end
      # the layout rules are checked again on every edited run (hob - sink, hob - tall); the built design is validated in full afterwards
      ws = Assistant.walls(proj)
      touched.each do |(ki, rk), cols| # the main-wall run keeps the planner's window rule: no upper unit in front of a window
        k = plan['kitchens'][ki]
        w = ws.find { |x| x['id'] == k['wall'] }
        next unless rk == 'a' && w

        clear_uppers_for_windows(cols, proj, w['id'], (k['origin'][0] - w['p0'][0]) * w['dir'][0] + (k['origin'][1] - w['p0'][1]) * w['dir'][1])
      end
      touched.each { |(_, rk), cols| plan['problems'].concat(rule_problems(ergonomics(cols.map { |c| [c['t'], c['w']] }, start_wall: false, end_wall: false), "edited run #{rk.upcase}")) }
      plan
    end

    def propose_rules(proj, cfg, opts = {})
      ws = Assistant.walls(proj)
      notes = []
      problems = []
      return { 'layout' => nil, 'problems' => [{ 'code' => 'NO_ROOM', 'message' => 'no room walls yet' }], 'kitchens' => [], 'notes' => notes } if ws.size < 3

      base_d = cfg['base_d'].to_f
      want = (opts['layout'] || 'auto').to_s
      cl = proj['room']['ceiling']['v']
      if cl && cl.to_f < Config.top_line(cfg) - 0.5
        problems << { 'code' => 'CEILING_LOW', 'severity' => 'error', 'message' => "ceiling #{cl.to_f.round} mm is below the top of the two upper tiers (#{Config.top_line(cfg).round} mm)" }
      end
      # DESIGN IMAGE: the ordered units the vision provider read are fitted to the real wall (straight runs); other layouts only steer the planner
      vd = opts['from_vision'] && proj['vision'] && proj['vision']['design']
      if vd && vd['units'].to_a.any?
        return vision_straight(proj, cfg, ws, vd, notes, problems) if vd['layout'] == 'straight'

        opts = opts.merge('layout' => vd['layout']) if (opts['layout'] || 'auto').to_s == 'auto'
        notes << "design image: #{vd['layout']} layout followed; unit-by-unit matching is only done for straight runs"
      end
      # main wall: the wall with the best USABLE stretch (free of doors / columns, minus what the perpendicular walls take at open ends); a window or a
      # confirmed water point on a wall counts in its favour (the sink goes there). opts['wall'] forces one.
      score = lambda do |w|
        seg = usable(proj, ws, w, cfg)
        len = seg ? seg[1] - seg[0] : 0.0
        bonus = 0.0
        bonus += 1200 if seg && windows_in(proj, w['id'], seg[0], seg[1]).any?
        bonus += 800 if proj['services'].any? { |s| s['wall'] == w['id'] && s['kind'] == 'water_cold' }
        [len + bonus, len]
      end
      main = opts['wall'] ? ws.find { |w| w['id'] == opts['wall'] } : ws.max_by { |w| score.call(w)[0] }
      seg_open = usable(proj, ws, main, cfg)
      seg_corner = usable(proj, ws, main, cfg, start_corner: true)
      free_a = seg_corner ? seg_corner[1] : 0.0
      if free_a < MIN_RUN
        if seg_open.nil? || seg_open[1] - seg_open[0] < MIN_RUN
          problems << { 'code' => 'RUN_TOO_SHORT', 'severity' => 'error', 'message' => "no wall has a free stretch of #{MIN_RUN.round} mm for the kitchen (best: wall #{main['id']}, #{seg_open ? (seg_open[1] - seg_open[0]).round : 0} mm)" }
        end
        seg_open ||= [0.0, 0.0]
        a0 = seg_open[0]
        len = seg_open[1] - seg_open[0]
        return { 'layout' => 'straight', 'kitchens' => straight_only(proj, cfg, main, a0, len, opts, notes, problems), 'notes' => notes, 'problems' => problems }
      end
      prev = adjacent(ws, main, :prev)
      nxt = adjacent(ws, main, :next)
      free_prev = perpendicular?(main, prev) ? free_to_end(proj, prev) - base_d - far_trim(proj, ws, prev, :start, cfg) : 0.0
      free_next = perpendicular?(main, nxt) ? free_from_start(proj, nxt) - base_d - far_trim(proj, ws, nxt, :end, cfg) : 0.0
      opp = opposite(ws, main)
      depth = opp ? gap(main, opp) : nil
      layout = want
      if layout == 'auto'
        layout = if free_prev >= 1200 && free_next >= 1200 && free_a >= 2400 then 'U'
                 elsif free_prev >= 1200 && free_a >= 2400 then 'L'
                 elsif free_next >= 1200 && free_a >= 2400 then 'L_right'
                 else 'straight'
                 end
      end
      layout = 'straight' if layout == 'island' && !(depth && depth >= ISLAND_MIN_DEPTH)
      if layout == 'U' && (free_prev < 1200 || free_next < 1200)
        layout = free_prev >= 1200 ? 'L' : (free_next >= 1200 ? 'L_right' : 'straight')
      end
      layout = 'straight' if (layout == 'L' && free_prev < 1200) || (layout == 'L_right' && free_next < 1200)
      layout = 'straight' if layout == 'parallel' && (opp.nil? || free_from_start(proj, opp) < MIN_RUN)
      layout = 'L' if layout == 'U' && (free_a - main['len']).abs > 1 && free_prev >= 1200 # a U needs both corners of the main wall
      layout = 'straight' if %w[U L_right].include?(layout) && (free_a - main['len']).abs > 1
      notes << "layout #{layout} chosen for wall #{main['id']} (free #{free_a.round} mm)"
      kitchens = case layout
                 when 'U' then build_u(proj, cfg, main, prev, nxt, free_a, free_prev, free_next, opts, notes, problems)
                 when 'L' then build_l(proj, cfg, main, prev, free_a, free_prev, :left, opts, notes, problems)
                 when 'L_right' then build_l(proj, cfg, main, nxt, free_a, free_next, :right, opts, notes, problems)
                 when 'parallel' then build_parallel(proj, cfg, main, opp, free_a, depth, opts, notes, problems)
                 when 'island' then build_island(proj, cfg, main, opp, free_a, depth, opts, notes, problems)
                 else straight_only(proj, cfg, main, seg_open[0], seg_open[1] - seg_open[0], opts, notes, problems)
                 end
      { 'layout' => layout.sub('_right', ''), 'kitchens' => kitchens, 'notes' => notes, 'problems' => problems }
    end

    def vision_straight(proj, cfg, ws, vd, notes, problems)
      wall = ws.find { |w| w['id'] == proj['vision']['wall'] } || ws.max_by { |w| s = usable(proj, ws, w, cfg); s ? s[1] - s[0] : 0.0 }
      seg = free_segments(proj, wall).max_by { |a, b| b - a } # the run takes the whole free stretch of that wall, as drawn in the design
      if seg.nil? || seg[1] - seg[0] < MIN_RUN
        problems << { 'code' => 'RUN_TOO_SHORT', 'severity' => 'error', 'message' => "wall #{wall['id']} has no free stretch of #{MIN_RUN.round} mm" }
        return { 'layout' => 'straight', 'kitchens' => [], 'notes' => notes, 'problems' => problems }
      end
      len = (seg[1] - seg[0]).floor(-1).to_f
      r = AssistantVision.fit(vd['units'], len, cfg)
      notes.concat(r['notes'])
      problems.concat(r['problems'])
      return { 'layout' => 'straight', 'kitchens' => [], 'notes' => notes, 'problems' => problems } if r['cols'].empty?

      cols = clear_uppers_for_windows(r['cols'], proj, wall['id'], seg[0])
      # a design that was copied from the client's image is built as drawn; broken layout rules are reported, not silently rearranged
      problems.concat(rule_problems(ergonomics(cols.map { |c| [c['t'], c['w']] }, start_wall: seg[0] <= 1, end_wall: seg[0] + len >= wall['len'] - 1), 'design image').map { |p| p.merge('severity' => 'warn') })
      { 'layout' => 'straight', 'notes' => notes, 'problems' => problems, 'as_drawn' => true,
        'kitchens' => [kitchen(wall, seg[0], { 'layout' => 'straight', 'runs' => { 'a' => { 'len' => len.round(1), 'cols' => cols } } })] }
    end

    # allowed: the run ends a refrigerator may stand at. It never stands between units: an end that meets another run (a corner) is not allowed.
    def main_opts(proj, wall, seg_a, len, opts, fridge_at, allowed = %w[start end])
      fridge_at = opts['fridge_side'] if allowed.include?(opts['fridge_side'])
      o = { 'fridge' => opts['fridge'] == false ? nil : fridge_at, 'dev' => opts['fridge_dev'], 'dishwasher' => opts['dishwasher'] != false, 'sink' => true,
            'hob' => true, 'drawers' => true }
      win = windows_in(proj, wall['id'], seg_a, seg_a + len).first
      o['window_center'] = win['off'] + win['w'] / 2.0 - seg_a if win
      o['window_span'] = [win['off'] - seg_a, win['off'] + win['w'] - seg_a] if win
      pl = %w[drain water_cold].flat_map { |k| proj['services'].select { |sv| sv['kind'] == k && sv['wall'] == wall['id'] && sv['off'].to_f.between?(seg_a, seg_a + len) } }.first
      if pl # plumbing rough-in: the sink goes over it
        o['window_center'] = pl['off'].to_f - seg_a
        o['sink_anchor'] = 'plumbing'
      end
      o
    end

    def straight_only(proj, cfg, wall, seg_a, len, opts, notes, problems = [])
      o = main_opts(proj, wall, seg_a, len, opts, 'start')
      solid_at = ->(x) { x <= 1 || x >= wall['len'] - 1 || proj['columns'].any? { |c| c['wall'] == wall['id'] && ((c['off'] + c['w'] - x).abs < 2 || (c['off'] - x).abs < 2) } } # a wall or a column, not a door side
      o['fridge_wall'] = o['fridge'] == 'start' ? solid_at.call(seg_a) : (o['fridge'] == 'end' && solid_at.call(seg_a + len))
      o['start_wall'] = solid_at.call(seg_a)
      o['end_wall'] = solid_at.call(seg_a + len)
      r = plan_main(len, cfg, o, notes)
      if r['error']
        problems << { 'code' => r['error'], 'severity' => 'error', 'message' => "run #{len.round} mm cannot hold the standard appliances (fridge + drawers + hob + sink#{o['dishwasher'] ? ' + dishwasher' : ''})" }
        return []
      end
      cols = clear_uppers_for_windows(r['cols'], proj, wall['id'], seg_a)
      notes.concat(r['notes'] || [])
      problems.concat(rule_problems(r['rules'].to_a, "wall #{wall['id']}"))
      sink_check(r, o, problems)
      [kitchen(wall, seg_a, { 'layout' => 'straight', 'runs' => { 'a' => { 'len' => len.round(1), 'cols' => cols } } })]
    end

    def ws_of(proj)
      Assistant.walls(proj)
    end

    def kitchen(wall, seg_a, params)
      o = Assistant.wall_point(wall, seg_a)
      { 'wall' => wall['id'], 'origin' => [o[0].round(2), o[1].round(2), 0.0], 'rot' => wall['rot'], 'params' => params }
    end

    # a side run of plain cabinets. corner: the run starts at another run (a CORNER_FILLER post comes first); wall_end: its far end stands against a wall
    def plain_run(len, cfg, first: nil, corner: false, wall_end: false)
      lead = corner ? CORNER_FILLER : 0.0
      return { 'len' => len.round(1), 'cols' => [] } if len - lead < STD_MIN

      rest = len - lead
      tailc = []
      if first == 'fridge_end'
        fw = fridge_width(cfg)
        tailc << { 't' => 'fridge_open', 'w' => fw }
        tailc << { 't' => 'filler', 'w' => FRIDGE_WALL_GAP } if wall_end && FRIDGE_WALL_GAP.positive?
        rest -= EGC::Num.sum(tailc) { |c| c['w'] }
      end
      return { 'len' => len.round(1), 'cols' => [] } if rest < STD_MIN

      cols = fill_cols(rest, 'doors')
      cols[cols.size / 2]['t'] = 'drawers3' if cols.size >= 3 && cols[cols.size / 2]['t'] == 'doors'
      cols = [{ 't' => 'filler', 'w' => lead }] + cols if corner
      { 'len' => len.round(1), 'cols' => cols + tailc }
    end

    # the sink must sit within 300 mm of the plumbing point it was aimed at
    def sink_check(r, o, problems)
      return unless o['sink_anchor'] == 'plumbing' && r['sink_error'].to_f > 300

      problems << { 'code' => 'SINK_OFF_PLUMBING', 'severity' => 'warn', 'message' => "the sink centre is #{r['sink_error'].round} mm from the drain / water point (limit 300 mm)" }
    end

    # main run of an L / U: an L-shaped corner base + a corner post at every end that meets a side run, the appliances planned on the rest
    def corner_main(proj, cfg, main, free_a, opts, fr, corners, notes, problems)
      take = CORNER_UNIT_W + CORNER_FILLER
      lead = corners.include?(:start) ? take : 0.0
      len = free_a - lead - (corners.include?(:end) ? take : 0.0)
      o = main_opts(proj, main, lead, len, opts, fr, fr ? [fr] : [])
      o['start_wall'] = !corners.include?(:start)
      o['end_wall'] = !corners.include?(:end)
      o['fridge_wall'] = fr == 'end' ? free_a >= main['len'] - 1 : (fr == 'start')
      r = plan_main(len, cfg, o, notes)
      return nil if r['error']

      problems.concat(rule_problems(r['rules'].to_a, "wall #{main['id']}"))
      sink_check(r, o, problems)
      notes.concat(r['notes'] || [])
      cols = r['cols']
      cols = [{ 't' => 'corner_l', 'w' => CORNER_UNIT_W }, { 't' => 'filler', 'w' => CORNER_FILLER }] + cols if corners.include?(:start)
      cols += [{ 't' => 'filler', 'w' => CORNER_FILLER }, { 't' => 'corner_l', 'w' => CORNER_UNIT_W }] if corners.include?(:end)
      clear_uppers_for_windows(cols, proj, main['id'], 0.0)
      # UPPER CORNER: a blind corner wall unit + a unit on the side wall replace the one straight wall unit over the corner base (which leaves the side
      # wall above the corner empty). Not where a window stands at the corner, on either wall.
      ws = ws_of(proj)
      zone = take
      corners.each do |cn|
        col = cn == :start ? cols.first : cols.last
        side = adjacent(ws, main, cn == :start ? :prev : :next)
        clear = cn == :start ? windows_in(proj, side['id'], side['len'] - zone, side['len']).empty? : windows_in(proj, side['id'], 0.0, zone).empty?
        next unless col['w1'] != 'none' && clear

        col.merge!('cu' => true, 'w1' => 'none', 'w2' => 'none')
      end
      cols
    end

    # the corner unit keeps its plain upper when there is no side run to return onto
    def plain_corner_upper(col)
      return unless col && col.delete('cu')

      col.delete('w1')
      col.delete('w2')
    end

    # a side run that carries the refrigerator at its far end, or nil when it does not fit there
    def side_run(len, cfg, fridge, wall_end)
      r = plain_run(len, cfg, first: fridge ? 'fridge_end' : nil, corner: true, wall_end: wall_end)
      fridge && r['cols'].none? { |c| c['t'] == 'fridge_open' } ? nil : r
    end

    # length left for a side run once the corner base (deeper than a plain base) takes its place on the side wall
    def side_len(free_side, cfg)
      (free_side - (CORNER_UNIT_W - cfg['base_d'].to_f)).floor(-1).to_f
    end

    def build_l(proj, cfg, main, side, free_a, free_side, l_side, opts, notes, problems)
      # fridge at the far end of the main run (the corner is at its start for a left L, at its end for a right L)
      # the refrigerator stands at a free END of a run, never beside the corner: the far end of the main run, or (the other variant) the far end of the side run
      far = l_side == :left ? 'end' : 'start'
      fr = opts['fridge'] == false ? nil : far
      ws = ws_of(proj)
      side_wall_end = l_side == :left ? far_trim(proj, ws, side, :start, cfg).zero? && (free_to_end(proj, side) - side['len']).abs <= 1 : far_trim(proj, ws, side, :end, cfg).zero? && (free_from_start(proj, side) - side['len']).abs <= 1
      b = fr && %w[start end].include?(opts['fridge_side']) && opts['fridge_side'] != far ? side_run(side_len(free_side, cfg), cfg, true, side_wall_end) : nil
      if b
        fr = nil
        notes << 'refrigerator at the far end of the side run'
      end
      cols = corner_main(proj, cfg, main, free_a, opts, fr, [l_side == :left ? :start : :end], notes, problems)
      unless cols
        problems << { 'code' => 'RUN_TOO_SHORT', 'severity' => 'error', 'message' => "main run #{free_a.round} mm cannot hold the corner unit and the standard appliances" }
        return []
      end
      b ||= plain_run(side_len(free_side, cfg), cfg, corner: true)
      plain_corner_upper(l_side == :left ? cols.first : cols.last) if b['cols'].empty?
      [kitchen(main, 0.0, { 'layout' => 'L', 'l_side' => l_side.to_s, 'runs' => { 'a' => { 'len' => free_a.round(1), 'cols' => cols }, (l_side == :left ? 'b' : 'c') => b } })]
    end

    def build_u(proj, cfg, main, prev, nxt, free_a, free_prev, free_next, opts, notes, problems)
      clear = free_a - 2 * cfg['base_d'].to_f
      problems << { 'code' => 'AISLE_TOO_NARROW', 'severity' => 'error', 'message' => "the U leaves #{clear.round} mm between the two legs (minimum #{AISLE_MIN.round})" } if clear < AISLE_MIN
      cols = corner_main(proj, cfg, main, free_a, opts, nil, %i[start end], notes, problems)
      unless cols
        problems << { 'code' => 'RUN_TOO_SHORT', 'severity' => 'error', 'message' => "main run #{free_a.round} mm cannot hold two corner units and the standard appliances" }
        return []
      end
      # fridge on the far end of a side run (last column of the list = far end), never on the main run between the two corners: side B, or side C when
      # the refrigerator is asked for at the end
      b_wall = far_trim(proj, ws_of(proj), prev, :start, cfg).zero? && (free_to_end(proj, prev) - prev['len']).abs <= 1
      c_wall = far_trim(proj, ws_of(proj), nxt, :end, cfg).zero? && (free_from_start(proj, nxt) - nxt['len']).abs <= 1
      want_f = opts['fridge'] != false
      c = want_f && opts['fridge_side'] == 'end' ? side_run(side_len(free_next, cfg), cfg, true, c_wall) : nil
      b = plain_run(side_len(free_prev, cfg), cfg, first: want_f && c.nil? ? 'fridge_end' : nil, corner: true, wall_end: b_wall)
      c ||= plain_run(side_len(free_next, cfg), cfg, corner: true)
      plain_corner_upper(cols.first) if b['cols'].empty?
      plain_corner_upper(cols.last) if c['cols'].empty?
      [kitchen(main, 0.0, { 'layout' => 'U', 'runs' => { 'a' => { 'len' => free_a.round(1), 'cols' => cols }, 'b' => b, 'c' => c } })]
    end

    def build_parallel(proj, cfg, main, opp, free_a, depth, opts, notes, problems)
      unless opp
        problems << { 'code' => 'NO_OPPOSITE_WALL', 'severity' => 'error', 'message' => 'no parallel wall for a parallel layout' }
        return straight_only(proj, cfg, main, 0.0, free_a, opts, notes, problems)
      end
      aisle = depth - 2 * cfg['base_d'].to_f
      problems << { 'code' => 'AISLE_TOO_NARROW', 'severity' => 'error', 'message' => "aisle #{aisle.round} mm < #{AISLE_MIN.round}" } if aisle < AISLE_MIN
      o = main_opts(proj, main, 0.0, free_a, opts, 'start')
      o['fridge_wall'] = true
      r = plan_main(free_a, cfg, o, notes)
      problems.concat(rule_problems(r['rules'].to_a, "wall #{main['id']}")) unless r['error']
      if r['error']
        problems << { 'code' => r['error'], 'severity' => 'error', 'message' => "main run #{free_a.round} mm cannot hold the standard appliances" }
        return []
      end
      cols = clear_uppers_for_windows(r['cols'], proj, main['id'], 0.0)
      notes.concat(r['notes'] || [])
      lc = [free_from_start(proj, opp), free_a].min
      c = plain_run(lc.floor(-1), cfg)
      # the opposite run is built from its own wall start; express the offset in the main run's frame
      m0 = Assistant.wall_point(main, 0.0)
      c0 = Assistant.wall_point(opp, 0.0) # start of the opposite wall runs against the main direction
      off = ((m0[0] - c0[0]) * main['dir'][0] + (m0[1] - c0[1]) * main['dir'][1]) - lc
      off = [off, 0.0].max
      [kitchen(main, 0.0, { 'layout' => 'parallel', 'aisle' => aisle.round(1), 'c_offset' => off.round(1), 'runs' => { 'a' => { 'len' => free_a.round(1), 'cols' => cols }, 'c' => c } })]
    end

    def build_island(proj, cfg, main, opp, free_a, depth, opts, notes, problems)
      o = main_opts(proj, main, 0.0, free_a, opts, 'start')
      o['fridge_wall'] = true
      r = plan_main(free_a, cfg, o, notes)
      problems.concat(rule_problems(r['rules'].to_a, "wall #{main['id']}")) unless r['error']
      if r['error']
        problems << { 'code' => r['error'], 'severity' => 'error', 'message' => "main run #{free_a.round} mm cannot hold the standard appliances" }
        return []
      end
      cols = clear_uppers_for_windows(r['cols'], proj, main['id'], 0.0)
      notes.concat(r['notes'] || [])
      il = [free_a - 600, 2400].min.floor(-1)
      aisle = [(depth - 2 * cfg['base_d'].to_f - 600) / 2.0, 1200.0].min
      problems << { 'code' => 'AISLE_TOO_NARROW', 'severity' => 'error', 'message' => "island aisle #{aisle.round} mm" } if aisle < AISLE_MIN
      c = plain_run(il, cfg)
      [kitchen(main, 0.0, { 'layout' => 'island', 'aisle' => aisle.round(1), 'c_offset' => ((free_a - il) / 2.0).round(1), 'runs' => { 'a' => { 'len' => free_a.round(1), 'cols' => cols }, 'c' => c } })]
    end

    # ------------------------------------------------------------------ build it in the model (one undoable operation)
    # replaces the kitchens the assistant made earlier (never touches anything else); returns the new kitchen groups
    def generate(proj, cfg, opts = {}, model = Sketchup.active_model)
      rm = proj['room_model']
      if rm.is_a?(Hash) && rm['ready'] == false
        plan = { 'layout' => nil, 'notes' => [], 'kitchens' => [],
                 'problems' => [{ 'code' => 'ROOM_MODEL_INCOMPLETE', 'severity' => 'error',
                                  'message' => "detected room measurements need confirmation: #{Array(rm['pending']).join(' | ')}" }] }
        return { 'plan' => plan, 'roots' => [], 'refused' => true }
      end

      cfg = cfg.merge('ceiling' => proj['room']['ceiling']['v'].to_f) if proj['room']['ceiling']['v'] && proj['room']['ceiling']['st'] != Assistant::REQ
      plan = propose(proj, cfg, opts)
      return { 'plan' => plan, 'roots' => [], 'refused' => plan['problems'].any? { |p| (p['severity'] || 'error') == 'error' } } if plan['kitchens'].empty?
      # a design that is known to be impossible is REPORTED, not built (opts['force'] builds it anyway, flagged)
      if plan['problems'].any? { |p| (p['severity'] || 'error') == 'error' } && !opts['force']
        return { 'plan' => plan, 'roots' => [], 'refused' => true }
      end
      # the same engineering validation the proposals pass before they are shown, again at the build: an invalid layout is never built
      val = Proposals.validate(proj, plan, Proposals.units(plan, cfg), cfg)
      unless val['ok']
        val['checks'].select { |c| c['result'] == 'FAIL' }.each { |c| plan['problems'] << { 'code' => "LAYOUT_#{c['code']}", 'severity' => 'error', 'message' => "layout validation failed: #{c['code']} #{c['detail']}" } }
        return { 'plan' => plan, 'roots' => [], 'refused' => true }
      end

      roots = []
      model.start_operation('E.G.C Assistant: generate design', true)
      begin
        model.entities.grep(Sketchup::Group).select { |g| g.get_attribute('egc', 'assistant') }.each { |g| g.erase! if g.valid? }
        plan['kitchens'].each_with_index do |k, i|
          params = k['params'].merge('origin' => k['origin'], 'rot' => k['rot'])
          root = Kitchen.generate(params, cfg, manage_operation: false)
          root.set_attribute('egc', 'assistant', true)
          root.set_attribute('egc', 'assistant_idx', i)
          roots << root
        end
        Exposure.refresh(cfg, model, own_op: false)
        roots.each { |r| EGC::AssistantEdit.stamp(r) }
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      proj['design'] = { 'layout' => plan['layout'], 'plan' => plan['kitchens'], 'opts' => opts, 'notes' => plan['notes'], 'at' => Time.now.to_i }
      Assistant.save(proj, model)
      { 'plan' => plan, 'roots' => roots }
    end
  end
end
