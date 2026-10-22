# frozen_string_literal: true

module EGC
  # Live on-canvas width resize: drag the handle on a selected base/wall/tall cabinet's right
  # edge. The cabinet stretches live (a cheap preview scale) while dragging; on release it is
  # rebuilt with its linked uppers and following columns in one undoable operation.
  class ResizeTool
    HIT_PX = 22
    STEP_MM = 5.0
    MIN_MM = 150.0
    MAX_MM = 2400.0

    def initialize(cab, cfg)
      @cab = cab
      @cfg = cfg
      @w0 = cab.get_attribute('egc', 'w').to_f
      @h = cab.get_attribute('egc', 'h').to_f
      @d = cab.get_attribute('egc', 'd').to_f
      @orig_t = cab.transformation
      @parent_t = Geom::Transformation.new
      owner = Kitchen.find_owner_group(cab)
      while owner
        @parent_t = owner.transformation * @parent_t
        owner = Kitchen.find_owner_group(owner)
      end
      @world_t = @parent_t * @orig_t
      @cur_w = @w0
      @dragging = false
      @hover = false
    end

    def activate
      Sketchup.status_text = 'Drag the amber handle to resize width  |  Esc to cancel'
      App.enter_placement if defined?(App)
    end

    def deactivate(_view)
      abort_resize
      App.exit_placement if defined?(App)
    end

    def onCancel(_reason, _view)
      abort_resize
      Sketchup.active_model.select_tool(nil)
    end

    def handle_point(w = @cur_w)
      local = Geom::Point3d.new(w.mm, -(@d / 2.0).mm, (@h / 2.0).mm)
      @world_t * local
    end

    def near_handle?(x, y, view)
      hp = view.screen_coords(handle_point)
      Math.hypot(hp.x - x, hp.y - y) < HIT_PX
    end

    def onMouseMove(_flags, x, y, view)
      return update_drag(x, y, view) if @dragging

      @hover = @cab.valid? && near_handle?(x, y, view)
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      return unless @cab.valid? && near_handle?(x, y, view)

      @dragging = true
      Sketchup.active_model.start_operation('Live resize E.G.C column', true)
      @operation_open = true
      view.invalidate
    end

    def update_drag(x, y, view)
      return unless @cab.valid?

      ray = view.pickray(x, y)
      origin = handle_point(0)
      axis = @world_t.xaxis
      pts = Geom.closest_points([origin, axis], ray)
      return unless pts

      w = (@world_t.inverse * pts[0]).x.to_mm
      w = (w / STEP_MM).round * STEP_MM
      @cur_w = w.clamp(MIN_MM, MAX_MM)
      sx = @cur_w / @w0
      @cab.transformation = @orig_t * Geom::Transformation.scaling(ORIGIN, sx, 1, 1)
      view.invalidate
    end
    ORIGIN = Geom::Point3d.new(0, 0, 0)

    def onLButtonUp(_flags, _x, _y, _view)
      return unless @dragging

      @dragging = false
      unless @operation_open
        Sketchup.active_model.start_operation('Live resize E.G.C column', true)
        @operation_open = true
      end
      @cab.transformation = @orig_t
      cab, cfg, w = @cab, @cfg, @cur_w
      delta = w - @w0
      if delta.abs >= STEP_MM
        Kitchen.cascade_resize(cab, { 'w' => w }, cfg, manage_operation: false)
        Sketchup.active_model.commit_operation
        @operation_open = false
      else
        abort_resize
      end
      Sketchup.active_model.select_tool(nil)
    rescue StandardError
      abort_resize
      Sketchup.active_model.select_tool(nil)
      raise
    end

    def abort_resize
      return unless @operation_open

      Sketchup.active_model.abort_operation
      @operation_open = false
      @dragging = false
    end

    def draw(view)
      return unless @cab.valid?

      s = view.screen_coords(handle_point)
      r = @dragging || @hover ? 7 : 5
      col = @dragging ? Sketchup::Color.new(217, 164, 65) : (@hover ? Sketchup::Color.new(184, 134, 43) : Sketchup::Color.new(140, 140, 140))
      view.drawing_color = col
      circle = (0..16).map { |i| a = i * Math::PI / 8; Geom::Point3d.new(s.x + r * Math.cos(a), s.y + r * Math.sin(a), 0) }
      view.draw2d(GL_POLYGON, circle)
      view.draw_text(Geom::Point3d.new(s.x + 12, s.y - 10, 0), "#{@cur_w.round} mm") if @dragging
    rescue StandardError
      nil
    end
  end
end
