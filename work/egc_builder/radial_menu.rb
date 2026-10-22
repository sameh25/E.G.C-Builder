# frozen_string_literal: true

module EGC
  # THE single primary quick-action workflow (1.17.2 consolidation - used to be split across this
  # tool and the separate QuickActionsTool, two toolbar buttons the user had to pick between with
  # overlapping/duplicate commands). Click an E.G.C unit to pop the action icons around the cursor,
  # move toward one and click again to run it. The primary ring holds the everyday commands; "More"
  # opens a second ring with positioning tools (rotate / add left-right / snap) without leaving the
  # tool or hiding those commands permanently.
  # Every action is a vector glyph (drawn with thick strokes) with its name printed next to it, all sizes follow the Windows scaling.
  class RadialMenuTool
    ACTIONS = [
      { id: 'edit', en: 'Edit Unit', ar: 'تعديل الوحدة' },
      { id: 'replace', en: 'Replace', ar: 'استبدال' },
      { id: 'dims', en: 'Dimensions', ar: 'الأبعاد' },
      { id: 'space', en: 'Available Space', ar: 'المساحة المتاحة' },
      { id: 'worktop', en: 'Worktop', ar: 'الرخام' },
      { id: 'dup', en: 'Duplicate', ar: 'نسخ' },
      { id: 'mirror', en: 'Mirror', ar: 'قلب' },
      { id: 'open', en: 'Open/close', ar: 'فتح/قفل' },
      { id: 'draw', en: 'Shop drawing', ar: 'شوب دروينج' },
      { id: 'more', en: 'More', ar: 'المزيد' }
    ].freeze
    # secondary ring (positioning tools, formerly the separate "Quick Actions" tool)
    MORE_ACTIONS = [
      { id: 'rot_r', en: 'Rotate +90', ar: 'تدوير يمين 90' },
      { id: 'rot_l', en: 'Rotate -90', ar: 'تدوير يسار 90' },
      { id: 'add_r', en: 'Add right', ar: 'إضافة يمين' },
      { id: 'add_l', en: 'Add left', ar: 'إضافة شمال' },
      { id: 'snap_l', en: 'Snap to left unit', ar: 'التصاق بالوحدة اليسار' },
      { id: 'snap_r', en: 'Snap to right unit', ar: 'التصاق بالوحدة اليمين' },
      { id: 'snap_w', en: 'Back to wall', ar: 'ضهر الوحدة على الحيطة' },
      { id: 'mat', en: 'Unit materials', ar: 'خامات الوحدة' },
      { id: 'handle', en: 'Unit handle', ar: 'مقبض الوحدة' },
      { id: 'back', en: 'Back', ar: 'رجوع' }
    ].freeze
    # glyphs: polylines in a -10..10 box (y down), one simple idea per action
    GLYPHS = {
      'edit' => [[[-7, 7], [-7, 4], [4, -7], [7, -4], [-4, 7], [-7, 7]], [[1, -4], [4, -1]]],
      'replace' => [[[-6, -4], [5, -4]], [[2, -7], [5, -4], [2, -1]], [[6, 4], [-5, 4]], [[-2, 1], [-5, 4], [-2, 7]]],
      'dims' => [[[-8, 0], [8, 0]], [[-8, -4], [-8, 4]], [[8, -4], [8, 4]], [[-8, 0], [-4, -2]], [[-8, 0], [-4, 2]], [[8, 0], [4, -2]], [[8, 0], [4, 2]]],
      'space' => [[[-7, -7], [7, -7], [7, 7], [-7, 7], [-7, -7]], [[0, -4], [0, 4]], [[-4, 0], [4, 0]]],
      'worktop' => [[[-8, 3], [8, 3], [8, 6], [-8, 6], [-8, 3]], [[-6, 3], [-6, -3]], [[6, 3], [6, -3]]],
      'dup' => [[[-8, -3], [-8, 8], [3, 8], [3, -3], [-8, -3]], [[-3, -8], [8, -8], [8, 3], [3, 3]]],
      'mirror' => [[[0, -9], [0, 9]], [[-2, -6], [-8, 6], [-2, 6], [-2, -6]], [[2, -6], [8, 6], [2, 6], [2, -6]]],
      'iso' => [[[0, -8], [7, -4], [7, 4], [0, 8], [-7, 4], [-7, -4], [0, -8]], [[0, 0], [0, 8]], [[0, 0], [7, -4]], [[0, 0], [-7, -4]]],
      'open' => [[[-6, -9], [-6, 9]], [[-6, -9], [7, -5], [7, 5], [-6, 9]], [[3, -1], [3, 1]]],
      'draw' => [[[-6, -9], [6, -9], [6, 9], [-6, 9], [-6, -9]], [[-3, -4], [3, -4]], [[-3, 0], [3, 0]], [[-3, 4], [1, 4]]],
      'more' => [[[-6, 0], [-4, 0]], [[-1, 0], [1, 0]], [[4, 0], [6, 0]]]
    }.freeze
    # secondary ring: short text/symbol icon (same look the old Quick Actions tool used)
    MORE_ICONS = { 'rot_r' => '⟳', 'rot_l' => '⟲', 'add_r' => '+►', 'add_l' => '◄+', 'snap_l' => '◄', 'snap_r' => '►', 'snap_w' => '▌', 'mat' => '▦', 'handle' => '⊐', 'back' => '↩' }.freeze
    BASE_R_IN = 34
    BASE_R_OUT = 128
    BASE_R = 21 # icon circle radius

    def sf
      @sf ||= begin
        [[::UI.scale_factor.to_f, 1.0].max, 2.5].min
      rescue StandardError
        1.0
      end
    end

    def r_in
      BASE_R_IN * sf
    end

    def r_out
      BASE_R_OUT * sf
    end

    def activate
      Sketchup.status_text = 'Click an E.G.C unit for the quick menu, move to a slice, click to run it  |  Esc to exit'
      @open = false
      @mode = :main
      LiveDims.suppress(true)
    end

    def deactivate(view)
      LiveDims.suppress(false)
      view.invalidate
    end

    def onCancel(_reason, _view)
      Sketchup.active_model.select_tool(nil)
    end

    def find_unit(x, y, view)
      ray = view.pickray(x, y)
      res = Sketchup.active_model.raytest(ray)
      return nil unless res

      hit_pt, path = res
      (path || []).reverse_each do |e|
        next unless e.is_a?(Sketchup::Group)
        return e if e.get_attribute('egc', 'spec') || e.get_attribute('egc', 'wardrobe')
      end

      # Missed every cabinet's own group - check whether the click actually landed on the
      # continuous worktop/fascia/end-panel covering one of them (a very easy, natural click:
      # the slab overhangs the cabinet fronts) and resolve to the unit underneath it instead.
      part_group = (path || []).reverse_each.find do |e|
        e.is_a?(Sketchup::Group) && Kitchen::WORKTOP_PARTS.include?(e.get_attribute('egc', 'part').to_s)
      end
      part_group && Kitchen.unit_under_worktop(part_group, hit_pt)
    end

    def onLButtonDown(_flags, x, y, view)
      return run_selected(view) if @open

      g = find_unit(x, y, view)
      unless g
        Sketchup.active_model.selection.clear
        return
      end
      Sketchup.active_model.selection.clear
      Sketchup.active_model.selection.add(g)
      @target = g
      @cx = x
      @cy = y
      @open = true
      @mode = :main
      @hover = nil
      view.invalidate
    end

    def current_actions
      @mode == :more ? MORE_ACTIONS : ACTIONS
    end

    def onMouseMove(_flags, x, y, view)
      return unless @open

      dx = x - @cx
      dy = y - @cy
      r = Math.hypot(dx, dy)
      n = current_actions.size
      @hover = if r < r_in
                 nil
               else
                 ang = Math.atan2(dy, dx) + Math::PI / 2
                 ang += 2 * Math::PI if ang.negative?
                 ((ang / (2 * Math::PI / n)) + 0.5).floor % n
               end
      view.invalidate
    end

    def rotate(g, deg)
      EGC.safe_op(Sketchup.active_model, 'E.G.C Rotate') do
        g.transform!(Geom::Transformation.rotation(g.transformation.origin, Z_AXIS, deg.degrees))
        Exposure.refresh(nil, Sketchup.active_model, own_op: false)
      end
    end

    def add_side(g, side)
      spec = Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))
      w = (spec[:w] || g.get_attribute('egc', 'w')).to_f
      EGC.safe_op(Sketchup.active_model, 'E.G.C Add Side') do
        spec[:code] = nil
        spec[:name] = "#{spec[:name].to_s.sub(/_cd*z/, '')}_c"
        ents = g.parent.respond_to?(:entities) ? g.parent.entities : Sketchup.active_model.entities
        c = Cabinet.build(ents, spec, Config.for_project(Config.build(Config.saved), Sketchup.active_model))
        ax = g.transformation.xaxis
        sgn = side == :right ? 1.0 : -1.0
        c.transformation = g.transformation
        c.transform!(Geom::Transformation.translation(Geom::Vector3d.new(ax.x * w.mm * sgn, ax.y * w.mm * sgn, ax.z * w.mm * sgn)))
        Numbering.apply(Sketchup.active_model) # the added unit gets its permanent U-ID now
        Sketchup.active_model.selection.clear
        Sketchup.active_model.selection.add(c)
        Exposure.refresh(nil, Sketchup.active_model, own_op: false)
      end
    end

    def run_more(id, g, view)
      case id
      when 'back'
        @mode = :main
        @hover = nil
        view.invalidate
        return
      when 'rot_r' then rotate(g, 90)
      when 'rot_l' then rotate(g, -90)
      when 'add_r' then App.start_beside(g, :right) # the user picks WHICH unit in the library (not a copy of this one)
      when 'add_l' then App.start_beside(g, :left)
      when 'snap_l' then Snap.side(g, :left)
      when 'snap_r' then Snap.side(g, :right)
      when 'snap_w' then Snap.wall(g)
      when 'mat' then App.start_unit_materials(g)
      when 'handle' then App.open_unit_editor(g, focus: 'uHpick')
      end
      @open = false
      view.invalidate
    end

    def run_selected(view)
      act = @hover && current_actions[@hover]
      g = @target
      return unless act && g&.valid?

      if @mode == :more
        return run_more(act[:id], g, view)
      end
      if act[:id] == 'more'
        @mode = :more
        @hover = nil
        view.invalidate
        return
      end

      @open = false
      view.invalidate
      case act[:id]
      when 'edit' then App.show_unit_popup(g)
      when 'replace' then App.show_unit_popup(g, focus: 'replace')
      when 'dims' then LiveDims.toggle
      when 'worktop' then App.show_worktop_popup(g)
      when 'space'
        if Space.visible?
          Space.set_visible(false)
        else
          Sketchup.active_model.select_tool(SpaceTool.new)
        end
      when 'dup' then Context.duplicate(g)
      when 'mirror' then Context.mirror(g)
      when 'iso' then ViewTools.isolate(Sketchup.active_model.selection)
      when 'open' then Context.toggle_open([g])
      when 'draw' then Context.drawing([g])
      end
    rescue StandardError => e
      ::UI.messagebox("E.G.C Builder: #{e.message}")
    end

    def slice_center(i)
      n = current_actions.size
      ang = -Math::PI / 2 + i * (2 * Math::PI / n)
      r = (r_in + r_out) / 2.0
      [@cx + r * Math.cos(ang), @cy + r * Math.sin(ang)]
    end

    def circle_pts(cx, cy, r, segs = 20)
      (0..segs).map { |k| a = k * 2 * Math::PI / segs; Geom::Point3d.new(cx + r * Math.cos(a), cy + r * Math.sin(a), 0) }
    end

    # side of the ring where the name column stands: the side AWAY from the selected unit's centre on screen (labels never cover the unit);
    # a click on the middle of the unit picks the side with more free room in the view
    def label_side(view)
      b = @target.bounds
      pts = (0..7).map { |i| view.screen_coords(b.corner(i)) }
      ux = (pts.map(&:x).min + pts.map(&:x).max) / 2.0
      return (ux > @cx ? -1 : 1) if (ux - @cx).abs > 20 * sf

      (view.vpwidth - @cx) >= @cx ? 1 : -1
    end

    # ONE label, for the hovered slice only (compact icons otherwise - never covers the cabinet, never
    # overlaps its neighbours since at most one is ever drawn): a small tag right next to that icon, on
    # the side away from the selected unit so it never sits over the cabinet geometry.
    def draw_labels(view, side, lang, amber, white)
      return unless @hover

      i = @hover
      a = current_actions[i]
      rad = BASE_R * sf
      mx, my = slice_center(i)
      label = lang == 'ar' ? a[:ar] : a[:en]
      tw = label.length * 9.0 * sf + 20 * sf
      th = 24 * sf
      x0 = side.positive? ? mx + rad + 10 * sf : mx - rad - 10 * sf - tw
      ly = my
      view.drawing_color = amber
      view.draw2d(GL_QUADS, [[x0, ly - th / 2], [x0 + tw, ly - th / 2], [x0 + tw, ly + th / 2], [x0, ly - th / 2 + th]].map { |p, q| Geom::Point3d.new(p, q, 0) })
      view.line_width = 1.6 * sf
      view.drawing_color = white
      view.draw2d(GL_LINE_LOOP, [[x0, ly - th / 2], [x0 + tw, ly - th / 2], [x0 + tw, ly + th / 2], [x0, ly + th / 2]].map { |p, q| Geom::Point3d.new(p, q, 0) })
      opts = { size: 13, bold: true, color: Sketchup::Color.new(20, 22, 26), align: TextAlignCenter }
      view.draw_text(Geom::Point3d.new(x0 + tw / 2.0, ly - 8 * sf, 0), label, opts)
      view.line_width = 1
    end

    def draw(view)
      return unless @open && @target&.valid?

      lang = (defined?(App) ? App.lang : 'en')
      rad = BASE_R * sf
      amber = Sketchup::Color.new(240, 185, 63)
      dark = Sketchup::Color.new(20, 22, 26)
      white = Sketchup::Color.new(255, 255, 255)
      more = @mode == :more
      current_actions.each_with_index do |a, i|
        mx, my = slice_center(i)
        on = @hover == i
        view.drawing_color = on ? amber : dark
        view.draw2d(GL_POLYGON, circle_pts(mx, my, rad, 32))
        view.line_width = (on ? 3.5 : 2.5) * sf
        view.drawing_color = on ? white : amber
        view.draw2d(GL_LINE_LOOP, circle_pts(mx, my, rad, 32))
        view.line_width = 2.6 * sf
        view.drawing_color = on ? dark : white
        if more
          view.draw_text(Geom::Point3d.new(mx - 6 * sf, my - 8 * sf, 0), MORE_ICONS[a[:id]] || '?',
                          { size: 13, bold: true, color: (on ? dark : white) })
        else
          k = rad / 26.0 * 1.9 # glyph scale: the 20-unit box fills ~75 % of the circle
          GLYPHS[a[:id]].each do |pl|
            view.draw2d(GL_LINE_STRIP, pl.map { |gx, gy| Geom::Point3d.new(mx + gx * k, my + gy * k, 0) })
          end
        end
      end
      draw_labels(view, label_side(view), lang, amber, white)
      view.line_width = 2.0 * sf
      view.drawing_color = amber
      view.draw2d(GL_LINE_LOOP, circle_pts(@cx, @cy, r_in, 32))
      view.line_width = 1
    rescue StandardError
      nil
    end
  end
end
