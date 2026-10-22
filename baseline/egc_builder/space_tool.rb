# frozen_string_literal: true

module EGC
  # SPACE TOOL - live clear dimensions of the void INSIDE a unit, and adding a shelf / divider from that context.
  #  * Space.void_at(unit, x, d, z): the largest empty rectangle around a point of the unit's own frame, measured from the REAL built
  #    boards (carcass, shelves, dividers, drawer boxes) - never from the spec - so it is right after any Resize / Divide / Reload.
  #  * SpaceTool: hover a unit (front doors are ignored, the ray goes to the first empty point behind the front), click to LOCK a void;
  #    the locked point is stored in the unit's own frame, so the overlay keeps showing the CURRENT clear W x H x D while you keep
  #    working (resize, add shelves, move the unit) and after Save / Reopen (stored on the unit).
  #  * keys while the tool is active:  S = add a shelf at the locked height,  V = add a vertical divider at the locked position,
  #    U = remove the last added shelf/divider,  Esc = leave.  Each is one Undo step and rebuilds the unit from its spec (cutlist
  #    and production data stay the single truth: the additions live in spec[:extras]).
  module Space
    OBST = %w[side_l side_r bottom top divider vdivider col_divider shelf top_rail_f top_rail_b front_strip drawer_side drawer_bottom drawer_back
              drawer_subfront].freeze
    ATTR = 'egc'
    module_function

    def unit?(g)
      g.is_a?(Sketchup::Group) && !!(g.get_attribute(ATTR, 'spec') || g.get_attribute(ATTR, 'wardrobe'))
    end

    # nearest E.G.C unit in a raytest path (or nil)
    def unit_in_path(path)
      (path || []).reverse_each { |e| return e if unit?(e) }
      nil
    end

    def accumulated(unit)
      tr = unit.transformation
      owner = Kitchen.find_owner_group(unit)
      while owner
        tr = owner.transformation * tr
        owner = Kitchen.find_owner_group(owner)
      end
      tr
    end

    # builder frame (mm): x along the unit, d from the back toward the room, z up  <->  unit-local model point
    def to_builder(p)
      [p.x.to_mm, -p.y.to_mm, p.z.to_mm]
    end

    def from_builder(x, d, z)
      Geom::Point3d.new(x.mm, -d.mm, z.mm)
    end

    # boards of a unit as builder-frame boxes { n:, x0:, x1:, d0:, d1:, z0:, z1: }
    def boards(unit)
      out = []
      walk = lambda do |ents, tr|
        ents.each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)

          etr = tr * e.transformation
          role = e.get_attribute(ATTR, 'role')
          if role
            part = e.get_attribute(ATTR, 'part').to_s
            next unless role == 'part' && (OBST.include?(part) || part == 'back')

            lb = e.respond_to?(:local_bounds) ? e.local_bounds : e.definition.bounds
            pts = (0..7).map { |i| etr * lb.corner(i) }.map { |q| to_builder(q) }
            out << { n: part, x0: pts.map { |q| q[0] }.min, x1: pts.map { |q| q[0] }.max, d0: pts.map { |q| q[1] }.min,
                     d1: pts.map { |q| q[1] }.max, z0: pts.map { |q| q[2] }.min, z1: pts.map { |q| q[2] }.max }
          else
            walk.call(e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities, etr)
          end
        end
      end
      walk.call(unit.entities, Geom::Transformation.new)
      out
    end

    # Largest empty rectangle (x/z) around (x, z) at depth d, plus the clear depth (back panel face -> carcass front).
    # -> { x0:, x1:, z0:, z1:, d0:, d1:, w:, h:, d: } (mm) or nil when the point is inside a board / outside the carcass.
    def void_at(unit, x, d, z, list = nil)
      bs = list || boards(unit)
      sides = bs.select { |b| %w[side_l side_r].include?(b[:n]) }
      return nil if sides.empty?

      cw0 = sides.map { |b| b[:x0] }.min
      cw1 = sides.map { |b| b[:x1] }.max
      cz0 = sides.map { |b| b[:z0] }.min
      cz1 = sides.map { |b| b[:z1] }.max
      front = sides.map { |b| b[:d1] }.max
      back = bs.select { |b| b[:n] == 'back' }.map { |b| b[:d1] }.max || sides.map { |b| b[:d0] }.min
      return nil unless x > cw0 && x < cw1 && z > cz0 && z < cz1 && d > back - 1 && d < front + 1

      d = [[d, back + 15.0].max, front - 40.0].min # evaluate inside the carcass: shelves stop 20 mm short of the front, and at the front plane no board cuts through
      obs = bs.select { |b| b[:n] != "back" && d > b[:d0] + 0.5 && d < b[:d1] - 0.5 } # boards that cut through this depth
      return nil if obs.any? { |b| x > b[:x0] && x < b[:x1] && z > b[:z0] && z < b[:z1] }

      left = obs.select { |b| b[:x1] <= x + 0.01 && z > b[:z0] && z < b[:z1] }.map { |b| b[:x1] }.max || cw0
      right = obs.select { |b| b[:x0] >= x - 0.01 && z > b[:z0] && z < b[:z1] }.map { |b| b[:x0] }.min || cw1
      low = obs.select { |b| b[:z1] <= z + 0.01 && b[:x1] > left + 0.5 && b[:x0] < right - 0.5 }.map { |b| b[:z1] }.max || cz0
      high = obs.select { |b| b[:z0] >= z - 0.01 && b[:x1] > left + 0.5 && b[:x0] < right - 0.5 }.map { |b| b[:z0] }.min || cz1
      { x0: left, x1: right, z0: low, z1: high, d0: back, d1: front, w: right - left, h: high - low, d: front - back }
    end

    # picks the first empty point behind the front along a ray (unit-local ray, mm builder frame)
    def probe(unit, ray_local)
      bs = boards(unit)
      sides = bs.select { |b| %w[side_l side_r].include?(b[:n]) }
      return nil if sides.empty?

      o = to_builder(ray_local[0])
      v = [ray_local[1].x, -ray_local[1].y, ray_local[1].z]
      len = Math.sqrt(EGC::Num.sum(v) { |q| q * q })
      v = v.map { |q| q / len }
      5000.times do |i|
        t = i * 3.0
        x = o[0] + v[0] * t
        d = o[1] + v[1] * t
        z = o[2] + v[2] * t
        hit = void_at(unit, x, d, z, bs)
        return { pt: [x, d, z], void: hit, boards: bs } if hit
      end
      nil
    end

    # ---- locked void (per model, survives save/reopen on the unit) ---------------------------------------
    def lock(unit, x, d, z)
      unit.set_attribute(ATTR, 'space_pt', [x, d, z])
      @locked = unit
    end

    def unlock
      @locked&.delete_attribute(ATTR, 'space_pt') if @locked&.valid?
      @locked = nil
    end

    def locked_unit(model)
      return @locked if @locked&.valid?

      found = nil
      walk = lambda do |ents|
        ents.each do |e|
          next unless e.is_a?(Sketchup::Group)

          if unit?(e) && e.get_attribute(ATTR, 'space_pt')
            found = e
            return
          end
          walk.call(e.entities) unless e.get_attribute(ATTR, 'role')
        end
      end
      walk.call(model.entities)
      @locked = found
    end

    def locked_void(unit)
      pt = unit.get_attribute(ATTR, 'space_pt')
      return nil unless pt.is_a?(Array) && pt.size == 3

      v = void_at(unit, pt[0], pt[1], pt[2])
      # after a resize the point may sit on a moved board: nudge toward the middle of the unit's opening
      v || void_at(unit, pt[0], pt[1], pt[2] + 4)
    end

    # ---- adding a shelf / divider inside the locked void -------------------------------------------------
    def ward?(unit)
      !!unit.get_attribute(ATTR, 'wardrobe')
    end

    # the additions of a unit: spec[:extras] of a cabinet, params['extras'] of a wardrobe of the dressing designer
    def extras_of(unit)
      if ward?(unit)
        Array(JSON.parse(unit.get_attribute(ATTR, 'params').to_s)['extras']).map { |e| e.transform_keys(&:to_sym) }
      else
        spec = Cabinet.spec_from_json(unit.get_attribute(ATTR, 'spec'))
        raise 'this unit has a mechanism: its interior is fixed' if spec[:mech]

        Array(spec[:extras])
      end
    end

    # opt: 'drop' = hanging rail, mm below the top of the space; 'heights' = drawer front heights from the bottom up (shared out over the space)
    def add_extra(unit, kind, count = nil, opt = {})
      pt = unit.get_attribute(ATTR, 'space_pt')
      raise 'lock a void first (click inside the unit)' unless pt

      v = void_at(unit, pt[0], pt[1], pt[2])
      raise 'the locked point is no longer inside an empty space' unless v

      ward = ward?(unit)
      t = Config.build['thk'].to_f
      ex = extras_of(unit)
      case kind
      when 'shelf'
        raise 'the void is too low for a shelf' if v[:h] < 2 * t + 60

        ex << { type: "shelf", x0: v[:x0], x1: v[:x1], z: (pt[2] - t / 2.0).round(1) }
        unit.set_attribute(ATTR, "space_pt", [pt[0], pt[1], pt[2] + t / 2.0 + 10.0]) # the lock moves to the space ABOVE the new shelf
      when 'divider'
        raise 'the void is too narrow for a divider' if v[:w] < 2 * t + 60

        ex << { type: "divider", x: (pt[0] - t / 2.0).round(1), z0: v[:z0], z1: v[:z1] }
        unit.set_attribute(ATTR, "space_pt", [pt[0] + t / 2.0 + 10.0, pt[1], pt[2]]) # ... or to the RIGHT of the new divider
      when 'shelves' # several shelves spread evenly over the height of the space
        n = (count || 2).to_i.clamp(1, 8)
        raise "the space is too low for #{n} shelves | الفراغ قليل الارتفاع على #{n} رفوف" if v[:h] < n * (t + 80) + 80

        clear = (v[:h] - n * t) / (n + 1.0)
        n.times { |i| ex << { type: 'shelf', x0: v[:x0], x1: v[:x1], z: (v[:z0] + clear * (i + 1) + t * i).round(1) } }
      when 'drawers', 'doors'
        raise 'the doors of a wardrobe come from the dressing designer (hinged / sliding / none) | ضلف الدولاب بتتحدد من مصمم الدريسنج (مفصلات / سحاب / بدون)' if ward && kind == 'doors'

        hs = kind == 'drawers' ? Array((opt || {})['heights']).map(&:to_f).select(&:positive?).first(6) : []
        n = kind == 'drawers' ? (hs.empty? ? (count || 3).to_i.clamp(1, 6) : hs.size) : count.to_i
        front_free!(unit, v) unless ward # the drawers of a wardrobe are inner drawers behind its doors, like the ones of the designer
        if hs.any? && v[:h] * hs.min / hs.sum < 90
          raise "with these heights the smallest drawer front would be #{(v[:h] * hs.min / hs.sum).round} mm in this space (90 at least) | بالارتفاعات دي أصغر وش درج هيبقى #{(v[:h] * hs.min / hs.sum).round} مم في الفراغ ده (90 على الأقل)"
        end
        raise "the space is too narrow (#{v[:w].round} mm) | الفراغ ضيق (#{v[:w].round} مم)" if v[:w] < (kind == 'drawers' ? 250 : 200)
        raise "the space is too low for #{n} drawers (#{v[:h].round} mm) | الفراغ قليل الارتفاع على #{n} أدراج (#{v[:h].round} مم)" if kind == 'drawers' && v[:h] < n * 110
        raise "the space is too low for a door (#{v[:h].round} mm) | الفراغ قليل الارتفاع على ضلفة (#{v[:h].round} مم)" if kind == 'doors' && v[:h] < 200

        ex << { type: 'fill', cell: kind, n: n, x0: v[:x0].round(1), x1: v[:x1].round(1), z0: v[:z0].round(1), z1: v[:z1].round(1) }.merge(hs.empty? ? {} : { ratio: hs })
      when 'rail'
        raise "a hanging rail needs a space at least 300 wide and 400 high | ماسورة التعليق تحتاج فراغ 300 عرض و 400 ارتفاع على الأقل" if v[:w] < 300 || v[:h] < 400

        drop = (opt || {})['drop'].to_f
        drop = 60.0 unless drop.positive?
        raise "the rail goes 45 to #{(v[:h] - 150).round} mm below the top of this space | الماسورة تتركب من 45 إلى #{(v[:h] - 150).round} مم تحت سقف الفراغ ده" unless drop.between?(45, v[:h] - 150)

        ex << { type: 'rail', x0: v[:x0].round(1), x1: v[:x1].round(1), z: (v[:z1] - drop - 15.0).round(1) }
      else
        raise "unknown extra #{kind}"
      end
      apply_extras(unit, ex)
    end

    # drawers / doors go into a space that is open to the front: refused when a front of the unit already stands in front of it
    def front_free!(unit, v)
      walk = lambda do |ents, tr|
        ents.each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)

          etr = tr * e.transformation
          part = e.get_attribute(ATTR, 'part').to_s
          if part.empty?
            walk.call(e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities, etr)
          elsif %w[door drawer_front flap trim filler].include?(part)
            lb = e.respond_to?(:local_bounds) ? e.local_bounds : e.definition.bounds
            pts = (0..7).map { |i| to_builder(etr * lb.corner(i)) }
            ox = [pts.map { |q| q[0] }.max, v[:x1]].min - [pts.map { |q| q[0] }.min, v[:x0]].max
            oz = [pts.map { |q| q[2] }.max, v[:z1]].min - [pts.map { |q| q[2] }.min, v[:z0]].max
            if ox > 10 && oz > 10
              raise 'this space is behind a front of the unit: drawers / doors can only go into a space that is open to the front (use an open unit, or the unit designer) | الفراغ ده وراه واجهة من الوحدة: الأدراج والضلف تتركب في فراغ مفتوح من قدام فقط (استخدم وحدة مفتوحة أو مصمم الوحدة)'
            end
          end
        end
      end
      walk.call(unit.entities, Geom::Transformation.new)
      true
    end

    def remove_last_extra(unit)
      ex = extras_of(unit)
      return false if ex.empty?

      ex.pop
      apply_extras(unit, ex)
      true
    end

    # rebuild the unit from its spec with the new extras (one undo step); keeps the locked point
    def apply_extras(unit, extras)
      pt = unit.get_attribute(ATTR, 'space_pt')
      model = Sketchup.active_model
      ng = nil
      EGC.safe_op(model, 'E.G.C interior') do
        ng = if ward?(unit)
               Wardrobe.rebuild(unit, JSON.parse(unit.get_attribute(ATTR, 'params').to_s).merge('extras' => extras), Config.build)
             else
               Kitchen.rebuild_cabinet(unit, { 'extras' => extras }, Config.build, manage_operation: false)
             end
        (ng || unit).set_attribute(ATTR, 'space_pt', pt) if pt
      end
      @locked = ng if ng&.valid?
      ng
    end

    # ---- drawing -----------------------------------------------------------------------------------------
    def draw_void(view, unit, v, color)
      tr = accumulated(unit)
      pts = ->(x, d, z) { tr * from_builder(x, d, z) }
      c = [[v[:x0], v[:d0], v[:z0]], [v[:x1], v[:d0], v[:z0]], [v[:x1], v[:d0], v[:z1]], [v[:x0], v[:d0], v[:z1]],
           [v[:x0], v[:d1], v[:z0]], [v[:x1], v[:d1], v[:z0]], [v[:x1], v[:d1], v[:z1]], [v[:x0], v[:d1], v[:z1]]].map { |q| pts.call(*q) }
      view.drawing_color = color
      view.line_width = 2
      view.line_stipple = ''
      view.draw(GL_LINES, [c[0], c[1], c[1], c[2], c[2], c[3], c[3], c[0], c[4], c[5], c[5], c[6], c[6], c[7], c[7], c[4],
                           c[0], c[4], c[1], c[5], c[2], c[6], c[3], c[7]])
      label = lambda do |a, b, txt|
        m = Geom::Point3d.new((a.x + b.x) / 2.0, (a.y + b.y) / 2.0, (a.z + b.z) / 2.0)
        s = view.screen_coords(m)
        view.draw_text([s.x + 4, s.y - 8], txt, { size: 12, bold: true, color: color })
      end
      label.call(c[4], c[5], "#{v[:w].round} mm")
      label.call(c[5], c[6], "#{v[:h].round} mm")
      label.call(c[0], c[4], "#{v[:d].round} mm")
      ctr = pts.call((v[:x0] + v[:x1]) / 2.0, v[:d1], (v[:z0] + v[:z1]) / 2.0)
      s = view.screen_coords(ctr)
      txt = "#{v[:w].round} × #{v[:h].round} × #{v[:d].round} mm"
      view.draw_text([s.x - txt.length * 3.5, s.y - 22], txt, { size: 14, bold: true, color: Sketchup::Color.new(255, 255, 255) })
    rescue StandardError
      nil
    end

    if defined?(Sketchup::Overlay)
      # keeps showing the LOCKED void (current dimensions) whichever tool is active - but ONLY while
      # visibility is explicitly ON (Quick Actions toggle / Esc), never a permanent guide.
      class Overlay < Sketchup::Overlay
        def initialize
          super('egc_space', 'E.G.C - Available Space')
        end

        def draw(view)
          return unless Space.visible?(view.model)

          u = Space.locked_unit(view.model)
          return unless u&.valid?

          v = Space.locked_void(u)
          Space.draw_void(view, u, v, Sketchup::Color.new(40, 150, 90)) if v
        end
      end
    end

    # Show/hide toggle for the Available Space guide, independent of the LOCK itself (the lock keeps
    # measuring the same point through Resize/Reload; visibility only controls whether it is DRAWN).
    # Off by default and after every toggle-off / Esc - never reappears on its own.
    def visible?(model = Sketchup.active_model)
      model.get_attribute(ATTR, 'space_vis_on', false) == true
    end

    def set_visible(on, model = Sketchup.active_model)
      model.set_attribute(ATTR, 'space_vis_on', on)
      model.active_view.invalidate
    rescue StandardError
      nil
    end

    def toggle_visible(model = Sketchup.active_model)
      set_visible(!visible?(model), model)
    end

    def sync(model = Sketchup.active_model)
      return false unless defined?(Sketchup::Overlay)

      ov = model.overlays.find { |o| o.overlay_id == 'egc_space' }
      unless ov
        model.overlays.add(Overlay.new)
        ov = model.overlays.find { |o| o.overlay_id == 'egc_space' }
      end
      ov.enabled = true if ov
      model.active_view.invalidate
      true
    end
  end

  class SpaceTool
    def activate
      Space.sync
      Space.set_visible(true)
      Sketchup.status_text = 'E.G.C Available Space: hover a unit, click to lock the space | S = shelf, V = divider, D = 3 drawers, O = door(s), R = hanging rail, U = undo last, Esc = hide + exit  (or use the buttons in the unit panel)'
      @hover = nil
      LiveDims.suppress(true)
    end

    def deactivate(view)
      LiveDims.suppress(false)
      view.invalidate
    end

    def onCancel(_r, _v)
      Space.set_visible(false)
      Sketchup.active_model.select_tool(nil)
    end

    def pick(view, x, y)
      ray = view.pickray(x, y)
      res = Sketchup.active_model.raytest(ray, true)
      unit = res && Space.unit_in_path(res[1])
      return nil unless unit

      inv = Space.accumulated(unit).inverse
      lr = [inv * ray[0], (inv * ray[1]).normalize]
      hit = Space.probe(unit, lr)
      hit && hit.merge(unit: unit)
    end

    def onMouseMove(_f, x, y, view)
      @hover = pick(view, x, y)
      view.invalidate
    end

    def onLButtonDown(_f, x, y, view)
      h = pick(view, x, y)
      return unless h

      Space.lock(h[:unit], *h[:pt])
      Sketchup.active_model.selection.clear
      Sketchup.active_model.selection.add(h[:unit])
      view.invalidate
    end

    def onKeyDown(key, _rep, _flags, view)
      u = Space.locked_unit(Sketchup.active_model)
      return unless u&.valid?

      case key
      when 'S'.ord then Space.add_extra(u, 'shelf')
      when 'V'.ord then Space.add_extra(u, 'divider')
      when 'U'.ord then Space.remove_last_extra(u)
      when 'D'.ord then Space.add_extra(u, 'drawers', 3)
      when 'O'.ord then Space.add_extra(u, 'doors')
      when 'R'.ord then Space.add_extra(u, 'rail')
      end
      view.invalidate
    rescue StandardError => e
      id = Diag.log('space_tool', { key: key }, error: e)
      ::UI.messagebox("E.G.C Space: #{Diag.user_message(e, id)}")
    end

    def draw(view)
      return unless @hover && @hover[:void]

      Space.draw_void(view, @hover[:unit], @hover[:void], Sketchup::Color.new(217, 164, 65))
    end
  end
end
