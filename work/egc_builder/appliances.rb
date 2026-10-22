# frozen_string_literal: true

module EGC
  # Real appliance geometry (door, glass, handles, knobs/rings, control strips...) instead of a
  # flat grey box - used for every VISIBLE appliance: free-standing devices from the catalog, and
  # any appliance cell inside a cabinet that isn't hidden behind its own door.
  # Local frame (mm): x left->right, d = distance from the back of the housing toward the room
  # (front face is at d = dep), z up from the appliance's own base.
  module Appliances
    module_function

    # name => [metallic, roughness] (SketchUp PBR)
    # name => [image in assets/tex/dev, real size of one tile in mm] - our own generated images (tools/gen_textures.js)
    TEX = { 'Body Steel' => ['dev_steel', 220], 'Door Steel' => ['dev_steel', 220], 'Fridge Steel' => ['dev_steel', 220], 'Sink Steel' => ['dev_steel', 260],
            'Steel Dark' => ['dev_steel_dark', 320], 'Cast Iron' => ['acg_powder', 300], 'Enamel' => ['dev_enamel', 180],
            'Cutting Board' => ['dev_board', 420], 'Ceramic Glass' => ['dev_ceramic', 300] }.freeze
    PBR = {
      'Body Steel' => [0.9, 0.32], 'Door Steel' => [0.9, 0.28], 'Steel Dark' => [0.8, 0.4], 'Black Glass' => [0.0, 0.05], 'Clear Glass' => [0.0, 0.03],
      'Smoked Glass' => [0.0, 0.04], 'Chrome' => [1.0, 0.08], 'Enamel' => [0.0, 0.35], 'White' => [0.0, 0.3],
      'Grey Dark' => [0.0, 0.5], 'Rubber' => [0.0, 0.9], 'LED' => [0.0, 0.3], 'Sink Steel' => [1.0, 0.28],
      'Cast Iron' => [0.6, 0.6], 'Ceramic Glass' => [0.0, 0.06], 'Tap Chrome' => [1.0, 0.06], 'Brass' => [1.0, 0.25],
      'Opening Frame' => [0.0, 0.4], 'Opening Glass' => [0.0, 0.03], 'Opening Steel' => [0.8, 0.4], 'Opening Chrome' => [1.0, 0.1],
      'Opening Leaf' => [0.0, 0.45], 'Wire Chrome' => [1.0, 0.16], 'Anthracite' => [0.25, 0.5], 'Zinc Bracket' => [0.9, 0.35], 'Damper' => [0.2, 0.5]
    }.freeze

    # surface relief + gloss variation of the real metals (ambientCG CC0 maps, assets/tex/dev/acg_*_n / _r - see LICENSE_ambientCG.txt):
    # normal map + roughness map on the SketchUp PBR material, so steel shows its fine scratches and the cast iron its powder grain
    PBR_MAPS = { 'Body Steel' => 'acg_m012', 'Door Steel' => 'acg_m012', 'Fridge Steel' => 'acg_m012', 'Sink Steel' => 'acg_m012',
                 'Steel Dark' => 'acg_m032', 'Cast Iron' => 'acg_m027', 'Enamel' => 'acg_m027' }.freeze

    def pbr_maps(m, name)
      key = PBR_MAPS[name]
      return unless key && m.respond_to?(:normal_texture=) && m.get_attribute('egc', 'pbr_maps') != key

      dir = File.join(File.dirname(__FILE__), 'assets', 'tex', 'dev')
      nt = File.join(dir, "#{key}_n.jpg")
      rt = File.join(dir, "#{key}_r.jpg")
      return unless File.file?(nt) && File.file?(rt)

      m.normal_texture = nt
      m.normal_style = Sketchup::Material::NORMAL_STYLE_OPENGL
      m.normal_scale = 0.6
      m.normal_enabled = true
      m.roughness_texture = rt
      m.set_attribute('egc', 'pbr_maps', key)
    rescue StandardError
      nil
    end

    def mat(name, rgb, alpha = nil)
      model = Sketchup.active_model
      full = "EGC Dev #{name}"
      m = model.materials[full] || model.materials.add(full)
      m.color = Sketchup::Color.new(*rgb) unless m.texture
      if (tx = TEX[name]) && m.get_attribute('egc', 'dev_tex') != tx.join(':') # real surface: brushed steel, cast iron, enamel, wood...
        tp = File.join(File.dirname(__FILE__), 'assets', 'tex', 'dev', "#{tx[0]}.jpg")
        begin
          if File.file?(tp)
            m.texture = tp
            m.texture.size = [Geo.mm(tx[1]), Geo.mm(tx[1])]
            m.set_attribute('egc', 'dev_tex', tx.join(':'))
          end
        rescue StandardError
          nil
        end
      end
      m.alpha = alpha if alpha
      if (pb = PBR[name]) && m.get_attribute('egc', 'pbr') != name
        begin
          m.metalness_enabled = pb[0].positive?
          m.metallic_factor = pb[0] if pb[0].positive?
          m.roughness_enabled = true
          m.roughness_factor = pb[1]
          m.set_attribute('egc', 'pbr', name)
        rescue StandardError
          nil
        end
      end
      pbr_maps(m, name)
      m
    end

    def pal
      {
        body: mat('Body Steel', [186, 189, 192]), door: mat('Door Steel', [204, 207, 210]), steel_dk: mat('Steel Dark', [112, 116, 120]),
        black: mat('Black Glass', [20, 22, 26]), glass: mat('Clear Glass', [196, 214, 224], 0.3),
        smoke: mat('Smoked Glass', [30, 33, 38], 0.72), chrome: mat('Chrome', [214, 217, 220]),
        enamel: mat('Enamel', [55, 57, 61]), white: mat('White', [240, 241, 240]),
        grey_dk: mat('Grey Dark', [80, 84, 88]), rubber: mat('Rubber', [22, 22, 24]),
        led: mat('LED', [255, 246, 214]), blue: mat('Display Blue', [46, 132, 214]),
        basin: mat('Sink Steel', [190, 194, 198]), brass: mat('Brass', [178, 142, 74]),
        cast: mat('Cast Iron', [30, 30, 32]), ceramic: mat('Ceramic Glass', [14, 15, 18]),
        zone: mat('Cooking Zone', [64, 68, 74]), tap: mat('Tap Chrome', [206, 210, 214]),
        wood: mat('Cutting Board', [198, 160, 116])
      }
    end

    def box(ents, x, d, z, sx, sd, sz, material)
      return nil if sx <= 0.05 || sd <= 0.05 || sz <= 0.05

      g = ents.add_group
      Geo.box(g.entities, 0, 0, 0, sx, sd, sz)
      g.transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), -Geo.mm(d), Geo.mm(z))))
      g.material = material
      g
    end

    def cyl(ents, x, d, z, r, len, material, axis = :y, segs = 24)
      g = ents.add_group
      n = case axis
          when :z then Geom::Vector3d.new(0, 0, 1)
          when :x then Geom::Vector3d.new(1, 0, 0)
          else Geom::Vector3d.new(0, 1, 0)
          end
      f = g.entities.add_face(g.entities.add_circle(Geom::Point3d.new(0, 0, 0), n, Geo.mm(r), segs))
      if f
        sign = case axis
               when :z then f.normal.z >= 0 ? 1 : -1
               when :x then f.normal.x >= 0 ? 1 : -1
               else f.normal.y <= 0 ? 1 : -1
               end
        f.pushpull(sign * Geo.mm(len))
      end
      g.transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), -Geo.mm(d), Geo.mm(z))))
      g.material = material
      g
    end

    def ring(ents, x, d, z, r_out, r_in, thick, material, axis = :y, segs = 32)
      g = ents.add_group
      ge = g.entities
      n = axis == :z ? Geom::Vector3d.new(0, 0, 1) : Geom::Vector3d.new(0, 1, 0)
      ge.add_face(ge.add_circle(Geom::Point3d.new(0, 0, 0), n, Geo.mm(r_out), segs))
      ge.add_circle(Geom::Point3d.new(0, 0, 0), n, Geo.mm(r_in), segs)
      faces = ge.grep(Sketchup::Face)
      if faces.size > 1
        # A thin annulus is smaller than its centre disc. Area sorting erased the ring itself.
        inner = faces.find { |face| face.classify_point(ORIGIN) == Sketchup::Face::PointInside }
        inner.erase! if inner&.valid?
      end
      rf = ge.grep(Sketchup::Face).first
      if rf&.valid?
        sign = axis == :z ? (rf.normal.z >= 0 ? 1 : -1) : (rf.normal.y <= 0 ? 1 : -1)
        rf.pushpull(sign * Geo.mm(thick))
      end
      g.transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), -Geo.mm(d), Geo.mm(z))))
      g.material = material
      g
    end

    def knob(ents, x, d, z, r, material)
      cyl(ents, x, d, z, r, 14, material, :y)
      cyl(ents, x, d + 13, z + r * 0.45, 1.4, 2, mat('Knob Mark', [30, 30, 30]), :y, 8)
    end

    # ---- individual builders (x,d,z = local origin; w,dep,h = footprint) --------------------------
    def hob_zone(ents, cx, cd, cz, r, material, ring_mat)
      # a cooking zone is PRINTED on the glass: thin circles, not a raised disc
      pr = mat('Zone Print', [150, 154, 160])
      ring(ents, cx, cd, cz + 0.5, r + 18, r + 16.4, 0.6, pr, :z, 48)
      ring(ents, cx, cd, cz + 0.5, r * 0.62, r * 0.62 - 1.4, 0.6, pr, :z, 40) if r > 60
      box(ents, cx - 6, cd - 0.6, cz + 0.5, 12, 1.2, 0.6, pr)
      box(ents, cx - 0.6, cd - 6, cz + 0.5, 1.2, 12, 0.6, pr)
    end

    def hood_builtin(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      box(ents, x, d, z, w, dep, h, p[:body])                                      # housing (mostly hidden inside the wall unit)
      grille(ents, x + 14, d + 24, z - 1, w - 28, dep - 48, p[:steel_dk], 7)        # filter grille on the underside
      slab(ents, x + 6, z + h * 0.12, w - 12, h * 0.62, d + dep, 8, p[:black], -2)  # front visor panel (dark glass/acrylic)
      bezel(ents, x + 6, z + h * 0.12, w - 12, h * 0.62, d + dep, 3, p[:steel_dk], 6, -1) # steel frame around the visor
      slab(ents, x + w * 0.5 - 55, z + h * 0.8, 110, 4, d + dep, 3, p[:led], -1)    # LED light line
      button_row(ents, x + w * 0.5 - 48, z + h * 0.1, 3, 32, d + dep, p[:grey_dk], 10) # touch controls
    end

    def washer(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      box(ents, x, d, z, w, dep, h, p[:white])
      cx = x + w * 0.5
      cz = z + h * 0.46
      ring(ents, cx, d + dep - 4, cz, 150, 130, 6, p[:steel_dk], :y, 28)
      cyl(ents, cx, d + dep - 10, cz, 128, 8, p[:smoke], :y, 28)
      box(ents, x + 12, d + dep - 6, z + h - 40, w - 24, 3, 24, p[:body])
      knob(ents, x + w - 40, d + dep - 6, z + h - 28, 14, p[:grey_dk])
    end

    BUILDERS = {
      'oven' => :oven, 'microwave' => :microwave, 'hob' => :hob_electric, 'hob_gas' => :hob_gas,
      'hood' => :hood_builtin, 'hood_chimney' => :hood_chimney, 'hood_slim' => :hood_slim,
      'sink' => :sink, 'fridge' => :fridge, 'freezer' => :freezer, 'fridge_under' => :fridge,
      'dishwasher' => :dishwasher, 'washer' => :washer, 'dryer' => :dryer,
      'coffee' => :coffee, 'warming' => :warming_drawer, 'wine_cooler' => :wine_cooler, 'wall_rail' => :wall_rail
    }.freeze

    def build?(kind)
      BUILDERS.key?(kind.to_s)
    end

    # The detailed builder failed AND the simplified fallback failed too: nothing is left in the model.
    class BuildError < StandardError; end

    # Test hook only: ->(kind) { raise 'injected' } makes the detailed builder fail on purpose (fault-injection test).
    class << self
      attr_accessor :fault_injection
    end

    # Optional, user-supplied (LICENSED) models: assets/models/appliance_<kind>.skp with an optional sidecar appliance_<kind>.json:
    #   { "native": {"w":595,"d":550,"h":595},        # dimensions the model was made for (default: its own bounds)
    #     "uniform_scale": {"min":0.98,"max":1.02},     # OPTIONAL opt-in: ONE factor on all axes, inside these limits (default: none)
    #     "fit": {"min_w":560,"max_w":600,"min_d":..,"max_d":..,"min_h":..,"max_h":..},   # fit limits on the scaled result
    #     "anchor": "front_bottom_left",                # origin convention (default: the model's own min corner at the slot origin)
    #     "clearance": {"top":5,"sides":2,"back":30},   # informational installation clearance
    #     "variants": [{"file":"appliance_oven_45.skp","w":595,"d":550,"h":455}] }   # alternative files chosen by size
    # NEVER DISTORTS a model: no per-axis scaling exists ("scale_axes" is ignored and logged). Order: exact native size (2 mm) ->
    # size variant -> uniform scaling only if "uniform_scale" allows it and the three ratios agree -> otherwise REJECTED (logged)
    # so the generated E.G.C appliance is used. Axes: x = width, y = depth (front toward -y), z = height.
    def user_model(ents, kind, w, dep, h)
      dir = File.join(File.dirname(__FILE__), 'assets', 'models')
      base = File.join(dir, "appliance_#{kind}")
      return false unless File.file?("#{base}.skp") || File.file?("#{base}.json")

      meta = File.file?("#{base}.json") ? (JSON.parse(File.read("#{base}.json")) rescue {}) : {}
      files = [{ 'file' => "appliance_#{kind}.skp" }] + Array(meta['variants'])
      files.each do |v|
        path = File.join(dir, v['file'].to_s)
        next unless File.file?(path)

        defn = Sketchup.active_model.definitions.load(path)
        bb = defn.bounds
        next if bb.width <= 0 || bb.height <= 0 || bb.depth <= 0

        nat = v['w'] ? v : (meta['native'] || {})
        nw = (nat['w'] || bb.width.to_mm).to_f
        nd = (nat['d'] || bb.height.to_mm).to_f
        nh = (nat['h'] || bb.depth.to_mm).to_f
        if v['scale_axes'] || meta['scale_axes']
          Diag.log('appliance_user_model', { device: kind, file: v['file'] }, state: 'scale_axes_ignored') # per-axis scaling is never honoured
        end
        ratios = [w / nw, dep / nd, h / nh]
        sc = 1.0
        if [[w, nw], [dep, nd], [h, nh]].all? { |a, b| (a - b).abs <= 2.0 }
          sc = 1.0                                   # exact native size
        else
          us = meta['uniform_scale']                 # explicit opt-in, one factor for all three axes, inside its limits
          lo = us.is_a?(Hash) ? us['min'].to_f : 0.0
          hi = us.is_a?(Hash) ? us['max'].to_f : 0.0
          next unless lo.positive? && hi >= lo && ratios.max - ratios.min <= 0.005 && ratios.min >= lo && ratios.max <= hi

          sc = EGC::Num.sum(ratios) / 3.0
        end
        fit = meta['fit'] || {}
        ok = (!fit['min_w'] || w >= fit['min_w']) && (!fit['max_w'] || w <= fit['max_w']) && (!fit['min_d'] || dep >= fit['min_d']) &&
             (!fit['max_d'] || dep <= fit['max_d']) && (!fit['min_h'] || h >= fit['min_h']) && (!fit['max_h'] || h <= fit['max_h'])
        next unless ok

        tr = Geom::Transformation.new(Geom::Point3d.new(-bb.min.x * sc, -Geo.mm(dep) - bb.min.y * sc, -bb.min.z * sc)) *
             Geom::Transformation.scaling(sc, sc, sc)
        inst = ents.add_instance(defn, tr)
        inst.set_attribute('egc', 'asset_file', v['file'].to_s)
        inst.set_attribute('egc', 'asset_scale', sc)
        return true
      end
      Diag.log('appliance_user_model', { device: kind, w: w, d: dep, h: h }, state: 'rejected_no_fit')
      false
    rescue StandardError => e
      Diag.log('appliance_user_model', { device: kind, w: w, d: dep, h: h }, error: e, state: 'rejected_error')
      false
    end

    # Builds real geometry inside a wrapper group (so it can be tagged/id'd like any other part) and returns that group.
    # Status is recorded on the group ('build_status'): DETAILED (the E.G.C builder), USER_MODEL (licensed asset), SIMPLIFIED
    # (a kind without a builder, or the detailed builder failed and a clean box was built from an EMPTY group) or FAILED
    # (both failed: nothing is left in the model and BuildError is raised). A detailed-builder exception is never swallowed:
    # it is written to the diagnostic log with device, dimensions and stack trace.
    def build(parent_ents, name, kind, x, d, z, w, dep, h, cfg = {})
      g = parent_ents.add_group
      g.name = name
      sel = BUILDERS[kind.to_s]
      status = 'DETAILED'
      why = nil
      if user_model(g.entities, kind, w, dep, h)
        status = 'USER_MODEL'
      elsif sel
        begin
          fault_injection&.call(kind.to_s)
          send(sel, g.entities, 0, 0, 0, w, dep, h, cfg)
        rescue StandardError => e
          Diag.log('appliance_build', { device: kind, name: name, w: w, d: dep, h: h }, error: e, state: 'detailed_failed')
          why = "#{e.class}: #{e.message}"[0, 200]
          g.erase! if g.valid? # roll back every partial part
          g = parent_ents.add_group
          g.name = name
          begin
            Geo.box(g.entities, 0, 0, 0, w, dep, h)
            g.material = Geo.material('appliance', cfg)
            status = 'SIMPLIFIED'
            Diag.log('appliance_build', { device: kind, name: name, w: w, d: dep, h: h }, state: 'simplified')
          rescue StandardError => e2
            Diag.log('appliance_build', { device: kind, name: name, w: w, d: dep, h: h }, error: e2, state: 'FAILED')
            g.erase! if g.valid?
            raise BuildError, "appliance #{kind} could not be built (#{why})"
          end
        end
      else
        Geo.box(g.entities, 0, 0, 0, w, dep, h)
        g.material = Geo.material('appliance', cfg)
        status = 'SIMPLIFIED'
        why = 'no detailed builder for this kind'
      end
      g.transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), -Geo.mm(d), Geo.mm(z))))
      g.set_attribute('egc', 'role', 'appliance')
      g.set_attribute('egc', 'part', kind.to_s)
      g.set_attribute('egc', 'build_status', status)
      g.set_attribute('egc', 'build_error', why) if why
      g.layer = Geo.tag('EGC Appliances') rescue nil
      g
    end

    # Drop-in replacement for a flat Panel.add(...,'appliance',...,role:'appliance') call: uses the
    # real detailed geometry when we have a builder for `kind`, otherwise falls back to the old flat
    # box so nothing breaks for a kind we haven't modelled yet.
    def place(ents, name, kind, x, d, z, w, dep, h, cfg = {})
      return build(ents, name, kind, x, d, z, w, dep, h, cfg) if build?(kind)

      Panel.add(ents, name, kind.to_s, x, d, z, w, dep, h, 'appliance', cfg, role: 'appliance')
    end
  end
end
