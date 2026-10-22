# frozen_string_literal: true

module EGC
  # Arabic wording for the assistant's engine messages (validation items, design notes / problems). The engine produces one English sentence
  # per CODE; this maps CODE -> Arabic sentence built from the same numbers / ids, so the Arabic UI never shows English sentences.
  # The English text and the CODE are untouched (reports, tests, CSV keep using them).
  module AssistantI18n
    module_function

    WORDS = { 'fridge clearances' => 'تخليصات الثلاجة', 'clearances' => 'التخليصات', 'side' => 'جانب', 'top' => 'علوي', 'back' => 'خلفي', 'front' => 'أمامي',
              'fridge' => 'الثلاجة', 'hob' => 'الهوب', 'oven' => 'الفرن', 'housing' => 'بيت الثلاجة', 'gap' => 'فراغ', 'mm' => 'مم' }.freeze

    def words(s)
      s.to_s.gsub('fridge clearances', 'تخليصات الثلاجة').gsub(/[A-Za-z]+/) { |w| WORDS[w] || w }
    end

    def n(msg)
      msg.to_s.scan(/-?\d+(?:\.\d+)?/)
    end

    def id_after(msg, key)
      msg.to_s[/#{key} (\S+)/, 1].to_s
    end

    MSG = {
      'OVERLAPPING_UNITS' => ->(i, m) { "تداخل بين الوحدات: #{i['where']}" },
      'OUTSIDE_ROOM' => ->(i, m) { "#{i['where']} تخرج من حدود الغرفة (#{n(m)[0]} من 8 أركان)" },
      'DOOR_BLOCKED' => ->(i, m) { "#{i['where']} تقف أمام الباب #{id_after(m, 'door')}" },
      'WINDOW_COVERED' => ->(i, m) { "#{i['where']} تغطي الشباك #{id_after(m, 'window')} (الجلسة #{n(m).last} مم)" },
      'WINDOW_BELOW_WORKTOP' => ->(i, m) { "جلسة الشباك #{i['where']} (#{n(m)[0]} مم) أقل من سطح العمل 900 مم" },
      'COLUMN_CONFLICT' => ->(i, m) { "#{i['where']} تصطدم بالعمود #{id_after(m, 'column')}" },
      'REQUIRES_CONFIRMATION' => ->(i, m) { "#{i['where']}: #{words(m.to_s.sub(/\A[^:]*: /, '').sub(/ is a configurable default.*/, ''))} - قيمة افتراضية قابلة للضبط وليست بيانات المصنّع" },
      'HOB_OVEN_CLEARANCE' => ->(i, m) { "الفراغ بين الهوب والفرن #{n(m)[0]} مم أقل من #{n(m)[1]} مم" },
      'CEILING_LOW' => ->(i, m) { "الوحدات تصل إلى #{n(m)[0]} مم بينما السقف #{n(m)[1]} مم" },
      'CEILING_UNKNOWN' => ->(_i, _m) { 'ارتفاع السقف غير مؤكد' },
      'CEILING_UNCONFIRMED' => ->(_i, _m) { 'ارتفاع السقف غير مؤكد من المستخدم' },
      'SERVICE_NOT_NEAR_SINK' => ->(i, m) { "لا توجد نقطة مياه / صرف خلال 800 مم من #{i['where']}" },
      'SERVICES_UNKNOWN' => ->(_i, _m) { 'لم تُؤكَّد أي نقطة خدمات (مياه / صرف / كهرباء / غاز): سترسم المخططات اقتراحات عليها علامة REQUIRES_CONFIRMATION' },
      'AISLE_TOO_NARROW' => ->(i, m) { "الممر #{n(m)[-2] || n(m)[0]} مم أقل من الحد الأدنى #{n(m).last} مم" },
      'STALE_PRODUCTION_DATA' => ->(i, m) { "بيانات إنتاج قديمة في #{i['where']}: #{m}" },
      'ANALYSIS_FAILED' => ->(_i, m) { "فشل تحليل الإنتاج: #{m}" },
      'NO_ROOM' => ->(_i, _m) { 'لم تُحدَّد الغرفة (الحوائط) بعد' },
      'RUN_TOO_SHORT' => ->(_i, m) { "لا يوجد حائط بمسافة حرة كافية للمطبخ (#{n(m)[0]} مم على الأقل)" },
      'NO_OPPOSITE_WALL' => ->(_i, _m) { 'لا يوجد حائط موازٍ للتصميم المتوازي' }
    }.freeze

    FIX = {
      'OVERLAPPING_UNITS' => 'احذف الوحدة المكررة أو انقلها / صغّر الوحدة المجاورة',
      'OUTSIDE_ROOM' => 'قصّر الخط أو انقل الوحدة داخل الحوائط',
      'DOOR_BLOCKED' => 'أزل الوحدة أو قصّرها',
      'WINDOW_COVERED' => 'أزل الوحدة العلوية أمام الشباك (الوحدة السفلية مقبولة فقط لو الجلسة فوق سطح العمل 900 مم)',
      'WINDOW_BELOW_WORKTOP' => 'ارفع سبلاش سطح العمل أو أكّد',
      'COLUMN_CONFLICT' => 'استخدم قطع العمود (تعديل > قطع العمود) أو اترك المكان',
      'REQUIRES_CONFIRMATION' => 'أكّد التخليصات للجهاز الفعلي (الإعدادات)',
      'HOB_OVEN_CLEARANCE' => 'اختر هوب / فرن أقل عمقاً أو وحدة أعلى',
      'CEILING_LOW' => 'اخفض الطوابق أو أكّد ارتفاع السقف',
      'CEILING_UNKNOWN' => 'أدخل ارتفاع السقف',
      'CEILING_UNCONFIRMED' => 'أكّد ارتفاع السقف',
      'SERVICE_NOT_NEAR_SINK' => 'أكّد أو أضف نقاط المياه والصرف (أو انقل الحوض)',
      'SERVICES_UNKNOWN' => 'أدخل نقاط الخدمات الحقيقية',
      'AISLE_TOO_NARROW' => 'قلّل عرض الجزيرة / احذف الخط الثاني',
      'STALE_PRODUCTION_DATA' => 'أعد بناء الوحدة بأداة Resize / Edit'
    }.freeze

    def item(i)
      i = i.dup
      f = MSG[i['code'].to_s] || (i['code'].to_s.start_with?('REQUIRES') ? MSG['REQUIRES_CONFIRMATION'] : nil)
      i['message'] = f.call(i, i['message'].to_s) if f
      fx = FIX[i['code'].to_s] || (i['code'].to_s.start_with?('REQUIRES') ? FIX['REQUIRES_CONFIRMATION'] : nil)
      i['fix'] = fx if fx && i['fix']
      i
    end

    def note(s)
      case s.to_s
      when /\Alayout (\S+) chosen for wall (\S+) \(free (\d+) mm\)/ then "تم اختيار تخطيط #{Regexp.last_match(1)} على الحائط #{Regexp.last_match(2)} (المسافة الحرة #{Regexp.last_match(3)} مم)"
      when /\Asink centred under the window \(error (\d+) mm\)/ then "الحوض في منتصف الشباك (فرق #{Regexp.last_match(1)} مم)"
      else s
      end
    end

    def validation(v)
      return v unless v.is_a?(Hash)

      v = v.dup
      %w[problems warnings info suggestions].each { |k| v[k] = v[k].map { |i| item(i) } if v[k].is_a?(Array) }
      v
    end

    def plan(p)
      return p unless p.is_a?(Hash)

      p = p.dup
      p['notes'] = p['notes'].map { |s| note(s) } if p['notes'].is_a?(Array)
      p['problems'] = p['problems'].map { |i| item(i) } if p['problems'].is_a?(Array)
      p
    end

    TITLES = { 'Change refrigerator' => 'تغيير الثلاجة', 'Sink under the window' => 'الحوض تحت الشباك', 'Drawers right of the hob' => 'أدراج يمين الهوب',
               'Glass upper doors' => 'أبواب علوية زجاج', 'No handles' => 'بدون مقابض', 'Narrower island' => 'جزيرة أضيق' }.freeze
    # [regex, arabic replacement]  (applied to what / why / affected / expected / message)
    EDIT_RX = [
      [/\ARefrigerator (\S+) -> (\S+) \((\d+) mm\), housing (\d+) -> (\d+) mm/, 'الثلاجة \1 ← \2 (\3 مم)، بيت الثلاجة \4 ← \5 مم'],
      [/\Ayou asked for a (\d+) mm refrigerator/, 'طلبت ثلاجة \1 مم'],
      [/\Adoor unit (\d+) gives (\d+) mm/, 'وحدة الأبواب \1 تتنازل عن \2 مم'],
      [/\A(\d+) columns\z/, '\1 أعمدة'],
      [/\Athe kitchen is regenerated from its plan with the new housing; the run length stays the same/, 'يُعاد توليد المطبخ من خطته بالبيت الجديد وطول الخط ثابت'],
      [/\Are-plan run A: sink centred on window (\S+) \(error (\d+) mm\)/, 'إعادة تخطيط الخط A: الحوض في منتصف الشباك \1 (فرق \2 مم)'],
      [/\Ayou asked for the sink under the window/, 'طلبت الحوض تحت الشباك'],
      [/\Asink centre within (\d+) mm of the window centre; run length unchanged/, 'مركز الحوض خلال \1 مم من مركز الشباك، وطول الخط ثابت'],
      [/\A(\S+): doors -> 3 drawers \(same width (\d+) mm\)/, '\1: أبواب ← 3 أدراج (نفس العرض \2 مم)'],
      [/\Ayou asked for drawers to the right of the hob/, 'طلبت أدراج يمين الهوب'],
      [/\Aonly that unit is rebuilt; nothing else moves/, 'تُعاد هذه الوحدة فقط ولا يتحرك أي شيء آخر'],
      [/\A(\d+) upper unit\(s\): door -> glass door/, '\1 وحدة علوية: باب ← باب زجاج'],
      [/\Ayou asked for glass uppers/, 'طلبت أبواب علوية زجاج'],
      [/\Ahandle style (\S+) -> none on (\d+) units/, 'شكل المقبض \1 ← بدون على \2 وحدة'],
      [/\Ayou asked for handle-less fronts/, 'طلبت واجهات بدون مقابض'],
      [/\Aisland depth (\d+) -> (\d+) mm/, 'عمق الجزيرة \1 ← \2 مم'],
      [/\Ayou asked for the island (\d+) mm narrower/, 'طلبت الجزيرة أضيق بمقدار \1 مم'],
      [/\Aisland run\z/, 'خط الجزيرة'],
      [/\AI could not resolve this sentence to a known edit\./, 'لم أستطع ربط هذه الجملة بتعديل معروف.'],
      [/\AThere is no assistant-generated kitchen in the model yet\./, 'لا يوجد مطبخ مولَّد بالمساعد في الموديل بعد.'],
      [/\ANo refrigerator model in the catalogue matches (\d+) mm\./, 'لا يوجد موديل ثلاجة في الكتالوج بعرض \1 مم.'],
      [/\AThe refrigerator housing grows by (\d+) mm but the door units can only give (\d+) mm.*/, 'بيت الثلاجة يزيد \1 مم لكن وحدات الأبواب تستطيع التنازل عن \2 مم فقط.'],
      [/\AThe kitchen has no refrigerator open housing\./, 'المطبخ لا يحتوي على بيت ثلاجة مفتوح.'],
      [/\AThere is no window on wall (\S+) in the constraints\./, 'لا يوجد شباك على الحائط \1 في القيود.'],
      [/\AThe run cannot be re-planned with the sink under the window\./, 'لا يمكن إعادة تخطيط الخط والحوض تحت الشباك.'],
      [/\ANo run A found\./, 'لا يوجد الخط A.'],
      [/\AThere is no base unit directly to the right of the hob\./, 'لا توجد وحدة سفلية مباشرة يمين الهوب.'],
      [/\AThere is no hob unit in the kitchen\./, 'لا توجد وحدة هوب في المطبخ.'],
      [/\AThere are no upper door units to change\./, 'لا توجد وحدات علوية بأبواب لتغييرها.'],
      [/\AThe fronts already have no handles\./, 'الواجهات بدون مقابض بالفعل.']
    ].freeze

    def edit_text(s)
      s = s.to_s
      EDIT_RX.each { |rx, ar| return s.sub(rx, ar) if s.match?(rx) }
      s
    end

    def edit(d)
      d = d.dup
      d['title'] = TITLES[d['title']] || d['title'] if d['title']
      %w[what why expected message].each { |k| d[k] = edit_text(d[k]) if d[k].is_a?(String) }
      d['affected'] = d['affected'].map { |x| edit_text(x) } if d['affected'].is_a?(Array)
      d
    end

    # the whole reply hash
    def reply(data, lang)
      return data unless lang.to_s == 'ar' && data.is_a?(Hash)

      d = data.dup
      d['validation'] = validation(d['validation']) if d['validation']
      d['plan'] = plan(d['plan']) if d['plan']
      d = edit(d) if d['what'] || (d['message'] && d['ok'] == false)
      d
    end
  end
end
