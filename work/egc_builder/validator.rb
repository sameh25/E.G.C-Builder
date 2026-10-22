# frozen_string_literal: true

require 'json'

module EGC
  # GENERATION COMPLETENESS VALIDATOR (diagnostics / tests - never runs during normal production)
  #
  # Compares what a generated unit SHOULD contain (from its own stored spec) with what is really in the model, part by part:
  # mandatory boards, fronts, plinth / legs, non-zero sizes, parts inside the unit's own bounds, nothing hidden, every moving assembly in its
  # CLOSED (rest) state, no part rotated out of the unit's axes. Also builds a position-independent FINGERPRINT of a kitchen so the same design
  # generated at the origin, away from it, at negative coordinates or rotated can be proven identical.
  module Validate
    module_function

    EPS = 0.35 # mm
    Problem = Struct.new(:cab, :type, :expected, :actual, :part, :transform, :position) do
      def to_s
        "CABINET: #{cab} TYPE: #{type} EXPECTED PART: #{expected} ACTUAL: #{actual} PART: #{part} TRANSFORM: #{transform} POSITION: #{position}"
      end
    end

    # every part / hardware / appliance group of a unit with its box in the unit's own frame (mm)
    def parts_of(u)
      inv = u.tr.inverse
      acc = []
      walk = lambda do |g, tr, asm|
        (g.is_a?(Sketchup::Group) ? g.entities : g.definition.entities).each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)

          t = tr * e.transformation
          d = e.attribute_dictionary('egc')
          role = d && d['role'].to_s
          if d && %w[part hw glass appliance].include?(role)
            lb = e.respond_to?(:local_bounds) ? e.local_bounds : e.definition.bounds
            pts = [lb.min.x, lb.max.x].product([lb.min.y, lb.max.y], [lb.min.z, lb.max.z]).map { |x, y, z| inv * (t * Geom::Point3d.new(x, y, z)) }
            acc << { e: e, part: d['part'].to_s, role: role, mat: d['mat'], t: t, asm: asm, d: d,
                     x: pts.map { |p| p.x.to_mm }.minmax, y: pts.map { |p| p.y.to_mm }.minmax, z: pts.map { |p| p.z.to_mm }.minmax }
          end
          walk.call(e, t, asm || (d && d['move'] ? e : nil)) unless d && %w[part glass appliance].include?(role)
        end
      end
      walk.call(u.g, u.tr, nil)
      acc
    end

    def moving_groups(u)
      out = []
      walk = lambda do |g|
        (g.is_a?(Sketchup::Group) ? g.entities : g.definition.entities).each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)

          out << e if e.get_attribute('egc', 'move')
          walk.call(e)
        end
      end
      walk.call(u.g)
      out
    end

    def identity?(t)
      a = t.to_a
      id = Geom::Transformation.new.to_a
      a.each_with_index.all? { |v, i| (v - id[i]).abs < 1e-6 }
    end

    # -> [Problem]
    def unit(u, tol: 12.0)
      spec = Cabinet.spec_from_json(u.g.get_attribute('egc', 'spec'))
      kind = u.kind
      type = spec[:type].to_s
      ps = parts_of(u)
      names = ps.map { |p| p[:part] }
      out = []
      pos = u.tr.origin.to_a.map { |v| v.to_mm.round(1) }.inspect
      add = lambda { |expected, actual, part = nil, tr = nil| out << Problem.new(u.g.name, "#{kind}/#{type}", expected, actual, part, tr, pos) }
      corner = type == 'corner_l' # L-shaped corner unit: back x2, side_r, side_f, L-shaped bottom / top (corner.rb)
      need = corner ? %w[back side_r side_f] : %w[side_l side_r back]
      need.delete('back') if spec[:no_back]
      need << 'bottom' unless kind == 'hood' || spec[:mech].to_s == 'DISH_RACK_FLAP' || spec[:custom_bottom] || spec[:no_bottom]
      if corner
        need << 'top'
      elsif kind == 'base'
        need += %w[top_rail_f top_rail_b]
      elsif %w[wall tall hood].include?(kind)
        need << 'top'
      end
      need << 'plinth' if %w[base tall].include?(kind) && spec[:plinth].to_f > 0 && !spec[:floor]
      need.each { |n| add.call(n, 'MISSING') unless names.include?(n) }
      # fronts
      unless spec[:mech]
        Array(spec[:cells]).each do |c|
          case c[:t].to_s
          when 'drawers'
            n = (c[:n] || 1).to_i
            k = names.count('drawer_front')
            add.call("#{n} drawer_front (cell)", "unit has #{k} drawer fronts in total") if k < n
          when 'doors', 'flap'
            add.call('door / flap front', 'MISSING') unless (names & %w[door flap]).any?
          end
        end
      end
      ps.each do |p|
        sx = p[:x][1] - p[:x][0]
        sy = p[:y][1] - p[:y][0]
        sz = p[:z][1] - p[:z][0]
        if p[:role] == 'part' && [sx, sy, sz].min < EPS
          add.call("#{p[:part]} non-zero size", "ZERO-SIZE #{sx.round(2)}x#{sy.round(2)}x#{sz.round(2)}", p[:part])
        end
        overhang = %w[countertop splash upstand].include?(p[:part]) || corner # worktop overhangs the fronts; the L corner is wider than its nominal frame
        if p[:role] == 'part' && !overhang && (p[:x][0] < -EPS || p[:x][1] > u.w + EPS || p[:z][0] < -EPS || p[:z][1] > u.h + EPS || p[:y][0] < -u.d - tol || p[:y][1] > EPS)
          add.call("#{p[:part]} inside unit bounds", "PART OUTSIDE CABINET EXPECTED BOUNDS x#{p[:x].map(&:round)} y#{p[:y].map(&:round)} z#{p[:z].map(&:round)}", p[:part])
        end
        add.call("#{p[:part]} visible", 'HIDDEN', p[:part]) if p[:role] == 'part' && (p[:e].hidden? || !p[:e].layer.visible?)
        if p[:role] == 'part' && !p[:asm]
          rel = u.tr.inverse * p[:t]
          ax = rel.xaxis
          ay = rel.yaxis
          az = rel.zaxis
          unless (ax.x - 1).abs < 1e-6 && (ay.y - 1).abs < 1e-6 && (az.z - 1).abs < 1e-6
            add.call("#{p[:part]} axis-aligned with unit", 'ROTATED / INVALID TRANSFORM', p[:part], rel.to_a.map { |v| v.round(3) }.inspect)
          end
        end
      end
      moving_groups(u).each do |g|
        add.call("#{g.name} closed (rest state)", 'OPEN / MOVED', g.name, g.transformation.to_a.map { |v| v.round(3) }.inspect) unless identity?(g.transformation)
      end
      out
    end

    # -> { units: n, problems: [Problem], per_unit: { name => [Problem] } }
    def model(m = Sketchup.active_model, only: nil)
      us = Exposure.collect(m)[:units]
      us = us.select { |u| only.include?(u.g.persistent_id) } if only
      per = {}
      us.each { |u| per[u.g.name] = unit(u) }
      { units: us.size, problems: per.values.flatten, per_unit: per }
    end

    # Position independent description of a kitchen (units + parts + production numbers), relative to the kitchen root, so a translated /
    # rotated copy of the same design gives the identical hash.
    def fingerprint(root, m = Sketchup.active_model)
      rinv = root.transformation.inverse
      us = Exposure.collect(m)[:units].select { |u| nested?(u.g, root) }
      units = us.map do |u|
        rel = rinv * u.tr
        parts = parts_of(u).map do |p|
          [p[:part], p[:role], p[:mat], p[:d]['len'], p[:d]['wid'], p[:d]['thk'], p[:d]['eb_l'], p[:d]['eb_w'], p[:d]['groove'], p[:d]['pid'],
           p[:x].map { |v| v.round(1) }, p[:y].map { |v| v.round(1) }, p[:z].map { |v| v.round(1) }]
        end.sort_by(&:to_s)
        o = rel.origin
        ang = (Math.atan2(rel.xaxis.y, rel.xaxis.x) * 180 / Math::PI).round(1)
        d = u.g.attribute_dictionary('egc')
        { 'name' => u.g.name, 'kind' => u.kind, 'w' => u.w, 'd' => u.d, 'h' => u.h, 'at' => [o.x.to_mm.round(1), o.y.to_mm.round(1), o.z.to_mm.round(1), ang],
          'hw' => d['hw'], 'led' => d['led'], 'exp' => d['exp'], 'parts' => parts }
      end.sort_by { |x| x['name'] }
      { 'units' => units, 'unit_count' => units.size, 'part_count' => EGC::Num.sum(units) { |x| x['parts'].size } }
    end

    def nested?(g, root)
      p = g.parent
      while p.respond_to?(:instances) && (inst = p.instances.first)
        return true if inst == root

        p = inst.parent
      end
      false
    end
  end
end
