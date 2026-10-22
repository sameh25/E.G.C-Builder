# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'digest'
require 'cgi'

module EGC
  # SITE & MANUFACTURING PACKAGE  ("جهز المشروع للتنفيذ والتصنيع" / "Create Site & Manufacturing Pack")
  #
  # Nothing here is a second data source: every document is produced from the current 3D model, the constraint model and the existing production core
  # (Cutlist / Nesting / Drawings / Report / Quote). The package layout:
  #   01_SITE_PLAN 02_WALL_ELEVATIONS 03_ELECTRICAL 04_PLUMBING_GAS_DUCT 05_WORKTOP_CUTOUTS 06_SECTIONS_INSTALLATION 07_CABINET_SHOP_DRAWINGS
  #   08_CUTLIST_NESTING_MATERIAL_TAKEOFF 09_COST_INTERNAL 10_CUSTOMER_QUOTE 11_INSTALLATION_NOTES 12_CLIENT_PRESENTATION  (+ STATUS.html, manifest.json)
  #
  # STALENESS: every document stores the fingerprints it was made from (layout / production / constraints / prices). When the model changes later the
  # affected documents become OUTDATED (SitePack.status). CROSS-CHECK: 3D model <-> cabinet IDs <-> part IDs <-> appliances <-> service points <->
  # site drawings <-> shop drawings <-> cut list <-> nesting <-> material takeoff <-> cost / quote. FINAL ISSUE is refused while anything critical is stale,
  # unconfirmed or unpriced.
  module SitePack
    module_function

    DIRS = { 'site_plan' => '01_SITE_PLAN', 'elevations' => '02_WALL_ELEVATIONS', 'electrical' => '03_ELECTRICAL', 'plumbing' => '04_PLUMBING_GAS_DUCT', 'worktop' => '05_WORKTOP_CUTOUTS',
             'sections' => '06_SECTIONS_INSTALLATION', 'shop' => '07_CABINET_SHOP_DRAWINGS', 'production' => '08_CUTLIST_NESTING_MATERIAL_TAKEOFF', 'cost' => '09_COST_INTERNAL',
             'quote' => '10_CUSTOMER_QUOTE', 'notes' => '11_INSTALLATION_NOTES', 'client' => '12_CLIENT_PRESENTATION' }.freeze
    DEPS = { 'site_plan' => %w[layout constraints], 'elevations' => %w[layout constraints], 'electrical' => %w[layout constraints], 'plumbing' => %w[layout constraints],
             'worktop' => %w[layout production], 'sections' => %w[layout constraints], 'shop' => %w[layout production], 'production' => %w[production], 'cost' => %w[production prices],
             'quote' => %w[production prices], 'notes' => %w[layout constraints], 'client' => %w[layout] }.freeze

    # ------------------------------------------------------------------ fingerprints
    def production_hash(an)
      rows = an[:rows].map { |r| [r[:part], r[:len], r[:wid], r[:thk], r[:qty], r[:mat], r[:groove], r[:groove_geo], r[:eb_l], r[:eb_w], r[:eb_t], r[:notes]].join('|') }.sort
      sheets = an[:nest].map do |(k, t), n|
        placed = n[:sheets].map { |s| s[:placed].map { |p| [p[:item][:id], p[:x], p[:y], p[:w], p[:h], p[:rotated]] } }
        JSON.generate([k, t, n[:sheet], placed, n[:oversize]])
      end.sort
      cfg = an[:cfg] || {}
      stock = cfg.slice('sheet_l', 'sheet_w', 'sheets', 'grain_lock', 'kerf', 'trim')
      Digest::MD5.hexdigest((rows + sheets + [JSON.generate(stock), JSON.generate(an[:hw].transform_values { |v| v.round(2) })]).join("\n"))
    end

    def prices_hash(cfg, client = {})
      Digest::MD5.hexdigest(JSON.generate([cfg['price_m2'], cfg['price_sheet'], cfg['price_edge_m'], cfg['price_hw'], cfg['price_app'], cfg['extra_costs'], cfg['labor_pct'], cfg['quote'], client]))
    end

    def hashes(model, proj, cfg, an, client = {})
      { 'layout' => ClientShot.geometry_fingerprint(model), 'production' => production_hash(an), 'constraints' => Assistant.constraints_hash(proj), 'prices' => prices_hash(cfg, client) }
    end

    # ------------------------------------------------------------------ status of the documents already issued
    # -> [{ 'key','file','status' => CURRENT|OUTDATED|NOT_GENERATED, 'why' => [...] }]
    def status(model, proj, cfg, client = {})
      client = proj['quote_client'] || {} if client.empty?
      an = Cutlist.analyse(cfg, model, use_selection: false)
      now = hashes(model, proj, cfg, an, client)
      DEPS.keys.map do |k|
        d = proj['docs'][k]
        next({ 'key' => k, 'status' => 'NOT_GENERATED', 'why' => [], 'files' => [] }) unless d

        changed = DEPS[k].select { |dep| d['deps'][dep] != now[dep] }
        { 'key' => k, 'status' => changed.empty? ? 'CURRENT' : 'OUTDATED', 'why' => changed.map { |c| "#{c} changed since #{Time.at(d['at']).strftime('%H:%M:%S')}" }, 'files' => d['files'] }
      end
    end

    # ------------------------------------------------------------------ unresolved (REQUIRES_CONFIRMATION) items - the assistant states them, never guesses
    def unresolved(model, proj, cfg, an, ic)
      out = []
      out << 'room geometry is not CONFIRMED (' + proj['room']['poly_st'].to_s + ')' unless proj['room']['poly_st'] == Assistant::CONFIRMED
      out << 'ceiling height not confirmed' unless proj['room']['ceiling']['st'] == Assistant::CONFIRMED
      proj['openings'].each { |o| out << "opening #{o['id']} is #{o['st']}" unless o['st'] == Assistant::CONFIRMED }
      proj['columns'].each { |c| out << "column #{c['id']} is #{c['st']}" unless c['st'] == Assistant::CONFIRMED }
      data = SiteDocs.collect(model, proj, cfg)
      sv = SiteDocs.services(data)
      sv['points'].each { |p| out << "service point #{p['id']} (#{p['label']}, wall #{p['wall']}) is a proposal: REQUIRES_CONFIRMATION" if p['st'] != 'CONFIRMED' }
      data[:units].each { |u| u['requires'].each { |r| out << "#{u['name']}: #{r['item']} (#{r['detail']}) REQUIRES_CONFIRMATION" } }
      ic[:missing].each { |m| out << "MISSING PRICE: #{m['item']} (#{m['reason']})" }
      out.uniq
    end

    # ------------------------------------------------------------------ CROSS-CHECK
    def crosscheck(model, proj, cfg, an, ic, docs)
      issues = []
      add = ->(code, sev, where, msg, action = nil) { issues << { 'code' => code, 'severity' => sev, 'where' => where, 'message' => msg, 'action' => action } }
      units = Exposure.collect(model)[:units]
      # 1. production data really matches the 3D geometry
      an[:integrity].each do |b|
        code = b[:code] || 'STALE_PRODUCTION_DATA'
        add.call(code, 'error', "#{b[:cab]}/#{b[:part]}", b[:detail].to_s, code == 'OVERLAPPING_UNITS' ? 'delete or move the duplicate' : 'rebuild the unit (E.G.C Resize / Edit)')
      end
      # 2. cabinet IDs / part IDs: 3D <-> cut list <-> nesting <-> shop drawing
      model_pids = []
      units.each { |u| Validate.parts_of(u).each { |p| model_pids << p[:d]['pid'].to_s if %w[part glass].include?(p[:role]) && p[:d]['pid'] } }
      each_root_part(model).each { |d| model_pids << d['pid'].to_s if d['pid'] }
      cut_pids = an[:raw].map { |r| r[:pid].to_s }.reject(&:empty?)
      nest_ids = an[:nest].values.flat_map { |n| n[:items].map { |i| i[:id].to_s } }
      add.call('ID_MISMATCH_CUTLIST', 'error', 'cut list', "#{(model_pids - cut_pids).size} model part(s) are not in the cut list, #{(cut_pids - model_pids).size} cut list part(s) are not in the model") if (model_pids - cut_pids).any? || (cut_pids - model_pids).any?
      board = an[:raw].reject { |r| %w[top glass splash].include?(r[:mat]) }.map { |r| r[:pid].to_s }
      add.call('ID_MISMATCH_NESTING', 'error', 'nesting', "#{(board - nest_ids).size} board part(s) missing from the nesting, #{(nest_ids - board).size} nesting id(s) unknown") if (board - nest_ids).any? || (nest_ids - board).any?
      shop = docs['shop_text'].to_s
      if shop.empty?
        add.call('SHOP_DRAWINGS_NOT_CHECKED', 'warn', 'shop drawings', 'no shop drawing text supplied to the cross-check')
      else
        miss = units.select { |u| %w[wall base tall hood].include?(u.kind) }.reject { |u| shop.include?(CGI.escapeHTML(u.g.name)) }.map { |u| u.g.name }
        add.call('SHOP_DRAWING_MISSING_CABINET', 'error', 'shop drawings', "cabinets without a shop drawing: #{miss.first(5).join(', ')}") unless miss.empty?
        pm = cut_pids.reject { |pid| shop.include?("<td>#{CGI.escapeHTML(pid)}</td>") }
        add.call('SHOP_DRAWING_PART_IDS', 'error', 'shop drawings', "#{pm.size} part id(s) of the cut list are not in the shop drawings: #{pm.first(4).join(', ')}") unless pm.empty?
      end
      # 3. appliances <-> service points
      data = SiteDocs.collect(model, proj, cfg)
      sv = SiteDocs.services(data)
      data[:units].each do |u|
        u['apps'].each do |ap|
          need = { 'sink' => %w[water_cold water_hot drain], 'dishwasher' => %w[elec water_cold drain], 'washer' => %w[elec water_cold drain], 'hob_gas' => %w[gas], 'hood' => %w[elec duct] }[ap['kind']] || %w[elec]
          have = sv['points'].select { |p| p['unit'] == u['code'] && p['device_kind'] == ap['kind'] }.map { |p| p['kind'] }
          add.call('APPLIANCE_WITHOUT_SERVICE', 'error', "#{u['name']}/#{ap['kind']}", "service points missing: #{(need - have).join(', ')}") unless (need - have).empty? || %w[fridge freezer oven hob].include?(ap['kind']) && (have & need).any?
        end
      end
      # 4. quantities: takeoff / cost follow the nesting
      sheets = EGC::Num.sum(an[:nest].values) { |n| n[:sheets].size }
      cost_sheets = EGC::Num.sum(ic[:lines].select { |l| l[:cat] == 'board' && l[:item] =~ /\((\d+) sheets\)/ }) { |l| l[:item][/\((\d+) sheets\)/, 1].to_i }
      add.call('COST_NOT_FROM_NESTING', 'error', 'cost', "cost lines count #{cost_sheets} sheets, nesting needs #{sheets}") unless cost_sheets == sheets
      # 5. outdated documents
      (docs['status'] || []).each { |s| add.call('DOCUMENT_OUTDATED', 'error', s['key'], s['why'].join('; '), 'regenerate the package') if s['status'] == 'OUTDATED' }
      # 6. unknown critical data
      unresolved(model, proj, cfg, an, ic).each { |u| add.call('REQUIRES_CONFIRMATION', 'warn', 'project', u, 'confirm or enter the real value') }
      final_ok = issues.none? { |i| i['severity'] == 'error' } && issues.none? { |i| i['code'] == 'REQUIRES_CONFIRMATION' }
      { 'issues' => issues, 'errors' => issues.count { |i| i['severity'] == 'error' }, 'warnings' => issues.count { |i| i['severity'] == 'warn' }, 'final_allowed' => final_ok }
    end

    # worktop slabs, fascia pieces, fillers, end panels: parts that belong to a run, not to one cabinet - they need drawings too (same part IDs as the cut list)
    def run_parts_sheet(model, cfg, lang, proj)
      rows = each_root_part(model).sort_by { |d| d['pid'].to_s }.map do |d|
        eb = d['eb_l'].to_i.zero? && d['eb_w'].to_i.zero? ? '' : "L×#{d['eb_l']} W×#{d['eb_w']}"
        "<tr><td>#{CGI.escapeHTML(d['pid'].to_s)}</td><td>#{CGI.escapeHTML(I18n.part(d['part'].to_s, lang))}</td><td>#{d['len']}</td><td>#{d['wid']}</td><td>#{d['thk']}</td><td>#{CGI.escapeHTML((cfg['mat_names'][d['mat']] || d['mat']).to_s)}</td><td>#{CGI.escapeHTML(eb)}</td><td>#{CGI.escapeHTML(d['notes'].to_s)}</td></tr>"
      end
      "<section class='page'><header><div class='brand'>E.G.C <b>Builder</b></div><div><h1>#{lang == 'ar' ? 'قطع الأضلاع: سطح العمل والوزرة والحشوات' : 'Run pieces: worktop, fascia, fillers, end panels'}</h1></div></header><table><tr><th>ID</th><th>Part</th><th>Length</th><th>Width</th><th>Thk</th><th>Material</th><th>Edge</th><th>Groove / cutouts</th></tr>#{rows.join}</table></section>"
    end

    def each_root_part(model)
      out = []
      walk = lambda do |ents|
        ents.each do |e|
          next unless e.is_a?(Sketchup::Group)

          d = e.attribute_dictionary('egc')
          if d && d['role'] == 'part' && d['pid'] && !ancestor_unit?(e)
            out << d
          elsif !(d && d['role']) && !(d && d['spec'] && d['cab'])
            walk.call(e.entities)
          end
        end
      end
      walk.call(model.entities)
      out
    end

    def ancestor_unit?(g)
      p = g.parent
      while p.respond_to?(:instances) && (i = p.instances.first)
        return true if i.get_attribute('egc', 'spec') && i.get_attribute('egc', 'cab')

        p = i.parent
      end
      false
    end

    # ------------------------------------------------------------------ BUILD
    # opts: 'lang' 'en'|'ar', 'client' => { name, project, margin_pct, vat_pct, ... }, 'final' => bool, 'client_shots' => bool, 'scenes' => bool
    def build(model, proj, cfg, dir, opts = {})
      lang = (opts['lang'] || 'en').to_s
      client = opts['client'] || { 'name' => proj['client'], 'project' => proj['name'], 'margin_pct' => (cfg['quote'] || {})['margin_pct'], 'vat_pct' => (cfg['quote'] || {})['vat_pct'], 'discount_pct' => 0, 'valid_days' => 15 }
      t0 = Time.now
      Exposure.refresh(cfg, model, own_op: true)
      an = Cutlist.analyse(cfg, model, use_selection: false)
      ic = Costing.internal(an, cfg, lang)
      timing = { 'analysis_s' => (Time.now - t0).round(2) }
      data = SiteDocs.collect(model, proj, cfg)
      files = Hash.new { |h, k| h[k] = [] }
      docs_text = {}
      write = lambda do |key, name, content|
        d = File.join(dir, DIRS[key])
        FileUtils.mkdir_p(d)
        File.binwrite(File.join(d, name), content.to_s.encode('UTF-8')) # binary: CSV keeps its exact CRLF (text mode would write CR CR LF)
        files[key] << "#{DIRS[key]}/#{name}"
      end
      proj['quote_client'] = client
      hs = hashes(model, proj, cfg, an, client)
      pending_final = opts['final'] ? true : false
      # a first cross-check decides the status printed on every sheet
      groups = ClientShot.kitchen_roots(model).flat_map { |r| AssistantEdit.units_in(r) }.map(&:g)
      groups = Exposure.collect(model)[:units].map(&:g) if groups.empty?
      shop_html = Drawings.html(groups.select { |g| g.get_attribute('egc', 'spec') }, cfg, lang, proj['name'].to_s.empty? ? model.title.to_s : proj['name'])
      shop_html = shop_html.sub('</body></html>') { run_parts_sheet(model, cfg, lang, proj) + '</body></html>' }
      guard_ok = an[:integrity].empty?
      cc0 = crosscheck(model, proj, cfg, an, ic, { 'shop_text' => shop_html, 'status' => [] })
      final = pending_final && cc0['final_allowed']
      requested_status = %w[DRAFT FOR REVIEW APPROVED AS\ BUILT].include?(opts['status'].to_s) ? opts['status'].to_s : 'DRAFT'
      st = { status: final ? 'FOR PRODUCTION' : requested_status, doc: 'CURRENT' }
      refused = pending_final && !final
      t1 = Time.now
      write.call('site_plan', 'site_plan.html', SvgDraw.page('Site plan', SiteDocs.site_plan(data, lang, st), lang))
      SiteDocs.used_walls(data).each do |w|
        write.call('elevations', "elevation_wall_#{w['id']}.html", SvgDraw.page("Elevation #{w['id']}", SiteDocs.elevation(data, w, lang, st), lang))
      end
      write.call('electrical', 'electrical_plan.html', SvgDraw.page('Electrical', SiteDocs.services_plan(data, %w[elec], 'ELECTRICAL PLAN (site preparation)', 'مخطط الكهرباء (تجهيز الموقع)', '03', lang, st), lang))
      sv = SiteDocs.services(data)
      write.call('electrical', 'service_points.csv', service_csv(sv['points']))
      write.call('plumbing', 'plumbing_plan.html', SvgDraw.page('Plumbing', SiteDocs.services_plan(data, %w[water_cold water_hot drain], 'PLUMBING PLAN (water + drain)', 'مخطط السباكة (مياه + صرف)', '04-P', lang, st), lang))
      write.call('plumbing', 'gas_duct_plan.html', SvgDraw.page('Gas / hood duct', SiteDocs.services_plan(data, %w[gas duct], 'GAS / HOOD DUCT PLAN', 'مخطط الغاز / مخرج الشفاط', '04-G', lang, st), lang))
      write.call('worktop', 'worktop_plan.html', SvgDraw.page('Worktop', SiteDocs.worktop(data, lang, st), lang))
      secs = SiteDocs.sections(data, lang, st)
      write.call('sections', 'sections.html', SvgDraw.page('Sections', secs, lang))
      write.call('sections', 'appliance_installation.html', SvgDraw.page('Appliance installation', SiteDocs.appliance_sheet(data, lang, st), lang))
      write.call('sections', 'installation_plan.html', SvgDraw.page('Installation plan', SiteDocs.installation(data, lang, st), lang))
      write.call('shop', 'shop_drawings.html', shop_html)
      Phase1Docs.outputs(data, groups.select { |g| g.get_attribute('egc', 'spec') }, cfg, lang, st).each do |name, content|
        key = name.start_with?('E-01') ? 'electrical' : name.start_with?('P-01') ? 'plumbing' : name.start_with?('A-01') ? 'sections' : 'shop'
        write.call(key, name, content)
      end
      if guard_ok
        write.call('production', 'cutlist.csv', Cutlist.csv(an, lang))
        write.call('production', 'labels.csv', Cutlist.labels_csv(an, lang))
        write.call('production', 'opencutlist.csv', Cutlist.opencutlist_csv(an, lang))
        write.call('production', 'drilling.csv', Cutlist.boring_csv(an))
        write.call('production', 'groove_routing.csv', Cutlist.groove_csv(an))
        write.call('production', 'nesting.dxf', Nesting.dxf(an[:nest]))
        write.call('production', 'cutlist_report.html', Report.html(an, lang, proj['name'].to_s))
      else
        write.call('production', 'PRODUCTION_BLOCKED.txt', "STALE_PRODUCTION_DATA / OVERLAPPING_UNITS: production exports refused.\n" + an[:integrity].first(10).map { |b| "#{b[:cab]}/#{b[:part]}: #{b[:detail]}" }.join("\n"))
      end
      tk = Costing.takeoff(an, cfg, lang)
      write.call('production', 'material_takeoff.html', SvgDraw.page('Material takeoff', SvgDraw.sheet(proj, title: lang == 'ar' ? 'حصر الخامات' : 'MATERIAL TAKEOFF', sheet_no: '08-M', scale: 'NTS', zone: 'ALL', status: st[:status], lang: lang, extra_status: st[:doc], body: Costing.takeoff_html(tk, lang)), lang))
      write.call('production', 'material_takeoff.csv', Costing.takeoff_csv(tk))
      write.call('cost', 'internal_cost.html', SvgDraw.page('Internal cost', SvgDraw.sheet(proj, title: lang == 'ar' ? 'التكلفة الداخلية (سري)' : 'INTERNAL COST (confidential)', sheet_no: '09', scale: 'NTS', zone: 'ALL', status: st[:status], lang: lang, extra_status: st[:doc], body: Costing.internal_html(ic, lang)), lang))
      write.call('quote', 'customer_quote.html', Costing.customer_html(an, client, cfg, lang, ic)[:html])
      unres = unresolved(model, proj, cfg, an, ic)
      write.call('notes', 'installation_notes.html', SvgDraw.page('Installation notes', SiteDocs.notes(data, unres, lang, st), lang))
      timing['documents_s'] = (Time.now - t1).round(2)
      # client presentation (cameras only - the geometry is verified unchanged)
      shots = nil
      if opts['client_shots'] != false
        begin
          prev_sel = model.selection.to_a
          model.selection.clear # selection outlines must never appear in a client picture (restored below)
          shots = ClientShot.run(model, proj, cfg)
          d = File.join(dir, DIRS['client'])
          FileUtils.mkdir_p(d)
          view = model.active_view
          shots['scenes'].each do |s|
            model.pages.selected_page = model.pages[s['name']]
            view.camera = model.pages[s['name']].camera
            ClientShot.presentation_options(model) # selecting a scene loads its style (blue sky, edges): the picture must use the clean presentation options
            view.refresh
            fn = "#{s['name']}.png"
            view.write_image({ filename: File.join(d, fn), width: 1600, height: 1000, antialias: true })
            files['client'] << "#{DIRS['client']}/#{fn}"
          end
          model.selection.add(prev_sel.select(&:valid?)) unless prev_sel.empty?
          write.call('client', 'presentation_notes.html', SvgDraw.page('Client presentation', SvgDraw.sheet(proj, title: 'CLIENT PRESENTATION', sheet_no: '12', scale: '-', zone: 'ALL', status: st[:status], lang: lang, extra_status: st[:doc],
                                                                                                                     body: SvgDraw.data_table(%w[Scene Eye Target FOV Notes], shots['scenes'].map { |s| [s['name'], s['eye'].join(', '), s['target'].join(', '), s['fov'], s['notes'].join('; ')] }) + "<div class='note'>geometry unchanged: #{shots['geometry_unchanged']}</div>"), lang))
        rescue StandardError => e
          Diag.log('client_shot', {}, error: e)
          write.call('client', 'CLIENT_SHOT_FAILED.txt', e.message)
        end
      end
      # record what each document was made from (staleness engine)
      now = Time.now.to_i
      DEPS.each do |k, deps|
        proj['docs'][k] = { 'files' => files[k], 'deps' => deps.to_h { |x| [x, hs[x]] }, 'at' => now, 'status_printed' => st[:status] }
      end
      proj['docs_meta'] = { 'dir' => dir, 'lang' => lang, 'final' => final, 'at' => now }
      Assistant.save(proj, model)
      cc = crosscheck(model, proj, cfg, an, ic, { 'shop_text' => shop_html, 'status' => status(model, proj, cfg, client) })
      status_html = status_page(proj, cc, status(model, proj, cfg, client), unres, ic, st, lang)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'STATUS.html'), status_html, encoding: 'UTF-8')
      manifest = { 'project' => proj['name'], 'client' => proj['client'], 'rev' => proj['rev'], 'version' => PLUGIN_VERSION, 'status' => st[:status], 'final_requested' => pending_final, 'final_refused' => refused, 'hashes' => hs,
                   'files' => files, 'crosscheck' => cc.slice('errors', 'warnings', 'final_allowed'), 'timing' => timing.merge('total_s' => (Time.now - t0).round(2)), 'entities' => model.entities.size }
      File.write(File.join(dir, 'manifest.json'), JSON.pretty_generate(manifest), encoding: 'UTF-8')
      { 'dir' => dir, 'manifest' => manifest, 'crosscheck' => cc, 'unresolved' => unres, 'internal_cost' => { 'total' => ic[:total], 'complete' => ic[:complete], 'missing' => ic[:missing] }, 'takeoff' => tk, 'shots' => shots, 'refused_final' => refused }
    end

    def service_csv(pts)
      rows = [%w[service_id kind device device_kind unit wall_reference wall_status x_from_wall_start_mm z_above_model_ffl_mm specification status source]]
      codes = { 'elec' => 'E', 'water_cold' => 'CW', 'water_hot' => 'HW', 'drain' => 'D', 'gas' => 'G', 'duct' => 'DU', 'led' => 'LED' }
      pts.each { |p| rows << [p['id'], codes[p['kind']] || p['kind'], p['device'], p['device_kind'], p['unit'], p['wall'], p['wall_status'], p['off'].round, p['z'].round, p['spec'] || 'REQUIRES_CONFIRMATION', p['st'], p['src']] }
      rows.map { |r| r.map { |c| "\"#{c.to_s.gsub('"', '""')}\"" }.join(',') }.join("\n")
    end

    def status_page(proj, cc, stat, unres, ic, st, lang)
      ar = lang == 'ar'
      s = +"<h2>#{ar ? 'حالة المستندات' : 'Document status'}</h2>"
      s << SvgDraw.data_table([ar ? 'المستند' : 'Document', ar ? 'الحالة' : 'Status', ar ? 'السبب' : 'Reason'], stat.map { |x| [x['key'], SvgDraw.badge(x['status']), x['why'].join('; ')] })
      s << "<h2>#{ar ? 'الفحص المتقاطع' : 'Cross-check'} (#{cc['errors']} errors, #{cc['warnings']} warnings)</h2>"
      s << SvgDraw.data_table(%w[Code Severity Where Message Action], cc['issues'].map { |i| [i['code'], i['severity'], i['where'], i['message'], i['action'].to_s] })
      s << "<div class='#{cc['final_allowed'] ? 'note' : 'warn'}'>FINAL ISSUE: #{cc['final_allowed'] ? 'ALLOWED' : 'BLOCKED'}</div>"
      SvgDraw.page('Package status', SvgDraw.sheet(proj, title: 'PACKAGE STATUS', sheet_no: '00', scale: '-', zone: 'ALL', status: st[:status], lang: lang, extra_status: nil, body: s), lang)
    end
  end
end
