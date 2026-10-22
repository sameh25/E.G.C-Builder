# frozen_string_literal: true

require 'json'

module EGC
  # Mechanism library: real cabinet-contained assemblies with open/close motion.
  # Every moving assembly is a sub-group tagged with an 'egc/move' attribute:
  #   { 'type'=>'lin', 'v'=>[dx,dd,dz] }                       (builder space, mm, at fully open)
  #   { 'type'=>'rot', 'pivot'=>[x,d,z], 'axis'=>[..], 'deg'=>a } (axis in builder space)
  #   optional 'phase'=>[t0,t1] so several parts open one after the other.
  module Mechanisms
    IMG = 'assets/mech'

    def self.i(id, cat, en, ar, host, w, mb, o = {})
      img = o.delete(:img) || id
      { id: id, cat: cat, en: en, ar: ar, host: host, w: w, mb: mb, o: o, img: "#{IMG}/#{img}.jpg" }
    end

    ITEMS = [
      i('DRAWERS_SIDE', 'drawers', 'Drawers – side telescopic runners', 'أدراج – مجرى جانبي تلسكوبي', 'base', 600, :drawers, n: 3, nr: [1, 2, 3, 4], img: 'DRAWER_SIDE_{n}'),
      i('DRAWERS_UNDER', 'drawers', 'Drawers – concealed (undermount) runners', 'أدراج – مجرى مخفي', 'base', 600, :drawers, n: 3, nr: [1, 2, 3, 4], style: :under, img: 'DRAWER_CON_{n}'),
      i('INNER_SIDE', 'inner', 'Inner drawers behind doors – side runners', 'أدراج داخلية خلف باب – جانبي', 'base', 600, :inner, n: 3, nr: [2, 3], img: 'INNER_SIDE_{n}'),
      i('INNER_UNDER', 'inner', 'Inner drawers behind doors – concealed', 'أدراج داخلية خلف باب – مخفي', 'base', 600, :inner, n: 3, nr: [2, 3], style: :under, img: 'INNER_CON_{n}'),

      i('PULLOUT_BASKET', 'pullouts', 'Wire basket pull-out', 'سلة سلك سحب', 'base', 400, :pullout, item: :wire, levels: 2, key: 'basket_set'),
      i('PULLOUT_BASKET_SWING', 'pullouts', 'Wire basket pull-out behind hinged door', 'سلة سلك خلف باب مفصلي', 'base', 450, :pullout, item: :wire, levels: 3, mode: :swing, key: 'basket_set'),
      i('SPICE_PULLOUT', 'pullouts', 'Spice pull-out', 'سحب بهارات', 'base', 200, :pullout, item: :spice, levels: 4, key: 'spice_rack'),
      i('TRAY_PULLOUT', 'pullouts', 'Tray / bottle pull-out', 'سحب صواني / زجاجات', 'base', 300, :pullout, item: :tray, key: 'tray_rack'),
      i('WASTE_BINS', 'pullouts', 'Waste bin pull-out', 'سحب سلة مهملات', 'base', 450, :waste, key: 'waste_bin'),
      i('PANTRY_PULL', 'pullouts', 'Tall pantry pull-out', 'مخزن طولي سحب', 'tall', 400, :larder, levels: 5, key: 'pantry_pullout'),
      i('TROLLEY_3TIER', 'pullouts', 'Trolley – 3-tier wire', 'ترولي 3 أدوار سلك', 'base', 300, :pullout, item: :trolley, levels: 3, key: 'trolley'),
      i('BOX_UNIT_2TIER', 'pullouts', 'Box unit – 2 open boxes', 'وحدة صناديق مفتوحة × 2', 'base', 450, :pullout, item: :box, levels: 2, key: 'box_unit'),
      i('WIRE_DRAWER', 'pullouts', 'Wire drawer (undermount rail)', 'درج سلك على مجرى مخفي', 'base', 450, :pullout, item: :wire, levels: 1, key: 'wire_drawer'),
      i('LAUNDRY_BAG', 'pullouts', 'Laundry bag pull-out', 'سحب كيس غسيل', 'base', 450, :pullout, item: :laundry, key: 'laundry_bag'),
      i('PLATE_GLASS_HOLDER', 'pullouts', 'Plate & glass holder', 'حامل أطباق وأكواب', 'base', 450, :pullout, item: :plate, key: 'plate_holder'),
      i('VIDEO_M1_PANTRY_A', 'pullouts', 'Pantry – swing door + sliding frame', 'مخزن – باب مفصلي + إطار منزلق', 'tall', 450, :larder, levels: 5, mode: :swing, frame: :slide, key: 'pantry_pullout'),
      i('VIDEO_M2_PANTRY_B', 'pullouts', 'Pantry – swing door + fixed frame', 'مخزن – باب مفصلي + إطار ثابت', 'tall', 450, :larder, levels: 6, mode: :swing, key: 'pantry_fixed'),
      i('VIDEO_M6_SINGLE_BIN', 'pullouts', 'Single bin behind swing door', 'سلة مهملات خلف باب', 'base', 400, :waste, mode: :swing, key: 'waste_bin'),

      i('SLIDE_SINGLE', 'sliding', 'Sliding front – single', 'واجهة سحاب – مفردة', 'base', 600, :sliding, n: 1),
      i('SLIDE_DOUBLE', 'sliding', 'Sliding front – double', 'واجهة سحاب – مزدوجة', 'base', 800, :sliding, n: 2),
      i('SLIDE_TRIPLE', 'sliding', 'Sliding front – triple', 'واجهة سحاب – ثلاثية', 'base', 900, :sliding, n: 3),
      i('SLIDE_BYPASS', 'sliding', 'Sliding front – bypass', 'واجهة سحاب – بايباس', 'base', 1200, :sliding, n: 2, tracks: 2),

      i('AVENTOS_HF', 'wall', 'E.G.C Bi-Fold Lift (generic)', 'رفع بيفولد E.G.C (عام)', 'wall', 900, :foldlift),
      i('BIFOLD_REF', 'wall', 'Bi-fold lift - reference linkage (800 x 560)', 'رفع بيفولد - وصلات مرجعية (800 × 560)', 'wall', 800, :bifold_ref, fix: { h: 560.0, cd: 320.0 }, img: 'AVENTOS_HF'),
      i('IMOVE_DOUBLE_600', 'wall', 'Pull-down double tray 600 (iMove type)', 'رف مزدوج سحب لأسفل 600 (نوع iMove)', 'wall', 600, :imove, fix: { h: 710.0, cd: 322.0 }, key: 'imove_double_tray', img: 'DISH_RACK'),
      i('IMOVE_SINGLE_600', 'wall', 'Pull-down single tray 600 (iMove type)', 'رف مفرد سحب لأسفل 600 (نوع iMove)', 'wall', 600, :dish, flap: true, tray: true, hw: 'imove_single_tray', img: 'DISH_RACK'),
      i('IMOVE_SINGLE_900', 'wall', 'Pull-down single tray 900 (iMove type)', 'رف مفرد سحب لأسفل 900 (نوع iMove)', 'wall', 900, :dish, flap: true, tray: true, hw: 'imove_single_tray', img: 'DISH_RACK'),
      i('LIFT_UP', 'wall', 'Lift-up flap with articulated arms', 'فلاب رفع بأذرع', 'wall', 800, :lift),
      i('DISH_RACK', 'wall', 'Wall dish rack', 'رف أطباق علوي', 'wall', 600, :dish),
      i('DISH_RACK_FLAP', 'wall', 'Dish rack – flap + pull-down', 'رف أطباق – فلاب + سحب لأسفل', 'wall', 800, :dish, flap: true),

      i('DOOR_BIN', 'pullouts', 'Waste bin on the door', 'سلة مهملات على الضلفة', 'base', 450, :doorbin, key: 'door_bin', img: 'WASTE_BINS'),
      i('BROOM_PULLOUT', 'pullouts', 'Broom / cleaning pull-out column 15', 'ساحب مكنسة وأدوات نظافة 15', 'tall', 150, :broom, key: 'broom_pullout', img: 'PANTRY_PULL'),
      i('CHEF_TABLE', 'pullouts', 'Swing-out work table (ChefsTable type, units 400-600)', 'ترابيزة شغل تتسحب لقدام (نوع ChefsTable، وحدات 40-60)', 'base', 600, :cheftable, key: 'chef_table', img: 'TRAY_PULLOUT'),
      i('PULL_TABLE', 'pullouts', 'Pull-out table behind a drawer front 90', 'ترابيزة سحب خلف وش درج 90', 'base', 900, :pulltable, key: 'table_pullout', img: 'TRAY_PULLOUT'),
      i('LIFT_BASKET', 'wall', 'Powered lift basket 90 (comes down out of the unit)', 'رف كهربائي نازل من الوحدة 90', 'wall', 900, :liftbasket, key: 'electric_lift', open_bottom: true, img: 'DISH_RACK'),
      i('LEMANS', 'corners', 'Blind corner swing-out trays - right (LeMans II type, door 600 / unit 1000)', 'ركنة عمياء بصواني دوارة - يمين (نوع LeMans II، ضلفة 60 / وحدة 100)', 'base', 1000, :lemans, blind: 'right', variant: '600', key: 'lemans_set', img: 'MAGIC_CORNER'),
      i('LEMANS_L', 'corners', 'Blind corner swing-out trays - left (LeMans II type, door 600 / unit 1000)', 'ركنة عمياء بصواني دوارة - يسار (نوع LeMans II، ضلفة 60 / وحدة 100)', 'base', 1000, :lemans, blind: 'left', variant: '600', key: 'lemans_set', img: 'MAGIC_CORNER'),
      i('CUTLERY', 'accessories', 'Cutlery tray drawers', 'أدراج بصينية أدوات مائدة', 'base', 600, :cutlery, key: 'cutlery_tray'),

      i('CAROUSEL', 'corners', 'Corner carousel', 'كاروسيل ركنة', 'base', 900, :carousel, shape: :full, levels: 2),
      i('CAROUSEL_34', 'corners', 'Turning baskets 3/4', 'سلال دوارة 3/4', 'base', 900, :carousel, shape: :three_quarter, levels: 2),
      i('MAGIC_CORNER', 'corners', 'Blind corner baskets - right', 'ركنة عمياء بسلال - يمين', 'base', 1200, :magic, blind: 'right'),
      i('MAGIC_CORNER_L', 'corners', 'Blind corner baskets - left', 'ركنة عمياء بسلال - يسار', 'base', 1200, :magic, blind: 'left'),

      i('TROUSER_RACK', 'wardrobe', 'Trouser rack pull-out', 'حامل بناطيل سحب', 'tall', 600, :trouser, key: 'trouser_rack'),
      i('WARDROBE_LIFT_RAIL', 'wardrobe', 'Hydraulic pull-down rail', 'ماسورة هيدروليك سحب لأسفل', 'tall', 900, :liftrail, key: 'pulldown_rail')
    ].freeze

    CATEGORIES = %w[drawers inner pullouts sliding doors wall accessories corners wardrobe].freeze

    module_function

    # Verification status of a mechanism model: GENERIC (E.G.C linkage, correct for the type) / REFERENCE_BASED (uses published planning rules) /
    # MANUFACTURER_VERIFIED (matched to a manufacturer drawing set - none yet) / UNVERIFIED. Nothing here claims brand conformity.
    VERIFICATION = { 'AVENTOS_HF' => 'REFERENCE_BASED', 'MAGIC_CORNER' => 'GENERIC REFERENCE-BASED MECHANISM', 'MAGIC_CORNER_L' => 'GENERIC REFERENCE-BASED MECHANISM',
                     'LEMANS' => 'REFERENCE REQUIRED', 'LEMANS_L' => 'REFERENCE REQUIRED' }.freeze # planning sizes from the supplier sheet; arm linkage and tray outline are not the manufacturer's

    def verification(id)
      VERIFICATION[id.to_s] || 'GENERIC'
    end

    def item(id)
      ITEMS.find { |x| x[:id] == id.to_s }
    end

    # Portable generic profile metadata; no manufacturer drilling pattern is implied.
    def profile(id)
      x = item(id)
      return nil unless x

      { 'id' => x[:id], 'type' => x[:cat], 'manufacturer' => nil, 'model' => nil,
        'host' => x[:host], 'nominal_width_mm' => x[:w], 'geometry_profile' => x[:mb].to_s,
        'parameters' => JSON.parse(JSON.generate(x[:o])), 'verification' => verification(id),
        'drilling_status' => 'REQUIRES MECHANISM SPECIFICATION', 'data_status' => 'GENERIC / NOT MANUFACTURER CERTIFIED' }
    end

    def real_thumb?(x)
      (x[:o][:nr] || [nil]).all? do |n|
        File.exist?(File.join(DIR, 'assets', 'thumbs', "mech_#{x[:id]}#{n ? "_n#{n}" : ''}_closed.png"))
      end
    end

    def payload
      ITEMS.map { |x| fam = Families.family_of(x[:id]); fi = fam && Families::FAM[fam]; ve = Families::OF[x[:id]]; { 'fam' => fam, 'famEn' => fi && fi[:en], 'famAr' => fi && fi[:ar], 'varEn' => ve && ve[1], 'varAr' => ve && ve[2], 'real' => real_thumb?(x), 'thumb' => "assets/thumbs/mech_#{x[:id]}#{x[:o][:nr] ? '_n{n}' : ''}", 'verify' => verification(x[:id]), 'req' => Families.limits(x[:id])[:min], 'max' => Families.limits(x[:id])[:max], 'id' => x[:id], 'cat' => x[:cat], 'en' => x[:en], 'ar' => x[:ar], 'host' => x[:host], 'w' => x[:w], 'img' => x[:img], 'n' => x[:o][:n], 'nr' => x[:o][:nr] } }
    end

    # ---- motion ------------------------------------------------------------
    def phase(m, t)
      p0, p1 = m['phase'] || [0.0, 1.0]
      return 0.0 if t <= p0
      return 1.0 if t >= p1

      (t - p0) / (p1 - p0)
    end

    # NOTE: this module_function copy of move_transform is shadowed at runtime - mech_motion.rb reopens
    # Mechanisms' singleton class (`class << self`) with its own move_transform, loads after this file, and
    # every internal call from a `Mechanisms.*` singleton method (set_state included) resolves through the
    # singleton class, so mech_motion.rb's version is what actually runs. The 'hinge_arm' move type is
    # implemented there (hinge_arm_transform), not here.
    def move_transform(m, t)
      tt = phase(m, t)
      if m['type'] == 'lin'
        v = m['v']
        Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(v[0] * tt), -Geo.mm(v[1] * tt), Geo.mm(v[2] * tt)))
      else
        pv = m['pivot']
        ax = m['axis']
        Geom::Transformation.rotation(Geo.p3(pv[0], pv[1], pv[2]), Geom::Vector3d.new(ax[0], -ax[1], ax[2]),
                                      (m['deg'].to_f * tt).degrees)
      end
    end

    def collect(list, acc = [])
      list.each do |e|
        next unless e.is_a?(Sketchup::Group)

        acc << e if e.get_attribute('egc', 'move')
        collect(e.entities.to_a, acc)
      end
      acc
    end

    # t in 0..1 applied to all moving assemblies inside the given entities
    def set_state(list, t)
      t = [[t.to_f, 0.0].max, 1.0].min
      isolate_motion(list)
      open_all(list).each do |g|
        m = JSON.parse(g.get_attribute('egc', 'move'))
        g.transformation = move_transform(m, t)
      end
    end

    # the moving assemblies an "open / close all" of these units drives: without the drawers marked all_skip (and the runner members
    # linked to them) unless that drawer itself is what was asked for
    def open_all(list)
      all = collect(list)
      skip = all.select { |g| g.get_attribute('egc', 'all_skip') && !list.include?(g) }.map(&:name)
      return all if skip.empty?

      all.reject { |g| skip.include?(g.name) || skip.include?(g.get_attribute('egc', 'link').to_s) }
    end

    # A unique cabinet can still contain shared nested folding-door groups.
    # Detach each moving branch before changing its children so copies stay independent.
    def isolate_motion(list)
      list.grep(Sketchup::Group).each do |g|
        next if collect([g]).empty?

        g.make_unique if g.definition.instances.length > 1
        isolate_motion(g.entities.to_a)
      end
    end
  end

  # Builder methods mixed into Cabinet (they use its instance state).
  module MechBuilders
    # front span (doors/drawer fronts) and inner span (shelves, drawer boxes) of the current column;
    # the whole cabinet when the cell is not split into columns (see Cabinet#columns)
    def cx0; @fx0 || 0.0; end
    def cw; @fw || @w; end
    def ix0; @sx0 || @t; end
    def ix1; @sx1 || (@w - @t); end

    def asm(name, move = nil)
      g = (@cur || @e).add_group
      g.name = "#{@name}_#{name}"
      g.set_attribute('egc', 'move', JSON.generate(move)) if move
      g
    end

    def in_asm(g)
      old = @cur
      @cur = g.entities
      keepalive = @cur.add_cpoint(Geom::Point3d.new(0, 0, 0))
      raise 'Could not initialize mechanism assembly entities' unless keepalive&.valid?

      yield
    ensure
      keepalive.erase! if keepalive&.valid?
      @cur = old
    end

    HINGE_OPEN_DEG = 90.0

    def door_move(k, n, x, dw, zf, hf, flap)
      if flap
        return { 'type' => 'rot', 'pivot' => [x + dw / 2.0, @cd + @ft, zf + hf], 'axis' => [1, 0, 0], 'deg' => -100 }
      end

      left = hinge_side(k, n)[0]
      # doors open square (90 degrees) - the owner's decision for this tool; a 110 degree hinge is simply stopped at 90
      mv = { 'type' => 'rot', 'pivot' => [left ? x : x + dw, @cd + @ft, 0], 'axis' => [0, 0, 1], 'deg' => left ? -HINGE_OPEN_DEG : HINGE_OPEN_DEG }
      mv['phase'] = @door_phase if @door_phase
      mv['slide'] = door_slide if door_slide
      mv
    end

    DOOR_OPEN_GAP = 3.0 # mm between the hinge-side edge of a door opened square and the carcass front

    # how far the turning door is drawn back toward the carcass (see Mechanisms.rot_tr 'slide'); only with the concealed hinge modelled on it
    def door_slide
      return nil unless respond_to?(:sample_hinge?, true) && sample_hinge? && @ft > DOOR_OPEN_GAP

      [0, -(@ft - DOOR_OPEN_GAP), 0]
    end

    def hb(part, x, d, z, sx, sd, sz, mat = 'appliance', move = nil)
      pn(part, x, d, z, sx, sd, sz, mat, role: 'hw')
    end

    # ---- realistic hardware geometry ---------------------------------------
    def cyl(part, cx, cd0, z, r, len, axis = :z, mat = 'appliance')
      solid = lambda do |ents|
        n = axis == :z ? Geom::Vector3d.new(0, 0, 1) : Geom::Vector3d.new(0, 1, 0)
        f = ents.add_face(ents.add_circle(Geom::Point3d.new(0, 0, 0), n, Geo.mm(r), 20))
        next unless f

        sign = axis == :z ? (f.normal.z >= 0 ? 1 : -1) : (f.normal.y <= 0 ? 1 : -1)
        f.pushpull(sign * Geo.mm(len))
      end
      Panel.add(@cur || @e, @name, part, cx, cd0, z, 2 * r, axis == :z ? 2 * r : len, axis == :z ? len : 2 * r, mat, @c,
                role: 'hw', solid: solid)
    end

    def hinge_zs(z, h)
      n = hinge_count(h)
      bot = z + 100
      top = z + h - 100
      # with the upright front strip the top hinge sits below it (its arm reaches the carcass front edge, where the strip stands)
      top = [top, @z0 + @hc - @t - front_strip_h - 30.0].min if respond_to?(:front_strip?, true) && front_strip?
      return [bot, top] if n <= 2

      Array.new(n) { |i| bot + (top - bot) * i / (n - 1.0) }
    end

    def hinge_abs(k, n, x, dw, zf, hf)
      left, = hinge_side(k, n)
      x_e = left ? x : x + dw
      xc = left ? x_e + 21.5 : x_e - 21.5
      hinge_zs(zf, hf).map { |zc| [xc, zc] }
    end

    def hinge_side(k, n)
      left = n == 1 ? @s.to_h[:hand].to_s != 'R' : k < n / 2.0
      [left, (left && k.zero?) || (!left && k == n - 1)]
    end

    # cup + body: built inside the door assembly so they move rigidly with the door.
    def door_hinges(k, n, x, dw, zf, hf)
      left, = hinge_side(k, n)
      x_e = left ? x : x + dw
      xc = left ? x_e + 21.5 : x_e - 21.5
      hinge_zs(zf, hf).each { |zc| MechParts.cup_hinge(@cur || @e, xc, @cd, zc, left ? :left : :right) }
    end

    # Mounting plate stays on the carcass side panel (outer hinges only - the ones that actually reach
    # a side panel). The arm + pivot pin are built alongside it, as their OWN independently-animated
    # assembly (see hinge_arm_transform): the arm stays anchored to this fixed plate and re-aims to the
    # cup's current position every frame, instead of swinging rigidly with the door - so the two hinge
    # halves never visibly separate as the door opens. Always called at the cabinet's own (non-moving)
    # level, same as the plate always was, so no manual @cur juggling is needed.
    def door_plates(k, n, x, dw, zf, hf)
      left, outer = hinge_side(k, n)
      return unless outer

      xs = left ? ix0 : ix1
      x_e = left ? x : x + dw
      xc = left ? x_e + 21.5 : x_e - 21.5
      plate_x = left ? xs + 1.5 : xs - 1.5
      plate_d = @cd - 22
      dmove = door_move(k, n, x, dw, zf, hf, false)
      hinge_zs(zf, hf).each_with_index do |zc, i|
        MechParts.hinge_mount_plate(@e, left ? xs : xs - 3, @cd - 44, zc - 21)
        # two articulated links of constant length; the elbow is solved per frame (Mechanisms.hinge_ik_tr).
        # Length: just long enough to span plate -> cup over the whole opening (max distance x 1.06 / 2 each).
        dv = Geom::Vector3d.new(dmove['axis'][0], -dmove['axis'][1], dmove['axis'][2])
        pp = Geo.p3(plate_x, plate_d, zc)
        cup0 = Geo.p3(xc, @cd, zc)
        dmax = (0..10).map do |s|
          c = Geom::Transformation.rotation(Geo.p3(*dmove['pivot']), dv, (dmove['deg'].to_f * s / 10.0).degrees) * cup0
          Math.hypot((c.x - pp.x).to_mm, (c.y - pp.y).to_mm)
        end.max
        ll = [dmax * 0.53, 14.0].max
        # elbow bulges toward the cabinet interior (+x for a left hinge, -x for a right hinge)
        side = left ? -1.0 : 1.0
        2.times do |li|
          spec = { 'type' => 'hinge_ik', 'link' => li, 'plate' => [plate_x, plate_d, zc], 'cup' => [xc, @cd, zc],
                   'l1' => ll, 'l2' => ll, 'side' => side, 'dpivot' => dmove['pivot'], 'daxis' => dmove['axis'],
                   'ddeg' => dmove['deg'], 'phase' => dmove['phase'] }
          a = asm("hinge_arm#{k}_#{i}_l#{li}", spec)
          in_asm(a) { MechParts.hinge_link(a.entities, ll, li) }
          # not identity at t=0 (unlike other move types), so pose once at build time
          a.transformation = Mechanisms.hinge_ik_tr(spec, 0.0)
        end
      end
    end

    # 3-part telescopic side runners (fixed + intermediate + drawer member)
    def runners_side(_bx, d0, slide, rz, travel, xl = @t, xr = @w - @t)
      moving = @cur
      @cur = nil
      slide_fixed_mid(xl, xr, d0, rz + 4, slide, travel)
      @cur = moving
      slide_inner(xl, xr, d0, rz + 4, slide)
    end

    # concealed (undermount) runners under the drawer sides
    def runners_under(bx, bw, d0, slide, bz, travel)
      moving = @cur
      @cur = nil
      xr = ix1
      hb('runner_under_fixed', ix0, d0 + 20, bz - 14, 16, slide - 40, 6)
      hb('runner_under_fixed', xr - 16, d0 + 20, bz - 14, 16, slide - 40, 6)
      @cur = moving
      hb('runner_under_drawer', ix0 + 10, d0 + 10, bz - 8, 20, slide - 30, 6)
      hb('runner_under_drawer', xr - 30, d0 + 10, bz - 8, 20, slide - 30, 6)
      hb('runner_lock', bx + 6, d0 + slide - 40, bz - 8, 14, 30, 22)
      hb('runner_lock', bx + bw - 20, d0 + slide - 40, bz - 8, 14, 30, 22)
    end

    def legs
      return if @plinth <= 0 || @s[:floor]

      xs = @w > 800 ? [40, @w / 2.0, @w - 40] : [40, @w - 40]
      ds = [@bk + 40, @cd - 60]
      xs.each do |x|
        ds.each do |d|
          cyl('leg', x, d, 0, 15, @plinth, :z)
          cyl('leg_base', x, d, 0, 26, 4, :z, 'profile')
        end
      end
    end

    def bnd
      { x0: @t + 3, x1: @w - @t - 3, d0: @bk + 12, d1: @cd - 25,
        z0: @z0 + (@kind == :hood ? 0 : @t) + 12, z1: @z0 + @hc - @t - 10 }
    end

    def full_front
      [@z0 + @gap / 2.0, @hc - @gap - front_drop]
    end

    def mech_build(id)
      it = Mechanisms.item(id)
      raise "Unknown mechanism #{id}" unless it

      o = it[:o].dup
      o[:n] = @s[:mech_n].to_i if @s[:mech_n] && o[:nr]
      fam = "fam_#{it[:mb]}"
      respond_to?(fam, true) ? send(fam, o) : send("mb_#{it[:mb]}", o)
      @hw[o[:key]] += 1 if o[:key]
    end

    def mb_drawers(o)
      zf, hf = full_front
      drawers({ t: :drawers, n: o[:n], style: o[:style] }, zf, hf)
    end

    def mb_inner(o)
      zf, hf = full_front
      @door_phase = [0.0, 0.3] # the doors are fully open before the drawers start to leave the carcass
      doors({ t: :doors }, zf, hf, false)
      @door_phase = nil
      n = o[:n]
      inner_h = (@hc - 2 * @t - 20) / n
      slide = (((@cd - @ft - @bk - 40) / 50.0).floor * 50).clamp(250, 500)
      dt = Config.drawer_thickness!(@c)
      bw = @w - 2 * @t - 26
      bx = @t + 13
      fd = @cd - @ft - 8 # behind the hinge arms that cross the front zone
      d0 = fd - slide
      n.times do |i|
        z = @z0 + @t + 10 + i * inner_h
        a = asm("inner#{i + 1}", { 'type' => 'lin', 'v' => [0, slide * 0.9 + @ft + 20, 0], 'phase' => [0.3, 1.0] })
        @link_to=a.name
        @runner_phase=[0.3,1.0]
        in_asm(a) do
          pn('drawer_front', @t + 2, fd, z, @w - 2 * @t - 4, @ft, inner_h - 6, 'front', grain: :x, eb: [2, 2], eb_t: 2.0)
          bh = [inner_h - 60, 60.0].max
          pn('drawer_side', bx, d0, z + 20, dt, slide, bh, 'carcass', grain: :d, eb: [1, 0])
          pn('drawer_side', bx + bw - dt, d0, z + 20, dt, slide, bh, 'carcass', grain: :d, eb: [1, 0])
          pn('drawer_back', bx + dt, d0, z + 20, bw - 2 * dt, dt, bh, 'carcass', grain: :x)
          pn('drawer_subfront', bx + dt, d0 + slide - dt, z + 20, bw - 2 * dt, dt, bh, 'carcass', grain: :x, eb: [1, 0])
          pn('drawer_bottom', bx, d0, z + 28, bw, slide, 6, 'back', grain: :d)
          if o[:style]==:under
            runners_under(bx,bw,d0,slide,z+20,slide*0.9+@ft+20)
          else
            runners_side(bx,d0,slide,z+20+bh/2-22,slide*0.9+@ft+20,@t,@w-@t)
          end
        end
        @link_to=nil
        @runner_phase=nil
        @hw[o[:style] == :under ? 'undermount_slide' : 'slide_pair'] += 1
      end
    end

    def mb_hinged(_o)
      zf, hf = full_front
      shelves({ t: :doors, shelves: 1, z0: @z0 + @t, h: @hc - 2 * @t })
      doors({ t: :doors }, zf, hf, false)
    end

    def mb_sliding(o)
      n_in = o[:n]
      n = n_in == 1 ? 2 : n_in # a single moving leaf still needs a fixed panel to slide over
      tracks = o[:tracks] || [n, 3].min
      inner = @w - 2 * @t
      ov = 30.0
      pw = (inner + (n - 1) * ov) / n
      zb = @z0 + @t + 14
      hh = @hc - 2 * @t - 40
      shelves({ t: :doors, shelves: 1, z0: @z0 + @t, h: @hc - 2 * @t, front_clear: tracks * (@ft + 9) + 8 }) # shelf stops short of the door tracks
      n.times do |i|
        layer = i % [tracks, 1].max
        x = @t + i * (pw - ov)
        dplane = @cd - (layer + 1) * (@ft + 9)
        dir = i < n / 2.0 ? 1 : -1
        fixed = (n_in == 1 && i == 1) || (n == 3 && i == 1)
        pos = i.even? ? :side_r : :side_l
        if fixed
          front('door', x, pw, zb, hh, pos, grain: :z, d: dplane)
          next
        end
        # never let a leaf leave the carcass: travel is limited to the free room on its sliding side
        room = dir == 1 ? (@t + inner) - (x + pw) : x - @t
        travel = [room, (pw - ov) * 0.9].min
        a = asm("slide#{i + 1}", { 'type' => 'lin', 'v' => [dir * travel, 0, 0] })
        in_asm(a) do
          front('door', x, pw, zb, hh, pos, grain: :z, d: dplane)
          # round roller wheel on a small mounting bracket (was a flat box - real hangers roll on a wheel)
          [x + 40, x + pw - 62].each do |rx|
            h_slab('roller_bracket', rx, dplane + 4, zb + hh - 2, 22, @ft - 8, 10, :zinc)
            h_rod('roller_wheel', rx + 5, dplane + 5, zb + hh, :d, @ft - 10, 12, :chrome, 24)
            h_rod('roller_axle', rx + 9, dplane + 3, zb + hh + 4, :d, @ft - 6, 4, :zinc, 16)
            h_slab('bottom_guide', rx + 6, dplane + 4, zb - 8, 10, @ft - 8, 10, :plastic)
          end
        end
        @hw['slide_wheel'] += 2
        @hw['slide_guide'] += 2
      end
      td0 = @cd - tracks * (@ft + 9) - 2
      tl = tracks * (@ft + 9) + 2
      # top/bottom rails as a real C-channel cross-section (web + two lips) instead of a solid block -
      # the wheels visibly ride inside the top rail, the guide pad inside the shallow bottom one.
      tz = @z0 + @hc - @t - 22
      hb('track_top_web', @t, td0, tz + 18, inner, tl, 4)
      hb('track_top_lip_f', @t, td0, tz, inner, 4, 22)
      hb('track_top_lip_b', @t, td0 + tl - 4, tz, inner, 4, 22)
      bz = @z0 + @t
      hb('track_bottom_web', @t, td0, bz, inner, tl, 3)
      hb('track_bottom_lip_f', @t, td0, bz, inner, 3, 10)
      hb('track_bottom_lip_b', @t, td0 + tl - 3, bz, inner, 3, 10)
      @hw['slide_track_m'] += 2 * inner / 1000.0
    end

    # Side steel plates with slotted mounting rail + black damper housings + dishes - what a real pull-down
    # dish rack looks like (modelled from a reference rack; only its function/proportions were used).
    # plate stacks on each rack level (decoration, no cut-list / hardware count)
    def dish_decor(b, levels)
      w = b[:x1] - b[:x0]
      h = b[:z1] - b[:z0]
      pal = Appliances.pal
      levels.times do |k|
        z = b[:z0] + 20 + k * (h - 40) / [levels, 1].max + 8
        [0.28, 0.72].each do |fx|
          cx = b[:x0] + w * fx
          cd = (b[:d0] + b[:d1]) / 2.0
          7.times { |i| Appliances.cyl(@cur || @e, cx, cd, z + i * 9, [w * 0.15, 95].min, 3, pal[:white], :z, 20) }
        end
      end
    end

    def cutlery_insert(x, d, z, w, dep)
      hb('cutlery_base', x, d, z, w, dep, 4, 'front')
      n = 4
      n.times do |i|
        hb('cutlery_div', x + (i + 1) * w / (n + 1), d, z + 4, 4, dep, 40, 'front')
      end
      hb('cutlery_div', x, d + dep * 0.55, z + 4, w, 4, 40, 'front')
    end

    def mb_cutlery(_o)
      zf, hf = full_front
      fh = (hf - @gap * 2) / 3.0
      3.times do |i|
        drawers({ t: :drawers, n: 1, insert: i == 2 ? :cutlery : nil }, zf + i * (fh + @gap), fh)
      end
    end

  end

  class Cabinet
    include MechBuilders
  end
end
