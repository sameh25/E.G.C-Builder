# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'cgi'

module EGC
  # Audience-specific exports built from the same current model extraction.
  module ProductionPackages
    module_function

    def h(value)
      CGI.escapeHTML(value.to_s)
    end

    def page(title, links, lang)
      dir = lang == 'ar' ? 'rtl' : 'ltr'
      label = lang == 'ar' ? 'ملفات الحزمة' : 'Package files'
      "<!doctype html><html lang='#{lang}' dir='#{dir}'><meta charset='utf-8'><title>#{h(title)}</title><style>body{font:16px Arial;max-width:1100px;margin:30px auto;padding:0 20px}li{margin:8px}a{color:#154c79}</style><h1>#{h(title)}</h1><h2>#{label}</h2><ul>#{links.map { |name, href| "<li><a href='#{h(href)}'>#{h(name)}</a></li>" }.join}</ul></html>"
    end

    def save(path, content)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, content.to_s.encode('UTF-8'))
    end

    def unit_groups(model)
      roots = ClientShot.kitchen_roots(model)
      groups = roots.flat_map { |root| AssistantEdit.units_in(root).map(&:g) }
      # manually placed / custom units live outside the kitchen roots: they are production units too
      groups += Exposure.collect(model)[:units].map(&:g)
      groups.select { |g| g.valid? && g.get_attribute('egc', 'spec') }.uniq
    end

    def unit_details(data, groups, cfg, lang, st)
      groups.map do |g|
        code = g.get_attribute('egc', 'code').to_s
        code = format('U%02d', groups.index(g) + 1) if code.empty?
        sheet_id = "F-03-#{code.gsub(/[^A-Za-z0-9_-]/, '_')}"
        html = Phase1Docs.representative_unit(data, groups, cfg, lang, st, group: g).gsub('K-03', sheet_id)
        [sheet_id, "#{sheet_id}_#{code}.html", html]
      end
    end

    # Human-readable factory schedules (F-04..F-10), one sheet per page-sized chunk, built from the same analysis as the CSV outputs.
    def schedule_sheets(an, data, groups, cfg, lang, proj)
      ar = lang == 'ar'
      k = ->(en, a) { ar ? a : en }
      out = []
      add = lambda do |no, title, body_chunks|
        body_chunks.each_with_index do |body, i|
          n = body_chunks.size > 1 ? "#{no}-#{i + 1}" : no
          html = SvgDraw.sheet(proj, title: "#{title}#{body_chunks.size > 1 ? " (#{i + 1}/#{body_chunks.size})" : ''}", sheet_no: n, scale: 'NTS', zone: 'ALL', status: 'DRAFT', lang: lang, body: body)
          out << [n, "#{n}_#{title.downcase.gsub(/[^a-z0-9]+/, '_')}.html", html, title]
        end
      end
      table = lambda do |headers, rows, per = 27|
        rows = [[k.call('(none)', '(لا يوجد)')] + [''] * (headers.size - 1)] if rows.empty?
        rows.each_slice(per).map { |chunk| SvgDraw.data_table(headers, chunk) }
      end
      add.call('F-04', k.call('Material schedule', 'جدول الخامات'), [Costing.takeoff_html(Costing.takeoff(an, cfg, lang), lang)])
      parts = an[:raw].sort_by { |p| [p[:code].to_s, p[:pid].to_s] }
      add.call('F-05', k.call('Cut list', 'قائمة القطع'),
               table.call(%w[Part\ ID Unit Part Material Thk L W Edge Notes], parts.map { |p| [p[:pid], p[:code], p[:part], (cfg['mat_names'] || {})[p[:mat]] || p[:mat], p[:thk], p[:len], p[:wid], "#{p[:eb_l]}L/#{p[:eb_w]}W", [p[:groove], p[:notes]].compact.join(' ')] }, 27))
      add.call('F-06', k.call('Edge band schedule', 'جدول شريط الحواف'),
               table.call(['Part ID', 'Unit', 'Material', 'Edge thk', 'Long edges', 'Short edges'], parts.select { |p| p[:eb_l].to_i.positive? || p[:eb_w].to_i.positive? }.map { |p| [p[:pid], p[:code], p[:mat], p[:eb_t], p[:eb_l], p[:eb_w]] }, 27))
      hw_rows = an[:hw].select { |kk, v| v.to_f.positive? && kk.to_s != 'plinth_m' }.map { |kk, v| [kk, v.round(1), kk.to_s.start_with?('hinge') ? 'GENERIC - REQUIRES HINGE SPECIFICATION' : 'GENERIC'] }
      plinth_m = an[:hw].fetch('plinth_m', 0).to_f
      hw_rows << ['Plastic plinth profile (purchased, 3000 mm lengths)', "#{(plinth_m * 1000 / 3000.0).ceil} pcs / #{plinth_m.round(2)} m", 'NOT SHEET STOCK'] if plinth_m.positive?
      add.call('F-07', k.call('Hardware schedule', 'جدول الإكسسوارات'), table.call(['Item', 'Quantity', 'Status'], hw_rows, 27))
      mech_rows = groups.filter_map do |g|
        id = g.get_attribute('egc', 'mech')
        next unless id
        [g.get_attribute('egc', 'code'), id, Mechanisms.verification(id), 1, 'REQUIRES MECHANISM SPECIFICATION']
      end
      add.call('F-08', k.call('Mechanism schedule', 'جدول الميكانيزمات'), table.call(['Unit', 'Mechanism', 'Verification', 'Qty', 'Status'], mech_rows, 27))
      app_rows = data[:units].flat_map { |u| u['apps'].map { |a| op = a['opening'] || {}; [u['code'], a['dev'], a['kind'], [op['w'], op['h'], op['d']].compact.join(' x '), (a['profile'] || {})['data_status'] || 'REQUIRES CONFIRMATION'] } }
      add.call('F-09', k.call('Appliance schedule', 'جدول الأجهزة'), table.call(['Unit', 'Appliance', 'Type', 'Opening W x H x D', 'Data status'], app_rows, 27))
      top_rows = an[:raw].select { |p| p[:mat] == 'top' }.map { |p| [p[:pid], p[:code], p[:len], p[:wid], p[:thk], p[:notes]] }
      add.call('F-10', k.call('Countertop and cutouts', 'الرخام والفتحات'), table.call(['Part ID', 'Unit', 'Length', 'Width', 'Thk', 'Cutouts / notes'], top_rows, 27))
      out
    end

    # Machine / production data (CSV, DXF, labels, grooves, drilling status). Shared by the Factory package and the stand-alone Production Data package.
    def write_production_data(dir, an, data, groups, cfg, lang, links)
      production = production_files(an, data, groups, cfg, lang)
      production.each { |name, contents| save(File.join(dir, 'Production_Data', name), contents); links << [name, "Production_Data/#{name}"] }
      save(File.join(dir, 'Production_Data', 'machine_data_status.txt'), machine_notes(an, cfg).join("\r\n"))
      links << ['Machine data status / limitations', 'Production_Data/machine_data_status.txt']
    end

    def production_files(an, data, groups, cfg, lang)
      production = {
        'cutlist.csv' => Cutlist.csv(an, lang), 'nesting.csv' => nesting_csv(an),
        'back_grooves.csv' => table_csv(%w[part_id unit_id part groove_reference offset_mm depth_mm width_mm back_thickness_mm status], an[:raw].filter_map do |p|
          g = p[:back_groove]
          next unless g
          gd = JSON.parse(g.to_s) rescue {}
          [p[:pid], p[:code], p[:part], gd['reference'], gd['offset'], gd['depth'], gd['width'], cfg['back_thk'], gd['status']]
        end),
        'cutting.csv' => Cutlist.laser_csv(an), 'laser.csv' => Cutlist.laser_csv(an),
        'laser_cut_positions.csv' => Cutlist.laser_csv(an), 'labels/labels.csv' => Cutlist.labels_csv(an, lang), 'labels/labels.html' => Labels.html(an, lang),
        'hardware.csv' => table_csv(%w[item quantity category], an[:hw].select { |k, v| v.to_f.positive? && k.to_s != 'plinth_m' }.map { |k, v| [k, v, Quote::MECHANISM_PRICE_KEYS.include?(k.to_s) ? 'mechanism' : 'hardware'] }),
        'mechanisms.csv' => table_csv(%w[mechanism quantity], an[:hw].select { |k, v| v.to_f.positive? && Quote::MECHANISM_PRICE_KEYS.include?(k.to_s) }.map { |k, v| [k, v] }), # mechanism hardware only (legs, clips, hinges ... are in hardware.csv)
        'mechanism_profiles.csv' => table_csv(%w[unit_id mechanism_id manufacturer model category host nominal_width_mm verification parameters drilling_status], groups.filter_map { |g| id = g.get_attribute('egc', 'mech').to_s; next if id.empty?; p = Mechanisms.profile(id); [g.get_attribute('egc', 'code'), id, p && p['manufacturer'], p && p['model'], p && p['type'], p && p['host'], p && p['nominal_width_mm'], p && p['verification'], p && JSON.generate(p['parameters']), p && p['drilling_status']] }),
        'plinth_profiles.csv' => begin
          required_m = an[:hw].fetch('plinth_m', 0).to_f
          stock_length_mm = 3000
          profile_qty = (required_m * 1000 / stock_length_mm).ceil
          table_csv(%w[item required_length_mm standard_stock_length_mm purchased_profiles clips], required_m.positive? ? [['Plastic plinth profile', (required_m * 1000).round(1), stock_length_mm, profile_qty, an[:hw].fetch('plinth_clip', 0)]] : [])
        end,
        'drilling.csv' => Cutlist.boring_csv(an), 'led_groove.csv' => Cutlist.groove_csv(an),
        'ocl.csv' => Cutlist.opencutlist_csv(an, lang), 'opencutlist.csv' => Cutlist.opencutlist_csv(an, lang), 'dxf/nesting.dxf' => Nesting.dxf(an[:nest]),
        'material_takeoff.csv' => Costing.takeoff_csv(Costing.takeoff(an, cfg, lang)),
        'edge_band_schedule.csv' => table_csv(%w[part_id unit_id material edge_thickness_mm long_edges short_edges], an[:raw].filter_map { |p| [p[:pid], p[:code], p[:mat], p[:eb_t], p[:eb_l], p[:eb_w]] if p[:eb_l].to_i.positive? || p[:eb_w].to_i.positive? }),
        'appliance_openings.csv' => table_csv(%w[unit_id appliance_code type opening_width_mm opening_height_mm opening_depth_mm source], data[:units].flat_map { |u| u['apps'].map { |a| [u['code'], a['dev'], a['kind'], a.dig('opening', 'w'), a.dig('opening', 'h'), a.dig('opening', 'd'), a['dev_src']] } }),
        'appliance_profiles.csv' => table_csv(%w[unit_id appliance_id type manufacturer model nominal_width_mm nominal_height_mm nominal_depth_mm opening_width_mm opening_height_mm opening_depth_mm service_types data_status], data[:units].flat_map { |u| u['apps'].map { |a| pr = a['profile'] || {}; nd = pr['nominal_dimensions_mm'] || {}; op = a['opening'] || {}; [u['code'], a['dev'], a['kind'], pr['manufacturer'], pr['model'], nd['w'], nd['h'], nd['d'], op['w'], op['h'], op['d'], Array(pr['service_types']).join('|'), pr['data_status'] || 'REQUIRES_CONFIRMATION'] } } ),
        'countertop_cutouts.csv' => table_csv(%w[part_id unit_id length_mm width_mm thickness_mm notes], an[:raw].filter_map { |p| [p[:pid], p[:code], p[:len], p[:wid], p[:thk], p[:notes]] if p[:mat] == 'top' && p[:notes].to_s.match?(/cutout|sink|hob/i) })
      }
      production.merge!(Cam.files(an, lang)) # layered CNC DXF + one cut list per sheet material
      production
    end

    def machine_notes(an, cfg)
      drilling_rows = Cutlist.boring_csv(an).lines.size - 1
      groove_rows = Cutlist.groove_csv(an).lines.size - 1
      machine_notes = []
      machine_notes << 'REQUIRES MECHANISM SPECIFICATION: no modeled drilling coordinates were found; no hinge/runner/shelf-pin positions were invented.' if drilling_rows.zero?
      machine_notes << 'NO MODELED LED GROOVES: LED CNC output contains only its header; regenerate units with configured groove geometry if routing is required.' if groove_rows.zero?
      back_status = Config.back_groove_status(cfg)
      machine_notes << (back_status == 'REQUIRES CONSTRUCTION PARAMETER' ?
        'REQUIRES CONSTRUCTION PARAMETER: back-groove depth or offset is missing; no inset groove machining data is issued.' :
        'BACK GROOVE MODELED: closed carcass side parts carry rebate metadata and back_grooves.csv. Confirm machine-side orientation before CNC; generic CNC coordinates are not included in hinge/drilling output.')
      machine_notes << 'GENERIC HINGE PROFILE: visible hinge geometry and motion are generic; manufacturer/model and drilling specification remain unconfirmed. Generic cup locations are excluded from CNC drilling output.' if an[:hw]['hinge'].to_f.positive?
      machine_notes << 'DXF geometry is limited to modeled/nested part outlines and supported groove geometry; verify all cutouts against the unit detail/model before machining.'
      machine_notes
    end

    # Stand-alone Production Data (machine) package: no drawings, only the machine outputs.
    def machine(model, cfg, lang, dir, proj = Assistant.load(model))
      groups = unit_groups(model)
      raise 'PRODUCTION_EXPORT_ERROR: generate or place at least one E.G.C cabinet before exporting production data.' if groups.empty?
      an = Cutlist.analyse(cfg, model, use_selection: false)
      Cutlist.guard_exports!(an)
      oversize = an[:nest].values.flat_map { |n| n[:oversize] }
      raise "PRODUCTION_EXPORT_ERROR: #{oversize.map { |p| p[:id] }.join(', ')} exceed configured sheet stock. Update project stock dimensions or resize those parts first." if oversize.any?
      data = SiteDocs.collect(model, proj, cfg)
      FileUtils.mkdir_p(dir)
      links = []
      write_production_data(dir, an, data, groups, cfg, lang, links)
      save(File.join(dir, 'index.html'), page(lang == 'ar' ? 'حزمة بيانات الإنتاج' : 'Production data package', links, lang))
      { dir: dir, files: links.size + 1, index: File.join(dir, 'index.html') }
    end

    # Complete project package: Factory + Site + Production data in sub-folders (client quotation stays a separate, priced, client-facing document).
    def complete(model, cfg, lang, dir, proj = Assistant.load(model))
      FileUtils.mkdir_p(dir)
      f = factory(model, cfg, lang, File.join(dir, '1_Factory'), proj)
      st = site_mep(model, cfg, lang, File.join(dir, '2_Site_MEP'), proj)
      { dir: dir, factory: f, site: st, pdf: f[:pdf] }
    end

    FACTORY_DIRS = { 'drawings' => '01_Shop_Drawings', 'parts' => '02_Part_Drawings', 'cut' => '03_Cut_List', 'carcass' => '04_Carcass', 'exterior' => '05_Exterior', 'back' => '06_Back',
                     'hw' => '07_Hardware', 'mech' => '08_Mechanisms', 'nest' => '09_Nesting', 'dxf' => '10_DXF', 'cnc' => '11_CNC', 'labels' => '12_Labels', 'assembly' => '13_Assembly',
                     'bom' => '14_BOM', 'rev' => '15_Revision' }.freeze
    # machine file -> factory folder
    FACTORY_MAP = { 'cutlist.csv' => 'cut', 'ocl.csv' => 'cut', 'opencutlist.csv' => 'cut', 'nesting.csv' => 'nest', 'cutting.csv' => 'nest', 'laser.csv' => 'nest',
                    'laser_cut_positions.csv' => 'nest', 'dxf/nesting.dxf' => 'nest', 'back_grooves.csv' => 'back', 'labels/labels.csv' => 'labels', 'labels/labels.html' => 'labels',
                    'hardware.csv' => 'hw', 'plinth_profiles.csv' => 'hw', 'mechanisms.csv' => 'mech', 'mechanism_profiles.csv' => 'mech', 'drilling.csv' => 'cnc', 'led_groove.csv' => 'cnc',
                    'material_takeoff.csv' => 'bom', 'edge_band_schedule.csv' => 'bom', 'appliance_openings.csv' => 'assembly', 'appliance_profiles.csv' => 'bom', 'countertop_cutouts.csv' => 'bom' }.freeze

    # Factory package: everything the workshop needs to MANUFACTURE, in numbered folders. Refused (with the exact reasons) when the production
    # integrity gate blocks. The revision is issued first, so every sheet and file carries the same revision letter.
    def factory(model, cfg, lang, dir, proj = Assistant.load(model))
      groups = unit_groups(model)
      raise 'FACTORY_PACKAGE_NO_UNITS: generate or place at least one E.G.C cabinet before exporting.' if groups.empty?

      Numbering.apply(model, own_op: true) if Numbering.stale?(model)
      rev = Revision.issue(cfg, model, 'factory package')
      proj = Assistant.load(model)
      set = begin
        ExecFactory.build(model, cfg, lang, proj)
      rescue StandardError => e
        Diag.log('factory_drawing', { lang: lang }, error: e, state: 'FACTORY_DRAWING_ERROR')
        raise
      end
      an = set[:an]
      oversize = an[:nest].values.flat_map { |n| n[:oversize] }
      raise "FACTORY_NESTING_OVERSIZE: #{oversize.map { |p| p[:id] }.join(', ')} exceed configured sheet stock. Update project stock dimensions or resize those parts before exporting the factory package." if oversize.any?

      gate = ProductionGate.run(model, cfg, an, sheets: set[:sheets], proj: proj, kind: 'factory')
      ProductionGate.raise_if_blocked(gate)
      FileUtils.mkdir_p(dir)
      links = []
      put = ->(key, name, content) { rel = "#{FACTORY_DIRS[key]}/#{name}"; save(File.join(dir, rel), content); links << [rel, rel] }
      html = ExecDraw.html_page(set[:sheets], title: 'Factory Shop Drawings', lang: lang)
      put.call('drawings', 'Factory_Shop_Drawings.html', html)
      put.call('drawings', 'drawing_lint.json', JSON.pretty_generate(ExecDraw.lint_report(set[:sheets])))
      put.call('parts', 'Part_Drawings.html', PartDrawings.html(an, lang))
      put.call('cut', 'cutlist_all_families.csv', Families.csv(an, nil, lang))
      put.call('carcass', 'cutlist_carcass.csv', Families.csv(an, 'CARCASS', lang))
      put.call('exterior', 'cutlist_exterior.csv', Families.csv(an, 'EXTERIOR', lang))
      put.call('back', 'cutlist_back.csv', Families.csv(an, 'BACK', lang))
      put.call('bom', 'worktop.csv', Families.csv(an, 'WORKTOP', lang))
      put.call('bom', 'plinth_and_special.csv', Families.csv(an, 'PLINTH', lang) + "\r\n" + Families.rows(an, 'SPECIAL', lang).map { |rw| rw.map { |v| "\"#{v}\"" }.join(',') }.join("\r\n"))
      production_files(an, set[:data], groups, cfg, lang).each do |name, content|
        if name.start_with?('cam/') then put.call('dxf', File.basename(name), content)
        elsif name.start_with?('cutlists/') then put.call('nest', File.basename(name), content)
        else put.call(FACTORY_MAP[name] || 'bom', File.basename(name), content)
        end
      end
      put.call('cnc', 'machine_data_status.txt', machine_notes(an, cfg).join("\r\n"))
      mp = MachineProfile.verified
      if mp
        ck = MachineProfile.check(mp, an)
        if ck['errors'].empty?
          put.call('cnc', "#{mp['name'].gsub(/[^A-Za-z0-9_-]+/, '_')}_operations.csv", MachineProfile.ops_csv(ck['ops']))
        else
          put.call('cnc', 'MACHINE_OUTPUT_BLOCKED.txt', "Machine profile #{mp['name']}: machine-specific output BLOCKED\r\n" + ck['errors'].join("\r\n"))
        end
      else
        put.call('cnc', 'REQUIRES_MACHINE_PROFILE.txt', "REQUIRES MACHINE PROFILE\r\nNo verified machine profile in #{MachineProfile.dir}.\r\nMachine-specific CNC output is NOT issued. The layered engineering DXF in 10_DXF is.\r\n" \
                                                        "A profile is a JSON file with: #{MachineProfile::REQUIRED.join(', ')} (tools: [{id, type: drill|router, dia, max_depth}], postprocessor: #{MachineProfile::POSTPROCESSORS.join('|')}).")
      end
      put.call('assembly', 'assembly.csv', assembly_csv(an, lang))
      put.call('bom', 'BOM_summary.csv', bom_csv(an, cfg))
      put.call('rev', 'revision.txt', "CURRENT REVISION: #{rev['rev']}\r\n\r\n#{Revision.text(model)}")
      put.call('rev', 'production_gate.txt', ProductionGate.text(gate))
      save(File.join(dir, 'index.html'), page(lang == 'ar' ? "حزمة المصنع - REV #{rev['rev']}" : "Factory package - REV #{rev['rev']}", links, lang))
      pdf_name = "#{FACTORY_DIRS['drawings']}/Factory_Shop_Drawings_#{lang == 'ar' ? 'AR' : 'EN'}.pdf"
      PdfExport.html_to_pdf(html, File.join(dir, pdf_name))
      { dir: dir, pdf: File.join(dir, pdf_name), units: groups.size, files: links.size + 2, sheets: set[:sheets].size, rev: rev['rev'], gate: gate }
    end

    # per unit: its boards (Part ID, size), its hardware and the order of assembly
    def assembly_csv(an, lang)
      rows = []
      order = { 'CARCASS' => 1, 'BACK' => 2, 'EXTERIOR' => 5, 'SPECIAL' => 6, 'WORKTOP' => 7, 'PLINTH' => 8 }
      an[:cabs].sort_by { |u| u[:code].to_s }.each do |u|
        an[:raw].select { |p| p[:code] == u[:code] }.sort_by { |p| [order[ProductionModel.family(p)] || 9, p[:pid].to_s] }.each do |p|
          rows << [u[:code], u[:type], order[ProductionModel.family(p)], ProductionModel.family(p), p[:pid], I18n.part(p[:part], lang), "#{p[:len]} x #{p[:wid]} x #{p[:thk]}"]
        end
        (u[:hw] || {}).each { |k, v| rows << [u[:code], u[:type], 3, 'HARDWARE', '', k, v] if v.to_f.positive? }
      end
      table_csv(%w[unit_id unit_type step family part_id part size_or_qty], rows) + "\r\n\"steps: 1 carcass (sides, bottom, top / rails, shelves) - 2 back into its groove - 3 hardware - 4 drawer boxes - 5 fronts - 6 glass / special - 7 worktop on site - 8 plinth on site\""
    end

    def bom_csv(an, cfg)
      rows = []
      ProductionModel::FAMILY_ORDER.each do |f|
        ps = an[:raw].select { |p| ProductionModel.family(p) == f }
        next if ps.empty?

        ps.group_by { |p| [p[:mat], p[:thk]] }.each do |(m, t), list|
          n = an[:nest][[m, t]]
          rows << [f, (cfg['mat_names'] || {})[m] || m, t, list.size, (list.sum { |p| p[:len] * p[:wid] } / 1_000_000.0).round(3), n ? n[:sheets].size : 'not sheet-nested', n ? n[:sheet].map(&:round).join(' x ') : '']
        end
      end
      (an[:edge] || {}).each { |t, m| rows << ['EDGE BANDING', "PVC #{t} mm", t, '', '', "#{m.round(2)} m", ''] }
      an[:hw].each { |k, v| rows << ['HARDWARE', k, '', v.round(2), '', '', ''] if v.to_f.positive? }
      (an[:apps] || {}).each { |k, v| rows << ['APPLIANCE', k, '', v, '', 'generic family profile - REQUIRES MODEL CONFIRMATION', ''] }
      table_csv(%w[family item thickness_mm boards_or_qty area_m2 sheets_or_note stock_mm], rows)
    end

    def table_csv(headers, rows)
      ([headers] + rows).map { |r| r.map { |v| "\"#{v.to_s.gsub('"', '""')}\"" }.join(',') }.join("\r\n")
    end

    # Sheet-local part placements come directly from the same Nesting.pack result as the laser CSV/DXF.
    def nesting_csv(an)
      headers = %w[material thickness_mm sheet_number stock_length_mm stock_width_mm part_id unit_id part sheet_x_mm sheet_y_mm cut_length_mm cut_width_mm rotated status]
      rows = []
      an[:nest].each do |(mat, thk), nest|
        nest[:sheets].each_with_index do |sheet, si|
          sheet[:placed].each do |placed|
            item = placed[:item]
            rows << [mat, thk, si + 1, *nest[:sheet], item[:id], item[:code], item[:part], placed[:x], placed[:y], placed[:w], placed[:h], placed[:rotated] ? 'YES' : 'NO', 'NESTED']
          end
        end
        nest[:oversize].each do |item|
          rows << [mat, thk, nil, *nest[:sheet], item[:id], item[:code], item[:part], nil, nil, item[:l], item[:w], nil, 'OVERSIZE']
        end
      end
      table_csv(headers, rows)
    end

    SITE_DIRS = %w[01_GA 02_Elevations 03_Unit_Identification 04_Finished_Dimensions 05_Fillers 06_Panels 07_Worktop 08_Appliances 09_Electrical 10_Water 11_Drain 12_Gas
                   13_Ventilation 14_Fixing 15_Installation 16_Revision].freeze
    SITE_SHEETS = { '02_Elevations' => %w[S-07 S-02A], '03_Unit_Identification' => %w[S-01], '08_Appliances' => %w[S-02A S-09], '09_Electrical' => %w[S-03 S-06], '10_Water' => %w[S-04],
                    '11_Drain' => %w[S-04], '12_Gas' => %w[S-05], '13_Ventilation' => %w[S-05], '16_Revision' => %w[S-10] }.freeze
    SITE_KINDS = { '09_Electrical' => %w[elec led], '10_Water' => %w[water_cold water_hot], '11_Drain' => %w[drain], '12_Gas' => %w[gas], '13_Ventilation' => %w[duct] }.freeze

    # Site / Civil-MEP package: everything the site engineer needs to INSTALL, in numbered folders (drawings per discipline + data). Same gate and revision.
    def site_mep(model, cfg, lang, dir, proj = Assistant.load(model))
      Numbering.apply(model, own_op: true) if Numbering.stale?(model)
      rev = Revision.issue(cfg, model, 'site package')
      proj = Assistant.load(model)
      set = begin
        ExecSite.build(model, cfg, lang, proj)
      rescue StandardError => e
        Diag.log('site_drawing', { lang: lang }, error: e, state: 'SITE_DRAWING_ERROR')
        raise
      end
      sv = set[:sv]
      an = Cutlist.analyse(cfg, model, use_selection: false)
      gate = ProductionGate.run(model, cfg, an, sheets: set[:sheets], proj: proj, kind: 'site')
      ProductionGate.raise_if_blocked(gate)
      FileUtils.mkdir_p(dir)
      links = []
      put = ->(folder, name, content) { rel = "#{folder}/#{name}"; save(File.join(dir, rel), content); links << [rel, rel] }
      html = ExecDraw.html_page(set[:sheets], title: 'Site Civil-MEP Shop Drawings', lang: lang)
      put.call('01_GA', 'Site_Shop_Drawings.html', html)
      put.call('01_GA', 'drawing_lint.json', JSON.pretty_generate(ExecDraw.lint_report(set[:sheets])))
      SITE_SHEETS.each do |folder, pre|
        sub = set[:sheets].select { |sh| pre.any? { |p| sh.no.to_s.start_with?(p) } }
        put.call(folder, 'sheets.html', ExecDraw.html_page(sub, title: folder, lang: lang)) unless sub.empty?
      end
      cols = %w[service_id type device unit wall X_from_datum_mm Z_AFFL_mm specification notes status source]
      row = ->(p) { [p['id'], p['kind'], p['device'], p['unit'], p['wall'], p['off'], p['z'], p['spec'], p['notes'], p['st'], p['src']] }
      SITE_KINDS.each { |folder, kinds| put.call(folder, 'service_points.csv', table_csv(cols, sv['points'].select { |p| kinds.include?(p['kind']) }.map(&row))) }
      put.call('16_Revision', 'service_points_all.csv', table_csv(cols, sv['points'].map(&row)))
      put.call('16_Revision', 'service_points.json', JSON.pretty_generate(sv))
      data = set[:data]
      put.call('04_Finished_Dimensions', 'units.csv', table_csv(%w[unit_id unit_type type W H D wall X_from_datum_start X_from_datum_end Z_bottom], data[:units].map { |u| [u['code'], Numbering::TYPE[u['kind'].to_s], u['type'], u['w'].to_f.round(1), u['h'].to_f.round(1), u['d'].to_f.round(1), u['wall'], u['along'] && u['along'][0].round, u['along'] && u['along'][1].round, u['z0'].to_f.round] }))
      pick = ->(parts) { an[:raw].select { |p| parts.include?(p[:part].to_s) }.map { |p| [p[:pid], p[:code], p[:cab], I18n.part(p[:part], lang), p[:len], p[:wid], p[:thk], (cfg['mat_names'] || {})[p[:mat]] || p[:mat]] } }
      head = %w[part_id unit_id run_or_unit part length width thickness material]
      put.call('05_Fillers', 'fillers.csv', table_csv(head, pick.call(%w[filler trim])))
      put.call('06_Panels', 'panels.csv', table_csv(head, pick.call(%w[end_panel fascia side_finish finish_panel])))
      put.call('07_Worktop', 'worktop.csv', table_csv(head, an[:raw].select { |p| %w[top splash].include?(p[:mat].to_s) }.map { |p| [p[:pid], p[:code], p[:cab], I18n.part(p[:part], lang), p[:len], p[:wid], p[:thk], p[:notes]] }))
      files = production_files(an, data, unit_groups(model), cfg, lang)
      put.call('07_Worktop', 'countertop_cutouts.csv', files['countertop_cutouts.csv'])
      put.call('08_Appliances', 'appliance_openings.csv', files['appliance_openings.csv'])
      put.call('08_Appliances', 'appliance_profiles.csv', files['appliance_profiles.csv'])
      put.call('14_Fixing', 'fixing.csv', table_csv(%w[unit_id unit_type fixing quantity note], an[:cabs].flat_map do |u|
        hw = u[:hw] || {}
        t = Numbering::TYPE[u[:kind].to_s]
        out = []
        out << [u[:code], t, 'wall hanger', hw['wall_hanger'], 'to the wall - wall plugs / screws REQUIRE SPECIFICATION for the wall type'] if hw['wall_hanger'].to_f.positive?
        out << [u[:code], t, 'adjustable leg', hw['leg'], 'level to the datum line'] if hw['leg'].to_f.positive?
        out << [u[:code], t, 'anti-tip fixing', 1, 'tall unit to the wall - REQUIRES SPECIFICATION'] if t == 'T'
        out << [u[:code], t, 'unit-to-unit connector', '', 'to the neighbouring units - REQUIRES SPECIFICATION'] if %w[B T].include?(t)
        out
      end))
      put.call('15_Installation', 'installation.txt', ["INSTALLATION SEQUENCE (REV #{rev['rev']})", '1. Check the services against 09-13 (positions are proposals until CONFIRMED).', '2. Mark the datum line (FFL) and the wall datum X = 0.',
                                                       '3. Set the base and tall units on their legs, level, connect (03, 04).', '4. Fix the tall units to the wall (anti-tip).', '5. Hang the wall units (14).',
                                                       '6. Fillers and panels (05, 06).', '7. Worktop and cutouts (07).', '8. Appliances (08) - models and clearances REQUIRE CONFIRMATION.', '9. Plinth profile, fronts adjustment, handles.'].join("\r\n"))
      put.call('16_Revision', 'revision.txt', "CURRENT REVISION: #{rev['rev']}\r\n\r\n#{Revision.text(model)}")
      put.call('16_Revision', 'production_gate.txt', ProductionGate.text(gate))
      save(File.join(dir, 'index.html'), page(lang == 'ar' ? "حزمة الموقع والخدمات - REV #{rev['rev']}" : "Site / MEP package - REV #{rev['rev']}", links, lang))
      pdf_name = "01_GA/Site_Engineer_Civil_MEP_Shop_Drawings_#{lang == 'ar' ? 'AR' : 'EN'}.pdf"
      PdfExport.html_to_pdf(html, File.join(dir, pdf_name))
      { dir: dir, pdf: File.join(dir, pdf_name), walls: SiteDocs.used_walls(set[:data]).size, services: sv['points'].size, files: links.size + 2, inferred: sv['points'].count { |q| q['st'] != 'CONFIRMED' }, sheets: set[:sheets].size, rev: rev['rev'], gate: gate }
    end
  end
end
