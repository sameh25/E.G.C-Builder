# frozen_string_literal: true

require 'json'

module EGC
  # Catalog data sent to the dialog: unit types, mechanisms, appliances, materials.
  module Catalog
    DEV_IMG = 'assets/dev'

    def self.dev(id, kind, en, ar, w, h, d, z = 0)
      { id: id, kind: kind, en: en, ar: ar, w: w, h: h, d: d, z: z, img: "#{DEV_IMG}/#{id}.png" }
    end

    # Free-standing / built-in appliance boxes (nominal dimensions in mm)
    DEVICES = [
      dev('FRIDGE_TALL', 'fridge', 'Refrigerator – bottom freezer', 'ثلاجة فريزر سفلي', 600, 1850, 650),
      dev('FRIDGE_TOP', 'fridge', 'Refrigerator – top freezer', 'ثلاجة فريزر علوي', 700, 1750, 700).merge(style: 'top'), # generic nominal size: the real width is entered
      dev('FRIDGE_SBS', 'fridge', 'Refrigerator – side by side', 'ثلاجة جنب لجنب (مياه)', 900, 1780, 720),
      dev('FREEZER_TALL', 'freezer', 'Freezer – tall', 'فريزر طويل', 600, 1850, 650),
      dev('FRIDGE_UNDER', 'fridge', 'Refrigerator – under counter', 'ثلاجة تحت الرخام', 600, 820, 580),
      dev('WINE_COOLER', 'wine_cooler', 'Wine cooler', 'مبرد مشروبات', 600, 820, 580),
      dev('WASHER_60', 'washer', 'Washing machine 60', 'غسالة 60', 600, 820, 580),
      dev('DRYER_60', 'dryer', 'Dryer 60', 'نشافة 60', 600, 820, 580),
      dev('DISH_60', 'dishwasher', 'Dishwasher 60', 'غسالة أطباق 60', 600, 820, 570),
      dev('DISH_45', 'dishwasher', 'Dishwasher 45', 'غسالة أطباق 45', 450, 820, 570),
      dev('OVEN_60', 'oven', 'Built-in oven 60', 'فرن مدمج 60', 595, 595, 560),
      dev('COMPACT_45', 'oven', 'Compact oven 45', 'فرن كومباكت 45', 595, 455, 545),
      dev('MICRO_38', 'microwave', 'Microwave 38', 'ميكروويف 38', 595, 380, 400),
      dev('COFFEE_45', 'coffee', 'Coffee machine 45', 'ماكينة قهوة مدمجة 45', 595, 455, 400),
      dev('WARMING_DRAWER', 'warming', 'Warming drawer', 'درج تسخين', 595, 140, 540),
      dev('HOB_60', 'hob', 'Hob 60 (electric)', 'بوتجاز مسطح 60 كهرباء', 590, 50, 520, 854),
      dev('HOB_GAS_60', 'hob_gas', 'Hob 60 (gas)', 'بوتجاز مسطح 60 غاز', 590, 50, 520, 854),
      dev('SINK_600', 'sink', 'Sink 60', 'حوض 60', 600, 200, 450, 900),
      dev('SINK_800', 'sink', 'Sink 80', 'حوض 80', 800, 200, 450, 900),
      dev('HOOD_CHIMNEY', 'hood_chimney', 'Hood – chimney', 'شفاط مدخنة', 600, 700, 500, 1800),
      dev('HOOD_SLIM', 'hood_slim', 'Hood – slim', 'شفاط سلم', 600, 150, 300, 1500),
      dev('RAIL_1200', 'wall_rail', 'Wall rail 1200 with accessories (Linero type)', 'قضيب حائط 1200 بإكسسوارات (نوع Linero)', 1200, 300, 130, 1080),
      dev('RAIL_800', 'wall_rail', 'Wall rail 800 with accessories (Linero type)', 'قضيب حائط 800 بإكسسوارات (نوع Linero)', 800, 300, 130, 1080)
    ].freeze

    TYPE_NAMES = {
      'doors' => ['Base unit – doors', 'وحدة سفلية بأبواب'], 'drawers2' => ['Base – 2 drawers', 'وحدة سفلية درجين'],
      'drawers3' => ['Base – 3 drawers', 'وحدة سفلية 3 أدراج'], 'drawers4' => ['Base – 4 drawers', 'وحدة سفلية 4 أدراج'],
      'drawer_doors' => ['Base – drawer + doors', 'وحدة سفلية درج + أبواب'], 'sink' => ['Sink base', 'وحدة حوض'],
      'sink_drawer' => ['Sink base + drawer', 'وحدة حوض + درج'], 'hob' => ['Hob base', 'وحدة بوتجاز'], 'hob_oven' => ['Hob + oven base', 'وحدة بوتجاز + فرن'], 'fridge_open' => ['Fridge open housing', 'بيت ثلاجة مفتوح'], 'fridge_empty' => ['Fridge housing without the fridge', 'بيت ثلاجة بدون ثلاجة'],
      'oven' => ['Oven base', 'وحدة فرن'], 'washer_bi' => ['Built-in washer unit', 'وحدة غسالة مدمجة'],
      'dishwasher_bi' => ['Built-in dishwasher unit', 'وحدة غسالة أطباق مدمجة'], 'open' => ['Open unit', 'وحدة مفتوحة'],
      'pots' => ['Pots drawers', 'وحدة أدراج قدور'], 'corner_l' => ['L-shaped corner base', 'وحدة ركنة L'], 'blind_corner' => ['Blind corner base', 'وحدة ركنة عمياء'],
      'fridge_bi' => ['Built-in fridge tower', 'برج ثلاجة مدمجة'], 'pantry' => ['Pantry tower', 'برج مخزن'],
      'oven_tower' => ['Oven + microwave tower', 'برج فرن وميكروويف'], 'oven_tall' => ['Oven tower (built-in)', 'برج فرن مدمج'], 'microwave_tower' => ['Microwave tower (built-in)', 'برج ميكروويف مدمج'], 'flap' => ['Wall unit – lift-up', 'وحدة علوية فلاب'],
      'glass' => ['Wall unit – glass', 'وحدة علوية زجاج'], 'blind' => ['Wall blind corner', 'وحدة علوية ركنة'],
      'hood' => ['Hood unit', 'وحدة هود'], 'wardrobe' => ['Wardrobe', 'دولاب'], 'hinged' => ['Wardrobe – hinged', 'دولاب مفصلي'],
      'custom' => ['Custom layout', 'تصميم مخصص'], 'sliding' => ['Wardrobe – sliding', 'دولاب سحاب'], 'none' => ['Wardrobe – open', 'دولاب مفتوح']
    }.freeze

    module_function

    def type_name(type, lang = 'en')
      k = type.to_s
      if (n = TYPE_NAMES[k])
        return lang == 'ar' ? n[1] : n[0]
      end
      it = Mechanisms.item(k.upcase)
      it ? (lang == 'ar' ? it[:ar] : it[:en]) : nil
    end

    # what the appliance builder needs to know about a device record besides its size (the refrigerator type)
    def dev_cfg(dv, cfg)
      dv && dv[:style] ? cfg.merge('fridge_style' => dv[:style].to_s) : cfg
    end

    def device(id)
      DEVICES.find { |x| x[:id] == id.to_s } || sized_device(id) || hob_device(id)
    end

    # 'HOB_M_GAS_90' = the hob kind 'gas_90' of Kitchen::HOB_MODELS as a device record (generic size class, like every other device here)
    def hob_device(id)
      m = id.to_s.match(/\AHOB_M_(\w+)\z/)
      pr = m && Kitchen::HOB_MODELS[m[1].downcase]
      return nil unless pr

      base = DEVICES.find { |x| x[:id] == (pr[:kind] == 'hob_gas' ? 'HOB_GAS_60' : 'HOB_60') }
      base.merge(id: id.to_s, w: pr[:body][0], d: pr[:body][1], en: pr[:en], ar: pr[:ar])
    end

    # A refrigerator of the client's REAL width: 'FRIDGE_W700' = the generic refrigerator record with w = 700 mm (side-by-side body from 850 mm).
    # The id carries the size, so a saved model needs no extra data to rebuild / price / schedule it.
    def sized_device(id)
      m = id.to_s.match(/\AFRIDGE_(W|T)(\d{3,4})\z/) # W = bottom freezer (side by side from 850), T = top freezer
      return nil unless m

      w = m[2].to_i
      return nil unless w.between?(450, 1300)

      base = DEVICES.find { |x| x[:id] == (m[1] == 'T' ? 'FRIDGE_TOP' : (w >= 850 ? 'FRIDGE_SBS' : 'FRIDGE_TALL')) }
      base.merge(id: id.to_s, w: w, en: "Refrigerator #{w} mm", ar: "ثلاجة #{w} مم")
    end

    # Generic nominal profile only. Manufacturer-specific dimensions/ratings remain unset until supplied.
    def profile(id)
      d = device(id)
      return nil unless d

      services = case d[:kind]
                 when 'sink' then %w[CW HW D]
                 when 'dishwasher', 'washer' then %w[E CW D]
                 when 'hob_gas' then %w[E G]
                 when 'hood_chimney', 'hood_slim' then %w[E DU]
                 when 'wall_rail' then []
                 else %w[E]
                 end
      { 'id' => d[:id], 'type' => d[:kind], 'manufacturer' => nil, 'model' => nil,
        'nominal_dimensions_mm' => { 'w' => d[:w], 'h' => d[:h], 'd' => d[:d] },
        'body_dimensions_mm' => nil, 'opening_requirements_mm' => nil, 'installation_clearance_mm' => EGC::ApplianceClearances.installation_clearance_mm(d[:kind]),
        'countertop_cutout_mm' => nil, 'service_types' => services, 'electrical_specification' => nil,
        'cold_water_specification' => nil, 'hot_water_specification' => nil, 'drain_specification' => nil,
        'duct_specification' => nil, 'gas_specification' => nil, 'data_status' => 'GENERIC_NOMINAL / REQUIRES_CONFIRMATION',
        'family' => d[:kind], 'ventilation_mm' => nil, 'door_clearance_mm' => nil, 'mounting' => HOUSING[d[:id]] ? "built-in (#{HOUSING[d[:id]][1]} housing)" : 'free-standing / not housed',
        'source' => 'E.G.C generic family profile: nominal size class only, no manufacturer data', 'verification' => 'GENERIC / REQUIRES MODEL CONFIRMATION' }.merge(verified_profile(d[:id]) || {})
    end

    # A VERIFIED appliance profile is only ever data the user / supplier adds (never invented here): %APPDATA%/EGC_Builder/appliance_profiles/<DEVICE_ID>.json
    # with the manufacturer's values and its 'source'. Without a 'source' and 'verified_by' the file is ignored.
    def verified_profile(id)
      f = File.join(ENV['APPDATA'].to_s, 'EGC_Builder', 'appliance_profiles', "#{id}.json")
      return nil unless File.file?(f)

      h = JSON.parse(File.read(f, encoding: 'utf-8'))
      return nil if h['source'].to_s.strip.empty? || h['verified_by'].to_s.strip.empty?

      h.merge('verification' => "VERIFIED by #{h['verified_by']}", 'data_status' => 'VERIFIED')
    rescue StandardError
      nil
    end

    # device id => built-in housing unit (kind, type, width). Devices that are normally free-standing have none.
    HOUSING = {
      'OVEN_60' => ['base', 'oven', 600], 'COMPACT_45' => ['tall', 'oven_tall', 600], 'MICRO_38' => ['tall', 'microwave_tower', 600],
      'FRIDGE_TALL' => ['tall', 'fridge_open', 640], 'FRIDGE_SBS' => ['tall', 'fridge_open', 940], 'DISH_60' => ['base', 'dishwasher_bi', 600], 'DISH_45' => ['base', 'dishwasher_bi', 450],
      'WASHER_60' => ['base', 'washer_bi', 660], 'SINK_600' => ['base', 'sink', 600], 'SINK_800' => ['base', 'sink', 800],
      'HOB_60' => ['base', 'hob', 600], 'HOB_GAS_60' => ['base', 'hob', 600]
    }.freeze

    def devices_payload
      DEVICES.map do |x|
        h = HOUSING[x[:id]]
        x.transform_keys(&:to_s).merge('profile' => profile(x[:id]), 'housing' => h && { 'kind' => h[0], 'type' => h[1], 'w' => h[2] })
      end
    end

    # kind is a Geo material key ('front'/'carcass'/'drawer' -> boards, 'top'/'splash' -> worktops)
    def swatch(kind, id)
      list = %w[top splash].include?(kind.to_s) ? materials['worktops'] : materials['boards']
      list.find { |m| m['code'] == id.to_s }
    end

    def materials
      @materials ||= begin
        JSON.parse(File.read(File.join(DIR, 'assets', 'materials.json'), encoding: 'UTF-8'))
      rescue StandardError
        { 'boards' => [], 'worktops' => [] }
      end
    end

    # library types that can be placed as units (used for thumbnails / catalog)
    def units_payload
      out = []
      Library::BASE.each { |k, v| out << unit_row('base', k, v) }
      Library::TALL.each { |k, v| out << unit_row('tall', k, v) }
      Library::SLOT.each { |k, v| out << unit_row('slot', k, v) }
      (Library::WALL.keys + ['hood']).each { |k| out << unit_row('wall', k, Library::WALL[k] || { cells: [{ t: :hood }, { t: :doors }] }).merge('tier' => 1, 'cat' => 'upper1') }
      # UPPER 2 = its own family (H 500, D 600, Z 2200, groove 450): the same door variants, never a relabelled Upper 1
      Library::WALL.each { |k, v| out << unit_row('wall', k, v, 'wall2').merge('tier' => 2, 'cat' => 'upper2') }
      out
    end

    def thumb_path(name)
      rel = "assets/thumbs/#{name}"
      File.exist?(File.join(DIR, "#{rel}.png")) ? "#{rel}.png" : nil
    end

    def unit_row(kind, type, df, thumb_kind = nil)
      tk = thumb_kind || kind
      { 'kind' => kind, 'type' => type, 'img' => thumb_path("unit_#{tk}_#{type}_closed"), 'img_open' => thumb_path("unit_#{tk}_#{type}_open"),
        'cells' => (df[:cells] || []).map { |c| c.transform_keys(&:to_s).transform_values { |v| v.is_a?(Symbol) ? v.to_s : v } },
        'cutout' => df[:cutout].to_s }
    end
  end
end
