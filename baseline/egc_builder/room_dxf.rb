# frozen_string_literal: true

module EGC
  # Room boundary from a 2D DXF (plan view). No AI: pure geometry.
  #   walls    : a closed polyline (or a closed chain of lines) on layer WALLS (any layer whose name contains WALL, or the layer the user names);
  #              two closed outlines (inner + outer wall face) -> the inner one is the room
  #   doors    : lines / polylines on a layer whose name contains DOOR, lying on a wall  -> door opening (height 2100 unless a text says otherwise)
  #   windows  : the same on a layer containing WIN -> window (sill / height from a nearby text "SILL 1000", "H 1200"; defaults are marked INFERRED)
  #   columns  : closed polylines on a layer containing COL
  #   plumbing : a text containing DRAIN / WATER / PLUMB / SINK (or the Arabic words) or anything on a layer containing PLUMB / DRAIN / WATER / SANIT
  #   ceiling  : a text "CEILING 2800" / "CLG 2800"; default 2800 (INFERRED)
  # Drawing units: $INSUNITS when the file states it, otherwise guessed from the size of the room (reported, never silent).
  module RoomDxf
    module_function

    DEF_CEILING = 2800.0
    DEF_DOOR_H = 2100.0
    DEF_SILL = 1000.0
    DEF_WIN_H = 1200.0
    NEAR_WALL = 350.0 # mm: an opening / marker further than this from every wall is ignored (reported)
    PLUMB_RE = /drain|water|plumb|sink|صرف|مياه|مياة|حوض|سباك/i.freeze

    class Error < StandardError; end

    # -> { units: Integer|nil, ents: [ { type:, layer:, pts: [[x, y], ...], closed:, text:, r: } ] }
    def parse(text)
      lines = text.to_s.encode('UTF-8', invalid: :replace, undef: :replace).split(/\r?\n/)
      pairs = []
      i = 0
      while i + 1 < lines.size
        pairs << [lines[i].strip.to_i, lines[i + 1].strip]
        i += 2
      end
      units = nil
      pairs.each_with_index { |(c, v), k| units = pairs[k + 1][1].to_i if c == 9 && v == '$INSUNITS' && pairs[k + 1] }
      a = pairs.index { |c, v| c == 2 && v == 'ENTITIES' }
      raise Error, 'DXF_NO_ENTITIES: the file has no ENTITIES section (save it as ASCII DXF)' unless a

      ents = []
      cur = nil
      poly = nil
      flush = lambda do
        next unless cur

        if cur[:type] == 'VERTEX'
          poly[:pts] << [cur[:x].last.to_f, cur[:y].last.to_f] if poly && cur[:x].any?
        elsif cur[:type] == 'POLYLINE'
          poly = cur.merge(type: 'LWPOLYLINE', pts: [])
        elsif cur[:type] == 'SEQEND'
          ents << poly if poly
          poly = nil
        else
          cur[:pts] = cur[:x].zip(cur[:y]).select { |x, y| x && y }.map { |x, y| [x.to_f, y.to_f] } unless cur[:pts]
          ents << cur
        end
        cur = nil
      end
      pairs[(a + 1)..].each do |c, v|
        if c.zero?
          flush.call
          break if v == 'ENDSEC'

          cur = { type: v, layer: '0', x: [], y: [], closed: false, text: +'' }
        elsif cur
          case c
          when 8 then cur[:layer] = v
          when 10, 11 then cur[:x] << v
          when 20, 21 then cur[:y] << v
          when 70 then cur[:closed] = (v.to_i & 1) == 1 if %w[LWPOLYLINE POLYLINE].include?(cur[:type])
          when 1, 3 then cur[:text] << v
          when 40 then cur[:r] = v.to_f
          end
        end
      end
      flush.call
      { units: units, ents: ents.each { |e| e.delete(:x); e.delete(:y) } }
    end

    def area(poly)
      s = 0.0
      poly.each_with_index { |(x, y), k| nx, ny = poly[(k + 1) % poly.size]; s += x * ny - nx * y }
      s / 2.0
    end

    def clean(poly)
      p = poly.dup
      p.pop if p.size > 1 && (p.first[0] - p.last[0]).abs < 1e-6 && (p.first[1] - p.last[1]).abs < 1e-6
      p = p.each_with_index.reject { |q, k| k.positive? && (q[0] - p[k - 1][0]).abs < 1e-6 && (q[1] - p[k - 1][1]).abs < 1e-6 }.map(&:first)
      # drop points that lie on a straight wall (one wall = one segment)
      loop do
        k = (0...p.size).find do |j|
          a = p[j - 1]
          b = p[j]
          c = p[(j + 1) % p.size]
          cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
          cr.abs <= 1e-4 * [Math.hypot(b[0] - a[0], b[1] - a[1]) * Math.hypot(c[0] - b[0], c[1] - b[1]), 1e-9].max
        end
        break unless k && p.size > 3

        p.delete_at(k)
      end
      p
    end

    # closed loop from loose LINE segments (end points matched within tol drawing units)
    def chain(segs, tol)
      return nil if segs.size < 3

      rest = segs.map { |s| s.map(&:dup) }
      path = rest.shift.dup
      until rest.empty?
        tail = path.last
        k = rest.index { |s| Math.hypot(s[0][0] - tail[0], s[0][1] - tail[1]) <= tol || Math.hypot(s[1][0] - tail[0], s[1][1] - tail[1]) <= tol }
        return nil unless k

        s = rest.delete_at(k)
        path << (Math.hypot(s[0][0] - tail[0], s[0][1] - tail[1]) <= tol ? s[1] : s[0])
      end
      Math.hypot(path.first[0] - path.last[0], path.first[1] - path.last[1]) <= tol ? path[0...-1] : nil
    end

    def layer_is(e, re)
      e[:layer].to_s =~ re
    end

    def num_mm(n)
      n = n.to_f
      n < 10 ? n * 1000 : (n < 400 ? n * 10 : n)
    end

    # proj is filled in place; returns the import report
    def import(text, proj, opts = {})
      d = parse(text)
      ents = d[:ents]
      notes = []
      wall_re = opts['layer'].to_s.empty? ? /wall|حائط|جدار/i : /\A#{Regexp.escape(opts['layer'].to_s)}\z/i
      closed = ents.select { |e| e[:type] == 'LWPOLYLINE' && e[:closed] && e[:pts].size >= 3 }
      cands = closed.select { |e| layer_is(e, wall_re) }.map { |e| e[:pts] }
      if cands.empty?
        segs = ents.select { |e| e[:type] == 'LINE' && layer_is(e, wall_re) && e[:pts].size == 2 }.map { |e| e[:pts] }
        open_pl = ents.select { |e| e[:type] == 'LWPOLYLINE' && !e[:closed] && layer_is(e, wall_re) }
        open_pl.each { |e| e[:pts].each_cons(2) { |p, q| segs << [p, q] } }
        ext = segs.flatten(1).map { |p| p[0] }.minmax
        lp = chain(segs, [(ext[1].to_f - ext[0].to_f) * 0.002, 1e-6].max) if segs.size >= 3
        cands << lp if lp
      end
      if cands.empty?
        cands = closed.reject { |e| layer_is(e, /door|win|col|باب|شباك|عمود/i) }.map { |e| e[:pts] }
        notes << 'no closed outline on a WALLS layer: the largest closed polyline of the drawing was taken as the room' unless cands.empty?
      end
      raise Error, 'DXF_NO_ROOM: no closed room outline found (draw the room as one closed polyline on layer WALLS)' if cands.empty?

      cands = cands.map { |p| clean(p) }.select { |p| p.size >= 3 }.sort_by { |p| -area(p).abs }
      room = cands.first
      inner = cands[1]
      if inner && area(inner).abs >= 0.5 * area(room).abs
        room = inner
        notes << 'two wall outlines found: the inner one is the room'
      end
      ext = [room.map { |p| p[0] }.minmax, room.map { |p| p[1] }.minmax]
      size = [ext[0][1] - ext[0][0], ext[1][1] - ext[1][0]].max
      scale, usrc = case d[:units]
                    when 4 then [1.0, 'file: millimetres']
                    when 5 then [10.0, 'file: centimetres']
                    when 6 then [1000.0, 'file: metres']
                    when 1 then [25.4, 'file: inches']
                    else size < 60 ? [1000.0, 'guessed from the room size: metres'] : (size < 2000 ? [10.0, 'guessed from the room size: centimetres'] : [1.0, 'guessed from the room size: millimetres'])
                    end
      ox = ext[0][0]
      oy = ext[1][0]
      tr = ->(p) { [((p[0] - ox) * scale).round(1), ((p[1] - oy) * scale).round(1)] }
      Assistant.set_room(proj, room.map { |p| tr.call(p) }, Assistant::CONFIRMED)
      ws = Assistant.walls(proj)
      texts = ents.select { |e| %w[TEXT MTEXT].include?(e[:type]) && e[:pts].any? }.map { |e| { s: e[:text].gsub(/\\[A-Za-z][^;]*;|[{}]/, ''), at: tr.call(e[:pts].first), layer: e[:layer] } }
      along = ->(w, p) { (p[0] - w['p0'][0]) * w['dir'][0] + (p[1] - w['p0'][1]) * w['dir'][1] }
      nearest = ->(p) { ws.min_by { |w| Assistant.dist_to_wall(w, p) } }
      # ---- openings: every door / window entity is projected on the wall it lies on; overlapping pieces of one opening are merged
      found = { 'door' => [], 'window' => [] }
      ents.each do |e|
        kind = layer_is(e, /door|باب/i) ? 'door' : (layer_is(e, /win|شباك/i) ? 'window' : nil)
        next unless kind && %w[LINE LWPOLYLINE].include?(e[:type])

        pts = e[:pts].map { |p| tr.call(p) }
        w = ws.min_by { |x| pts.map { |p| Assistant.dist_to_wall(x, p) }.min }
        on = pts.select { |p| Assistant.dist_to_wall(w, p) <= NEAR_WALL }
        next if on.size < 2

        a0, a1 = on.map { |p| along.call(w, p) }.minmax
        found[kind] << [w['id'], [a0, 0].max, [a1, w['len']].min] if a1 - a0 >= 300
      end
      report_open = []
      found.each do |kind, list|
        list.group_by(&:first).each do |wid, rows|
          merged = []
          rows.sort_by { |r| r[1] }.each { |_, a0, a1| merged.last && a0 <= merged.last[1] + 50 ? merged.last[1] = [merged.last[1], a1].max : merged << [a0, a1] }
          merged.each do |a0, a1|
            w = ws.find { |x| x['id'] == wid }
            mid = Assistant.wall_point(w, (a0 + a1) / 2.0)
            near = texts.select { |t| Math.hypot(t[:at][0] - mid[0], t[:at][1] - mid[1]) <= 1200 }.map { |t| t[:s] }.join(' ')
            sill = kind == 'window' ? near[/(?:sill|جلسة)\s*[:=]?\s*(\d+(?:\.\d+)?)/i, 1] : nil
            hgt = near[/(?:\bh|height|ارتفاع)\s*[:=]?\s*(\d+(?:\.\d+)?)/i, 1]
            given = kind == 'door' ? !hgt.nil? : (!sill.nil? && !hgt.nil?)
            o = Assistant.add_opening(proj, wid, kind, a0.round(1), (a1 - a0).round(1), hgt ? num_mm(hgt) : (kind == 'door' ? DEF_DOOR_H : DEF_WIN_H),
                                      kind == 'door' ? 0.0 : (sill ? num_mm(sill) : DEF_SILL), given ? Assistant::CONFIRMED : Assistant::INFERRED)
            report_open << o
          end
        end
      end
      # ---- columns
      cols = []
      ents.select { |e| e[:type] == 'LWPOLYLINE' && e[:closed] && layer_is(e, /col|عمود/i) }.each do |e|
        pts = e[:pts].map { |p| tr.call(p) }
        w = ws.min_by { |x| pts.map { |p| Assistant.dist_to_wall(x, p) }.min }
        next if pts.map { |p| Assistant.dist_to_wall(w, p) }.min > NEAR_WALL

        a0, a1 = pts.map { |p| along.call(w, p) }.minmax
        nx = w['dir'][1]
        ny = -w['dir'][0]
        dep = pts.map { |p| ((p[0] - w['p0'][0]) * nx + (p[1] - w['p0'][1]) * ny).abs }.max
        cols << Assistant.add_column(proj, w['id'], [a0, 0].max.round(1), ([a1, w['len']].min - [a0, 0].max).round(1), dep.round(1), Assistant::CONFIRMED)
      end
      # ---- primary plumbing point
      marks = texts.select { |t| t[:s] =~ PLUMB_RE || t[:layer].to_s =~ /plumb|drain|water|sanit/i }.map { |t| t[:at] }
      marks += ents.select { |e| %w[POINT CIRCLE INSERT].include?(e[:type]) && layer_is(e, /plumb|drain|water|sanit|صرف|مياه/i) && e[:pts].any? }.map { |e| tr.call(e[:pts].first) }
      plumb = nil
      if marks.any?
        m = marks.min_by { |p| Assistant.dist_to_wall(nearest.call(p), p) }
        w = nearest.call(m)
        off = [[along.call(w, m), 0].max, w['len']].min.round(1)
        Assistant.add_service(proj, 'drain', w['id'], off, SiteDocs::WATER_Z['drain'], nil, Assistant::INFERRED)
        Assistant.add_service(proj, 'water_cold', w['id'], off, SiteDocs::WATER_Z['water_cold'], nil, Assistant::INFERRED)
        plumb = { 'wall' => w['id'], 'off' => off, 'dist_from_wall' => Assistant.dist_to_wall(w, m).round }
      else
        notes << 'no plumbing marker in the drawing: the sink goes under the window (or to the middle of the main wall); add a text DRAIN on the water wall to fix its place'
      end
      # ---- ceiling
      ct = texts.map { |t| t[:s][/(?:ceiling|clg|سقف)\s*[:=]?\s*(\d+(?:\.\d+)?)/i, 1] }.compact.first
      Assistant.set_ceiling(proj, ct ? num_mm(ct) : (opts['ceiling'].to_f.positive? ? opts['ceiling'].to_f : DEF_CEILING), ct || opts['ceiling'].to_f.positive? ? Assistant::CONFIRMED : Assistant::INFERRED)
      notes << "ceiling height not written in the drawing: #{DEF_CEILING.round} mm assumed - confirm it" unless ct || opts['ceiling'].to_f.positive?
      { 'unit' => usrc, 'scale' => scale, 'walls' => ws.map { |w| { 'id' => w['id'], 'len' => w['len'].round(1) } }, 'openings' => report_open.map { |o| o.slice('id', 'type', 'wall', 'off', 'w', 'h', 'sill', 'st') },
        'columns' => cols.map { |c| c.slice('id', 'wall', 'off', 'w', 'd') }, 'plumbing' => plumb, 'ceiling' => proj['room']['ceiling'], 'notes' => notes }
    end

    # Room walls drawn in the model: one group (tag EGC_ROOM, attribute egc/room_shell), each wall extruded to the ceiling as a single surface on the wall line,
    # with the door and window openings left open. Replaces the shell of an earlier import.
    def build_shell(model, proj)
      ceil = (proj['room']['ceiling']['v'] || DEF_CEILING).to_f
      model.entities.grep(Sketchup::Group).select { |g| g.get_attribute('egc', 'room_shell') }.each { |g| g.erase! if g.valid? }
      g = model.entities.add_group
      g.name = 'EGC_ROOM'
      g.set_attribute('egc', 'room_shell', true)
      g.layer = model.layers.add('EGC_ROOM')
      Assistant.walls(proj).each do |w|
        ops = proj['openings'].select { |o| o['wall'] == w['id'] }.sort_by { |o| o['off'] }
        rect = lambda do |a0, a1, z0, z1|
          next if a1 - a0 < 1 || z1 - z0 < 1

          p0 = Assistant.wall_point(w, a0)
          p1 = Assistant.wall_point(w, a1)
          g.entities.add_face([Geo.mm(p0[0]), Geo.mm(p0[1]), Geo.mm(z0)], [Geo.mm(p1[0]), Geo.mm(p1[1]), Geo.mm(z0)], [Geo.mm(p1[0]), Geo.mm(p1[1]), Geo.mm(z1)], [Geo.mm(p0[0]), Geo.mm(p0[1]), Geo.mm(z1)])
        end
        pos = 0.0
        ops.each do |o|
          rect.call(pos, o['off'], 0.0, ceil)
          top = [o['sill'].to_f + o['h'].to_f, ceil].min
          rect.call(o['off'], o['off'] + o['w'], 0.0, o['sill'].to_f) if o['type'] == 'window'
          rect.call(o['off'], o['off'] + o['w'], top, ceil)
          pos = o['off'] + o['w']
        end
        rect.call(pos, w['len'], 0.0, ceil)
      end
      g
    end
  end
end
