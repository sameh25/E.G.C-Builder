# frozen_string_literal: true

require 'json'

module EGC
  # Permanent unit IDs U01, U02 ... A unit keeps its ID for life (resize, replace, edit, mirror, move): the ID is stored on the unit AND in its build spec,
  # so every rebuild reuses it. Only a unit that has no U-ID yet gets one: the next free number, floor units (base / tall) first in layout order
  # (run A, B, C; left to right), then the wall units in the same order. Unit type is a separate attribute: B = base, W = wall (and hood), T = tall.
  # The two modules of a split tall unit share one number: U05L (lower) and U05U (upper). Board IDs follow: P-U04-001, P-U04-002 ...
  module Numbering
    module_function

    ATTR = 'egc'
    TYPE = { 'base' => 'B', 'wall' => 'W', 'hood' => 'W', 'tall' => 'T' }.freeze
    UID = /\AU(\d{2,})([LU])?\z/.freeze
    GENERATED = /\A([A-Z])_(\d+)_/.freeze

    def cabs(list, acc = [])
      list.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)

        if e.get_attribute(ATTR, 'cab')
          acc << e
        elsif e.is_a?(Sketchup::Group)
          cabs(e.entities.to_a, acc)
        end
      end
      acc
    end

    def units(model)
      cabs(model.entities.to_a).select { |g| TYPE.key?(g.get_attribute(ATTR, 'kind').to_s) }
    end

    def tier_rank(name)
      return 9 if name.end_with?('_over')

      name[/_W(\d)\z/, 1].to_i
    end

    def order_key(g)
      floor = %w[base tall].include?(g.get_attribute(ATTR, 'kind').to_s) ? 0 : 1
      m = g.name.to_s.match(GENERATED)
      x = (g.bounds.min.x.to_mm rescue 0.0)
      m ? [floor, 0, m[1], m[2].to_i, tier_rank(g.name.to_s.sub(/_U\z/, '')), x] : [floor, 1, 'Z', 0, 0, x]
    end

    # { group => new code } for every unit that has no U-ID yet
    def plan(model)
      all = units(model)
      used = all.map { |g| g.get_attribute(ATTR, 'code').to_s[UID, 1] }.compact.map(&:to_i)
      nxt = (used.max || 0)
      shared = {}
      out = {}
      all.reject { |g| g.get_attribute(ATTR, 'code').to_s =~ UID }.sort_by { |g| order_key(g) }.each do |g|
        asm = g.get_attribute(ATTR, 'tall_assembly').to_s
        if asm.empty?
          out[g] = format('U%02d', nxt += 1)
        else
          sib = all.find { |o| !o.equal?(g) && o.get_attribute(ATTR, 'tall_assembly').to_s == asm && o.get_attribute(ATTR, 'code').to_s =~ UID }
          base = shared[asm] ||= (sib ? sib.get_attribute(ATTR, 'code').to_s.sub(/[LU]\z/, '') : format('U%02d', nxt += 1))
          out[g] = base + (g.get_attribute(ATTR, 'code').to_s.end_with?('U') || g.name.to_s.end_with?('_U') ? 'U' : 'L')
        end
      end
      out
    end

    def retag_parts(ents, old, new)
      ents.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)

        if e.get_attribute(ATTR, 'code').to_s == old
          e.set_attribute(ATTR, 'code', new)
          pid = e.get_attribute(ATTR, 'pid').to_s
          e.set_attribute(ATTR, 'pid', "P-#{new}-#{pid[("P-#{old}-").length..]}") if pid.start_with?("P-#{old}-")
        end
        retag_parts(e.is_a?(Sketchup::Group) ? e.entities.to_a : e.definition.entities.to_a, old, new) unless e.get_attribute(ATTR, 'cab')
      end
    end

    def set_code(g, code)
      old = g.get_attribute(ATTR, 'code').to_s
      g.set_attribute(ATTR, 'code', code)
      g.set_attribute(ATTR, 'unit_type', TYPE[g.get_attribute(ATTR, 'kind').to_s])
      sp = (JSON.parse(g.get_attribute(ATTR, 'spec').to_s) rescue nil)
      if sp.is_a?(Hash)
        sp['code'] = code
        g.set_attribute(ATTR, 'spec', JSON.generate(sp))
      end
      unless g.get_attribute(ATTR, 'tall_assembly').to_s.empty?
        base = code.sub(/[LU]\z/, '')
        g.set_attribute(ATTR, 'tall_assembly', base)
        g.set_attribute(ATTR, 'tall_lower', "#{base}L")
        g.set_attribute(ATTR, 'tall_upper', "#{base}U")
      end
      retag_parts(g.entities.to_a, old, code) if g.respond_to?(:entities)
    end

    # gives a U-ID to every unit that has none. Returns how many units were numbered. Units that already have one are never touched.
    def apply(model = Sketchup.active_model, own_op: false)
      map = plan(model)
      units(model).each { |g| g.set_attribute(ATTR, 'unit_type', TYPE[g.get_attribute(ATTR, 'kind').to_s]) unless g.get_attribute(ATTR, 'unit_type') }
      return 0 if map.empty?

      model.start_operation('E.G.C unit IDs', true) if own_op
      map.each { |g, code| set_code(g, code) }
      model.commit_operation if own_op
      map.size
    end

    def plan_next(model)
      format('U%02d', (units(model).map { |g| g.get_attribute(ATTR, 'code').to_s[UID, 1] }.compact.map(&:to_i).max || 0) + 1)
    end

    # boards of a unit in build order: [[part name, occurrence], group]
    def part_list(g, acc = [])
      (g.is_a?(Sketchup::Group) ? g.entities : g.definition.entities).each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)

        if e.get_attribute(ATTR, 'pid')
          acc << e
        elsif !e.get_attribute(ATTR, 'cab')
          part_list(e, acc)
        end
      end
      acc
    end

    def keyed(list)
      seen = Hash.new(0)
      list.map { |e| k = [e.get_attribute(ATTR, 'part').to_s, e.get_attribute(ATTR, 'role').to_s]; [[*k, seen[k] += 1], e] }
    end

    def part_keys(g)
      keyed(part_list(g)).to_h { |k, e| [k, e.get_attribute(ATTR, 'pid').to_s] }
    end

    # after a rebuild: a board of the same kind (part name + role + occurrence) keeps its old Part ID; added boards continue after the highest number
    def keep_part_ids(old, ng)
      return if old.nil? || old.empty?

      code = ng.get_attribute(ATTR, 'code').to_s
      num = ->(pid) { pid.to_s[/-(\d+)\z/, 1].to_i }
      top = old.values.map { |p| num.call(p) }.max || 0
      keyed(part_list(ng)).each do |k, e|
        pid = old[k]
        pid = format('P-%s-%03d', code, top += 1) if pid.nil? || pid.empty?
        e.set_attribute(ATTR, 'pid', pid)
      end
    end

    def stale?(model = Sketchup.active_model)
      units(model).any? { |g| g.get_attribute(ATTR, 'code').to_s !~ UID }
    end

    # "U4", "u04", "unit 4", "Unit 04", "الوحدة 4", "وحدة ٤" -> "U04"
    def resolve(text)
      t = text.to_s.tr('٠١٢٣٤٥٦٧٨٩', '0123456789')
      n = t[/\bU\s*0*(\d+)\b/i, 1] || t[/\bunit\s*(?:no\.?\s*)?0*(\d+)/i, 1] || t[/(?:الوحدة|وحدة|الوحده|وحده)\s*(?:رقم\s*)?0*(\d+)/, 1]
      n && format('U%02d', n.to_i)
    end

    def find(model, code)
      units(model).find { |g| g.get_attribute(ATTR, 'code').to_s.sub(/[LU]\z/, '') == code.to_s }
    end
  end
end
