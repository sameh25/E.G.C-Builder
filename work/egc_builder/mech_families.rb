# frozen_string_literal: true

module EGC
  # E.G.C Mechanism Family Engine: a limited set of ORIGINAL generic families (not one model per product).
  # A family fixes the host rules, the motion profile and the shared parts it is made of; a catalog item
  # (Mechanisms::ITEMS) is a Variant of a family, and the builders derive the variant from the cabinet's
  # real clear dimensions (rail length, number of baskets, ...) instead of scaling geometry.
  module Families
    module_function

    # host_type, handedness, mounting_zone, front_dependency, required_removed_parts, motion_profile, min clear dims (mm)
    FAM = {
      'PULL_OUT_BASKET' => { en: 'Pull-out baskets & organisers', ar: 'سلال ومنظمات سحب', host: %w[base], hand: 'none',
                             zone: 'cabinet floor / side panels', front: 'attached front (own door front)', removed: %w[shelves],
                             profile: 'TELESCOPIC_SLIDE', min: { cw: 110, ch: 300, cd: 330 } },
      'TALL_LARDER' => { en: 'Tall larder / pantry', ar: 'مخزن طولي (Larder)', host: %w[tall], hand: 'none',
                         zone: 'floor + top guide', front: 'attached front or swing door', removed: %w[shelves],
                         profile: 'TELESCOPIC_SLIDE', min: { cw: 260, ch: 1200, cd: 430 } },
      'DISH_RACK' => { en: 'Dish racks', ar: 'حوامل أطباق', host: %w[wall base], hand: 'none',
                       zone: 'side panels', front: 'door or lift-up flap', removed: %w[shelves],
                       profile: 'LIFT', min: { cw: 520, ch: 500, cd: 290 } },
      'WASTE_PULL_OUT' => { en: 'Waste bins', ar: 'سلات مهملات', host: %w[base], hand: 'none',
                            zone: 'cabinet floor', front: 'attached front or swing door', removed: %w[shelves],
                            profile: 'TELESCOPIC_SLIDE', min: { cw: 260, ch: 380, cd: 420 } },
      'ROTATING_CAROUSEL' => { en: 'Rotating / carousel baskets', ar: 'سلال دوّارة / كاروسيل', host: %w[base], hand: 'LR',
                               zone: 'floor + top pole', front: 'hinged door', removed: %w[shelves],
                               profile: 'ROTATE', min: { cw: 640, ch: 500, cd: 480 } },
      'BLIND_CORNER' => { en: 'Blind corner (swing-out baskets)', ar: 'ركنة عمياء (سلال سحب)', host: %w[base], hand: 'LR',
                          zone: 'floor slides', front: 'hinged door (opening side)', removed: %w[shelves],
                          profile: 'CORNER_COMPOUND', min: { cw: 700, ch: 500, cd: 480 } },
      'DRAWER_FRONT' => { en: 'Drawers', ar: 'أدراج', host: %w[base tall], hand: 'none',
                          zone: 'side panels', front: 'own drawer fronts', removed: %w[shelves],
                          profile: 'TELESCOPIC_SLIDE', min: { cw: 200, ch: 200, cd: 330 } },
      'DRAWER_INTERNAL' => { en: 'Internal drawers', ar: 'أدراج داخلية', host: %w[base tall], hand: 'none',
                             zone: 'side panels', front: 'requires a hinged door', removed: %w[shelves],
                             profile: 'TELESCOPIC_SLIDE', min: { cw: 300, ch: 300, cd: 380 } },
      'SLIDING_FRONT' => { en: 'Sliding fronts', ar: 'واجهات سحاب', host: %w[base wall], hand: 'none',
                           zone: 'top + bottom track', front: 'own sliding leaves', removed: %w[shelves],
                           profile: 'LINEAR_SLIDE', min: { cw: 500, ch: 300, cd: 200 } },
      'LIFT_UP' => { en: 'Lift-up flap', ar: 'فلاب رفع', host: %w[wall], hand: 'none',
                     zone: 'side panels (upper)', front: 'own flap', removed: %w[],
                     profile: 'LIFT', min: { cw: 400, ch: 300, cd: 250 } },
      'FOLD_LIFT' => { en: 'Fold-lift (bi-fold) flap', ar: 'رفع وطي (بيفولد)', host: %w[wall], hand: 'none',
                       zone: 'side panels (upper)', front: 'two linked leaves', removed: %w[],
                       profile: 'FOLD_LIFT', min: { cw: 500, ch: 480, cd: 300 } },
      'TALL_NARROW' => { en: 'Narrow tall pull-outs', ar: 'سحب طولي ضيق', host: %w[tall], hand: 'none',
                         zone: 'floor + top slide', front: 'attached front', removed: %w[shelves],
                         profile: 'TELESCOPIC_SLIDE', min: { cw: 100, ch: 1200, cd: 430 } },
      'WORK_TABLE' => { en: 'Pull-out tables', ar: 'ترابيزات سحب', host: %w[base], hand: 'none',
                        zone: 'side panels / floor', front: 'attached front', removed: %w[shelves],
                        profile: 'TELESCOPIC_SLIDE', min: { cw: 360, ch: 500, cd: 430 } },
      'WARDROBE_PULL_OUT' => { en: 'Wardrobe pull-outs', ar: 'ملحقات دريسنج سحب', host: %w[tall], hand: 'none',
                               zone: 'side panels', front: 'attached rack front / rail', removed: %w[],
                               profile: 'TELESCOPIC_SLIDE', min: { cw: 400, ch: 700, cd: 400 } }
    }.freeze

    # catalog id => [family, variant label (en), variant label (ar)]
    OF = {
      'DRAWERS_SIDE' => ['DRAWER_FRONT', 'Side runners', 'مجرى جانبي'], 'DRAWERS_UNDER' => ['DRAWER_FRONT', 'Concealed runners', 'مجرى مخفي'],
      'CUTLERY' => ['DRAWER_FRONT', 'Cutlery trays', 'صواني أدوات مائدة'],
      'INNER_SIDE' => ['DRAWER_INTERNAL', 'Side runners', 'مجرى جانبي'], 'INNER_UNDER' => ['DRAWER_INTERNAL', 'Concealed runners', 'مجرى مخفي'],
      'PULLOUT_BASKET' => ['PULL_OUT_BASKET', 'Wire baskets', 'سلال سلك'], 'PULLOUT_BASKET_SWING' => ['PULL_OUT_BASKET', 'Behind hinged door', 'خلف باب مفصلي'], 'SPICE_PULLOUT' => ['PULL_OUT_BASKET', 'Spice', 'بهارات'],
      'TRAY_PULLOUT' => ['PULL_OUT_BASKET', 'Tray / bottles', 'صواني / زجاجات'], 'TROLLEY_3TIER' => ['PULL_OUT_BASKET', 'Trolley', 'ترولي'],
      'BOX_UNIT_2TIER' => ['PULL_OUT_BASKET', 'Open boxes', 'صناديق مفتوحة'], 'WIRE_DRAWER' => ['PULL_OUT_BASKET', 'Wire drawer', 'درج سلك'],
      'LAUNDRY_BAG' => ['PULL_OUT_BASKET', 'Laundry bag', 'كيس غسيل'], 'PLATE_GLASS_HOLDER' => ['PULL_OUT_BASKET', 'Plate & glass', 'أطباق وأكواب'],
      'PANTRY_PULL' => ['TALL_LARDER', 'Pull-out frame', 'إطار سحب'], 'VIDEO_M1_PANTRY_A' => ['TALL_LARDER', 'Swing door + sliding frame', 'باب مفصلي + إطار منزلق'],
      'VIDEO_M2_PANTRY_B' => ['TALL_LARDER', 'Swing door + fixed frame', 'باب مفصلي + إطار ثابت'],
      'DISH_RACK' => ['DISH_RACK', 'Behind door', 'خلف باب'], 'DISH_RACK_FLAP' => ['DISH_RACK', 'Flap + pull-down', 'فلاب + سحب لأسفل'],
      'DOOR_BIN' => ['WASTE_PULL_OUT', 'On the door', 'على الضلفة'], 'BROOM_PULLOUT' => ['TALL_NARROW', 'Broom column', 'ساحب مكنسة'],
      'CHEF_TABLE' => ['WORK_TABLE', 'Swing-out table', 'ترابيزة تتسحب لقدام'], 'PULL_TABLE' => ['WORK_TABLE', 'Table behind a drawer front', 'ترابيزة خلف وش درج'],
      'LIFT_BASKET' => ['DISH_RACK', 'Powered lift basket', 'رف كهربائي نازل'], 'LEMANS' => ['BLIND_CORNER', 'Swing-out trays, right', 'صواني دوارة يمين'], 'LEMANS_L' => ['BLIND_CORNER', 'Swing-out trays, left', 'صواني دوارة يسار'],
      'IMOVE_SINGLE_600' => ['DISH_RACK', 'Pull-down single tray 600', 'رف مفرد سحب لأسفل 600'], 'IMOVE_SINGLE_900' => ['DISH_RACK', 'Pull-down single tray 900', 'رف مفرد سحب لأسفل 900'],
      'WASTE_BINS' => ['WASTE_PULL_OUT', 'Pull-out (1-2 bins)', 'سحب (سلة أو اثنتين)'], 'VIDEO_M6_SINGLE_BIN' => ['WASTE_PULL_OUT', 'Swing door + sliding bin', 'باب مفصلي + سلة منزلقة'],
      'CAROUSEL' => ['ROTATING_CAROUSEL', 'Full round', 'دائري كامل'], 'CAROUSEL_34' => ['ROTATING_CAROUSEL', '3/4 turning', 'دوار 3/4'],
      'MAGIC_CORNER' => ['BLIND_CORNER', 'Blind corner baskets - right', 'ركنة عمياء بسلال - يمين'], 'MAGIC_CORNER_L' => ['BLIND_CORNER', 'Blind corner baskets - left', 'ركنة عمياء بسلال - يسار'],
      'SLIDE_SINGLE' => ['SLIDING_FRONT', '1 leaf', 'ضلفة'], 'SLIDE_DOUBLE' => ['SLIDING_FRONT', '2 leaves', 'ضلفتين'],
      'SLIDE_TRIPLE' => ['SLIDING_FRONT', '3 leaves', '3 ضلف'], 'SLIDE_BYPASS' => ['SLIDING_FRONT', 'Bypass', 'بايباس'],
      'LIFT_UP' => ['LIFT_UP', 'Single flap + arms', 'فلاب واحد + أذرع'],
      'BIFOLD_REF' => ['FOLD_LIFT', 'Bi-fold lift, reference linkage', 'رفع بيفولد بوصلات مرجعية'], 'IMOVE_DOUBLE_600' => ['DISH_RACK', 'Pull-down double tray', 'رف مزدوج سحب لأسفل'],
      'AVENTOS_HF' => ['FOLD_LIFT', 'Bi-fold lift (generic)', 'رفع وطي بضلفتين (عام)'],
      'TROUSER_RACK' => ['WARDROBE_PULL_OUT', 'Trouser rack', 'حامل بناطيل'], 'WARDROBE_LIFT_RAIL' => ['WARDROBE_PULL_OUT', 'Pull-down rail', 'ماسورة سحب لأسفل']
    }.freeze

    # small per-family stretch on top of the motion profile duration
    DURATION_MULT = { 'PULL_OUT_BASKET' => 1.0, 'TALL_LARDER' => 1.15, 'DISH_RACK' => 1.05, 'WASTE_PULL_OUT' => 1.0, 'ROTATING_CAROUSEL' => 1.0,
                      'BLIND_CORNER' => 1.0, 'FOLD_LIFT' => 1.0, 'LIFT_UP' => 1.0 }.freeze

    def duration_multiplier(id)
      DURATION_MULT[family_of(id)] || 1.0
    end

    def family_of(id)
      OF[id.to_s]&.first
    end

    def info(id)
      f = family_of(id)
      f && FAM[f]
    end

    # per-item requirement (nominal cabinet width the variant is designed for) on top of the family minimum
    # LEMANS: supplier planning table of the door-600 variant. CHEF_TABLE: supplier drawing (clear width 362-568, depth >= 480, height >= 535).
    ITEM_MIN = {
      'DOOR_BIN' => { cw: 330 }, 'LEMANS' => { cw: 960, ch: 600, cd: 500 }, 'LEMANS_L' => { cw: 960, ch: 600, cd: 500 }, 'CHEF_TABLE' => { cw: 362, ch: 535, cd: 480 }, 'LIFT_BASKET' => { cw: 560 }, 'PULL_TABLE' => { cw: 560 },
      'IMOVE_SINGLE_600' => { cw: 562 }, 'IMOVE_SINGLE_900' => { cw: 862 }, # clear inside width the tray set is made for (supplier drawing: 562-568 / 862-868)
      'SPICE_PULLOUT' => { cw: 110 }, 'PULLOUT_BASKET' => { cw: 110 }, 'TRAY_PULLOUT' => { cw: 110 }, 'WASTE_BINS' => { cw: 260 },
      'VIDEO_M6_SINGLE_BIN' => { cw: 260 }, 'LAUNDRY_BAG' => { cw: 380 }, 'PLATE_GLASS_HOLDER' => { cw: 380 },
      'TROLLEY_3TIER' => { cw: 260 }, 'MAGIC_CORNER' => { cw: 760 }, 'MAGIC_CORNER_L' => { cw: 760 }, 'CAROUSEL' => { cw: 780 },
      'CAROUSEL_34' => { cw: 780 }
    }.freeze

    # upper limits published for a variant (clear inside sizes)
    ITEM_MAX = { 'CHEF_TABLE' => { cw: 568 }, 'LEMANS' => { ch: 900 }, 'LEMANS_L' => { ch: 900 } }.freeze

    # clear inside sizes an item needs / may not exceed (what the library card shows and #fit enforces)
    def limits(id)
      fam = info(id)
      { min: ((fam && fam[:min]) || {}).merge(ITEM_MIN[id.to_s] || {}).transform_keys(&:to_s), max: (ITEM_MAX[id.to_s] || {}).transform_keys(&:to_s) }
    end

    # Real clear (inside) dimensions of the host the mechanism goes into.
    def clear_dims(kind, w, h, d, cfg, plinth = nil)
      t = cfg['thk'].to_f
      pl = plinth.nil? ? (kind.to_s == 'wall' ? 0.0 : cfg['plinth'].to_f) : plinth.to_f
      top = kind.to_s == 'base' ? cfg['top_thk'].to_f : 0.0
      { cw: w.to_f - 2 * t, ch: h.to_f - pl - top - 2 * t, cd: d.to_f - cfg['front_thk'].to_f - cfg['back_thk'].to_f }
    end

    # -> { ok:, reasons: [...], suggest: {...}, clear:, req:, family:, envelope: }
    def fit(id, kind, w, h, d, cfg, plinth = nil)
      it = Mechanisms.item(id)
      fam = info(id)
      return { ok: true, reasons: [], clear: {}, req: {} } unless it && fam

      clear = clear_dims(kind, w, h, d, cfg, plinth)
      req = fam[:min].merge(ITEM_MIN[id.to_s] || {})
      reasons = []
      reasons << "host #{kind} not allowed (needs #{fam[:host].join('/')})" unless fam[:host].include?(kind.to_s)
      { cw: 'clear width', ch: 'clear height', cd: 'clear depth' }.each do |k, label|
        reasons << "#{label} #{clear[k].round} < #{req[k]} mm" if clear[k] < req[k]
        mx = (ITEM_MAX[id.to_s] || {})[k]
        reasons << "#{label} #{clear[k].round} > #{mx} mm" if mx && clear[k] > mx
      end
      out = { ok: reasons.empty?, reasons: reasons, clear: clear, req: req, family: OF[id.to_s][0] }
      out[:suggest] = suggest(id, kind, clear, req, cfg, w) unless out[:ok]
      out[:envelope] = envelope(id, clear)
      out
    end

    def suggest(id, kind, clear, req, cfg, w)
      s = []
      s << "widen the unit to at least #{(w.to_f + req[:cw] - clear[:cw]).ceil} mm" if clear[:cw] < req[:cw]
      alt = Mechanisms::ITEMS.select { |x| x[:id] != id && family_of(x[:id]) == family_of(id) }
                            .select { |x| kind.to_s == x[:host] && (ITEM_MIN[x[:id]] || {}).fetch(:cw, FAM[family_of(x[:id])][:min][:cw]) <= clear[:cw] }
      s << "variants that fit: #{alt.first(3).map { |x| x[:id] }.join(', ')}" unless alt.empty?
      mx = ITEM_MAX[id.to_s] || {}
      s << "narrow the unit to at most #{(w.to_f - clear[:cw] + mx[:cw]).floor} mm" if mx[:cw] && clear[:cw] > mx[:cw]
      s << 'use a deeper unit' if clear[:cd] < req[:cd]
      s << 'use a taller unit' if clear[:ch] < req[:ch]
      s
    end

    # travel / swing the moving parts need in FRONT of the unit (mm)
    def envelope(id, clear)
      it = Mechanisms.item(id)
      case family_of(id)
      when 'PULL_OUT_BASKET', 'WASTE_PULL_OUT', 'TALL_LARDER', 'DRAWER_FRONT', 'DRAWER_INTERNAL', 'WARDROBE_PULL_OUT'
        { front_travel: [[clear[:cd] * 0.9, 550].min, 200].max.round }
      when 'BLIND_CORNER', 'ROTATING_CAROUSEL' then { front_travel: (clear[:cd] * 0.85).round, door_swing: (clear[:cw] * 0.5).round }
      when 'LIFT_UP', 'FOLD_LIFT' then { above: (it ? clear[:ch] : 0).round }
      else {}
      end
    end

    def check!(id, kind, w, h, d, cfg, plinth = nil)
      res = fit(id, kind, w, h, d, cfg, plinth)
      raise message(id, res) unless res[:ok]

      res
    end

    def message(id, res)
      "#{id}: #{res[:reasons].join('; ')}. #{(res[:suggest] || []).join('; ')}"
    end

    # what the UI / docs show for a family
    def describe(id, kind, w, h, d, cfg, plinth = nil)
      f = info(id)
      return nil unless f

      r = fit(id, kind, w, h, d, cfg, plinth)
      { family: family_of(id), host_type: f[:host], handedness: f[:hand], mounting_zone: f[:zone], front_dependency: f[:front],
        required_removed_parts: f[:removed], motion_profile: f[:profile], clear_width: r[:clear][:cw]&.round,
        clear_height: r[:clear][:ch]&.round, clear_depth: r[:clear][:cd]&.round, motion_envelope: r[:envelope], fit: r[:ok] }
    end
  end
end
