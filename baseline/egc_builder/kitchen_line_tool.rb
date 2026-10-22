# frozen_string_literal: true
module EGC
  class KitchenLineTool
    MIN_MM = 150.0

    def initialize(cfg)
      @cfg = cfg
      @ip = Sketchup::InputPoint.new
      @start = nil
      @hover = nil
      @made = []
      @busy = false
    end

    def activate
      Sketchup.status_text = 'Kitchen Run: click START, then click END. Each segment is built immediately. Continue clicking for L/U. Esc = finish.'
      App.enter_placement if defined?(App)
    end

    def deactivate(view)
      App.exit_placement if defined?(App)
      view.invalidate
    end

    def onCancel(_reason, view)
      finish(view)
    end

    def onKeyDown(key, _repeat, _flags, view)
      finish(view) if key == 13 || key == 10 || key == 27
    end

    def onMouseMove(_flags, x, y, view)
      @ip.pick(view, x, y)
      @hover = @ip.valid? ? @ip.position : nil
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      return if @busy
      @ip.pick(view, x, y)
      return unless @ip.valid?
      p = @ip.position

      unless @start
        @start = p
        @hover = p
        Sketchup.status_text = 'Kitchen Run: now click the END point. The run will be built immediately.'
        view.invalidate
        return
      end

      build_segment(@start, p)
      @start = p
      @hover = p
      Sketchup.status_text = 'Kitchen Run: segment built. Click next point to continue, or Esc/Enter to finish.'
      view.invalidate
    rescue StandardError => e
      @busy = false
      ::UI.messagebox("E.G.C Kitchen Run error:\n#{e.message}")
    end

    # Double click should not add two extra/duplicate points.
    def onLButtonDoubleClick(_flags, _x, _y, view)
      finish(view)
    end

    def draw(view)
      return unless @start
      p2 = @hover || @start
      view.drawing_color = Sketchup::Color.new(217, 164, 65)
      view.line_width = 4
      view.draw(GL_LINES, [@start, p2]) if p2 != @start
      view.draw_points([@start], 10, 3, Sketchup::Color.new(217, 164, 65))
      view.draw_points([p2], 8, 3, Sketchup::Color.new(217, 164, 65)) if p2 != @start
      len = (@start.distance(p2)).to_mm
      if len >= MIN_MM
        mid = Geom.linear_combination(0.5, @start, 0.5, p2)
        view.draw_text(mid, "#{len.round} mm", { size: 12, bold: true, color: Sketchup::Color.new(217,164,65) })
      end
    end

    private

    def build_segment(a, b)
      vec = b - a
      len = vec.length.to_mm
      return if len < MIN_MM
      @busy = true
      ang_deg = Math.atan2(vec.y, vec.x) * 180.0 / Math::PI
      params = {
        'layout' => 'straight',
        'runs' => { 'a' => { 'len' => len, 'cols' => Kitchen.auto_columns(len) } },
        'origin' => [a.x.to_mm, a.y.to_mm, a.z.to_mm],
        'rot' => ang_deg
      }
      g = Kitchen.generate(params, @cfg)
      @made << g if g && g.valid?
    ensure
      @busy = false
    end

    def finish(view)
      Sketchup.active_model.selection.clear
      @made.each { |g| Sketchup.active_model.selection.add(g) if g && g.valid? }
      Sketchup.active_model.select_tool(nil)
      view.invalidate
    end
  end
end
