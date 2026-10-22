# frozen_string_literal: true

require 'json'
require 'cgi'

module EGC
  # MATERIAL TAKEOFF + INTERNAL COST + CUSTOMER QUOTE - all read from the SAME production analysis (Cutlist.analyse: real parts of the 3D model, real
  # nesting, real hardware). No second quantity engine: boards are the SHEETS the nesting really needs (with kerf / trim / waste), not theoretical m2.
  # A price that is not known is reported as MISSING PRICE - it is never hidden inside a total.
  module Costing
    module_function

    def h(s)
      CGI.escapeHTML(s.to_s)
    end


    def fmt(v)
      format('%.2f', v.to_f).reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
    end

    def incomplete_banner(cost, lang = 'en')
      return '' if cost[:complete]

      title = lang == 'ar' ? 'التكلفة غير مكتملة — أسعار أو بيانات تصنيع ناقصة' : 'INCOMPLETE COST — missing prices or unresolved manufacturing data'
      details = (cost[:missing] || []).map { |m| "#{h(m['item'])}: #{h(m['reason'])}" }.join('<br>')
      "<div style='background:#fde0dc;color:#b42318;padding:10px;margin:10px 0'><b>#{title}</b><br>#{details}</div>"
    end

    APP_KINDS = %w[fridge oven microwave hob hob_gas hood hood_chimney hood_slim dishwasher washer dryer coffee wine_cooler warming sink freezer wall_rail].freeze

    # ------------------------------------------------------------------ takeoff
    def takeoff(an, cfg, lang = 'en')
      names = cfg['mat_names'] || {}
      boards = an[:nest].map do |(mat, thk), n|
        net = n[:used]
        { 'material' => names[mat] || mat, 'key' => mat, 'category' => 'board', 'thk' => thk, 'net_m2' => net.round(3), 'sheet' => n[:sheet].map(&:round), 'sheets' => n[:sheets].size,
          'sheet_m2' => (n[:sheet][0] * n[:sheet][1] / 1_000_000.0).round(3), 'gross_m2' => n[:total].round(3), 'waste_m2' => (n[:total] - net).round(3), 'waste_pct' => n[:waste].round(1),
          'kerf' => cfg['kerf'], 'trim' => cfg['trim'], 'oversize' => n[:oversize].map { |o| o[:id] || o['id'] }.compact,
          'parts' => n[:items].size }
      end
      area = an[:area]
      sheet_goods = %w[top glass splash].filter_map do |mat|
        a = area[mat]
        next unless a && a > 0

        rows = an[:rows].select { |r| r[:mat] == mat }
        { 'material' => names[mat] || mat, 'key' => mat, 'category' => mat == 'top' ? 'worktop' : mat, 'thk' => rows.first && rows.first[:thk], 'net_m2' => a.round(3), 'pieces' => EGC::Num.sum(rows) { |r| r[:qty] },
          'length_m' => (EGC::Num.sum(rows) { |r| r[:len] * r[:qty] } / 1000.0).round(2) }
      end
      edge = an[:edge].map { |t, m| { 'thk' => t, 'meters' => m.round(2) } }
      hw = an[:hw].reject { |_, v| v.to_f <= 0 }.map { |k, v| { 'key' => k, 'qty' => v.round(2) } }
      led = an[:led]
      { 'boards' => boards, 'sheet_goods' => sheet_goods, 'edge' => edge, 'hardware' => hw,
        'led' => { 'runs' => led['runs'], 'strip_m' => (led['strip_mm'] / 1000.0).round(2), 'profile_m' => (led['strip_mm'] / 1000.0).round(2) }, 'fascia' => an[:fascia],
        'appliances' => an[:apps].map { |k, n| { 'kind' => k, 'qty' => n } },
        'totals' => { 'sheets' => EGC::Num.sum(boards) { |b| b['sheets'] }, 'net_m2' => EGC::Num.sum(boards) { |b| b['net_m2'] }.round(2), 'waste_m2' => EGC::Num.sum(boards) { |b| b['waste_m2'] }.round(2),
                      'waste_pct' => (EGC::Num.sum(boards) { |b| b['gross_m2'] }.positive? ? (EGC::Num.sum(boards) { |b| b['waste_m2'] } / EGC::Num.sum(boards) { |b| b['gross_m2'] } * 100.0).round(1) : 0) } }
    end

    def takeoff_html(t, lang = 'en')
      ar = lang == 'ar'
      k = ->(en, a) { ar ? a : en }
      s = +"<h2>#{k.call('Boards (from NESTING - the sheets really required)', 'الألواح (من التقطيع - عدد الأوراق الفعلي)')}</h2>"
      s << SvgDraw.data_table([k.call('Material', 'الخامة'), k.call('Thk', 'السمك'), k.call('Sheet', 'الورقة'), k.call('Sheets required', 'عدد الأوراق'), k.call('Net m²', 'صافي م²'), k.call('Gross m²', 'إجمالي م²'), k.call('Waste m²', 'هالك م²'), k.call('Waste %', 'هالك %'), k.call('Kerf/Trim', 'كيرف/تقليم'), k.call('Oversize', 'خارج المقاس')],
                              t['boards'].map { |b| [b['material'], b['thk'], b['sheet'].join('×'), b['sheets'], b['net_m2'], b['gross_m2'], b['waste_m2'], b['waste_pct'], "#{b['kerf']}/#{b['trim']}", b['oversize'].empty? ? '-' : b['oversize'].join(', ')] })
      s << "<div class='note'>#{k.call('Total sheets', 'إجمالي الأوراق')}: <b>#{t['totals']['sheets']}</b> · #{k.call('waste', 'الهالك')} #{t['totals']['waste_m2']} m² (#{t['totals']['waste_pct']} %)</div>"
      s << "<h2>#{k.call('Worktop / glass / splash (by net area)', 'الرخام / الزجاج / الباك سبلاش (بالمساحة الصافية)')}</h2>"
      s << SvgDraw.data_table([k.call('Material', 'الخامة'), k.call('Category', 'النوع'), k.call('Thk', 'السمك'), k.call('Net m²', 'صافي م²'), k.call('Pieces', 'القطع'), k.call('Length m', 'الطول م')], t['sheet_goods'].map { |g| [g['material'], g['category'], g['thk'], g['net_m2'], g['pieces'], g['length_m']] })
      s << "<h2>#{k.call('Edge banding', 'شريط الحواف')}</h2>" + SvgDraw.data_table([k.call('Thickness mm', 'السمك مم'), k.call('Metres', 'متر')], t['edge'].map { |e| [e['thk'], e['meters']] })
      s << "<h2>#{k.call('Hardware, mechanisms, accessories, LED', 'الإكسسوار والمكانيزمات والإضاءة')}</h2>" + SvgDraw.data_table([k.call('Item', 'البند'), k.call('Qty', 'الكمية')], t['hardware'].map { |x| [x['key'], x['qty']] })
      s << "<div class='note'>LED: #{t['led']['runs']} #{k.call('continuous run(s)', 'مسار متصل')}, #{k.call('strip', 'شريط')} #{t['led']['strip_m']} m, #{k.call('profile', 'بروفايل')} #{t['led']['profile_m']} m</div>"
      unless t['fascia'].empty?
        s << "<h2>#{k.call('Top fascia', 'الوزرة العلوية')}</h2>" + SvgDraw.data_table([k.call('Run', 'الضلع'), k.call('Length mm', 'الطول مم'), k.call('Height mm', 'الارتفاع مم'), k.call('Pieces', 'القطع')], t['fascia'].map { |f| [f['id'], f['length_mm'], f['height_mm'], f['pieces']] })
      end
      s << "<h2>#{k.call('Appliances (schedule)', 'الأجهزة (الجدول)')}</h2>" + SvgDraw.data_table([k.call('Kind', 'النوع'), k.call('Qty', 'العدد')], t['appliances'].map { |a| [a['kind'], a['qty']] })
      s
    end

    def takeoff_csv(t)
      rows = [%w[section material key thk sheet sheets net_m2 gross_m2 waste_m2 waste_pct]]
      t['boards'].each { |b| rows << ['board', b['material'], b['key'], b['thk'], b['sheet'].join('x'), b['sheets'], b['net_m2'], b['gross_m2'], b['waste_m2'], b['waste_pct']] }
      t['sheet_goods'].each { |g| rows << [g['category'], g['material'], g['key'], g['thk'], '', g['pieces'], g['net_m2'], '', '', ''] }
      t['edge'].each { |e| rows << ['edge', "#{e['thk']} mm", '', e['thk'], '', '', e['meters'], '', '', ''] }
      t['hardware'].each { |x| rows << ['hardware', x['key'], x['key'], '', '', x['qty'], '', '', '', ''] }
      rows.map { |r| r.map { |c| "\"#{c.to_s.gsub('"', '""')}\"" }.join(',') }.join("\n")
    end

    # ------------------------------------------------------------------ internal cost
    # -> { lines, missing: [..], extra: [..], subtotal, total, currency, complete }
    def internal(an, cfg, lang = 'en')
      cost = an[:cost]
      lines = cost[:lines].map { |l| l.merge(status: (l[:price].to_f <= 0 && l[:qty].to_f.positive?) ? 'MISSING_PRICE' : 'PRICED') }
      missing = (cost[:missing] || lines.select { |l| l[:status] == 'MISSING_PRICE' }.map { |l| { 'item' => l[:item], 'reason' => 'no unit price in the price table' } }).map(&:dup)
      pa = cfg['price_app'] || {}
      an[:apps].each do |kind, n|
        p = pa[kind]
        if p.nil?
          lines << { item: "Appliance: #{kind}", qty: n, unit: 'pcs', price: nil, amount: 0.0, cat: 'appliance', status: 'MISSING_PRICE' }
          missing << { 'item' => "appliance #{kind} x#{n}", 'reason' => 'appliance price not entered (never invented)' }
        else
          lines << { item: "Appliance: #{kind}", qty: n, unit: 'pcs', price: p.to_f, amount: p.to_f * n, cat: 'appliance', status: 'PRICED' }
        end
      end
      sub = EGC::Num.sum(lines) { |l| l[:amount].to_f }
      board_area = EGC::Num.sum(an[:nest].values) { |n| n[:total] }
      extra = (cfg['extra_costs'] || []).map do |e|
        v = e['value']
        if v.nil?
          missing << { 'item' => "extra cost: #{e['name']}", 'reason' => 'not set (REQUIRES_CONFIRMATION)' }
          { 'name' => e['name'], 'kind' => e['kind'], 'value' => nil, 'amount' => 0.0, 'status' => 'MISSING_DATA' }
        else
          amt = case e['kind'] when 'pct' then sub * v.to_f / 100.0 when 'per_m2' then board_area * v.to_f else v.to_f end
          { 'name' => e['name'], 'kind' => e['kind'], 'value' => v, 'amount' => amt, 'status' => 'SET' }
        end
      end
      labor = cost[:labor].to_f
      total = sub + labor + EGC::Num.sum(extra) { |e| e['amount'] }
      { lines: lines, missing: missing, extra: extra, subtotal: sub, labor: labor, total: total, currency: cost[:currency], complete: missing.empty? }
    end

    def internal_html(ic, lang = 'en')
      ar = lang == 'ar'
      k = ->(en, a) { ar ? a : en }
      s = +''
      unless ic[:complete]
        s << "<div class='warn'>#{k.call('INCOMPLETE COST', 'التكلفة غير مكتملة')}: #{ic[:missing].size} #{k.call('item(s) without a price / value are NOT in the total:', 'بند بدون سعر / قيمة وغير محسوبة في الإجمالي:')}</div><ul>#{ic[:missing].map { |m| "<li><span class='st MISSING_PRICE'>MISSING PRICE</span> #{h(m['item'])} - #{h(m['reason'])}</li>" }.join}</ul>"
      end
      s << SvgDraw.data_table([k.call('Item', 'البند'), k.call('Qty', 'الكمية'), k.call('Unit', 'الوحدة'), k.call('Price', 'السعر'), k.call('Amount', 'المبلغ'), k.call('Status', 'الحالة')],
                              ic[:lines].map { |l| [l[:item], l[:qty], l[:unit], l[:price].nil? ? '-' : fmt(l[:price]), fmt(l[:amount]), SvgDraw.badge(l[:status])] })
      s << "<h2>#{k.call('Additional costs', 'تكاليف إضافية')}</h2>" + SvgDraw.data_table([k.call('Name', 'الاسم'), k.call('Basis', 'الأساس'), k.call('Value', 'القيمة'), k.call('Amount', 'المبلغ'), k.call('Status', 'الحالة')],
                                                                                    ic[:extra].map { |e| [e['name'], e['kind'], e['value'].nil? ? '-' : e['value'], fmt(e['amount']), SvgDraw.badge(e['status'] == 'SET' ? 'CONFIRMED' : 'MISSING_DATA')] })
      s << "<table class='data'><tr><td><b>#{k.call('Materials + hardware + appliances', 'خامات + إكسسوار + أجهزة')}</b></td><td>#{fmt(ic[:subtotal])} #{h(ic[:currency])}</td></tr>" \
           "<tr><td>#{k.call('Labour %', 'عمالة %')}</td><td>#{fmt(ic[:labor])}</td></tr><tr><td><b>#{k.call('INTERNAL COST TOTAL (known items only)', 'إجمالي التكلفة الداخلية (البنود المعروفة فقط)')}</b></td><td><b>#{fmt(ic[:total])} #{h(ic[:currency])}</b></td></tr></table>"
      s << "<div class='note'>#{k.call('INTERNAL - not for the customer.', 'داخلي - ليس للعميل.')}</div>"
      s
    end

    # customer quote = the existing Quote page + a visible banner when a price is missing
    def customer_html(an, client, cfg, lang, ic)
      q = Quote.html(an, client, cfg, lang)
      return q if q[:incomplete]
      return q if ic[:complete]

      ar = lang == 'ar'
      banner = "<div style='background:#fde0dc;color:#b42318;padding:8px 14px;font-weight:700;margin:8px 0'>#{ar ? 'تنبيه: عرض السعر غير مكتمل - أسعار ناقصة' : 'NOTICE: quotation INCOMPLETE - missing prices'} (#{ic[:missing].size}): #{ic[:missing].first(6).map { |m| h(m['item']) }.join(' | ')}</div>"
      q.merge(html: q[:html].sub(/<body[^>]*>/) { |b| b + banner }, incomplete: true)
    end
  end
end
