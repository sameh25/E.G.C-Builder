# frozen_string_literal: true

require 'json'

module EGC
  # EXPOSURE + LED RUNS
  #
  # A face the user can SEE (the end of a run, the underside of an upper unit) must not show carcass board: it takes the external
  # finish material (config 'ext_mat', default = the fronts' material). A face hidden by a neighbour stays carcass.
  #   Exposure.refresh   detects, from the real geometry, which sides / undersides of every E.G.C unit are covered by a neighbour
  #                      (unit, end panel, filler, appliance) and updates the affected PANELS in place (material key = cut list / nesting /
  #                      cost follow it). The user can override any face per unit: spec[:exp] = { l/r/b/t => 'auto'|'exposed'|'hidden' }.
  #   LedRun.detect      derives the LED runs (adjacent upper units whose grooves line up = ONE run) from the same geometry - never stored,
  #                      so it cannot go stale when units are added, resized, moved or deleted.
  # Finish is opt-in: sides add one decorative board each; underside/top replace the material of the existing board.
  module Exposure
    module_function

    TOL = 3.0      # mm: faces closer than this touch (an appliance slot leaves 2 mm each side: exactly 2.0 sat ON the old limit, so float noise decided it and the same kitchen flipped between positions)
    MIN_OV = 50.0  # mm: overlap needed for a neighbour to really cover a face

    Rec = Struct.new(:g, :tr, :w, :d, :h, :kind, :corners, :unit)

    def box_corners(tr, x0, x1, y0, y1, z0, z1)
      [x0, x1].product([y0, y1], [z0, z1]).map { |x, y, z| tr * Geom::Point3d.new(x.mm, y.mm, z.mm) }
    end

    def bounds_corners(e, t)
      lb = e.respond_to?(:local_bounds) ? e.local_bounds : e.definition.bounds
      [lb.min.x, lb.max.x].product([lb.min.y, lb.max.y], [lb.min.z, lb.max.z]).map { |x, y, z| t * Geom::Point3d.new(x, y, z) }
    end

    # -> { units: [Rec], blockers: [Rec] }  (every E.G.C unit / end panel / filler / appliance, in world space)
    def collect(model = Sketchup.active_model)
      return { units: [], blockers: [] } unless model
      acc = { units: [], blockers: [] }
      walk(model.entities.to_a, Geom::Transformation.new, acc)
      acc
    end

    def walk(list, tr, acc)
      list.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)

        t = tr * e.transformation
        d = e.attribute_dictionary('egc')
        if d && d['spec'] && d['cab']
          w = d['w'].to_f
          dd = d['d'].to_f
          h = d['h'].to_f
          acc[:units] << Rec.new(e, t, w, dd, h, d['kind'].to_s, box_corners(t, 0, w, -dd, 0, 0, h), true)
        elsif d && d['role'] == 'part' && %w[end_panel filler].include?(d['part'].to_s)
          acc[:blockers] << Rec.new(e, t, 0, 0, 0, 'panel', bounds_corners(e, t), false)
        elsif d && (d['device'] || d['role'] == 'appliance')
          acc[:blockers] << Rec.new(e, t, 0, 0, 0, 'device', bounds_corners(e, t), false)
        elsif !(d && d['role'])
          kids = e.is_a?(Sketchup::Group) ? e.entities.to_a : e.definition.entities.to_a
          walk(kids, t, acc)
        end
      end
    end

    def ov(a0, a1, b0, b1)
      [a1, b1].min - [a0, b0].max
    end

    # area (mm2) of the rectangle [a0,a1]x[b0,b1] NOT covered by any of `rects` ([a0,a1,b0,b1]); exact (coordinate compression, no sampling)
    def uncovered(a0, a1, b0, b1, rects)
      as = ([a0, a1] + rects.flat_map { |r| [r[0], r[1]] }).select { |v| v >= a0 && v <= a1 }.uniq.sort
      bs = ([b0, b1] + rects.flat_map { |r| [r[2], r[3]] }).select { |v| v >= b0 && v <= b1 }.uniq.sort
      free = 0.0
      as.each_cons(2) do |p, q|
        bs.each_cons(2) do |s, t|
          ma = (p + q) / 2.0
          mb = (s + t) / 2.0
          free += (q - p) * (t - s) unless rects.any? { |r| ma > r[0] && ma < r[1] && mb > r[2] && mb < r[3] }
        end
      end
      free
    end

    # Which faces of `u` can the user SEE? A face is visible when a real patch of it (>= MIN_OV x MIN_OV mm) is not covered by a neighbour:
    # a deeper unit above a shallower one leaves its front strip visible, a shallower one leaves the front of the deeper neighbour's side visible.
    # -> { 'l'=>, 'r'=>, 'b'=> (underside FULLY free: a groove position is visible), 'bv'=> (any visible patch of the underside: external finish) }
    def auto_for(u, others)
      inv = u.tr.inverse
      cov = { 'l' => [], 'r' => [], 'b' => [] }
      others.each do |b|
        next if b.g.equal?(u.g)

        pts = b.corners.map { |p| inv * p }
        x0, x1 = pts.map { |p| p.x.to_mm.round(2) }.minmax
        y0, y1 = pts.map { |p| p.y.to_mm.round(2) }.minmax
        z0, z1 = pts.map { |p| p.z.to_mm.round(2) }.minmax
        yov = ov(-u.d, 0.0, y0, y1)
        zov = ov(0.0, u.h, z0, z1)
        xov = ov(0.0, u.w, x0, x1)
        cov['l'] << [y0, y1, z0, z1] if x1.abs <= TOL && x0 < -10 && yov > MIN_OV && zov > MIN_OV
        cov['r'] << [y0, y1, z0, z1] if (x0 - u.w).abs <= TOL && x1 > u.w + 10 && yov > MIN_OV && zov > MIN_OV
        cov['b'] << [x0, x1, y0, y1] if z1.abs <= TOL && z0 < -10 && xov > MIN_OV && yov > MIN_OV
      end
      min_area = MIN_OV * MIN_OV
      out = {}
      %w[l r].each { |s| out[s] = cov[s].empty? || uncovered(-u.d, 0.0, 0.0, u.h, cov[s]) >= min_area }
      free = cov['b'].empty? ? u.w * u.d : uncovered(0.0, u.w, -u.d, 0.0, cov['b'])
      out['b'] = free >= 0.98 * u.w * u.d
      out['bv'] = free >= min_area
      out
    end

    def hget(h, k)
      h.is_a?(Hash) ? (h.key?(k.to_sym) ? h[k.to_sym] : h[k.to_s]) : nil   # false must survive (never use ||)
    end

    # effective exposure of one face: override > automatic > default
    def effective(spec, side, auto)
      if side.to_sym == :bv # visible patch of the underside (external finish): follows the underside override, else the geometry, else the underside itself
        ov = hget(spec[:exp], :b).to_s
        return true if ov == 'exposed'
        return false if ov == 'hidden'

        a = auto && auto['bv']
        return a.nil? ? effective(spec, :b, auto) : (a || effective(spec, :b, auto))
      end
      ov = hget(spec[:exp], side).to_s
      return true if ov == 'exposed'
      return false if ov == 'hidden'

      a = auto && auto[side.to_s]
      a.nil? ? Cabinet::EXPOSE_DEFAULT[side.to_sym] : a
    end

    # ---- units standing INSIDE each other (a kitchen generated twice on the same spot, a unit dragged onto another): two boards in one place is
    # never manufacturable and doubles every quantity. Reported as OVERLAPPING_UNITS; exports are refused until it is resolved.
    OVERLAP_MIN = 5.0 # mm of interpenetration on every axis (touching / 2 mm tolerance never counts)

    def overlaps(model = Sketchup.active_model, only: nil)
      us = collect(model)[:units]
      us = us.select { |u| only.include?(u.g.persistent_id) } if only
      wb = us.map { |u| u.corners.map { |p| [p.x, p.y, p.z] }.transpose.map(&:minmax) }
      out = []
      us.each_with_index do |a, i|
        inv = nil
        ((i + 1)...us.size).each do |j|
          bb = wb[j]
          ab = wb[i]
          next if (0..2).any? { |k| [ab[k][1], bb[k][1]].min - [ab[k][0], bb[k][0]].max <= OVERLAP_MIN.mm }

          inv ||= a.tr.inverse
          b = us[j]
          pts = b.corners.map { |p| inv * p }
          x0, x1 = pts.map { |p| p.x.to_mm }.minmax
          y0, y1 = pts.map { |p| p.y.to_mm }.minmax
          z0, z1 = pts.map { |p| p.z.to_mm }.minmax
          ox = ov(0.0, a.w, x0, x1)
          oy = ov(-a.d, 0.0, y0, y1)
          oz = ov(0.0, a.h, z0, z1)
          next unless ox > OVERLAP_MIN && oy > OVERLAP_MIN && oz > OVERLAP_MIN

          out << { pid: a.g.persistent_id, part: 'unit', cab: a.g.name, code: 'OVERLAPPING_UNITS',
                   detail: "stands inside #{b.g.name} (#{ox.round}x#{oy.round}x#{oz.round} mm overlap)" }
        end
      end
      out
    end

    # What has to change on one unit, or nil when it is already right. Cheap on purpose (runs for every unit on every refresh): the spec JSON is
    # only parsed when the unit carries a user override; everything else comes from the unit's own attributes and part attributes.
    def plan(u, auto, cfg)
      d = u.g.attribute_dictionary('egc')
      kind = d['kind'].to_s
      return nil unless %w[wall base tall hood].include?(kind)

      raw = d['spec'].to_s
      ov = raw.include?('"exp":') ? Cabinet.spec_from_json(raw)[:exp] : nil
      spec = { exp: ov }
      ext = (cfg['ext_mat'] || 'front').to_s
      eff = %i[l r b bv t].to_h { |s| [s, effective(spec, s, auto)] }
      want = {}
      if kind == 'wall'
        want['bottom'] = hget(spec[:exp], :b).to_s == 'exposed' ? ext : 'carcass'
        want['top'] = hget(spec[:exp], :t).to_s == 'exposed' ? ext : 'carcass'
      end
      # a side the user marked as exposed is cut from the finish board itself
      want['side_l'] = hget(spec[:exp], :l).to_s == 'exposed' ? ext : 'carcass'
      want['side_r'] = hget(spec[:exp], :r).to_s == 'exposed' ? ext : 'carcass'
      ends = [eff[:l], eff[:r]].count(true)
      changes = []
      u.g.entities.each do |p|
        next unless p.is_a?(Sketchup::Group) && p.get_attribute('egc', 'role') == 'part'

        part = p.get_attribute('egc', 'part')
        next unless want.key?(part)

        ch = {}
        ch[:mat] = want[part] if p.get_attribute('egc', 'mat') != want[part]
        ch[:eb_w] = ends if part == 'bottom' && kind == 'wall' && p.get_attribute('egc', 'eb_w').to_i != ends
        changes << ch.merge(ent: p) unless ch.empty?
      end
      # The LED groove is GEOMETRY: a wall unit whose underside is hidden has no groove (nor LED data / CNC), one whose underside became
      # visible gets it -> rebuilt from its own spec when the visibility differs from what it was built with.
      led_capable = kind == 'wall' && raw =~ /"led_off":[0-9]/ && cfg['led'] && !raw.include?('DISH_RACK_FLAP') && !raw.include?('"no_bottom":true')
      # the groove no longer depends on visibility (standard: every tier is grooved); a unit built before 1.16 without it is rebuilt once from its own spec
      led_rebuild = led_capable && d['led'].nil? && !raw.include?('"notch"') && !raw.include?('"corner":true') # the L corner unit has its own builder and no groove data: rebuilding it on every pass only lost the selection
      # Decorative panels are opt-in. Count actual panels to migrate old automatic panels and duplicates.
      expected = 0 # cladding panels of earlier versions are removed: the unit is rebuilt once with finished sides instead
      actual = u.g.entities.grep(Sketchup::Group).count do |p|
        p.get_attribute('egc', 'role') == 'part' && p.get_attribute('egc', 'part') == 'end_panel'
      end
      sides_changed = actual != expected && !raw.include?('"corner":true') # L-corner has its own carcass builder (no rectangular side-finish panels).
      rebuild = led_rebuild || sides_changed
      return nil if changes.empty? && !rebuild # nothing to change: do not rewrite the spec of every unit on every refresh

      { unit: u, pid: u.g.persistent_id, changes: changes, auto: auto, eff: eff, rebuild: rebuild }
    end

    def apply(pl, cfg)
      g = pl[:unit].g
      spec = Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))
      spec[:exp_auto] = pl[:auto]
      g.set_attribute('egc', 'spec', JSON.generate(spec))
      return if pl[:rebuild] # geometry differs (LED groove): the unit is rebuilt from this spec right after

      pl[:changes].each do |c|
        p = c[:ent]
        next unless p.valid?

        if c[:mat]
          p.set_attribute('egc', 'mat', c[:mat])
          ucfg = spec[:mats].is_a?(Hash) && !spec[:mats].empty? ? cfg.merge('unit_mats' => spec[:mats].to_h { |k, v| [k.to_s, v.to_s] }) : cfg
          p.material = Geo.material_for(c[:mat], ucfg, p.get_attribute('egc', 'turned'))
          (code = Geo.unit_code(c[:mat], ucfg)) ? p.set_attribute('egc', 'mat_code', code) : p.delete_attribute('egc', 'mat_code')
          begin
            p.layer = Geo.tag(Panel.tag_for(p.get_attribute('egc', 'role'), c[:mat]))
          rescue StandardError
            nil
          end
        end
        p.set_attribute('egc', 'eb_w', c[:eb_w]) if c[:eb_w]
      end
      g.set_attribute('egc', 'exp', JSON.generate(pl[:eff].transform_keys(&:to_s)))
    end

    def apply_all(plans, cfg, model)
      plans.each { |pl| apply(pl, cfg) }
      # a rebuild invalidates Ruby references to sibling groups: find every unit again by its persistent id before rebuilding it
      pids = plans.select { |pl| pl[:rebuild] }.map { |pl| pl[:pid] }
      pids.each do |pid|
        g = model.find_entity_by_persistent_id(pid)
        Kitchen.rebuild_cabinet(g, {}, cfg, manage_operation: false) if g && g.valid?
      end
    end

    # Recompute and apply. Returns the number of units whose faces changed. `own_op: true` wraps the update in its own (transparent, so
    # Undo removes it together with the action that caused it) operation - pass false when the caller already owns an open operation.
    def refresh(cfg = nil, model = Sketchup.active_model, own_op: true)
      return 0 if @in_refresh

      refresh_now(cfg, model, own_op)
    end

    def refresh_now(cfg, model, own_op)

      @in_refresh = true
      cfg ||= Config.build(Config.saved)
      recs = collect(model)
      all = recs[:units] + recs[:blockers]
      plans = recs[:units].filter_map { |u| plan(u, auto_for(u, all), cfg) }
      watch(model, recs)
      return 0 if plans.empty?

      if own_op
        model.start_operation('E.G.C exposure', true, false, true)
        begin
          apply_all(plans, cfg, model)
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
      else
        apply_all(plans, cfg, model)
      end
      plans.size
    rescue StandardError => e
      Diag.log('exposure_refresh', {}, error: e)
      0
    ensure
      @in_refresh = false
    end

    # ---- units added / deleted / MOVED by hand in SketchUp (Move tool, drag, delete, paste...): refresh once the user is done. Debounced:
    # every event re-arms a 0.7 s timer; while a Move / Rotate / Scale tool is mid-drag nothing runs (no polling, no work per frame).
    class Watch < Sketchup::EntitiesObserver
      def onElementRemoved(_ents, _id)
        Exposure.schedule
      end

      def onElementAdded(_ents, _e)
        Exposure.schedule
      end

      def onElementModified(_ents, e)
        Exposure.schedule if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      end
    end

    class ToolWatch < Sketchup::ToolsObserver
      def onToolStateChanged(_tools, name, _id, state)
        Exposure.busy = (state.to_i != 0 && name.to_s =~ /Move|Rotate|Scale/i) ? true : false
        Exposure.schedule unless Exposure.busy
      end

      def onActiveToolChanged(_tools, _name, _id)
        Exposure.busy = false
        Exposure.schedule
      end
    end

    class AppWatch < Sketchup::AppObserver
      def onOpenModel(_model)
        ::UI.start_timer(1.0, false) { Exposure.watch }
      end

      def onNewModel(_model)
        ::UI.start_timer(1.0, false) { Exposure.watch }
      end
    end

    @pending = false
    @watched = {}
    @busy = false

    class << self
      attr_accessor :busy
    end

    def schedule
      @stamp = Time.now
      return if @pending

      @pending = true
      arm
    end

    def arm
      ::UI.start_timer(0.7, false) do
        if @busy || @in_refresh || (Time.now - @stamp) < 0.65
          arm
        else
          @pending = false
          begin
            refresh(nil, Sketchup.active_model)
          rescue StandardError => e
            Diag.log('exposure_watch', {}, error: e)
          end
        end
      end
    end

    def watch(model = Sketchup.active_model, recs = nil)
      @obs ||= Watch.new
      lists = [model.entities]
      (recs || collect(model))[:units].each { |u| lists << u.g.parent.entities if u.g.parent.respond_to?(:entities) }
      lists.uniq(&:object_id).each do |l|
        key = l.object_id
        next if @watched[key] && @watched[key][:model].equal?(model)

        l.add_observer(@obs)
        @watched[key] = { model: model }
      end
      unless @tw
        @tw = ToolWatch.new
        model.tools.add_observer(@tw)
        Sketchup.add_observer(AppWatch.new)
      end
    rescue StandardError
      nil
    end
  end
  # ------------------------------------------------------------------------------------------------------------------------------
  module LedRun
    module_function

    TOL = 2.0

    # Adjacent upper units whose LED grooves line up (touching ends, parallel, same groove offset / size) form ONE run.
    # only: optional list of persistent ids (a selection). -> [{ 'id','units','start','end','length_mm','n','pids' }] sorted by position.
    def detect(model = Sketchup.active_model, only: nil)
      nodes = []
      Exposure.collect(model)[:units].each do |u|
        led = u.g.get_attribute('egc', 'led')
        next unless led
        next if only && !only.include?(u.g.persistent_id)

        p0 = u.tr * Geom::Point3d.new(0, 0, 0)
        p1 = u.tr * Geom::Point3d.new(u.w.mm, 0, 0)
        nodes << { u: u, l: JSON.parse(led), e: [p0, p1], dir: (p1 - p0).normalize, name: u.g.name, w: u.w }
      end
      parent = (0...nodes.size).to_a
      find = ->(i) { parent[i] == i ? i : (parent[i] = find.call(parent[i])) }
      nodes.each_index do |i|
        ((i + 1)...nodes.size).each do |j|
          a = nodes[i]
          b = nodes[j]
          next unless a[:dir].parallel?(b[:dir])
          next unless (a[:l]['off'] - b[:l]['off']).abs < 0.5 && (a[:l]['lw'] - b[:l]['lw']).abs < 0.01 && (a[:l]['ld'] - b[:l]['ld']).abs < 0.01
          next unless a[:e].any? { |p| b[:e].any? { |q| p.distance(q).to_mm <= TOL } }

          parent[find.call(i)] = find.call(j)
        end
      end
      runs = nodes.each_index.group_by { |i| find.call(i) }.values.map do |idx|
        ns = idx.map { |i| nodes[i] }
        d0 = ns.first[:dir]
        pts = ns.flat_map { |n| n[:e] }
        lo = pts.min_by { |p| EGC::Num.sum(p.to_a.zip(d0.to_a)) { |a, b| a * b } }
        hi = pts.max_by { |p| EGC::Num.sum(p.to_a.zip(d0.to_a)) { |a, b| a * b } }
        order = ns.sort_by { |n| EGC::Num.sum(n[:u].tr.origin.to_a.zip(d0.to_a)) { |a, b| a * b } }
        { 'units' => order.map { |n| n[:name] }, 'n' => ns.size, 'length_mm' => EGC::Num.sum(ns) { |n| n[:w] }.round(1),
          'start' => lo.to_a.map { |v| v.to_mm.round(1) }, 'end' => hi.to_a.map { |v| v.to_mm.round(1) },
          'groove' => ns.first[:l].slice('off', 'lw', 'ld'), 'pids' => order.map { |n| n[:u].g.persistent_id } }
      end
      # numbered by the first unit's NAME (A_2_..., A_4_... left to right, run A then B then C), never by world position: moving or rotating a
      # kitchen must not renumber its LED runs (labels, shop drawings and the cut list quote these numbers)
      nat = ->(s) { s.to_s.scan(/\d+|\D+/).map { |x| x =~ /\d/ ? [0, x.to_i, ''] : [1, 0, x] } }
      runs.sort_by! { |r| [nat.call(r['units'].first), r['start'][1].round(-1), r['start'][0], r['start'][2]] }
      runs.each_with_index { |r, i| r['id'] = format('LED RUN %02d', i + 1) }
      runs
    end

    def summary(runs)
      { 'runs' => runs.size, 'strip_mm' => EGC::Num.sum(runs) { |r| r['length_mm'] }.round(1), 'profile_mm' => EGC::Num.sum(runs) { |r| r['length_mm'] }.round(1),
        'list' => runs.map { |r| r.slice('id', 'n', 'length_mm', 'start', 'end', 'units') } }
    end
  end
end

# watch models that are already open when the plugin loads (Move / delete by hand refresh the exposure without any E.G.C command)
::UI.start_timer(2.0, false) { EGC::Exposure.watch } if defined?(::UI)
