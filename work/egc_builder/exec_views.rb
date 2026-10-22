# frozen_string_literal: true

require 'json'

module EGC
  # Orthographic views, sections and automatic DETAIL zooms built from the real part boxes of a unit (Drawings.boxes).
  # The same draw_* functions render the parent view and its enlarged DETAIL (different scale + clip), so a detail can never
  # disagree with the parent drawing.
  module ExecViews
    module_function

    ED = ExecDraw
    STY = {
      'front' => ['#ecdcbc', '#5c4b2c'], 'carcass' => ['#f8f6ef', '#222'], 'back' => ['#e4dfd0', '#444'], 'drawer' => ['#f1eee4', '#444'],
      'profile' => ['#6b6b6b', '#111'], 'appliance' => ['#d9dee4', '#555'], 'top' => ['#cdd0d4', '#111'], 'glass' => ['#cfe6f2', '#456']
    }.freeze
    DETAIL_SCALES = [0.2, 0.5, 1, 2, 2.5, 4, 5, 8, 10, 12.5, 15, 20].freeze
    GRID = %w[side_l side_r].freeze

    def style(b)
      return ['#ffffff', '#777'] if b[:role] == 'hw'

      STY[b[:mat].to_s] || ['#f3f3f3', '#333']
    end

    def unit_top(bs)
      bs.reject { |q| q[:role] == 'hw' || (q[:role] == 'appliance' && %w[sink hob hob_gas hob_electric].include?(q[:part])) }.map { |q| q[:z1] }.max || 1e9
    end

    # ----------------------------------------------------------------------------------------------- unit geometry summary
    def summary(bs)
      real = bs.reject { |b| b[:role] == 'hw' && b[:pid].to_s.include?('-') && %w[leg leg_base].include?(b[:part]) }
      all = bs.reject { |b| (b[:role] == 'hw' && !%w[leg leg_base].include?(b[:part])) || (b[:role] == 'appliance' && %w[sink hob hob_gas hob_electric].include?(b[:part])) }
      xs = all.flat_map { |b| [b[:x0], b[:x1]] }
      ds = all.flat_map { |b| [b[:d0], b[:d1]] }
      zs = all.flat_map { |b| [b[:z0], b[:z1]] }
      sides = bs.select { |b| GRID.include?(b[:part]) }
      carc_d = sides.empty? ? nil : [sides.map { |b| b[:d0] }.min, sides.map { |b| b[:d1] }.max]
      jd = all.reject { |b| b[:role] == 'appliance' || b[:role] == 'hw' }.flat_map { |b| [b[:d0], b[:d1]] } # depth of the joinery only: a free-standing appliance may stand proud of its housing
      { x: [xs.min, xs.max], d: [ds.min, ds.max], z: [zs.min, zs.max], carcass_d: carc_d, joinery_d: (jd.empty? ? [ds.min, ds.max] : [jd.min, jd.max]), real: real, all: all }
    end

    # groove geometry is derived from the model: back panel engagement in the side panel
    def back_groove(bs)
      back = bs.find { |b| b[:part] == 'back' && b[:notes].to_s.include?('groove') }
      side = bs.find { |b| b[:part] == 'side_l' }
      return nil unless back && side

      { depth: side[:x1] - back[:x0], offset: back[:d0] - side[:d0], width: back[:d1] - back[:d0], back_thk: back[:d1] - back[:d0], side_thk: side[:x1] - side[:x0],
        back: back, side: side, side_r: bs.find { |b| b[:part] == 'side_r' } }
    end

    # ----------------------------------------------------------------------------------------------- front elevation
    def draw_front(sh, mp, bs, hinge_sides: nil)
      order = bs.reject { |b| b[:role] == 'hw' && !%w[leg leg_base profile].include?(b[:part]) }.sort_by { |b| [b[:d1], b[:d0]] }
      order.each do |b|
        fill, stroke = style(b)
        x = mp.x(b[:x0])
        y = mp.y(b[:z1])
        w = mp.len(b[:x1] - b[:x0])
        h = mp.len(b[:z1] - b[:z0])
        if b[:role] == 'appliance' && !%w[leg].include?(b[:part])
          z1 = [b[:z1], unit_top(bs)].min # sink / hob bodies rise above the worktop: the cabinet drawing stops at the unit top
          next if z1 <= b[:z0]

          sh.rect(x, mp.y(z1), w, mp.len(z1 - b[:z0]), fill: fill, stroke: '#555', sw: 0.25, dash: '1.2 0.8', op: 0.55)
        else
          sh.rect(x, y, w, h, fill: fill, stroke: stroke, sw: b[:mat] == 'front' ? 0.22 : 0.16)
        end
      end
      # door swing symbols (apex at the hinge side): doors only, from the real front boxes
      doors = bs.select { |b| b[:mat] == 'front' && %w[door door1 door2].include?(b[:part]) }
      doors.each_with_index do |b, i|
        cups = bs.select { |q| q[:part] == 'sample_hinge_cup' && q[:z0] >= b[:z0] - 2 && q[:z1] <= b[:z1] + 2 && q[:x0] >= b[:x0] - 2 && q[:x1] <= b[:x1] + 2 }
        left = if hinge_sides then hinge_sides[i] == :left
               elsif cups.any? then cups.sum { |q| (q[:x0] + q[:x1]) / 2.0 } / cups.size < (b[:x0] + b[:x1]) / 2.0
               else (b[:x0] + b[:x1]) / 2.0 < (bs.map { |q| q[:x1] }.max / 2.0)
               end
        ax = left ? mp.x(b[:x0]) : mp.x(b[:x1])
        bx = left ? mp.x(b[:x1]) : mp.x(b[:x0])
        sh.line(ax, mp.y((b[:z0] + b[:z1]) / 2.0), bx, mp.y(b[:z1]), w: 0.1, dash: '1.4 0.9', color: '#555')
        sh.line(ax, mp.y((b[:z0] + b[:z1]) / 2.0), bx, mp.y(b[:z0]), w: 0.1, dash: '1.4 0.9', color: '#555')
      end
    end

    # ----------------------------------------------------------------------------------------------- section A-A (vertical, cut at x)
    def draw_section_a(sh, mp, bs, xcut)
      vis = bs.reject { |b| b[:role] == 'hw' && !%w[leg leg_base profile].include?(b[:part]) }
      cut, beyond = vis.partition { |b| b[:x0] <= xcut + 0.01 && b[:x1] >= xcut - 0.01 && !%w[side_l side_r].include?(b[:part]) }
      beyond.each do |b|
        next unless GRID.include?(b[:part]) || b[:mat] == 'drawer'

        sh.rect(mp.x(b[:d0]), mp.y(b[:z1]), mp.len(b[:d1] - b[:d0]), mp.len(b[:z1] - b[:z0]), fill: 'none', stroke: '#999', sw: 0.1, dash: '1.2 0.8')
      end
      cut.each do |b|
        if b[:role] == 'appliance' && b[:part] != 'leg'
          z1 = [b[:z1], unit_top(bs)].min
          next if z1 <= b[:z0]

          sh.rect(mp.x(b[:d0]), mp.y(z1), mp.len(b[:d1] - b[:d0]), mp.len(z1 - b[:z0]), fill: '#e8ecf0', stroke: '#555', sw: 0.2, dash: '1.2 0.8', op: 0.6)
        else
          sh.hatch(mp.x(b[:d0]), mp.y(b[:z1]), [mp.len(b[:d1] - b[:d0]), 0.3].max, [mp.len(b[:z1] - b[:z0]), 0.3].max, sw: 0.25)
        end
      end
    end

    # ----------------------------------------------------------------------------------------------- plan section B-B (cut at z)
    def draw_plan(sh, mp, bs, zcut, groove: true)
      vis = bs.reject { |b| b[:role] == 'hw' && b[:part] != 'profile' }
      cut = vis.select { |b| b[:z0] <= zcut + 0.01 && b[:z1] >= zcut - 0.01 && b[:part] != 'leg' }
      cut.sort_by { |b| b[:mat] == 'front' ? 1 : 0 }.each do |b|
        x = mp.x(b[:x0])
        y = mp.y(b[:d0])
        w = [mp.len(b[:x1] - b[:x0]), 0.3].max
        h = [mp.len(b[:d1] - b[:d0]), 0.3].max
        if b[:role] == 'appliance'
          sh.rect(x, y, w, h, fill: '#e8ecf0', stroke: '#555', sw: 0.2, dash: '1.2 0.8', op: 0.6)
        else
          sh.hatch(x, y, w, h, sw: 0.25)
        end
      end
      return unless groove

      g = back_groove(bs)
      return unless g

      [[g[:side], :l], [g[:side_r], :r]].each do |side, which|
        next unless side

        gx0 = which == :l ? side[:x1] - g[:depth] : side[:x0]
        gx1 = which == :l ? side[:x1] : side[:x0] + g[:depth]
        gx0 = side[:x0] if which == :r && false
        # groove is cut in the INNER face: left side -> towards +x, right side -> towards -x
        gx0, gx1 = which == :l ? [side[:x1] - g[:depth], side[:x1]] : [side[:x0], side[:x0] + g[:depth]]
        sh.rect(mp.x(gx0), mp.y(g[:back][:d0]), mp.len(gx1 - gx0), mp.len(g[:width]), fill: '#fff', stroke: '#111', sw: 0.12)
      end
      # back panel drawn over the grooves (it engages both)
      b = g[:back]
      sh.hatch(mp.x(b[:x0]), mp.y(b[:d0]), mp.len(b[:x1] - b[:x0]), [mp.len(b[:d1] - b[:d0]), 0.3].max, sw: 0.2)
    end

    # ----------------------------------------------------------------------------------------------- dimension chains
    # unique sorted edges within tolerance
    def edges(vals, tol = 0.6)
      out = []
      vals.compact.sort.each { |v| out << v if out.empty? || (v - out.last).abs > tol }
      out
    end

    def front_panels(bs)
      bs.select { |b| b[:mat] == 'front' && %w[door door1 door2 drawer_front flap flap_upper flap_lower filler].include?(b[:part]) }
    end

    # ----------------------------------------------------------------------------------------------- DETAIL system
    # Candidate detail callouts for a unit. Each: { key:, title(en/ar), view: :plan|:section|:front, region: [a0,a1,b0,b1], status: text key or nil }
    def detail_candidates(bs, d, cfg, ctx = {})
      out = []
      g = back_groove(bs)
      if g
        out << { key: :groove, view: :plan, region: [g[:side][:x0] - 4, g[:side][:x1] + 36, g[:side][:d0] - 6, g[:back][:d1] + 30], title: 'back_groove', note: nil }
      end
      doors = bs.select { |b| b[:mat] == 'front' && %w[door door1 door2].include?(b[:part]) }
      if doors.any?
        db = doors.min_by { |b| b[:x0] }
        out << { key: :hinge, view: :plan, region: [db[:x0] - 6, db[:x0] + 56, db[:d0] - 40, db[:d1] + 14], title: 'hinge_zone', note: 'req_hinge', zcut: ((db[:z0] + db[:z1]) / 2.0), anchor_zone: db }
      end
      dfs = bs.select { |b| b[:part] == 'drawer_front' }
      if dfs.any?
        df = dfs.min_by { |b| b[:z0] }
        out << { key: :drawer, view: :section, region: [df[:d0] - 150, df[:d1] + 30, df[:z0] - 22, df[:z1] + 22], title: 'drawer_zone', note: 'req_runner' }
      end
      apps = bs.select { |b| b[:role] == 'appliance' && b[:part] != 'leg' }
      if apps.any?
        a = apps.max_by { |b| (b[:x1] - b[:x0]) * (b[:z1] - b[:z0]) }
        out << { key: :appliance, view: :front, region: [a[:x0] - 40, a[:x1] + 40, a[:z0] - 30, a[:z1] + 30], title: 'appliance_opening', note: 'req_app', app: a }
      end
      if %w[sink sink_drawer hob hob_oven].include?(d['type'].to_s)
        out << { key: :cutout, view: :cutout, region: nil, title: 'cutout', note: nil }
      end
      out << { key: :lift, view: :lift, region: nil, title: 'lift', note: 'req_mech' } if d['mech'].to_s == 'LIFT_UP'
      fil = bs.find { |b| b[:part] == 'filler' && (b[:x1] - b[:x0]) < 150 }
      out << { key: :filler, view: :front, region: [fil[:x0] - 20, fil[:x1] + 20, fil[:z0], [fil[:z1], fil[:z0] + 120].min], title: 'filler', note: nil } if fil
      out
    end

    # draw one DETAIL into the cell (x,y,w,h) in sheet mm; returns the scale N used
    def draw_detail(sh, det, bs, cell, label, cfg, d, ctx = {})
      x, y, w, h = cell
      lang = sh.lang
      sh.rect(x, y, w, h, stroke: '#333', sw: 0.3)
      sh.text(x + 2, y + 5, "#{ED.t(lang, 'detail')} #{label}  -  #{ED.t(lang, det[:title])}", size: 3.2, bold: true, anchor: :left) unless sh.rtl
      sh.text(x + w - 2, y + 5, "#{ED.t(lang, 'detail')} #{label}  -  #{ED.t(lang, det[:title])}", size: 3.2, bold: true, anchor: :left) if sh.rtl
      inner = [x + 2, y + 9, w - 4, h - 22]
      case det[:view]
      when :cutout then return draw_cutout_detail(sh, inner, label, cfg, d, bs)
      when :lift then return draw_lift_detail(sh, inner, cfg, d, bs)
      end
      a0, a1, b0, b1 = det[:region]
      n = ED.pick_scale((a1 - a0) + 4, (b1 - b0) + 4, inner[2] - 16, inner[3] - 6, DETAIL_SCALES)
      k = 1.0 / n
      cxm = inner[0] + inner[2] / 2.0
      cym = inner[1] + inner[3] / 2.0
      mid_a = (a0 + a1) / 2.0
      mid_b = (b0 + b1) / 2.0
      kind = det[:view] == :plan ? :plan : :elev
      mp = ED::Map.new(cxm - mid_a * k, cym + (kind == :plan ? -mid_b * k : mid_b * k), k, kind)
      sh.clip_begin(inner[0], inner[1], inner[2], inner[3])
      case det[:view]
      when :plan then draw_plan(sh, mp, bs, det[:zcut] || ctx[:zmid], groove: true)
      when :section then draw_section_a(sh, mp, bs, ctx[:xmid])
      else draw_front(sh, mp, bs)
      end
      sh.clip_end
      sh.text(x + 2, y + h - 3, "#{ED.t(lang, 'scale')} #{ED.scale_label(n)}", size: 2.8, anchor: :left) unless sh.rtl
      sh.text(x + w - 2, y + h - 3, "#{ED.t(lang, 'scale')} #{ED.scale_label(n)}", size: 2.8, anchor: :left) if sh.rtl
      dim_detail(sh, det, bs, mp, inner, cfg, lang)
      sh.text(sh.rtl ? x + w - 2 : x + 2, y + h - 8, ED.t(lang, det[:note]), size: 2.5, color: '#8a1c12', anchor: :left) if det[:note]
      sh.text(sh.rtl ? x + w - 2 : x + 2, y + h - 12.5, det[:board_note], size: 2.5, bold: true, anchor: :left) if det[:board_note]
      n
    end

    def dim_detail(sh, det, bs, mp, inner, cfg, lang)
      case det[:key]
      when :groove
        g = back_groove(bs)
        return unless g

        s = g[:side]
        b = g[:back]
        bx = mp.x(s[:x0])
        top = mp.y(s[:d0])
        # rear edge label + 5 mm offset, groove width, depth, side thickness, back thickness (all from the model geometry)
        sh.dim_v(mp.y(s[:d0]), mp.y(b[:d0]), mp.x(s[:x0]) - 4.5, ED.fmt(g[:offset]), from_x: mp.x(s[:x0]) - 0.5)
        sh.dim_v(mp.y(b[:d0]), mp.y(b[:d1]), mp.x(s[:x1]) + 4.5, ED.fmt(g[:width]), from_x: mp.x(s[:x1]) + 0.5)
        sh.dim_h(mp.x(b[:x0]), mp.x(s[:x1]), mp.y(b[:d1]) + 7, ED.fmt(g[:depth]), from_y: mp.y(b[:d1]) + 0.5)
        sh.dim_h(mp.x(s[:x0]), mp.x(s[:x1]), top - 4.5, ED.fmt(g[:side_thk]), from_y: top - 0.5)
        sh.text(bx - 1, top - 8.5, ED.t(lang, 'rear_edge'), size: 2.4, anchor: :pleft, bold: true)
        sh.text(mp.x(b[:x0]) + 2, mp.y(b[:d0]) + (mp.y(b[:d1]) - mp.y(b[:d0])) / 2.0 - 3.4, "#{ED.t(lang, 'back')} #{ED.fmt(g[:back_thk])}", size: 2.4, anchor: :pleft)
      when :hinge
        db = det[:anchor_zone]
        sd = bs.find { |b| b[:part] == 'side_l' }
        return unless db && sd

        sh.dim_h(mp.x(db[:x0]), mp.x(sd[:x0]), mp.y(db[:d1]) + 5.5, ED.fmt(db[:x0] - sd[:x0]).sub('-', ''), from_y: mp.y(db[:d1]) + 0.5) if (db[:x0] - sd[:x0]).abs > 0.4
        sh.dim_v(mp.y(db[:d0]), mp.y(db[:d1]), mp.x(db[:x0]) - 4.0, ED.fmt(db[:d1] - db[:d0]), from_x: mp.x(db[:x0]) - 0.5)
        sh.text(mp.x(db[:x0]) + 1.5, mp.y(db[:d1]) + 9.5, "#{ED.t(lang, 'front_thk')} #{ED.fmt(db[:d1] - db[:d0])}", size: 2.4, anchor: :pleft)
      when :drawer
        dfs = bs.select { |b| b[:part] == 'drawer_front' }
        df = dfs.min_by { |b| b[:z0] }
        sh.dim_v(mp.y(df[:z1]), mp.y(df[:z0]), mp.x(df[:d1]) + 5, ED.fmt(df[:z1] - df[:z0]), from_x: mp.x(df[:d1]) + 0.5, side: :right)
        box = bs.select { |b| b[:mat] == 'drawer' && b[:z0] >= df[:z0] - 1 && b[:z1] <= df[:z1] + 1 }
        if box.any?
          bz0 = box.map { |b| b[:z0] }.min
          bz1 = box.map { |b| b[:z1] }.max
          bd1 = box.map { |b| b[:d1] }.max
          sh.dim_v(mp.y(bz1), mp.y(bz0), mp.x(bd1) - 6, ED.fmt(bz1 - bz0), from_x: mp.x(bd1) - 1.5, side: :left)
          # board thicknesses read from the model: drawer box board (18 mm) and the drawer front
          dback = box.select { |b| b[:part] == 'drawer_back' }.max_by { |b| b[:d1] }
          inside = ->(x, y) { x > inner[0] + 2 && x < inner[0] + inner[2] - 8 && y > inner[1] + 6 && y < inner[1] + inner[3] }
          if dback && inside.call(mp.x(dback[:d0]), mp.y(bz1) - 5.5) && inside.call(mp.x(dback[:d1]), mp.y(bz1) - 5.5)
            sh.dim_h(mp.x(dback[:d0]), mp.x(dback[:d1]), mp.y(bz1) - 5.5, ED.fmt(dback[:d1] - dback[:d0]), from_y: mp.y(bz1) - 0.5)
            det[:board_note] = "#{ED.t(lang, 'drawer_board')} #{ED.fmt(dback[:d1] - dback[:d0])} mm"
          end
          sh.dim_h(mp.x(df[:d0]), mp.x(df[:d1]), mp.y(df[:z1]) - 5.5, ED.fmt(df[:d1] - df[:d0]), from_y: mp.y(df[:z1]) - 0.5) if inside.call(mp.x(df[:d0]), mp.y(df[:z1]) - 5.5) && inside.call(mp.x(df[:d1]), mp.y(df[:z1]) - 5.5)
        end
      when :appliance
        a = det[:app]
        sh.dim_h(mp.x(a[:x0]), mp.x(a[:x1]), mp.y(a[:z0]) + 6, ED.fmt(a[:x1] - a[:x0]), from_y: mp.y(a[:z0]) + 0.5)
        sh.dim_v(mp.y(a[:z1]), mp.y(a[:z0]), mp.x(a[:x0]) - 5, ED.fmt(a[:z1] - a[:z0]), from_x: mp.x(a[:x0]) - 0.5)
      end
    end

    def draw_cutout_detail(sh, inner, _label, cfg, d, bs)
      kind = d['type'].to_s.start_with?('sink') ? :sink : :hob
      r = Kitchen.cutout_rect(kind, 0, d['w'].to_f, cfg)
      return nil unless r

      w = d['w'].to_f
      dep = d['d'].to_f
      n = ED.pick_scale(w + 40, dep + 40, inner[2] - 12, inner[3] - 10, DETAIL_SCALES)
      k = 1.0 / n
      ox = inner[0] + (inner[2] - w * k) / 2.0
      oy = inner[1] + 6
      sh.rect(ox, oy, w * k, dep * k, fill: '#cdd0d4', stroke: '#111', sw: 0.25)
      sh.rect(ox + r[0] * k, oy + r[1] * k, r[2] * k, r[3] * k, fill: '#fff', stroke: '#111', sw: 0.25)
      sh.dim_h(ox + r[0] * k, ox + (r[0] + r[2]) * k, oy + dep * k + 5, ED.fmt(r[2]), from_y: oy + (r[1] + r[3]) * k)
      sh.dim_v(oy + r[1] * k, oy + (r[1] + r[3]) * k, ox + w * k + 5, ED.fmt(r[3]), from_x: ox + (r[0] + r[2]) * k, side: :right)
      sh.dim_h(ox, ox + r[0] * k, oy + dep * k + 11, ED.fmt(r[0]), from_y: oy + dep * k) if r[0] > 1
      sh.dim_v(oy, oy + r[1] * k, ox - 5, ED.fmt(r[1]), from_x: ox) if r[1] > 1
      n
    end

    def draw_lift_detail(sh, inner, cfg, d, bs)
      fp = bs.find { |b| b[:part] == 'flap' }
      return nil unless fp

      hh = fp[:z1] - fp[:z0]
      ft = fp[:d1] - fp[:d0]
      samples, thetas, dds, dzs = Cabinet.allocate.flap_path
      pivot = [fp[:d1], fp[:z1]] # outer top edge of the closed front (d, z)
      n = ED.pick_scale(hh + 60, hh + 80, inner[2] - 10, inner[3] - 8, DETAIL_SCALES)
      k = 1.0 / n
      ox = inner[0] + 6
      oy = inner[1] + inner[3] - 4
      mp = ED::Map.new(ox - (pivot[0] - ft) * k, oy + fp[:z0] * k, k, :elev)
      cab = bs.select { |b| %w[side_l].include?(b[:part]) }.first
      mp.then { |m| sh.rect(m.x(cab[:d0]), m.y(cab[:z1]), m.len(cab[:d1] - cab[:d0]), m.len(cab[:z1] - cab[:z0]), fill: '#f8f6ef', stroke: '#777', sw: 0.2, dash: '1.2 0.8') } if cab
      [0.0, 0.25, 0.5, 0.75, 1.0].each do |u|
        i = (u * (samples.size - 1)).round
        th = thetas[i]
        pts = [[0, 0], [ft, 0], [ft, -hh], [0, -hh]].map do |pd, pz|
          # hang below the outer top edge, rotate about it (d,z plane), then translate by the hinge-line travel
          q = MotionProfiles.rot2([pd - ft, pz], [0, 0], th)
          [pivot[0] + dds[i] + q[0] + ft - ft, pivot[1] + dzs[i] + q[1]]
        end
        poly = pts.map { |pd, pz| [mp.x(pd), mp.y(pz)] }
        sh.poly(poly, fill: u.zero? || u == 1.0 ? '#ecdcbc' : 'none', stroke: u.zero? || u == 1.0 ? '#5c4b2c' : '#8a6d3b', sw: u.zero? || u == 1.0 ? 0.25 : 0.14, dash: u.zero? || u == 1.0 ? nil : '1.4 0.9')
        lp = poly.last
        sh.text(lp[0] + 1.2, lp[1] - 1.0, "#{(u * 100).round}%", size: 2.4, anchor: :pleft, color: '#444', ltr: true)
      end
      sh.text(inner[0] + 2, inner[1] + 3, "#{(thetas.last).abs.round} deg / +#{ED.fmt(dds.last)} mm", size: 2.6, anchor: :pleft, ltr: true)
      n
    end
  end
end
