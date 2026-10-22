# frozen_string_literal: true

module EGC
  module I18n
    STR = {
      'en' => {
        'menu_open' => 'Open E.G.C Builder', 'menu_cutlist' => 'Cut list & report', 'menu_place' => 'Place kitchen...',
        'menu_unit' => 'Insert single unit...', 'tb_name' => 'E.G.C Builder',
        'ctx_style' => 'Apply the kitchen style to this unit', 'ctx_cards' => 'Part cards / QR stickers', 'ctx_clash' => 'Check interference', 'ctx_register_prod' => 'تسجيل للإنتاج (قائمة القطع)', 'ctx_register_prod' => 'Add to production (cut list)', 'ctx_open' => 'Open / close', 'ctx_explode' => 'Exploded view on / off', 'ctx_edit' => 'Edit (dialog)',
        'ctx_resize' => 'Live resize (drag) ↔', 'ctx_dup' => 'Duplicate (rebuilt copy)',
        'ctx_mirror' => 'Mirror hinge side', 'ctx_iso' => 'Isolate', 'ctx_show' => 'Show everything', 'ctx_draw' => 'Shop drawing',
        'menu_client' => 'Client view (hide hardware)', 'menu_scenes' => 'Create scenes', 'menu_audit' => 'Preflight check',
        'overlap_ask' => "An E.G.C kitchen is already standing on this spot.

YES = replace it with the new kitchen
NO = keep both (they will overlap: doubled boards, false neighbours, wrong quantities)
CANCEL = change nothing", 'select_any' => 'Select an E.G.C unit first.', 'notch_no_mech' => 'Column notch is not available on mechanism units - change the unit type first.', 'op_err_no_wall' => 'Click on a wall face (it must be drawn geometry: a face, or a face inside a group/component).', 'op_err_not_vertical' => 'This face is not a vertical wall.', 'op_err_outside' => 'The opening does not fit inside this wall face (keep it away from the wall edges).', 'op_err_overlap' => 'It overlaps another opening.', 'op_err_wall_thickness' => 'Could not measure the wall thickness (the wall needs a back face).', 'preflight_ok' => 'No problems found',
        'report' => 'Cut List & Cost Report', 'project' => 'Project', 'date' => 'Date',
        'summary' => 'Summary', 'parts_total' => 'Total parts', 'net_area' => 'Net board area (m²)',
        'sheets' => 'Sheets used', 'waste' => 'Waste', 'cost' => 'Estimated cost', 'total' => 'Total',
        'material' => 'Material', 'thk' => 'Thk', 'part' => 'Part', 'len' => 'Length', 'wid' => 'Width',
        'qty' => 'Qty', 'edge' => 'Edge banding', 'groove' => 'Groove / notes', 'area' => 'Area (m²)',
        'cutlist' => 'Cut list', 'edging' => 'Edge banding (m)', 'hardware' => 'Hardware',
        'appliances' => 'Appliances', 'nesting' => 'Sheet layout (nesting)', 'sheet' => 'Sheet',
        'price' => 'Unit price', 'amount' => 'Amount', 'item' => 'Item', 'count' => 'Count',
        'cabinets' => 'Cabinets', 'name' => 'Name', 'size' => 'Size (W x H x D)', 'labor' => 'Labor / margin',
        'nothing' => 'No E.G.C parts found in the model.', 'oversize' => 'Part larger than the sheet',
        'sheet_size' => 'Sheet size', 'stock_by_material' => 'Stock by material and thickness', 'kerf' => 'Kerf',
        'hinge' => 'Hinges', 'hinge_bifold' => 'Bi-fold corner hinges', 'vent_grille' => 'Ventilation grilles (under oven)', 'gola_l_m' => 'Handle-free L profile (m)', 'gola_c_m' => 'Handle-free C profile (m)', 'gola_w_m' => 'Handle-free wall unit profile (m)', 'gola_v_m' => 'Handle-free vertical profile (m)', 'gola_v2_m' => 'Handle-free vertical double profile (m)', 'gola_led_m' => 'LED strip in the handle-free profiles (m)', 'slide_pair' => 'Drawer slides (pair)', 'handle' => 'Handles',
        'profile_m' => 'J-profile (m)', 'leg' => 'Adjustable legs', 'plinth_clip' => 'Plinth profile clips', 'shelf_pin' => 'Shelf pins',
        'lift_up' => 'Lift-up fittings', 'led_m' => 'LED profile (m)', 'wall_hanger' => 'Wall hangers',
        'rod_m' => 'Hanging rail (m)', 'rod_bracket' => 'Rail brackets', 'slide_track_m' => 'Sliding track (m)', 'slide_wheel' => 'Sliding rollers',
        'p_vdivider' => 'Vertical divider', 'p_sliding_door' => 'Sliding door',
        'p_side_l' => 'Side (L)', 'p_side_r' => 'Side (R)', 'p_back' => 'Back', 'p_bottom' => 'Bottom',
        'p_top' => 'Top', 'p_top_rail_f' => 'Front rail', 'p_front_strip' => 'Front strip (upright)', 'p_top_rail_b' => 'Back rail', 'p_divider' => 'Divider',
        'p_shelf' => 'Shelf', 'p_door' => 'Door', 'p_flap' => 'Lift-up door', 'p_drawer_front' => 'Drawer front',
        'p_drawer_side' => 'Drawer side', 'p_drawer_back' => 'Drawer back', 'p_drawer_subfront' => 'Drawer sub-front',
        'p_drawer_bottom' => 'Drawer bottom', 'p_plinth' => 'Plinth', 'p_countertop' => 'Countertop',
        'p_fascia' => 'Fascia / curtain', 'p_filler' => 'Filler', 'p_end_panel' => 'End panel', 'p_upstand' => 'Upstand', 'p_backsplash' => 'Backsplash',
        'a_fridge' => 'Refrigerator', 'a_washer' => 'Washing machine', 'a_dishwasher' => 'Dishwasher',
        'a_oven' => 'Built-in oven', 'a_microwave' => 'Microwave', 'a_hood' => 'Cooker hood',
        'a_dryer' => 'Dryer', 'a_freezer' => 'Freezer', 'a_wine_cooler' => 'Wine cooler', 'a_coffee' => 'Coffee machine', 'a_warming' => 'Warming drawer', 'a_hob' => 'Hob', 'a_sink' => 'Sink',
        'a_hob_gas' => 'Gas hob', 'a_hood_chimney' => 'Chimney hood', 'a_hood_slim' => 'Slim hood', 'a_wall_rail' => 'Wall rail with accessories',
        'basket' => 'Wire baskets', 'basket_set' => 'Basket pull-out sets', 'spice_rack' => 'Spice pull-outs', 'tray_rack' => 'Tray pull-outs', 'waste_bin' => 'Waste bin pull-outs', 'waste_bin_unit' => 'Waste bins',
        'pantry_pullout' => 'Pantry pull-out sets', 'pantry_fixed' => 'Pantry (fixed frame) sets', 'trolley' => 'Trolleys', 'box_unit' => 'Box units', 'wire_drawer' => 'Wire drawers', 'laundry_bag' => 'Laundry bags', 'plate_holder' => 'Plate holders',
        'undermount_slide' => 'Undermount slides (pair)', 'bifold_lift' => 'Bi-fold lift sets', 'dish_rack' => 'Dish racks', 'hanging_rail' => 'Hanging rails (cut to length)', 'imove_single_tray' => 'Pull-down single tray sets', 'door_bin' => 'Door-mounted bins', 'broom_pullout' => 'Broom pull-out columns', 'chef_table' => 'Swing-out work tables', 'table_pullout' => 'Pull-out tables', 'electric_lift' => 'Powered lift baskets', 'lemans_set' => 'Corner swing-out tray sets', 'cutlery_tray' => 'Cutlery trays', 'trouser_rack' => 'Trouser racks', 'pulldown_rail' => 'Pull-down rails'
      },
      'ar' => {
        'menu_open' => 'فتح E.G.C Builder', 'menu_cutlist' => 'قائمة القطع والتقرير', 'menu_place' => 'وضع المطبخ...',
        'menu_unit' => 'إدراج وحدة منفردة...', 'tb_name' => 'E.G.C Builder',
        'ctx_style' => 'طبّق استايل المطبخ على الوحدة', 'ctx_cards' => 'كروت القطع / ملصقات QR', 'ctx_clash' => 'فحص التداخل', 'ctx_open' => 'فتح / قفل', 'ctx_explode' => 'عرض منفجر تشغيل / إيقاف', 'ctx_edit' => 'تعديل (نافذة)',
        'ctx_resize' => 'تحجيم حي بالسحب ↔', 'ctx_dup' => 'نسخ (وحدة مبنية من جديد)',
        'ctx_mirror' => 'قلب جهة المفصلة', 'ctx_iso' => 'عزل', 'ctx_show' => 'إظهار الكل', 'ctx_draw' => 'شوب دروينج',
        'menu_client' => 'عرض العميل (إخفاء الهاردوير)', 'menu_scenes' => 'إنشاء المشاهد', 'menu_audit' => 'فحص قبل التصنيع',
        'overlap_ask' => "يوجد مطبخ E.G.C قائم في نفس المكان.

نعم = استبداله بالمطبخ الجديد
لا = إبقاء الاثنين (سيتداخلان: ألواح مضاعفة وجيران خاطئون وكميات خاطئة)
إلغاء = لا تغيّر شيئًا", 'select_any' => 'حدد وحدة E.G.C أولاً.', 'notch_no_mech' => 'قطع العمود غير متاح لوحدات الميكانيزم - غيّر نوع الوحدة أولاً.', 'op_err_no_wall' => 'اضغط على وجه حائط مرسوم (وجه Face أو وجه داخل Group/Component).', 'op_err_not_vertical' => 'الوجه ده مش حائط رأسي.', 'op_err_outside' => 'الفتحة مش داخلة في وجه الحائط (ابعدها عن حواف الحائط).', 'op_err_overlap' => 'الفتحة بتتداخل مع فتحة تانية.', 'op_err_wall_thickness' => 'مقدرتش أقيس سمك الحائط (لازم يكون له وجه خلفي).', 'preflight_ok' => 'لا توجد مشاكل',
        'report' => 'تقرير قائمة القطع والتكلفة', 'project' => 'المشروع', 'date' => 'التاريخ',
        'summary' => 'الملخص', 'parts_total' => 'إجمالي القطع', 'net_area' => 'صافي مساحة الألواح (م²)',
        'sheets' => 'عدد الألواح المستخدمة', 'waste' => 'الهالك', 'cost' => 'التكلفة التقديرية', 'total' => 'الإجمالي',
        'material' => 'الخامة', 'thk' => 'السمك', 'part' => 'القطعة', 'len' => 'الطول', 'wid' => 'العرض',
        'qty' => 'العدد', 'edge' => 'الشريط الحراري', 'groove' => 'حفر / ملاحظات', 'area' => 'المساحة (م²)',
        'cutlist' => 'قائمة القطع', 'edging' => 'الشريط الحراري (متر)', 'hardware' => 'الإكسسوارات',
        'appliances' => 'الأجهزة', 'nesting' => 'خريطة تقطيع الألواح', 'sheet' => 'لوح',
        'price' => 'سعر الوحدة', 'amount' => 'المبلغ', 'item' => 'البند', 'count' => 'الكمية',
        'cabinets' => 'الوحدات', 'name' => 'الاسم', 'size' => 'المقاس (عرض × ارتفاع × عمق)', 'labor' => 'مصنعية / هامش',
        'nothing' => 'لا توجد قطع E.G.C في الموديل.', 'oversize' => 'قطعة أكبر من اللوح',
        'sheet_size' => 'مقاس اللوح', 'stock_by_material' => 'مخزون كل خامة وسمكها', 'kerf' => 'سماكة المنشار',
        'hinge' => 'مفصلات', 'hinge_bifold' => 'مفصلات بيفولد للركنة', 'vent_grille' => 'شبك تهوية تحت الفرن', 'gola_l_m' => 'بروفايل جولا L (متر)', 'gola_c_m' => 'بروفايل جولا C (متر)', 'gola_w_m' => 'بروفايل جولا للعلوي (متر)', 'gola_v_m' => 'بروفايل جولا رأسي (متر)', 'gola_v2_m' => 'بروفايل جولا رأسي مزدوج (متر)', 'gola_led_m' => 'شريط LED داخل بروفايل الجولا (متر)', 'slide_pair' => 'مجاري أدراج (زوج)', 'handle' => 'مقابض',
        'profile_m' => 'بروفايل J (متر)', 'leg' => 'أرجل ضبط', 'plinth_clip' => 'مشابك بروفايل القاعدة', 'shelf_pin' => 'مسامير رفوف',
        'lift_up' => 'رافعات هيدروليك', 'led_m' => 'بروفايل ليد (متر)', 'wall_hanger' => 'شنايل تعليق',
        'rod_m' => 'ماسورة تعليق (متر)', 'rod_bracket' => 'حوامل ماسورة', 'slide_track_m' => 'ريل سحاب (متر)', 'slide_wheel' => 'عجل سحاب',
        'p_vdivider' => 'فاصل رأسي', 'p_sliding_door' => 'باب سحاب',
        'p_side_l' => 'جنب (يسار)', 'p_side_r' => 'جنب (يمين)', 'p_back' => 'ضهر', 'p_bottom' => 'قاعدة',
        'p_top' => 'سقف', 'p_top_rail_f' => 'عارضة أمامية', 'p_front_strip' => 'شرحة أمامية واقفة', 'p_top_rail_b' => 'عارضة خلفية', 'p_divider' => 'فاصل',
        'p_shelf' => 'رف', 'p_door' => 'باب', 'p_flap' => 'باب رافع', 'p_drawer_front' => 'واجهة درج',
        'p_drawer_side' => 'جنب درج', 'p_drawer_back' => 'ضهر درج', 'p_drawer_subfront' => 'مقدمة درج داخلية',
        'p_drawer_bottom' => 'قاع درج', 'p_plinth' => 'وزرة (قاعدة)', 'p_countertop' => 'رخام / سطح عمل',
        'p_fascia' => 'ستارة / وزرة علوية', 'p_filler' => 'حشوة', 'p_end_panel' => 'جنب إنهاء', 'p_upstand' => 'حاجز رخام خلفي', 'p_backsplash' => 'باك سبلاش',
        'a_fridge' => 'ثلاجة', 'a_washer' => 'غسالة', 'a_dishwasher' => 'غسالة أطباق',
        'a_oven' => 'فرن مدمج', 'a_microwave' => 'ميكروويف', 'a_hood' => 'شفاط (هود)',
        'a_dryer' => 'نشافة', 'a_freezer' => 'فريزر', 'a_wine_cooler' => 'مبرد مشروبات', 'a_coffee' => 'ماكينة قهوة', 'a_warming' => 'درج تسخين', 'a_hob' => 'بوتجاز مسطح', 'a_sink' => 'حوض',
        'a_hob_gas' => 'بوتجاز غاز', 'a_hood_chimney' => 'شفاط مدخنة', 'a_hood_slim' => 'شفاط سلم', 'a_wall_rail' => 'قضيب حائط بإكسسوارات',
        'basket' => 'سلال سلك', 'basket_set' => 'أطقم سلال سحب', 'spice_rack' => 'سحب بهارات', 'tray_rack' => 'سحب صواني', 'waste_bin' => 'سحب مهملات', 'waste_bin_unit' => 'سلال مهملات',
        'pantry_pullout' => 'مخازن سحب', 'pantry_fixed' => 'مخازن بإطار ثابت', 'trolley' => 'ترولي', 'box_unit' => 'وحدات صناديق', 'wire_drawer' => 'أدراج سلك', 'laundry_bag' => 'أكياس غسيل', 'plate_holder' => 'حوامل أطباق',
        'undermount_slide' => 'مجاري مخفية (زوج)', 'bifold_lift' => 'أطقم رفع بيفولد', 'dish_rack' => 'رفوف أطباق', 'hanging_rail' => 'مواسير تعليق (تتقص على المقاس)', 'imove_single_tray' => 'أطقم رف مفرد سحب لأسفل', 'door_bin' => 'سلال مهملات على الضلفة', 'broom_pullout' => 'ساحب مكنسة', 'chef_table' => 'ترابيزات شغل سحب لقدام', 'table_pullout' => 'ترابيزات سحب', 'electric_lift' => 'رفوف كهربائية نازلة', 'lemans_set' => 'أطقم صواني ركنة دوارة', 'cutlery_tray' => 'صواني أدوات مائدة', 'trouser_rack' => 'حوامل بناطيل', 'pulldown_rail' => 'مواسير هيدروليك'
      }
    }.freeze

    module_function

    def t(key, lang = 'en')
      (STR[lang] || STR['en'])[key] || STR['en'][key] || key
    end

    def part(name, lang = 'en')
      t("p_#{name}", lang)
    end

    def app(name, lang = 'en')
      t("a_#{name}", lang)
    end
  end
end
