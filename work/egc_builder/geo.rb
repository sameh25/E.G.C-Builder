# frozen_string_literal: true

module EGC
  # Low level geometry + panel creation.
  # Builder space: x along the wall, d = distance from wall towards the room (front),
  # z up.  World: y = -d  (so fronts face -Y and the default Front view sees them).
  module Geo
    module_function

    def mm(v)
      v.to_f.mm
    end

    def p3(x, d, z)
      Geom::Point3d.new(mm(x), -mm(d), mm(z))
    end

    def extrude(ents, pts, axis, dist)
      face = ents.add_face(pts)
      return nil unless face && face.valid?

      sign = face.normal.dot(axis) >= 0 ? 1 : -1
      face.pushpull(sign * mm(dist))
      face
    end

    def box(ents, x, d, z, sx, sd, sz)
      return nil if sx <= 0.01 || sd <= 0.01 || sz <= 0.01

      pts = [p3(x, d, z), p3(x + sx, d, z), p3(x + sx, d + sd, z), p3(x, d + sd, z)]
      extrude(ents, pts, Geom::Vector3d.new(0, 0, 1), sz)
    end

    def hex_to_color(hex)
      h = hex.to_s.delete('#')
      h = h.chars.map { |c| c * 2 }.join if h.length == 3
      Sketchup::Color.new(h[0, 2].to_i(16), h[2, 2].to_i(16), h[4, 2].to_i(16))
    end

    COLOR_KEY = {
      'carcass' => 'carcass_color', 'front' => 'front_color', 'top' => 'top_color',
      'back' => 'back_color', 'drawer' => 'carcass_color', 'profile' => 'profile_color',
      'appliance' => nil, 'glass' => nil, 'room' => nil, 'floor' => nil, 'splash' => 'splash_color',
      'plinth' => 'plinth_color'
    }.freeze
    FIXED = {
      'appliance' => [176, 180, 186], 'glass' => [170, 210, 230],
      'room' => [200, 196, 190], 'floor' => [222, 220, 214], 'hood' => [190, 194, 198], 'led_channel' => [255, 240, 170]
    }.freeze
    # material key -> cfg key holding a chosen catalog swatch id (material code); drawer boxes
    # follow the carcass swatch, splash follows the countertop swatch.
    SWATCH_KEY = { 'carcass' => 'carcass_swatch', 'front' => 'front_swatch', 'drawer' => 'carcass_swatch',
                   'top' => 'top_swatch', 'splash' => 'top_swatch' }.freeze

    def tag(name)
      layers = Sketchup.active_model.layers
      layers[name] || layers.add(name)
    end

    def owned?(m)
      m.get_attribute('egc', 'owned') == true
    rescue StandardError
      true # attribute dictionaries unsupported on this API - assume it's ours
    end

    def mark_owned(m)
      m.set_attribute('egc', 'owned', true)
    rescue StandardError
      nil
    end

    # Real-world repeat size (mm) of one texture tile, by the swatch's own material family - a wood
    # veneer/board grain repeats far tighter than a stone slab or a brushed-metal sheet, so one fixed
    # size for everything either stretches wood into a blur or tiles stone too small to read as a slab.
    TEX_TILE_MM = { 'Wood' => 900, 'Stone' => 1200, 'Metallic' => 900, 'Texture' => 600 }.freeze

    # Repaint the ONE shared "EGC <key>" material in place (never a differently-named material)
    # so every cabinet already using it updates instantly, exactly like a plain colour change does.
    def apply_swatch(m, key, entry)
      want = entry['tex'] || "flat:#{entry['code']}"
      begin
        m.set_attribute('egc', 'tex_path', File.join(DIR, entry['tex'])) if entry['tex'] # the grain twin turns this picture
      rescue StandardError
        nil
      end
      want += ":#{entry['tile_mm']}" if entry['tile_mm']
      cur = begin
        m.get_attribute('egc', 'tex_id')
      rescue StandardError
        nil
      end
      return if cur == want

      if entry['tex']
        m.texture = File.join(DIR, entry['tex'])
        tile = entry['tile_mm'].to_f
        tile = TEX_TILE_MM[entry['cat'].to_s] || (%w[top splash].include?(key) ? 1200 : 700) unless tile > 0
        m.texture.size = mm(tile)
      else
        m.texture = nil if m.texture
        m.color = Sketchup::Color.new(*entry['rgb'])
      end
      begin
        m.set_attribute('egc', 'tex_id', want)
      rescue StandardError
        nil
      end
    end

    # ---- PBR (SketchUp 2025+ metalness / roughness) so glossy fronts, polished stone, steel and glass
    # actually read differently in the viewport / Enscape / V-Ray instead of one flat plastic look.
    # key => [metallic, roughness]; fronts/tops depend on the finish setting.
    def pbr_values(key, cfg, textured)
      case key
      when 'front' then [0.0, cfg['front_finish'].to_s == 'matt' ? 0.55 : (textured ? 0.4 : 0.14)]
      when 'carcass' then [0.0, 0.6]
      when 'back' then [0.0, 0.75]
      when 'drawer' then [0.0, 0.5]
      when 'top' then [0.0, cfg['top_finish'].to_s == 'matt' ? 0.5 : 0.12]
      when 'splash' then [0.0, 0.25]
      when 'glass' then [0.0, 0.03]
      when 'profile' then [0.85, 0.3]
      when 'appliance' then [0.5, 0.35]
      when 'plinth' then [0.0, 0.4]
      end
    end

    def apply_pbr(m, key, cfg)
      metal, rough = pbr_values(key, cfg, !!m.texture)
      return unless rough

      stamp = "#{key}:#{metal}:#{rough}"
      return if m.get_attribute('egc', 'pbr') == stamp

      m.metalness_enabled = metal.positive?
      m.metallic_factor = metal if metal.positive?
      m.roughness_enabled = true
      m.roughness_factor = rough
      m.set_attribute('egc', 'pbr', stamp)
    rescue StandardError
      nil
    end

    def material(key, cfg)
      model = Sketchup.active_model
      name = "EGC #{key}"
      m = model.materials[name] || model.materials.add(name)
      sk = SWATCH_KEY[key]
      id = sk && cfg[sk]
      entry = id && Catalog.swatch(key, id)
      if entry
        apply_swatch(m, key, entry)
        mark_owned(m)
        m.alpha = 0.35 if key == 'glass'
        apply_pbr(m, key, cfg)
        sync_twin(m) if model.materials["#{name}#{TWIN}"]
        return m
      end

      return m if m.texture && !owned?(m) # a texture applied by hand in SketchUp - leave it alone

      m.texture = nil if m.texture # clear a catalog texture we set earlier, back to flat colour
      ck = COLOR_KEY[key]
      if ck && cfg[ck]
        m.color = hex_to_color(cfg[ck])
      elsif FIXED[key]
        m.color = Sketchup::Color.new(*FIXED[key])
      end
      mark_owned(m)
      m.alpha = 0.35 if key == 'glass'
      apply_pbr(m, key, cfg)
      sync_twin(m) if model.materials["#{name}#{TWIN}"]
      m
    end

    # GRAIN DIRECTION: SketchUp lays a group's texture with the picture's vertical along Z on upright faces and along the depth on flat
    # faces. A board whose grain must run the other way (a shelf or a top along its width, a drawer front across, a drawer side along
    # the depth) takes the "<material> 90" twin: the same swatch with the picture turned 90 degrees, kept in step with the original.
    TWIN = ' 90'

    def turned?(taxis, ga)
      ga != (taxis == :z ? :d : :z)
    end

    # the swatch code a unit carries for this material key (its own materials, see Cabinet#initialize); drawer boxes follow the carcass
    def unit_code(key, cfg)
      um = cfg['unit_mats']
      return nil unless um.is_a?(Hash) && !um.empty?

      um[key == 'drawer' ? 'carcass' : key.to_s]
    end

    # a unit's own material: one shared "EGC <key> <code>" material per swatch, so every unit with that swatch shares it and the
    # kitchen material ("EGC <key>") is never repainted by it
    def unit_material(key, code, cfg)
      entry = SWATCH_KEY.key?(key) && Catalog.swatch(key, code)
      return material(key, cfg) unless entry

      model = Sketchup.active_model
      name = "EGC #{key} #{code}"
      m = model.materials[name] || model.materials.add(name)
      apply_swatch(m, key, entry)
      mark_owned(m)
      apply_pbr(m, key, cfg)
      sync_twin(m) if model.materials["#{name}#{TWIN}"]
      m
    end

    def material_for(key, cfg, turned)
      code = unit_code(key, cfg)
      m = code ? unit_material(key, code, cfg) : material(key, cfg)
      return m unless turned && SWATCH_KEY.key?(key)

      model = Sketchup.active_model
      t = model.materials["#{m.name}#{TWIN}"] || model.materials.add("#{m.name}#{TWIN}")
      sync_twin(m, t)
      t
    rescue StandardError
      m
    end

    def sync_twin(m, t = Sketchup.active_model.materials["#{m.name}#{TWIN}"])
      return unless t

      path = m.get_attribute('egc', 'tex_path') if m.texture
      want = path ? "#{path}:#{m.texture.width.round(3)}" : "flat:#{m.color.to_a.inspect}"
      if t.get_attribute('egc', 'tex_id') != want
        if path && (rep = turned_rep(path))
          t.texture = rep
          t.texture.size = [m.texture.height, m.texture.width]
        else
          t.texture = nil if t.texture
          t.color = m.color
        end
        t.set_attribute('egc', 'tex_id', want)
        mark_owned(t)
      end
      t.alpha = m.alpha
      if m.respond_to?(:roughness_factor)
        t.metalness_enabled = m.metalness_enabled?
        t.metallic_factor = m.metallic_factor if m.metalness_enabled?
        t.roughness_enabled = m.roughness_enabled?
        t.roughness_factor = m.roughness_factor
      end
    rescue StandardError
      nil
    end

    # the picture turned (transposed) once per file and session
    def turned_rep(path)
      @turned ||= {}
      @turned[path] ||= begin
        r = Sketchup::ImageRep.new(path)
        w = r.width
        h = r.height
        bpp = r.bits_per_pixel / 8
        stride = w * bpp + r.row_padding
        d = r.data
        rows = Array.new(h) { |y| d.byteslice(y * stride, w * bpp).unpack("a#{bpp}" * w) }
        out = Sketchup::ImageRep.new
        out.set_data(h, w, bpp * 8, 0, rows.transpose.map!(&:join).join)
        out
      end
    rescue StandardError
      nil
    end
  end

  module Panel
    module_function

    ATTR = 'egc'

    # o: :grain (:x,:d,:z), :eb [len_edges, wid_edges], :eb_t (mm), :role, :thk, :notes, :groove
    def add(ents, cab, part, x, d, z, sx, sd, sz, mat, cfg, o = {})
      g = ents.add_group
      if o[:solid]
        o[:solid].call(g.entities)
      else
        Geo.box(g.entities, 0, 0, 0, sx, sd, sz)
      end
      g.transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), -Geo.mm(d), Geo.mm(z))))
      g.name = "#{cab}_#{part}"
      dims = { x: sx.to_f, d: sd.to_f, z: sz.to_f }
      thk = o[:thk] || dims.values.min
      rest = dims.dup
      taxis = rest.key(thk) || rest.min_by { |_, v| (v - thk).abs }[0]
      rest.delete(taxis)
      ga = o[:grain]
      ga = rest.max_by { |_, v| v }[0] unless ga && rest.key?(ga)
      turned = Geo.turned?(taxis, ga)
      g.set_attribute(ATTR, 'turned', true) if turned
      g.material = Geo.material_for(mat, cfg, turned)
      (code = Geo.unit_code(mat, cfg)) && g.set_attribute(ATTR, 'mat_code', code) # the unit's own swatch: the cut list keeps it apart
      len = rest[ga]
      wid = rest.reject { |k, _| k == ga }.values.first
      role = o[:role] || 'part'
      g.set_attribute(ATTR, 'role', role)
      g.set_attribute(ATTR, 'part', part)
      g.set_attribute(ATTR, 'cab', cab)
      g.set_attribute(ATTR, 'mat', mat)
      g.set_attribute(ATTR, 'len', len.round(1))
      g.set_attribute(ATTR, 'wid', wid.round(1))
      g.set_attribute(ATTR, 'thk', thk.round(1))
      g.set_attribute(ATTR, 'len_axis', ga.to_s) # which builder axis (x / d / z) the LENGTH runs along: lets the CNC export place drilling on the panel
      g.set_attribute(ATTR, 'grain', o.fetch(:grain_fixed, true))
      eb = o[:eb] || [0, 0]
      g.set_attribute(ATTR, 'eb_l', eb[0])
      g.set_attribute(ATTR, 'eb_w', eb[1])
      g.set_attribute(ATTR, 'eb_t', o[:eb_t] || 0.8) # carcass tape 0.8 mm PVC (fronts and visible panels pass 2.0)
      g.set_attribute(ATTR, 'groove', o[:groove]) if o[:groove]
      g.set_attribute(ATTR, 'groove_geo', JSON.generate(o[:groove_geo])) if o[:groove_geo] # router data: axis (route along the LENGTH), offset from the PANEL back edge, width, depth
      g.set_attribute(ATTR, 'back_groove', JSON.generate(o[:back_groove])) if o[:back_groove]
      g.set_attribute(ATTR, 'notes', o[:notes]) if o[:notes]
      g.set_attribute(ATTR, 'bore', JSON.generate(o[:bore])) if o[:bore] && !o[:bore].empty?
      code = o[:code] || cab
      g.set_attribute(ATTR, 'code', code)
      g.set_attribute(ATTR, 'pid', next_pid(code))
      g.layer = Geo.tag(tag_for(role, mat)) rescue nil
      g.set_attribute(ATTR, 'orig', g.transformation.to_a)
      if %w[part glass].include?(role)
        v = EX[part]
        if v
          v = [v[0], v[1], (part == 'shelf' && @seq[code].odd? ? -v[2] : v[2])] if part == 'shelf'
          g.set_attribute(ATTR, 'ex', v)
        end
      end
      g
    end

    # EXPLODED VIEW: every part moves toward the viewer (out of the front) and up / down only - never sideways and never backward, so the
    # parts of one unit do not run into the units standing left and right of it, nor into the wall. Layers from the back to the front:
    # back (stays) < carcass < shelves < drawer boxes < fronts.
    EX = {
      'back' => [0, 0, 0], 'side_l' => [0, 0.45, 0], 'side_r' => [0, 0.45, 0], 'bottom' => [0, 0.25, -0.3], 'top' => [0, 0.25, 0.45],
      'top_rail_f' => [0, 0.6, 0.45], 'top_rail_b' => [0, 0.1, 0.45], 'front_strip' => [0, 0.9, 0.25], 'shelf' => [0, 1.0, 0], 'divider' => [0, 0.8, 0], 'vdivider' => [0, 0.8, 0],
      'drawer_back' => [0, 1.25, 0], 'drawer_side' => [0, 1.5, 0], 'drawer_bottom' => [0, 1.5, -0.25], 'drawer_subfront' => [0, 1.8, 0],
      'door' => [0, 2.2, 0], 'flap' => [0, 2.2, 0], 'sliding_door' => [0, 2.2, 0], 'drawer_front' => [0, 2.2, 0], 'trim' => [0, 2.2, 0], 'filler' => [0, 1.6, 0],
      'plinth' => [0, 1.2, 0], 'fascia' => [0, 1.2, 0.3], 'countertop' => [0, 0, 1.0], 'upstand' => [0, 0, 1.5], 'backsplash' => [0, 0, 0], 'end_panel' => [0, 0.45, 0]
    }.freeze

    def next_pid(code)
      @seq ||= Hash.new(0)
      @seq[code] += 1
      format('P-%s-%03d', code, @seq[code]) # board ID P-U04-001: unit ID + 3-digit part number
    end

    def reset_ids
      @seq = Hash.new(0)
    end

    # a rebuilt unit (Edit / Mirror / Replace / Resize) numbers its parts from 01 again, so Part IDs stay stable for the same unit
    def reset_code(code)
      @seq ||= Hash.new(0)
      @seq[code] = 0
    end

    def tag_for(role, mat)
      return 'EGC Hardware' if role == 'hw'
      return 'EGC Appliances' if role == 'appliance'
      return 'EGC Countertop' if %w[top splash].include?(mat)
      return 'EGC Glass' if mat == 'glass'

      mat == 'front' ? 'EGC Fronts' : 'EGC Carcass'
    end
  end
end
