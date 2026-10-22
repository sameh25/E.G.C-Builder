# frozen_string_literal: true

module EGC
  # Self-contained QR Code generator (ISO/IEC 18004, byte mode, error correction level L, versions 1-15 = up to 520 bytes). No gems, no tools,
  # no network. QR.matrix(text) -> array of rows of booleans (true = dark); QR.svg(text) -> an <svg> element.
  module QR
    module_function

    # version => [error-correction codewords per block, [[blocks, data codewords per block], ...]]   (level L)
    BLOCKS = {
      1 => [7, [[1, 19]]], 2 => [10, [[1, 34]]], 3 => [15, [[1, 55]]], 4 => [20, [[1, 80]]], 5 => [26, [[1, 108]]],
      6 => [18, [[2, 68]]], 7 => [20, [[2, 78]]], 8 => [24, [[2, 97]]], 9 => [30, [[2, 116]]], 10 => [18, [[2, 68], [2, 69]]],
      11 => [20, [[4, 81]]], 12 => [24, [[2, 92], [2, 93]]], 13 => [26, [[4, 107]]], 14 => [30, [[3, 115], [1, 116]]], 15 => [22, [[5, 87], [1, 88]]]
    }.freeze
    ALIGN = { 1 => [], 2 => [6, 18], 3 => [6, 22], 4 => [6, 26], 5 => [6, 30], 6 => [6, 34], 7 => [6, 22, 38], 8 => [6, 24, 42], 9 => [6, 26, 46],
              10 => [6, 28, 50], 11 => [6, 30, 54], 12 => [6, 32, 58], 13 => [6, 34, 62], 14 => [6, 26, 46, 66], 15 => [6, 26, 48, 70] }.freeze

    EXP = Array.new(512, 0)
    LOG = Array.new(256, 0)
    x = 1
    255.times do |i|
      EXP[i] = x
      LOG[x] = i
      x <<= 1
      x ^= 0x11d if x > 255
    end
    (255...512).each { |i| EXP[i] = EXP[i - 255] }

    class TooLong < StandardError; end

    def gmul(a, b)
      a.zero? || b.zero? ? 0 : EXP[LOG[a] + LOG[b]]
    end

    def generator(n)
      g = [1]
      n.times do |i|
        nx = Array.new(g.size + 1, 0)
        g.each_with_index do |c, j|
          nx[j] ^= c
          nx[j + 1] ^= gmul(c, EXP[i])
        end
        g = nx
      end
      g
    end

    def ec_bytes(data, n)
      gen = generator(n)
      rem = Array.new(n, 0)
      data.each do |b|
        f = b ^ rem.shift
        rem << 0
        gen[1..].each_with_index { |c, i| rem[i] ^= gmul(c, f) }
      end
      rem
    end

    def data_capacity(v)
      BLOCKS[v][1].sum { |n, k| n * k }
    end

    def version_for(len)
      (1..15).find { |v| 4 + (v < 10 ? 8 : 16) + 8 * len <= data_capacity(v) * 8 } || raise(TooLong, "QR payload of #{len} bytes exceeds 520 bytes")
    end

    def codewords(bytes, v)
      bits = [0, 1, 0, 0]
      cc = v < 10 ? 8 : 16
      (cc - 1).downto(0) { |i| bits << ((bytes.size >> i) & 1) }
      bytes.each { |b| 7.downto(0) { |i| bits << ((b >> i) & 1) } }
      cap = data_capacity(v) * 8
      [4, cap - bits.size].min.times { bits << 0 }
      bits << 0 while bits.size % 8 != 0
      data = bits.each_slice(8).map { |s| s.join.to_i(2) }
      pad = [0xEC, 0x11].cycle
      data << pad.next while data.size < cap / 8
      ecn, groups = BLOCKS[v]
      blocks = []
      pos = 0
      groups.each { |n, k| n.times { blocks << data[pos, k]; pos += k } }
      ecs = blocks.map { |b| ec_bytes(b, ecn) }
      out = []
      blocks.map(&:size).max.times { |i| blocks.each { |b| out << b[i] if i < b.size } }
      ecn.times { |i| ecs.each { |e| out << e[i] } }
      out
    end

    def matrix(text, mask = 0)
      bytes = text.to_s.encode('UTF-8').bytes
      v = version_for(bytes.size)
      size = 17 + 4 * v
      m = Array.new(size) { Array.new(size, false) }
      fn = Array.new(size) { Array.new(size, false) }
      set = lambda do |cx, cy, dark|
        m[cy][cx] = dark
        fn[cy][cx] = true
      end
      finder = lambda do |cx, cy|
        (-4..4).each do |dy|
          (-4..4).each do |dx|
            xx = cx + dx
            yy = cy + dy
            next unless xx.between?(0, size - 1) && yy.between?(0, size - 1)

            dist = [dx.abs, dy.abs].max
            set.call(xx, yy, dist != 2 && dist != 4)
          end
        end
      end
      size.times do |i|
        set.call(6, i, i.even?)
        set.call(i, 6, i.even?)
      end
      finder.call(3, 3)
      finder.call(size - 4, 3)
      finder.call(3, size - 4)
      al = ALIGN[v]
      al.each do |ay|
        al.each do |ax|
          next if (ax == 6 && ay == 6) || (ax == 6 && ay == al.last) || (ax == al.last && ay == 6)

          (-2..2).each { |dy| (-2..2).each { |dx| set.call(ax + dx, ay + dy, [dx.abs, dy.abs].max != 1) } }
        end
      end
      # format information (level L = 01, mask), BCH(15,5)
      d = (1 << 3) | mask
      rem = d
      10.times { rem = (rem << 1) ^ ((rem >> 9) * 0x537) }
      fbits = ((d << 10) | rem) ^ 0x5412
      fb = ->(i) { (fbits >> i) & 1 == 1 }
      (0..5).each { |i| set.call(8, i, fb.call(i)) }
      set.call(8, 7, fb.call(6))
      set.call(8, 8, fb.call(7))
      set.call(7, 8, fb.call(8))
      (9...15).each { |i| set.call(14 - i, 8, fb.call(i)) }
      (0...8).each { |i| set.call(size - 1 - i, 8, fb.call(i)) }
      (8...15).each { |i| set.call(8, size - 15 + i, fb.call(i)) }
      set.call(8, size - 8, true)
      if v >= 7
        rem = v
        12.times { rem = (rem << 1) ^ ((rem >> 11) * 0x1F25) }
        vbits = (v << 12) | rem
        18.times do |i|
          bit = (vbits >> i) & 1 == 1
          a = size - 11 + i % 3
          b = i / 3
          set.call(a, b, bit)
          set.call(b, a, bit)
        end
      end
      cw = codewords(bytes, v)
      total = cw.size * 8
      i = 0
      right = size - 1
      while right >= 1
        right = 5 if right == 6
        size.times do |vert|
          2.times do |j|
            xx = right - j
            upward = ((right + 1) & 2).zero?
            yy = upward ? size - 1 - vert : vert
            next if fn[yy][xx]

            bit = i < total ? (cw[i >> 3] >> (7 - (i & 7))) & 1 == 1 : false
            i += 1
            inv = case mask
                  when 0 then (xx + yy).even?
                  when 1 then yy.even?
                  when 2 then (xx % 3).zero?
                  else ((xx + yy) % 3).zero?
                  end
            m[yy][xx] = bit ^ inv
          end
        end
        right -= 2
      end
      m
    end

    # <svg> of the code; px = rendered size in CSS units, 4 quiet modules on every side
    def svg(text, px = '26mm')
      m = matrix(text)
      n = m.size
      d = +''
      m.each_with_index do |row, y|
        x = 0
        while x < n
          if row[x]
            x0 = x
            x += 1 while x < n && row[x]
            d << "M#{x0 + 4} #{y + 4}h#{x - x0}v1h-#{x - x0}z"
          else
            x += 1
          end
        end
      end
      "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 #{n + 8} #{n + 8}' width='#{px}' height='#{px}' shape-rendering='crispEdges'><rect width='100%' height='100%' fill='#fff'/><path d='#{d}' fill='#000'/></svg>"
    end
  end
end
