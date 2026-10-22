# frozen_string_literal: true

module EGC
  # Geometric interference check between UNITS (right-click > E.G.C Builder > Check interference). Every tagged part is taken on its true
  # plan outline (so fronts that stand open at an angle are not blown up to a box) with its height range. Checked: everything closed, then
  # each checked unit on its way open (25 / 50 / 75 %) and fully open, the others closed. NOT checked: parts of one unit against each other. The model is left exactly as it was (the opening is done inside an operation that is rolled back).
  module Interference
    module_function

    SHRINK = 1.0 # mm: parts that only touch are not a clash
    OPEN_STEPS = [0.25, 0.5, 0.75, 1.0].freeze

    def parts(g)
      out = []
      walk = lambda do |e, tr|
        t = tr * e.transformation
        nm = e.get_attribute('egc', 'part')
        if nm
          dfn = e.is_a?(Sketchup::Group) ? e.entities.parent : e.definition
          ps = (0..7).map { |k| dfn.bounds.corner(k).transform(t) }
          hull = hull_of(ps.map { |p| [p.x.to_mm.round(2), p.y.to_mm.round(2)] })
          out << { n: nm.to_s, poly: hull, z0: ps.map { |p| p.z.to_mm }.min, z1: ps.map { |p| p.z.to_mm }.max } if hull.size >= 3
        elsif e.is_a?(Sketchup::Group)
          e.entities.each { |k| walk.call(k, t) if k.is_a?(Sketchup::Group) || k.is_a?(Sketchup::ComponentInstance) }
        end
      end
      walk.call(g, parent_tr(g))
      out
    end

    def parent_tr(g)
      tr = Geom::Transformation.new
      p = g.parent
      while p.is_a?(Sketchup::ComponentDefinition) && (inst = p.instances.first)
        tr = inst.transformation * tr
        p = inst.parent
      end
      tr
    end

    def hull_of(pts)
      pts = pts.uniq.sort
      return pts if pts.size < 3

      cross = ->(o, a, b) { (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]) }
      lo = []
      pts.each do |p|
        lo.pop while lo.size >= 2 && cross.call(lo[-2], lo[-1], p) <= 0
        lo << p
      end
      up = []
      pts.reverse_each do |p|
        up.pop while up.size >= 2 && cross.call(up[-2], up[-1], p) <= 0
        up << p
      end
      h = lo[0...-1] + up[0...-1]
      cx = h.sum { |p| p[0] } / h.size
      cy = h.sum { |p| p[1] } / h.size
      h.map { |x, y| l = Math.hypot(x - cx, y - cy); l < SHRINK * 1.5 ? [x, y] : [x - (x - cx) / l * SHRINK, y - (y - cy) / l * SHRINK] }
    end

    def overlap?(p, q)
      return false if p[:z1] <= q[:z0] + SHRINK || q[:z1] <= p[:z0] + SHRINK
      return true if p[:poly].any? { |v| LemansKin.inside?(q[:poly], v) } || q[:poly].any? { |v| LemansKin.inside?(p[:poly], v) }

      o = ->(a, b, c) { (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) }
      p[:poly].each_index.any? do |i|
        a = p[:poly][i]
        b = p[:poly][(i + 1) % p[:poly].size]
        q[:poly].each_index.any? do |j|
          c = q[:poly][j]
          d = q[:poly][(j + 1) % q[:poly].size]
          (o.call(a, b, c) * o.call(a, b, d)).negative? && (o.call(c, d, a) * o.call(c, d, b)).negative?
        end
      end
    end

    def label(g)
      c = g.get_attribute('egc', 'code').to_s
      c.empty? ? g.name.to_s : c
    end

    def near?(a, b)
      ba = a.bounds
      bb = b.bounds
      pad = 1200.mm
      !(ba.max.x + pad < bb.min.x || bb.max.x + pad < ba.min.x || ba.max.y + pad < bb.min.y || bb.max.y + pad < ba.min.y)
    end

    # targets: units to check (nil = every unit). -> { checked:, others:, clashes: [{ a:, b:, part_a:, part_b:, state: }] }
    def check(targets = nil, model = Sketchup.active_model)
      all = Snap.standing_units(model).map { |u| u[:g] }.select { |g| g.get_attribute('egc', 'spec') }
      targets = (targets || all).select { |g| all.include?(g) }
      found = []
      seen = {}
      scan = lambda do |g, state|
        mine = parts(g)
        all.each do |o|
          next if o.equal?(g) || !near?(g, o)

          theirs = parts(o)
          mine.each do |p|
            theirs.each do |q|
              next unless overlap?(p, q)

              key = [[label(g), p[:n]], [label(o), q[:n]]].sort + [state == 'closed']
              if seen[key] # the same two parts at another opening: one line, every opening it happens at
                seen[key][:state] += " / #{state[/\d+%\z/] || '100%'}" unless seen[key][:state].end_with?(state[/\d+%\z/] || '100%') || state == 'closed'
                next
              end

              found << (seen[key] = { a: label(g), b: label(o), part_a: p[:n], part_b: q[:n], state: state.dup })
            end
          end
        end
      end
      targets.each { |g| scan.call(g, 'closed') }
      model.start_operation('E.G.C interference check', true)
      begin
        targets.each do |g|
          next if Mechanisms.collect([g]).empty?

          OPEN_STEPS.each do |u| # on the way open as well: a front can clear its neighbour fully open and still hit it half-way
            Mechanisms.set_state([g], u)
            scan.call(g, "#{label(g)} open#{u < 1.0 ? " #{(u * 100).round}%" : ''}")
          end
          Mechanisms.set_state([g], 0.0)
        end
      ensure
        model.abort_operation # nothing of the check stays in the model
      end
      { checked: targets.size, others: all.size, clashes: found }
    end

    def report(res, lang = 'en')
      ar = lang.to_s == 'ar'
      head = ar ? "فحص التداخل: #{res[:checked]} وحدة مقابل #{res[:others]} وحدة في الموديل" : "Interference check: #{res[:checked]} unit(s) against the #{res[:others]} unit(s) in the model"
      scope = ar ? 'تم الفحص: الكل مقفول، ثم كل وحدة وهي بتفتح (25 / 50 / 75٪) ومفتوحة على الآخر. لم يُفحص: أجزاء الوحدة مع نفسها.' : 'Checked: everything closed, then each unit on its way open (25 / 50 / 75 %) and fully open. Not checked: parts of one unit against each other.'
      return "#{head}\n\n#{ar ? 'لا يوجد تداخل.' : 'No interference found.'}\n\n#{scope}" if res[:clashes].empty?

      lines = res[:clashes].first(14).map { |c| "- #{c[:a]} #{c[:part_a]}  x  #{c[:b]} #{c[:part_b]}   (#{c[:state]})" }
      more = res[:clashes].size > 14 ? "\n... +#{res[:clashes].size - 14}" : ''
      "#{head}\n\n#{ar ? "تداخلات: #{res[:clashes].size}" : "Clashes: #{res[:clashes].size}"}\n#{lines.join("\n")}#{more}\n\n#{scope}"
    end
  end
end
