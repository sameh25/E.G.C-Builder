# frozen_string_literal: true

require 'cgi'

module EGC
  # Phase 1 sheets consume the same SiteDocs/Cutlist extraction used by SitePack.
  module Phase1Docs
    module_function

    def h(s)
      CGI.escapeHTML(s.to_s)
    end

    def badge(status, lang)
      names = { 'CONFIRMED' => 'مؤكد', 'INFERRED' => 'مستنتج', 'REQUIRES_CONFIRMATION' => 'يتطلب التأكيد', 'MISSING_DATA' => 'بيانات ناقصة' }
      label = lang == 'ar' ? (names[status.to_s] || status.to_s) : status.to_s
      { html: "<span class='st #{status.to_s.gsub(/\W/, '_')}'>#{h(label)}</span>" }
    end

    def service_code(kind)
      { 'elec' => 'E', 'water_cold' => 'CW', 'water_hot' => 'HW', 'drain' => 'D', 'gas' => 'G', 'duct' => 'DU', 'led' => 'LED' }[kind.to_s] || kind.to_s
    end

    def kitchen_elevations(data, lang, st, identify: false)
      ar = lang == 'ar'
      sheets = SiteDocs.used_walls(data).map do |wall|
        ceiling = (data[:proj].dig('room', 'ceiling', 'v') || data[:cfg]['ceiling']).to_f
        cv = SvgDraw::Canvas.new(0, 0, wall['len'], ceiling, pad: 700)
        cv.rect(0, 0, wall['len'], ceiling, fill: '#fff', stroke: '#555')
        cv.line(-200, 0, wall['len'] + 200, 0, stroke: '#111', sw: cv.fs / 9.0)
        units = data[:units].select { |u| u['wall'] == wall['id'] && u['along'] }
        units.each do |u|
          a, b = u['along']
          z0 = u['z0'].to_f
          cv.rect(a, z0, b, z0 + u['h'].to_f, fill: u['kind'] == 'base' ? '#efe3c6' : '#e4e1d5', stroke: '#333', sw: cv.fs / 18.0)
          # label fitted to the unit width (two/three short lines, never wider than the unit) so narrow units do not collide
          cx = (a + b) / 2.0
          cz = z0 + u['h'].to_f / 2.0
          fit = ->(str, mx) { [mx, (b - a).abs * 0.9 / ([str.to_s.length, 1].max * 0.6)].min }
          if identify
            cv.text(cx, cz, u['code'].to_s, size: fit.call(u['code'], cv.fs * 0.9), bold: true)
          else
            dims = "#{u['w'].round}x#{u['h'].round}x#{u['d'].round}"
            cv.text(cx, cz + cv.fs * 0.55, u['code'].to_s, size: fit.call(u['code'], cv.fs * 0.6), bold: true)
            cv.text(cx, cz - cv.fs * 0.05, u['type'].to_s, size: fit.call(u['type'], cv.fs * 0.42))
            cv.text(cx, cz - cv.fs * 0.6, dims, size: fit.call(dims, cv.fs * 0.42))
          end
          u['apps'].each do |ap|
            x = SiteDocs.along_of(wall, ap['center'])
            lo, hi = ap['z'] || [ap['center'][2] - 50, ap['center'][2] + 50]
            cv.rect(x - u['w'].to_f * 0.18, lo.to_f, x + u['w'].to_f * 0.18, hi.to_f, fill: '#454a50', stroke: '#111')
            cv.text(x, (lo.to_f + hi.to_f) / 2.0, identify ? (ap['dev'] || ap['kind']) : ap['kind'], size: cv.fs * 0.42, fill: '#fff')
          end
        end
        SiteDocs.each_part(data[:model], %w[countertop fascia filler end_panel], data[:walls]).each do |p|
          next unless p[:pts] && p[:pts].any?
          al = p[:pts].map { |q| (q.x.to_mm - wall['p0'][0]) * wall['dir'][0] + (q.y.to_mm - wall['p0'][1]) * wall['dir'][1] }
          next if al.max < 0 || al.min > wall['len']
          cv.rect(al.min, p[:z][0], al.max, p[:z][1], fill: p[:part] == 'countertop' ? '#333' : '#d7c69f', stroke: '#111')
        end
        unless identify
          run_lo = units.map { |u| u['along'][0] }.min || 0
          run_hi = units.map { |u| u['along'][1] }.max || wall['len']
          cv.dim(run_lo, 0, run_hi, 0, -cv.fs * 2.2, "#{ar ? 'عرض المطبخ' : 'KITCHEN'} #{(run_hi - run_lo).round} mm")
          cv.dim(0, 0, 0, ceiling, cv.fs * 3.2, "#{ceiling.round} mm")
          cfg = data[:cfg]
          levels = [[ar ? 'أعلى الرخامة' : 'Worktop top', cfg['base_h'].to_f], [ar ? 'أسفل العلوي 1' : 'Upper 1 bottom', cfg['base_h'].to_f + cfg['gap_h'].to_f], [ar ? 'أعلى العلوي 1' : 'Upper 1 top', cfg['base_h'].to_f + cfg['gap_h'].to_f + cfg['w1_h'].to_f]]
          levels << [ar ? 'أعلى العلوي 2' : 'Upper 2 top', cfg['base_h'].to_f + cfg['gap_h'].to_f + cfg['w1_h'].to_f + cfg['w2_h'].to_f] if cfg['w2_enabled']
          levels.each { |label, z| cv.line(0, z, wall['len'], z, stroke: '#aaa', sw: cv.fs / 45.0, dash: '30 18'); cv.text(wall['len'] + cv.fs * 0.3, z, "#{label} #{z.round}", anchor: 'start', size: cv.fs * 0.43, fill: '#555') }
          cv.text(0, -cv.fs * 4.6, 'FFL ±0.00', anchor: 'start', size: cv.fs * 0.65)
        end
        body = "<div class='draw'>#{cv.svg}</div>#{SiteDocs.reference_notes(data)}"
        body << "<div class='warn'>#{ar ? 'المرجع الأفقي بداية الحائط؛ المحاور المستنتجة تتطلب تأكيد الموقع.' : 'Horizontal datum: wall start. Inferred cabinet reference lines require site confirmation.'}</div>" if wall['reference_only']
        title = if ar
                  identify ? "تعريف الوحدات — #{wall['id']}" : "المطبخ العام — #{wall['id']}"
                else
                  identify ? "UNIT IDENTIFICATION — #{wall['id']}" : "GENERAL KITCHEN ELEVATION — #{wall['id']}"
                end
        SvgDraw.sheet(data[:proj], title: title, sheet_no: identify ? "K-02-#{wall['id']}" : "K-01-#{wall['id']}", scale: 'NTS (dimensions mm)', zone: wall['id'], status: st[:status], lang: lang, extra_status: st[:doc], body: body)
      end
      sheets
    end

    def services_elevations(data, kinds, lang, st, title_en, title_ar, number)
      ar = lang == 'ar'
      sv = SiteDocs.services(data)
      points = sv['points'].select { |p| kinds.include?(p['kind']) }
      sheets = SiteDocs.used_walls(data).map do |wall|
        ceiling = (data[:proj].dig('room', 'ceiling', 'v') || data[:cfg]['ceiling']).to_f
        cv = SvgDraw::Canvas.new(0, 0, wall['len'], ceiling, pad: 850)
        cv.rect(0, 0, wall['len'], ceiling, fill: '#fff', stroke: '#555')
        cv.line(-200, 0, wall['len'] + 200, 0, stroke: '#111', sw: cv.fs / 9.0)
        data[:units].select { |u| u['wall'] == wall['id'] && u['along'] }.each do |u|
          a, b = u['along']; cv.rect(a, u['z0'], b, u['z0'] + u['h'].to_f, fill: '#f2efe7', stroke: '#777')
          cv.text((a + b) / 2.0, u['z0'] + u['h'].to_f / 2.0, u['code'], size: cv.fs * 0.45)
          u['apps'].each do |ap|
            x = SiteDocs.along_of(wall, ap['center']); lo, hi = ap['z'] || [ap['center'][2] - 50, ap['center'][2] + 50]
            cv.rect(x - u['w'].to_f * 0.16, lo.to_f, x + u['w'].to_f * 0.16, hi.to_f, fill: '#454a50', stroke: '#111')
            cv.text(x, (lo.to_f + hi.to_f) / 2.0, ap['kind'], size: cv.fs * 0.38, fill: '#fff')
          end
        end
        here = points.select { |p| p['wall'] == wall['id'] }
        here.each_with_index do |p, i|
          color = p['st'] == 'CONFIRMED' && !wall['reference_only'] ? '#177245' : '#b42318'
          cv.circle(p['off'].to_f, p['z'].to_f, cv.fs * 0.34, fill: '#fff', stroke: color, sw: cv.fs / 18.0)
          cv.text(p['off'].to_f, p['z'].to_f + cv.fs * 0.55, p['id'], size: cv.fs * 0.55, fill: color, bold: true)
          cv.dim(0, 0, p['off'].to_f, 0, -cv.fs * (1.7 + (i % 3) * 0.8), "X #{p['off'].round}", color: color) if p['off'].to_f > 0
          cv.dim(p['off'].to_f, 0, p['off'].to_f, p['z'].to_f, cv.fs * (0.7 + (i % 2) * 0.3), "Z #{p['z'].round}", color: color) if p['z'].to_f > 0
        end
        cv.text(0, -cv.fs * 4.2, ar ? 'X من بداية الحائط (مم) · Z من FFL ±0.00 (مم)' : 'X from wall start (mm) · Z above FFL ±0.00 (mm)', anchor: 'start', size: cv.fs * 0.58)
        body = "<div class='draw'>#{cv.svg}</div>"
        body << "<div class='warn'>#{ar ? 'FFL = منسوب SketchUp Z=0؛ يلزم تأكيد مطابقته للأرضية النهائية.' : 'FFL is model Z=0; confirm it matches the finished floor level.'}</div>"
        body << "<div class='warn'>#{ar ? 'المحور R مستنتج من ظهور الخزائن وليس حائط موقع مقاس.' : 'R reference is inferred from cabinet backs, not a measured site wall.'}</div>" if wall['reference_only']
        rows = here.map do |p|
          [p['id'], service_code(p['kind']), p['label'], p['unit'], wall['id'], p['off'].round, p['z'].round, p['spec'] || 'REQUIRES_CONFIRMATION', badge(p['st'], lang), p['src']]
        end
        headers = ar ? %w[المعرف النوع الجهاز الوحدة الحائط X_مم Z_مم المواصفة الحالة المصدر] : %w[Service_ID Type Device Unit Wall X_mm_Z0 Z_mm_FFL Specification Status Source]
        body << SvgDraw.data_table(headers, rows)
        body << "<div class='note'>#{ar ? 'المواصفات غير المتاحة لم تُفترض. المواقع المقترحة تتطلب مراجعة ميدانية.' : 'Unknown ratings, pipe sizes and installation requirements are not inferred; proposed locations require site review.'}</div>"
        title = ar ? "#{title_ar} — #{wall['id']}" : "#{title_en} — #{wall['id']}"
        SvgDraw.sheet(data[:proj], title: title, sheet_no: "#{number}-#{wall['id']}", scale: 'NTS (dimensions mm)', zone: wall['id'], status: st[:status], lang: lang, extra_status: st[:doc], body: body)
      end
      sheets
    end

    def appliance_schedule(data, lang, st)
      ar = lang == 'ar'; sv = SiteDocs.services(data); seq = 0
      rows = data[:units].flat_map do |u|
        u['apps'].map do |ap|
          seq += 1
          opening = ap['opening']
          service_ids = sv['points'].select { |p| p['unit'] == u['code'] && p['device_kind'] == ap['kind'] }.map { |p| p['id'] }.join(', ')
          profile = ap['profile'] || {}
          [format('AP%02d', seq), ap['dev'] || ap['kind'], (ar ? ap['dev_name_ar'] : ap['dev_name']) || ap['kind'], u['code'], u['wall'] || (ar ? 'لا يوجد مرجع حائط' : 'NO WALL DATUM'),
           opening ? [opening['w'], opening['h'], opening['d']].compact.map(&:round).join('×') : '-',
           (ap['dev'] && Catalog.device(ap['dev']) ? [Catalog.device(ap['dev'])[:w], Catalog.device(ap['dev'])[:h], Catalog.device(ap['dev'])[:d]].join('×') : 'MISSING_DATA'),
           [profile['manufacturer'], profile['model']].compact.reject(&:empty?).join(' / ').then { |x| x.empty? ? 'MISSING_DATA' : x },
           service_ids.empty? ? 'NONE / CHECK' : service_ids, badge(ap['dev_src'] == 'spec' ? 'MODELED' : 'INFERRED', lang), profile['data_status'] || 'REQUIRES_CONFIRMATION']
        end
      end
      heads = ar ? ['معرف الجهاز','النوع/الكود','الجهاز','الوحدة','الحائط','فتحة W×H×D','المقاس الاسمي W×H×D','الشركة / الموديل','معرفات الخدمة','مصدر الموديل','حالة البيانات الفنية'] : ['Appliance ID','Type / code','Device','Unit ID','Wall datum','Opening W×H×D mm','Nominal W×H×D mm','Manufacturer / model','Service IDs','Model source','Technical data status']
      body = SvgDraw.data_table(heads, rows)
      body << "<div class='warn'>#{ar ? 'المقاس الاسمي أو متطلبات المصنع غير المتوفرة: REQUIRES_CONFIRMATION.' : 'Unknown nominal data or manufacturer installation requirements: REQUIRES_CONFIRMATION.'}</div>"
      SvgDraw.sheet(data[:proj], title: ar ? 'جدول الأجهزة والخدمات' : 'APPLIANCE / SERVICE SCHEDULE', sheet_no: 'A-01', scale: 'NTS', zone: 'ALL', status: st[:status], lang: lang, extra_status: st[:doc], body: body)
    end

    # Back groove section detail: rear edge of the side panel, 5 mm offset, 10 mm deep groove, back panel engagement (all from project settings).
    def back_groove_detail_svg(cfg, cap)
      off = (cfg['back_groove_offset'] || 5).to_f
      depth = (cfg['back_groove_depth'] || 10).to_f
      bt = cfg['back_thk'].to_f
      gw = bt + (cfg['back_clearance'] || 0).to_f
      th = cfg['thk'].to_f
      sc = 7.0
      w = 300
      hh = 230
      ox = 60
      oy = 30
      px = ->(v) { (ox + v * sc).round(1) }
      py = ->(v) { (oy + v * sc).round(1) }
      sv = +"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 #{w} #{hh}' width='#{w}' height='#{hh}' class='v' style='font-family:Segoe UI,Arial;font-size:9px'>"
      # side panel (thickness th across x, rear edge at y=0); groove cut into the inner face (x = th)
      sv << "<polygon points='#{px.call(0)},#{py.call(0)} #{px.call(th)},#{py.call(0)} #{px.call(th)},#{py.call(off)} #{px.call(th - depth)},#{py.call(off)} #{px.call(th - depth)},#{py.call(off + gw)} #{px.call(th)},#{py.call(off + gw)} #{px.call(th)},#{py.call(26)} #{px.call(0)},#{py.call(26)}' fill='#efe3c6' stroke='#333' stroke-width='1'/>"
      # back panel engaged in the groove (runs across the carcass, +x)
      sv << "<rect x='#{px.call(th - depth)}' y='#{py.call(off)}' width='#{(150).round(1)}' height='#{(bt * sc).round(1)}' fill='#d9d2c0' stroke='#333' stroke-width='1'/>"
      dim = lambda do |x1, y1, x2, y2, label, tx, ty|
        "<line x1='#{x1}' y1='#{y1}' x2='#{x2}' y2='#{y2}' stroke='#b42318' stroke-width='0.8'/><text x='#{tx}' y='#{ty}' fill='#b42318'>#{label}</text>"
      end
      sv << dim.call(px.call(-1.5), py.call(0), px.call(-1.5), py.call(off), "#{off.round(1)}", px.call(-4.2), py.call(off / 2 + 0.6))
      sv << dim.call(px.call(th - depth), py.call(off + gw + 2), px.call(th), py.call(off + gw + 2), "#{depth.round(1)}", px.call(th - depth), py.call(off + gw + 3.8))
      sv << dim.call(px.call(th + 1.5), py.call(off), px.call(th + 1.5), py.call(off + gw), "#{gw.round(1)}", px.call(th + 2.2), py.call(off + gw / 2 + 0.6))
      sv << dim.call(px.call(0), py.call(-1.5), px.call(th), py.call(-1.5), "#{th.round(1)}", px.call(th / 2 - 1), py.call(-2.2))
      sv << "<text x='#{px.call(0) - 52}' y='#{py.call(0) - 14}' font-weight='700'>#{cap.call('REAR EDGE', 'الحافة الخلفية')}</text>"
      sv << "<text x='#{px.call(th) + 14}' y='#{py.call(off + 10)}'>#{cap.call('BACK', 'الظهر')} #{bt.round(1)}</text>"
      sv << '</svg>'
      sv
    end

    def representative_unit(data, groups, cfg, lang, st, group: nil, sheet_no: 'K-03')
      g = group || groups.find { |x| x.get_attribute('egc', 'spec') }
      return SvgDraw.sheet(data[:proj], title: lang == 'ar' ? 'تفصيل وحدة ممثلة' : 'REPRESENTATIVE UNIT DETAIL', sheet_no: 'K-03', status: st[:status], lang: lang, extra_status: st[:doc], body: "<div class='warn'>#{lang == 'ar' ? 'لا توجد وحدة خزانة قابلة للتفصيل في الموديل.' : 'No cabinet unit is available for a detail sheet.'}</div>") unless g

      bs = Drawings.boxes(g.entities.to_a)
      spec = (JSON.parse(g.get_attribute('egc', 'spec').to_s) rescue {})
      d = g.attribute_dictionary('egc') || {}
      parts = bs.select { |b| %w[part glass].include?(b[:role]) }.sort_by { |b| b[:pid].to_s }
      rows = parts.map { |b| [b[:pid], I18n.part(b[:part], lang), b[:len], b[:wid], b[:thk], cfg['mat_names'][b[:mat]] || b[:mat], "L#{b[:eb_l]} / W#{b[:eb_w]}", [b[:groove], b[:notes]].compact.join(' ')] }
      heads = lang == 'ar' ? %w[معرف_القطعة الجزء الطول العرض السمك الخامة الحواف ملاحظات] : %w[Part_ID Part Length Width Thickness Material Edges Groove_or_notes]
      meta = [
        [lang == 'ar' ? 'الوحدة / النوع' : 'Unit / type', "#{d['code']} / #{d['type'] || d['kind']}", lang == 'ar' ? 'الأبعاد W×H×D (مم)' : 'W×H×D (mm)', [d['w'], d['h'], d['d']].map { |v| v.to_f.round }.join(' × ')],
        [lang == 'ar' ? 'السماكات الهيكل / الظهر' : 'Carcass / back thickness', "#{cfg['thk']} / #{cfg['back_thk']} mm", lang == 'ar' ? 'الآلية' : 'Mechanism', d['mech'].to_s.empty? ? '-' : d['mech']],
        [lang == 'ar' ? 'عدد التقسيمات' : 'Internal cells', Array(spec['cells']).size, lang == 'ar' ? 'الأجهزة/الفتحات' : 'Appliances / openings', SiteDocs.collect(data[:model], data[:proj], cfg)[:units].find { |u| u['code'] == d['code'] }.to_a[0].to_s],
        [lang == 'ar' ? 'تركيب الظهر' : 'Back construction', (Config.back_groove_ready?(cfg) ? (lang == 'ar' ? 'ظهر داخل مجرى: عمق 10 مم وإزاحة 5 مم؛ مطبق على الجوانب غير المفتوحة' : 'Inset back in side grooves: 10 mm depth, 5 mm offset; applied to closed carcass sides') : (lang == 'ar' ? 'يتطلب معلمة إنشائية' : 'REQUIRES CONSTRUCTION PARAMETER')), lang == 'ar' ? 'تصنيع المجرى' : 'Groove machining', (Config.back_groove_ready?(cfg) ? (lang == 'ar' ? 'هندسة المجرى موجودة؛ تحقق من اتجاه التصنيع قبل CNC' : 'GROOVE MODELED; CNC orientation requires validation') : (lang == 'ar' ? 'يتطلب معلمة إنشائية' : Config.back_groove_status(cfg)))]
      ]
      meta[2][3] = data[:units].select { |u| u['code'] == d['code'] }.flat_map { |u| u['apps'].map { |a| "#{a['kind']} #{a['opening'] && a['opening']['w']}×#{a['opening'] && a['opening']['h']}" } }.join(', ')
      ar = lang == 'ar'
      cap = ->(en, a2) { ar ? a2 : en }
      has_groove = parts.any? { |b| b[:groove].to_s.include?('groove') || b[:notes].to_s.include?('groove') }
      left = "<div class='ud-l'><div class='views'><figure>#{Drawings.view_svg(bs, :front, cfg, 330)}<figcaption>#{cap.call('Front', 'واجهة')}</figcaption></figure>" \
             "<figure>#{Drawings.view_svg(bs, :side, cfg, 260)}<figcaption>#{cap.call('Side section view', 'جانب')}</figcaption></figure>" \
             "<figure>#{Drawings.view_svg(bs, :plan, cfg, 260)}<figcaption>#{cap.call('Plan', 'مسقط')}</figcaption></figure>" \
             "#{has_groove ? "<figure>#{back_groove_detail_svg(cfg, cap)}<figcaption>#{cap.call('DETAIL - back groove (plan section at side panel)', 'تفصيل مجرى الظهر')}</figcaption></figure>" : ''}</div></div>"
      right = +"<div class='ud-r'>"
      right << SvgDraw.data_table([cap.call('Unit data', 'البند'), cap.call('Value', 'القيمة'), cap.call('Construction', 'البند'), cap.call('Value', 'القيمة')], meta)
      right << SvgDraw.data_table(heads, rows)
      dr = Drawings.drilling_rows(bs)
      right << SvgDraw.data_table(%w[Part Type Diameter_Depth Qty Positions_mm], dr) unless dr.empty?
      right << "<div class='note'>#{cap.call('Hinge, runner and mechanism drilling is not issued: REQUIRES HINGE / MECHANISM SPECIFICATION.', 'ثقوب المفصلات والمجاري والميكانيزم غير صادرة: تتطلب مواصفة')}</div></div>"
      body = left + right + "<div style='clear:both'></div>"
      SvgDraw.sheet(data[:proj], title: lang == 'ar' ? 'تفصيل وحدة ممثلة — بيانات الموديل' : 'REPRESENTATIVE UNIT DETAIL — MODEL DATA', sheet_no: 'K-03', scale: 'NTS (dimensions mm)', zone: d['code'].to_s, status: st[:status], lang: lang, extra_status: st[:doc], body: body)
    end

    def outputs(data, groups, cfg, lang, st)
      {
        'K-01_general_elevation.html' => SvgDraw.page('K-01', kitchen_elevations(data, lang, st), lang),
        'K-02_unit_identification.html' => SvgDraw.page('K-02', kitchen_elevations(data, lang, st, identify: true), lang),
        'K-03_representative_unit.html' => SvgDraw.page('K-03', [representative_unit(data, groups, cfg, lang, st)], lang),
        'E-01_electrical_services.html' => SvgDraw.page('E-01', services_elevations(data, %w[elec led], lang, st, 'ELECTRICAL SERVICES ELEVATION', 'واجهة الخدمات الكهربائية', 'E-01'), lang),
        'P-01_plumbing_drain.html' => SvgDraw.page('P-01', services_elevations(data, %w[water_cold water_hot drain], lang, st, 'PLUMBING & DRAINAGE ELEVATION', 'واجهة المياه والصرف', 'P-01'), lang),
        'A-01_appliance_service_schedule.html' => SvgDraw.page('A-01', [appliance_schedule(data, lang, st)], lang)
      }
    end
  end

  # Keep the shared title block authoritative and add the chosen presentation language to every sheet.
  module SvgDraw
    class << self
      alias_method :phase1_original_sheet, :sheet unless method_defined?(:phase1_original_sheet)

      def sheet(proj, title:, sheet_no:, scale: 'NTS', zone: '-', status: 'DRAFT', body:, lang: 'en', extra_status: nil)
        html = phase1_original_sheet(proj, title: title, sheet_no: sheet_no, scale: scale, zone: zone, status: status, body: body, lang: lang, extra_status: extra_status)
        ar = lang == 'ar'
        row = "<tr><td class='k'>#{ar ? 'لغة الرسم' : 'Language'}</td><td>#{ar ? 'العربية RTL' : 'English LTR'}</td></tr>"
        html.sub!('</table></section>', row + '</table></section>')
        labels = { 'DRAFT' => 'مسودة', 'FOR REVIEW' => 'للمراجعة', 'APPROVED' => 'معتمد', 'FOR PRODUCTION' => 'للتصنيع', 'AS BUILT' => 'حسب التنفيذ', 'ISSUED FOR CONSTRUCTION' => 'صادر للتنفيذ', 'CONFIRMED' => 'مؤكد', 'INFERRED' => 'مستنتج', 'REQUIRES_CONFIRMATION' => 'يتطلب التأكيد', 'MISSING_DATA' => 'بيانات ناقصة', 'CURRENT' => 'حالي' }
        html.sub!(">#{h(status)}</span>", ">#{h(ar ? (labels[status.to_s] || status) : status)}</span>")
        html.sub!(">#{h(extra_status)}</span>", ">#{h(ar ? (labels[extra_status.to_s] || extra_status) : extra_status)}</span>") if extra_status
        html
      end
    end
  end
end
