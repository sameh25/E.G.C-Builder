# frozen_string_literal: true

require 'json'
require 'base64'

module EGC
  # Dialog side of the Intelligent Assistant: one dispatcher, every handler answers the dialog with { type: 'assist', op:, data: }.
  module AssistantUI
    module_function

    OPS = %w[assist_ceiling assist_load assist_room assist_scan assist_add assist_correct assist_remove assist_image assist_scale assist_trace assist_propose assist_options assist_option_edit assist_providers assist_generate assist_validate
             assist_cmd_preview assist_cmd_apply assist_undo assist_shot assist_check assist_fix assist_pack assist_status assist_open_dir assist_project assist_services assist_vision_settings assist_vision_pick assist_vision_run assist_vision_apply assist_dxf assist_room_read assist_room_fix assist_render_pack assist_gate].freeze

    def model
      Sketchup.active_model
    end

    def reply(op, data)
      App.send({ "type" => "assist", "op" => op, "data" => AssistantI18n.reply(data, @lang) })
    end

    def state(lang = 'en', cfg = nil)
      proj = Assistant.load(model)
      cfg ||= Config.for_project(Config.build(Config.saved), model)
      { 'proj' => proj, 'summary' => Assistant.summary(proj, lang), 'walls' => Assistant.walls(proj).map { |w| w.slice('id', 'len', 'p0', 'p1') },
        'status' => (Exposure.collect(model)[:units].empty? ? [] : SitePack.status(model, proj, cfg)), 'has_kitchen' => !ClientShot.kitchen_roots(model).empty?,
        'room_model' => room_view(proj['room_model'], lang) }
    end

    # the reconstructed room as the user checks it before any proposal: dimension table (value, status, source, editable) + plan / elevation drawings
    def room_view(rm, lang)
      return nil unless rm

      { 'source' => rm['source'], 'rows' => RoomModel.table(rm, lang), 'svg' => RoomModel.svg(rm), 'problems' => rm['problems'], 'ready' => rm['ready'], 'confirmed' => rm['confirmed'] == true, 'pending' => rm['pending'] || [],
        'dims' => rm['dims'], 'relations' => rm['relations'], 'main_wall' => rm['main_wall'], 'questions' => rm['questions'] || [], 'checks' => rm['checks'] || [],
        'status' => rm['status'], 'type' => rm['type'], 'engine' => rm['engine'], 'mock' => rm['mock'], 'scale' => rm['scale'], 'depth' => rm['depth'], 'distance' => rm['distance'] }
    end

    def call(op, msg)
      lang = (msg["lang"] || App.lang || "en").to_s
      @lang = lang
      cfg = msg['cfg'] ? App.cfg_from(msg.merge('no_save' => true)) : Config.for_project(Config.build(Config.saved), model)
      proj = Assistant.load(model)
      case op
      when 'assist_load', 'assist_status' then reply(op, state(lang, cfg))
      when 'assist_project'
        %w[name client rev].each { |k| proj[k] = msg[k].to_s if msg.key?(k) }
        Assistant.save(proj, model)
        reply(op, state(lang, cfg))
      when 'assist_ceiling'
        v = msg['ceiling'].to_f
        raise 'ceiling must be a positive number (mm)' unless v.positive?

        Assistant.set_ceiling(proj, v, Assistant::CONFIRMED)
        Assistant.save(proj, model)
        reply(op, state(lang, cfg))
      when 'assist_room'
        if msg['poly'].is_a?(Array) && msg['poly'].size >= 3
          Assistant.set_room(proj, msg['poly'], msg['status'] || Assistant::CONFIRMED)
        else
          Assistant.room_from_dims(proj, msg['w'].to_f, msg['d'].to_f, Assistant::CONFIRMED)
        end
        Assistant.set_ceiling(proj, msg['ceiling'].to_f, Assistant::CONFIRMED) if msg['ceiling'].to_f.positive?
        Assistant.save(proj, model)
        reply(op, state(lang, cfg))
      when 'assist_render_pack'
        # presentation render source from the approved design, shown before saving like every other package
        Preview.package(title: lang == 'ar' ? 'مصدر الرندر (من التصميم المعتمد)' : 'Render source (from the approved design)', folder_name: "EGC_Render_Source_#{Time.now.strftime('%Y%m%d_%H%M%S')}",
                        lang: lang, entry: 'perspective_shaded.png') { |stage| RenderPack.export(model, cfg, stage, lang) }
        reply(op, { 'render_pack' => true })
      when 'assist_gate'
        g = ProductionGate.run(model, cfg)
        reply(op, { 'gate' => g })
      when 'assist_room_read'
        # SketchUp geometry -> the shared room model (no AI). Nothing is designed here: the user checks the table first.
        rm = RoomModel.from_skp(model)
        RoomModel.apply(rm, proj)
        Assistant.save(proj, model)
        reply(op, state(lang, cfg))
      when 'assist_room_fix'
        rm = proj['room_model'] or raise 'read the room first'
        rm = RoomModel.correct(rm, msg['key'].to_s, msg['value'])
        rm['poly'].to_a.size >= 3 ? RoomModel.apply(rm, proj) : proj['room_model'] = rm
        Assistant.save(proj, model)
        reply(op, state(lang, cfg))
      when 'assist_dxf'
        # TRACK 1 (no AI): room outline, openings, columns and the plumbing point from a 2D DXF; walls drawn to the ceiling; with 'build' the rule-based layout follows at once
        path = msg['path'] || UI.openpanel(lang == 'ar' ? 'اختر ملف DXF لحدود الغرفة' : 'Choose the room DXF', '', 'DXF|*.dxf||')
        return reply(op, { 'dxf' => { 'cancelled' => true } }) unless path

        np = Assistant.load_blank
        %w[name client rev].each { |k| np[k] = proj[k] if proj[k] }
        rep = RoomDxf.import(File.read(path, mode: 'rb').force_encoding('UTF-8'), np, { 'layer' => msg['layer'], 'ceiling' => msg['ceiling'] })
        model.start_operation('E.G.C room from DXF', true)
        Assistant.save(np, model)
        RoomDxf.build_shell(model, np) unless msg['shell'] == false
        model.commit_operation
        extra = { 'dxf' => rep }
        if msg['build']
          res = AssistantDesign.generate(np, cfg, { 'layout' => 'auto', 'accepted' => true, 'accept_inferred' => true }.merge(msg['opts'] || {}), model)
          extra.merge!('plan' => res['plan'].slice('layout', 'notes', 'problems'), 'made' => res['roots'].size, 'refused' => res['refused'],
                       'validation' => res['roots'].empty? ? nil : AssistantValidate.run(Assistant.load(model), cfg, model))
        end
        reply(op, state(lang, cfg).merge(extra))
      when 'assist_scan'
        ents = model.selection.empty? ? nil : model.selection.to_a
        segs = Assistant.scan_walls(model, ents)
        poly = Assistant.chain_polygon(segs)
        found = { 'segments' => segs.map { |s| { 'a' => s[:a].map(&:round), 'b' => s[:b].map(&:round), 'len' => s[:len].round, 'h' => s[:h].round } }, 'polygon' => poly && poly.map { |p| p.map(&:round) } }
        if msg['apply'] && poly
          Assistant.set_room(proj, poly, Assistant::INFERRED) # lengths are measured; which side is the room is inferred
          h = segs.map { |s| s[:h] }.max
          Assistant.set_ceiling(proj, h.round, Assistant::INFERRED) if h && !proj['room']['ceiling']['v']
          op_found = Assistant.scan_openings(proj, model)
          proj['openings'].reject! { |o| o['src'] }
          op_found.each { |o| e = Assistant.add_opening(proj, o['wall'], o['type'], o['off'], o['w'], o['h'], o['sill'], Assistant::CONFIRMED); e['src'] = o['src'] }
          Assistant.save(proj, model)
        end
        reply(op, state(lang, cfg).merge('found' => found))
      when 'assist_add'
        case msg['kind']
        when 'opening' then Assistant.add_opening(proj, msg['wall'], msg['type'] || 'window', msg['off'], msg['w'], msg['h'], msg['sill'])
        when 'column' then Assistant.add_column(proj, msg['wall'], msg['off'], msg['w'], msg['d'])
        when 'service' then Assistant.add_service(proj, msg['skind'], msg['wall'], msg['off'], msg['z'], msg['device'])
        end
        Assistant.save(proj, model)
        reply(op, state(lang, cfg))
      when 'assist_correct'
        v = msg['value']
        v = v.to_f if %w[off w h d z sill].include?(msg['field'])
        Assistant.correct(proj, msg['list'], msg['id'], msg['field'], v)
        Assistant.save(proj, model)
        reply(op, state(lang, cfg))
      when 'assist_remove'
        proj[msg['list']].reject! { |x| x['id'] == msg['id'] }
        Assistant.save(proj, model)
        reply(op, state(lang, cfg))
      when 'assist_image'
        path = msg['path'] || ::UI.openpanel('Plan image / sketch', '', 'Images|*.png;*.jpg;*.jpeg;*.bmp||')
        return unless path && File.exist?(path)

        bytes = File.binread(path)
        raise 'image larger than 8 MB' if bytes.size > 8_000_000

        mime = path =~ /\.png$/i ? 'image/png' : 'image/jpeg'
        Assistant.attach_image(proj, path)
        Assistant.save(proj, model)
        reply(op, state(lang, cfg).merge('image' => { 'path' => path, 'data' => "data:#{mime};base64,#{Base64.strict_encode64(bytes)}" },
                                         'vision' => AssistantProviders.analyze_image(path, proj).reject { |k, _| k == 'detected' }))
      when 'assist_vision_settings'
        AssistantVision.save_settings(msg['set']) if msg['set'].is_a?(Hash)
        reply(op, { 'vision_settings' => AssistantVision.settings })
      when 'assist_vision_pick'
        which = msg['which'] == 'design' ? 'design' : 'site'
        @vision ||= {}
        if msg['clear']
          @vision.delete(which)
          return reply(op, { 'vision_image' => { 'which' => which, 'path' => nil, 'data' => nil } })
        end
        path = msg['path'] || ::UI.openpanel(which == 'site' ? 'Site image (with dimensions)' : 'Design image', '', 'Images|*.png;*.jpg;*.jpeg;*.webp||')
        return reply(op, { 'cancelled' => true }) unless path && File.exist?(path)

        mime, b64 = AssistantVision.image_part(path)
        @vision[which] = path
        @vision_read = nil
        reply(op, { 'vision_image' => { 'which' => which, 'path' => path, 'data' => "data:#{mime};base64,#{b64}" } })
      when 'assist_vision_run'
        v = @vision || {}
        raise 'VISION_SITE_IMAGE_REQUIRED: choose the site image (the one with the dimensions) first.' unless v['site']

        done = lambda do |res|
          @vision_read = res['read'] if res['ok']
          # dimension-first read: the room is reconstructed at once and shown (table + plan + questions) - nothing is designed or built yet
          if res['ok'] && res['read']['site']['view'] == 'room'
            p2 = Assistant.load(model)
            AssistantVision.apply(res['read'], p2, paths: v)
            Assistant.save(p2, model)
            reply(op, state(lang, cfg).merge('vision_result' => res))
          else
            reply(op, { 'vision_result' => res })
          end
        end
        # the AI provider is an optional enhancement: without a key (or when asked) the picture is read on this computer (Windows text recognition)
        if AssistantVision.settings['has_key'] && msg['local'] != true
          AssistantVision.analyze(v['site'], v['design']) { |res| done.call(res) }
        else
          res = ImageLocal.analyze(v['site'])
          # the reference design image is optional and only an AI provider can read it: said plainly, the room is read all the same
          res['read']['site']['notes'] << 'the reference design image was not read (it needs an AI provider); the room and the proposals do not depend on it' if res['ok'] && v['design']
          done.call(res)
        end
      when 'assist_vision_apply'
        read = msg['read'].is_a?(Hash) ? msg['read'] : @vision_read
        raise 'VISION_NOTHING_READ: analyse the images first.' unless read

        AssistantVision.apply(read, proj, confirmed: msg['confirmed'] == true, paths: @vision || {})
        Assistant.set_ceiling(proj, msg['ceiling'].to_f, Assistant::CONFIRMED) if msg['ceiling'].to_f.positive?
        Assistant.save(proj, model)
        plan = AssistantDesign.propose(proj, cfg.merge('ceiling' => (proj['room']['ceiling']['v'] || cfg['ceiling']).to_f), { 'from_vision' => true })
        reply(op, state(lang, cfg).merge('vision_applied' => true, 'plan' => plan.slice('layout', 'notes', 'problems'),
                                         'runs' => plan['kitchens'].map { |k| k['params']['runs'].transform_values { |rr| { 'len' => rr['len'], 'cols' => rr['cols'].map { |c| "#{c['t']} #{c['w'].to_f.round}" } } } }))
      when 'assist_scale'
        Assistant.attach_image(proj, proj['image'] && proj['image']['path'], msg['ref'], msg['mm'])
        Assistant.image_consistency(proj, msg['checks'].map { |c| [c['px'], c['mm']] }) if msg['checks'].is_a?(Array) && msg['checks'].any?
        Assistant.save(proj, model)
        reply(op, state(lang, cfg))
      when 'assist_trace'
        r = Assistant.trace_room(proj, msg['points'])
        Assistant.save(proj, model)
        reply(op, state(lang, cfg).merge('trace' => r))
      when 'assist_propose'
        plan = AssistantDesign.propose(proj, cfg.merge('ceiling' => (proj['room']['ceiling']['v'] || cfg['ceiling']).to_f), msg['opts'] || {})
        reply(op, { 'plan' => plan.slice('layout', 'notes', 'problems'), 'runs' => plan['kitchens'].map { |k| k['params']['runs'].transform_values { |r| { 'len' => r['len'], 'cols' => r['cols'].map { |c| "#{c['t']} #{c['w'].to_f.round}" } } } } })
      when 'assist_providers'
        reply(op, { 'provider' => AssistantProviders.capabilities })
      when 'assist_options'
        raise 'define the room first (walls + ceiling)' unless Assistant.walls(proj).size >= 3

        reply(op, AssistantOptions.build(proj, cfg.merge('ceiling' => (proj['room']['ceiling']['v'] || cfg['ceiling']).to_f), msg['opts'] || {}))
      when 'assist_option_edit'
        raise 'define the room first (walls + ceiling)' unless Assistant.walls(proj).size >= 3

        reply(op, { 'option' => AssistantOptions.edit(proj, cfg.merge('ceiling' => (proj['room']['ceiling']['v'] || cfg['ceiling']).to_f), msg['opts'] || {}, msg['id']) })
      when 'assist_generate'
        # INPUT -> ANALYSIS -> PROPOSAL -> USER REVIEW -> USER ACCEPTS -> BUILD: nothing is built without an explicit accept.
        raise 'PROPOSAL_NOT_ACCEPTED - review a design proposal (A/B/C) and accept it before building' unless (msg['opts'] || {})['accepted'] == true

        raise 'define the room first (walls + ceiling)' unless Assistant.walls(proj).size >= 3
        sm = Assistant.summary(proj, lang)
        unless sm['ready'] # critical constraints first: nothing is designed from an unconfirmed / unscaled input
          miss = sm['lines'].select { |l| l[:st] == Assistant::REQ }.map { |l| "#{l[:label]}: #{l[:value]}" }
          miss << 'ceiling height' unless proj['room']['ceiling']['v']
          raise "CONSTRAINTS_INCOMPLETE - confirm first: #{miss.join(' | ')}"
        end
        inferred = sm['lines'].select { |l| l[:st] == Assistant::INFERRED }
        if inferred.any? && !(msg['opts'] || {})['accept_inferred']
          raise "CONSTRAINTS_UNCONFIRMED - correct/confirm or tick 'accept inferred values': #{inferred.map { |l| "#{l[:label]}: #{l[:value]}" }.join(' | ')}"
        end

        res = AssistantDesign.generate(proj, cfg, msg['opts'] || {}, model)
        val = res['roots'].empty? ? nil : AssistantValidate.run(Assistant.load(model), cfg, model)
        reply(op, { 'plan' => res['plan'].slice('layout', 'notes', 'problems'), 'made' => res['roots'].size, 'refused' => res['refused'], 'validation' => val })
      when 'assist_validate'
        reply(op, { 'validation' => AssistantValidate.run(proj, cfg, model) })
      when 'assist_cmd_preview'
        pv = AssistantEdit.preview(msg['text'], cfg, proj, model)
        @pending = pv if pv['ok']
        reply(op, pv.reject { |k, _| k == 'target' })
      when 'assist_cmd_apply'
        raise 'no preview to apply' unless @pending

        r = AssistantEdit.apply(@pending, cfg, model, confirm: msg['confirm'] == true)
        @pending = nil if r['ok']
        reply(op, r.merge('validation' => (r['ok'] ? AssistantValidate.run(Assistant.load(model), cfg, model) : nil)))
      when 'assist_undo'
        Sketchup.undo
        reply(op, { 'undone' => true, 'validation' => AssistantValidate.run(Assistant.load(model), cfg, model) })
      when 'assist_shot'
        reply(op, { 'report' => ClientShot.run(model, proj, cfg), 'check' => ClientShot.check(model, proj) })
      when 'assist_check'
        reply(op, { 'check' => ClientShot.check(model, proj) })
      when 'assist_fix'
        ClientShot.fix(model)
        reply(op, { 'check' => ClientShot.check(model, proj) })
      when 'assist_pack'
        opts = { 'lang' => lang, 'final' => msg['final'] == true, 'status' => msg['status'], 'client' => msg['client'], 'client_shots' => msg['client_shots'] != false }
        folder = "EGC_Package_#{(proj['name'].to_s.empty? ? 'Project' : proj['name']).gsub(/[^\w\-]+/, '_')}_rev#{proj['rev']}"
        answer = lambda do |r, dir|
          { 'dir' => dir, 'status' => r['manifest']['status'], 'files' => r['manifest']['files'].transform_values(&:size), 'crosscheck' => r['crosscheck'].slice('errors', 'warnings', 'final_allowed'),
            'issues' => r['crosscheck']['issues'].first(40), 'cost' => r['internal_cost'], 'timing' => r['manifest']['timing'], 'refused_final' => r['refused_final'], 'unresolved' => r['unresolved'].first(30), 'takeoff' => r['takeoff']['totals'] }
        end
        if msg['dir'] # explicit folder (scripts / tests): written directly
          r = SitePack.build(model, proj, cfg, File.join(msg['dir'], folder), opts)
          return reply(op, answer.call(r, r['dir']))
        end
        # PREVIEW BEFORE SAVE: the package is built into the staging folder and shown. The project record (issued documents) is restored when the
        # user cancels, and points at the real folder once it is saved.
        before = JSON.generate(proj)
        r = nil
        Preview.package(title: lang == 'ar' ? 'حزمة الموقع والتصنيع' : 'Site & Manufacturing package', folder_name: folder, lang: lang, entry: 'STATUS.html', open_after: 'STATUS.html',
                        on_saved: lambda { |target|
                          pr = Assistant.load(model)
                          (pr['docs_meta'] ||= {})['dir'] = target
                          Assistant.save(pr, model)
                          reply(op, answer.call(r, target))
                        },
                        on_cancel: lambda {
                          Assistant.save(JSON.parse(before), model)
                          reply(op, { 'cancelled' => true })
                        }) { |stage| r = SitePack.build(model, proj, cfg, stage, opts) }
      when 'assist_services'
        raise 'generate the kitchen first' if ClientShot.kitchen_roots(model).empty?

        data = SiteDocs.collect(model, proj, cfg)
        sv = SiteDocs.services(data)
        reply(op, { 'points' => sv['points'], 'orphans' => sv['orphans'] })
      when 'assist_open_dir'
        dir = msg['dir']
        ::UI.openURL("file:///#{dir}") if dir && File.directory?(dir)
      end
    end
  end
end
