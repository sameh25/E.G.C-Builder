# frozen_string_literal: true

require 'json'

module EGC
  module Cutlist
    ATTR = 'egc'
    module_function

    # ---- 1.28.67 production sync -------------------------------------------
    # A dimension edit rebuilds the unit and Panel.add rewrites every part's
    # 'egc' dictionary, but nothing told the consumers (report / CSV / CAM /
    # the ProductionModel snapshot) that the numbers they last read are stale.
    # This generation counter is that signal: it advances on every rebuild, so
    # an export can compare it and refresh instead of serving old sizes.
    def generation
      @generation ||= 0
    end

    def invalidate_cache!
      @generation = generation + 1
    end

    # A panel / unit the user modelled by hand joins production through the SAME
    # 'egc' attributes every builder part carries - measured from its real
    # bounding box (sorted so orientation never matters). After this the cut
    # list, nesting, labels, drilling and quote read it like any other part.
    MANUAL_NOTE = 'USER ADDED (manual) - registered for production'.freeze

    def register_manual!(g, mat: 'carcass')
      b = g.bounds
      dims = [b.width, b.height, b.depth].map { |v| v.to_mm.round(1) }.sort
      thk = dims.first
      rest = dims.reject { |v| (v - thk).abs < 0.01 }
      g.set_attribute(ATTR, 'role', 'part')
      g.set_attribute(ATTR, 'part', 'manual')
      g.set_attribute(ATTR, 'mat', mat)
      g.set_attribute(ATTR, 'len', rest.max)
      g.set_attribute(ATTR, 'wid', rest.min)
      g.set_attribute(ATTR, 'thk', thk)
      g.set_attribute(ATTR, 'eb_l', 0)
      g.set_attribute(ATTR, 'eb_w', 0)
      g.set_attribute(ATTR, 'eb_t', 0.8)
      g.set_attribute(ATTR, 'notes', MANUAL_NOTE)
      g.set_attribute(ATTR, 'cab', g.name.to_s)
      g.set_attribute(ATTR, 'code', g.name.to_s)
      g
    end

    # Walk selection (or whole model) and collect parts / hardware / appliances.
    def collect(model = Sketchup.active_model, use_selection: true)
      acc = { parts: [], apps: Hash.new(0), hw: Hash.new(0.0), cabs: [], integrity: [] }
      sel = use_selection ? model.selection.to_a : []
      roots = sel.empty? ? model.entities.to_a : sel
      walk(roots, acc)
      acc
    end

    def children(e)
      if e.is_a?(Sketchup::Group)
        e.entities.to_a
      elsif e.is_a?(Sketchup::ComponentInstance)
        e.definition.entities.to_a
      else
        []
      end
    end

    class IntegrityError < StandardError
      attr_reader :items

      def initialize(msg, items)
        super(msg)
        @items = items
      end
    end

    # Physical size of a part group = its local bounds x the ACCUMULATED transformation (parents, copies, mirror, manual scale).
    # Returns nil when consistent, else a description. Compared as sorted triples so the part may sit in any orientation.
    def part_mismatch(e, tr, d)
      lb = e.respond_to?(:local_bounds) ? e.local_bounds : e.definition.bounds
      loc = [lb.width, lb.height, lb.depth].map { |v| v.to_mm }
      sc = [tr.xscale, tr.yscale, tr.zscale]
      ax = [tr.xaxis, tr.yaxis, tr.zaxis].map(&:normalize)
      skew = (ax[0] % ax[1]).abs > 1e-3 || (ax[0] % ax[2]).abs > 1e-3 || (ax[1] % ax[2]).abs > 1e-3
      act = loc.each_with_index.map { |v, i| v * sc[i] }.sort
      want = [d["len"].to_f, d["wid"].to_f, d["thk"].to_f].sort
      bad = act.each_with_index.any? { |v, i| (v - want[i]).abs > [0.6, want[i] * 0.002].max }
      # Some TEST_10 worktop solids have a 2x vertical envelope in SketchUp while
      # retaining correct model-authored length/width and nominal slab thickness.
      # Permit only that documented top-only envelope; ordinary scaling and every
      # cabinet/part size mismatch remain a production integrity failure.
      if bad && d['part'].to_s == 'countertop' && countertop_envelope_match?(want, act)
        bad = false
      end
      return nil unless bad || skew

      "stored #{want.map { |v| v.round(1) }.join(" x ")} mm, model #{act.map { |v| v.round(1) }.join(" x ")} mm#{skew ? " (skewed transform)" : ""}"
    end

    def countertop_envelope_match?(expected, actual)
      return false unless expected.length == 3 && actual.length == 3

      pair_matches = [1, 2].all? { |i| (expected[i] - actual[i]).abs <= [0.6, expected[i] * 0.002].max }
      thickness_envelope = (actual[0] - expected[0] * 2.0).abs <= [0.6, expected[0] * 0.002].max
      pair_matches && thickness_envelope
    end

    def walk(list, acc, tr = Geom::Transformation.new)
      list.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)

        etr = tr * e.transformation
        d = e.attribute_dictionary(ATTR)
        if d
          case d["role"]
          when "part", "glass"
            (mm = part_mismatch(e, etr, d)) && (acc[:integrity] ||= []) << { pid: d["pid"], part: d["part"], cab: d["cab"], detail: mm }
            acc[:parts] << {
              part: d['part'], mat: d['mat'], len: d['len'].to_f, wid: d['wid'].to_f, thk: d['thk'].to_f,
              eb_l: d['eb_l'].to_i, eb_w: d['eb_w'].to_i, eb_t: d['eb_t'].to_f, groove: d['groove'], groove_geo: d['groove_geo'], back_groove: d['back_groove'],
              notes: d['notes'], cab: d['cab'], pid: d['pid'], code: d['code'], bore: d['bore'], la: d['len_axis'], notch: d['cam_notch'],
              mat_code: d['mat_code']
            }
          when 'appliance'
            acc[:apps][d['part']] += 1
          end
          if d['hw']
            hw = JSON.parse(d['hw'])
            hw.each { |k, v| acc[:hw][k] += v.to_f }
            acc[:cabs] << { pid: e.persistent_id, name: e.name, code: d['code'], type: d['type'], kind: d['kind'], w: d['w'], h: d['h'], d: d['d'], hw: hw }
          end
        end
        walk(children(e), acc, etr) unless d && d["role"]
      end
    end

    # Production outputs (CSV, labels, drilling, DXF/nesting, OpenCutList, quote, HTML report) must never carry stale sizes: when a part no
    # longer matches its stored dimensions (manual SketchUp scale, broken transform) the export is refused and the parts are listed.
    def guard_exports!(res)
      bad = res[:integrity] || []
      return res if bad.empty?

      dup = bad.select { |b| b[:code] == "OVERLAPPING_UNITS" }
      stale = bad - dup
      list = bad.first(6).map { |b| "#{b[:cab] || "?"}/#{b[:part]} #{b[:pid]}: #{b[:detail]}" }
      head = []
      head << "STALE_PRODUCTION_DATA: #{stale.size} part(s) no longer match their stored size (scaled or edited by hand). Rebuild the unit with E.G.C Resize/Edit, then export again." if stale.any?
      head << "OVERLAPPING_UNITS: #{dup.size} unit(s) stand inside another unit (a kitchen generated twice on the same spot, or a unit dragged onto another). Delete or move the duplicate, then export again." if dup.any?
      raise IntegrityError.new(head.join("
") + "
" + list.join("
"), bad)
    end

    # Executive summary: derived from the SAME analysed rows / hardware / appliance totals as the cut list, CSV, labels and quote - no second
    # set of numbers. Panels are cuttable boards only; appliances and hardware are counted separately (never in the board area).
    def summary(res, cfg, lang = "en")
      names = cfg["mat_names"] || {}
      panels = Hash.new { |h, k| h[k] = { area: 0.0, parts: 0 } }
      res[:rows].each do |r|
        next if %w[top glass splash].include?(r[:mat]) || r[:part].to_s == 'plinth'

        k = [names[r[:mat]] || r[:mat], r[:thk]]
        panels[k][:area] += r[:len] * r[:wid] * r[:qty] / 1_000_000.0
        panels[k][:parts] += r[:qty]
      end
      worktop = res[:rows].select { |r| r[:mat] == "top" }
      splash = res[:rows].select { |r| r[:mat] == "splash" }
      hw = res[:hw]
      label = ->(k) { (I18n.t(k, lang) rescue k) || k }
      pick = ->(keys) { keys.filter_map { |k| hw[k].to_f > 0 ? { key: k, label: label.call(k), qty: hw[k].round(2) } : nil } }
      hinges = hw.keys.select { |k| k.to_s.start_with?("hinge") }
      slides = %w[slide_pair undermount_slide slide_wheel]
      used = hinges + slides + %w[profile_mm led_mm]
      others = hw.keys.reject { |k| used.include?(k) }
      {
        panels: panels.map { |(m, t), v| { material: m, thk: t, area_m2: v[:area].round(2), parts: v[:parts] } }.sort_by { |p| [p[:material].to_s, p[:thk]] },
        panel_area_m2: EGC::Num.sum(panels.values) { |v| v[:area] }.round(2),
        edge_m: (res[:edge] || {}).map { |t, m| { thk: t, meters: m.round(1) } },
        hinges: pick.call(hinges), slides: pick.call(slides), accessories: pick.call(others),
        profile_m: (hw["profile_mm"].to_f / 1000.0).round(1), led_m: (hw["led_mm"].to_f / 1000.0).round(1),
        led: res[:led], fascia: res[:fascia],
        appliances: (res[:apps] || {}).map { |k, n| { kind: k, label: I18n.app(k, lang), qty: n } },
        worktop: { area_m2: EGC::Num.sum(worktop) { |r| r[:len] * r[:wid] * r[:qty] / 1_000_000.0 }.round(2), length_m: EGC::Num.sum(worktop) { |r| r[:len] * r[:qty] / 1000.0 }.round(2),
                   splash_m2: EGC::Num.sum(splash) { |r| r[:len] * r[:wid] * r[:qty] / 1_000_000.0 }.round(2) }
      }
    end

    # RAW (saw / CNC) size of a board. The model and the cut list carry the FINISHED size; a thick PVC edge (>= EDGE_DEDUCT_MIN mm, i.e. the
    # 2 mm banding of fronts and visible panels) is glued on afterwards, so the board is cut smaller by one band thickness per banded edge.
    # Thin tape (carcass 0.5 - 1 mm) is not deducted. eb_l = banded LONG edges (they reduce the width), eb_w = banded SHORT edges (the length).
    EDGE_DEDUCT_MIN = 1.5

    def cut_size(p)
      t = p[:eb_t].to_f
      return [p[:len], p[:wid]] if t < EDGE_DEDUCT_MIN || %w[top glass splash plinth].include?(p[:mat].to_s) || p[:part].to_s == 'plinth' # stone, glass and bought profiles are not edge-banded boards

      [(p[:len] - p[:eb_w].to_i * t).round(1), (p[:wid] - p[:eb_l].to_i * t).round(1)]
    end

    def aggregate(parts)
      h = {}
      parts.each do |p|
        key = [p[:mat], p[:thk], p[:len], p[:wid], p[:part], p[:eb_l], p[:eb_w], p[:eb_t], p[:groove], p[:groove_geo], p[:notes]]
        h[key] ||= p.merge(qty: 0)
        h[key][:qty] += 1
      end
      h.values.sort_by { |p| [p[:mat].to_s, -p[:thk], p[:part].to_s, -p[:len], -p[:wid]] }
    end

    # Drilling is left out of the production outputs unless the setting asks for it (owner, 1.28.52 / 1.28.53: production = the boards and
    # the LED groove - hinges, handles, shelf pins, cam bolts and dowels are drilled on site). HW_BORES: the fitting holes among them.
    HW_BORES = ['hinge cup', 'hinge plate', 'handle screw', 'flush pull pocket'].freeze

    def hw_bores?(cfg = nil)
      (cfg || Config.build)['prod_hw_bores'] == true
    rescue StandardError
      false
    end

    def prod_bore(raw, cfg = nil)
      return raw if raw.nil? || raw.to_s.empty? || hw_bores?(cfg)

      nil # owner 1.28.53: no drilling at all in production (shelf pins, cam bolts and dowels too) - the boards, the LED and back grooves only
    end

    # Units with their OWN material (spec :mats): their boards are a separate material in every list - "front@OAK01" - named after the
    # swatch and cut from the same sheet size / grain rule as the kitchen's material of that key.
    def unit_materials!(parts, cfg)
      parts.each do |p|
        code = p[:mat_code].to_s
        next if code.empty?

        base = p[:mat].to_s
        key = "#{base}@#{code}"
        p[:mat] = key
        entry = Catalog.swatch(base == 'drawer' ? 'carcass' : base, code)
        (cfg['mat_names'] ||= {})[key] ||= entry ? "#{entry['name']} (#{code})" : key
        if cfg['sheets'].is_a?(Hash)
          cfg['sheets'].keys.select { |k| k.to_s == base || k.to_s.start_with?("#{base}:") }.each { |k| cfg['sheets'][k.to_s.sub(base, key)] ||= cfg['sheets'][k] }
        end
        (cfg['grain_lock'] ||= {})[key] = cfg['grain_lock'][base] if cfg['grain_lock'].is_a?(Hash) && cfg['grain_lock'].key?(base)
      end
    end

    # Full analysis used by the report and the dialog table.
    def analyse(cfg, model = Sketchup.active_model, use_selection: true)
      Numbering.apply(model, own_op: true) if Numbering.stale?(model) # a unit added after the last numbering still carries a builder code
      Exposure.refresh(cfg, model, own_op: true)   # visible faces follow the current neighbours before anything is counted
      raw = collect(model, use_selection: use_selection)
      raw[:parts].each { |p| p[:bore] = prod_bore(p[:bore], cfg) }
      unit_materials!(raw[:parts], cfg)
      plinth_mm = EGC::Num.sum(raw[:parts].select { |p| p[:part].to_s == 'plinth' }) { |p| p[:len] }
      raw[:hw]['plinth_m'] = plinth_mm / 1000.0 if plinth_mm.positive?
      rows = aggregate(raw[:parts])
      out = { rows: rows, raw: raw[:parts], apps: raw[:apps], cabs: raw[:cabs], hw: raw[:hw], cfg: cfg, integrity: raw[:integrity] || [], generation: generation }
      out[:integrity] += Exposure.overlaps(model, only: use_selection ? raw[:cabs].map { |c| c[:pid] }.compact : nil)
      runs = LedRun.detect(model, only: use_selection ? raw[:cabs].map { |c| c[:pid] }.compact : nil)
      out[:led] = LedRun.summary(runs).merge('runs_full' => runs)
      raw[:hw]['led_mm'] = out[:led]['strip_mm'] # one continuous strip per RUN (not per cabinet); every upper underside carries its groove (tier 1 @35, tier 2 @450) so every upper is in a run
      out[:fascia] = raw[:parts].select { |p| p[:part] == 'fascia' }.group_by { |p| p[:cab].to_s.sub(/\d+$/, '') }.map { |k, v| { 'id' => k, 'pieces' => v.size, 'length_mm' => EGC::Num.sum(v) { |p| p[:len] }.round(1), 'height_mm' => v.first[:wid], 'mat' => v.first[:mat] } }
      area = Hash.new(0.0)
      rows.each { |r| area[r[:mat]] += r[:len] * r[:wid] * r[:qty] / 1_000_000.0 }
      out[:area] = area
      edge = Hash.new(0.0)
      rows.each do |r|
        next if r[:part].to_s == 'plinth'

        edge[r[:eb_t]] += (r[:eb_l] * r[:len] + r[:eb_w] * r[:wid]) * r[:qty] / 1000.0
      end
      out[:edge] = edge
      out[:nest] = nest_all(raw[:parts], cfg)
      out[:cost] = cost(out, cfg)
      out
    end

    # ---- 1.28.67 grain policy -------------------------------------------------
    # Rotation on the saw is only legal when the board has no grain to line up.
    # The old rule was a two-entry manual map (cfg['grain_lock'] = front/top), so a
    # wood-veneer carcass was free to rotate and the grain ran across the part.
    #
    # Order of authority:
    #   1. an explicit cfg['grain_lock'] entry always wins (true = never rotate);
    #   2. wood / textured swatches keep their grain and never rotate;
    #   3. solid / plain boards (no texture) rotate freely.
    def grain_free?(mat, mat_code = nil)
      base = mat.to_s.split('@').first
      code = mat_code.to_s
      code = mat.to_s.split('@').last if code.empty? && mat.to_s.include?('@')
      return true if %w[back drawer plinth].include?(base) && code.empty? # solid back / drawer boards

      sw = code.empty? ? nil : Catalog.swatch(%w[top splash].include?(base) ? base : 'front', code)
      return false if sw && (sw['cat'].to_s == 'Wood' || sw['tex'].to_s.include?('/wood/'))

      true
    rescue StandardError
      false
    end

    def rotatable?(row, mat, lock)
      return false if lock[mat] == true # explicit project lock
      return true if lock[mat] == false # explicit project unlock

      grain_free?(mat, row[:mat_code])
    end

    # Nesting per sheet material (top/glass/splash are priced by net area). Items are labelled with part IDs.
    def nest_all(parts, cfg)
      lock = cfg['grain_lock'] || {}
      res = {}
      parts.reject { |p| p[:part].to_s == 'plinth' || p[:mat].to_s == 'plinth' }.group_by { |r| [r[:mat], r[:thk]] }.each do |(mat, thk), rs|
        next if %w[top glass splash].include?(mat)

        colors = {}
        items = rs.each_with_index.map do |r, i|
          key = [r[:part], r[:len], r[:wid]]
          colors[key] ||= colors.size + 1
          cl, cw = cut_size(r) # the sheet is nested with the RAW cut size (finished size minus thick edge banding)
          { id: (r[:pid] || (i + 1)).to_s, l: cl, w: cw, fin_l: r[:len], fin_w: r[:wid], rot: rotatable?(r, mat, lock), part: r[:part], color: colors[key], code: r[:code], groove: r[:groove], groove_geo: r[:groove_geo],
            bore: r[:bore], back_groove: r[:back_groove], la: r[:la], notch: r[:notch], thk: r[:thk], eb_l: r[:eb_l], eb_w: r[:eb_w], eb_t: r[:eb_t], notes: r[:notes] }
        end
        dims = Config.stock_dimensions(cfg, mat, thk)
        sl, sw = dims if dims
        raise "STOCK_SIZE_REQUIRED: set valid sheet length and width in Project Pricing for #{mat} #{thk} mm before nesting/export." unless sl.to_f.positive? && sw.to_f.positive?
        sl = sl.to_f
        sw = sw.to_f
        r = Nesting.pack(items, sl, sw, cfg['kerf'].to_f, cfg['trim'].to_f)
        used = EGC::Num.sum(r[:sheets]) { |s| s[:area] }
        total = r[:sheets].size * sl * sw
        res[[mat, thk]] = { sheets: r[:sheets], oversize: r[:oversize], items: items, sheet: [sl, sw], strategy: r[:strategy],
                            used: used / 1_000_000.0, total: total / 1_000_000.0,
                            waste: total.zero? ? 0 : (1 - used / total) * 100.0 }
      end
      res
    end

    # Purchase cost follows the actual nested stock count. A missing project sheet price stays missing.
    def board_price(cfg, mat, thk)
      prices = cfg['price_sheet'] || {}
      key = prices.keys.find { |k| k.to_s.start_with?("#{mat}:") && k.to_s.split(':', 2).last.to_f == thk.to_f }
      key ||= mat if prices.key?(mat)
      [key && !prices[key].nil? ? prices[key].to_f : nil, 'sheet']
    end

    def cost(out, cfg)
      lines = []
      cur = cfg['currency']
      out[:nest].each do |(mat, thk), n|
        price, unit = board_price(cfg, mat, thk)
        qty = n[:sheets].size
        lines << { item: "#{cfg['mat_names'][mat] || mat} #{thk} mm (#{n[:sheets].size} sheets)", qty: qty.round(2), unit: unit,
                   price: price, amount: qty * price.to_f, cat: 'board', mat: mat, thk: thk }
      end
      %w[top glass splash].each do |mat|
        a = out[:area][mat]
        next unless a && a > 0

        settings = (cfg['material_pricing'] || {})[mat] || {}
        rows = out[:rows].select { |r| r[:mat] == mat }
        basis = settings['basis'].to_s
        qty, unit = case basis
                    when 'm2' then [a, 'm²']
                    when 'linear_m' then [EGC::Num.sum(rows) { |r| r[:len] * r[:qty] } / 1000.0, 'm']
                    when 'piece' then [EGC::Num.sum(rows) { |r| r[:qty] }, 'pcs']
                    else [a, 'm² (unpriced)']
                    end
        price = settings['price']
        lines << { item: cfg['mat_names'][mat] || mat, qty: qty.round(2), unit: unit, price: price,
                   amount: price.nil? || !%w[m2 linear_m piece].include?(basis) ? 0.0 : qty * price.to_f,
                   cat: 'worktop', mat: mat }
      end
      out[:edge].each do |t, m|
        key = t >= 1 ? '2' : '0.5'
        p = (cfg['price_edge_m'] || {})[key].to_f
        lines << { item: "Edge banding #{t} mm", qty: m.round(1), unit: 'm', price: p, amount: m * p, cat: 'edge' }
      end
      hwp = cfg['price_hw'] || {}
      hw = out[:hw].dup
      hw['profile_m'] = hw.delete('profile_mm').to_f / 1000.0 if hw['profile_mm']
      hw['led_m'] = hw.delete('led_mm').to_f / 1000.0 if hw['led_mm']
      out[:hw_view] = hw
      hw.each do |k, v|
        next if v <= 0

        p = hwp[k].to_f
        lines << { item: k, qty: v.round(2), unit: '', price: p, amount: v * p, cat: 'hw', key: k }
      end
      sub = EGC::Num.sum(lines) { |l| l[:amount] }
      lab = sub * cfg['labor_pct'].to_f / 100.0
      # Zero remains the established 'not priced' convention for material/hardware
      # tables. Appliance zero prices retain their existing explicit-free meaning.
        missing = lines.select { |l| l[:qty].positive? && l[:price].to_f <= 0 }.map do |l|
        { 'item' => l[:item], 'reason' => 'no positive unit price in the price table' }
      end
      out[:nest].each do |(mat, thk), n|
        next if n[:oversize].empty?

        missing << { 'item' => "#{mat} #{thk} mm: #{n[:oversize].map { |i| i[:id] }.join(', ')}",
                     'reason' => 'parts exceed available stock; unplaced board costs are NOT included' }
      end
      { lines: lines, subtotal: sub, labor: lab, total: sub + lab, currency: cur, missing: missing, complete: missing.empty? }
    end

    # Cost allocated to every unit / run part (by part ID prefix "code")
    def per_code(out, cfg)
      pm2 = cfg['price_m2'] || {}
      hwp = cfg['price_hw'] || {}
      rates = {}
      out[:nest].each do |(mat, thk), n|
        price, unit = board_price(cfg, mat, thk)
        total = n[:sheets].size * price.to_f
        rates[[mat, thk]] = n[:used] > 0 ? total / n[:used] : 0.0
      end
      indices = Hash.new(0)
      rows = {}
      row = lambda do |code|
        rows[code] ||= { code: code, board: 0.0, edge: 0.0, hw: 0.0, area: 0.0, parts: 0 }
      end
      out[:raw].each do |p|
        r = row.call(p[:code].to_s)
        a = p[:len] * p[:wid] / 1_000_000.0
        key = [p[:mat], p[:thk]]
        indices[key] += 1
        n = out[:nest][key]
        id = (p[:pid] || indices[key]).to_s
        unplaced = n && n[:oversize].any? { |i| i[:id].to_s == id }
        if unplaced
          r[:incomplete] = true
        else
          r[:board] += a * (rates[key] || 0.0)
        end
        r[:area] += a
        r[:parts] += 1
        m = (p[:eb_l] * p[:len] + p[:eb_w] * p[:wid]) / 1000.0
        r[:edge] += m * ((cfg['price_edge_m'] || {})[p[:eb_t] >= 1 ? '2' : '0.5']).to_f
      end
      out[:cabs].each do |c|
        r = row.call(c[:code].to_s)
        c[:hw].each do |k, v|
          q = k == 'profile_mm' || k == 'led_mm' ? v.to_f / 1000.0 : v.to_f
          key = { 'profile_mm' => 'profile_m', 'led_mm' => 'led_m' }[k] || k
          r[:hw] += q * hwp[key].to_f
        end
        r[:name] = c[:name]
        r[:type] = c[:type]
        r[:size] = [c[:w], c[:h], c[:d]]
      end
      rows.values.each { |r| r[:total] = r[:board] + r[:edge] + r[:hw] }
      rows.values.sort_by { |r| r[:code] }
    end

    def csv(out, lang = 'en')
      t = ->(k) { I18n.t(k, lang) }
      cfg = out[:cfg]
      lines = ["﻿" + [t['material'], t['thk'], t['part'], t['len'], t['wid'], t['qty'], 'Edge L', 'Edge W',
                            'Edge mm', t['groove'], 'Cut L (raw)', 'Cut W (raw)'].join(',')]
      out[:rows].each do |r|
        lines << [cfg['mat_names'][r[:mat]] || r[:mat], r[:thk], I18n.part(r[:part], lang), r[:len], r[:wid], r[:qty],
                  r[:eb_l], r[:eb_w], r[:eb_t], [r[:groove], r[:notes]].compact.join(' '), *cut_size(r)].map { |c| "\"#{c}\"" }.join(',')
      end
      lines.join("\r\n")
    end

    # Which physical edges carry banding: L1/L2 = the two long edges, W1/W2 = the two short edges.
    def edge_sides(p)
      { l1: p[:eb_l] >= 1, l2: p[:eb_l] >= 2, w1: p[:eb_w] >= 1, w2: p[:eb_w] >= 2 }
    end

    def edge_label(p)
      "PVC #{p[:eb_t].round(1)} mm"
    end

    # OpenCutList-compatible part list (import as a cut list in OpenCutList / most cutting optimisers):
    # Length runs along the grain, Ymin/Ymax = long edges, Xmin/Xmax = short edges.
    def opencutlist_csv(out, lang = 'en')
      cfg = out[:cfg]
      head = ['Number', 'Name', 'Count', 'Length', 'Width', 'Thickness', 'Material', 'Grain', 'Edge Ymin', 'Edge Ymax',
              'Edge Xmin', 'Edge Xmax', 'Cabinet', 'Notes']
      lock = cfg['grain_lock'] || {}
      lines = ["﻿" + head.join(',')]
      out[:raw].reject { |p| p[:part].to_s == 'plinth' || p[:mat].to_s == 'plinth' }.sort_by { |p| [p[:mat].to_s, p[:code].to_s, p[:pid].to_s] }.each do |p|
        e = edge_sides(p)
        lab = edge_label(p)
        lines << [p[:pid], I18n.part(p[:part], lang), 1, p[:len], p[:wid], p[:thk], cfg['mat_names'][p[:mat]] || p[:mat],
                  lock[p[:mat]] ? 'along length' : 'none', e[:l1] ? lab : '', e[:l2] ? lab : '', e[:w1] ? lab : '', e[:w2] ? lab : '',
                  p[:code], [p[:groove], p[:notes]].compact.join(' ')].map { |c| "\"#{c}\"" }.join(',')
      end
      lines.join("\r\n")
    end

    # One row per physical part with its ID (for stickers / assembly)
    def labels_csv(out, lang = 'en')
      cfg = out[:cfg]
      head = ['ID', 'Unit', 'Part', 'Material', 'Thk', 'Length', 'Width', 'Edge L1', 'Edge L2', 'Edge W1', 'Edge W2', 'Notes', 'Raw Length', 'Raw Width', 'Job', 'QR']
      job = (cfg['job_name'] || (Sketchup.active_model.title rescue '')).to_s
      lines = ["﻿" + head.join(',')]
      out[:raw].sort_by { |p| [p[:code].to_s, p[:pid].to_s] }.each do |p|
        lines << [p[:pid], p[:code], I18n.part(p[:part], lang), cfg['mat_names'][p[:mat]] || p[:mat], p[:thk], p[:len], p[:wid],
                  *edge_sides(p).values.map { |b| b ? 'x' : '' }, [p[:groove], p[:notes]].compact.join(' '), *cut_size(p), job,
                  Labels.payload(p, cfg, job)].map { |c| "\"#{c}\"" }.join(',')
      end
      lines.join("\r\n")
    end

    # Saw/CNC hand-off list from the actual nest. Coordinates are sheet-local mm;
    # identifiers, material, rotation and stock dimensions come from Nesting.pack.
    def laser_csv(out)
      lines = [["\uFEFFSheet", 'Material', 'Thickness_mm', 'Part_ID', 'Unit_ID', 'Part', 'Sheet_X_mm', 'Sheet_Y_mm', 'Cut_Length_mm', 'Cut_Width_mm', 'Rotated', 'Stock_Length_mm', 'Stock_Width_mm']]
      out[:nest].each do |(mat, thk), nest|
        nest[:sheets].each_with_index do |sheet, si|
          sheet[:placed].each do |placed|
            item = placed[:item]
            lines << [si + 1, mat, thk, item[:id], item[:code], item[:part], placed[:x], placed[:y], placed[:w], placed[:h], placed[:rotated] ? 'YES' : 'NO', *nest[:sheet]]
          end
        end
      end
      lines.map { |row| row.map { |v| "\"#{v.to_s.gsub('"', '""')}\"" }.join(',') }.join("\r\n")
    end

    # Boring / drilling reference: hinge cups + system-32 shelf pin holes
    # CNC / router file for the LED grooves (E.G.C standard: tier 1 at 35 mm, tier 2 at 450 mm from the back edge, 10 x 10). One row per grooved underside.
    def groove_csv(out)
      lines = ["﻿Part ID,Cabinet,Part,Groove,Width (mm),Depth (mm),Offset from carcass back (mm),Offset from PANEL back edge (mm),Route length (mm),Tier,Reference"]
      out[:raw].each do |p|
        next unless p[:groove].to_s =~ /(\d+)x(\d+)@(\d+)/

        w, dp, off = Regexp.last_match(1), Regexp.last_match(2), Regexp.last_match(3)
        tier = p[:cab].to_s =~ /_W(\d)\z/ ? Regexp.last_match(1) : ''
        geo = (JSON.parse(p[:groove_geo].to_s) rescue {})
        lines << [p[:pid], p[:code], p[:part], p[:groove], w, dp, off, geo['off'] || 'NOT RECORDED - rebuild unit', p[:len], tier, 'cut in the UNDERSIDE face; route along the part length; through both ends'].map { |c| "\"#{c}\"" }.join(',')
      end
      lines.join("\r\n")
    end

    def boring_csv(out)
      lines = ["﻿Part ID,Part,Type,X (mm),Y (mm),Dia (mm),Depth (mm),Ref"]
      out[:raw].each do |p|
        next unless p[:bore]

        JSON.parse(p[:bore]).each do |h|
          next if h['t'].to_s == 'hinge cup' && h['status'].to_s != 'CONFIRMED'

          lines << [p[:pid], p[:part], h['t'], h['x'], h['y'], h['dia'], h['depth'], h['ref']].map { |c| "\"#{c}\"" }.join(',')
        end
      end
      lines.join("\r\n")
    end
  end
end
