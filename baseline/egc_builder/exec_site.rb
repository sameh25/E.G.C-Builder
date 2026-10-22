# frozen_string_literal: true

require 'json'

module EGC
  # Site / Civil-MEP execution drawing set (A3 landscape SVG sheets). Audience: site engineer, civil, electrical, plumbing, installer, duct/HVAC.
  # Datum: X = distance from the wall datum (wall start), Z = AFFL (height above the finished floor level). Every service point comes from
  # SiteDocs.services (the SAME coordinates feed the elevations, DETAIL zooms and schedules); statuses are never promoted.
  module ExecSite
    module_function

    ED = ExecDraw
    EV = ExecViews
    COLORS = { 'elec' => '#c2410c', 'water_cold' => '#1d4ed8', 'water_hot' => '#dc2626', 'drain' => '#4b5563', 'gas' => '#a16207', 'duct' => '#6d28d9', 'led' => '#0e7c5a' }.freeze
    CODES = { 'elec' => 'E', 'water_cold' => 'CW', 'water_hot' => 'HW', 'drain' => 'D', 'gas' => 'G', 'duct' => 'DU', 'led' => 'L' }.freeze
    KIND = { 'elec' => ['Electrical', 'كهرباء'], 'water_cold' => ['Cold water', 'مياه باردة'], 'water_hot' => ['Hot water', 'مياه ساخنة'], 'drain' => ['Drain', 'صرف'],
             'gas' => ['Gas', 'غاز'], 'duct' => ['Hood duct', 'مجرى الشفاط'], 'led' => ['LED / power', 'إضاءة / كهرباء'] }.freeze
    ST = { 'CONFIRMED' => ['CONFIRMED', 'مؤكد'], 'INFERRED' => ['INFERRED', 'مستنتج'], 'REQUIRES_CONFIRMATION' => ['REQUIRES CONFIRMATION', 'يتطلب تأكيد'], 'MISSING_DATA' => ['MISSING DATA', 'بيانات ناقصة'] }.freeze
    PANEL_W = 92.0

    def kind_label(k, lang)
      (KIND[k] || [k, k])[lang == 'ar' ? 1 : 0]
    end

    def st_label(s, lang)
      (ST[s.to_s] || [s.to_s, s.to_s])[lang == 'ar' ? 1 : 0]
    end

    def tx(lang, en, ar)
      lang == 'ar' ? ar : en
    end

    # ----------------------------------------------------------------------------------------------------------------- elevation frame
    # draws the wall elevation (units, appliances, openings, worktop) into zone (x0,y0,x1,y1); returns frame info
    def elev_frame(sh, data, wall, zone, lang, emphasise_apps: false, top_margin: 16.0, bottom_margin: 30.0, left_margin: 30.0, force_n: nil, code_labels: true)
      zx0, zy0, zx1, zy1 = zone
      units = data[:units].select { |u| u['wall'] == wall['id'] && u['along'] }
      len = [wall['len'].to_f, units.map { |u| u['along'][1] }.max.to_f].max
      ceiling = [(data[:proj].dig('room', 'ceiling', 'v') || data[:cfg]['ceiling']).to_f, units.map { |u| u['z0'] + u['h'] }.max.to_f].max
      n = force_n || ED.pick_scale(len, ceiling, zx1 - zx0 - left_margin - 12, zy1 - zy0 - top_margin - bottom_margin)
      k = 1.0 / n
      ox = zx0 + left_margin + ((zx1 - zx0 - left_margin - 12) - len * k) / 2.0
      ox = zx1 - 12 - ((zx1 - zx0 - left_margin - 12) - len * k) / 2.0 - len * k if false
      oy = zy0 + top_margin + ceiling * k
      mp = ED::Map.new(ox, oy, k, :elev) # X = a (mm from datum), Z = b (AFFL)
      fx = lambda { |a| sh.rtl ? ox + len * k - a * k : ox + a * k } # RTL mirrors X so the datum sits on the right
      rx = ->(a0, a1) { [fx.call(sh.rtl ? a1 : a0), (a1 - a0) * k] }
      sh.line(zx0 + 4, mp.y(0), zx1 - 4, mp.y(0), w: 0.5)
      sh.line(ox - 2, mp.y(ceiling), ox + len * k + 2, mp.y(ceiling), w: 0.18, dash: '3 1.5', color: '#777')
      (data[:proj]['openings'] || []).select { |o| o['wall'] == wall['id'] }.each do |o|
        z0 = o['type'] == 'door' ? 0 : o['sill'].to_f
        x, wd = rx.call(o['off'].to_f, o['off'].to_f + o['w'].to_f)
        sh.rect(x, mp.y(z0 + o['h'].to_f), wd, o['h'].to_f * k, fill: o['type'] == 'door' ? '#efe8d8' : '#d9ecf5', stroke: '#336', sw: 0.2, dash: '1.6 1')
        sh.text(x + wd / 2.0, mp.y(z0 + o['h'].to_f / 2.0), o['id'].to_s, size: 2.4, anchor: :center, color: '#336')
      end
      units.sort_by { |u| u['kind'] == 'base' ? 0 : 1 }.each do |u|
        x, wd = rx.call(*u['along'])
        sh.rect(x, mp.y(u['z0'] + u['h']), wd, u['h'] * k, fill: u['kind'] == 'base' ? '#f1e8d0' : '#ebe9e0', stroke: '#444', sw: 0.2)
        sh.text(x + wd / 2.0, mp.y(u['z0'] + u['h'] / 2.0) + 1, u['code'].to_s, size: [[wd / [u['code'].to_s.length, 1].max * 1.2, 2.8].min, 1.7].max, anchor: :center, color: '#555') if wd > 5 && code_labels
        u['apps'].each do |ap|
          next unless ap['z']

          cx = SiteDocs.along_of(wall, ap['center'])
          aw = ((ap['opening'] || {})['w'] || [u['w'] - 40, 0].max).to_f
          z1 = %w[sink hob hob_gas].include?(ap['kind'].to_s) ? [ap['z'][1], u['z0'] + u['h']].min : ap['z'][1]
          ax = fx.call(sh.rtl ? cx + aw / 2.0 : cx - aw / 2.0)
          sh.rect(ax, mp.y(z1), aw * k, (z1 - ap['z'][0]) * k, fill: '#d9dee4', stroke: emphasise_apps ? '#111' : '#666', sw: emphasise_apps ? 0.35 : 0.18, dash: emphasise_apps ? nil : '1.2 0.8', op: 0.75)
        end
      end
      # datum + FFL markers
      dx = fx.call(0)
      sh.line(dx, mp.y(ceiling) - 6, dx, mp.y(0) + 6, w: 0.25, dash: '5 1.2 1 1.2', color: '#0b57d0')
      sh.poly([[dx - 2.2, mp.y(0) + 6], [dx + 2.2, mp.y(0) + 6], [dx, mp.y(0) + 2.4]], fill: '#0b57d0', stroke: '#0b57d0', sw: 0.1)
      sh.text(dx + (sh.rtl ? -3.4 : 3.4), mp.y(0) + 9.2, "#{ED.t(lang, 'datum')} X=0", size: 2.7, anchor: :pleft, color: '#0b57d0', bold: true)
      sh.text(zx0 + 6, mp.y(0) - 1.4, "#{ED.t(lang, 'ffl')}  Z=0 (AFFL)", size: 2.6, anchor: :pleft, color: '#0b57d0', bold: true, ltr: !sh.rtl ? false : false)
      { mp: mp, fx: fx, rx: rx, k: k, n: n, len: len, ceiling: ceiling, ox: ox, oy: oy, units: units, wall: wall }
    end

    # ordinate dimensions: unit boundaries from the datum (X) and level ticks (Z AFFL)
    def ordinates(sh, fr, lang)
      mp = fr[:mp]
      k = fr[:k]
      yb = mp.y(0)
      xs = EV.edges(fr[:units].flat_map { |u| u['along'] } + [0, fr[:len]])
      xs.each do |a|
        x = fr[:fx].call(a)
        sh.line(x, yb, x, yb + 7 + ((xs.index(a)) % 2) * 5, w: 0.1, color: '#8a1c12')
        sh.text(x + 0.9, yb + 11 + ((xs.index(a)) % 2) * 5, ED.fmt(a), size: 2.4, anchor: :pleft, color: '#8a1c12', rot: 0, ltr: true)
      end
      sh.dim_h(fr[:fx].call(sh.rtl ? fr[:len] : 0), fr[:fx].call(sh.rtl ? 0 : fr[:len]), yb + 24, ED.fmt(fr[:len]), from_y: yb + 0.5)
      zs = EV.edges(fr[:units].flat_map { |u| [u['z0'], u['z0'] + u['h']] } + [0, fr[:ceiling]])
      lx = fr[:fx].call(sh.rtl ? fr[:len] : 0) - 12 # level scale outside the far end of the run (left in both languages)
      zs.each do |z|
        y = mp.y(z)
        sh.line(lx - (sh.rtl ? -1.5 : 1.5), y, lx + (sh.rtl ? -1.5 : 1.5), y, w: 0.12, color: '#8a1c12')
        sh.text(lx + (sh.rtl ? 2.0 : -2.0), y + 0.9, ED.fmt(z), size: 2.4, anchor: sh.rtl ? :pleft : :pright, color: '#8a1c12', ltr: true)
      end
      sh.line(lx, mp.y(fr[:ceiling]), lx, yb, w: 0.12, color: '#8a1c12')
    end

    # ----------------------------------------------------------------------------------------------------------------- service points
    def symbol(sh, x, y, kind, status, id, lang)
      col = COLORS[kind] || '#333'
      dash = status.to_s == 'CONFIRMED' ? nil : '0.9 0.6'
      case kind
      when 'drain' then sh.rect(x - 1.8, y - 1.8, 3.6, 3.6, fill: '#fff', stroke: col, sw: 0.35, dash: dash)
      when 'gas' then sh.poly([[x, y - 2.2], [x + 2.2, y], [x, y + 2.2], [x - 2.2, y]], fill: '#fff', stroke: col, sw: 0.35, dash: dash)
      when 'duct' then sh.circle(x, y, 3.2, fill: '#fff', stroke: col, sw: 0.4, dash: dash)
      else sh.circle(x, y, 1.9, fill: status.to_s == 'CONFIRMED' ? col : '#fff', stroke: col, sw: 0.35, dash: dash)
      end
      ink = status.to_s == 'CONFIRMED' && %w[drain gas duct].include?(kind) == false ? '#fff' : col
      case kind
      when 'elec' # socket outlet: two pins
        [-0.6, 0.6].each { |o| sh.line(x + o, y - 0.9, x + o, y + 0.9, w: 0.28, color: ink) }
      when 'water_cold', 'water_hot' # valve: a cross
        sh.line(x - 1.1, y - 1.1, x + 1.1, y + 1.1, w: 0.25, color: ink)
        sh.line(x - 1.1, y + 1.1, x + 1.1, y - 1.1, w: 0.25, color: ink)
      when 'drain' # waste: a pipe seen end on
        sh.circle(x, y, 1.1, stroke: col, sw: 0.25)
      when 'gas'
        sh.circle(x, y, 0.55, fill: col, stroke: col, sw: 0.1)
      when 'duct' # duct: crossed circle
        sh.line(x - 2.2, y - 2.2, x + 2.2, y + 2.2, w: 0.25, color: col)
        sh.line(x - 2.2, y + 2.2, x + 2.2, y - 2.2, w: 0.25, color: col)
      when 'led'
        sh.line(x - 1.0, y, x + 1.0, y, w: 0.28, color: ink)
      end
      id_label(sh, x, y, id.to_s, col)
      _ = lang
    end

    # service point ID text on a free spot beside its symbol (labels never overlap each other)
    def id_label(sh, x, y, id, col)
      return if id.empty?

      boxes = sh.instance_variable_get(:@id_boxes) || sh.instance_variable_set(:@id_boxes, [])
      w = ED.tw(id, 2.3) + 0.8
      side = sh.rtl ? -1 : 1
      cands = [[3.6 * side, -1.0], [3.6 * side, 2.8], [3.6 * side, -4.8], [-3.6 * side, -1.0], [-3.6 * side, 2.8], [-3.6 * side, -4.8], [3.6 * side, 6.6], [-3.6 * side, 6.6]]
      pick = cands.find do |dx, dy|
        x0 = dx.positive? ? x + dx : x + dx - w
        b = [x0, y + dy - 2.2, x0 + w, y + dy + 0.8]
        boxes.none? { |q| b[0] < q[2] && b[2] > q[0] && b[1] < q[3] && b[3] > q[1] }
      end || cands.first
      dx, dy = pick
      x0 = dx.positive? ? x + dx : x + dx - w
      boxes << [x0, y + dy - 2.2, x0 + w, y + dy + 0.8]
      sh.text(x + dx, y + dy, id, size: 2.3, anchor: dx.positive? ? :pleft : :pright, color: col, bold: true, ltr: true)
    end

    # "X=.. Z=.." text beside a detail point, on the first free spot (never over another label)
    def coord_label(sh, x, y, str, col)
      boxes = sh.instance_variable_get(:@coord_boxes) || sh.instance_variable_set(:@coord_boxes, [])
      w = ED.tw(str, 2.0) + 0.8
      side = sh.rtl ? -1 : 1
      cands = [[3.6 * side, 2.4], [3.6 * side, 5.4], [3.6 * side, 8.4], [-3.6 * side, 2.4], [-3.6 * side, 5.4], [-3.6 * side, 8.4], [3.6 * side, -4.0], [-3.6 * side, -4.0]]
      dx, dy = cands.find do |cx, cy|
        x0 = cx.positive? ? x + cx : x + cx - w
        b = [x0, y + cy - 2.0, x0 + w, y + cy + 0.8]
        boxes.none? { |q| b[0] < q[2] && b[2] > q[0] && b[1] < q[3] && b[3] > q[1] }
      end || cands.first
      x0 = dx.positive? ? x + dx : x + dx - w
      boxes << [x0, y + dy - 2.0, x0 + w, y + dy + 0.8]
      sh.text(x + dx, y + dy, str, size: 2.0, anchor: dx.positive? ? :pleft : :pright, color: col, ltr: true)
    end

    # unit codes drawn after the service points, each on a spot that does not touch a point symbol / ID
    def unit_labels(sh, fr, pts, extra: [])
      mp = fr[:mp]
      boxes = extra.dup
      boxes += pts.map do |p|
        px = fr[:fx].call(p['off'])
        py = mp.y(p['z'])
        [px - 5, py - 5, px + 8 + ED.tw(p['id'].to_s, 2.3), py + 5]
      end
      fr[:units].each do |u|
        x, wd = fr[:rx].call(*u['along'])
        next unless wd > 5

        y0 = mp.y(u['z0'] + u['h'])
        hh = u['h'] * fr[:k]
        fs = [[wd / [u['code'].to_s.length, 1].max * 1.2, 2.8].min, 1.7].max
        w = ED.tw(u['code'].to_s, fs)
        spots = [0.5, 0.2, 0.8, 0.35, 0.65, 0.08, 0.92].map { |f| y0 + hh * f }
        spot = spots.find do |yy|
          b = [x + wd / 2.0 - w / 2.0, yy - fs, x + wd / 2.0 + w / 2.0, yy + 1]
          boxes.none? { |q| b[0] < q[2] && b[2] > q[0] && b[1] < q[3] && b[3] > q[1] }
        end || spots.first
        sh.text(x + wd / 2.0, spot + 1, u['code'].to_s, size: fs, anchor: :center, color: '#555')
      end
    end

    # draws points (elevation) + staggered ordinate labels: X above the ceiling line, Z at the left of the datum
    def points_on(sh, fr, pts, lang, label: true, skip_ids: [])
      mp = fr[:mp]
      xg = {}
      zg = {}
      pts.each do |p|
        (xg[p['off'].to_f.round(-1)] ||= []) << p
        (zg[p['z'].to_f.round(-1)] ||= []) << p
      end
      xl = xg.keys.sort
      zl = zg.keys.sort
      drawn_x = {}
      drawn_z = {}
      seen_pos = Hash.new(0)
      pts.each do |p|
        x = fr[:fx].call(p['off'].to_f)
        y = mp.y(p['z'].to_f)
        col = COLORS[p['kind']] || '#333'
        if label
          kx = p['off'].to_f.round
          kz = p['z'].to_f.round
          unless drawn_x[kx] # one X ordinate label per distinct X (points sharing X share one leader)
            drawn_x[kx] = true
            lvl = xl.index(p['off'].to_f.round(-1)) % 3
            ytop = mp.y(fr[:ceiling]) - 4 - lvl * 5.2
            sh.line(x, y, x, ytop, w: 0.1, dash: '1 1', color: col)
            sh.text(x + (sh.rtl ? -0.8 : 0.8), ytop - 0.8, "X=#{ED.fmt(p['off'])}", size: 2.2, anchor: :pleft, color: col, ltr: true)
          end
          unless drawn_z[kz]
            drawn_z[kz] = true
            lz = zl.index(p['z'].to_f.round(-1)) % 3
            xlabel = fr[:fx].call(sh.rtl ? fr[:len] : 0) - (26 + lz * 15) # Z labels outside the far (left) end of the run in both languages
            xlabel = [xlabel, ED::FRAME + 16].max # keep the ordinate label inside the frame
            sh.line(x, y, xlabel, y, w: 0.1, dash: '1 1', color: col)
            sh.text(xlabel - 0.8, y - 0.8, "Z=#{ED.fmt(p['z'])}", size: 2.2, anchor: :pright, color: col, ltr: true)
          end
        end
        pos = [(x / 4.0).round, (y / 4.0).round]
        dup = seen_pos[pos]
        seen_pos[pos] += 1
        symbol(sh, x, y + dup * 3.4, p['kind'], p['st'], skip_ids.include?(p['id']) ? '' : p['id'], lang)
      end
    end

    def src_label(p, lang)
      return tx(lang, 'user point', 'نقطة مستخدم') if p['src'].to_s.start_with?('user point')

      tx(lang, 'proposed from modeled appliance - verify', 'مقترح من موضع الجهاز - تحقق')
    end

    # point table (compact) inside rect; returns rows that did not fit
    def point_table(sh, pts, rect, lang)
      x0, y0, x1, y1 = rect
      heads = ['ID', tx(lang, 'Type', 'النوع'), tx(lang, 'Equipment', 'الجهاز'), tx(lang, 'Unit', 'وحدة'), 'X', 'Z AFFL', tx(lang, 'Status', 'الحالة'), tx(lang, 'Notes', 'ملاحظات')]
      widths = [16, 30, 40, 16, 18, 20, 44, 70]
      scale = (x1 - x0) / widths.sum
      ws = widths.map { |w| w * scale }
      ws = ws.reverse if sh.rtl
      hs = sh.rtl ? heads.reverse : heads
      rh = 5.0
      fit = [((y1 - y0) / rh).floor - 1, 0].max
      draw = lambda do |vals, y, head|
        vals = vals.reverse if sh.rtl && !head
        vals = hs if head
        x = x0
        sh.rect(x0, y, x1 - x0, rh, fill: head ? '#e9e4d3' : 'none', sw: 0.12, stroke: '#888')
        vals.each_with_index do |v, i|
          sh.line(x, y, x, y + rh, w: 0.08, color: '#aaa') if i.positive?
          sh.text(sh.rtl ? x + ws[i] - 1 : x + 1, y + rh - 1.5, ED.fit_text(v.to_s, 2.6, ws[i] - 2), size: 2.6, anchor: :left, bold: head)
          x += ws[i]
        end
      end
      draw.call(heads, y0, true)
      shown = pts.first(fit)
      shown.each_with_index do |p, i|
        draw.call([p['id'], kind_label(p['kind'], lang), p['device'], p['unit'], ED.fmt(p['off']), ED.fmt(p['z']), st_label(p['st'], lang), src_label(p, lang)], y0 + rh * (i + 1), false)
      end
      pts.drop(fit)
    end

    # ----------------------------------------------------------------------------------------------------------------- DETAIL clusters
    def clusters(pts, k)
      groups = []
      pts.each do |p|
        g = groups.find { |c| c.any? { |q| ((q['off'] - p['off']).abs * k) < 9 && ((q['z'] - p['z']).abs * k) < 9 } }
        g ? g << p : groups << [p]
      end
      groups.select { |c| c.size >= 2 }
    end

    def draw_detail(sh, cell, cluster, fr, label, lang, title, ctx_unit: nil)
      x, y, w, h = cell
      sh.rect(x, y, w, h, stroke: '#333', sw: 0.3)
      sh.text(x + (sh.rtl ? w - 2 : 2), y + 5, "#{ED.t(lang, 'detail')} #{label} - #{title}", size: 3.0, bold: true, anchor: :left)
      inner = [x + 3, y + 9, w - 6, h - 20]
      xs = cluster.map { |p| p['off'] }
      zs = cluster.map { |p| p['z'] }
      a0 = xs.min - 220
      a1 = xs.max + 220
      b0 = zs.min - 160
      b1 = zs.max + 160
      if ctx_unit # whole unit around its service points, so the point is located relative to the cabinet
        a0 = [xs.min - 150, ctx_unit['along'][0] - 40].min
        a1 = [xs.max + 150, ctx_unit['along'][1] + 40].max
        b0 = [zs.min - 120, ctx_unit['z0'] - 30].min
        b1 = [zs.max + 160, [ctx_unit['z0'] + ctx_unit['h'] + 20, zs.max + 450].min].max
      end
      n = ED.pick_scale(a1 - a0, b1 - b0, inner[2], inner[3], EV::DETAIL_SCALES)
      k = 1.0 / n
      cx = inner[0] + inner[2] / 2.0
      cy = inner[1] + inner[3] / 2.0
      mid_a = (a0 + a1) / 2.0
      mid_b = (b0 + b1) / 2.0
      px = ->(a) { sh.rtl ? cx - (a - mid_a) * k : cx + (a - mid_a) * k }
      py = ->(b) { cy - (b - mid_b) * k }
      sh.clip_begin(*inner)
      fr[:units].each do |u|
        ux0 = px.call(sh.rtl ? u['along'][1] : u['along'][0])
        sh.rect(ux0, py.call(u['z0'] + u['h']), (u['along'][1] - u['along'][0]) * k, u['h'] * k, fill: u['kind'] == 'base' ? '#f1e8d0' : '#ebe9e0', stroke: '#444', sw: 0.2)
        u['apps'].each do |ap|
          next unless ap['z']

          acx = SiteDocs.along_of(fr[:wall], ap['center'])
          aw = ((ap['opening'] || {})['w'] || [u['w'] - 40, 0].max).to_f
          z1 = %w[sink hob hob_gas].include?(ap['kind'].to_s) ? [ap['z'][1], u['z0'] + u['h']].min : ap['z'][1]
          sh.rect(px.call(sh.rtl ? acx + aw / 2.0 : acx - aw / 2.0), py.call(z1), aw * k, (z1 - ap['z'][0]) * k, fill: '#d9dee4', stroke: '#666', sw: 0.2, dash: '1.2 0.8', op: 0.7)
        end
      end
      sh.clip_end
      cluster.each do |p|
        symbol(sh, px.call(p['off']), py.call(p['z']), p['kind'], p['st'], p['id'], lang)
        coord_label(sh, px.call(p['off']), py.call(p['z']), "X=#{ED.fmt(p['off'])} Z=#{ED.fmt(p['z'])}", COLORS[p['kind']] || '#333')
      end
      if ctx_unit # point located from the unit's left edge and from the unit bottom (and absolute X / Z in the label)
        u0 = ctx_unit['along'][0]
        ub = ctx_unit['z0']
        cluster.each_with_index do |p, i|
          if (p['off'] - u0).abs >= 1
            xa = px.call(u0)
            xb = px.call(p['off'])
            sh.dim_h([xa, xb].min, [xa, xb].max, inner[1] + inner[3] - 3 - i * 5, ED.fmt((p['off'] - u0).abs), from_y: py.call(p['z']) + 2)
          end
          next unless (p['z'] - ub).abs >= 1

          ya = py.call(ub)
          yb = py.call(p['z'])
          sh.dim_v([ya, yb].min, [ya, yb].max, inner[0] + 6 + i * 6, ED.fmt((p['z'] - ub).abs), from_x: px.call(p['off']) - 2)
        end
      end
      # local dimensions between neighbouring points (same underlying coordinates)
      sx = cluster.sort_by { |p| p['off'] }
      sx.each_cons(2).each_with_index do |(p, q), i|
        next if (p['off'] - q['off']).abs < 1

        sh.dim_h(px.call(p['off']), px.call(q['off']), inner[1] + inner[3] - 3 - i * 5, ED.fmt((q['off'] - p['off']).abs), from_y: py.call(p['z']) + 2)
      end
      sz = cluster.sort_by { |p| p['z'] }
      sz.each_cons(2).each_with_index do |(p, q), i|
        next if (p['z'] - q['z']).abs < 1

        sh.dim_v(py.call(q['z']), py.call(p['z']), inner[0] + 6 + i * 6, ED.fmt((q['z'] - p['z']).abs), from_x: px.call(p['off']) - 2)
      end
      rng = ->(v) { v.min == v.max ? ED.fmt(v.min) : "#{ED.fmt(v.min)}..#{ED.fmt(v.max)}" }
      sh.text(x + (sh.rtl ? w - 2 : 2), y + h - (ctx_unit && h >= 70 ? 7 : 3), "#{ED.t(lang, 'scale')} #{ED.scale_label(n)}   X=#{rng.call(xs)}  Z=#{rng.call(zs)}", size: 2.5, anchor: :left, ltr: false)
      sh.text(x + (sh.rtl ? w - 2 : 2), y + h - 3, ED.fit_text(ED.t(lang, 'detail_note'), 2.2, w - 4), size: 2.2, anchor: :left, color: '#555') if ctx_unit && h >= 70
    end

    # ----------------------------------------------------------------------------------------------------------------- service sheet
    def service_sheets(data, sv, kinds, wall, lang, proj, no, title, extra: nil, label: true, allow_empty: false, unit_details: false)
      pts = sv['points'].select { |p| kinds.include?(p['kind']) && p['wall'] == wall['id'] }
      return [] if pts.empty? && !allow_empty

      sh = ED::Sheet.new(proj, lang: lang, no: no, title: "#{title} - #{wall['id']}", zone: wall['id'].to_s, status: 'DRAFT')
      ax0, ay0, ax1, ay1 = sh.area
      elev_h = 170.0
      cl_probe = nil
      # first pass at full width to learn the scale for cluster detection
      fr_probe = elev_frame(ED::Sheet.new(proj, lang: lang, no: 'tmp', title: 'tmp'), data, wall, [ax0, ay0, ax1 - PANEL_W - 4, ay0 + elev_h], lang)
      cl = label ? clusters(pts, fr_probe[:k]) : []
      ugroups = []
      panel_units = false
      if unit_details && cl.empty? && !pts.empty?
        ugroups = pts.group_by { |p| p['unit'] }.values.sort_by { |g| g.map { |p| p['off'] }.min }
        if ugroups.size <= 3 # few details: they sit in the side panel of the same sheet
          cl = ugroups
          panel_units = true
        end
      end
      zone = cl.empty? ? [ax0, ay0, ax1, ay0 + elev_h] : (sh.rtl ? [ax0 + PANEL_W + 4, ay0, ax1, ay0 + elev_h] : [ax0, ay0, ax1 - PANEL_W - 4, ay0 + elev_h])
      fr = elev_frame(sh, data, wall, zone, lang, code_labels: false)
      ordinates(sh, fr, lang)
      points_on(sh, fr, pts, lang, label: label, skip_ids: panel_units ? [] : cl.flatten.map { |p| p['id'] })
      callout_boxes = []
      extra&.call(sh, fr)
      sh.instance_variable_set(:@scale, ED.scale_label(fr[:n]))
      # detail callouts + cells
      labels = %w[A B C D E F]
      cl.first(3).each_with_index do |c, i|
        mid = [c.sum { |p| p['off'] } / c.size.to_f, c.sum { |p| p['z'] } / c.size.to_f]
        cx = fr[:fx].call(mid[0])
        cy = fr[:mp].y(mid[1])
        callout_boxes << [cx - 12, cy - 12, cx + 12, cy + 12]
        sh.circle(cx, cy, 9, stroke: '#0b57d0', sw: 0.25, dash: '1.6 0.9')
        sh.circle(cx + 9, cy - 9, 3.0, fill: '#fff', stroke: '#0b57d0', sw: 0.3)
        sh.text(cx + 9, cy - 8, labels[i], size: 3.1, anchor: :center, bold: true, color: '#0b57d0')
        ids = c.map { |p| p['unit'] }.uniq.join('/')
        cell_h = (elev_h + 6) / [cl.first(3).size, 1].max.to_f # fewer details = taller cells
        cell = [sh.rtl ? ax0 : ax1 - PANEL_W, ay0 + i * cell_h, PANEL_W, cell_h - 3]
        ctx = panel_units ? data[:units].find { |q| q['code'] == c.first['unit'] && q['wall'] == wall['id'] } : nil
        draw_detail(sh, cell, c, fr, labels[i], lang, "#{kind_label(c.first['kind'], lang)} #{ids}", ctx_unit: ctx)
      end
      detail_sheets = []
      if unit_details && !panel_units && cl.empty? && !pts.empty?
        groups = ugroups
        groups.each_with_index do |g, i|
          cx = fr[:fx].call(g.sum { |p| p['off'] } / g.size.to_f)
          cy = fr[:mp].y(g.map { |p| p['z'] }.min) + 9
          callout_boxes << [cx - 4, cy - 4, cx + 4, cy + 4]
          sh.circle(cx, cy, 3.0, fill: '#fff', stroke: '#0b57d0', sw: 0.3)
          sh.text(cx, cy + 1.0, ('A'.ord + i).chr, size: 3.0, anchor: :center, bold: true, color: '#0b57d0')
        end
        detail_sheets = unit_detail_sheets(data, groups, fr, wall, lang, proj, "#{no}-D", title)
      end
      unit_labels(sh, fr, pts, extra: callout_boxes)
      rest = label ? point_table(sh, pts, [ax0, ay0 + elev_h + 12, ax1, ay1 - 2], lang) : [] # the coordinated sheet is an overview: the full table is S-08
      sh.text(sh.rtl ? ax1 - 2 : ax0 + 2, ay0 + elev_h + 16, ED.t(lang, 'see_s08'), size: 2.8, anchor: :left, color: '#444') unless label
      sh.text(sh.rtl ? ax1 - 2 : ax0 + 2, ay0 + elev_h + 8, ED.t(lang, 'inferred_note'), size: 2.6, anchor: :left, color: '#8a1c12')
      out = [sh]
      out.concat(detail_sheets)
      out.concat(rest_table(proj, lang, no, title, rest)) unless rest.empty?
      out
    end

    # enlarged installation details (A, B, C ...) - one cell per unit, built from the SAME service coordinates
    def unit_detail_sheets(data, groups, fr, wall, lang, proj, no, title)
      npages = (groups.size / 6.0).ceil
      per = (groups.size / npages.to_f).ceil # spread evenly: no nearly-empty last sheet
      pages = groups.each_slice(per).to_a
      pages.each_with_index.map do |chunk, pi|
        sh = ED::Sheet.new(proj, lang: lang, no: pages.size > 1 ? "#{no}#{pi + 1}" : no, title: "#{title} - #{ED.t(lang, 'detail')} - #{wall['id']}", zone: wall['id'].to_s)
        ax0, ay0, ax1, ay1 = sh.area
        cols = per <= 2 ? per : (per <= 4 ? 2 : 3)
        rows = (per / cols.to_f).ceil
        cw = (ax1 - ax0 - 4) / cols.to_f
        ch = (ay1 - ay0 - 4) / rows.to_f
        chunk.each_with_index do |g, i|
          col = i % cols
          row = i / cols
          cx = sh.rtl ? ax1 - 2 - (col + 1) * cw : ax0 + 2 + col * cw
          u = data[:units].find { |q| q['code'] == g.first['unit'] && q['wall'] == wall['id'] }
          draw_detail(sh, [cx, ay0 + 2 + row * ch, cw - 3, ch - 3], g, fr, ('A'.ord + pi * per + i).chr, lang, "#{kind_label(g.first['kind'], lang)} #{g.first['unit']}", ctx_unit: u)
        end
        sh.instance_variable_set(:@scale, 'AS NOTED')
        sh
      end
    end

    def rest_table(proj, lang, no, title, rows)
      ED.table_sheets(proj, lang, "#{no}-T", "#{title} (+)", ['ID', tx(lang, 'Type', 'النوع'), tx(lang, 'Equipment', 'الجهاز'), tx(lang, 'Unit', 'وحدة'), 'X', 'Z AFFL', tx(lang, 'Status', 'الحالة')],
                      rows.map { |p| [p['id'], kind_label(p['kind'], lang), p['device'], p['unit'], ED.fmt(p['off']), ED.fmt(p['z']), st_label(p['st'], lang)] }, [20, 40, 70, 24, 30, 30, 160], per_page: 34)
    end
  end
end
