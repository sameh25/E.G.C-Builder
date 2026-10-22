# frozen_string_literal: true

require 'cgi'

module EGC
  # Client quotation built from the model (prices come from the settings table).
  module Quote
    L = {
      'en' => { 'title' => 'Quotation', 'client' => 'Client', 'phone' => 'Phone', 'address' => 'Address', 'project' => 'Project',
                'date' => 'Date', 'valid' => 'Valid for (days)', 'code' => 'Code', 'desc' => 'Description', 'size' => 'Size (W×H×D mm)',
                'price' => 'Price', 'qty' => 'Qty', 'sub' => 'Subtotal', 'discount' => 'Discount', 'vat' => 'VAT', 'total' => 'Grand total',
                'terms' => 'Terms & conditions', 'base' => 'Base units', 'wall' => 'Wall units', 'tall' => 'Tall units',
                'ward' => 'Wardrobes', 'other' => 'Countertop, fascia & finishing', 'appl' => 'Appliances (supplied separately)',
                'sign' => 'Client signature', 'no' => 'No.', 'notes' => 'Notes' },
      'ar' => { 'title' => 'عرض سعر', 'client' => 'العميل', 'phone' => 'الهاتف', 'address' => 'العنوان', 'project' => 'المشروع',
                'date' => 'التاريخ', 'valid' => 'صلاحية العرض (يوم)', 'code' => 'الكود', 'desc' => 'البيان', 'size' => 'المقاس (عرض×ارتفاع×عمق مم)',
                'price' => 'السعر', 'qty' => 'الكمية', 'sub' => 'الإجمالي الفرعي', 'discount' => 'الخصم', 'vat' => 'ضريبة القيمة المضافة', 'total' => 'الإجمالي النهائي',
                'terms' => 'الشروط والأحكام', 'base' => 'وحدات سفلية', 'wall' => 'وحدات علوية', 'tall' => 'أبراج',
                'ward' => 'دواليب', 'other' => 'الرخام والستارة والتشطيبات', 'appl' => 'الأجهزة (توريد منفصل)',
                'sign' => 'توقيع العميل', 'no' => 'م', 'notes' => 'ملاحظات' }
    }.freeze

    module_function

    def h(s)
      CGI.escapeHTML(s.to_s)
    end

    def money(v)
      v.round.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
    end

    MECHANISM_PRICE_KEYS = %w[slide_pair undermount_slide slide_wheel lift_up basket basket_set spice_rack tray_rack waste_bin waste_bin_unit pantry_pullout pantry_fixed trolley box_unit wire_drawer laundry_bag plate_holder bifold_lift dish_rack cutlery_tray trouser_rack pulldown_rail slide_track_m].freeze

    def category_for_line(line)
      case line[:cat].to_s
      when 'board', 'edge' then :board # edge banding is part of the board materials for the client
      when 'worktop' then %w[glass splash].include?(line[:mat].to_s) ? :glass : :worktop
      when 'appliance' then :appliance
      when 'hw'
        key = line[:key].to_s
        return :hinges if key.start_with?('hinge')
        return :mechanisms if MECHANISM_PRICE_KEYS.include?(key)

        :hardware
      else :other
      end
    end

    # Client-facing wording: internal part / hardware keys never appear in the quotation.
    CLIENT_HW = {
      'en' => { 'leg' => 'Adjustable cabinet legs', 'plinth_clip' => 'Plinth fixing clips', 'plinth_m' => 'Plastic plinth profile', 'wall_hanger' => 'Wall cabinet hangers', 'shelf_pin' => 'Shelf supports',
                'appliance_front_bracket' => 'Appliance front fixings', 'profile_m' => 'Handle profile', 'led_m' => 'LED lighting strip', 'hinge' => 'Concealed hinges', 'hinge_bifold' => 'Bi-fold corner hinges', 'slide_pair' => 'Drawer runners',
                'lift_up' => 'Lift-up fittings', 'basket' => 'Pull-out wire baskets', 'basket_set' => 'Pull-out basket sets', 'waste_bin' => 'Waste bin', 'waste_bin_unit' => 'Waste bin pull-out',
                'spice_rack' => 'Spice pull-out', 'tray_rack' => 'Tray / bottle pull-out', 'pantry_pullout' => 'Pantry pull-out', 'handle' => 'Handles', 'push_opener' => 'Push-to-open openers', 'rod_m' => 'Hanging rail', 'rod_bracket' => 'Rail brackets' },
      'ar' => { 'leg' => 'أرجل ضبط للخزائن', 'plinth_clip' => 'مشابك تثبيت الوزرة', 'plinth_m' => 'وزرة بلاستيك', 'wall_hanger' => 'علاقات الوحدات العلوية', 'shelf_pin' => 'مساند الأرفف',
                'appliance_front_bracket' => 'تثبيت واجهة الأجهزة', 'profile_m' => 'بروفايل المقبض', 'led_m' => 'شريط إضاءة LED', 'hinge_bifold' => 'مفصلات بيفولد للركنة', 'hinge' => 'مفصلات مخفية', 'slide_pair' => 'مجاري الأدراج',
                'lift_up' => 'ميكانيزم رفع', 'basket' => 'سلال سحب سلك', 'basket_set' => 'أطقم سلال سحب', 'waste_bin' => 'سلة مهملات', 'waste_bin_unit' => 'سحب سلة مهملات',
                'spice_rack' => 'سحب بهارات', 'tray_rack' => 'سحب صواني / زجاجات', 'pantry_pullout' => 'مخزن سحب', 'handle' => 'مقابض', 'push_opener' => 'فتح بالضغط', 'rod_m' => 'ماسورة تعليق', 'rod_bracket' => 'حوامل الماسورة' }
    }.freeze

    CLIENT_APP = {
      'en' => { 'sink' => 'Kitchen sink', 'oven' => 'Built-in oven', 'hob' => 'Hob', 'hob_gas' => 'Gas hob', 'hood' => 'Cooker hood', 'hood_chimney' => 'Chimney hood', 'hood_slim' => 'Slim hood',
                'dishwasher' => 'Dishwasher', 'washer' => 'Washing machine', 'dryer' => 'Dryer', 'fridge' => 'Refrigerator', 'freezer' => 'Freezer', 'microwave' => 'Microwave oven',
                'coffee' => 'Coffee machine', 'wine_cooler' => 'Wine cooler', 'warming' => 'Warming drawer' },
      'ar' => { 'sink' => 'حوض المطبخ', 'oven' => 'فرن مدمج', 'hob' => 'موقد', 'hob_gas' => 'موقد غاز', 'hood' => 'شفاط', 'hood_chimney' => 'شفاط مدخنة', 'hood_slim' => 'شفاط رفيع',
                'dishwasher' => 'غسالة أطباق', 'washer' => 'غسالة ملابس', 'dryer' => 'نشافة', 'fridge' => 'ثلاجة', 'freezer' => 'فريزر', 'microwave' => 'ميكروويف',
                'coffee' => 'ماكينة قهوة', 'wine_cooler' => 'مبرد نبيذ', 'warming' => 'درج تدفئة' }
    }.freeze

    def client_name(line, lang)
      if line[:cat].to_s == 'appliance'
        kind = line[:item].to_s.sub(/\AAppliance:\s*/, '')
        return (CLIENT_APP[lang] || CLIENT_APP['en'])[kind] || kind.tr('_', ' ').capitalize
      end
      return line[:item] unless line[:cat].to_s == 'hw'

      (CLIENT_HW[lang] || CLIENT_HW['en'])[line[:key].to_s] || line[:key].to_s.tr('_', ' ').capitalize
    end

    def client_qty(line)
      line[:cat].to_s == 'hw' && line[:key].to_s.end_with?('_m') ? line[:qty].to_f.round(1) : (line[:cat].to_s == 'hw' ? line[:qty].to_f.round : line[:qty])
    end

    AR_UNITS = { 'sheet' => 'لوح', 'sheets' => 'لوح', 'm' => 'م', 'm²' => 'م²', 'pcs' => 'قطعة', 'pc' => 'قطعة', 'm² (unpriced)' => 'م² (بدون سعر)' }.freeze

    def client_unit(line, lang)
      return (lang == 'ar' ? AR_UNITS[line[:unit].to_s] || line[:unit] : line[:unit]) unless line[:cat].to_s == 'hw'

      line[:key].to_s.end_with?('_m') ? 'm' : (lang == 'ar' ? 'قطعة' : 'pcs')
    end

    def category_for_extra(name)
      return :installation if name.to_s.match?(/install/i)
      return :transport if name.to_s.match?(/transport/i)
      return :services if name.to_s.match?(/manufact|labou?r/i)

      :other
    end

    # out: Cutlist.analyse result. client: hash with name/phone/address/project/notes/margin_pct/vat_pct/discount_pct/valid_days/terms
    def html(out, client, cfg, lang = 'en')
      l = L[lang] || L['en']
      cur = cfg['currency']
      internal = Costing.internal(out, cfg, lang)
      margin = client['margin_pct'].to_f
      vat = client['vat_pct'].to_f
      disc = client['discount_pct'].to_f
      labels = if lang == 'ar'
                 { board: 'ألواح الخزائن / الخشب', worktop: 'الرخام / سطح العمل', glass: 'الزجاج / الكسوة', appliance: 'الأجهزة', hinges: 'المفصلات', mechanisms: 'الميكانيزمات', hardware: 'الهاردوير', services: 'التصنيع والخدمات', installation: 'التركيب', transport: 'النقل', other: 'تكاليف أخرى' }
               else
                 { board: 'Cabinet boards / wood materials', worktop: 'Worktop / stone', glass: 'Glass / backsplash', appliance: 'Appliances', hinges: 'Hinges', mechanisms: 'Mechanisms', hardware: 'Hardware', services: 'Manufacturing / services', installation: 'Installation', transport: 'Transport', other: 'Other costs' }
               end
      groups = Hash.new { |hh, k| hh[k] = [] }
      internal[:lines].each do |line|
        groups[category_for_line(line)] << { item: client_name(line, lang), qty: client_qty(line), unit: client_unit(line, lang), cost: line[:amount].to_f, missing: line[:status] == 'MISSING_PRICE' }
      end
      internal[:extra].each do |extra|
        groups[category_for_extra(extra['name'])] << { item: extra['name'], qty: '-', unit: '', cost: extra['amount'].to_f, missing: extra['status'] != 'SET' } # cost basis (percent / fixed) is internal
      end
      groups[:services] << { item: (lang == 'ar' ? 'مصنعية' : 'Labour'), qty: '-', unit: '', cost: internal[:labor].to_f, missing: false } if internal[:labor].to_f.positive?
      order = %i[board hardware mechanisms appliance worktop glass services installation transport other hinges]
      subtotal = internal[:total].to_f * (1 + margin / 100.0)
      groups.each_value { |list| list.each { |r| r[:price] = r[:cost] * (1 + margin / 100.0) } }
      discount = subtotal * disc / 100.0
      net = subtotal - discount
      vat_amt = net * vat / 100.0
      grand = net + vat_amt
      co = cfg['company'] || {}
      dir = lang == 'ar' ? 'rtl' : 'ltr'
      s = +"<!doctype html><html lang='#{lang}' dir='#{dir}'><head><meta charset='utf-8'><title>#{h(l['title'])}</title><style>"
      s << CSS
      s << "</style></head><body><div class='wrap'>"
      pricing_status = Costing.internal(out, cfg, lang)
      s << Costing.incomplete_banner(pricing_status, lang)
      s << "<header><div><div class='brand'>#{h(co['name'].to_s.empty? ? 'E.G.C' : co['name'])}</div><div class='sub'>#{h(co['phone'])} #{h(co['address'])}</div></div>"
      s << "<div><h1>#{h(l['title'])}</h1><div class='sub'>#{h(l['date'])}: #{Time.now.strftime('%Y-%m-%d')} · #{h(l['valid'])}: #{h(client['valid_days'] || 15)}</div></div></header>"
      s << "<section class='meta'><div><b>#{h(l['client'])}:</b> #{h(client['name'])}</div><div><b>#{h(l['phone'])}:</b> #{h(client['phone'])}</div>"
      s << "<div><b>#{h(l['address'])}:</b> #{h(client['address'])}</div><div><b>#{h(l['project'])}:</b> #{h(client['project'])}</div></section>"
      n = 0
      order.each do |g|
        list = groups[g]
        next if list.nil? || list.empty?

        s << "<h2>#{h(labels[g])}</h2><table><tr><th>#{h(l['no'])}</th><th>#{h(l['desc'])}</th><th>#{h(l['qty'])}</th><th>#{h(l['price'])} (#{h(cur)})</th></tr>"
        list.each do |r|
          n += 1
          qty = "#{r[:qty]} #{r[:unit]}"
          amount = r[:missing] ? (lang == 'ar' ? 'سعر مطلوب' : 'PRICE REQUIRED') : money(r[:price])
          s << "<tr><td>#{n}</td><td>#{h(r[:item])}#{r[:missing] ? " <b class='missing'>#{lang == 'ar' ? 'سعر مطلوب' : 'MISSING PRICE'}</b>" : ''}</td><td>#{h(qty)}</td><td class='n'>#{amount}</td></tr>"
        end
        s << '</table>'
      end
      if pricing_status[:complete]
        s << "<table class='tot'><tr><td>#{h(l['sub'])}</td><td class='n'>#{money(subtotal)} #{h(cur)}</td></tr>"
        s << "<tr><td>#{h(l['discount'])} (#{disc.round(1)}%)</td><td class='n'>- #{money(discount)}</td></tr>" if disc > 0
        s << "<tr><td>#{h(l['vat'])} (#{vat.round(1)}%)</td><td class='n'>#{money(vat_amt)}</td></tr>" if vat > 0
        s << "<tr class='g'><td>#{h(l['total'])}</td><td class='n'>#{money(grand)} #{h(cur)}</td></tr></table>"
      else
        s << "<table class='tot'><tr class='g'><td>#{lang == 'ar' ? 'العرض غير مكتمل - لا تعتمد سعراً نهائياً' : 'QUOTATION INCOMPLETE - FINAL PRICE WITHHELD'}</td><td class='n'>#{lang == 'ar' ? 'أدخل الأسعار المفقودة' : 'MISSING PRICES'}</td></tr></table>"
      end
      s << "<h2>#{h(l['notes'])}</h2><p>#{h(client['notes'])}</p>" unless client['notes'].to_s.empty?
      s << "<h2>#{h(l['terms'])}</h2><p class='sub'>#{h(client['terms'])}</p>" unless client['terms'].to_s.empty?
      s << "<div class='sig'>#{h(l['sign'])}: ____________________</div></div></body></html>"
      { html: s, subtotal: subtotal, discount: discount, vat: vat_amt, total: grand, incomplete: !pricing_status[:complete] }
    end

    CSS = <<~CSS
      :root{--ink:#1c1f24;--mut:#6b7280;--line:#e5e7eb;--acc:#b8862b}
      *{box-sizing:border-box}body{margin:0;background:#fafaf7;color:var(--ink);font:14px/1.5 "Segoe UI",Tahoma,Arial,sans-serif}
      .wrap{max-width:900px;margin:0 auto;padding:28px 22px}
      header{display:flex;justify-content:space-between;align-items:flex-end;border-bottom:3px solid var(--acc);padding-bottom:12px;margin-bottom:14px}
      .brand{font-size:22px;font-weight:700;letter-spacing:.08em;color:var(--acc)}h1{margin:0;font-size:24px}.sub{color:var(--mut);font-size:12px}
      .meta{display:grid;grid-template-columns:1fr 1fr;gap:4px 18px;background:#fff;border:1px solid var(--line);border-radius:10px;padding:10px 14px;margin-bottom:10px}
      h2{margin:18px 0 6px;font-size:16px;border-inline-start:4px solid var(--acc);padding-inline-start:10px}
      table{width:100%;border-collapse:collapse;background:#fff;border:1px solid var(--line);font-size:13px}
      th,td{padding:6px 10px;border-bottom:1px solid var(--line);text-align:start}th{background:#f3efe4}td.n{text-align:end;font-variant-numeric:tabular-nums}
      table.tot{margin-top:14px;max-width:420px;margin-inline-start:auto}table.tot tr.g td{font-weight:700;font-size:16px;background:#f3efe4}
      .sig{margin-top:40px;color:var(--mut)}.missing{color:#b42318;font-size:11px}@media print{body{background:#fff}.wrap{padding:0}}
    CSS
  end
end
