# frozen_string_literal: true

module EGC
  # Timed open/close animation for E.G.C units.
  #  - smootherstep easing (calm start, fastest in the middle, calm stop, no snap at either end)
  #  - duration per motion profile (tunable) x global speed (Slow / Normal / Fast), proportional to the distance left
  #  - reversing mid-run continues from the CURRENT t (no jump); Close from t=0.63 runs 0.63 -> 0
  #  - one undo step for the whole animation: frame 0 is a normal operation, later frames are TRANSPARENT operations
  #    which SketchUp merges into it
  # Compound mechanisms keep their own phases: the global timeline is smooth, Mechanisms.set_state does the staging.
  module Animator
    module_function

    # seconds for a full 0 -> 1 stroke at Normal speed (visual starting points, tunable)
    DURATIONS = { 'hinge' => 1.05, 'slide' => 1.15, 'telescopic' => 1.4, 'lift' => 1.45, 'fold_lift' => 1.9,
                  'rotate' => 1.9, 'swing_out' => 1.8, 'compound' => 2.4 }.freeze
    SPEED = { 'slow' => 1.5, 'normal' => 1.0, 'fast' => 0.65 }.freeze
    FPS = 30.0
    MIN_SECONDS = 0.25

    @runs = {} # key (sorted entity ids) => run: every independent part (a door, a drawer) animates on its own; several may run at once
    @last_slider = nil
    @on_frame = nil # test hook: ->(t) { }

    class << self
      attr_accessor :on_frame
    end

    def speed
      v = Sketchup.read_default('EGC_Builder', 'motion_speed', 'normal').to_s
      SPEED.key?(v) ? v : 'normal'
    end

    def set_speed(v)
      Sketchup.write_default('EGC_Builder', 'motion_speed', SPEED.key?(v.to_s) ? v.to_s : 'normal')
    end

    # velocity knots [u, v] per profile (piecewise linear); position = normalised integral. 'close' variants add a soft-close tail.
    VELOCITY = {
      'hinge' => { open: [[0, 0], [0.3, 1], [0.7, 0.95], [1, 0]], close: [[0, 0], [0.25, 1], [0.7, 0.9], [0.9, 0.35], [1, 0]] },
      'slide' => { open: [[0, 0], [0.1, 1], [0.8, 1], [0.92, 0.4], [1, 0]], close: [[0, 0], [0.1, 1], [0.7, 1], [0.86, 0.38], [1, 0]] },
      'telescopic' => { open: [[0, 0], [0.12, 1], [0.78, 1], [0.92, 0.35], [1, 0]], close: [[0, 0], [0.1, 1], [0.68, 1], [0.86, 0.32], [1, 0]] },
      'lift' => { open: [[0, 0], [0.22, 0.65], [0.5, 1], [0.8, 0.8], [1, 0]], close: [[0, 0], [0.2, 0.7], [0.5, 1], [0.82, 0.5], [1, 0]] },
      'fold_lift' => { open: [[0, 0], [0.2, 0.75], [0.5, 1], [0.85, 0.7], [1, 0]], close: [[0, 0], [0.18, 0.7], [0.5, 1], [0.85, 0.55], [1, 0]] },
      'rotate' => { open: [[0, 0], [0.35, 1], [0.65, 1], [1, 0]], close: [[0, 0], [0.35, 1], [0.65, 1], [1, 0]] },
      'swing_out' => { open: [[0, 0], [0.3, 1], [0.7, 0.9], [1, 0]], close: [[0, 0], [0.3, 1], [0.7, 0.8], [1, 0]] },
      'compound' => { open: [[0, 0], [0.2, 0.85], [0.5, 1], [0.85, 0.8], [1, 0]], close: [[0, 0], [0.2, 0.8], [0.5, 1], [0.85, 0.6], [1, 0]] }
    }.freeze

    @curves = {}

    def curve_table(profile, dir)
      @curves[[profile, dir]] ||= begin
        knots = (VELOCITY[profile] || VELOCITY['hinge'])[dir]
        n = 200
        vel = (0..n).map do |i|
          u = i / n.to_f
          a, b = knots.each_cons(2).find { |p, q| u >= p[0] && u <= q[0] } || [knots[-2], knots[-1]]
          f = b[0] == a[0] ? 0.0 : (u - a[0]) / (b[0] - a[0])
          a[1] + (b[1] - a[1]) * f
        end
        cum = [0.0]
        (1..n).each { |i| cum << cum[-1] + (vel[i] + vel[i - 1]) / 2.0 }
        cum.map { |c| c / cum[-1] }
      end
    end

    # position (0..1) at time fraction u for a profile; dir = :open | :close
    def ease(u, profile = 'hinge', dir = :open)
      u = [[u, 0.0].max, 1.0].min
      tb = curve_table(profile, dir)
      x = u * (tb.size - 1)
      i = [x.floor, tb.size - 2].min
      tb[i] + (tb[i + 1] - tb[i]) * (x - i)
    end

    # profile class of a unit group, from its family / the kinds of moves it contains
    def profile_of(unit)
      mech = unit.get_attribute('egc', 'mech').to_s
      fam = mech.empty? ? nil : Families.info(mech)
      moves = Mechanisms.collect([unit]).map { |g| JSON.parse(g.get_attribute('egc', 'move')) }
      return 'compound' if moves.any? { |m| m['type'] == 'seq' }

      case fam && fam[:profile]
      when 'FOLD_LIFT' then 'fold_lift'
      when 'LIFT' then 'lift'
      when 'ROTATE' then 'rotate'
      when 'CORNER_COMPOUND' then 'compound'
      when 'TELESCOPIC_SLIDE' then 'telescopic'
      when 'LINEAR_SLIDE' then 'slide'
      else moves.any? { |m| m['type'] == 'lin' } ? 'telescopic' : 'hinge'
      end
    end

    def stroke_seconds(units)
      base = units.map { |u| (DURATIONS[profile_of(u)] || 1.0) * Families.duration_multiplier(u.get_attribute('egc', 'mech')) }.max || 1.0
      base * SPEED[speed]
    end

    # ---- state ----------------------------------------------------------------------------------------------
    def current_t(units)
      r = @runs[key_of(units)]
      return r[:t] if r

      g = units.flat_map { |u| Mechanisms.collect([u]) }.first
      return 0.0 unless g

      t = g.get_attribute('egc', 'anim_t')
      t.nil? ? (g.get_attribute('egc', 'is_open') == true ? 1.0 : 0.0) : t.to_f
    end

    def running?
      !@runs.empty?
    end

    # ---- public API -------------------------------------------------------------------------------------------
    def toggle(sel)
      units = sel.to_a
      return if Mechanisms.collect(units).empty?

      if (r = @runs[key_of(units)])
        animate(units, r[:to] >= 0.5 ? 0.0 : 1.0) # reverse mid-flight from the current t
      else
        animate(units, current_t(units) >= 0.5 ? 0.0 : 1.0)
      end
    end

    def animate(units, to_t)
      units = units.to_a
      from = current_t(units)
      stop_run(key_of(units))
      prepared = prepare(units)
      return if prepared.empty?

      to = [[to_t.to_f, 0.0].max, 1.0].min
      return finish(prepared, units, to) if (to - from).abs < 1e-4

      secs = [stroke_seconds(units) * (to - from).abs, MIN_SECONDS].max
      run = { key: key_of(units), units: units, prepared: prepared, from: from, to: to, secs: secs, t0: Time.now, frame: 0, t: from,
              profile: units.map { |u| profile_of(u) }.max_by { |p| DURATIONS[p] || 1.0 }, dir: to < from ? :close : :open }
      @runs[run[:key]] = run
      run[:timer] = UI.start_timer(1.0 / FPS, true) { tick(run) }
      tick(run)
    end

    def slider(units, t)
      units = units.to_a
      stop_run(key_of(units))
      prepared = prepare(units)
      return if prepared.empty?

      transparent = @last_slider && (Time.now - @last_slider) < 2.0
      @last_slider = Time.now
      frame_op('E.G.C motion', transparent) do
        apply(prepared, t)
        store(units, t)
      end
    end

    def stop_run(key = nil)
      (key ? [key] : @runs.keys).each do |k|
        r = @runs.delete(k)
        UI.stop_timer(r[:timer]) if r && r[:timer]
      end
    end

    # ---- internals --------------------------------------------------------------------------------------------
    def key_of(units)
      units.map(&:entityID).sort
    end

    def prepare(units)
      Mechanisms.isolate_motion(units)
      Mechanisms.open_all(units).map { |g| [g, JSON.parse(g.get_attribute('egc', 'move'))] }
    end

    def apply(prepared, t)
      prepared.each { |g, m| g.transformation = Mechanisms.move_transform(m, t) if g.valid? }
    end

    def store(units, t)
      Mechanisms.collect(units).each do |g|
        g.set_attribute('egc', 'anim_t', t.round(4))
        g.set_attribute('egc', 'is_open', t > 0.5)
      end
    end

    def frame_op(name, transparent)
      model = Sketchup.active_model
      model.start_operation(name, true, false, transparent ? true : false)
      yield
      model.commit_operation
    rescue StandardError
      model.abort_operation
      raise
    end

    def tick(run)
      return unless @runs[run[:key]].equal?(run)

      unless run[:units].all?(&:valid?) # a unit was rebuilt/erased mid-animation: stop, never let a failing frame abort (= undo) the user's edit
        UI.stop_timer(run[:timer]) if run[:timer]
        @runs.delete(run[:key])
        return
      end

      u =[(Time.now - run[:t0]) / run[:secs], 1.0].min
      t = run[:from] + (run[:to] - run[:from]) * ease(u, run[:profile], run[:dir])
      run[:t] = t
      last = u >= 1.0
      frame_op('E.G.C open/close', run[:frame].positive?) do
        apply(run[:prepared], last ? run[:to] : t)
        store(run[:units], run[:to]) if last
      end
      run[:frame] += 1
      @on_frame&.call(last ? run[:to] : t)
      return unless last

      UI.stop_timer(run[:timer])
      @runs.delete(run[:key])
    end

    def finish(prepared, units, to)
      frame_op('E.G.C open/close', false) do
        apply(prepared, to)
        store(units, to)
      end
    end
  end
end
