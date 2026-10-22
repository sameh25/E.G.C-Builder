# frozen_string_literal: true

require 'json'

module EGC
  # DIMENSION-FIRST room reconstruction from a picture. The vision provider (or a MOCK answer in tests) returns WHAT it sees - walls in order, openings,
  # every dimension text with its kind / target / chain / confidence / pixel end points - and this module, deterministically:
  #   parses the numbers (printed or handwritten, Arabic or Western digits, mm / cm / m, 4,000 / 4 000 / 4m), resolves the drawing unit,
  #   checks the scale of the drawing from the dimensioned pixel segments (rejects OCR outliers), adds dimension chains without double counting,
  #   cross-checks overall vs pieces and sill + height + above vs ceiling, builds the wall graph (any number of walls, any corner angle, open sides,
  #   parallel walls) and returns the SAME RoomModel structure as the SketchUp reader, with provenance on every value.
  # Nothing is invented: a value that is missing, unreadable, ambiguous or of low confidence becomes REQUIRES_CONFIRMATION with ONE precise question.
  module RoomReader
    module_function

    C = RoomModel::C
    I = RoomModel::I
    R = RoomModel::R
    CONF_MIN = 0.8      # below this the provider's reading must be confirmed by the user (handwriting, blur ...)
    SCALE_TOL = 0.06    # a dimension whose mm / px differs more than 6 % from the drawing's scale is an outlier
    KINDS = %w[wall_overall segment opening_width opening_offset opening_offset_end opening_height sill above ceiling wall_distance].freeze

    def num(v)
      v.is_a?(Numeric) ? v.to_f : nil
    end

    # '4,000' '4 000' '4000 mm' '4m' '2,6 م' '٤٠٠٠' '400 سم' -> [value, unit or nil]
    def parse(text)
      t = text.to_s.tr('٠١٢٣٤٥٦٧٨٩', '0123456789').tr('۰۱۲۳۴۵۶۷۸۹', '0123456789').tr('٫', '.').tr('٬', ',').downcase.strip
      unit = if t =~ /mm|مم|ملم|مللي/ then 'mm'
             elsif t =~ /cm|سم|سنتي/ then 'cm'
             elsif t =~ /\d\s*(m|م|متر)(?![a-z])/ then 'm'
             end
      s = t[/\d[\d.,' ]*\d|\d/]
      return [nil, unit] unless s

      s = s =~ /\A\d{1,3}([, ']\d{3})+(\.\d+)?\z/ ? s.gsub(/[, ']/, '') : s.tr(',', '.').delete(" '")
      v = Float(s) rescue nil
      [v, unit]
    end

    def factor(unit)
      { 'mm' => 1.0, 'cm' => 10.0, 'm' => 1000.0 }[unit.to_s]
    end

    def r1(v)
      v && v.to_f.round(1)
    end

    def prov(source, basis, conf, validation, extra = {})
      { 'source' => source, 'basis' => basis, 'confidence' => conf && conf.round(2), 'validation' => validation }.merge(extra)
    end

    # room = the provider's "room" object (+ 'source' => 'MOCK' for a canned answer); corrections = { 'wall:W2:len' => 6000, ... } typed by the user
    def solve(room, corrections = {})
      input = JSON.parse(JSON.generate(room))
      corr = corrections.transform_keys(&:to_s)
      mock = input['source'].to_s.upcase == 'MOCK'
      src_img = mock ? 'MOCK' : (input['source'].to_s.upcase == 'LOCAL_OCR' ? 'OCR' : 'IMAGE_DIMENSION')
      view = input['view'].to_s
      problems = []
      checks = []
      questions = []
      ask = lambda do |key, text, value = nil, conf = nil, choices = nil|
        questions << { 'key' => key, 'text' => text, 'value' => value, 'confidence' => conf, 'choices' => choices }.compact unless questions.any? { |q| q['key'] == key }
      end
      walls = Array(input['walls']).each_with_index.map do |w, i|
        { 'xid' => (w['id'] || "W#{i + 1}").to_s, 'label' => w['label'], 'open' => w['open'] == true, 'angle' => num(corr["wall:#{w['id'] || "W#{i + 1}"}:angle"]) || num(w['angle_to_next']) || 90.0,
          'next' => w.key?('next') ? w['next'] : :auto, 'px' => w['px'] }
      end
      if walls.empty?
        return insufficient(input, corr, src_img, ['no wall could be identified in the picture'])
      end

      label = ->(xid) { w = walls.find { |x| x['xid'] == xid.to_s }; w ? (w['label'] ? "#{w['label']} wall" : "wall #{xid}") : (xid.to_s =~ /\AO\d/ ? "opening #{xid}" : xid.to_s) }
      ops = Array(input['openings']).each_with_index.map { |o, i| { 'xid' => (o['id'] || "O#{i + 1}").to_s, 'wall' => o['wall'].to_s, 'type' => %w[door window opening].include?(o['type'].to_s) ? o['type'].to_s : 'window' } }
      # ---- numbers, unit, confidence
      dims = Array(input['dimensions']).each_with_index.map do |d, i|
        v, u = d['value'].is_a?(Numeric) ? [d['value'].to_f, nil] : parse(d['value'] || d['text'])
        u ||= parse(d['text'])[1]
        u ||= d['unit'].to_s if factor(d['unit'])
        { 'id' => (d['id'] || "D#{i + 1}").to_s, 'text' => (d['text'] || d['value']).to_s, 'raw' => v, 'unit' => u, 'kind' => KINDS.include?(d['kind'].to_s) ? d['kind'].to_s : nil,
          'target' => d['target'], 'chain' => d['chain'], 'order' => d['order'].to_i, 'hand' => d['handwritten'] == true, 'conf' => num(d['confidence']) || 1.0, 'px' => d['px'] }
      end
      gu = factor(input['unit']) ? input['unit'].to_s : nil
      unless gu # the drawing's unit from the size of its numbers (a room wall is 1 - 30 m)
        big = dims.reject { |d| d['unit'] || d['raw'].nil? || %w[opening_height sill above].include?(d['kind']) }.map { |d| d['raw'] }.max
        gu = big.nil? ? 'mm' : (big < 30 ? 'm' : (big < 1500 ? 'cm' : 'mm'))
        checks << { 'check' => 'drawing unit', 'result' => 'INFERRED', 'detail' => "no unit written: #{gu} (largest number #{big && big.round(2)})" } if big
      end
      dims.each do |d|
        d['mm'] = d['raw'] && r1(d['raw'] * factor(d['unit'] || gu))
        tgt = corr["dim:#{d['id']}:target"]
        if tgt.to_s == 'IGNORE' # the user says this number is not a wall of this room: kept in the list, used for nothing
          d['kind'] = nil
          d['ignored'] = true
        elsif tgt
          d['target'] = tgt
        end
        if corr.key?("dim:#{d['id']}:value")
          d['mm'] = r1(corr["dim:#{d['id']}:value"].to_f)
          d['user'] = true
        end
        if corr["dim:#{d['id']}:confirm"] && d['mm'] # the value as read, confirmed by the user with one click
          d['user'] = true
          d['confirmed'] = true
        end
        d['st'] = if d['mm'].nil? then R
                  elsif d['user'] || d['conf'] >= CONF_MIN then C
                  else R
                  end
        next unless d['st'] == R

        what = dim_name(d, label)
        if d['mm'].nil?
          ask.call("dim:#{d['id']}:value", "#{what}: \"#{d['text']}\" cannot be read - type it (mm).")
        else
          ask.call("dim:#{d['id']}:value", "#{what}: #{d['mm'].round} mm - confidence #{(d['conf'] * 100).round} %#{d['hand'] ? ' (handwritten)' : ''}", d['mm'], d['conf'])
        end
      end
      # ---- scale of the drawing (orthographic views only): every dimension with pixel end points gives mm / px
      scale = nil
      if %w[plan elevation].include?(view)
        rat = dims.filter_map { |d| px = d['px']; next unless d['mm'] && px.is_a?(Array) && px.size == 2; l = Math.hypot(px[1][0].to_f - px[0][0].to_f, px[1][1].to_f - px[0][1].to_f); [d, d['mm'] / l] if l > 5 }
        if rat.size >= 2
          med = rat.map(&:last).sort[rat.size / 2]
          out = rat.select { |_, k| (k / med - 1).abs > SCALE_TOL }
          out.each do |d, k|
            d['st'] = R unless d['user']
            problems << { 'code' => 'SCALE_OUTLIER', 'message' => "\"#{d['text']}\" (#{d['mm'].round} mm) does not match the drawing: its line measures #{(d['mm'] / k * med).round} mm at the scale of the other dimensions" } unless d['user']
            ask.call("dim:#{d['id']}:value", "\"#{d['text']}\" reads #{d['mm'].round} mm but the drawing scale gives about #{(d['mm'] / k * med).round(-1)} mm. Which is right?", d['mm'], d['conf']) unless d['user']
          end
          good = rat - out
          spread = good.map { |_, k| (k / med - 1).abs }.max.to_f
          scale = { 'mm_per_px' => med.round(4), 'n' => good.size, 'outliers' => out.size, 'confidence' => (1 - spread / SCALE_TOL).clamp(0.0, 1.0).round(2) }
          checks << { 'check' => 'drawing scale', 'result' => out.empty? ? 'PASS' : 'FAIL', 'detail' => "#{good.size} dimensions agree on #{med.round(3)} mm/px#{out.empty? ? '' : ", #{out.size} outlier(s)"}" }
        end
      end
      # a length without a wall: ask which wall it belongs to (never guess)
      dims.select { |d| d['kind'] == 'wall_overall' && (d['target'].nil? || walls.none? { |w| w['xid'] == d['target'].to_s }) }.each do |d|
        problems << { 'code' => 'AMBIGUOUS_DIMENSION', 'message' => "#{d['text']} is a wall length but its wall is not clear" }
        ask.call("dim:#{d['id']}:target", "Which wall does #{d['mm'] ? "#{d['mm'].round} mm" : d['text']} belong to?", nil, d['conf'], walls.map { |w| w['xid'] } + ['IGNORE'])
      end
      dims.reject { |d| d['kind'] }.each { |d| checks << { 'check' => "dimension #{d['text']}", 'result' => 'IGNORED', 'detail' => d['ignored'] ? 'set aside by the user: not a wall of this room' : 'the provider did not say what it measures' } }
      val = ->(d) { d && d['mm'] }
      conf_of = ->(list) { list.map { |d| d['user'] ? 1.0 : d['conf'] }.min }
      st_of = ->(list) { list.any? { |d| d['st'] == R } ? R : C }
      src_of = ->(list) { list.all? { |d| d['user'] } ? (list.all? { |d| d['confirmed'] } ? 'USER_CONFIRMED' : 'USER_CORRECTION') : src_img }
      hand = ->(list) { list.any? { |d| d['hand'] } ? { 'handwritten' => true } : {} }
      # ---- chains (pieces along one wall, in order); a chain belongs to the wall its pieces / its opening are on
      op_wall = ops.to_h { |o| [o['xid'], o['wall']] }
      chains = dims.select { |d| d['chain'] && %w[segment opening_width opening_offset opening_offset_end].include?(d['kind']) }.group_by { |d| d['chain'].to_s }.transform_values { |l| l.sort_by { |d| d['order'] } }
      chain_wall = chains.transform_values { |l| l.map { |d| walls.any? { |w| w['xid'] == d['target'].to_s } ? d['target'].to_s : op_wall[d['target'].to_s] }.compact.first }
      # ---- walls
      walls.each do |w|
        if corr.key?("wall:#{w['xid']}:len")
          w['len'] = r1(corr["wall:#{w['xid']}:len"])
          w['st'] = C
          w['prov'] = prov('USER_CORRECTION', 'typed by the user', 1.0, 'USER')
          next
        end
        ov = dims.select { |d| d['kind'] == 'wall_overall' && d['target'].to_s == w['xid'] && d['mm'] }
        ch = chains.select { |k, _| chain_wall[k] == w['xid'] }.values
        piece = ch.max_by(&:size)
        csum = piece && piece.all? { |d| d['mm'] } ? r1(piece.sum { |d| d['mm'] }) : nil
        if ov.map { |d| d['mm'] }.uniq.size > 1
          problems << { 'code' => 'DIMENSIONS_DISAGREE', 'message' => "#{label.call(w['xid'])}: written as #{ov.map { |d| d['mm'].round }.join(' and ')} mm" }
          ask.call("wall:#{w['xid']}:len", "#{label.call(w['xid'])} is written as #{ov.map { |d| d['mm'].round }.uniq.join(' and ')} mm. Which is right?", ov.first['mm'])
        end
        if ov.any? && csum
          ok = (ov.first['mm'] - csum).abs <= 1.0
          checks << { 'check' => "#{label.call(w['xid'])}: #{piece.map { |d| d['mm'].round }.join(' + ')} = #{csum.round} vs overall #{ov.first['mm'].round}", 'result' => ok ? 'PASS' : 'FAIL' }
          w['len'] = ov.first['mm']
          w['st'] = ok ? st_of.call(ov + piece) : R
          w['prov'] = prov(src_of.call(ov), 'overall dimension, confirmed by its chain', conf_of.call(ov + piece), ok ? 'PASS' : 'FAIL', hand.call(ov + piece))
          unless ok
            problems << { 'code' => 'DIMENSIONS_DO_NOT_ADD_UP', 'message' => "#{label.call(w['xid'])}: pieces #{piece.map { |d| d['mm'].round }.join(' + ')} = #{csum.round} mm but the overall dimension is #{ov.first['mm'].round} mm" }
            ask.call("wall:#{w['xid']}:len", "#{label.call(w['xid'])}: the pieces add up to #{csum.round} mm but the overall dimension says #{ov.first['mm'].round} mm. What is the real length?", ov.first['mm'])
          end
        elsif ov.any?
          w['len'] = ov.first['mm']
          w['st'] = ov.map { |d| d['mm'] }.uniq.size > 1 ? R : st_of.call(ov)
          w['prov'] = prov(src_of.call(ov), 'overall dimension', conf_of.call(ov), 'UNCHECKED', hand.call(ov))
        elsif csum
          w['len'] = csum
          w['st'] = st_of.call(piece)
          w['prov'] = prov('GEOMETRY', "sum of the dimension chain #{piece.map { |d| d['mm'].round }.join(' + ')}", conf_of.call(piece), 'DERIVED', hand.call(piece))
          checks << { 'check' => "#{label.call(w['xid'])}: #{piece.map { |d| d['mm'].round }.join(' + ')} = #{csum.round}", 'result' => 'PASS', 'detail' => 'no overall dimension; length = sum of the chain' }
        elsif scale && w['px'].is_a?(Array) && w['px'].size == 2 && !w['open']
          l = Math.hypot(w['px'][1][0].to_f - w['px'][0][0].to_f, w['px'][1][1].to_f - w['px'][0][1].to_f) * scale['mm_per_px']
          w['len'] = l.round(-1)
          w['st'] = I
          w['prov'] = prov('GEOMETRY', "measured on the drawing at #{scale['mm_per_px']} mm/px (no dimension written)", scale['confidence'], 'SCALED')
          ask.call("wall:#{w['xid']}:len", "#{label.call(w['xid'])} has no written dimension; the drawing scale gives about #{w['len'].round} mm. Confirm or type it.", w['len'])
        elsif w['open']
          w['len'] = nil
        else
          w['len'] = nil
          w['st'] = R
          problems << { 'code' => 'INSUFFICIENT_DIMENSIONAL_EVIDENCE', 'message' => "#{label.call(w['xid'])}: no written length, no dimension chain and no drawing scale" }
          ask.call("wall:#{w['xid']}:len", "Length of the #{label.call(w['xid'])} is not written - type it (mm).")
        end
      end
      # ---- openings
      ceil_d = dims.select { |d| d['kind'] == 'ceiling' && d['mm'] }
      ceiling = if corr.key?('ceiling') then { 'v' => r1(corr['ceiling']), 'st' => C, 'prov' => prov('USER_CORRECTION', 'typed by the user', 1.0, 'USER') }
                elsif ceil_d.any? then { 'v' => ceil_d.first['mm'], 'st' => ceil_d.map { |d| d['mm'] }.uniq.size > 1 ? R : st_of.call(ceil_d), 'prov' => prov(src_of.call(ceil_d), 'ceiling dimension', conf_of.call(ceil_d), 'UNCHECKED', hand.call(ceil_d)) }
                end
      openings = ops.map do |o|
        one = ->(kind) { dims.find { |d| d['kind'] == kind && d['target'].to_s == o['xid'] && d['mm'] } }
        used = []
        f = {}
        pv = {}
        %w[w h sill above].zip(%w[opening_width opening_height sill above]).each do |k, kind|
          d = one.call(kind)
          next unless d

          f[k] = d['mm']
          used << d
          pv[k] = src_of.call([d])
        end
        chain = chains.values.find { |l| l.any? { |d| d['kind'] == 'opening_width' && d['target'].to_s == o['xid'] } }
        if chain
          i = chain.index { |d| d['kind'] == 'opening_width' && d['target'].to_s == o['xid'] }
          f['off'] = r1(chain[0...i].sum { |d| d['mm'].to_f })
          used.concat(chain[0...i])
          pv['off'] = 'GEOMETRY'
        elsif (d = one.call('opening_offset'))
          f['off'] = d['mm']
          used << d
          pv['off'] = src_of.call([d])
        elsif (d = one.call('opening_offset_end')) && f['w'] && (wl = walls.find { |w| w['xid'] == o['wall'] }) && wl['len']
          f['off'] = r1(wl['len'] - d['mm'] - f['w'])
          used << d
          pv['off'] = 'GEOMETRY'
        end
        %w[off w h sill].each { |k| next unless corr.key?("opening:#{o['xid']}:#{k}"); f[k] = r1(corr["opening:#{o['xid']}:#{k}"]); pv[k] = 'USER_CORRECTION' }
        cv = ceiling && ceiling['v']
        if cv
          if f['sill'].nil? && f['h'] && f['above']
            f['sill'] = r1(cv - f['h'] - f['above'])
            pv['sill'] = 'GEOMETRY'
          elsif f['above'].nil? && f['h'] && f['sill']
            f['above'] = r1(cv - f['sill'] - f['h'])
            pv['above'] = 'GEOMETRY'
          elsif f['h'].nil? && f['sill'] && f['above']
            f['h'] = r1(cv - f['sill'] - f['above'])
            pv['h'] = 'GEOMETRY'
          end
          if f['sill'] && f['h'] && f['above']
            ok = (f['sill'] + f['h'] + f['above'] - cv).abs <= 1.0
            checks << { 'check' => "#{o['xid']}: sill #{f['sill'].round} + height #{f['h'].round} + above #{f['above'].round} = #{(f['sill'] + f['h'] + f['above']).round} vs ceiling #{cv.round}", 'result' => ok ? 'PASS' : 'FAIL' }
            problems << { 'code' => 'DIMENSIONS_DO_NOT_ADD_UP', 'message' => "#{o['xid']}: sill + height + above = #{(f['sill'] + f['h'] + f['above']).round} mm but the ceiling is #{cv.round} mm" } unless ok
          end
        end
        f['sill'] ||= 0.0 if o['type'] == 'door'
        miss = %w[off w h sill].reject { |k| f[k] }
        miss.each { |k| ask.call("opening:#{o['xid']}:#{k}", "#{o['type'].capitalize} #{o['xid']} on the #{label.call(o['wall'])}: #{{ 'off' => 'distance from the start of the wall', 'w' => 'width', 'h' => 'height', 'sill' => 'height from the floor' }[k]} is not written - type it (mm).") }
        st = miss.empty? && used.none? { |d| d['st'] == R } ? C : R
        { 'xid' => o['xid'], 'xwall' => o['wall'], 'type' => o['type'] == 'opening' ? 'window' : o['type'], 'off' => f['off'], 'w' => f['w'], 'h' => f['h'], 'sill' => f['sill'], 'above' => f['above'], 'st' => st,
          'prov' => prov((pv.values & %w[USER_CORRECTION USER_CONFIRMED]).first || src_img, pv.map { |k, v| "#{k}: #{v}" }.join(', '), used.empty? ? nil : conf_of.call(used), st == C ? 'PASS' : 'INCOMPLETE', hand.call(used)) }
      end
      if ceiling.nil? # ceiling = sill + height + above of a fully dimensioned opening
        o = openings.find { |x| x['sill'] && x['h'] && x['above'] }
        ceiling = o ? { 'v' => r1(o['sill'] + o['h'] + o['above']), 'st' => o['st'], 'prov' => prov('GEOMETRY', "sill + height + above of #{o['xid']}", o['prov']['confidence'], 'DERIVED') } : nil
      end
      unless ceiling
        ceiling = { 'v' => nil, 'st' => R, 'prov' => prov(nil, 'not written', nil, 'MISSING') }
        ask.call('ceiling', 'The ceiling height is not written - type it (mm).')
      end
      # ---- geometry
      geo = build_geometry(input, walls, dims, corr, label, ask, problems, checks)
      rm = assemble(input, corr, src_img, walls, openings, ceiling, dims, geo, problems, checks, questions, scale)
      rm
    end

    # wall graph -> polygon. Walls are listed in order walking around the room with the room on the RIGHT; 'angle_to_next' = inside corner angle
    # (90 = square corner). An open chain is closed by open (non-physical) sides; two unconnected walls facing each other = parallel walls.
    def build_geometry(input, walls, dims, corr, label, ask, problems, checks)
      phys = walls.reject { |w| w['open'] }
      parallel = walls.size == 2 && (input['type'].to_s == 'parallel' || walls[0]['next'].nil? || walls.any? { |w| w['opposite'] })
      if parallel
        d = dims.find { |x| x['kind'] == 'wall_distance' && x['mm'] }
        gap = corr['distance'] ? corr['distance'].to_f : (d && d['mm'])
        a, b = walls.map { |w| w['len'] }
        unless gap
          problems << { 'code' => 'INSUFFICIENT_DIMENSIONAL_EVIDENCE', 'message' => 'two parallel walls but the distance between them is not written' }
          ask.call('distance', 'What is the distance between the two parallel walls (mm)?')
        end
        len = [a, b].compact.min
        problems << { 'code' => 'PARALLEL_WALLS_DIFFER', 'message' => "the parallel walls are #{a.round} and #{b.round} mm: the shorter length is used for both" } if a && b && (a - b).abs > 1
        g = gap || 0.0
        pts = [[0.0, 0.0], [0.0, g], [len.to_f, g], [len.to_f, 0.0]]
        # edge 1 (top) = first wall, edge 3 (bottom) = second wall, the ends are open
        return { 'pts' => pts, 'edges' => [nil, walls[0], nil, walls[1]], 'closed' => false, 'gap' => gap, 'gap_st' => gap ? (corr['distance'] || d['st'] == C ? C : R) : R }
      end
      # open sides without a length at the end of the list (e.g. the side open to the living room) are simply the side that closes the room
      tail = []
      walls = walls.dup
      tail.unshift(walls.pop) while walls.size > 1 && walls.last['open'] && walls.last['len'].nil?
      pts = [[0.0, 0.0]]
      dir = [0.0, 1.0]
      walls.each do |w|
        l = w['len'] || 0.0
        p = pts.last
        pts << [p[0] + dir[0] * l, p[1] + dir[1] * l]
        t = (180.0 - w['angle']) * Math::PI / 180.0 # turn right by (180 - inside angle)
        dir = [dir[0] * Math.cos(t) + dir[1] * Math.sin(t), -dir[0] * Math.sin(t) + dir[1] * Math.cos(t)]
      end
      per = walls.sum { |w| w['len'].to_f }
      gap = Math.hypot(pts.last[0] - pts[0][0], pts.last[1] - pts[0][1])
      wants_closed = tail.empty? && (walls.last['next'].to_s == walls.first['xid'] || input['closed'] == true)
      closed = tail.empty? && walls.size >= 3 && gap <= [30.0, per * 0.005].max
      if wants_closed && !closed && walls.all? { |w| w['len'] }
        problems << { 'code' => 'GEOMETRY_DOES_NOT_CLOSE', 'message' => "the walls do not close the room: #{gap.round} mm gap (check a length or a corner angle)" }
        checks << { 'check' => 'room closes', 'result' => 'FAIL', 'detail' => "gap #{gap.round} mm" }
      elsif closed
        checks << { 'check' => 'room closes', 'result' => 'PASS', 'detail' => "gap #{gap.round} mm over #{per.round} mm of walls" }
      end
      if closed
        pts.pop
        edges = walls.dup
      elsif walls.size == 1
        dep = corr['depth'] ? corr['depth'].to_f : (dims.find { |x| x['kind'] == 'wall_distance' && x['mm'] } || {})['mm']
        ask.call('depth', 'How deep is the room in front of this wall (mm)? Only one wall is visible.') unless dep
        dep ||= AssistantVision::ROOM_DEPTH_ASSUMED # an open side only: flagged as an assumption, never a wall length
        l = walls[0]['len'].to_f
        # the wall is the north side of the room, the other three sides are open
        pts = [[0.0, 0.0], [0.0, dep.to_f], [l, dep.to_f], [l, 0.0]]
        return { 'pts' => pts, 'edges' => [nil, walls[0], nil, nil], 'closed' => false, 'depth' => dep, 'depth_st' => corr['depth'] ? C : I }
      elsif walls.size == 2
        q = [pts[0][0] + pts[2][0] - pts[1][0], pts[0][1] + pts[2][1] - pts[1][1]] # the open L is completed as a parallelogram
        pts << q
        edges = walls + [tail[0], tail[1]]
      else
        edges = walls + [tail[0]] # the last end is joined straight back to the first corner (open side)
      end
      { 'pts' => pts, 'edges' => edges, 'closed' => closed }
    end

    # polygon (clockwise, wall A from the south-west corner) + the SAME fields as every other RoomModel
    def assemble(input, corr, src_img, walls, openings, ceiling, dims, geo, problems, checks, questions, scale)
      pts = geo['pts']
      edges = geo['edges']
      if Assistant.signed_area(pts) > 0 # anticlockwise: walk the other way round (offsets along a wall are mirrored)
        pts = [pts[0]] + pts[1..].reverse
        edges = edges.reverse
        flipped = true
      end
      k = (0...pts.size).min_by { |i| [pts[i][0] + pts[i][1], pts[i][0]] }
      pts = pts.rotate(k)
      edges = edges.rotate(k)
      ox, oy = pts.first
      poly = pts.map { |x, y| [(x - ox).round(1), (y - oy).round(1)] }
      ids = RoomModel::IDS
      map = {}
      rmw = RoomModel.wall_dirs(poly).each_with_index.map do |x, i|
        w = edges[i]
        map[w['xid']] = x['id'] if w
        if w && !w['open']
          { 'id' => x['id'], 'name' => w['label'], 'xid' => w['xid'], 'len' => x['len'], 'physical' => true, 'st' => w['st'] || R, 'prov' => w['prov'],
            'src' => w['prov'] ? "#{w['prov']['source']}: #{w['prov']['basis']}" : 'missing' }
        else
          { 'id' => x['id'], 'name' => w && w['label'], 'xid' => w && w['xid'], 'len' => x['len'], 'physical' => false, 'st' => I, 'prov' => prov('GEOMETRY', 'open side (no wall in the picture)', nil, 'DERIVED'),
            'src' => 'GEOMETRY: open side of the room (no wall)' }
        end
      end
      rops = openings.filter_map do |o|
        wid = map[o['xwall']]
        unless wid
          problems << { 'code' => 'OPENING_WALL_UNKNOWN', 'message' => "#{o['xid']}: its wall #{o['xwall']} is not in the room" }
          next
        end
        wl = rmw.find { |x| x['id'] == wid }['len']
        off = o['off']
        off = r1(wl - off - o['w']) if flipped && off && o['w']
        o.reject { |kk, _| %w[xwall].include?(kk) }.merge('wall' => wid, 'off' => off, 'src' => "#{o['prov']['source']}: #{o['prov']['basis']}")
      end
      st_ceiling = ceiling['st']
      main = rmw.select { |w| w['physical'] }.find { |w| w['name'].to_s =~ /main|رئيس/i } || rmw.select { |w| w['physical'] }.max_by { |w| w['len'] }
      rm = { 'source' => 'image', 'reader' => true, 'engine' => input['engine'] || (src_img == 'MOCK' ? 'MOCK' : 'AI provider'), 'type' => input['type'].to_s.empty? ? topology(rmw, geo) : input['type'].to_s, 'topology' => topology(rmw, geo), 'mock' => src_img == 'MOCK',
             'poly' => poly, 'walls' => rmw, 'openings' => rops,
             'ceiling' => { 'v' => ceiling['v'], 'st' => st_ceiling, 'prov' => ceiling['prov'], 'src' => ceiling['prov'] && "#{ceiling['prov']['source']}: #{ceiling['prov']['basis']}" },
             'angles' => walls.each_cons(2).map { |a, b| { 'at' => "#{map[a['xid']]}-#{map[b['xid']]}", 'deg' => a['angle'], 'wall' => a['xid'] } },
             'dims' => dims.map { |d| { 'id' => d['id'], 'text' => d['text'], 'value' => d['mm'], 'measured' => nil, 'kind' => d['kind'], 'what' => d['kind'] ? "#{d['kind']} #{Array(d['target']).join('/')}" : 'not used', 'st' => d['st'], 'confidence' => d['conf'], 'handwritten' => d['hand'] } },
             'checks' => checks, 'questions' => questions, 'scale' => scale, 'problems' => problems, 'main_wall' => main && main['id'],
             'input' => input, 'corrections' => corr, 'map' => map }
      rm['depth'] = { 'v' => geo['depth'], 'st' => geo['depth_st'] } if geo['depth']
      rm['distance'] = { 'v' => geo['gap'], 'st' => geo['gap_st'] } if geo.key?('gap')
      rm['relations'] = rm['angles'].map { |a| "#{a['at']}: #{a['deg'].round} deg corner" }
      blocking = rm['walls'].any? { |w| w['physical'] && w['st'] == R } || st_ceiling == R || rops.any? { |o| o['st'] == R } ||
                 (geo.key?('gap') && geo['gap_st'] == R) || problems.any? { |p| %w[INSUFFICIENT_DIMENSIONAL_EVIDENCE GEOMETRY_DOES_NOT_CLOSE AMBIGUOUS_DIMENSION].include?(p['code']) }
      rm['ready'] = !blocking
      rm['status'] = if problems.any? { |p| p['code'] == 'INSUFFICIENT_DIMENSIONAL_EVIDENCE' } then 'INSUFFICIENT DIMENSIONAL EVIDENCE'
                     elsif blocking then 'REQUIRES CONFIRMATION'
                     else 'RECONSTRUCTED'
                     end
      rm
    end

    def topology(rmw, geo)
      ph = rmw.count { |w| w['physical'] }
      return 'parallel' if geo.key?('gap')
      return 'single_wall' if ph == 1
      return 'L' if ph == 2
      return 'U' if ph == 3 && !geo['closed']
      return 'closed_rectangle' if geo['closed'] && rmw.size == 4 && ph == 4

      geo['closed'] ? 'closed_irregular' : 'open_irregular'
    end

    def insufficient(input, corr, src_img, missing)
      { 'source' => 'image', 'reader' => true, 'mock' => src_img == 'MOCK', 'poly' => [], 'walls' => [], 'openings' => [], 'ceiling' => { 'v' => nil, 'st' => R, 'src' => 'not written' },
        'dims' => [], 'checks' => [], 'questions' => [], 'problems' => missing.map { |m| { 'code' => 'INSUFFICIENT_DIMENSIONAL_EVIDENCE', 'message' => m } },
        'status' => 'INSUFFICIENT DIMENSIONAL EVIDENCE', 'ready' => false, 'input' => input, 'corrections' => corr, 'map' => {} }
    end

    # what one dimension measures, in words: "Opening O1 width", "Left wall length", "Ceiling height"
    NAMES = { 'opening_width' => 'width', 'opening_height' => 'height', 'sill' => 'sill (floor to opening)', 'above' => 'above the opening (to the ceiling)',
              'opening_offset' => 'distance from the start of the wall', 'opening_offset_end' => 'distance to the end of the wall', 'wall_overall' => 'length',
              'segment' => 'piece of the dimension chain', 'wall_distance' => 'distance between the walls' }.freeze

    def dim_name(d, label)
      return 'Ceiling height' if d['kind'] == 'ceiling'

      tg = d['target'].is_a?(Array) ? d['target'].map { |t| label.call(t) }.join(' / ') : (d['target'] ? label.call(d['target']) : 'Dimension')
      "#{tg[0].upcase}#{tg[1..]} #{NAMES[d['kind']] || 'dimension'}".strip
    end

    # a correction typed in the room table (RoomModel ids) -> the reader's own ids -> solved again. Everything else stays as read.
    def correct(rm, key, value)
      parts = key.to_s.split(':')
      inv = rm['map'].invert
      k = case parts[0]
          when 'wall' then "wall:#{inv[parts[1]] || parts[1]}:#{parts[2] == 'angle' ? 'angle' : 'len'}"
          when 'opening' then "opening:#{(rm['openings'][parts[1].to_i] || {})['xid'] || parts[1]}:#{parts[2]}"
          else key.to_s
          end
      return solve(rm['input'], rm['corrections'].merge(k => true)) if parts[0] == 'dim' && parts[2] == 'confirm'

      v = value.is_a?(String) && parts[2] == 'target' ? value : value.to_f
      raise "#{key}: a positive number is required" if v.is_a?(Float) && !v.positive? && !key.to_s.end_with?(':sill')

      solve(rm['input'], rm['corrections'].merge(k => v))
    end
  end
end
