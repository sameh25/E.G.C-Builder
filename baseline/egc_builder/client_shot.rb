# frozen_string_literal: true

require 'json'
require 'digest'

module EGC
  # PROFESSIONAL CLIENT SHOT - camera candidates, scenes, render-ready check.
  #
  # Presentation only: cameras, scene visibility and view options change - the cabinet geometry never does (the module fingerprints the geometry before
  # and after and refuses to report success if anything moved). Walls that stand between the camera and the kitchen are hidden ONLY in the scene
  # (Page#set_drawingelement_visibility); they are never deleted, moved or re-tagged. Renderer independent: no V-Ray / Enscape / D5 needed.
  module ClientShot
    module_function

    SCENES = { 'hero' => 'EGC_Client_Hero', 'secondary' => 'EGC_Client_View_02', 'detail' => 'EGC_Client_Detail' }.freeze
    TECH_SCENE = 'EGC_Design_Technical'
    EYE_Z = 1500.0 # mm: natural standing eye height, level camera (verticals stay vertical)

    # ------------------------------------------------------------------ what is the design?
    def kitchen_roots(model)
      r = model.entities.grep(Sketchup::Group).select { |g| g.get_attribute('egc', 'kitchen') }
      a = r.select { |g| g.get_attribute('egc', 'assistant') }
      a.empty? ? r : a
    end

    def bounds_mm(ents)
      bb = Geom::BoundingBox.new
      ents.each { |e| bb.add(e.bounds) }
      bb
    end

    def mm(v)
      v.to_mm
    end

    def geometry_fingerprint(model)
      us = Exposure.collect(model)[:units].map { |u| [u.g.name, u.tr.to_a.map { |v| v.round(5) }, u.g.attribute_dictionary('egc')['spec'].to_s.size] }
      Digest::MD5.hexdigest(JSON.generate(us.sort_by(&:first)))
    end

    # ------------------------------------------------------------------ room / features
    def room_poly(proj, model, roots)
      poly = proj && proj['room'] && proj['room']['poly']
      return poly if poly && poly.size >= 3

      bb = bounds_mm(roots)
      x0 = mm(bb.min.x) - 2500
      x1 = mm(bb.max.x) + 2500
      y0 = mm(bb.min.y) - 3000
      y1 = mm(bb.max.y) + 300
      [[x0, y0], [x0, y1], [x1, y1], [x1, y0]]
    end

    def features(model)
      us = Exposure.collect(model)[:units]
      f = {}
      f['tall'] = us.select { |u| u.kind == 'tall' || u.g.get_attribute('egc', 'type').to_s == 'fridge_open' }
      f['hob'] = us.find { |u| u.g.get_attribute('egc', 'type').to_s =~ /hob/ }
      f['sink'] = us.find { |u| u.g.get_attribute('egc', 'type').to_s =~ /sink/ }
      f
    end

    def center_mm(u, z = 1100)
      p = u.tr * Geom::Point3d.new((u.w / 2.0).mm, (-u.d / 2.0).mm, z.mm)
      [mm(p.x), mm(p.y), z]
    end

    # ------------------------------------------------------------------ cameras
    def inside_poly?(poly, x, y, margin = 250.0)
      AssistantValidate.inside?(poly, x, y, 0.0) && poly.each_index.all? do |i|
        a = poly[i]
        b = poly[(i + 1) % poly.size]
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        t = ((x - a[0]) * dx + (y - a[1]) * dy) / (dx * dx + dy * dy)
        t = [[t, 0].max, 1].min
        Math.hypot(x - (a[0] + dx * t), y - (a[1] + dy * t)) >= margin
      end
    end

    def inside_geometry?(model, x, y, z, roots)
      p = Geom::Point3d.new(x.mm, y.mm, z.mm)
      roots.any? { |r| r.bounds.contains?(p) } && Exposure.collect(model)[:units].any? { |u| u.corners.map { |c| c }.then { |cs| bb = Geom::BoundingBox.new; cs.each { |c| bb.add(c) }; bb.contains?(p) } }
    end

    # smallest lens (fov) at which the WHOLE kitchen sits inside the frame from this eye; nil when even the widest lens (72) cannot
    def fit_fov(view, eye, target, bb)
      [38.0, 42.0, 46.0, 50.0, 54.0, 58.0, 62.0, 66.0, 70.0].each do |f|
        c = Sketchup::Camera.new(Geom::Point3d.new(*eye.map(&:mm)), Geom::Point3d.new(*target.map(&:mm)), Geom::Vector3d.new(0, 0, 1))
        c.fov = f
        view.camera = c
        pts = (0..7).map { |k| view.screen_coords(bb.corner(k)) }
        xs = pts.map(&:x)
        ys = pts.map(&:y)
        return f if xs.min >= view.vpwidth * 0.04 && xs.max <= view.vpwidth * 0.96 && ys.min >= view.vpheight * 0.04 && ys.max <= view.vpheight * 0.96
      end
      nil
    end

    ASPECT = 1.6 # the pictures are 1600 x 1000

    # one sample per cabinet: the middle of its front face (30 mm in front of it), so "can the camera see this cabinet?" is a real ray test
    def sample_points(model)
      Exposure.collect(model)[:units].map do |u|
        h = u.h.to_f.positive? ? u.h.to_f : 700.0
        { p: u.tr * Geom::Point3d.new((u.w / 2.0).mm, (-u.d - 30.0).mm, (h / 2.0).mm), unit: u.g } # local frame: the unit transform already carries its own Z
      end
    end

    # does a level camera at eye / target with lens fov (VERTICAL degrees) frame this point (margin 6 %)?
    def in_frame?(eye, target, pt, fov)
      fwd = target - eye
      fwd.normalize!
      right = fwd.cross(Geom::Vector3d.new(0, 0, 1))
      right.normalize!
      up = right.cross(fwd)
      v = pt - eye
      z = v.dot(fwd)
      return false if z <= 100.mm

      th = Math.tan(fov * Math::PI / 360.0)
      (v.dot(right) / z).abs <= th * ASPECT * 0.94 && (v.dot(up) / z).abs <= th * 0.94 # SketchUp's fov is the VERTICAL angle (fov_is_height? = true)
    end

    # normalised frame coordinates (-1..1 = frame edge) of a point seen by a level camera; nil behind the camera
    def ndc_x(eye, target, pt, fov)
      fwd = target - eye
      fwd.normalize!
      right = fwd.cross(Geom::Vector3d.new(0, 0, 1))
      right.normalize!
      v = pt - eye
      z = v.dot(fwd)
      return nil if z <= 100.mm

      v.dot(right) / z / (Math.tan(fov * Math::PI / 360.0) * ASPECT)
    end

    # the cabinet itself must be the first cabinet the eye meets; walls / room objects never block (they are hidden in the client scenes)
    def unit_visible?(model, eye, s)
      dir = s[:p] - eye
      dist = dir.length
      dir.normalize!
      org = eye
      6.times do
        res = model.raytest([org, dir], true)
        return true unless res
        return true if res[0].distance(eye) >= dist - 20.mm

        path = res[1]
        return true if path.any? { |e| e.equal?(s[:unit]) }
        return false if path.any? { |e| e.respond_to?(:attribute_dictionary) && e.get_attribute('egc', 'spec') } # another cabinet stands in front

        org = res[0].offset(dir, 5.mm)
      end
      true
    end

    # the corners that decide whether the kitchen is framed: convex hull of the cabinets in plan, at floor and at the top of the tallest unit
    def frame_points(units)
      pts = units.flat_map { |u| u.corners.map { |c| [c.x.to_mm.round(1), c.y.to_mm.round(1)] } }.uniq.sort
      return [] if pts.size < 3

      cross = ->(o, a, b) { (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]) }
      lower = []
      pts.each do |p|
        lower.pop while lower.size >= 2 && cross.call(lower[-2], lower[-1], p) <= 0
        lower << p
      end
      upper = []
      pts.reverse_each do |p|
        upper.pop while upper.size >= 2 && cross.call(upper[-2], upper[-1], p) <= 0
        upper << p
      end
      hull = lower[0..-2] + upper[0..-2]
      ztop = units.map { |u| u.corners.map { |c| c.z.to_mm }.max }.max
      hull.flat_map { |x, y| [Geom::Point3d.new(x.mm, y.mm, 0), Geom::Point3d.new(x.mm, y.mm, ztop.mm)] }
    end

    # eye positions on a grid of the free floor (inside the room, clear of every cabinet), scored by how many cabinets they FRAME and really SEE
    def rank_eyes(model, poly, samples, boxes, corner_pts = nil)
      xs = poly.map { |p| p[0] }
      ys = poly.map { |p| p[1] }
      pad = 3500.0 # the eye may stand OUTSIDE the room (behind a wall that the scene hides), never inside the wall thickness
      edge_dist = lambda do |x, y|
        poly.each_index.map do |i|
          a = poly[i]
          b = poly[(i + 1) % poly.size]
          dx = b[0] - a[0]
          dy = b[1] - a[1]
          t = [[((x - a[0]) * dx + (y - a[1]) * dy) / (dx * dx + dy * dy), 0].max, 1].min
          Math.hypot(x - (a[0] + dx * t), y - (a[1] + dy * t))
        end.min
      end
      pts = []
      x = xs.min - pad
      while x <= xs.max + pad
        y = ys.min - pad
        while y <= ys.max + pad
          inside = AssistantValidate.inside?(poly, x, y, 0.0)
          ok = inside ? inside_poly?(poly, x, y, 250) : edge_dist.call(x, y) >= 600
          pts << [x, y, inside] if ok && boxes.none? { |b| x > b[0] - 350 && x < b[1] + 350 && y > b[2] - 350 && y < b[3] + 350 }
          y += 300
        end
        x += 300
      end
      cx = EGC::Num.sum(samples.map { |s| mm(s[:p].x) }.minmax) / 2.0
      cy = EGC::Num.sum(samples.map { |s| mm(s[:p].y) }.minmax) / 2.0
      target = Geom::Point3d.new(cx.mm, cy.mm, EYE_Z.mm)
      span = [samples.map { |s| mm(s[:p].x) }.minmax.then { |a, b| b - a }, samples.map { |s| mm(s[:p].y) }.minmax.then { |a, b| b - a }].max
      # average facing direction of the base units: a straight kitchen is best seen a little off the front axis (35 deg), never from a grazing angle
      fx = 0.0
      fy = 0.0
      Exposure.collect(model)[:units].select { |u| u.kind == 'base' }.each do |u|
        n = u.tr * Geom::Vector3d.new(0, -1, 0)
        fx += n.x
        fy += n.y
      end
      fl = Math.hypot(fx, fy)
      front_pen = lambda do |px, py|
        next 0.0 if fl < 0.35 * [1, Exposure.collect(model)[:units].size].max * 0.2 # U / parallel / island: no single facing direction
        dx = px - cx
        dy = py - cy
        dl = Math.hypot(dx, dy)
        next 0.0 if dl < 1

        ang = Math.acos([[(dx * fx + dy * fy) / (dl * fl), 1.0].min, -1.0].max) * 180.0 / Math::PI
        ([ang - 35.0, 0].max * 0.6)
      end
      far_pen = ->(px, py) { [Math.hypot(px - cx, py - cy) - 1.6 * span, 0].max / 100.0 * 0.5 } # a far eye flattens the perspective: prefer a natural distance
      first = pts.filter_map do |px, py, inside|
        next if Math.hypot(px - cx, py - cy) < 600

        eye = Geom::Point3d.new(px.mm, py.mm, EYE_Z.mm)
        best = nil
        (28..64).step(4).each do |fv|
          frac = corner_pts ? corner_pts.count { |q| in_frame?(eye, target, q, fv) }.to_f / corner_pts.size : samples.count { |s| in_frame?(eye, target, s[:p], fv) }.to_f / samples.size
          best = [fv, frac] if best.nil? || frac > best[1] + 0.001
          break if frac >= 0.999
        end
        nx = samples.filter_map { |s| ndc_x(eye, target, s[:p], best[0]) }
        fill = nx.empty? ? 0.0 : (nx.max - nx.min) / 2.0
        fill_pen = [0.75 - fill, 0].max * 100.0 # the kitchen must FILL the picture, not float small in the middle
        { 'eye' => [px, py, EYE_Z], 'fov' => best[0].to_f, 'framed' => best[1], 'inside' => inside, 'fill_pen' => fill_pen, 'target' => [cx, cy, EYE_Z], 'pre' => best[1] * 100.0 - (best[0] - 28) * 0.4 - (inside ? 0 : 6) - far_pen.call(px, py) - fill_pen - front_pen.call(px, py) }
      end
      short = first.sort_by { |c| -c['pre'] }.first(45)
      short |= first.select { |c| c['inside'] }.sort_by { |c| -c['pre'] }.first(15)
      # every direction around the kitchen gets candidates (the secondary view needs a different side)
      first.group_by { |c| ((Math.atan2(c['eye'][1] - cy, c['eye'][0] - cx) + Math::PI) / (Math::PI / 4)).floor }.each_value { |g| short |= g.sort_by { |c| -c['pre'] }.first(8) }
      fronts = Exposure.collect(model)[:units].select { |u| %w[base wall].include?(u.kind) }.map do |u|
        n = u.tr * Geom::Vector3d.new(0, -1, 0)
        n.normalize!
        [center_mm(u), n, u.w.to_f]
      end
      front_share = lambda do |px, py|
        tot = EGC::Num.sum(fronts) { |_, _, w| w }
        next 1.0 if tot <= 0

        EGC::Num.sum(fronts) { |c, n, w| ((px - c[0]) * n.x + (py - c[1]) * n.y).positive? && ((px - c[0]) * n.x + (py - c[1]) * n.y) / [Math.hypot(px - c[0], py - c[1]), 1].max > 0.12 ? w : 0.0 } / tot
      end
      near_pen = lambda do |px, py| # a cabinet right in front of the lens hides the kitchen behind it (a tower at arm's length fills a third of the frame)
        dmin = boxes.map { |b| dx = [b[0] - px, 0, px - b[1]].max; dy = [b[2] - py, 0, py - b[3]].max; Math.hypot(dx, dy) }.min.to_f
        [1500.0 - dmin, 0].max / 1500.0 * 30.0
      end
      scored = short.map do |c|
        eye = Geom::Point3d.new(c['eye'][0].mm, c['eye'][1].mm, EYE_Z.mm)
        vis = samples.count { |s| in_frame?(eye, target, s[:p], c['fov']) && unit_visible?(model, eye, s) }.to_f / samples.size
        fs = front_share.call(c['eye'][0], c['eye'][1])
        c.merge('seen' => vis, 'front' => fs, 'score' => vis * 100.0 - near_pen.call(c['eye'][0], c['eye'][1]) - (1.0 - fs) * 45.0 - (c['fov'] - 28) * 0.4 - (c['inside'] ? 0 : 6) - far_pen.call(c['eye'][0], c['eye'][1]) - c['fill_pen'] - front_pen.call(c['eye'][0], c['eye'][1]))
      end
      scored.sort_by { |c| -c['score'] }
    end

    # -> [{ 'key','name','eye','target','fov','notes' }]
    # HERO / SECONDARY: every free spot of the room floor is tried (level camera at standing eye height); the score is the share of cabinets that are inside the
    # frame AND really visible (ray test), minus a small penalty for wide lenses. The secondary looks from a different side. DETAIL: close on the feature
    # (hob + oven, else sink, else the fridge).
    def candidates(model, proj, cfg)
      roots = kitchen_roots(model)
      raise 'no kitchen in the model' if roots.empty?

      poly = room_poly(proj, model, roots)
      bb = bounds_mm(roots)
      kc = [mm(bb.center.x), mm(bb.center.y)]
      f = features(model)
      units = Exposure.collect(model)[:units]
      boxes = units.map do |u|
        b = Geom::BoundingBox.new
        u.corners.each { |c| b.add(c) }
        [mm(b.min.x), mm(b.max.x), mm(b.min.y), mm(b.max.y)]
      end
      samples = sample_points(model)
      ranked = rank_eyes(model, poly, samples, boxes, frame_points(units))
      out = []
      hero = ranked.first
      unless hero
        e = [kc[0], kc[1] - 2500, EYE_Z]
        hero = { 'eye' => e, 'fov' => 60.0, 'target' => [kc[0], kc[1], EYE_Z], 'seen' => 0.0, 'notes' => ['no free spot of the room frames the kitchen: default eye 2.5 m in front of it'] }
      end
      notes = hero['notes'] || []
      notes << "#{(hero['seen'] * 100).round} % of the cabinets are visible from this eye" if hero['seen'] < 0.999
      out << { 'key' => 'hero', 'eye' => hero['eye'], 'target' => hero['target'], 'fov' => hero['fov'], 'notes' => notes }
      ang0 = Math.atan2(hero['eye'][1] - kc[1], hero['eye'][0] - kc[0])
      sec = nil
      [0.95, 0.85, 0.7, 0.5].each do |share|
        sec = ranked.find do |c|
          d = (Math.atan2(c['eye'][1] - kc[1], c['eye'][0] - kc[0]) - ang0).abs
          d = 2 * Math::PI - d if d > Math::PI
          d > 35 * Math::PI / 180 && c['seen'] >= hero['seen'] * share && c['framed'] >= 0.98 && c['front'].to_f >= 0.9
        end
        break if sec
      end
      # no other side frames the WHOLE kitchen (a U in a small room): take the best complementary view that shows fronts only and frames at least half of it
      sec ||= ranked.select do |c|
        d = (Math.atan2(c['eye'][1] - kc[1], c['eye'][0] - kc[0]) - ang0).abs
        d = 2 * Math::PI - d if d > Math::PI
        d > 35 * Math::PI / 180 && c['framed'] >= 0.45 && c['front'].to_f >= 0.9
      end.max_by { |c| c['seen'] + (c['inside'] ? 0.05 : 0) }
      sec ||= ranked.find { |c| Math.hypot(c['eye'][0] - hero['eye'][0], c['eye'][1] - hero['eye'][1]) > 1500 }
      out << { 'key' => 'secondary', 'eye' => sec ? sec['eye'] : [hero['eye'][0] + 700, hero['eye'][1] - 300, EYE_Z], 'target' => sec ? sec['target'] : hero['target'],
               'fov' => sec ? sec['fov'] : [hero['fov'] + 6, 64.0].min,
               'notes' => sec ? ["#{(sec['seen'] * 100).round} % of the cabinets are visible from this eye"] : ['no second viewpoint: a small sideways step from the hero eye'] }
      feat = f['hob'] || f['sink'] || f['tall'].first
      if feat
        c = center_mm(feat, 1000)
        n = feat.tr * Geom::Vector3d.new(0, -1, 0)
        n.normalize!
        side = feat.tr * Geom::Vector3d.new(1, 0, 0)
        e = [c[0] + n.x * 2300 + side.x * 700, c[1] + n.y * 2300 + side.y * 700, 1350.0]
        e = [c[0] + n.x * 1500, c[1] + n.y * 1500, 1350.0] unless inside_poly?(poly, e[0], e[1], 100)
        out << { 'key' => 'detail', 'eye' => e, 'target' => [c[0], c[1], 850.0], 'fov' => 44.0, 'feature' => feat.g.name, 'notes' => [] }
      end
      out.each do |cd|
        cd['notes'] << 'eye moved out of a cabinet' if inside_geometry?(model, cd['eye'][0], cd['eye'][1], cd['eye'][2], roots) && (cd['eye'] = [cd['eye'][0], cd['eye'][1] + 300, cd['eye'][2]])
        cd['notes'] << 'wide lens (fov > 60): the room is tight' if cd['fov'] > 60
        cd['name'] = SCENES[cd['key']]
      end
      out.uniq { |c| c['key'] }
    end

    # ------------------------------------------------------------------ occluders (walls between the camera and the kitchen)
    def occluders(model, eye, target, roots, limit = 8)
      found = []
      hidden = []
      limit.times do
        ray = [Geom::Point3d.new(eye[0].mm, eye[1].mm, eye[2].mm), Geom::Point3d.new(target[0].mm, target[1].mm, target[2].mm) - Geom::Point3d.new(eye[0].mm, eye[1].mm, eye[2].mm)]
        res = model.raytest(ray, true)
        break unless res

        top = res[1].first
        break if roots.include?(top) || (top.respond_to?(:attribute_dictionary) && top.attribute_dictionary('egc'))

        # only what really stands between the eye and the target
        break if res[0].distance(ray[0]) > ray[1].length

        found << top
        top.hidden = true
        hidden << top
      end
      hidden.each { |e| e.hidden = false }
      found
    end

    # ------------------------------------------------------------------ scenes
    def presentation_options(model)
      ro = model.rendering_options
      bg = Sketchup::Color.new(240, 239, 234)
      { 'DisplaySketchAxes' => false, 'HideConstructionGeometry' => true, 'DisplayText' => false, 'DrawGround' => false, 'DrawHorizon' => false, 'DisplayFog' => false,
        'BackgroundColor' => bg, 'SkyColor' => bg, 'GroundColor' => bg, 'HorizonColor' => bg, 'DrawSilhouettes' => false, 'EdgeDisplayMode' => false, 'DisplayDims' => false, 'ShowViewName' => false }.each do |k, v|
        begin
          ro[k] = v
        rescue StandardError
          nil
        end
      end
    end

    def dimensions(model)
      model.entities.grep(Sketchup::Dimension) + model.entities.grep(Sketchup::Text)
    end

    # creates / updates the three client scenes + the technical scene. Returns a report (geometry fingerprint must not change).
    def run(model, proj, cfg)
      fp0 = geometry_fingerprint(model)
      cams = candidates(model, proj, cfg)
      roots = kitchen_roots(model)
      view = model.active_view
      model.start_operation('E.G.C Client Shot', true)
      report = { 'scenes' => [], 'occluders' => [] }
      begin
        ViewTools.client_view(true) # hardware / technical parts hidden (tag visibility)
        LiveDims.toggle if LiveDims.respond_to?(:enabled?) && LiveDims.enabled?
        presentation_options(model)
        cams.each do |cd|
          occ = occluders(model, cd['eye'], cd['target'], roots)
          cam = Sketchup::Camera.new(Geom::Point3d.new(*cd['eye'].map(&:mm)), Geom::Point3d.new(*cd['target'].map(&:mm)), Geom::Vector3d.new(0, 0, 1))
          cam.fov = cd['fov']
          model.pages.erase(model.pages[cd['name']]) if model.pages[cd['name']]
          view.camera = cam
          occ.each { |e| e.hidden = true }
          dimensions(model).each { |e| e.hidden = true }
          page = model.pages.add(cd['name'])
          page.transition_time = 0 # no camera animation: the picture must be exactly this camera
          page.use_camera = true
          page.use_hidden = true
          page.use_hidden_layers = true
          page.use_rendering_options = true
          occ.each { |e| page.set_drawingelement_visibility(e, false) }
          dimensions(model).each { |e| page.set_drawingelement_visibility(e, false) }
          occ.each { |e| e.hidden = false }
          dimensions(model).each { |e| e.hidden = false }
          report['scenes'] << { 'name' => cd['name'], 'eye' => cd['eye'].map(&:round), 'target' => cd['target'].map(&:round), 'fov' => cd['fov'], 'notes' => cd['notes'], 'hidden_walls' => occ.size }
          report['occluders'].concat(occ.map { |e| e.respond_to?(:name) ? e.name.to_s : e.class.to_s })
        end
        # separate DESIGN / TECHNICAL view: hardware visible, dimensions live, normal perspective of the whole kitchen
        ViewTools.client_view(false)
        bb = bounds_mm(roots)
        tc = Sketchup::Camera.new(Geom::Point3d.new((mm(bb.center.x) - 2500).mm, (mm(bb.min.y) - 3500).mm, 2600.mm), Geom::Point3d.new(bb.center.x, bb.center.y, 1200.mm), Geom::Vector3d.new(0, 0, 1))
        tc.fov = 50
        view.camera = tc
        model.pages.erase(model.pages[TECH_SCENE]) if model.pages[TECH_SCENE]
        pg = model.pages.add(TECH_SCENE)
        pg.transition_time = 0
        pg.use_camera = true
        report['technical'] = TECH_SCENE
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      report['geometry_unchanged'] = geometry_fingerprint(model) == fp0
      report
    end

    # ------------------------------------------------------------------ render-ready check
    # -> { 'ready'=>bool, 'issues'=>[{code, severity, message, fix}] }
    def check(model, proj = nil)
      issues = []
      add = ->(code, sev, msg, fix = nil) { issues << { 'code' => code, 'severity' => sev, 'message' => msg, 'fix' => fix } }
      units = Exposure.collect(model)[:units]
      add.call('NO_KITCHEN', 'error', 'no kitchen in the model') if units.empty?
      # materials
      bad = []
      units.each do |u|
        Validate.parts_of(u).each do |p|
          next unless %w[part glass].include?(p[:role])

          bad << "#{u.g.name}/#{p[:part]}" if p[:e].material.nil?
        end
      end
      add.call('MISSING_MATERIAL', 'error', "#{bad.size} part(s) have no material: #{bad.first(3).join(', ')}", 'Apply the E.G.C materials (Materials tab)') unless bad.empty?
      # fronts, appliances, sink, hob
      r = Validate.model(model)
      add.call('MISSING_FRONT_OR_PART', 'error', r[:problems].first.to_s[0, 160], 'Rebuild the unit') unless r[:problems].empty?
      types = units.map { |u| u.g.get_attribute('egc', 'type').to_s }
      apps = units.flat_map { |u| Validate.parts_of(u).select { |p| p[:role] == 'appliance' }.map { |p| p[:part].to_s } }
      add.call('NO_SINK_FIXTURE', 'warn', 'a sink unit has no sink / faucet') if types.any? { |t| t =~ /sink/ } && apps.none? { |a| a =~ /sink/ }
      add.call('NO_HOB_FIXTURE', 'warn', 'a hob unit has no hob') if types.any? { |t| t =~ /hob/ } && apps.none? { |a| a =~ /hob/ }
      add.call('NO_HOOD', 'info', 'no hood above the hob') if types.any? { |t| t =~ /hob/ } && units.none? { |u| u.kind == 'hood' }
      add.call('NO_FRIDGE', 'info', 'no refrigerator in the design') if apps.none? { |a| a =~ /fridge/ }
      # open mechanisms
      open = []
      walk = lambda { |ents| ents.grep(Sketchup::Group).each { |g| open << g.name if g.get_attribute('egc', 'move') && (g.get_attribute('egc', 'anim_t') || 0) > 0.05; walk.call(g.entities) } }
      walk.call(model.entities)
      add.call('OPEN_MECHANISMS', 'warn', "#{open.size} door/drawer/mechanism part(s) are left open", 'Close them (Fix)') unless open.empty?
      # debug / guides / axes / selection / dimensions
      dbg = model.entities.grep(Sketchup::Group).select { |g| g.name.to_s =~ /^(TMP|DEBUG|_dbg)/i }
      add.call('DEBUG_GEOMETRY', 'error', "#{dbg.size} debug group(s): #{dbg.map(&:name).first(3).join(', ')}", 'Delete them') unless dbg.empty?
      guides = model.entities.grep(Sketchup::ConstructionLine).size + model.entities.grep(Sketchup::ConstructionPoint).size
      add.call('GUIDES', 'warn', "#{guides} construction guide(s) in the model (hidden in the client scenes)") if guides.positive?
      dims = dimensions(model).size
      add.call('TECHNICAL_DIMENSIONS', 'info', "#{dims} dimension / text entities (hidden in the client scenes, kept in the technical view)") if dims.positive?
      add.call('AXES', 'info', 'axes are visible in the technical view (hidden in the client scenes)') if (model.rendering_options['DisplaySketchAxes'] rescue false)
      add.call('SELECTION', 'warn', 'something is selected (selection outlines show in the picture)', 'Clear the selection (Fix)') unless model.selection.empty?
      add.call('LIVE_DIMS', 'warn', 'Live Dimensions overlay is on', 'Turn it off (Fix)') if (LiveDims.respond_to?(:enabled?) && LiveDims.enabled?)
      add.call('TEXTURE_DIRECTION', 'info', 'wood-grain direction follows the construction rules (doors vertical, drawer fronts horizontal); the SketchUp API cannot read the texture rotation, so this is informational') if units.any?
      { 'ready' => issues.none? { |i| i['severity'] == 'error' }, 'issues' => issues }
    end

    # closes mechanisms, clears the selection, switches the live dimension overlay off (view state only)
    def fix(model)
      model.start_operation('E.G.C Render-ready fix', true)
      walk = lambda do |ents|
        ents.grep(Sketchup::Group).each do |g|
          if g.get_attribute('egc', 'move')
            next unless (g.get_attribute('egc', 'anim_t') || 0) > 0.05

            Mechanisms.set_state([g], 0.0)
            g.set_attribute('egc', 'anim_t', 0.0)
            g.set_attribute('egc', 'is_open', false)
          else
            walk.call(g.entities)
          end
        end
      end
      walk.call(model.entities)
      model.selection.clear
      LiveDims.toggle if LiveDims.respond_to?(:enabled?) && LiveDims.enabled?
      model.commit_operation
    end
  end
end
