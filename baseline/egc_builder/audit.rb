# frozen_string_literal: true

module EGC
  # Pre-manufacturing checks (preflight).
  module Audit
    module_function

    Issue = Struct.new(:level, :code, :where, :detail)

    # cfg: config hash; returns { issues: [{level, code, where, detail}], errors:, warnings:, parts: }
    def run(cfg, model = Sketchup.active_model, use_selection: false)
      res = Cutlist.analyse(cfg, model, use_selection: use_selection)
      raw = res[:raw] || []
      issues = []
      add = ->(lvl, code, where = '', detail = '') { issues << { 'level' => lvl, 'code' => code, 'where' => where.to_s, 'detail' => detail.to_s } }

      # oversize parts
      res[:nest].each do |(mat, _thk), n|
        n[:oversize].each { |o| add.call('error', 'oversize', o[:id], "#{o[:l].round}x#{o[:w].round} > #{n[:sheet][0].round}x#{n[:sheet][1].round}") }
      end
      seen = {}
      raw.each do |p|
        pid = p[:pid].to_s
        add.call('error', 'dup_pid', pid, p[:part]) if !pid.empty? && seen[pid]
        seen[pid] = true
        next if %w[top glass].include?(p[:mat])

        add.call('warn', 'narrow', pid, "#{p[:part]} #{p[:wid].round(1)} mm") if p[:wid] < 40 && p[:part] != 'profile'
        add.call('warn', 'shelf_span', pid, "#{p[:len].round} mm") if p[:part] == 'shelf' && p[:len] > 900
        if %w[door sliding_door].include?(p[:part])
          add.call('warn', 'door_wide', pid, "#{p[:wid].round} mm") if p[:wid] > 650 && p[:part] == 'door'
          add.call('warn', 'door_tall', pid, "#{p[:len].round} mm") if p[:len] > 2200 && p[:part] == 'door'
        end
        add.call('warn', 'drawer_low', pid, "#{p[:wid].round} mm") if p[:part] == 'drawer_front' && [p[:len], p[:wid]].min < 90
      end
      res[:rows].each do |r|
        next unless r[:part] == 'countertop'

        add.call('warn', 'top_long', r[:part], "#{r[:len].round} mm") if r[:len] > cfg['top_max_len'].to_f
      end

      # ceiling + overlaps between cabinets
      cabs = []
      collect_cabs(model.entities.to_a, cabs)
      ceil = cfg['ceiling'].to_f
      cabs.each do |g|
        top = g.bounds.max.z.to_mm
        # groups nested in a transformed parent report bounds in parent space, so only check root-level results
        add.call('error', 'ceiling', g.name, "#{top.round} > #{ceil.round}") if g.parent == model && top > ceil + 1
      end
      cabs.combination(2).each do |a, b|
        next unless a.parent == b.parent

        ba = a.bounds
        bb = b.bounds
        dx = [ba.max.x, bb.max.x].min - [ba.min.x, bb.min.x].max
        dy = [ba.max.y, bb.max.y].min - [ba.min.y, bb.min.y].max
        dz = [ba.max.z, bb.max.z].min - [ba.min.z, bb.min.z].max
        add.call('error', 'overlap', "#{a.name} / #{b.name}", "#{dx.to_mm.round}x#{dy.to_mm.round}x#{dz.to_mm.round}") if dx.to_mm > 5 && dy.to_mm > 5 && dz.to_mm > 5
      end
      # ---- data-integrity codes (spec -> geometry -> production) ----
      (res[:integrity] || []).each { |b| add.call("error", (b[:code] || "STALE_PRODUCTION_DATA"), "#{b[:cab]}/#{b[:part]} #{b[:pid]}", b[:detail]) }
      cabs.each do |g|
        tr = g.transformation
        sc = [tr.xscale, tr.yscale, tr.zscale]
        add.call("error", "SPEC_GEOMETRY_MISMATCH", g.name, "manual scale #{sc.map { |v| v.round(3) }.join(" x ")} - spec no longer describes the geometry") if sc.any? { |v| (v - 1.0).abs > 0.002 }
        add.call("error", "BROKEN_INSTANCE_REFERENCE", g.name, "unit has no geometry") if g.entities.count.zero?
      end
      walk_status = lambda do |list|
        list.each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)

          bs = e.get_attribute("egc", "build_status")
          add.call("error", "FAILED_APPLIANCE_BUILD", e.name, e.get_attribute("egc", "build_error").to_s) if bs == "FAILED"
          add.call("warn", "SIMPLIFIED_APPLIANCE", e.name, e.get_attribute("egc", "build_error").to_s) if bs == "SIMPLIFIED"
          walk_status.call(e.respond_to?(:entities) ? e.entities.to_a : e.definition.entities.to_a)
        end
      end
      walk_status.call(model.entities.to_a)
      add.call('info', 'empty') if raw.empty?
      { issues: issues, errors: issues.count { |i| i['level'] == 'error' }, warnings: issues.count { |i| i['level'] == 'warn' }, parts: raw.size }
    end

    def collect_cabs(list, acc)
      list.each do |e|
        next unless e.is_a?(Sketchup::Group)

        acc << e if e.get_attribute('egc', 'spec') || e.get_attribute('egc', 'wardrobe')
        collect_cabs(e.entities.to_a, acc) unless e.get_attribute('egc', 'role')
      end
    end

    MSG = {
      'en' => { 'oversize' => 'Part larger than the sheet', 'dup_pid' => 'Duplicate part ID', 'narrow' => 'Very narrow part (< 40 mm)',
                'shelf_span' => 'Shelf span over 900 mm may sag', 'door_wide' => 'Door wider than 650 mm', 'door_tall' => 'Door taller than 2200 mm may warp',
                'drawer_low' => 'Drawer front lower than 90 mm', 'top_long' => 'Countertop longer than the maximum slab length',
                'ceiling' => 'Unit is higher than the ceiling', 'overlap' => 'Units overlap', 'empty' => 'No E.G.C parts found',
                'STALE_PRODUCTION_DATA' => 'Part no longer matches its stored size - exports are blocked', 'SPEC_GEOMETRY_MISMATCH' => 'Unit was scaled by hand: spec and geometry differ',
                'FAILED_APPLIANCE_BUILD' => 'Appliance could not be built', 'SIMPLIFIED_APPLIANCE' => 'Appliance is a simplified box (detailed build failed or not modelled)',
                'BROKEN_INSTANCE_REFERENCE' => 'Broken instance', 'INVALID_MECHANISM_SOLUTION' => 'Mechanism has no valid solution' },
      'ar' => { 'oversize' => 'قطعة أكبر من اللوح', 'dup_pid' => 'رقم قطعة مكرر', 'narrow' => 'قطعة ضيقة جداً (أقل من 40 مم)',
                'shelf_span' => 'بحر الرف أكبر من 900 مم وممكن ينحني', 'door_wide' => 'باب أعرض من 650 مم', 'door_tall' => 'باب أطول من 2200 مم وممكن يلتوي',
                'drawer_low' => 'واجهة درج أقل من 90 مم', 'top_long' => 'الرخام أطول من أقصى طول للوح',
                'ceiling' => 'الوحدة أعلى من السقف', 'overlap' => 'تداخل بين وحدات', 'empty' => 'لا توجد قطع E.G.C',
                'STALE_PRODUCTION_DATA' => 'قطعة لم تعد تطابق مقاسها المخزن - التصدير متوقف', 'SPEC_GEOMETRY_MISMATCH' => 'الوحدة اتعملها Scale يدوي: المواصفات والهندسة مختلفين',
                'FAILED_APPLIANCE_BUILD' => 'تعذر بناء الجهاز', 'SIMPLIFIED_APPLIANCE' => 'الجهاز صندوق مبسط (البناء التفصيلي فشل أو غير مصمم)',
                'BROKEN_INSTANCE_REFERENCE' => 'عنصر تالف', 'INVALID_MECHANISM_SOLUTION' => 'الميكانيزم ملوش حل صالح' }
    }.freeze

    def message(code, lang)
      (MSG[lang] || MSG['en'])[code] || code
    end
  end
end
