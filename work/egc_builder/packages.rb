# frozen_string_literal: true

require 'json'
require 'fileutils'

module EGC
  # ================================================================================================================================ production families
  module Families
    module_function

    HEAD = ['Part ID', 'Unit ID', 'Description', 'Family', 'Material', 'Thickness', 'Length', 'Width', 'Qty', 'Grain', 'Edge L1', 'Edge L2', 'Edge W1', 'Edge W2', 'Edge mm',
            'Cut L (raw)', 'Cut W (raw)', 'Machining', 'Source unit'].freeze

    def machining(p)
      ops = (JSON.parse(p[:bore].to_s) rescue []).group_by { |h| h['dia'].to_f }.map { |d, hs| "#{d.round(1).to_s.sub(/\.0\z/, '')}mm x#{hs.size}" }
      bg = (JSON.parse(p[:back_groove].to_s) rescue nil)
      ops << "back groove #{bg['width']}x#{bg['depth']}@#{bg['offset']}" if bg
      ops << "LED groove #{p[:groove]}" if p[:groove]
      nt = (JSON.parse(p[:notch].to_s) rescue [])
      ops << "gola notch x#{nt.size}" unless nt.empty?
      ops.join('; ')
    end

    def rows(an, fam = nil, lang = 'en')
      cfg = an[:cfg]
      lock = cfg['grain_lock'] || {}
      an[:raw].select { |p| fam.nil? || ProductionModel.family(p) == fam }.sort_by { |p| [p[:code].to_s, p[:pid].to_s] }.map do |p|
        cl, cw = Cutlist.cut_size(p)
        [p[:pid], p[:code], I18n.part(p[:part], lang), ProductionModel.family(p), (cfg['mat_names'] || {})[p[:mat]] || p[:mat], p[:thk], p[:len], p[:wid], 1,
         lock[p[:mat]] ? 'along length' : 'none', *Cutlist.edge_sides(p).values.map { |b| b ? 'x' : '' }, p[:eb_t], cl, cw, machining(p), p[:cab]]
      end
    end

    def csv(an, fam = nil, lang = 'en')
      "﻿" + ([HEAD] + rows(an, fam, lang)).map { |r| r.map { |v| "\"#{v.to_s.gsub('"', '""')}\"" }.join(',') }.join("\r\n")
    end
  end

  # ================================================================================================================================ machine profiles
  # A machine profile describes ONE real CNC (work area, origin, tool library, safe Z, postprocessor). Profiles are never shipped with invented data: the
  # plugin only reads profiles the user / machine supplier puts in %APPDATA%/EGC_Builder/machine_profiles/*.json. Machine-specific output is produced only
  # from a VERIFIED profile (every required field present + verified_by / verified_on). Otherwise: REQUIRES MACHINE PROFILE.
  module MachineProfile
    module_function

    REQUIRED = %w[name work_area origin tools safe_z postprocessor verified_by verified_on].freeze
    POSTPROCESSORS = %w[egc_ops_csv].freeze

    def dir
      File.join(ENV['APPDATA'].to_s, 'EGC_Builder', 'machine_profiles')
    end

    def all(extra_dir = nil)
      [dir, extra_dir].compact.select { |d| File.directory?(d) }.flat_map { |d| Dir.glob(File.join(d, '*.json')) }.filter_map do |f|
        pr = JSON.parse(File.read(f, encoding: 'utf-8')) rescue next
        pr.merge('file' => f, 'missing' => missing(pr))
      end
    end

    def missing(pr)
      m = REQUIRED.reject { |k| pr[k].is_a?(String) ? !pr[k].strip.empty? : !pr[k].nil? && pr[k] != [] }
      m << "postprocessor (supported: #{POSTPROCESSORS.join(', ')})" if pr['postprocessor'] && !POSTPROCESSORS.include?(pr['postprocessor'])
      m
    end

    def verified(extra_dir = nil)
      all(extra_dir).find { |p| p['missing'].empty? }
    end

    # every machining operation of the engineering CAM data checked against the profile: tool exists, depth reachable, position inside the work area, one face
    def check(pr, an)
      tools = Array(pr['tools'])
      wa = pr['work_area']
      errs = []
      ops = []
      an[:nest].each do |(mat, thk), n|
        sl, sw = n[:sheet]
        errs << "#{mat} #{thk}: sheet #{sl.round} x #{sw.round} larger than the work area #{wa.inspect}" if wa.is_a?(Array) && (sl > wa[0].to_f || sw > wa[1].to_f)
        n[:sheets].each_with_index do |sh, si|
          sh[:placed].each do |pl|
            f = Cam.features(pl[:item])
            f[:circles].each do |lay, u, v, dia, depth|
              t = tools.find { |x| x['type'] == 'drill' && (x['dia'].to_f - dia).abs < 0.01 && x['max_depth'].to_f >= depth }
              errs << "#{pl[:item][:id]}: no drill #{dia} mm reaching #{depth} mm in the tool library" unless t
              ops << [mat, si + 1, pl[:item][:id], lay, t && t['id'], u, v, depth]
            end
            f[:rects].each do |lay, u0, v0, u1, v1, depth|
              wdt = [(u1 - u0).abs, (v1 - v0).abs].min
              t = tools.find { |x| x['type'] == 'router' && x['dia'].to_f <= wdt + 0.01 && x['max_depth'].to_f >= depth }
              errs << "#{pl[:item][:id]}: no router <= #{wdt.round(1)} mm reaching #{depth} mm for #{lay}" unless t
              ops << [mat, si + 1, pl[:item][:id], lay, t && t['id'], u0, v0, depth]
            end
            errs << "#{pl[:item][:id]}: depth >= board thickness" if (f[:circles].map { |c| c[4] } + f[:rects].map { |r| r[5] }).any? { |dpt| dpt >= thk.to_f && !(dpt - thk.to_f).abs.zero? }
          end
        end
      end
      { 'errors' => errs.uniq, 'ops' => ops }
    end

    def ops_csv(ops)
      "﻿material,sheet,part_id,layer,tool,u_mm,v_mm,depth_mm\r\n" + ops.map { |o| o.map { |v| v.is_a?(Float) ? v.round(2) : v }.join(',') }.join("\r\n")
    end
  end

  # ================================================================================================================================ part drawings
  # one drawing per DIFFERENT machined board (same size + same machining = one drawing with its quantity and Part IDs). Geometry from Cam.features: the
  # very same data the CNC files are made from.
  module PartDrawings
    module_function

    def item(p)
      { fin_l: p[:len], fin_w: p[:wid], part: p[:part], la: p[:la], bore: p[:bore], back_groove: p[:back_groove], groove_geo: p[:groove_geo], notch: p[:notch], thk: p[:thk], notes: p[:notes] }
    end

    def groups(an)
      an[:raw].select { |p| p[:bore] || p[:back_groove] || p[:groove_geo] || p[:notch] }.reject { |p| p[:bore] && (JSON.parse(p[:bore]) rescue []).empty? && !p[:back_groove] && !p[:groove_geo] && !p[:notch] }
              .group_by { |p| [p[:part], p[:mat], p[:thk], p[:len], p[:wid], p[:eb_l], p[:eb_w], p[:eb_t], Cam.features(item(p))] }
    end

    def svg(key, list, cfg)
      p = list.first
      f = Cam.features(item(p))
      l = p[:len].to_f
      w = p[:wid].to_f
      k = [380.0 / l, 170.0 / w].min
      x0 = 40
      y0 = 30
      tx = ->(u) { (x0 + u * k).round(1) }
      ty = ->(v) { (y0 + (w - v) * k).round(1) }
      o = +"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 470 #{(w * k + 120).round}' style='width:100%;max-width:680px;background:#fff;border:1px solid #ccc;margin:6px 0'>"
      o << "<rect x='#{x0}' y='#{y0}' width='#{(l * k).round(1)}' height='#{(w * k).round(1)}' fill='#f6f2ea' stroke='#222'/>"
      e = Cutlist.edge_sides(p)
      o << "<line x1='#{x0}' y1='#{ty.call(0)}' x2='#{tx.call(l)}' y2='#{ty.call(0)}' stroke='#c0392b' stroke-width='3'/>" if e[:l1]
      o << "<line x1='#{x0}' y1='#{y0}' x2='#{tx.call(l)}' y2='#{y0}' stroke='#c0392b' stroke-width='3'/>" if e[:l2]
      o << "<line x1='#{x0}' y1='#{y0}' x2='#{x0}' y2='#{ty.call(0)}' stroke='#c0392b' stroke-width='3'/>" if e[:w1]
      o << "<line x1='#{tx.call(l)}' y1='#{y0}' x2='#{tx.call(l)}' y2='#{ty.call(0)}' stroke='#c0392b' stroke-width='3'/>" if e[:w2]
      f[:rects].each { |lay, u0, v0, u1, v1, d| o << "<rect x='#{tx.call([u0, u1].min)}' y='#{ty.call([v0, v1].max)}' width='#{((u1 - u0).abs * k).round(1)}' height='#{[((v1 - v0).abs * k).round(1), 1].max}' fill='#{lay == 'NOTCH_GOLA' ? '#fff' : '#f3c0b8'}' stroke='#c0392b' stroke-width='0.6'><title>#{lay} depth #{d}</title></rect>" }
      f[:circles].each { |lay, u, v, dia, d| o << "<circle cx='#{tx.call(u)}' cy='#{ty.call(v)}' r='#{[dia * k / 2.0, 1.2].max.round(2)}' fill='none' stroke='#{lay == 'POCKET_35MM' ? '#7b2fbf' : (lay == 'DRILL_8MM' ? '#b8860b' : '#0a7d3b')}' stroke-width='0.7'><title>#{lay} d#{dia} depth #{d}</title></circle>" }
      o << "<text x='#{(x0 + l * k / 2).round}' y='#{(y0 + w * k + 16).round}' font-size='11' text-anchor='middle' font-family='Arial'>L #{l.round(1)}</text>"
      o << "<text x='#{x0 - 8}' y='#{(y0 + w * k / 2).round}' font-size='11' text-anchor='middle' font-family='Arial' transform='rotate(-90 #{x0 - 8} #{(y0 + w * k / 2).round})'>W #{w.round(1)}</text>"
      cl, cw = Cutlist.cut_size(p)
      cnt = f[:circles].group_by { |c| c[3] }.map { |d, cs| "#{d.round(1)} mm x#{cs.size}" }.join(', ')
      lines = ["#{list.map { |q| q[:pid] }.join(', ')}", "units #{list.map { |q| q[:code] }.uniq.join(', ')} | qty #{list.size} | #{(cfg['mat_names'] || {})[p[:mat]] || p[:mat]} #{p[:thk]} mm",
               "finished #{l.round(1)} x #{w.round(1)} | cut #{cl} x #{cw} | grain #{(cfg['grain_lock'] || {})[p[:mat]] ? 'along L' : 'free'} | edge #{e.select { |_, b| b }.keys.map(&:upcase).join(' ')} #{p[:eb_t]} mm",
               "holes: #{cnt.empty? ? '-' : cnt} | grooves: #{f[:rects].map { |r| "#{r[0]} d#{r[5]}" }.uniq.join(', ').then { |s| s.empty? ? '-' : s }}#{f[:notes].empty? ? '' : " | #{f[:notes].join('; ')}"}"]
      lines.each_with_index { |t, i| o << "<text x='10' y='#{(y0 + w * k + 36 + i * 15).round}' font-size='10' font-family='Arial'>#{t.gsub('&', '&amp;').gsub('<', '&lt;')[0, 150]}</text>" }
      o << "<text x='10' y='16' font-size='12' font-weight='bold' font-family='Arial'>#{I18n.part(p[:part], 'en')} - #{list.first[:pid]}#{list.size > 1 ? " (+#{list.size - 1})" : ''}</text></svg>"
    end

    def html(an, lang = 'en')
      g = groups(an)
      body = g.sort_by { |k, _| [k[1].to_s, k[0].to_s, -k[3].to_f] }.map { |k, list| svg(k, list, an[:cfg]) }.join
      "<!DOCTYPE html><html><head><meta charset='utf-8'><title>Part drawings</title><style>body{font-family:Arial;margin:12px}</style></head><body><h2>#{lang == 'ar' ? 'رسومات القطع' : 'Part drawings'} - #{g.size} different machined boards, #{g.values.sum(&:size)} boards</h2>#{body}</body></html>"
    end
  end

  # ================================================================================================================================ production integrity gate
  module ProductionGate
    module_function

    def check(list, name, ok, detail, blocking: true)
      list << { 'check' => name, 'status' => ok ? 'PASS' : (blocking ? 'BLOCKED' : 'WARNING'), 'detail' => detail.to_s[0, 600] }
    end

    # -> { 'ok' => bool, 'checks' => [...], 'blocking' => [...], 'warnings' => [...] }. sheets: the drawing set being issued (optional)
    def run(model, cfg, an = nil, sheets: nil, proj: Assistant.load(model), kind: 'factory')
      c = []
      an ||= Cutlist.analyse(cfg, model, use_selection: false)
      units = Numbering.units(model)
      stale = an[:integrity].reject { |b| b[:code] == 'OVERLAPPING_UNITS' }
      dup = an[:integrity].select { |b| b[:code] == 'OVERLAPPING_UNITS' }
      check(c, 'GEOMETRY: no stale unit (every board matches its stored size)', stale.empty?, stale.first(4).map { |b| "#{b[:cab]}/#{b[:part]} #{b[:detail]}" }.join('; '))
      check(c, 'GEOMETRY: no duplicate / overlapping units', dup.empty?, dup.first(4).map { |b| "#{b[:cab]} #{b[:detail]}" }.join('; '))
      noid = units.reject { |g| g.get_attribute('egc', 'code').to_s =~ Numbering::UID }
      check(c, 'GEOMETRY: every unit has a permanent U-ID', noid.empty?, noid.first(5).map(&:name).join(', '))
      bad = an[:cabs].reject { |u| [u[:w], u[:h], u[:d]].all? { |v| v.to_f.positive? } }
      check(c, 'GEOMETRY: unit dimensions valid', bad.empty?, bad.map { |u| u[:code] }.join(', '))
      if proj['room'] && proj['room']['poly'].to_a.size >= 3
        out = Exposure.collect(model)[:units].select { |u| u.corners.any? { |p| !AssistantValidate.inside?(proj['room']['poly'], p.x.to_mm, p.y.to_mm, 8.0) } }
        check(c, 'GEOMETRY: every unit inside the room', out.empty?, out.first(5).map { |u| u.g.get_attribute('egc', 'code') }.join(', '))
      end
      pids = an[:raw].map { |p| p[:pid].to_s }
      dupp = pids.tally.select { |_, n| n > 1 }.keys
      check(c, 'PARTS: no duplicate Part ID', dupp.empty?, dupp.first(6).join(', '))
      check(c, 'PARTS: every board has a Part ID', pids.none?(&:empty?), pids.count(&:empty?))
      codes = units.map { |g| g.get_attribute('egc', 'code').to_s }
      orphan = an[:raw].reject { |p| codes.include?(p[:code].to_s) || p[:code].to_s !~ /\AU\d/ }
      check(c, 'PARTS: no orphan board (every unit board belongs to an existing unit)', orphan.empty?, orphan.first(5).map { |p| p[:pid] }.join(', '))
      zero = an[:raw].select { |p| [p[:len], p[:wid], p[:thk]].any? { |v| v.to_f <= 0 } || p[:mat].to_s.empty? }
      check(c, 'PARTS: sizes and materials valid', zero.empty?, zero.first(5).map { |p| p[:pid] }.join(', '))
      fam_total = ProductionModel::FAMILY_ORDER.sum { |f| Families.rows(an, f).size }
      check(c, 'CUT LIST: family lists (carcass / exterior / back / drawer / worktop / plinth / special) account for every board once', fam_total == an[:raw].size, "#{fam_total} vs #{an[:raw].size}")
      check(c, 'CUT LIST: quantities reconcile with the boards', an[:rows].sum { |r| r[:qty] } == an[:raw].size, "#{an[:rows].sum { |r| r[:qty] }} vs #{an[:raw].size}")
      nestable = an[:raw].reject { |p| p[:part].to_s == 'plinth' || %w[plinth top glass splash].include?(p[:mat].to_s) }
      placed = an[:nest].values.flat_map { |n| n[:sheets].flat_map { |s| s[:placed].map { |q| q[:item][:id] } } }
      over = an[:nest].values.flat_map { |n| n[:oversize].map { |i| i[:id] } }
      check(c, 'NESTING: every sheet board nested exactly once', placed.sort == nestable.map { |p| p[:pid].to_s }.sort && placed.uniq.size == placed.size, "#{placed.size} nested / #{nestable.size} boards")
      check(c, 'NESTING: no oversize board', over.empty?, over.first(5).join(', '))
      mixed = an[:nest].select { |(mat, _t), n| n[:items].any? { |i| an[:raw].find { |p| p[:pid].to_s == i[:id] }&.dig(:mat) != mat } }
      check(c, 'NESTING: one stock family per nest (no mixed materials / thicknesses)', mixed.empty?, mixed.keys.inspect)
      cam_err = []
      an[:nest].each do |(_mat, thk), n|
        n[:sheets].each { |s| s[:placed].each { |pl| f = Cam.features(pl[:item]); (f[:circles].map { |q| q[4] } + f[:rects].reject { |r| r[0] == 'NOTCH_GOLA' }.map { |r| r[5] }).each { |d| cam_err << "#{pl[:item][:id]} depth #{d} >= #{thk}" if d >= thk.to_f } } }
      end
      check(c, 'CNC (engineering DXF): every operation inside its board and shallower than the board', cam_err.empty?, cam_err.first(5).join('; '))
      mp = MachineProfile.verified
      check(c, 'CNC (machine-specific output): verified machine profile', !mp.nil?, mp ? mp['name'] : "REQUIRES MACHINE PROFILE - none in #{MachineProfile.dir} (machine-specific output is not issued; the engineering DXF is)", blocking: false)
      hw_sum = Hash.new(0.0)
      an[:cabs].each { |u| (u[:hw] || {}).each { |k, v| hw_sum[k] += v.to_f } }
      hw_bad = hw_sum.reject { |k, v| (an[:hw][k].to_f - v).abs < 1e-6 }
      check(c, 'BOM: hardware totals = sum of the units', hw_bad.empty?, hw_bad.first(5).inspect)
      if sheets
        nos = sheets.map(&:no)
        miss = codes.reject { |cd| nos.any? { |n| n.to_s.start_with?("F-03-#{cd}") } }
        check(c, 'DRAWINGS: every unit has its shop drawing', kind != 'factory' || miss.empty?, miss.first(8).join(', '))
        text = sheets.map(&:body).join(' ')
        nopid = an[:raw].select { |p| p[:code].to_s =~ /\AU\d/ }.reject { |p| text.include?(p[:pid].to_s) }
        check(c, 'DRAWINGS: every unit Part ID appears on the drawings', kind != 'factory' || nopid.empty?, "#{nopid.size} missing, e.g. #{nopid.first(4).map { |p| p[:pid] }.join(', ')}")
        revs = sheets.map { |s| s.instance_variable_get(:@rev).to_s }.uniq
        check(c, 'DRAWINGS: drawing revision = model revision', revs == [proj['rev'].to_s], "#{revs.inspect} vs #{proj['rev'].inspect}")
      end
      val = (AssistantValidate.run(proj, cfg, model) rescue nil) if proj['room'] && proj['room']['poly'].to_a.size >= 3
      if val
        hard = val['problems'].reject { |i| %w[STALE_PRODUCTION_DATA OVERLAPPING_UNITS ANALYSIS_FAILED].include?(i['code']) }
        check(c, 'SITE: layout / clearance / opening rules', hard.empty?, hard.first(4).map { |i| "#{i['code']} #{i['message']}" }.join('; '))
        check(c, 'SITE: values still to confirm on site (services, appliance models, inferred dimensions)', val['warnings'].empty?, "#{val['warnings'].size} item(s) REQUIRE CONFIRMATION", blocking: false)
      end
      apps = an[:cabs].select { |u| u[:type].to_s =~ /fridge|hob|oven|sink|dishwasher|washer|microwave/ }
      check(c, 'SITE: appliance units present in the appliance schedule', apps.all? { |u| u[:code].to_s =~ Numbering::UID }, apps.size, blocking: false)
      blocking = c.select { |x| x['status'] == 'BLOCKED' }
      { 'ok' => blocking.empty?, 'checks' => c, 'blocking' => blocking, 'warnings' => c.select { |x| x['status'] == 'WARNING' } }
    end

    def text(g)
      (["PRODUCTION INTEGRITY GATE: #{g['ok'] ? 'PASS' : 'BLOCKED'}"] + g['checks'].map { |x| "#{x['status'].ljust(8)} #{x['check']}#{x['detail'].to_s.empty? ? '' : " - #{x['detail']}"}" }).join("\r\n")
    end

    def raise_if_blocked(g)
      return if g['ok']

      raise "PRODUCTION_GATE_BLOCKED: final production export refused.\n" + g['blocking'].map { |x| "#{x['check']}: #{x['detail']}" }.join("\n")
    end
  end
end
