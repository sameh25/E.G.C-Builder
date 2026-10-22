# frozen_string_literal: true

require 'json'
require 'digest'

module EGC
  # E.G.C INTELLIGENT ASSISTANT - project store + CONSTRAINT MODEL.
  #
  # Everything the assistant knows about a job (room, walls, openings, columns, service points, image, the design it generated, the documents it
  # issued) lives in ONE JSON document stored inside the SKP (model attribute 'egc_assistant' / 'project'), so save / close / reopen keeps it and the
  # documents can be regenerated without re-entering anything.
  #
  # Every value that matters for manufacturing or site work carries a STATUS - never a silent guess:
  #   CONFIRMED               typed by the user, or measured from geometry the user drew
  #   INFERRED                derived (from an image scale, a default, a rule) - shown to the user for confirmation
  #   REQUIRES_CONFIRMATION   needed but unknown
  module Assistant
    module_function

    ATTR = 'egc_assistant'
    CONFIRMED = 'CONFIRMED'
    INFERRED = 'INFERRED'
    REQ = 'REQUIRES_CONFIRMATION'

    DEFAULT_PROJECT = {
      'v' => 1, 'name' => '', 'client' => '', 'rev' => 'A',
      'room' => { 'ceiling' => { 'v' => nil, 'st' => REQ }, 'poly' => [], 'poly_st' => REQ, 'wall_thk' => 200 },
      'openings' => [], 'columns' => [], 'services' => [], 'no_build' => [],
      'image' => nil, 'design' => nil, 'docs' => {}
    }.freeze

    # ------------------------------------------------------------------ store
    def load(model = Sketchup.active_model)
      raw = model && model.get_attribute(ATTR, 'project')
      p = raw ? JSON.parse(raw) : {}
      deep_merge(JSON.parse(JSON.generate(DEFAULT_PROJECT)), p)
    rescue StandardError
      JSON.parse(JSON.generate(DEFAULT_PROJECT))
    end

    def save(proj, model = Sketchup.active_model)
      model.set_attribute(ATTR, 'project', JSON.generate(proj))
      proj
    end

    def deep_merge(a, b)
      a.merge(b) { |_k, x, y| x.is_a?(Hash) && y.is_a?(Hash) ? deep_merge(x, y) : y }
    end

    # ------------------------------------------------------------------ room + walls
    # Room corners (mm), clockwise as seen from above: the room is on the RIGHT of every wall's direction - exactly the frame a kitchen run is built
    # in (x along the wall, the cabinets grow toward -y = the room side). Counter-clockwise input is reversed.
    def set_room(proj, poly, status = CONFIRMED)
      poly = poly.map { |x, y| [x.to_f, y.to_f] }
      poly = poly.reverse if signed_area(poly) > 0
      proj['room']['poly'] = poly
      proj['room']['poly_st'] = status
      proj
    end

    # rectangle w x d (mm): corners clockwise (0,0) -> (0,d) -> (w,d) -> (w,0); wall A = the west wall, B = the north wall (y = d), C = east, D = south
    def room_from_dims(proj, w, d, status = CONFIRMED)
      set_room(proj, [[0, 0], [0, d], [w, d], [w, 0]], status)
    end

    def load_blank
      JSON.parse(JSON.generate(DEFAULT_PROJECT))
    end

    def signed_area(poly)
      s = 0.0
      poly.each_with_index { |(x0, y0), i| x1, y1 = poly[(i + 1) % poly.size]; s += x0 * y1 - x1 * y0 }
      s / 2.0
    end

    # -> [{ 'id'=>'A', 'p0'=>[x,y], 'p1'=>[x,y], 'len'=>, 'dir'=>[dx,dy], 'rot'=>deg }]
    def walls(proj)
      poly = proj['room']['poly']
      return [] if poly.size < 3

      poly.each_index.map do |i|
        p0 = poly[i]
        p1 = poly[(i + 1) % poly.size]
        dx = p1[0] - p0[0]
        dy = p1[1] - p0[1]
        len = Math.hypot(dx, dy)
        { 'id' => ('A'.ord + i).chr, 'p0' => p0, 'p1' => p1, 'len' => len.round(1), 'dir' => [dx / len, dy / len],
          'rot' => (Math.atan2(dy, dx) * 180.0 / Math::PI).round(6), 'st' => proj['room']['poly_st'] }
      end
    end

    def wall(proj, id)
      walls(proj).find { |w| w['id'] == id.to_s }
    end

    def wall_point(w, off)
      [w['p0'][0] + w['dir'][0] * off, w['p0'][1] + w['dir'][1] * off]
    end

    def next_id(proj, key, prefix)
      n = (proj[key] || []).map { |x| x['id'].to_s[/\d+/].to_i }.max.to_i + 1
      "#{prefix}#{n}"
    end

    # ------------------------------------------------------------------ constraint editing (a single value can be corrected without redrawing anything)
    def add_opening(proj, wall_id, type, off, w, h, sill, status = CONFIRMED)
      o = { 'id' => next_id(proj, 'openings', type == 'door' ? 'D' : 'W'), 'type' => type, 'wall' => wall_id, 'off' => off.to_f, 'w' => w.to_f, 'h' => h.to_f,
            'sill' => sill.to_f, 'st' => status }
      proj['openings'] << o
      o
    end

    def add_column(proj, wall_id, off, w, d, status = CONFIRMED)
      c = { 'id' => next_id(proj, 'columns', 'C'), 'wall' => wall_id, 'off' => off.to_f, 'w' => w.to_f, 'd' => d.to_f, 'st' => status }
      proj['columns'] << c
      c
    end

    def add_service(proj, kind, wall_id, off, z, device = nil, status = CONFIRMED)
      s = { 'id' => next_id(proj, 'services', 'S'), 'kind' => kind, 'wall' => wall_id, 'off' => off.to_f, 'z' => z.to_f, 'device' => device, 'st' => status }
      proj['services'] << s
      s
    end

    # update one field of one element: Assistant.correct(proj, 'openings', 'W1', 'off', 1200) -> the value becomes CONFIRMED
    def correct(proj, list, id, field, value)
      e = proj[list].find { |x| x['id'] == id }
      raise "#{id} not found in #{list}" unless e

      e[field] = value
      e['st'] = CONFIRMED
      e
    end

    def set_ceiling(proj, mm, status = CONFIRMED)
      proj['room']['ceiling'] = { 'v' => mm.to_f, 'st' => status }
    end

    # ------------------------------------------------------------------ image input (scale from ONE known dimension; traced points are INFERRED)
    # ref_px: two pixel points of a dimension the user knows; mm: that dimension. Everything traced afterwards is converted with this scale and stays INFERRED
    # until the user confirms it. No scale -> REQUIRES_CONFIRMATION (the assistant refuses to generate from an unscaled image).
    def attach_image(proj, path, ref_px = nil, mm = nil)
      img = { 'path' => path, 'scale' => nil, 'st' => REQ, 'ref' => nil }
      if ref_px && mm.to_f > 0
        d = Math.hypot(ref_px[1][0] - ref_px[0][0], ref_px[1][1] - ref_px[0][1])
        raise 'reference points coincide' if d <= 0

        img['scale'] = mm.to_f / d
        img['ref'] = { 'px' => ref_px, 'mm' => mm.to_f }
        img['st'] = INFERRED
      end
      proj['image'] = img
    end


    # A hand sketch is rarely to scale: every other labelled length on the image is compared with the scale that ONE reference gives.
    # checks: [[[x0,y0],[x1,y1]], mm] ... -> image['consistency'] { rows, ok }. A deviation > tol % makes the scale REQUIRES_CONFIRMATION (nothing is traced with it).
    def image_consistency(proj, checks, tol_pct = 8.0)
      img = proj['image']
      sc = img && img['scale']
      return nil unless sc

      rows = checks.map do |(a, b), mm|
        px = Math.hypot(b[0] - a[0], b[1] - a[1])
        implied = mm.to_f / px
        { 'px' => px.round(1), 'mm' => mm.to_f, 'implied_mm_per_px' => implied.round(3), 'dev_pct' => (((implied / sc) - 1) * 100).round(1) }
      end
      ok = rows.all? { |r| r['dev_pct'].abs <= tol_pct }
      img['consistency'] = { 'rows' => rows, 'ok' => ok, 'tol_pct' => tol_pct }
      img['st'] = REQ unless ok
      img['consistency']
    end

    # polyline traced on the image ([[px,py],...], y down) -> room corners in mm (y up), clockwise, status INFERRED
    def trace_room(proj, px_points)
      sc = proj['image'] && proj['image']['scale']
      unless sc
        proj['room']['poly_st'] = REQ
        return { 'error' => 'SCALE_UNKNOWN', 'message' => 'The image has no scale: give one known dimension first (two points + its length).' }
      end
      pts = px_points.map { |x, y| [(x * sc).round(1), (-y * sc).round(1)] }
      set_room(proj, pts, INFERRED)
      { 'ok' => true, 'poly' => proj['room']['poly'] }
    end

    # ------------------------------------------------------------------ input from existing SketchUp geometry
    # Walls the user already drew: vertical faces (loose, or inside groups / components; E.G.C groups are ignored) -> wall lines. The room side is the side
    # facing the centroid of all walls (INFERRED - shown for confirmation); lengths are measured (CONFIRMED).
    def scan_walls(model = Sketchup.active_model, ents = nil, min_len_mm: 600)
      segs = []
      walk = lambda do |list, tr|
        list.each do |e|
          if e.is_a?(Sketchup::Face)
            n = (tr * e.normal) rescue nil
            n = e.normal.transform(tr) if n.nil?
            next unless n.z.abs < 0.05

            pts = e.vertices.map { |v| tr * v.position }
            d = Geom::Vector3d.new(-n.y, n.x, 0)
            next if d.length < 1e-6

            d.normalize!
            ts = pts.map { |p| p.x * d.x + p.y * d.y }
            lo = ts.min
            hi = ts.max
            zmin = pts.map(&:z).min
            zmax = pts.map(&:z).max
            base = pts.min_by(&:z)
            a = [base.x + d.x * (lo - (base.x * d.x + base.y * d.y)), base.y + d.y * (lo - (base.x * d.x + base.y * d.y))]
            b = [base.x + d.x * (hi - (base.x * d.x + base.y * d.y)), base.y + d.y * (hi - (base.x * d.x + base.y * d.y))]
            len = (hi - lo).to_mm
            next if len < min_len_mm || (zmax - zmin).to_mm < 1500

            segs << { a: [a[0].to_mm, a[1].to_mm], b: [b[0].to_mm, b[1].to_mm], n: [n.x, n.y], len: len, h: (zmax - zmin).to_mm }
          elsif e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            next if e.attribute_dictionary('egc')

            walk.call(e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities, tr * e.transformation)
          end
        end
      end
      walk.call((ents || model.entities).to_a, Geom::Transformation.new)
      # the two faces of one wall (inner / outer) describe the same line: keep one per parallel, overlapping pair, and say which side is the room
      out = []
      segs.sort_by { |s| -s[:len] }.each do |s|
        dup = out.find do |o|
          dot = s[:n][0] * o[:n][0] + s[:n][1] * o[:n][1]
          dot.abs > 0.98 && ((s[:a][0] - o[:a][0]) * o[:n][0] + (s[:a][1] - o[:a][1]) * o[:n][1]).abs < 600 &&
            [Math.hypot(s[:a][0] - o[:a][0], s[:a][1] - o[:a][1]), Math.hypot(s[:b][0] - o[:b][0], s[:b][1] - o[:b][1]),
             Math.hypot(s[:a][0] - o[:b][0], s[:a][1] - o[:b][1]), Math.hypot(s[:b][0] - o[:a][0], s[:b][1] - o[:a][1])].min < 600
        end
        out << s unless dup
      end
      out
    end

    # walls found -> a room polygon (only when the segments chain into a closed loop within tol); otherwise the raw segments are returned for the user
    def chain_polygon(segs, tol = 400)
      return nil if segs.size < 3

      pts = segs.flat_map { |s| [s[:a], s[:b]] }
      corners = []
      segs.each { |s| [s[:a], s[:b]].each { |p| corners << p unless corners.any? { |q| Math.hypot(p[0] - q[0], p[1] - q[1]) < tol } } }
      corners.size == segs.size ? order_corners(corners, segs, tol) : nil
    end

    def order_corners(corners, segs, tol)
      adj = Hash.new { |h, k| h[k] = [] }
      segs.each do |s|
        ia = corners.index { |c| Math.hypot(c[0] - s[:a][0], c[1] - s[:a][1]) < tol }
        ib = corners.index { |c| Math.hypot(c[0] - s[:b][0], c[1] - s[:b][1]) < tol }
        next unless ia && ib

        adj[ia] << ib
        adj[ib] << ia
      end
      return nil unless adj.values.all? { |v| v.size == 2 }

      order = [0]
      prev = nil
      cur = 0
      (corners.size - 1).times do
        nxt = adj[cur].find { |x| x != prev && !order.include?(x) }
        break unless nxt

        order << nxt
        prev = cur
        cur = nxt
      end
      order.size == corners.size ? order.map { |i| corners[i] } : nil
    end

    # openings the user placed with the E.G.C Opening tool -> constraints (position measured along the nearest wall)
    def scan_openings(proj, model = Sketchup.active_model)
      ws = walls(proj)
      return [] if ws.empty?

      found = []
      walk = lambda do |list, tr|
        list.each do |e|
          next unless e.is_a?(Sketchup::Group)

          if Openings.opening?(e)
            prm = Openings.params_of(e)
            t = tr * e.transformation
            c = t * Geom::Point3d.new(prm['w'].mm / 2.0, 0, (prm['sill'] + prm['h'] / 2.0).mm)
            cw = [c.x.to_mm, c.y.to_mm]
            best = ws.min_by { |w| dist_to_wall(w, cw) }
            off = (cw[0] - best['p0'][0]) * best['dir'][0] + (cw[1] - best['p0'][1]) * best['dir'][1]
            kind = (Openings::TYPES[prm['type']] || {})[:kind] || 'window'
            found << { 'wall' => best['id'], 'type' => kind, 'off' => (off - prm['w'] / 2.0).round(1), 'w' => prm['w'], 'h' => prm['h'], 'sill' => prm['sill'], 'src' => e.persistent_id }
          elsif !e.attribute_dictionary('egc')
            walk.call(e.entities, tr * e.transformation)
          end
        end
      end
      walk.call(model.entities.to_a, Geom::Transformation.new)
      found
    end

    def dist_to_wall(w, pt)
      dx = pt[0] - w['p0'][0]
      dy = pt[1] - w['p0'][1]
      t = dx * w['dir'][0] + dy * w['dir'][1]
      t = [[t, 0].max, w['len']].min
      Math.hypot(dx - w['dir'][0] * t, dy - w['dir'][1] * t)
    end

    # ------------------------------------------------------------------ readable summary shown to the user BEFORE anything is generated
    def summary(proj, lang = 'en')
      ar = lang == 'ar'
      lines = []
      ws = walls(proj)
      cl = proj['room']['ceiling']
      lines << row(ar ? 'ارتفاع السقف' : 'Ceiling', cl['v'] ? "#{cl['v'].round} mm" : '-', cl['st'])
      ws.each { |w| lines << row(ar ? "الحائط #{w['id']}" : "Wall #{w['id']}", "#{w['len'].round} mm", w['st']) }
      proj['openings'].each { |o| lines << row("#{o['type'] == 'door' ? (ar ? 'باب' : 'Door') : (ar ? 'شباك' : 'Window')} #{o['id']}", "#{ar ? 'حائط' : 'wall'} #{o['wall']} @ #{o['off'].round}, #{o['w'].round}x#{o['h'].round}, #{ar ? 'عتبة' : 'sill'} #{o['sill'].round}", o['st']) }
      proj['columns'].each { |c| lines << row("#{ar ? 'عمود' : 'Column'} #{c['id']}", "#{ar ? 'حائط' : 'wall'} #{c['wall']} @ #{c['off'].round}, #{c['w'].round}x#{c['d'].round}", c['st']) }
      proj['services'].each { |s| lines << row("#{service_label(s['kind'], ar)} #{s['id']}", "#{ar ? 'حائط' : 'wall'} #{s['wall']} @ #{s['off'].round}, z #{s['z'].round}#{s['device'] ? " -> #{s['device']}" : ''}", s['st']) }
      unc = lines.select { |l| l[:st] != CONFIRMED }
      { 'lines' => lines, 'unconfirmed' => unc.size, 'ready' => ws.size >= 3 && cl['v'] && unc.none? { |l| l[:st] == REQ } }
    end

    def row(label, value, st)
      { label: label, value: value, st: st }
    end

    SERVICE_LABELS = { 'water_cold' => %w[Cold\ water مياه\ باردة], 'water_hot' => %w[Hot\ water مياه\ ساخنة], 'drain' => %w[Drain صرف], 'gas' => %w[Gas غاز],
                       'elec' => %w[Electrical كهرباء], 'duct' => %w[Hood\ duct مخرج\ الشفاط] }.freeze

    def service_label(kind, ar)
      (SERVICE_LABELS[kind] || [kind, kind])[ar ? 1 : 0]
    end

    # ------------------------------------------------------------------ hashes used by the staleness engine
    def constraints_hash(proj)
      Digest::MD5.hexdigest(JSON.generate(proj.slice('room', 'openings', 'columns', 'services', 'no_build')))
    end
  end
end
