# frozen_string_literal: true

require 'json'
require 'tmpdir'

module EGC
  # LOCAL image reading - no AI provider, no key, no internet. The text recognition built into Windows (Windows.Media.Ocr, tools/ocr.ps1) gives every
  # number written on the picture with its position; this module turns them into the SAME dimension-first room description the AI provider is asked
  # for, which RoomReader then solves (units, chains, checks, geometry, questions). The interpretation is deterministic and uses only arithmetic and
  # position on the picture - no dimension of any test room is known here:
  #   - three values stacked one above the other that add up to a fourth one  -> above + opening height + sill = ceiling (the opening)
  #   - the value nearest that opening = its width; the nearest values left / right of it = the wall pieces of the same chain
  #   - any other value = the length of the wall on that side of the picture
  # Anything this cannot decide is sent as an open question (never guessed). OCR has no confidence of its own: a clean number next to its unit gets 0.9,
  # a number dug out of noise (dimension ticks read as characters) 0.6 -> the user confirms that one value.
  # Limits: printed / typed digits read well; handwriting depends on the Windows OCR and is NOT claimed; the wall layout of an arbitrary picture is only
  # what the numbers' positions support (corner angles are taken as 90 degrees and marked as an assumption).
  module ImageLocal
    module_function

    SCRIPT = File.join(File.dirname(__FILE__), 'tools', 'ocr.ps1')
    UNIT = /\A(mm|cm|m|مم|سم|م|ملم)\.?\z/i
    DIG = '0-9٠-٩۰-۹'

    def available?
      RUBY_PLATFORM =~ /mswin|mingw|cygwin/ && File.exist?(SCRIPT)
    end

    def ocr(path)
      return { 'ok' => false, 'error' => 'LOCAL_OCR_UNAVAILABLE: local text recognition needs Windows 10/11.' } unless available?

      out = File.join(Dir.tmpdir, "egc_ocr_#{Process.pid}_#{rand(1_000_000)}.json")
      ok = system('powershell', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', SCRIPT, '-Path', path.to_s, '-Out', out)
      return { 'ok' => false, 'error' => 'LOCAL_OCR_FAILED: Windows PowerShell could not be started.' } unless ok && File.exist?(out)

      JSON.parse(File.read(out, encoding: 'bom|utf-8'))
    ensure
      File.delete(out) if out && File.exist?(out)
    end

    # every number on the picture: { text, value_text, unit, conf, cx, cy, h, pass }
    def tokens_of(pass)
      out = []
      Array(pass['lines']).each do |ln|
        ws = Array(ln['words'])
        ws.each_with_index do |w, i|
          t = w['text'].to_s
          next unless t =~ /[#{DIG}]/

          nxt = ws[i + 1] && ws[i + 1]['text'].to_s
          unit = nxt =~ UNIT ? nxt : nil
          cx = w['x'].to_f + w['w'].to_f / 2
          cy = w['y'].to_f + w['h'].to_f / 2
          if t =~ /\A[#{DIG}][#{DIG}.,٫٬']*\z/ || t =~ /\A[#{DIG}][#{DIG}.,]*(mm|cm|m|مم|سم|م)\z/i
            out << { 'text' => [t, unit].compact.join(' '), 'conf' => unit || t =~ /[a-zم]/i ? 0.9 : 0.85, 'cx' => cx, 'cy' => cy, 'h' => w['h'].to_f, 'clean' => true }
          else # dimension ticks / arrows read as characters around the number
            t.scan(/[#{DIG}]{3,}/).each { |g| out << { 'text' => [g, unit].compact.join(' '), 'conf' => 0.6, 'cx' => cx, 'cy' => cy, 'h' => w['h'].to_f, 'clean' => false, 'raw' => t } }
          end
        end
      end
      out.each { |k| v, u = RoomReader.parse(k['text']); k['v'] = v; k['unit'] = u }
      out.select { |k| k['v'] }
    end

    # least squares x' = a x + b y + c (and the same for y) from matched points; nil when it cannot be fitted
    def affine(pairs)
      return nil if pairs.size < 3

      solve = lambda do |idx|
        m = Array.new(3) { Array.new(4, 0.0) }
        pairs.each do |(x, y), q|
          r = [x, y, 1.0]
          3.times { |i| 3.times { |j| m[i][j] += r[i] * r[j] }; m[i][3] += r[i] * q[idx] }
        end
        3.times do |c|
          p = (c...3).max_by { |r| m[r][c].abs }
          return nil if m[p][c].abs < 1e-9

          m[c], m[p] = m[p], m[c]
          (0...3).each { |r| next if r == c; f = m[r][c] / m[c][c]; (c..3).each { |j| m[r][j] -= f * m[c][j] } }
        end
        (0...3).map { |i| m[i][3] / m[i][i] }
      end
      ax = solve.call(0)
      ay = solve.call(1)
      ax && ay ? ->(x, y) { [ax[0] * x + ax[1] * y + ax[2], ay[0] * x + ay[1] * y + ay[2]] } : nil
    end

    # all passes -> one list in the frame of the best pass (each pass may deskew differently: aligned on the numbers they share)
    def merge(o)
      passes = Array(o['passes']).map { |p| [p, tokens_of(p)] }.reject { |_, t| t.empty? }
      return [] if passes.empty?

      base_p, base = passes.max_by { |p, t| [t.count { |k| k['clean'] }, -p['scale'].to_f] }
      list = base.map(&:dup)
      passes.each do |p, toks|
        next if p.equal?(base_p)

        pairs = toks.select { |k| k['clean'] }.filter_map do |k|
          same = base.select { |b| b['clean'] && b['v'] == k['v'] }
          [[k['cx'], k['cy']], [same[0]['cx'], same[0]['cy']]] if same.size == 1
        end
        f = affine(pairs)
        next unless f

        toks.each do |k|
          x, y = f.call(k['cx'], k['cy'])
          next if list.any? { |b| b['v'] == k['v'] && Math.hypot(b['cx'] - x, b['cy'] - y) < 40 }

          list << k.merge('cx' => x.round(1), 'cy' => y.round(1), 'pass' => "#{p['lang']} x#{p['scale']}")
        end
      end
      list
    end

    def mm_of(toks)
      units = toks.filter_map { |k| k['unit'] }
      gu = units.empty? ? nil : units.tally.max_by(&:last)[0]
      unless gu
        big = toks.map { |k| k['v'] }.max.to_f
        gu = big < 30 ? 'm' : (big < 1500 ? 'cm' : 'mm')
      end
      toks.each { |k| k['mm'] = (k['v'] * RoomReader.factor(k['unit'] || gu)).round(1) }
      gu
    end

    # [left, opening, right]: two values at about the same height with a value between them (the smallest one, when several lie between), or nil
    def chain_of(toks)
      best = nil
      toks.combination(2).each do |a, b|
        l, r = [a, b].sort_by { |k| k['cx'] }
        dx = r['cx'] - l['cx']
        next unless dx.positive? && (l['cy'] - r['cy']).abs <= dx * 0.2

        mid = toks.select { |k| !k.equal?(l) && !k.equal?(r) && k['cx'] > l['cx'] && k['cx'] < r['cx'] }.min_by { |k| k['mm'] }
        next unless mid

        best = [l, mid, r, dx] if best.nil? || dx > best[3]
      end
      best && best[0, 3]
    end

    # numbers + positions -> the dimension-first room description (the provider's format), source LOCAL_OCR
    def interpret(o)
      toks = merge(o)
      gu = toks.empty? ? nil : mm_of(toks)
      amb = []
      dims = []
      add = ->(k, kind, target, extra = {}) { dims << { 'id' => "D#{dims.size + 1}", 'text' => k['text'], 'kind' => kind, 'target' => target, 'confidence' => k['conf'], 'handwritten' => false, 'px' => nil }.merge(extra); k['used'] = true }
      dist = ->(a, b) { Math.hypot(a['cx'] - b['cx'], a['cy'] - b['cy']) }
      # 1. the opening: above + height + sill = ceiling, written one above the other
      stack = nil
      toks.select { |c| c['mm'].between?(1800, 5000) }.sort_by { |c| -c['mm'] }.each do |c|
        rest = toks.reject { |k| k.equal?(c) }
        rest.combination(3).each do |tri|
          next unless (tri.sum { |k| k['mm'] } - c['mm']).abs <= [1.0, c['mm'] * 0.003].max

          spread = tri.combination(2).map { |a, b| dist.call(a, b) }.max
          stack = [c, tri.sort_by { |k| k['cy'] }, spread] if stack.nil? || spread < stack[2]
        end
      end
      walls = []
      ops = []
      if stack
        c, (above, height, sill), = stack
        ops << { 'id' => 'O1', 'wall' => 'W2', 'type' => sill['mm'] < 50 ? 'door' : 'window' }
        add.call(c, 'ceiling', nil)
        add.call(above, 'above', 'O1')
        add.call(height, 'opening_height', 'O1')
        add.call(sill, 'sill', 'O1')
        # 2. the opening width = the free value nearest the opening; the chain pieces = the nearest free values on its left / right
        cen = { 'cx' => [above, height, sill].sum { |k| k['cx'] } / 3.0, 'cy' => [above, height, sill].sum { |k| k['cy'] } / 3.0 }
        free = -> { toks.reject { |k| k['used'] } }
        wid = free.call.min_by { |k| dist.call(k, cen) }
        chain_x = []
        if wid
          left = free.call.reject { |k| k.equal?(wid) }.select { |k| k['cx'] < wid['cx'] }.min_by { |k| dist.call(k, wid) }
          right = free.call.reject { |k| k.equal?(wid) }.select { |k| k['cx'] > wid['cx'] }.min_by { |k| dist.call(k, wid) }
          n = 0
          if left
            add.call(left, 'segment', 'W2', 'chain' => 'C1', 'order' => n)
            n += 1
          end
          add.call(wid, 'opening_width', 'O1', 'chain' => 'C1', 'order' => n)
          n += 1
          add.call(right, 'segment', 'W2', 'chain' => 'C1', 'order' => n) if right
          chain_x = [left, wid, right].compact.map { |k| k['cx'] }
          amb << 'the opening has a dimension on one side only: its distance to the other end of the wall is not written' unless left && right
        end
        # 3. other values: the length of the wall on that side of the picture
        lo, hi = chain_x.minmax
        others = toks.reject { |k| k['used'] }
        lefts = others.select { |k| lo && k['cx'] < lo }
        rights = others.select { |k| hi && k['cx'] > hi }
        walls << { 'id' => 'W1', 'label' => 'left', 'angle_to_next' => 90, 'next' => 'W2' } if lefts.any?
        walls << { 'id' => 'W2', 'label' => 'main', 'angle_to_next' => 90, 'next' => rights.any? ? 'W3' : nil }
        walls << { 'id' => 'W3', 'label' => 'right', 'angle_to_next' => 90, 'next' => nil } if rights.any?
        [[lefts, 'W1'], [rights, 'W3']].each do |l, w|
          if l.size == 1 then add.call(l[0], 'wall_overall', w)
          else l.each { |k| add.call(k, 'wall_overall', nil) } # more than one value on that side: the user says which wall
          end
        end
        others.select { |k| !k['used'] }.each { |k| add.call(k, 'wall_overall', nil) }
        amb << 'corner angles are not dimensioned on the picture: 90 degrees assumed' if walls.size > 1
      elsif (ch = chain_of(toks))
        # 1b. no height stack, but a DIMENSION CHAIN along one wall: left piece + opening + right piece (two values side by side at about the same height
        # with a value between them). The opening, its width and its place come from the chain; the wall is their sum. The opening width is bound by
        # its position only -> one confirmation. Height and sill are not written: they are asked for, never guessed.
        left, wid, right = ch
        walls << { 'id' => 'W1', 'label' => 'main', 'angle_to_next' => 90, 'next' => nil }
        ops << { 'id' => 'O1', 'wall' => 'W1', 'type' => 'window' }
        add.call(left, 'segment', 'W1', 'chain' => 'C1', 'order' => 0)
        add.call(wid, 'opening_width', 'O1', 'chain' => 'C1', 'order' => 1, 'confidence' => [wid['conf'], 0.6].min)
        add.call(right, 'segment', 'W1', 'chain' => 'C1', 'order' => 2)
        sum = left['mm'] + wid['mm'] + right['mm']
        toks.reject { |k| k['used'] }.each do |k|
          if (k['mm'] - sum).abs <= sum * 0.03 then add.call(k, 'wall_overall', 'W1')
          else
            # a value that does not fit the chain is shown to the user (which wall / what it is) instead of being dropped or forced
            add.call(k, 'wall_overall', nil)
            amb << "#{k['text']} does not equal the chain #{left['text']} + #{wid['text']} + #{right['text']} = #{(sum / RoomReader.factor(gu)).round}: say what it measures"
          end
        end
        amb << 'the opening height and its sill are not written on the picture: type them'
      else
        # no opening found: every value is a wall length, in picture order; the user confirms each one
        toks.sort_by { |k| k['cx'] }.each_with_index do |k, i|
          walls << { 'id' => "W#{i + 1}", 'label' => "wall #{i + 1}", 'angle_to_next' => 90, 'next' => nil }
          add.call(k, 'wall_overall', "W#{i + 1}", 'confidence' => [k['conf'], 0.7].min)
        end
        walls.each_cons(2) { |a, b| a['next'] = b['id'] }
        amb << 'no opening / ceiling relation found: each number was taken as the length of the wall at its place in the picture - confirm them'
      end
      { 'source' => 'LOCAL_OCR', 'engine' => o['engine'], 'view' => 'sketch', 'unit' => gu, 'type' => walls.size == 1 ? 'single_wall' : (walls.size == 2 ? 'L' : (walls.size == 3 ? 'U' : 'irregular')),
        'walls' => walls, 'openings' => ops, 'dimensions' => dims, 'ambiguities' => amb,
        'tokens' => toks.map { |k| k.slice('text', 'mm', 'conf', 'cx', 'cy', 'raw', 'pass').compact } }
    end

    # picture -> the normalised read used by AssistantVision.apply (same shape as an AI provider answer)
    def analyze(path)
      o = ocr(path)
      return { 'ok' => false, 'message' => o['error'] || 'LOCAL_OCR_FAILED' } unless o['ok']

      room = interpret(o)
      return { 'ok' => false, 'message' => 'INSUFFICIENT DIMENSIONAL EVIDENCE: no number could be read on the picture by the local text recognition. Type the room dimensions, add an AI provider, or mark the room by hand (fallback).' } if room['dimensions'].empty?

      { 'ok' => true, 'local' => true,
        'read' => { 'unit' => room['unit'].to_s, 'problems' => [], 'mock' => false, 'local' => true, 'design' => nil,
                    'site' => { 'view' => 'room', 'room' => room, 'openings' => [], 'services' => [], 'written' => room['tokens'].map { |k| k['text'] },
                                'notes' => ['read on this computer with the Windows text recognition - no AI provider'] + room['ambiguities'] } } }
    end
  end
end
