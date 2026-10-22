# frozen_string_literal: true

module EGC
  # Design proposals WITHOUT geometry: the planner's run plan is laid out on the room in memory, scored, explained and drawn (plan, front elevation of every
  # run, axonometric view) as SVG. Nothing here touches the SketchUp model - only an explicit approval builds the selected proposal (AssistantDesign.generate).
  module Proposals
    module_function

    TALL = %w[fridge_open fridge_bi pantry oven_tower oven_tall microwave_tower].freeze
    APPS = { 'fridge_open' => 'fridge', 'fridge_bi' => 'fridge', 'hob_oven' => 'hob + oven', 'hob' => 'hob', 'sink' => 'sink', 'dishwasher_bi' => 'dishwasher', 'washer_bi' => 'washer',
             'oven_tower' => 'oven tower', 'oven_tall' => 'oven tower', 'microwave_tower' => 'microwave', 'oven' => 'oven' }.freeze
    LABEL = { 'doors' => 'doors', 'drawers3' => 'drawers', 'drawers2' => 'drawers', 'drawers4' => 'drawers', 'filler' => 'filler', 'corner_l' => 'corner', 'pantry' => 'pantry', 'open' => 'open' }.freeze
    WEIGHTS = { 'space' => 0.20, 'workflow' => 0.20, 'appliances' => 0.15, 'clearance' => 0.20, 'storage' => 0.10, 'manufacturing' => 0.10, 'user' => 0.05 }.freeze

    def kind_of(t)
      return 'tall' if TALL.include?(t)
      return 'filler' if t == 'filler'

      'base'
    end

    # every unit of every kitchen of the plan, in room coordinates (mm). Same placement rules as Kitchen.generate (run A along the wall, B / C on the
    # perpendicular walls starting at the corner unit, parallel / island run opposite).
    def units(plan, cfg)
      out = []
      n = 0
      dep = cfg['base_d'].to_f
      plan['kitchens'].each_with_index do |k, ki|
        rot = k['rot'].to_f * Math::PI / 180.0
        ox, oy = k['origin']
        world = ->(x, y) { [ox + x * Math.cos(rot) - y * Math.sin(rot), oy + x * Math.sin(rot) + y * Math.cos(rot)] }
        prm = k['params']
        runs = prm['runs']
        a = runs['a'] || { 'cols' => [] }
        c_left = a['cols'].first && a['cols'].first['t'] == 'corner_l' ? a['cols'].first['w'].to_f : dep
        c_right = a['cols'].last && a['cols'].last['t'] == 'corner_l' ? a['cols'].last['w'].to_f : dep
        room_w = a['len'].to_f
        # far_first: the run is built from its far end towards the corner (Kitchen.generate, left side run), so its U-IDs run that way too
        place = lambda do |rid, cols, frame, far_first = false|
          s = 0.0
          made = []
          cols.each_with_index do |c, i|
            w = c['w'].to_f
            d = c['t'] == 'corner_l' ? w : dep
            loc = frame.call(s, w, d)
            made << { 'n' => nil, 'k' => ki, 'island' => loc[:island], 'run' => rid, 'idx' => i, 't' => c['t'], 'w' => w, 'd' => d, 'kind' => kind_of(c['t']), 'app' => APPS[c['t']],
                     'poly' => loc[:poly].map { |x, y| world.call(x, y) }, 'along' => loc[:along].map { |x, y| world.call(x, y) },
                     'w1' => c['w1'] || (kind_of(c['t']) == 'base' && c['t'] != 'corner_l' ? (c['t'] =~ /hob/ ? 'hood' : 'doors') : 'none'),
                     # the upper tiers exactly as Kitchen.build_run hangs them: over every base unit (corner unit included), never over an island
                     'u1' => loc[:island] || kind_of(c['t']) != 'base' ? 'none' : ((c['w1'] || 'auto').to_s == 'auto' ? (%w[hob hob_oven].include?(c['t']) ? 'hood' : 'doors') : c['w1'].to_s),
                     'u2' => loc[:island] || kind_of(c['t']) != 'base' ? 'none' : ((c['w2'] || 'auto').to_s == 'auto' ? 'doors' : c['w2'].to_s) }
            s += w
          end
          made.reverse! if far_first
          made.each { |u| u['n'] = (n += 1) unless u['kind'] == 'filler' }
          out.concat(made)
        end
        place.call('A', a['cols'], ->(s, w, d) { { poly: [[s, 0], [s + w, 0], [s + w, -d], [s, -d]], along: [[s, -d], [s + w, -d]] } })
        if %w[L U].include?(prm['layout'].to_s)
          left = prm['layout'] == 'U' || prm['l_side'].to_s == 'left'
          right = prm['layout'] == 'U' || prm['l_side'].to_s == 'right'
          place.call('B', runs['b']['cols'], ->(s, w, _d) { { poly: [[0, -(c_left + s)], [dep, -(c_left + s)], [dep, -(c_left + s + w)], [0, -(c_left + s + w)]], along: [[dep, -(c_left + s)], [dep, -(c_left + s + w)]] } }, true) if left && runs['b']
          place.call('C', runs['c']['cols'], ->(s, w, _d) { { poly: [[room_w, -(c_right + s)], [room_w - dep, -(c_right + s)], [room_w - dep, -(c_right + s + w)], [room_w, -(c_right + s + w)]], along: [[room_w - dep, -(c_right + s)], [room_w - dep, -(c_right + s + w)]] } }) if right && runs['c']
          # upper corner units (Kitchen.corner_upper_spans: the same spans the build hangs), kept on the corner unit they stand over
          [[:left, a['cols'].first, runs['b'], c_left], [:right, a['cols'].last, runs['c'], c_right]].each do |side, col, run, s|
            next unless col && col['cu'] && run && run['cols'].to_a.any? && (side == :left ? left : right)

            cu = out.find { |u| u['k'] == ki && u['run'] == 'A' && u['idx'] == (side == :left ? 0 : a['cols'].size - 1) }
            cu['cu'] = Kitchen.corner_upper_spans(side, s, Kitchen.corner_post(run), cfg).map do |sp|
              d = sp[:d]
              poly = [[0.0, 0.0], [s, 0.0], [s, -d], [d, -d], [d, -s], [0.0, -s]] # L-shaped corner wall unit, legs as deep as the tier
              poly = poly.map { |x, y| [room_w - x, y] } if side == :right
              { 'tier' => sp[:tier], 'blind' => false, 'poly' => poly.map { |x, y| world.call(x, y) } }
            end
          end
        elsif %w[parallel island].include?(prm['layout'].to_s) && runs['c']
          aisle = (prm['aisle'] || cfg['aisle']).to_f
          off = (prm['c_offset'] || 0).to_f
          y0 = -(dep + aisle)
          isl = prm['layout'].to_s == 'island'
          lc = runs['c']['len'].to_f # this run is turned to face run A: its first unit stands at the RIGHT end (Kitchen.generate)
          place.call('C', runs['c']['cols'], ->(s, w, d) { { island: isl, poly: [[off + lc - s - w, y0], [off + lc - s, y0], [off + lc - s, y0 - d], [off + lc - s - w, y0 - d]], along: [[off + lc - s - w, y0], [off + lc - s, y0]] } })
        end
      end
      out
    end

    def centre(u)
      a, b = u['along']
      [(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0]
    end

    # ---------------------------------------------------------------------------------------------------------------- scoring (0 - 100 per criterion)
    def score(proj, plan, cfg, opts = {}, wanted = {})
      us = units(plan, cfg)
      parts = {}
      why = []
      free = Assistant.walls(proj).sum { |w| s = AssistantDesign.free_segments(proj, w); s.sum { |a, b| b - a } }
      built = us.reject { |u| u['island'] }.sum { |u| u['w'] } # the free WALL used (an island stands in the room, not on a wall)
      parts['space'] = free.positive? ? [built / [free, 1].max * 100.0 * 1.6, 100].min.round : 0 # 60 % of the free wall used = full marks
      why << "uses #{(built / 1000.0).round(2)} m of #{(free / 1000.0).round(2)} m of free wall"
      f = us.find { |u| u['app'] == 'fridge' }
      h = us.find { |u| u['app'].to_s.include?('hob') }
      s = us.find { |u| u['app'] == 'sink' }
      if f && h && s
        legs = [[f, s], [s, h], [h, f]].map { |a, b| Math.hypot(centre(a)[0] - centre(b)[0], centre(a)[1] - centre(b)[1]) }
        ok = legs.count { |l| l.between?(1200, 2700) } + (legs.sum <= 7900 ? 1 : 0)
        parts['workflow'] = (ok / 4.0 * 100).round
        why << "work triangle #{legs.map { |l| (l / 1000.0).round(2) }.join(' / ')} m (sum #{(legs.sum / 1000.0).round(2)} m; ideal legs 1.2-2.7 m, sum <= 7.9 m)"
      else
        parts['workflow'] = 40
        why << "work triangle incomplete (#{[f ? nil : 'fridge', h ? nil : 'hob', s ? nil : 'sink'].compact.join(', ')} missing)"
      end
      need = %w[fridge sink hob]
      need << 'dishwasher' unless opts['dishwasher'] == false
      have = need.count { |a| us.any? { |u| u['app'].to_s.include?(a) } }
      parts['appliances'] = (have * 100.0 / need.size).round
      rules = plan['problems'].select { |p| p['code'].to_s =~ /CLEARANCE|AISLE|DOOR|COLUMN/ }
      errs = plan['problems'].select { |p| (p['severity'] || 'error') == 'error' }
      parts['clearance'] = errs.empty? ? (rules.empty? ? 100 : 70) : 0
      why << (errs.empty? ? 'every layout rule kept (hob-sink >= 600, hob-tall / wall >= 400, fridge gaps, corner posts)' : "breaks: #{errs.map { |p| p['code'] }.uniq.join(', ')}")
      store = us.select { |u| u['kind'] == 'base' && u['app'].nil? }.sum { |u| u['w'] } + us.select { |u| u['w1'] && u['w1'] !~ /none|hood/ }.sum { |u| u['w'] }
      parts['storage'] = [store / 6000.0 * 100, 100].min.round
      why << "#{(store / 1000.0).round(2)} m of cabinet storage (base + upper)"
      widths = us.reject { |u| u['kind'] == 'filler' }.map { |u| u['w'].round }
      odd = widths.count { |w| (w % 50).nonzero? }
      fill = us.count { |u| u['kind'] == 'filler' && u['w'] > 60 }
      parts['manufacturing'] = [100 - (widths.uniq.size - 4).clamp(0, 10) * 5 - odd * 5 - fill * 10, 0].max
      why << "#{widths.uniq.size} different cabinet widths, #{odd} off the 50 mm grid"
      honoured = wanted.count { |k, v| opts[k] == v }
      parts['user'] = wanted.empty? ? 100 : (honoured * 100.0 / wanted.size).round
      total = WEIGHTS.sum { |k, wt| parts[k].to_f * wt }.round
      { 'total' => total, 'parts' => parts, 'why' => why, 'units' => us }
    end

    # ---------------------------------------------------------------------------------------------------------------- drawings (SVG, in memory)
    def code(n)
      format('U%02d', n)
    end

    # ---------------------------------------------------------------------------------------------------------------- ONE layout model
    # Every solid of the proposal in ROOM coordinates (mm), made from the solved unit coordinates only: the 2D plan, the 3D view and the validation
    # all read this list - nothing is arranged a second time. Heights / depths are the project's own (base, worktop, upper tiers, tall line).
    def solids(us, cfg)
      bh = cfg['base_h'].to_f
      tt = cfg['top_thk'].to_f
      w1z = bh + cfg['gap_h'].to_f
      w2z = w1z + cfg['w1_h'].to_f
      top = Config.top_line(cfg)
      out = []
      us.each do |u|
        id = u['n'] && code(u['n'])
        a, b = u['along']
        back = u['poly'].reject { |p| [a, b].any? { |q| (q[0] - p[0]).abs < 0.01 && (q[1] - p[1]).abs < 0.01 } }
        back = u['poly'][0..1] if back.size != 2
        ba, bb = back.sort_by { |p| Math.hypot(p[0] - a[0], p[1] - a[1]) }
        deep = lambda do |d|
          k = d / [u['d'].to_f, 1.0].max
          [ba, bb, [bb[0] + (b[0] - bb[0]) * k, bb[1] + (b[1] - bb[1]) * k], [ba[0] + (a[0] - ba[0]) * k, ba[1] + (a[1] - ba[1]) * k]]
        end
        base = { 'id' => id, 'run' => u['run'], 'label' => u['app'] || LABEL[u['t']] || u['t'], 'front' => [a, b] }
        case u['kind']
        when 'tall' then out << base.merge('part' => 'tall', 'poly' => u['poly'], 'z0' => 0.0, 'z1' => top, 'col' => u['app'] ? '#c9d0d8' : '#e6d9bd')
        when 'filler' then out << base.merge('part' => 'filler', 'poly' => u['poly'], 'z0' => 0.0, 'z1' => bh - tt, 'col' => '#d8d2c4')
        else
          out << base.merge('part' => 'base', 'poly' => u['poly'], 'z0' => 0.0, 'z1' => bh - tt, 'col' => u['app'] ? '#c9d0d8' : '#ead9b0')
          out << base.merge('part' => 'worktop', 'poly' => u['poly'], 'z0' => bh - tt, 'z1' => bh, 'col' => '#3a3a3a', 'id' => nil)
          t1 = u['u1'].to_s
          out << base.merge('part' => t1 == 'hood' ? 'hood' : 'upper1', 'poly' => deep.call((t1 == 'hood' ? cfg['hood_d'] || cfg['w1_d'] : cfg['w1_d']).to_f), 'z0' => w1z, 'z1' => w2z, 'col' => t1 == 'hood' ? '#b9bec5' : '#efe6cf', 'id' => nil, 'over' => id) unless t1.empty? || t1 == 'none'
          out << base.merge('part' => 'upper2', 'poly' => deep.call(cfg['w2_d'].to_f), 'z0' => w2z, 'z1' => top, 'col' => '#f3ecd9', 'id' => nil, 'over' => id) if cfg['w2_enabled'] && u['u2'].to_s != 'none'
          (u['cu'] || []).each { |c| out << base.merge('part' => c['tier'] == 1 ? 'upper1' : 'upper2', 'poly' => c['poly'], 'z0' => c['tier'] == 1 ? w1z : w2z, 'z1' => c['tier'] == 1 ? w2z : top, 'col' => c['tier'] == 1 ? '#efe6cf' : '#f3ecd9', 'id' => nil, 'over' => id, 'corner' => true) }
        end
      end
      out
    end

    def poly_area(p)
      a = 0.0
      p.each_index { |i| x1, y1 = p[i]; x2, y2 = p[(i + 1) % p.size]; a += x1 * y2 - x2 * y1 }
      a / 2.0
    end

    # area shared by two convex polygons (Sutherland - Hodgman)
    def overlap_area(pa, pb)
      pa = pa.reverse if poly_area(pa).negative?
      pb = pb.reverse if poly_area(pb).negative?
      out = pa
      pb.each_index do |i|
        c1 = pb[i]
        c2 = pb[(i + 1) % pb.size]
        inside = ->(p) { (c2[0] - c1[0]) * (p[1] - c1[1]) - (c2[1] - c1[1]) * (p[0] - c1[0]) >= -1e-9 }
        inp = out
        out = []
        inp.each_index do |j|
          s = inp[j - 1]
          e = inp[j]
          cross = lambda do
            dcx = c1[0] - c2[0]
            dcy = c1[1] - c2[1]
            dpx = s[0] - e[0]
            dpy = s[1] - e[1]
            n1 = c1[0] * c2[1] - c1[1] * c2[0]
            n2 = s[0] * e[1] - s[1] * e[0]
            den = dcx * dpy - dcy * dpx
            [(n1 * dpx - n2 * dcx) / den, (n1 * dpy - n2 * dcy) / den]
          end
          if inside.call(e)
            out << cross.call unless inside.call(s)
            out << e
          elsif inside.call(s)
            out << cross.call
          end
        end
        return 0.0 if out.size < 3
      end
      poly_area(out).abs
    end

    def in_room?(pt, poly, tol = 2.0)
      return true if poly.each_index.any? { |i| seg_dist(pt, poly[i], poly[(i + 1) % poly.size]) <= tol }

      c = false
      poly.each_index do |i|
        a = poly[i]
        b = poly[i - 1]
        c = !c if ((a[1] > pt[1]) != (b[1] > pt[1])) && (pt[0] < (b[0] - a[0]) * (pt[1] - a[1]) / (b[1] - a[1]) + a[0])
      end
      c
    end

    # ENGINEERING VALIDATION of the solved layout (before anything is drawn or built). A proposal that fails is never shown.
    def validate(proj, plan, us, cfg)
      room = proj['room']['poly']
      ws = Assistant.walls(proj)
      open_ids = proj['no_build'].select { |x| x['src'] == 'room_model' && x['off'].to_f < 1 }.map { |x| x['wall'] }
      floor = us
      real = us.reject { |u| u['kind'] == 'filler' }
      res = []
      add = ->(code, bad) { res << { 'code' => code, 'result' => bad.empty? ? 'PASS' : 'FAIL', 'detail' => bad.first(4).join('; ') } }
      nm = ->(u) { u['n'] ? code(u['n']) : "filler(run #{u['run']})" }
      add.call('NO_OVERLAP', floor.combination(2).filter_map { |a, b| ar = overlap_area(a['poly'], b['poly']); "#{nm.call(a)} / #{nm.call(b)} share #{(ar / 100.0).round} cm2" if ar > 100.0 })
      add.call('NO_OUTSIDE_WALL', floor.filter_map { |u| "#{nm.call(u)} leaves the room" unless u['poly'].all? { |p| in_room?(p, room) } })
      # corners: where a side run meets the main run there must be the corner unit, and the side run must start exactly at it
      bad = []
      plan['kitchens'].each_with_index do |k, ki|
        lay = k['params']['layout'].to_s
        next unless %w[L U].include?(lay)

        a = floor.select { |u| u['k'] == ki && u['run'] == 'A' }
        sides = { 'B' => a.first, 'C' => a.last }
        sides.each do |rid, cu|
          run = floor.select { |u| u['k'] == ki && u['run'] == rid }
          next if run.empty?

          bad << "run #{rid} meets run A without a corner unit" unless cu && cu['t'] == 'corner_l'
          gap = cu ? run.map { |u| u['poly'].flat_map { |p| cu['poly'].map { |q| Math.hypot(p[0] - q[0], p[1] - q[1]) } }.min }.min : 0
          bad << "run #{rid} does not start at the corner unit (#{gap.round} mm away)" if gap > 1.0
        end
      end
      add.call('NO_INVALID_CORNER', bad)
      # every unit stands with its back on a real wall (an island: inside the room, in an island plan) and touches its neighbours in the run
      bad = []
      floor.each do |u|
        a, b = u['along']
        back = u['poly'].reject { |p| [a, b].any? { |q| (q[0] - p[0]).abs < 0.01 && (q[1] - p[1]).abs < 0.01 } }
        if u['island'] || (plan['kitchens'][u['k']]['params']['layout'].to_s == 'parallel' && u['run'] == 'C' && !ws.any? { |w| !open_ids.include?(w['id']) && back.all? { |p| seg_dist(p, w['p0'], w['p1']) <= 2.0 } })
          bad << "#{nm.call(u)} is free-standing but the plan is not an island / parallel plan" unless %w[island parallel].include?(plan['kitchens'][u['k']]['params']['layout'].to_s)
          next
        end
        w = ws.find { |x| back.size == 2 && back.all? { |p| seg_dist(p, x['p0'], x['p1']) <= 2.0 } }
        bad << "#{nm.call(u)} does not stand against a wall" unless w
        bad << "#{nm.call(u)} stands on the open side #{w['id']} (no wall there)" if w && open_ids.include?(w['id'])
      end
      floor.group_by { |u| [u['k'], u['run']] }.each_value do |run|
        run.each_cons(2) do |p, q|
          d = p['poly'].flat_map { |x| q['poly'].map { |y| Math.hypot(x[0] - y[0], x[1] - y[1]) } }.min
          bad << "gap of #{d.round} mm between #{nm.call(p)} and #{nm.call(q)}" if d > 1.0
        end
      end
      add.call('NO_FLOATING_UNIT', bad)
      cen = ->(u) { [u['poly'].sum { |p| p[0] } / 4.0, u['poly'].sum { |p| p[1] } / 4.0] }
      dup = real.combination(2).filter_map { |a, b| "#{nm.call(a)} / #{nm.call(b)} at the same place" if Math.hypot(cen.call(a)[0] - cen.call(b)[0], cen.call(a)[1] - cen.call(b)[1]) < 1.0 }
      dup += real.map { |u| u['n'] }.tally.select { |_, n| n > 1 }.keys.map { |n| "#{code(n)} used twice" }
      add.call('NO_DUPLICATE_UNIT_POSITION', dup)
      # the refrigerator stands at a free end of its run, never between two units (a design copied from the client's image is built as drawn)
      bad = []
      unless plan['as_drawn']
        floor.group_by { |u| [u['k'], u['run']] }.each_value do |run|
          ru = run.reject { |u| u['kind'] == 'filler' }
          ru.each_with_index { |u, i| bad << "#{nm.call(u)} (refrigerator) stands between #{nm.call(ru[i - 1])} and #{nm.call(ru[i + 1])}" if u['app'] == 'fridge' && i.positive? && ru[i + 1] }
        end
      end
      add.call('FRIDGE_AT_RUN_END', bad)
      # openings: nothing tall or hung in front of a window, nothing in a doorway
      bad = []
      top = Config.top_line(cfg)
      sol = solids(us, cfg)
      proj['openings'].each do |o|
        w = ws.find { |x| x['id'] == o['wall'] } or next
        p0 = Assistant.wall_point(w, o['off'].to_f)
        p1 = Assistant.wall_point(w, o['off'].to_f + o['w'].to_f)
        z0 = o['sill'].to_f
        z1 = z0 + o['h'].to_f
        sol.each do |s|
          next if s['part'] == 'worktop' || s['z1'] <= z0 + 1 || s['z0'] >= [z1, top].min - 1

          bk = s['poly'].select { |p| seg_dist(p, w['p0'], w['p1']) <= 2.0 }
          next unless bk.size >= 2

          t = bk.map { |p| (p[0] - w['p0'][0]) * w['dir'][0] + (p[1] - w['p0'][1]) * w['dir'][1] }.minmax
          ov = [t[1], o['off'].to_f + o['w'].to_f].min - [t[0], o['off'].to_f].max
          bad << "#{s['id'] || "upper of #{s['over']}"} (#{s['part']}) covers the #{o['type']} on wall #{o['wall']} by #{ov.round} mm" if ov > 1.0 && p0 && p1
        end
      end
      add.call('OPENINGS_CLEAR', bad.uniq)
      { 'ok' => res.all? { |r| r['result'] == 'PASS' }, 'checks' => res }
    end

    # ---------------------------------------------------------------------------------------------------------------- 2D plan (from the solved layout)
    def plan_svg(proj, us, cfg = nil)
      ws = Assistant.walls(proj)
      xs = proj['room']['poly'].map(&:first)
      ys = proj['room']['poly'].map(&:last)
      w = xs.max - xs.min
      h = ys.max - ys.min
      k = 620.0 / [w, h].max
      pad = 46
      tx = ->(x) { (pad + (x - xs.min) * k).round(1) }
      ty = ->(y) { (pad + (ys.max - y) * k).round(1) }
      o = +"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 #{(w * k + 2 * pad).round} #{(h * k + 2 * pad).round}' style='width:100%;background:#fff' font-family='Arial'>"
      o << "<polygon points='#{proj['room']['poly'].map { |x, y| "#{tx.call(x)},#{ty.call(y)}" }.join(' ')}' fill='#f6f4ee' stroke='none'/>"
      nb = proj['no_build'].select { |x| x['off'].to_f < 1 && x['src'] == 'room_model' }.map { |x| x['wall'] }
      rc = proj['room']['poly'].transpose.map { |c| c.sum / c.size.to_f }
      ws.each do |x|
        open = nb.include?(x['id'])
        o << "<line x1='#{tx.call(x['p0'][0])}' y1='#{ty.call(x['p0'][1])}' x2='#{tx.call(x['p1'][0])}' y2='#{ty.call(x['p1'][1])}' stroke='#{open ? '#b5b5b5' : '#1d1d1d'}' stroke-width='#{open ? 1.2 : 7}' #{open ? "stroke-dasharray='7 5'" : ''}/>"
        mid = [(x['p0'][0] + x['p1'][0]) / 2.0, (x['p0'][1] + x['p1'][1]) / 2.0]
        nrm = [-x['dir'][1], x['dir'][0]]
        nrm = nrm.map { |v| -v } if nrm[0] * (rc[0] - mid[0]) + nrm[1] * (rc[1] - mid[1]) > 0 # away from the room: the label sits outside the wall
        mx = mid[0] + nrm[0] * 230
        my = mid[1] + nrm[1] * 230
        o << "<text x='#{tx.call(mx)}' y='#{(ty.call(my) + 4).round(1)}' font-size='12' text-anchor='middle' fill='#{open ? '#999' : '#111'}' #{x['dir'][0].abs < 0.5 ? "transform='rotate(-90 #{tx.call(mx)} #{ty.call(my)})'" : ''}>#{open ? 'open' : "wall #{x['id']} · #{x['len'].round}"}</text>"
      end
      proj['openings'].each do |op|
        x = ws.find { |q| q['id'] == op['wall'] } or next
        a = Assistant.wall_point(x, op['off'])
        b = Assistant.wall_point(x, op['off'] + op['w'])
        o << "<line x1='#{tx.call(a[0])}' y1='#{ty.call(a[1])}' x2='#{tx.call(b[0])}' y2='#{ty.call(b[1])}' stroke='#{op['type'] == 'door' ? '#c0392b' : '#5aa9e6'}' stroke-width='9'/>"
      end
      sol = cfg ? solids(us, cfg) : []
      sol.select { |s| %w[upper1 hood].include?(s['part']) }.each { |s| o << "<polygon points='#{s['poly'].map { |x, y| "#{tx.call(x)},#{ty.call(y)}" }.join(' ')}' fill='none' stroke='#8a6d1f' stroke-width='0.8' stroke-dasharray='4 3'/>" }
      us.each do |u|
        fill = u['app'] ? '#c9d0d8' : (u['kind'] == 'tall' ? '#e6d9bd' : (u['kind'] == 'filler' ? '#d8d2c4' : '#ead9b0'))
        o << "<polygon points='#{u['poly'].map { |x, y| "#{tx.call(x)},#{ty.call(y)}" }.join(' ')}' fill='#{fill}' stroke='#333' stroke-width='1'/>"
        next if u['kind'] == 'filler'

        cx = u['poly'].sum { |p| tx.call(p[0]) } / 4.0
        cy = u['poly'].sum { |p| ty.call(p[1]) } / 4.0
        fs = [[u['w'] * k * 0.34, 8].max, 13].min.round(1)
        o << "<text x='#{cx.round(1)}' y='#{(cy - 1).round(1)}' font-size='#{fs}' text-anchor='middle' font-weight='bold'>#{code(u['n'])}</text>"
        o << "<text x='#{cx.round(1)}' y='#{(cy + fs * 0.95).round(1)}' font-size='#{(fs * 0.72).round(1)}' text-anchor='middle' fill='#444'>#{u['w'].round}</text>"
      end
      # the work triangle refrigerator - sink - hob, drawn between the fronts of the three units with the length of every leg
      tri = [us.find { |u| u['app'] == 'fridge' }, us.find { |u| u['app'] == 'sink' }, us.find { |u| u['app'].to_s.include?('hob') }]
      if tri.all?
        pts = tri.map { |u| centre(u) }
        o << "<polygon points='#{pts.map { |x, y| "#{tx.call(x)},#{ty.call(y)}" }.join(' ')}' fill='#2e9e5b' fill-opacity='0.10' stroke='#2e9e5b' stroke-width='1.6' stroke-dasharray='6 4'/>"
        pts.each_with_index do |p, i|
          q = pts[(i + 1) % 3]
          len = Math.hypot(p[0] - q[0], p[1] - q[1])
          o << "<text x='#{tx.call((p[0] + q[0]) / 2.0)}' y='#{(ty.call((p[1] + q[1]) / 2.0) + 12).round(1)}' font-size='10.5' text-anchor='middle' fill='#1d7a43' font-weight='bold'>#{(len / 1000.0).round(2)} m</text>" if len > 300
        end
      end
      o << "<text x='#{pad}' y='#{(h * k + 2 * pad - 8).round}' font-size='11' fill='#555'>plan · mm · cabinets from the solved layout (dashed = upper units, blue = window, red = door)</text>"
      o << '</svg>'
    end

    # ---------------------------------------------------------------------------------------------------------------- 3D view (SAME solids as the plan)
    # Seen from inside the room, looking at the main run: the walls with their openings, the floor, then every solid of the layout as an opaque box
    # (far to near). Nothing is positioned here - the boxes are the plan's own coordinates lifted to their heights.
    def axo_svg(proj, plan, us, cfg)
      k0 = plan['kitchens'].first
      return '' unless k0

      rot = k0['rot'].to_f * Math::PI / 180.0
      ox, oy = k0['origin']
      # kitchen frame: X along the main wall (left -> right seen from the room), Y from that wall into the room
      loc = lambda do |p|
        dx = p[0] - ox
        dy = p[1] - oy
        [dx * Math.cos(rot) + dy * Math.sin(rot), -(-dx * Math.sin(rot) + dy * Math.cos(rot))]
      end
      sol = solids(us, cfg)
      side_b = us.any? { |u| u['run'] == 'B' }
      side_c = us.any? { |u| u['run'] == 'C' && !u['island'] } && plan['kitchens'].first['params']['layout'].to_s != 'parallel'
      sk = side_c && !side_b ? 0.42 : -0.42 # the viewer stands on the side that shows the inside of the wall carrying the side run
      pr = ->(x, y, z) { [x + y * sk, -z + y * 0.36] }
      view = [-sk, 1.0] # towards the viewer, in the kitchen frame (plan part)
      ceil_h = (proj['room']['ceiling']['v'] || cfg['ceiling']).to_f
      ws = Assistant.walls(proj)
      nb = proj['no_build'].select { |x| x['off'].to_f < 1 && x['src'] == 'room_model' }.map { |x| x['wall'] }
      cen_room = proj['room']['poly'].transpose.map { |c| c.sum / c.size.to_f }
      faces = [] # [depth, svg]
      pts_all = []
      poly3 = lambda do |pts, fill, stroke = '#3a3a3a', sw = 7, extra = "stroke-linejoin='round'"|
        q = pts.map { |x, y, z| pr.call(x, y, z) }
        pts_all.concat(q)
        "<polygon points='#{q.map { |a, b| "#{a.round(1)},#{b.round(1)}" }.join(' ')}' fill='#{fill}' stroke='#{stroke}' stroke-width='#{sw}' #{extra}/>"
      end
      back = +''
      back << poly3.call(proj['room']['poly'].map { |p| l = loc.call(p); [l[0], l[1], 0.0] }, '#e9e6de', '#b9b5a8', 8)
      ws.reject { |w| nb.include?(w['id']) }.each do |w|
        a = loc.call(w['p0'])
        b = loc.call(w['p1'])
        c = loc.call(cen_room)
        nrm = [-(b[1] - a[1]), b[0] - a[0]]
        nrm = nrm.map { |v| -v } if nrm[0] * (c[0] - a[0]) + nrm[1] * (c[1] - a[1]) < 0 # normal into the room
        next unless nrm[0] * view[0] + nrm[1] * view[1] > 1e-6 # only walls whose inside face looks at the viewer

        back << poly3.call([[a[0], a[1], 0], [b[0], b[1], 0], [b[0], b[1], ceil_h], [a[0], a[1], ceil_h]], '#f4f2ec', '#8d8a80', 10)
        proj['openings'].select { |o| o['wall'] == w['id'] }.each do |o|
          p0 = loc.call(Assistant.wall_point(w, o['off'].to_f))
          p1 = loc.call(Assistant.wall_point(w, o['off'].to_f + o['w'].to_f))
          z0 = o['sill'].to_f
          z1 = z0 + o['h'].to_f
          back << poly3.call([[p0[0], p0[1], z0], [p1[0], p1[1], z0], [p1[0], p1[1], z1], [p0[0], p0[1], z1]], o['type'] == 'door' ? '#f3d6d0' : '#cfe6f7', o['type'] == 'door' ? '#c0392b' : '#3b8fd0', 12)
        end
      end
      labels = +''
      sol.each do |s|
        p = s['poly'].map { |q| loc.call(q) }
        p = p.reverse if poly_area(p).negative?
        cx = p.sum { |q| q[0] } / p.size
        cy = p.sum { |q| q[1] } / p.size
        depth = cx * view[0] + cy * view[1]
        g = +''
        p.each_index do |i|
          a = p[i]
          b = p[(i + 1) % p.size]
          nrm = [b[1] - a[1], -(b[0] - a[0])] # outward (counter-clockwise polygon)
          next unless nrm[0] * view[0] + nrm[1] * view[1] > 1e-6

          front = nrm[1].abs > nrm[0].abs
          g << poly3.call([[a[0], a[1], s['z0']], [b[0], b[1], s['z0']], [b[0], b[1], s['z1']], [a[0], a[1], s['z1']]], front ? s['col'] : shade(s['col'], 0.86))
        end
        g << poly3.call(p.map { |q| [q[0], q[1], s['z1']] }, shade(s['col'], 1.06))
        faces << [[depth, s['z0']], g]
        next unless s['id']

        fa, fb = s['front'].map { |q| loc.call(q) }
        m = pr.call((fa[0] + fb[0]) / 2.0, (fa[1] + fb[1]) / 2.0, (s['z0'] + [s['z1'], 2000.0].min) / 2.0)
        labels << "<text x='#{m[0].round(1)}' y='#{m[1].round(1)}' font-size='95' text-anchor='middle' font-weight='bold' fill='#222'>#{s['id']}</text>"
        labels << "<text x='#{m[0].round(1)}' y='#{(m[1] + 95).round(1)}' font-size='62' text-anchor='middle' fill='#444'>#{s['label']}</text>" if (fb[0] - fa[0]).abs + (fb[1] - fa[1]).abs > 420
      end
      body = faces.sort_by(&:first).map(&:last).join
      minx, maxx = pts_all.map(&:first).minmax
      miny, maxy = pts_all.map(&:last).minmax
      m = 120
      "<svg xmlns='http://www.w3.org/2000/svg' viewBox='#{(minx - m).round} #{(miny - m).round} #{(maxx - minx + 2 * m).round} #{(maxy - miny + 2 * m).round}' style='width:100%;background:#fff' font-family='Arial'>#{back}#{body}#{labels}</svg>"
    end

    def shade(hex, f)
      r, g, b = hex.delete('#').scan(/../).map { |c| [[(c.to_i(16) * f).round, 0].max, 255].min }
      format('#%02x%02x%02x', r, g, b)
    end

    # front elevation of one run: base / tall units, uppers, unit numbers, labels, widths, overall length and heights
    def elev_svg(us, run, cfg)
      ru = us.select { |u| u['run'] == run }
      return '' if ru.empty?

      len = ru.sum { |u| u['w'] }
      bh = cfg['base_h'].to_f
      pl = cfg['plinth'].to_f
      w1z = bh + cfg['gap_h'].to_f
      top = Config.top_line(cfg)
      k = 560.0 / [len, top].max
      x0 = 30
      y = ->(z) { (20 + (top - z) * k).round(1) }
      o = +"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 #{(len * k + 60).round} #{(top * k + 70).round}' style='width:100%;background:#fff'>"
      x = 0.0
      ru.each do |u|
        px = (x0 + x * k).round(1)
        pw = (u['w'] * k).round(1)
        if u['kind'] == 'tall'
          o << "<rect x='#{px}' y='#{y.call(top)}' width='#{pw}' height='#{(top * k).round(1)}' fill='#e9e0cc' stroke='#444'/>"
        elsif u['kind'] == 'filler'
          o << "<rect x='#{px}' y='#{y.call(bh)}' width='#{pw}' height='#{((bh - pl) * k).round(1)}' fill='#ccc' stroke='#666'/>"
        else
          o << "<rect x='#{px}' y='#{y.call(bh)}' width='#{pw}' height='#{((bh - pl) * k).round(1)}' fill='#{u['app'] ? '#d9dee4' : '#efe3c6'}' stroke='#444'/>"
          if u['w1'] == 'hood'
            o << "<rect x='#{(px + pw * 0.2).round(1)}' y='#{y.call(top)}' width='#{(pw * 0.6).round(1)}' height='#{((top - w1z) * k).round(1)}' fill='#cfd3d8' stroke='#444'/>"
          elsif u['w1'] != 'none'
            o << "<rect x='#{px}' y='#{y.call(top)}' width='#{pw}' height='#{((top - w1z) * k).round(1)}' fill='#ebe9e0' stroke='#444'/>"
          end
        end
        unless u['kind'] == 'filler'
          zt = u['kind'] == 'tall' ? top / 2 : bh / 2
          o << "<text x='#{(px + pw / 2).round(1)}' y='#{y.call(zt)}' font-size='10' text-anchor='middle' font-family='Arial' font-weight='bold'>#{code(u['n'])}</text>"
          o << "<text x='#{(px + pw / 2).round(1)}' y='#{(y.call(zt) + 11).round(1)}' font-size='7.5' text-anchor='middle' font-family='Arial'>#{u['app'] || LABEL[u['t']] || u['t']}</text>"
        end
        o << "<text x='#{(px + pw / 2).round(1)}' y='#{(y.call(0) + 12).round(1)}' font-size='7.5' text-anchor='middle' font-family='Arial'>#{u['w'].round}</text>"
        x += u['w']
      end
      o << "<line x1='#{x0}' y1='#{(y.call(0) + 22).round(1)}' x2='#{(x0 + len * k).round(1)}' y2='#{(y.call(0) + 22).round(1)}' stroke='#8a1c12'/>"
      o << "<text x='#{(x0 + len * k / 2).round(1)}' y='#{(y.call(0) + 34).round(1)}' font-size='9' text-anchor='middle' font-family='Arial' fill='#8a1c12'>run #{run}: #{len.round} mm</text>"
      o << "<text x='#{x0 - 6}' y='#{y.call(bh)}' font-size='7' text-anchor='end' font-family='Arial'>#{bh.round}</text><text x='#{x0 - 6}' y='#{y.call(top)}' font-size='7' text-anchor='end' font-family='Arial'>#{top.round}</text>"
      o << '</svg>'
    end

    def preview(proj, plan, cfg, sc)
      us = sc['units']
      ws = Assistant.walls(proj)
      cen = ->(u) { [u['poly'].sum { |p| p[0] } / u['poly'].size, u['poly'].sum { |p| p[1] } / u['poly'].size] }
      wall_of = lambda do |u|
        next 'island' if u['island']

        w = ws.min_by { |x| seg_dist(cen.call(u), x['p0'], x['p1']) }
        w && seg_dist(cen.call(u), w['p0'], w['p1']) <= u['d'] / 2.0 + 80 ? w['id'] : 'free-standing'
      end
      { 'plan' => plan_svg(proj, us, cfg), 'elevations' => %w[A B C].map { |r| elev_svg(us, r, cfg) }.reject(&:empty?), 'axo' => axo_svg(proj, plan, us, cfg),
        'validation' => validate(proj, plan, us, cfg),
        'units' => us.reject { |u| u['kind'] == 'filler' }.map { |u| { 'id' => code(u['n']), 'run' => u['run'], 'wall' => wall_of.call(u), 'type' => u['t'], 'w' => u['w'].round, 'd' => u['d'].round, 'app' => u['app'] } },
        'clearances' => clearances(proj, plan, us, ws, cen),
        'style' => { 'front' => cfg['front_style'].to_s, 'color' => cfg['front_color'].to_s, 'handle' => cfg['handle'].to_s, 'source' => 'project settings (the proposal does not choose finishes)' } }
    end

    def seg_dist(p, a, b)
      dx = b[0] - a[0]
      dy = b[1] - a[1]
      l2 = dx * dx + dy * dy
      t = l2.zero? ? 0.0 : (((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2).clamp(0.0, 1.0)
      Math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy)
    end

    # measured, not judged: free space in front of every run (to the nearest wall or other unit), hob <-> sink and hob <-> tall unit gaps along the run,
    # aisle of a parallel / island plan. The layout rules themselves are the planner's (plan problems).
    def clearances(_proj, plan, us, ws, cen)
      out = []
      solid = us.map { |u| [u, u['poly']] }
      us.reject { |u| u['kind'] == 'filler' || u['t'] == 'corner_l' }.group_by { |u| u['run'] }.each do |run, ru| # the corner unit faces the other run
        best = ru.map do |u|
          a, b = u['along']
          m = [(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0]
          c = cen.call(u)
          l = Math.hypot(m[0] - c[0], m[1] - c[1])
          next nil if l < 1

          dir = [(m[0] - c[0]) / l, (m[1] - c[1]) / l]
          segs = ws.map { |w| [w['p0'], w['p1']] } + solid.reject { |x, _| x['run'] == run }.flat_map { |_, p| p.each_index.map { |i| [p[i], p[(i + 1) % p.size]] } }
          segs.map { |p, q| ray_hit(m, dir, p, q) }.compact.select { |t| t > 1 }.min
        end.compact
        out << { 'what' => "free space in front of run #{run}", 'mm' => best.min.round } if best.any?
      end
      hob = us.find { |u| u['app'].to_s.include?('hob') }
      gap = lambda do |x, y|
        (xa, xb), (ya, yb) = x['along'], y['along']
        [[xa, ya], [xa, yb], [xb, ya], [xb, yb]].map { |p, q| Math.hypot(p[0] - q[0], p[1] - q[1]) }.min
      end
      if hob
        sink = us.find { |u| u['app'] == 'sink' && u['run'] == hob['run'] }
        tall = us.select { |u| u['kind'] == 'tall' && u['run'] == hob['run'] }.min_by { |t| gap.call(hob, t) }
        out << { 'what' => "#{code(hob['n'])} hob - #{code(sink['n'])} sink (edge to edge)", 'mm' => gap.call(hob, sink).round } if sink
        out << { 'what' => "#{code(hob['n'])} hob - #{code(tall['n'])} tall unit (edge to edge)", 'mm' => gap.call(hob, tall).round } if tall
      end
      plan['kitchens'].each { |k| out << { 'what' => "aisle (#{k['params']['layout']})", 'mm' => k['params']['aisle'].to_f.round } if %w[parallel island].include?(k['params']['layout'].to_s) && k['params']['aisle'] }
      out
    end

    def ray_hit(o, d, p, q)
      ex = q[0] - p[0]
      ey = q[1] - p[1]
      den = d[0] * ey - d[1] * ex
      return nil if den.abs < 1e-9

      t = ((p[0] - o[0]) * ey - (p[1] - o[1]) * ex) / den
      s = ((p[0] - o[0]) * d[1] - (p[1] - o[1]) * d[0]) / den
      t.positive? && s.between?(-1e-6, 1 + 1e-6) ? t : nil
    end
  end
end
