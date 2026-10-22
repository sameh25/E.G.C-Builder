# frozen_string_literal: true

require 'json'

module EGC
  # Appliance visual pass (E.G.C-generated geometry only - no third-party models). Loaded after appliances_v2, so these builders
  # take over for the kinds they redefine. Rules:
  #  * every appliance is a real body: a hollow SHELL (back / sides / top / bottom + inner liner) with the front open, so the cavity is
  #    real and can be seen when a door is open - never a solid box with pictures on it;
  #  * fixed-size details (knobs, handles, bezels, hinges, feet, seals, vents) keep their size; only the panels grow with w/dep/h;
  #  * doors / drawers that are useful for design (clearance, reach) are separate MOVING groups with an 'egc/move' spec in the
  #    appliance's own builder frame (x, d from the back, z), closed = exact zero, driven by the same Animator as the mechanisms;
  #  * a device that has no moving part stays a static build (declared in DEVICE_MOTION).
  module Appliances
    module_function

    # what moves per kind (documentation + used by the audit/test tools)
    DEVICE_MOTION = {
      'oven' => 'bottom-hinged door', 'microwave' => 'side-hinged door', 'dishwasher' => 'drop-down door, then two racks slide out',
      'washer' => 'round door', 'dryer' => 'round door', 'wine_cooler' => 'glass door', 'fridge' => 'doors', 'freezer' => 'door, then the drawers inside',
      'warming' => 'drawer'
    }.freeze

    def mov(ents, name, spec)
      g = ents.add_group
      g.name = name
      g.set_attribute('egc', 'move', JSON.generate(spec))
      g
    end

    def alpha_mat(name, rgb, a)
      mat(name, rgb, a)
    end

    # hollow body: open toward the front (d + dep); inner liner shows through the opening
    def shell(ents, x, d, z, w, dep, h, t, outer, liner)
      box(ents, x, d, z, w, t, h, outer)
      box(ents, x, d, z, t, dep, h, outer)
      box(ents, x + w - t, d, z, t, dep, h, outer)
      box(ents, x, d, z + h - t, w, dep, t, outer)
      box(ents, x, d, z, w, dep, t, outer)
      l = 2.0
      box(ents, x + t, d + t, z + t, w - 2 * t, l, h - 2 * t, liner)
      box(ents, x + t, d + t, z + t, l, dep - t, h - 2 * t, liner)
      box(ents, x + w - t - l, d + t, z + t, l, dep - t, h - 2 * t, liner)
      box(ents, x + t, d + t, z + h - t - l, w - 2 * t, dep - t, l, liner)
      box(ents, x + t, d + t, z + t, w - 2 * t, dep - t, l, liner)
    end

    # wire rack / shelf: two side rods along d + cross rods along x
    def wire_rack(ents, x, d, z, w, dep, material, pitch = 24.0)
      [x, x + w - 3].each { |xx| cyl(ents, xx + 1.5, d, z, 1.5, dep, material, :y, 6) }
      n = [(dep / pitch).floor, 2].max
      (0..n).each { |i| cyl(ents, x, d + 3 + i * ((dep - 6) / n.to_f), z + 1.5, 1.5, w, material, :x, 6) }
    end

    # circular opening in a plate: rectangular plate x/z/w/h at the front plane with a round hole (through) of radius r
    def plate_with_hole(ents, x, d, z, w, h, cx, cz, r, thick, material)
      g = ents.add_group
      e = g.entities
      pts = [[0, 0], [w, 0], [w, h], [0, h]].map { |px, pz| Geo.p3(px, 0, pz) }
      e.add_face(pts)
      e.add_circle(Geo.p3(cx - x, 0, cz - z), Geom::Vector3d.new(0, 1, 0), Geo.mm(r), 40) # SketchUp splits the plate: annulus + disc
      faces = e.grep(Sketchup::Face).sort_by(&:area)
      faces.first.erase! if faces.size > 1
      face = e.grep(Sketchup::Face).max_by(&:area)
      face.pushpull((face.normal.y <= 0 ? 1 : -1) * Geo.mm(thick)) if face&.valid?
      g.transform!(Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(x), -Geo.mm(d), Geo.mm(z))))
      g.material = material
      g
    end

    # ------------------------------------------------------------------------------------------------ oven (+ compact)
    def oven(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      cs = h > 500 ? 74.0 : 62.0
      dh = h - cs
      gl = alpha_mat('Oven Glass', [26, 28, 32], 0.5)
      t = 10.0
      front = d + dep
      # body shell below the control band; the cavity is real
      shell(ents, x, d, z, w, dep - 24, dh, t, p[:enamel], p[:body])
      # cavity furniture: side rails, wire rack, baking tray
      3.times { |i| [x + t + 2, x + w - t - 5].each { |xx| box(ents, xx, d + 40, z + 40 + i * (dh - 100) / 3.0, 3, dep - 24 - 70, 3, p[:steel_dk]) } } if dh > 300
      wire_rack(ents, x + t + 6, d + 40, z + 40 + (dh - 100) / 3.0 + 4, w - 2 * t - 12, dep - 24 - 80, p[:chrome], 22)
      box(ents, x + t + 8, d + 50, z + 46, w - 2 * t - 16, dep - 24 - 100, 4, p[:enamel]) # tray
      box(ents, x + w * 0.5 - 6, d + dep - 24 - 30, z + dh - t - 8, 12, 6, 6, p[:led])   # cavity lamp
      # Convection fan and rear shroud, visible through the glass door.
      fan_x = x + w * 0.5
      fan_z = z + dh * 0.56
      fan_d = d + dep - 58
      ring(ents, fan_x, fan_d, fan_z, [w * 0.105, 58.0].min, [w * 0.085, 44.0].min, 2.0, p[:steel_dk], :y, 20) if dh > 300
      cyl(ents, fan_x, fan_d + 2, fan_z, 12, 3, p[:chrome], :y, 12) if dh > 300
      if dh > 300
        3.times do |i|
          a = i * 120.0 * Math::PI / 180.0
          fx = fan_x + Math.cos(a) * 28
          fz = fan_z + Math.sin(a) * 28
          box(ents, fx - 13, fan_d + 1, fz - 3, 26, 2, 6, p[:chrome])
        end
      end
      # control band (static) - on the housing that goes on up behind it (nothing floats above the cavity)
      box(ents, x, d, z + dh, w, dep - 24, cs, p[:body])
      slab(ents, x, z + dh, w, cs, front, 24, p[:body])
      slab(ents, x + w * 0.5 - 62, z + dh + cs * 0.3, 124, cs * 0.4, front, 3, p[:black], -1)
      slab(ents, x + w * 0.5 - 50, z + dh + cs * 0.44, 100, 8, front, 3, p[:blue], -4)
      [0.11, 0.25, 0.75, 0.89].each { |k| knob(ents, x + w * k, front, z + dh + cs * 0.5, 13, p[:grey_dk]) }
      seal_h(ents, x + 2, x + w - 2, z + dh - 3, front, p[:black])
      # door: bottom hinge, opens down to horizontal
      door = mov(ents, 'door', { 'type' => 'rot', 'pivot' => [x + w / 2.0, front, z + 2], 'axis' => [1, 0, 0], 'deg' => 90 })
      de = door.entities
      slab(de, x + 2, z + 2, w - 4, dh - 4, front, 24, p[:steel_dk])
      slab(de, x + w * 0.09, z + dh * 0.16, w * 0.82, dh * 0.66, front, 3, gl, -1)
      bezel(de, x + w * 0.085, z + dh * 0.15, w * 0.83, dh * 0.68, front, 5, p[:chrome], 5, -1)
      vent_slots(de, x + w * 0.2, z + dh * 0.05, w * 0.6, 12, front, p[:black], 3, 18)
      hbar(de, x + w * 0.1, x + w * 0.9, z + dh - 30, front, p[:chrome], 34, 7)
      [x + 26, x + w - 26].each { |hx| cyl(de, hx, front - 26, z + 6, 5, 8, p[:steel_dk], :x, 10) } # hinge pins
    end

    # ------------------------------------------------------------------------------------------------ microwave
    def microwave(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      col = [w * 0.24, 80.0].min
      dw = w - col - 6
      gl = alpha_mat('Oven Glass', [26, 28, 32], 0.5)
      front = d + dep
      t = 8.0
      shell(ents, x, d, z, w, dep - 22, h, t, p[:body], p[:white])
      # cavity: turntable + plate
      cyl(ents, x + dw * 0.5, d + (dep - 22) * 0.5, z + t + 8, [dw * 0.42, dep * 0.42].min, 3, p[:glass], :z, 28)
      cyl(ents, x + dw * 0.5, d + (dep - 22) * 0.5, z + t + 3, 10, 6, p[:steel_dk], :z, 12)
      # control column (static)
      slab(ents, x + w - col, z + 3, col - 3, h - 6, front, 22, p[:body])
      slab(ents, x + w - col + 8, z + h * 0.62, col - 19, h * 0.24, front, 3, p[:black], -1)
      slab(ents, x + w - col + 12, z + h * 0.7, col - 27, 6, front, 3, p[:blue], -4)
      3.times { |i| slab(ents, x + w - col + 10, z + h * 0.22 + i * (h * 0.11), col - 23, h * 0.07, front, 3, p[:grey_dk], -1) }
      knob(ents, x + w - col * 0.5 - 3, front, z + h * 0.42, 9, p[:grey_dk])
      # door: hinged on the left, swings out to the front
      door = mov(ents, 'door', { 'type' => 'rot', 'pivot' => [x + 3, front, 0], 'axis' => [0, 0, 1], 'deg' => -100 })
      de = door.entities
      slab(de, x + 3, z + 3, dw, h - 6, front, 22, p[:steel_dk])
      slab(de, x + 3 + dw * 0.08, z + h * 0.14, dw * 0.84, h * 0.72, front, 3, gl, -1)
      bezel(de, x + 3 + dw * 0.07, z + h * 0.13, dw * 0.86, h * 0.74, front, 4, p[:chrome], 4, -1)
      vbar(de, x + dw - 4, z + h * 0.18, z + h * 0.82, front, p[:chrome], 22, 5)
    end

    # ------------------------------------------------------------------------------------------------ dishwasher
    # drop-down door first, then the racks (they only come out once the door is open: phases 0-0.5 / 0.5-1)
    def dishwasher(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      cs = 74.0
      front = d + dep
      t = 8.0
      shell(ents, x, d, z, w, dep - 22, h, t, p[:body], p[:steel])
      # racks (sliding): lower + upper
      levels = [z + 60, z + 60 + (h - cs - 100) * 0.52]
      levels.each_with_index do |zl, i|
        r = mov(ents, "rack#{i + 1}", { 'type' => 'lin', 'v' => [0, [dep - 60, 420.0].min, 0], 'phase' => [0.5, 1.0] })
        re = r.entities
        wire_rack(re, x + t + 10, d + 30, zl, w - 2 * t - 20, dep - 22 - 60, p[:chrome], 30)
        box(re, x + t + 10, d + 30, zl, w - 2 * t - 20, 3, 36, p[:chrome]) # back stop
        n = ((w - 2 * t - 40) / 26.0).floor
        n.times { |k| cyl(re, x + t + 20 + k * 26, d + 60, zl + 3, 1.6, 34, p[:chrome], :z, 6) } if i.zero? # tines
        [x + t + 12, x + w - t - 14].each { |xx| box(re, xx, d + 30, zl - 10, 3, dep - 22 - 60, 10, p[:steel_dk]) } # rack runners
      end
      cyl(ents, x + w * 0.5, d + (dep - 22) * 0.5, z + 4 + (h - cs - 100) * 0.52 + 40, 50, 4, p[:steel_dk], :z, 20) if false
      cyl(ents, x + w * 0.5, d + (dep - 22) * 0.5, z + 4 + (h - cs - 100) * 0.52 + 46, 6, 8, p[:chrome], :z, 8) # spray arm hub
      box(ents, x + w * 0.5 - 90, d + (dep - 22) * 0.5 - 4, z + 4 + (h - cs - 100) * 0.52 + 52, 180, 8, 3, p[:steel_dk])
      # door: bottom hinge
      door = mov(ents, 'door', { 'type' => 'rot', 'pivot' => [x + w / 2.0, front, z + 2], 'axis' => [1, 0, 0], 'deg' => 90, 'phase' => [0.0, 0.5] })
      de = door.entities
      rslab(de, x + 2, z + 2, w - 4, h - cs - 4, front, 22, p[:door])
      slab(de, x + 2, z + h - cs, w - 4, cs - 2, front, 22, p[:black])
      slab(de, x + w * 0.5 - 50, z + h - cs + 30, 100, 10, front, 3, p[:blue], -1)
      6.times { |i| slab(de, x + 24 + i * ((w - 60) / 5.0), z + h - cs + 12, 12, 8, front, 3, p[:grey_dk], -1) }
      knob(de, x + w - 42, front, z + h - cs * 0.5 + 6, 13, p[:grey_dk])
      hbar(de, x + 50, x + w - 50, z + h - cs - 46, front, p[:chrome], 30, 8)
      slab(de, x + 10, z + 6, w - 20, 12, front, 6, p[:steel_dk], -1)
      seal_h(de, x + 2, x + w - 2, z + h - cs - 3, front, p[:black])
      bezel(de, x + 6, z + h - cs + 4, w - 12, cs - 10, front, 3, p[:steel_dk], 4, -1)
      # door inner liner (visible when the door is down): steel panel + gasket frame
      box(de, x + 8, front - 30, z + 10, w - 16, 8, h - cs - 24, p[:steel])
      bezel(de, x + 6, z + 8, w - 12, h - cs - 20, front - 22, 4, p[:rubber], 6, 0)
    end

    # ------------------------------------------------------------------------------------------------ washer / dryer
    def drum_front(ents, x, d, z, w, dep, h, cx, cz, r_open, front, p)
      # body with a real round opening in the front plate
      body_d = dep # `dep` is already the body depth (the door bulges into the last 26 mm of the nominal depth)
      shell(ents, x, d, z, w, body_d - 20, h, 10, p[:white], p[:grey_dk])
      plate_with_hole(ents, x, d + body_d - 20, z, w, h, cx, cz, r_open, 20, p[:white])
      # drum: hollow cylinder behind the opening
      ring(ents, cx, d + 70, cz, r_open + 6, r_open - 2, body_d - 90, pal[:steel_dk], :y, 40)
      cyl(ents, cx, d + 70, cz, r_open - 4, 4, pal[:grey_dk], :y, 40)
      # the drum as it is seen through the door glass: the owner's photo on a disc just behind the opening
      back = cyl(ents, cx, d + body_d - 70, cz, r_open + 2, 2, pal[:grey_dk], :y, 48)
      drum_picture(back, r_open + 2)
      body_d
    end

    # the back of the drum seen through the door glass: the owner's drum photo (assets/tex/dev/washer_drum.jpg), one picture across the
    # whole disc, centred on it
    def drum_picture(g, r)
      path = File.join(EGC::DIR, 'assets', 'tex', 'dev', 'washer_drum.jpg')
      return unless g && File.file?(path)

      model = Sketchup.active_model
      m = model.materials['EGC Washer Drum'] || model.materials.add('EGC Washer Drum')
      m.texture = path unless m.texture
      f = g.entities.grep(Sketchup::Face).min_by { |ff| ff.normal.y }
      return unless f

      y = f.vertices.first.position.y
      q = ->(u, v) { Geom::Point3d.new(Geo.mm(u), y, Geo.mm(v)) }
      f.position_material(m, [q.call(-r, -r), [0, 0], q.call(r, -r), [1, 0], q.call(r, r), [1, 1]], true)
    rescue StandardError
      nil
    end

    # THE HINGE of a round washer / dryer door (owner: "the door has no hinges"): a plate on the machine front with two knuckles, and the
    # door's own arm with the middle knuckle, all on the turning axis (px, pd) - side -1 = hinged on the left of the ring, +1 on the right
    def drum_door_hinge(fixed, door_ents, px, pd, cz, side, p)
      box(fixed, px - (side.negative? ? 18 : 4), pd - 2, cz - 80, 22, 4, 160, p[:chrome])
      [cz - 80, cz + 38].each { |zz| cyl(fixed, px, pd, zz, 6.5, 42, p[:chrome], :z, 14) }
      cyl(door_ents, px, pd, cz - 36, 6.5, 72, p[:chrome], :z, 14)
      box(door_ents, side.negative? ? px : px - 22, pd - 6, cz - 30, 22, 12, 60, p[:chrome])
    end

    def washer(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      feet(ents, x, d, z, w, dep, p[:rubber], 8)
      z += 8.0
      h -= 8.0
      front = d + dep - 26
      gl = alpha_mat('Washer Glass', [40, 52, 60], 0.45)
      cx = x + w * 0.5
      cz = z + (h - 90) * 0.5
      ro = [w * 0.36, (h - 130) * 0.5 - 6].min
      drum_front(ents, x, d, z, w, dep - 26, h, cx, cz, ro, front, p)
      # control panel: detergent drawer, display, program dial, buttons
      slab(ents, x + 6, z + h - 80, w - 12, 70, front - 2, 6, p[:body])
      slab(ents, x + 16, z + h - 62, 92, 34, front - 2, 8, p[:steel_dk], -4)         # detergent drawer front
      slab(ents, x + 26, z + h - 52, 72, 6, front - 2, 3, p[:black], -4)
      slab(ents, x + w * 0.5 - 40, z + h - 60, 80, 30, front - 2, 3, p[:black], -1)  # display
      slab(ents, x + w * 0.5 - 30, z + h - 50, 60, 8, front - 2, 3, p[:blue], -4)
      knob(ents, x + w - 64, front - 2, z + h - 45, 20, p[:grey_dk])                 # program dial
      3.times { |i| slab(ents, x + w - 130 + i * 20, z + h - 30, 12, 8, front - 2, 3, p[:grey_dk], -4) }
      # door: chrome ring + curved glass + latch; hinged on the left of the ring
      door = mov(ents, 'door', { 'type' => 'rot', 'pivot' => [cx - ro - 14, front, 0], 'axis' => [0, 0, 1], 'deg' => -110 })
      de = door.entities
      drum_door_hinge(ents, de, cx - ro - 14, front, cz, -1, p)
      ring(de, cx, front - 10, cz, ro + 14, ro - 2, 34, p[:chrome], :y, 40)
      cyl(de, cx, front - 4, cz, ro - 3, 4, gl, :y, 40)
      cyl(de, cx, front + 14, cz, ro * 0.62, 18, gl, :y, 36)                          # glass bowl
      box(de, cx + ro + 4, front + 6, cz - 18, 8, 14, 36, p[:steel_dk])              # latch
    end

    def dryer(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      feet(ents, x, d, z, w, dep, p[:rubber], 8)
      z += 8.0
      h -= 8.0
      front = d + dep - 26
      gl = alpha_mat('Dryer Glass', [44, 50, 58], 0.4)
      cx = x + w * 0.5
      cz = z + (h - 70) * 0.5 - 30
      ro = [w * 0.34, (h - 190) * 0.5 - 6].min
      drum_front(ents, x, d, z, w, dep - 26, h, cx, cz, ro, front, p)
      # control band: big central dial, display, six buttons
      slab(ents, x + 6, z + h - 80, w - 12, 72, front - 2, 6, p[:body])
      cyl(ents, x + w * 0.5, front - 2, z + h - 46, 26, 12, p[:steel_dk], :y, 28)
      cyl(ents, x + w * 0.5, front + 8, z + h - 46 + 16, 2.5, 3, p[:white], :y, 8)
      slab(ents, x + w - 150, z + h - 58, 96, 34, front - 2, 3, p[:black], -1)
      slab(ents, x + w - 140, z + h - 46, 76, 8, front - 2, 3, p[:blue], -4)
      6.times { |i| slab(ents, x + 24 + i * 22, z + h - 40, 14, 10, front - 2, 3, p[:grey_dk], -1) }
      # lint-filter / condenser drawer (bottom) with its own handle
      slab(ents, x + w * 0.16, z + 26, w * 0.68, 44, front - 2, 8, p[:steel_dk], -1)
      slab(ents, x + w * 0.3, z + 40, w * 0.4, 6, front - 2, 3, p[:chrome], -2)
      vent_slots(ents, x + w * 0.18, z + 12, w * 0.64, 14, front - 2, p[:black], 3, 22)
      door = mov(ents, 'door', { 'type' => 'rot', 'pivot' => [cx + ro + 10, front, 0], 'axis' => [0, 0, 1], 'deg' => 110 })
      de = door.entities
      drum_door_hinge(ents, de, cx + ro + 10, front, cz, 1, p)
      ring(de, cx, front - 10, cz, ro + 10, ro - 4, 28, p[:steel_dk], :y, 40)                # dark trim ring (dryers: no chrome ring)
      cyl(de, cx, front - 4, cz, ro - 5, 4, gl, :y, 40)
      box(de, cx - ro - 14, front + 4, cz - 22, 8, 12, 44, p[:steel_dk])                     # latch on the free side
    end

    # ------------------------------------------------------------------------------------------------ wine / beverage cooler
    def wine_cooler(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      front = d + dep
      gl = alpha_mat('Cooler Glass', [120, 150, 165], 0.22)
      t = 10.0
      shell(ents, x, d, z, w, dep - 30, h, t, p[:body], p[:grey_dk])
      n = 5
      n.times do |i|
        zz = z + 30 + i * ((h - 90) / (n - 0.6))
        [x + t + 4, x + w - t - 7].each { |xx| box(ents, xx, d + 24, zz - 2, 3, dep - 30 - 40, 3, p[:steel_dk]) }
        wire_rack(ents, x + t + 8, d + 24, zz, w - 2 * t - 16, dep - 30 - 40, p[:wood], 30)
        # bottles lying on the rack (two rows of 5)
        2.times { |rw| 5.times { |c| cyl(ents, x + t + 30 + c * ((w - 2 * t - 60) / 4.0), d + 34 + rw * 90, zz + 11, 38, 0.1, p[:zone], :y, 6) } } if false
        4.times { |c| cyl(ents, x + t + 40 + c * ((w - 2 * t - 80) / 3.0), d + 30, zz + 4, 34, 170, p[:cast], :y, 10) } # bottles stay inside the side walls
      end
      box(ents, x + t + 10, d + 20, z + h - t - 8, w - 2 * t - 20, 4, 4, p[:led]) # LED strip under the top
      slab(ents, x + 12, z + 4, w - 24, 14, front - 2, 6, p[:steel_dk], -1)         # base grille
      vent_slots(ents, x + 30, z + 8, w - 60, 12, front - 2, p[:black], 3, 24)
      # glass door: dark frame + REAL transparent glass (racks and bottles stay visible), hinged on the left
      door = mov(ents, 'door', { 'type' => 'rot', 'pivot' => [x + 2, front, 0], 'axis' => [0, 0, 1], 'deg' => -105 })
      de = door.entities
      fw = 20.0
      slab(de, x + 2, z + 22, w - 4, fw, front, 30, p[:steel_dk])
      slab(de, x + 2, z + h - fw - 2, w - 4, fw, front, 30, p[:steel_dk])
      slab(de, x + 2, z + 22 + fw, fw, h - 44 - 2 * fw + 20, front, 30, p[:steel_dk])
      slab(de, x + w - 2 - fw, z + 22 + fw, fw, h - 44 - 2 * fw + 20, front, 30, p[:steel_dk])
      slab(de, x + 2 + fw, z + 22 + fw, w - 4 - 2 * fw, h - 44 - 2 * fw + 20, front - 12, 4, gl, 0)
      vbar(de, x + w - 34, z + h * 0.25, z + h * 0.75, front, p[:chrome], 26, 6)
      slab(de, x + w * 0.5 - 30, z + h - 20, 60, 4, front, 3, p[:blue], -4)
    end

    # ------------------------------------------------------------------------------------------------ fridges
    # interior shared by every refrigerator body: glass shelves, crisper drawers
    def fridge_interior(ents, x, d, z, w, dep, h, p, shelves = 4)
      gl = alpha_mat('Shelf Glass', [190, 214, 224], 0.55)
      shelves.times { |i| box(ents, x + 12, d + 30, z + 60 + (i + 1) * ((h - 200) / (shelves + 1.0)), w - 24, dep - 60, 4, gl) }
      box(ents, x + 12, d + 30, z + 20, w - 24, dep - 60, 110, p[:white]) # crisper
      box(ents, x + 12, d + 30 + dep - 60 - 3, z + 20, w - 24, 3, 110, p[:steel_dk])
    end

    def door_bins(ents, x, front, z, w, h, p, n = 3)
      n.times { |i| box(ents, x + 10, front - 26, z + 40 + i * ((h - 120) / n.to_f), w - 20, 22, 6, p[:white]) }
    end

    # TOP-FREEZER refrigerator (the common free-standing type): small freezer door above, refrigerator door below, both hinged on the
    # right; dark grip handles lying along the gap between the doors, dark base. Generic - no maker's model.
    def fridge_top(ents, x, d, z, w, dep, h, p)
      front = d + dep
      body_d = dep - 30
      base = 60.0
      steel = mat('Fridge Steel', [198, 201, 204])
      box(ents, x, d, z, w, body_d, base, p[:rubber])                                  # dark base under the cabinet
      box(ents, x + 3, front - 32, z, w - 6, 30, base - 4, p[:rubber])                 # kick strip under the door
      vent_slots(ents, x + 40, z + 14, w - 80, 12, front - 2, p[:grey_dk], 3, 24)
      z += base
      h -= base
      split = (h * 0.72).round(1)                                                      # refrigerator below, freezer above
      shell(ents, x, d, z, w, body_d, split, 12.0, steel, p[:white])
      fridge_interior(ents, x, d, z, w, body_d, split, p, 4)
      shell(ents, x, d, z + split, w, body_d, h - split, 12.0, steel, p[:white])
      box(ents, x + 12, d + 30, z + split + (h - split) * 0.5, w - 24, body_d - 60, 4, p[:white]) # freezer shelf
      box(ents, x + 2, front - 31, z + split - 3, w - 4, 3, 6, p[:black])              # dark gasket line between the doors
      lower = mov(ents, 'door_fridge', { 'type' => 'rot', 'pivot' => [x + w - 2, front, 0], 'axis' => [0, 0, 1], 'deg' => 100 })
      e = lower.entities
      rslab(e, x + 2, z + 2, w - 4, split - 6, front, 30, steel)
      hbar(e, x + 26, x + w * 0.52, z + split - 46, front, p[:rubber], 30, 10)         # grip along the top of the lower door
      door_bins(e, x, front, z, w, split, p, 4)
      upper = mov(ents, 'door_freezer', { 'type' => 'rot', 'pivot' => [x + w - 2, front, 0], 'axis' => [0, 0, 1], 'deg' => 100 })
      e = upper.entities
      rslab(e, x + 2, z + split + 2, w - 4, h - split - 4, front, 30, steel)
      hbar(e, x + 26, x + w * 0.52, z + split + 44, front, p[:rubber], 30, 10)         # grip along the bottom of the freezer door
      door_bins(e, x, front, z + split, w, h - split, p, 1)
      slab(e, x + w - 86, z + h - 46, 56, 14, front, 2, p[:grey_dk], -1)               # badge plate (blank)
      [z + 6, z + split - 2, z + h - 16].each { |hz| box(ents, x + w - 44, front - 34, hz, 40, 34, 10, p[:grey_dk]) } # hinge blocks
    end

    def fridge(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      under = h < 1200
      fh = under ? 8.0 : 10.0
      feet(ents, x, d, z, w, dep, p[:rubber], fh)
      z += fh
      h -= fh
      front = d + dep
      t = 12.0
      body_d = dep - 30
      return fridge_top(ents, x, d, z, w, dep, h, p) if _cfg['fridge_style'].to_s == 'top' && !under && w < 800
      if under # under-counter: shell, small freezer flap on top + main door, LEFT hinge
        shell(ents, x, d, z, w, body_d, h, t, p[:body], p[:white])
        fridge_interior(ents, x, d, z, w, body_d, h, p, 2)
        door = mov(ents, 'door', { 'type' => 'rot', 'pivot' => [x + 2, front, 0], 'axis' => [0, 0, 1], 'deg' => -100 })
        de = door.entities
        rslab(de, x + 2, z + 2, w - 4, h - 4, front, 30, p[:door])
        seal_h(de, x + 4, x + w - 4, z + h - 120, front, p[:black], 4)                 # freezer flap line
        slab(de, x + w * 0.5 - 40, z + h - 60, 80, 8, front, 3, p[:black], -1)
        vbar(de, x + w - 30, z + h * 0.32, z + h * 0.72, front, p[:chrome], 26, 6)
        door_bins(de, x, front, z, w, h - 140, p, 3)
        return
      end
      if w >= 800 # side-by-side: freezer left with water dispenser, fridge right; each door has its own hinge
        fw = w * 0.4
        shell(ents, x, d, z, w, body_d, h, t, p[:body], p[:white])
        box(ents, x + fw - 4, d + 12, z + 12, 8, body_d - 12, h - 24, p[:body]) # centre wall
        fridge_interior(ents, x + fw, d, z, w - fw, body_d, h, p, 5)
        fridge_interior(ents, x, d, z, fw, body_d, h, p, 4)
        dl = mov(ents, 'door_freezer', { 'type' => 'rot', 'pivot' => [x + 2, front, 0], 'axis' => [0, 0, 1], 'deg' => -100 })
        e = dl.entities
        rslab(e, x + 2, z + 4, fw - 3, h - 8, front, 30, p[:door])
        slab(e, x + fw * 0.5 - 60, z + h * 0.52, 120, 200, front, 3, p[:black], -1)
        slab(e, x + fw * 0.5 - 45, z + h * 0.52 + 120, 90, 50, front, 3, p[:blue], -4)
        box(e, x + fw * 0.5 - 35, front - 20, z + h * 0.52 + 30, 70, 20, 10, p[:steel_dk])
        bezel(e, x + fw * 0.5 - 66, z + h * 0.52 - 6, 132, 212, front, 3, p[:chrome], 3, -2)
        slab(e, x + fw * 0.5 - 50, z + h * 0.52 - 12, 100, 10, front, 14, p[:chrome], 0)
        vbar(e, x + fw - 22, z + h * 0.35, z + h * 0.35 + 620, front, p[:chrome], 30, 8)
        door_bins(e, x, front, z, fw, h, p, 4)
        dr = mov(ents, 'door_fridge', { 'type' => 'rot', 'pivot' => [x + w - 2, front, 0], 'axis' => [0, 0, 1], 'deg' => 100 })
        e = dr.entities
        rslab(e, x + fw + 1, z + 4, w - fw - 3, h - 8, front, 30, p[:door])
        vbar(e, x + fw + 20, z + h * 0.35, z + h * 0.35 + 620, front, p[:chrome], 30, 8)
        door_bins(e, x + fw, front, z, w - fw, h, p, 4)
        [x + 12, x + w - 40].each { |hx| [z + 8, z + h - 30].each { |hz| slab(ents, hx, hz, 28, 22, front, 3, p[:grey_dk], -1) } }
        vent_slots(ents, x + 30, z + 4, w - 60, 14, front, p[:black], 3, 28)
        return
      end
      # tall bottom-freezer: fridge door (hinged on the right) + freezer drawer front (slides)
      split = h * 0.32
      shell(ents, x, d, z + split, w, body_d, h - split, t, p[:body], p[:white])
      fridge_interior(ents, x, d, z + split, w, body_d, h - split, p, 4)
      shell(ents, x, d, z, w, body_d, split, t, p[:body], p[:white])
      wire_rack(ents, x + 16, d + 30, z + 50, w - 32, body_d - 60, p[:chrome], 30)
      door = mov(ents, 'door_fridge', { 'type' => 'rot', 'pivot' => [x + w - 2, front, 0], 'axis' => [0, 0, 1], 'deg' => 100 })
      de = door.entities
      rslab(de, x + 2, z + split + 2, w - 4, h - split - 4, front, 30, p[:door])
      seal_h(de, x + 5, x + w - 5, z + split + 5, front, p[:black], 5) # distinct freezer/ refrigerator door break
      slab(de, x + w * 0.5 - 40, z + h - 120, 80, 40, front, 3, p[:black], -1)
      slab(de, x + w * 0.5 - 30, z + h - 108, 60, 6, front, 3, p[:blue], -4)
      vbar(de, x + 34, z + split + 60, z + split + 60 + [h * 0.3, 420].min, front, p[:chrome], 30, 8)
      door_bins(de, x, front, z + split, w, h - split, p, 5)
      dw = mov(ents, 'drawer_freezer', { 'type' => 'lin', 'v' => [0, body_d - 120, 0] })
      e = dw.entities
      rslab(e, x + 2, z + 2, w - 4, split - 6, front, 30, p[:door])
      vbar(e, x + 34, z + split * 0.25, z + split * 0.25 + [split * 0.6, 260].min, front, p[:chrome], 30, 8)
      box(e, x + 14, d + 40, z + 24, w - 28, body_d - 60, 4, p[:white])
      box(e, x + 14, d + 40, z + 24, 4, body_d - 60, split - 70, p[:white])
      box(e, x + w - 18, d + 40, z + 24, 4, body_d - 60, split - 70, p[:white])
    end

    # tall freezer: stacked drawers that pull out in sequence
    def freezer(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      feet(ents, x, d, z, w, dep, p[:rubber], 10)
      z += 10.0
      h -= 10.0
      front = d + dep
      n = h > 1500 ? 5 : 3
      body_d = dep - 30
      shell(ents, x, d, z, w, body_d, h, 12, p[:body], p[:white])
      # one full-height door (hinged on the right, like the refrigerator next to it); the drawers are INSIDE, behind it
      door = mov(ents, 'door', { 'type' => 'rot', 'pivot' => [x + w - 2, front, 0], 'axis' => [0, 0, 1], 'deg' => 100, 'phase' => [0.0, 0.45] })
      de = door.entities
      rslab(de, x + 2, z + 2, w - 4, h - 4, front, 30, p[:door])
      slab(de, x + w * 0.5 - 40, z + h - 120, 80, 40, front, 3, p[:black], -1)
      slab(de, x + w * 0.5 - 30, z + h - 108, 60, 6, front, 3, p[:blue], -4)
      vbar(de, x + 34, z + h * 0.42, z + h * 0.42 + [h * 0.3, 520].min, front, p[:chrome], 30, 8)
      inner = body_d - 60
      dh = (h - 140) / n
      n.times do |i|
        dr = mov(ents, "drawer#{i + 1}", { 'type' => 'lin', 'v' => [0, inner - 60, 0], 'phase' => [0.5 + 0.08 * i, 0.8 + 0.04 * i] })
        e = dr.entities
        zi = z + 40 + i * dh
        box(e, x + 18, d + 30 + inner - 6, zi, w - 36, 6, dh - 30, p[:smoke])   # clear bin front
        box(e, x + 18, d + 30, zi, w - 36, inner, 3, p[:white])
        box(e, x + 18, d + 30, zi, 3, inner, dh - 46, p[:white])
        box(e, x + w - 21, d + 30, zi, 3, inner, dh - 46, p[:white])
        box(e, x + 18, d + 30, zi, w - 36, 3, dh - 46, p[:white])
        box(e, x + w * 0.5 - 50, d + 30 + inner, zi + dh - 60, 100, 4, 18, p[:white]) # grip
      end
    end

    def warming_drawer(ents, x, d, z, w, dep, h, _cfg = {})
      p = pal
      front = d + dep
      shell(ents, x, d, z, w, dep - 22, h, 6, p[:body], p[:steel])
      dr = mov(ents, 'drawer', { 'type' => 'lin', 'v' => [0, dep - 120, 0] })
      e = dr.entities
      slab(e, x + 2, z + 2, w - 4, h - 4, front, 22, p[:door])
      slab(e, x + 8, z + h - 30, w - 16, 20, front, 3, p[:black], -1)
      slab(e, x + w * 0.5 - 28, z + h - 24, 56, 6, front, 3, p[:blue], -4)
      hbar(e, x + w * 0.16, x + w * 0.84, z + h * 0.4, front, p[:chrome], 26, 6)
      box(e, x + 10, d + 30, z + 10, w - 20, dep - 80, 3, p[:steel])
    end

  end
end
