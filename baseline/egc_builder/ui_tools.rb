# frozen_string_literal: true

require 'json'
require 'fileutils'

module EGC
  # Dialog callbacks for the Tools tab: views, scenes, preflight, quotation, drawings, production files.
  module App
    class << self
      def register_tools(d)
        d.add_action_callback('tools_init') { |_, _| guard { send({ 'type' => 'tags', 'states' => ViewTools.tag_states, 'client' => Config.read_json('client_b64', {}) }) } }
        d.add_action_callback('tags') { |_, json| guard { do_tags(JSON.parse(json)) } }
        d.add_action_callback('explode') { |_, json| guard { do_explode(JSON.parse(json)) } }
        d.add_action_callback('isolate') { |_, m| guard { do_isolate(m.to_s) } }
        d.add_action_callback('scenes') { |_, m| guard { do_scenes(m.to_s) } }
        d.add_action_callback('audit') { |_, json| guard { do_audit(JSON.parse(json)) } }
        d.add_action_callback('quote') { |_, json| guard('Production: client quotation') { do_quote(JSON.parse(json)) } }
        d.add_action_callback('drawings') { |_, json| guard('Production: shop drawings') { do_drawings(JSON.parse(json)) } }
        d.add_action_callback('presets_get') { |_, _| send({ 'type' => 'presets', 'list' => Config.read_json('presets_b64', []) }) }
        d.add_action_callback('preset_save') do |_, json|
          p = JSON.parse(json)
          list = Config.read_json('presets_b64', []).reject { |x| x['name'] == p['name'] }
          list << p
          Config.write_json('presets_b64', list)
          send({ 'type' => 'presets', 'list' => list })
        end
        d.add_action_callback('preset_delete') do |_, name|
          list = Config.read_json('presets_b64', []).reject { |x| x['name'] == name }
          Config.write_json('presets_b64', list)
          send({ 'type' => 'presets', 'list' => list })
        end
        d.add_action_callback('license_status') { |_, _| send({ 'type' => 'license', 'status' => License.status, 'enforce' => License::ENFORCE }) }
        d.add_action_callback('license_activate') do |_, key|
          ok = License.activate(key)
          send({ 'type' => 'license', 'status' => License.status, 'ok' => ok, 'enforce' => License::ENFORCE })
        end
        d.add_action_callback('production') do |_, json|
          kind = (JSON.parse(json)['kind'] rescue 'output')
          guard("Production: #{kind}") { do_production(JSON.parse(json)) }
        end
        d.add_action_callback('factory_package') { |_, json| guard('Production: factory shop drawings') { do_package(JSON.parse(json), 'factory') } }
        d.add_action_callback('site_mep_package') { |_, json| guard('Production: site / MEP drawings') { do_package(JSON.parse(json), 'site') } }
        d.add_action_callback('machine_package') { |_, json| guard('Production: production data package') { do_package(JSON.parse(json), 'machine') } }
        d.add_action_callback('complete_package') { |_, json| guard('Production: complete project package') { do_package(JSON.parse(json), 'complete') } }
        d.add_action_callback('custom_list') { |_, _| guard { send({ 'type' => 'custom_units', 'list' => CustomUnits.payload }) } }
        d.add_action_callback('custom_save') do |_, json|
          guard('Custom unit: register') do
            msg = JSON.parse(json)
            g = selected_cabinet
            raise 'CUSTOM_UNIT_ERROR: select a native E.G.C unit first.' unless g

            item = CustomUnits.register(g, msg['name'])
            send({ 'type' => 'custom_units', 'list' => CustomUnits.payload })
            send({ 'type' => 'toast', 'msg' => "Custom unit #{item['id']} registered" })
          end
        end
        d.add_action_callback('custom_delete') { |_, id| guard { CustomUnits.delete(id); send({ 'type' => 'custom_units', 'list' => CustomUnits.payload }) } }
        d.add_action_callback('custom_insert') do |_, json|
          guard('Custom unit: place') do
            msg = JSON.parse(json)
            Sketchup.active_model.select_tool(PlaceTool.new(:unit, CustomUnits.params(msg['id'], w: msg['w']), cfg_from(msg)))
            send({ 'type' => 'toast', 'msg' => 'pick_point' })
          end
        end
        d.add_action_callback('service_review_get') { |_, json| guard('Production: service point review') { do_service_review(JSON.parse(json)) } }
        d.add_action_callback('service_review_save') { |_, json| guard('Production: save service point review') { save_service_review(JSON.parse(json)) } }
      end

      def do_tags(msg)
        case msg['mode']
        when 'client' then ViewTools.client_view(msg['on'])
        when 'all' then ViewTools.show_all_tags
        when 'set'
          EGC.safe_op(Sketchup.active_model, 'E.G.C tag') { ViewTools.set_tag(msg['name'], msg['visible']) }
        end
        send({ 'type' => 'tags', 'states' => ViewTools.tag_states })
      end

      def do_explode(msg)
        m = Sketchup.active_model
        sel = m.selection.to_a
        sel = m.entities.to_a if sel.empty?
        EGC.safe_op(m, 'E.G.C explode') { ViewTools.explode(sel, msg['t'].to_f, (msg['amount'] || 300).to_f) }
      end

      def do_isolate(mode)
        if mode == 'show'
          ViewTools.show_everything
        elsif !ViewTools.isolate(Sketchup.active_model.selection)
          send({ 'type' => 'toast', 'msg' => 'select_any' })
        end
      end

      def do_scenes(mode)
        if mode == 'export'
          dir = ::UI.select_directory(title: 'E.G.C scenes export folder')
          return unless dir

          files = ViewTools.export_scenes(dir)
          ::UI.openURL("file:///#{File.join(dir, 'scenes.html').tr('\\', '/')}") if files.any?
          send({ 'type' => 'toast', 'msg' => 'exported' })
        else
          names = ViewTools.build_scenes
          send({ 'type' => 'toast', 'msg' => names.empty? ? 'nothing' : 'scenes_done' })
        end
      end

      def do_audit(msg)
        cfg = cfg_from(msg)
        l = msg['lang'] || lang
        r = Audit.run(cfg, Sketchup.active_model, use_selection: msg['scope'] == 'selection')
        items = r[:issues].map { |i| i.merge('text' => Audit.message(i['code'], l)) }
        send({ 'type' => 'audit', 'issues' => items, 'errors' => r[:errors], 'warnings' => r[:warnings], 'parts' => r[:parts] })
      end

      # Nothing is written to the user's disk here: the output is staged and shown in the preview window; Save there writes it.
      # Returns nil so callers stop (the 'exported' toast is sent when the user really saves).
      def save_and_open(content, default_name, ext = 'html', title = nil)
        base = Sketchup.active_model.title.to_s
        base = 'EGC_Project' if base.empty?
        Preview.document(content, "#{base}_#{default_name}.#{ext}", title: title || default_name.tr('_', ' '), lang: lang,
                                                                     on_saved: ->(_path) { send({ 'type' => 'toast', 'msg' => 'exported' }) })
        nil
      end

      def do_quote(msg)
        cfg = cfg_from(msg)
        client = msg['client'] || {}
        Config.write_json('client_b64', client)
        Config.save_project(Sketchup.active_model, cfg.merge('quote' => client))
        l = msg['lang'] || lang
        res = Cutlist.analyse(cfg, Sketchup.active_model, use_selection: msg['scope'] == 'selection')
        Cutlist.guard_exports!(res)
        if res[:rows].empty?
          raise 'QUOTATION_NO_MODEL_PARTS: no modeled cabinet parts were found. Generate or edit the current kitchen and include at least one E.G.C unit before requesting a quotation.'
        end
        pricing = Costing.internal(res, cfg, l)
        unless pricing[:complete]
          missing = pricing[:missing].first(8).map { |x| x['item'] }.join(', ')
          raise "PROJECT_PRICING_INCOMPLETE: quotation withheld because these model-derived costs have no project price: #{missing}. Open Production > Project Pricing, enter the missing prices, save to this SketchUp model, then generate the quotation again."
        end
        q = Quote.html(res, client, cfg, l)
        code = l == 'ar' ? 'AR' : 'EN'
        Preview.document(q[:html], "Client_Quotation_#{code}.html", title: l == 'ar' ? 'عرض سعر العميل' : 'Client quotation', lang: l, kind: :pdf,
                                                                    save_name: "Client_Quotation_#{code}.pdf",
                                                                    on_saved: ->(path) { send({ 'type' => 'toast', 'msg' => "PDF created: #{path}", 'total' => q[:total].round }) })
      end

      def do_drawings(msg)
        cfg = cfg_from(msg)
        m = Sketchup.active_model
        sel = m.selection.grep(Sketchup::Group).select { |g| g.get_attribute('egc', 'spec') || g.get_attribute('egc', 'wardrobe') }
        if sel.empty?
          all = []
          Audit.collect_cabs(m.entities.to_a, all)
          sel = all.first(60)
        end
        if sel.empty?
          raise 'SHOP_DRAWINGS_NO_CABINETS: no E.G.C cabinet groups are available. Generate/edit a unit or clear the selection to draw all modeled cabinets.'
        end
        return unless save_and_open(Drawings.html(sel, cfg, msg['lang'] || lang), 'shop_drawings')

        send({ 'type' => 'toast', 'msg' => 'exported' })
      end

      def do_production(msg)
        cfg = cfg_from(msg)
        l = msg['lang'] || lang
        res = Cutlist.analyse(cfg, Sketchup.active_model, use_selection: msg['scope'] == 'selection')
        Cutlist.guard_exports!(res)
        raise 'PRODUCTION_NO_PARTS: no modeled cut-list parts were found. Generate or edit the E.G.C units, then export again.' if res[:rows].empty?
        case msg['kind']
        when 'labels' then return unless save_and_open(Labels.html(res, l), 'labels', 'html') # printable stickers with QR codes (labels.csv stays in the production package)
        when 'boring'
          csv = Cutlist.boring_csv(res)
          raise 'DRILLING_OFF: drilling is switched off for production (Settings: Drilling in production) | التخريم مقفول في ملفات الإنتاج (الإعدادات: التخريم في الإنتاج)' unless Cutlist.hw_bores?(cfg)
          raise 'NO_DRILLING_DATA: the current modeled parts contain no recorded hinge/shelf-pin drilling specification. Rebuild the affected unit with supported hardware before exporting.' unless csv.lines.size > 1
          return unless save_and_open(csv, 'hinge_hardware_drilling', 'csv')
        when 'groove'
          csv = Cutlist.groove_csv(res)
          raise 'NO_LED_GROOVES: no modeled parts contain LED groove geometry. Enable LED routing and regenerate the affected upper units before exporting.' unless csv.lines.size > 1
          return unless save_and_open(csv, 'led_groove_routing', 'csv')
        when 'laser'
          csv = Cutlist.laser_csv(res)
          raise 'LASER_NESTING_EMPTY: nesting produced no part placements. Check stock dimensions and cut-list integrity, then export again.' unless csv.lines.size > 1
          return unless save_and_open(csv, 'laser_cut_positions', 'csv')
        when 'ocl' then return unless save_and_open(Cutlist.opencutlist_csv(res, l), 'opencutlist_parts', 'csv')
        when 'dxf'
          oversize = res[:nest].values.flat_map { |n| n[:oversize] }
          if oversize.any?
            raise "NESTING_OVERSIZE: choose larger stock or resize these parts before nesting export: #{oversize.map { |p| p[:id] }.join(', ')}"
          end
          return unless save_and_open(Nesting.dxf(res[:nest]), 'nesting', 'dxf')
        else
          raise "Unknown production output: #{msg['kind']}"
        end
        send({ 'type' => 'toast', 'msg' => 'exported' })
      end

      def do_package(msg, kind)
        model = Sketchup.active_model
        cfg = cfg_from(msg)
        lang = msg['lang'] || lang()
        proj = Assistant.load(model)
        name = proj['name'].to_s.empty? ? model.title.to_s : proj['name'].to_s
        name = 'EGC_Project' if name.empty?
        titles = if lang == 'ar'
                   { 'factory' => 'حزمة المصنع (شوب دروينج + بيانات الماكينات)', 'site' => 'حزمة الموقع (شوب دروينج كهرباء / سباكة / تركيب)', 'machine' => 'بيانات الإنتاج للماكينات', 'complete' => 'الحزمة الكاملة (مصنع + موقع)' }
                 else
                   { 'factory' => 'Factory package', 'site' => 'Site / MEP package', 'machine' => 'Production data package', 'complete' => 'Complete project package' }
                 end
        suffix = { 'factory' => 'Factory', 'site' => 'Site_MEP', 'machine' => 'Production_Data', 'complete' => 'Complete' }[kind]
        folder = "#{name.gsub(/[^\w-]+/, '_')}_#{suffix}_rev#{proj['rev']}_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
        entry = { 'factory' => '01_Shop_Drawings/Factory_Shop_Drawings.html', 'site' => '01_GA/Site_Shop_Drawings.html', 'machine' => 'Production_Data/cutlist.csv',
                  'complete' => '1_Factory/01_Shop_Drawings/Factory_Shop_Drawings.html' }[kind]
        # the whole package is built into the preview staging folder; Save in the preview window copies exactly those files
        job = Preview.package(title: titles[kind], folder_name: folder, lang: lang, entry: entry,
                              on_saved: ->(target) { send({ 'type' => 'toast', 'msg' => "#{titles[kind]} created: #{target}" }) }) do |stage|
          case kind
          when 'factory' then ProductionPackages.factory(model, cfg, lang, stage, proj)
          when 'site' then ProductionPackages.site_mep(model, cfg, lang, stage, proj)
          when 'machine' then ProductionPackages.machine(model, cfg, lang, stage, proj)
          else ProductionPackages.complete(model, cfg, lang, stage, proj)
          end
        end
        first = job[:result][:pdf] || job[:result][:index]
        job[:open_after] = File.expand_path(first)[(File.expand_path(Preview.stage).size + 1)..] if first
      end

      def do_service_review(msg)
        model = Sketchup.active_model
        data = SiteDocs.collect(model, Assistant.load(model), cfg_from(msg))
        sv = SiteDocs.services(data)
        send({ 'type' => 'service_review', 'points' => sv['points'], 'orphans' => sv['orphans'], 'unmatched' => sv['unmatched_devices'] })
      end

      def save_service_review(msg)
        rows = msg['points']
        model = Sketchup.active_model
        proj = Assistant.load(model)
        accepted = SiteDocs.normalize_service_review(rows)
        keys = accepted.map { |p| [p['kind'], p['device'], p['wall']] }
        proj['services'] = proj['services'].reject { |p| keys.include?([p['kind'], p['device'], p['wall']]) } + accepted
        Assistant.save(proj, model)
        send({ 'type' => 'service_review_saved' })
      end
    end
  end
end
