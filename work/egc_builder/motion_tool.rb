# frozen_string_literal: true

module EGC
  # "Click to open/close" - walk around the model and click any moving part of an E.G.C unit directly.
  #
  # THE PART UNDER THE MOUSE IS THE TARGET: clicking the left door of a two-door cabinet moves only that door, clicking drawer 2 moves only
  # drawer 2 (several drawers may stay open independently). Every independent moving assembly keeps its own animation state (anim_t / is_open).
  # A MECHANICALLY LINKED unit (bi-fold lift, magic corner, dish rack - any unit carrying a 'mech') is one coordinated mechanism: it moves as a whole.
  # The hovered part is outlined so the user sees exactly what will move.
  class MotionTool
    # -> [target_group, unit, world_transformation_of_target] or nil.  The target is the OUTERMOST moving assembly below the unit on the picked
    # path (a drawer front, a door leaf, the drawer box inside the same assembly all belong to ONE drawer), or the whole unit for a linked mechanism.
    INDEPENDENT_FAMILIES = %w[DRAWER_FRONT].freeze # a drawer unit from the mechanism library: its drawers are not linked to each other

    def self.resolve(path)
      path = Array(path)
      ui = path.rindex { |e| e.is_a?(Sketchup::Group) && (e.get_attribute('egc', 'spec') || e.get_attribute('egc', 'wardrobe')) }
      return nil unless ui

      unit = path[ui]
      tr = Geom::Transformation.new
      path[0..ui].each { |e| tr *= e.transformation if e.respond_to?(:transformation) }
      if unit.get_attribute('egc', 'mech') && !INDEPENDENT_FAMILIES.include?(Families.family_of(unit.get_attribute('egc', 'mech')).to_s)
        return Mechanisms.collect([unit]).empty? ? nil : [unit, unit, tr, path[0..ui]]
      end

      path[(ui + 1)..].each_with_index do |e, i|
        tr *= e.transformation if e.respond_to?(:transformation)
        return [e, unit, tr, path[0..(ui + 1 + i)]] if e.is_a?(Sketchup::Group) && e.get_attribute('egc', 'move')
      end
      nil
    end

    # A copy that still SHARES its definition with the original (component-style copy) would move together with it: make every instance on the
    # path unique first (top-down; children are looked up again by index because make_unique replaces them) and return the target inside the copy.
    def self.unique_target(chain)
      return chain.last if chain.all? { |e| !e.respond_to?(:definition) || e.definition.instances.length <= 1 }

      idx = chain.each_cons(2).map { |par, ch| par.definition.entities.to_a.index(ch) }
      cur = chain[0]
      cur.make_unique if cur.definition.instances.length > 1
      idx.each do |i|
        cur = cur.definition.entities.to_a[i]
        cur.make_unique if cur.respond_to?(:definition) && cur.definition.instances.length > 1
      end
      cur
    end

    def activate
      Sketchup.status_text = 'E.G.C Motion: click a door / drawer to open or close THAT part - Esc to exit'
      @hover = nil
    end

    def deactivate(view)
      view.invalidate
    end

    def onCancel(_reason, _view)
      Sketchup.active_model.select_tool(nil)
    end

    def resume(view)
      view.invalidate
    end

    def find_target(view, x, y)
      res = Sketchup.active_model.raytest(view.pickray(x, y))
      return nil unless res

      self.class.resolve(res[1])
    rescue StandardError
      nil
    end

    def onMouseMove(_flags, x, y, view)
      @hover = find_target(view, x, y)
      view.invalidate
    end

    # SketchUp delivers the 2nd press of a fast double click as onLButtonDoubleClick (not LButtonDown): treat it as another toggle so a quick
    # "click, click" opens then reverses the SAME part mid-motion instead of ignoring the 2nd click.
    def onLButtonDoubleClick(flags, x, y, view)
      onLButtonDown(flags, x, y, view)
    end

    def onLButtonDown(_flags, x, y, view)
      t = find_target(view, x, y)
      return unless t

      model = Sketchup.active_model
      model.start_operation('E.G.C part', true)
      begin
        target = self.class.unique_target(t[3])
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      linked = target.parent.respond_to?(:entities) ? target.parent.entities.grep(Sketchup::Group).select { |x| x.get_attribute('egc', 'link') == target.name } : []
      Animator.toggle([target] + linked) # the drawer + ITS OWN middle rail(s) (mechanically linked hardware)
      view.invalidate
    rescue StandardError => e
      ::UI.messagebox("E.G.C Motion:\n#{e.message}")
    end

    def draw(view)
      return unless @hover && @hover[0].valid?

      g, _unit, tr = @hover
      lb = g.local_bounds
      c = [lb.min.x, lb.max.x].product([lb.min.y, lb.max.y], [lb.min.z, lb.max.z]).map { |a, b, z| tr * Geom::Point3d.new(a, b, z) }
      view.drawing_color = Sketchup::Color.new(255, 140, 0)
      view.line_width = 3
      [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]].each { |a, b| view.draw(GL_LINES, [c[a], c[b]]) }
      pt = view.screen_coords(c[7])
      return if pt.x.to_f.abs > 100_000

      view.draw_text(Geom::Point3d.new(pt.x + 8, pt.y - 8, pt.z), "▶ #{g.name}", { size: 12, bold: true, color: [255, 255, 255] })
    end
  end
end
