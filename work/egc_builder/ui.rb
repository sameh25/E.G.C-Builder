# frozen_string_literal: true

require 'json'

module EGC
  # Interactive placement tool (kitchen or single unit) ------------------------
  class PlaceTool
    SNAP_TOL_MM = 150.0

    def initialize(kind, payload, cfg, replacements: [])
      @kind = kind # :kitchen / :unit
      @payload = payload
      @cfg = cfg
      @replacements = replacements
      @rot = 0
      @ip = Sketchup::InputPoint.new
      @snap_x = nil
    end

    def activate
      Sketchup.status_text = 'Click to place  |  near a unit: snaps beside / over it, aligned  |  on a wall: back to the wall  |  Left/Right arrows rotate 90 deg  |  Esc to cancel'
      App.enter_placement if defined?(App)
      @candidates = snap_candidates
      prepare_unit_snap if @kind == :unit
    end

    # ---- single unit: snap to the units already standing (beside / over, aligned and levelled) or to a wall face ----
    def prepare_unit_snap
      @units = Snap.standing_units
      @box = PlaceTool.unit_box(@payload, @cfg)
    end

    # size / class of the unit or appliance about to be placed (the same sizes Kitchen.place_unit builds)
    def self.unit_box(p, cfg)
      hang = Kitchen.default_z(p, cfg)
      if p['kind'].to_s == 'device'
        dv = Catalog.device(p['dev'])
        return { w: (p['w'] || dv[:w]).to_f, d: (p['d'] || dv[:d]).to_f, h: (p['h'] || dv[:h]).to_f, kind: hang > 300 ? 'wall' : 'base', hang: hang }
      elsif p['kind'].to_s == 'slot'
        sd = Library::SLOT[p['type'].to_s] || Library::SLOT['washer']
        h = sd[:under] ? cfg['base_h'].to_f - cfg['top_thk'].to_f - 5 : (p['h'] || sd[:h]).to_f
        return { w: p['w'].to_f, d: cfg['base_d'].to_f * sd[:d], h: h, kind: 'base', hang: hang }
      end

      spec = Kitchen.unit_spec(p, cfg)
      kind = %w[wall hood].include?(spec[:kind].to_s) ? 'wall' : spec[:kind].to_s
      { w: spec[:w].to_f, d: spec[:d].to_f, h: spec[:h].to_f, kind: kind, hang: Kitchen.default_z(p, cfg) }
    rescue StandardError
      nil
    end

    # the snapped pose under the cursor: { tr:, how: } or nil
    def unit_pose
      return nil unless @kind == :unit && @box && @ip.valid?

      pt = @ip.position
      pose = Snap.place_pose(@units, pt, @box[:w], @box[:d], @box[:h], @box[:kind], @box[:hang])
      return pose if pose

      rej = Snap.place_reject(@units, pt, @box[:w], @box[:d], @box[:h], @box[:kind]) # at a corner unit, but not a place: refused, not guessed
      return rej.merge(reject: true, at: pt) if rej

      face = @ip.face
      return nil unless face
      # a face of an E.G.C unit is not a wall: a new unit never puts its back on a cabinet front
      return nil if (@ip.instance_path.to_a rescue []).any? { |e| e.respond_to?(:attribute_dictionary) && e.attribute_dictionary('egc') }

      n = (@ip.transformation * face.normal).normalize
      floor = @units.reject { |u| u[:kind] == 'wall' }.map { |u| u[:tr].origin.z.to_mm }.min || 0.0
      tr = Snap.wall_pose(pt, n, @box[:w], floor + @box[:hang])
      tr && !Snap.place_blocked?(@units, tr, @box[:w], @box[:d], @box[:h]) ? { tr: tr, how: :wall } : nil
    rescue StandardError
      nil
    end

    def draw_pose(view, pose)
      if pose[:reject] # red cross at the cursor: nothing will be placed here
        c = pose[:at]
        r = 180.mm
        view.drawing_color = Sketchup::Color.new(220, 40, 40)
        view.line_width = 4
        view.draw(GL_LINES, [c.offset([1, 1, 0], r), c.offset([-1, -1, 0], r), c.offset([1, -1, 0], r), c.offset([-1, 1, 0], r)])
        view.tooltip = Snap::REJECT_TEXT[pose[:how]].to_s.split('  |  ')[App.respond_to?(:lang) && App.lang.to_s == 'ar' ? 1 : 0].to_s.sub('E.G.C: ', '')
        return
      end
      b = @box
      tr = pose[:tr]
      c = [[0, 0], [b[:w], 0], [b[:w], -b[:d]], [0, -b[:d]]]
      lo = c.map { |x, y| tr * Geom::Point3d.new(x.mm, y.mm, 0) }
      hi = c.map { |x, y| tr * Geom::Point3d.new(x.mm, y.mm, b[:h].mm) }
      view.drawing_color = Sketchup::Color.new(30, 160, 90)
      view.line_width = 3
      view.draw(GL_LINE_LOOP, lo)
      view.draw(GL_LINE_LOOP, hi)
      view.draw(GL_LINES, lo.zip(hi).flatten)
      if pose[:filler] # the filler that will be built with it
        fx = pose[:filler][:x]
        fw = pose[:filler][:w]
        view.drawing_color = Sketchup::Color.new(200, 140, 20)
        view.draw(GL_LINE_LOOP, [[fx, -b[:d]], [fx + fw, -b[:d]], [fx + fw, -b[:d]], [fx, -b[:d]]].each_with_index.map { |(x, y), i| tr * Geom::Point3d.new(x.mm, y.mm, (i < 2 ? 0 : b[:h]).mm) })
      end
      view.tooltip = { right: 'beside (right)', left: 'beside (left)', over_left: 'aligned left', over_right: 'aligned right', wall: 'back to wall', corner_arm: 'end of the corner arm (turned 90 deg, back to the side wall) + 50 filler', blind_return: 'return run in front of the blind lane (fronts 50 past the door)' }[pose[:how]].to_s
    end

    def deactivate(view)
      App.exit_placement if defined?(App)
      view.invalidate
    end

    def onCancel(_reason, _view)
      App.exit_placement if defined?(App)
      Sketchup.active_model.select_tool(nil)
    end

    # World X (mm) of every existing E.G.C run/kitchen/wardrobe/unit edge, for snapping a new one
    # flush against it - the common "continue the row" and "line up with the cabinet run" moves.
    def snap_candidates
      xs = []
      Sketchup.active_model.entities.grep(Sketchup::Group).each do |g|
        d = g.attribute_dictionary('egc')
        next unless d && (d['kitchen'] || d['wardrobe'] || d['run'] || d['spec'])

        bb = g.bounds
        xs << bb.min.x.to_mm
        xs << bb.max.x.to_mm
      end
      xs.uniq
    end

    def snapped_point(pt)
      @snap_x = nil
      best = SNAP_TOL_MM
      (@candidates || []).each do |cx|
        dist = (pt.x.to_mm - cx).abs
        next unless dist < best

        best = dist
        @snap_x = cx
      end
      return pt unless @snap_x

      Geom::Point3d.new(@snap_x.mm, pt.y, pt.z)
    end

    def onMouseMove(_flags, x, y, view)
      @ip.pick(view, x, y)
      view.invalidate
    end

    def onKeyDown(key, _rep, _flags, view)
      @rot = (@rot + 90) % 360 if key == VK_RIGHT
      @rot = (@rot - 90) % 360 if key == VK_LEFT
      view.invalidate
    end

    def rects
      c = @cfg['base_d'].to_f
      if @kind == :unit
        d = @payload['d'].to_f
        d = c if d <= 0
        return [[0, 0, @payload['w'].to_f, d]]
      end
      return [[0, 0, @payload['w'].to_f, (@payload['d'] || 600).to_f]] if @kind == :wardrobe

      p = @payload
      a = p['runs']['a']['len'].to_f
      out = [[0, 0, a, c]]
      lay = p['layout']
      left = lay == 'U' || (lay == 'L' && p['l_side'] != 'right')
      right = lay == 'U' || (lay == 'L' && p['l_side'] == 'right')
      out << [0, c, c, p['runs']['b']['len'].to_f] if left && p['runs']['b']
      out << [a - c, c, c, p['runs']['c']['len'].to_f] if right && p['runs']['c']
      out
    end

    def draw(view)
      return unless @ip.valid?

      pose = unit_pose
      return draw_pose(view, pose) if pose

      o = snapped_point(@ip.position)
      rot = Geom::Transformation.rotation(o, Geom::Vector3d.new(0, 0, 1), @rot.degrees)
      view.drawing_color = @snap_x ? Sketchup::Color.new(220, 70, 70) : Sketchup::Color.new(184, 134, 43)
      view.line_width = 2
      rects.each do |x, d, w, h|
        pts = [[x, d], [x + w, d], [x + w, d + h], [x, d + h]].map do |px, pd|
          rot * Geom::Point3d.new(o.x + px.mm, o.y - pd.mm, o.z)
        end
        view.draw(GL_LINE_LOOP, pts)
      end
      return unless @snap_x

      view.line_width = 1
      view.draw(GL_LINES, [Geom::Point3d.new(o.x, o.y + 3000.mm, o.z), Geom::Point3d.new(o.x, o.y - 3000.mm, o.z)])
    end

    def onLButtonDown(_flags, x, y, view)
      @ip.pick(view, x, y)
      return unless @ip.valid?

      pose = unit_pose
      if pose && pose[:reject] # not a valid place: say why, place nothing, keep the tool so another place can be picked
        Sketchup.status_text = Snap::REJECT_TEXT[pose[:how]].to_s
        ::UI.beep
        @last_reject = pose[:how]
        return
      end
      pt = snapped_point(@ip.position)
      origin = [pt.x.to_mm, pt.y.to_mm, pt.z.to_mm]
      pose ? Kitchen.place_unit(@payload, @cfg, origin, @rot, at: pose[:tr]) : place_at(origin)
      Kitchen.place_corner_filler(pose[:tr], pose[:filler], @box, @cfg) if pose && pose[:filler] # beside a corner unit: the 50 mm filler goes in with it
      Kitchen.blind_cover_off(pose[:unit], @cfg) if pose && pose[:how] == :blind_return
      Sketchup.active_model.select_tool(nil)
      App.notify('placed')
    rescue StandardError => e
      id = Diag.log("place_tool", { kind: @kind, payload: (@payload.is_a?(Hash) ? @payload.slice("kind", "type", "mech", "dev", "w", "h", "d") : nil) }, error: e)
      ::UI.messagebox("E.G.C Builder:\n#{Diag.user_message(e, id)}")
      Sketchup.active_model.select_tool(nil)
    end

    def place_at(origin)
      return Kitchen.place_unit(@payload, @cfg, origin, @rot) if @kind == :unit

      begin
        EGC.safe_op(Sketchup.active_model, 'Place E.G.C assembly') do
          @replacements.each { |g| g.erase! if g.valid? }
          if @kind == :kitchen
            Kitchen.generate(@payload.merge('origin' => origin, 'rot' => @rot), @cfg, manage_operation: false, check_overlap: true)
          else
            Wardrobe.generate(@payload, @cfg, origin, @rot, manage_operation: false)
          end
        end
      rescue Kitchen::Cancelled
        ::Sketchup.status_text = 'E.G.C: cancelled'
        nil
      end
    end
  end

  # Safety net: if any path leaves the library parked (exception, another tool picked) it returns as soon as the
  # Select tool becomes active again.
  class ToolWatch < Sketchup::ToolsObserver
    def onActiveToolChanged(_tools, tool_name, _tool_id)
      return unless App.hidden?
      return unless tool_name.to_s =~ /select/i

      ::UI.start_timer(0.05, false) { App.exit_placement }
    end
  end

  class SelObserver < Sketchup::SelectionObserver
    # SketchUp fires different callbacks depending on how the selection changed (a plain click vs.
    # a programmatic .add vs. a shift-click) - handle all of them so the dialog's "selected unit"
    # panel never goes stale.
    def onSelectionBulkChange(_sel)
      App.push_selection(from_observer: true)
    end

    def onSelectionCleared(_sel)
      App.push_selection(from_observer: true)
    end

    def onSelectionAdded(_sel, _entity)
      App.push_selection(from_observer: true)
    end

    def onSelectionRemoved(_sel, _entity)
      App.push_selection(from_observer: true)
    end
  end

  module App
    @dlg = nil
    @lang = nil

    class << self
      attr_reader :dlg

      def lang
        @lang ||= begin
          Sketchup.read_default('EGC_Builder', 'lang', 'ar').to_s
        rescue StandardError, ScriptError
          'ar'
        end
      end

      def show
        if @dlg && @dlg.visible?
          @dlg.bring_to_front
          return
        end
        @dlg = ::UI::HtmlDialog.new(
          dialog_title: 'E.G.C Builder', preferences_key: 'EGC_Builder_Dialog', scrollable: false, resizable: true,
          width: 1180, height: 820, min_width: 420, min_height: 480, style: ::UI::HtmlDialog::STYLE_DIALOG
        )
        @dlg.set_file(File.join(DIR, 'web', 'index.html'))
        callbacks
        @dlg.set_on_closed do
          do_ghost(false) # the see-through view never outlives the window
          @dlg = nil
        end
        @tool_watch ||= ToolWatch.new
        begin
          Sketchup.active_model.tools.add_observer(@tool_watch)
        rescue StandardError
          nil
        end
        @obs ||= SelObserver.new
        model = Sketchup.active_model
        begin
          model.selection.remove_observer(@obs)
        rescue StandardError
          nil
        end
        model.selection.add_observer(@obs)
        @dlg.show
      end

      def send(obj)
        return unless @dlg

        @dlg.execute_script("EGC.recv(#{JSON.generate(obj)})")
      end

      # every "push state to the dialog" message goes to BOTH windows when both happen to be open
      # (the main Kitchen/Units page and the small Edit Unit popup) - keeps them from going stale.
      def broadcast(obj)
        send(obj)
        popup_send(obj)
      end

      # Opens the dialog on the real Unit Edit panel for a specific 3D-selected unit (Quick Actions'
      # Edit / Replace) instead of just re-opening the dialog wherever it last was.
      def open_unit_editor(g, focus: nil)
        was_open = @dlg && @dlg.visible?
        show
        model = Sketchup.active_model
        model.selection.clear
        model.selection.add(g)
        go = lambda do
          push_selection
          send({ 'type' => 'goto', 'tab' => 'units', 'focus' => focus })
        end
        was_open ? go.call : ::UI.start_timer(0.4, false) { go.call }
      end

      # ------------------------------------------------------------------ small "Edit Unit" popup
      # A SEPARATE, small HtmlDialog - not the full Kitchen/Units page - showing only the fields valid
      # for the one selected unit (same index.html, loaded with ?popup=1 so its JS hides everything
      # else: nav, other tabs, the insert-new-unit card). Apply/Cancel only; Replace Unit lives inside it.
      def show_unit_popup(g, focus: nil)
        return unless g

        was_open = @pdlg && @pdlg.visible?
        unless @pdlg
          @pdlg = ::UI::HtmlDialog.new(
            dialog_title: (lang == 'ar' ? 'تعديل الوحدة' : 'Edit Unit'), preferences_key: 'EGC_Builder_UnitPopup',
            scrollable: false, resizable: true, width: 430, height: 660, min_width: 360, min_height: 420, style: ::UI::HtmlDialog::STYLE_DIALOG
          )
          @pdlg.set_url("file:///#{File.join(DIR, 'web', 'index.html').gsub('\\', '/')}?popup=1")
          popup_callbacks
          @pdlg.set_on_closed { @pdlg = nil }
        end
        model = Sketchup.active_model
        model.selection.clear
        model.selection.add(g)
        @pdlg.show
        go = lambda do
          popup_send(init_payload(Config.build(Config.saved), {}))
          push_selection
          popup_send({ 'type' => 'goto', 'tab' => 'units', 'focus' => focus }) if focus
        end
        was_open ? go.call : ::UI.start_timer(0.35, false) { go.call }
      end

      def popup_send(obj)
        return unless @pdlg

        @pdlg.execute_script("EGC.recv(#{JSON.generate(obj)})")
      end

      # Same small popup dialog as Edit Unit, switched into a compact worktop-only form (material,
      # thickness, overhangs, drop-lip, upstand, backsplash) for the run under the selected unit.
      def show_worktop_popup(g)
        return unless g

        was_open = @pdlg && @pdlg.visible?
        unless @pdlg
          @pdlg = ::UI::HtmlDialog.new(
            dialog_title: (lang == 'ar' ? 'الرخام' : 'Worktop'), preferences_key: 'EGC_Builder_UnitPopup',
            scrollable: false, resizable: true, width: 430, height: 660, min_width: 360, min_height: 420, style: ::UI::HtmlDialog::STYLE_DIALOG
          )
          @pdlg.set_url("file:///#{File.join(DIR, 'web', 'index.html').gsub('\\', '/')}?popup=1")
          popup_callbacks
          @pdlg.set_on_closed { @pdlg = nil }
        end
        model = Sketchup.active_model
        model.selection.clear
        model.selection.add(g)
        @pdlg.show
        go = lambda do
          popup_send(init_payload(Config.build(Config.saved), {}))
          push_selection
          popup_send({ 'type' => 'goto_worktop', 'preview' => worktop_preview(g) })
        end
        was_open ? go.call : ::UI.start_timer(0.35, false) { go.call }
      end

      # What Apply will touch, shown in the popup before the user commits: the run/chain detected for
      # `g` right now - a Kitchen.generate run if it's inside one, otherwise the connected chain found
      # by real adjacency (Snap's own alignment test), so the user can Cancel if it's not what they meant.
      def worktop_preview(g)
        return nil unless g && g.get_attribute('egc', 'kind').to_s == 'base'

        run = Kitchen.find_owner_group(g)
        if run && run.get_attribute('egc', 'run') && !run.get_attribute('egc', 'worktop_wrap')
          bases = run.entities.grep(Sketchup::Group).select { |x| Kitchen.base_kind?(x) }
          cx0 = g.transformation.origin.x.to_mm
          cx1 = cx0 + g.get_attribute('egc', 'w').to_f
          tops = run.entities.grep(Sketchup::Group).select { |x| %w[countertop upstand backsplash].include?(x.get_attribute('egc', 'part')) }
          lo, hi = Kitchen.grow_to_cover(tops, cx0, cx1)
          span = bases.select do |x|
            x0 = x.transformation.origin.x.to_mm
            x1 = x0 + x.get_attribute('egc', 'w').to_f
            x0 < hi - 0.5 && x1 > lo + 0.5
          end
          { 'count' => span.size, 'names' => span.map(&:name), 'len' => (hi - lo).round, 'source' => 'run' }
        else
          chain = Kitchen.connected_run(g)
          len = chain.sum { |x| x.get_attribute('egc', 'w').to_f }
          { 'count' => chain.size, 'names' => chain.map(&:name), 'len' => len.round, 'source' => chain.size > 1 ? 'adjacency' : 'single' }
        end
      rescue StandardError
        nil
      end

      # minimal callback set: only what the small unit-edit / worktop popup's JS actually calls
      def popup_callbacks
        d = @pdlg
        d.add_action_callback('ready') do |_, _|
          popup_send(init_payload(Config.build(Config.saved), {}))
          push_selection
        end
        d.add_action_callback('apply_edit') { |_, json| guard { do_apply_edit(JSON.parse(json)) } }
        d.add_action_callback('row_select') { |_, scope| guard { choose_row(scope) } }
        d.add_action_callback('civil_export') { |_, json| guard('Production: civil export') { Civil.export(nil, cfg_from(JSON.parse(json).merge('no_save' => true))) } }
        d.add_action_callback('apply_style') { |_, json| guard { do_apply_style(JSON.parse(json)) } }
        d.add_action_callback('unit_action') { |_, json| guard { do_unit_action(JSON.parse(json)) } }
        d.add_action_callback('apply_handle') { |_, json| guard { do_apply_handle(JSON.parse(json)) } }
        d.add_action_callback('unit_material') { |_, json| guard { do_unit_material(JSON.parse(json)) } }
        d.add_action_callback('space_tool') { |_, _| guard { Sketchup.active_model.select_tool(SpaceTool.new) } }
        d.add_action_callback('space_fill') { |_, json| guard { do_space_fill(JSON.parse(json)) } }
        d.add_action_callback('apply_worktop') { |_, json| guard { do_apply_worktop(JSON.parse(json)) } }
        d.add_action_callback('live_dims_toggle') { |_, _j| guard { LiveDims.toggle } }
        d.add_action_callback('close_popup') { |_, _j| @pdlg&.close }
        d.add_action_callback('set_lang') do |_, l|
          @lang = %w[ar en].include?(l.to_s) ? l.to_s : 'ar'
          Sketchup.write_default('EGC_Builder', 'lang', @lang)
          popup_send({ 'type' => 'lang', 'lang' => @lang })
        end
      end

      # Shrinks the dialog down to a small corner tab and tucks it out of the way while a place/
      # resize tool is active in the 3D view, so it stops covering the model; restores full size
      # (and its on-screen position) once the tool finishes or is cancelled.
      # While a place / resize / draw tool is active the library moves completely off-screen (state, tab, catalog family,
      # search and scroll all stay alive because the page is never closed) and comes back to the same size and position
      # when the tool ends, is cancelled with Esc, or the user picks any other tool.
      def enter_placement
        return unless @dlg
        return if @hidden

        @hidden = true
        @dlg.set_position(-20_000, -20_000)
      rescue StandardError
        @hidden = false
      end

      def exit_placement
        return unless @dlg
        return unless @hidden

        @hidden = false
        g = @geom || {}
        off = @geom_off || [8, 0] # the page reports the client origin; SketchUp positions the outer frame (learned below)
        tx = (g['x'] || 72).to_i + off[0]
        ty = (g['y'] || 60).to_i + off[1]
        @expect = [tx, ty]
        @dlg.set_position(tx, ty)
        @dlg.bring_to_front
      rescue StandardError
        @hidden = false
      end

      def hidden?
        !!@hidden
      end

      def remember_geometry(g)
        return if g['x'].to_i < -5000 # never remember the parked position

        if @expect # first report after a restore: learn the frame offset so repeated hide / restore cycles never drift
          @geom_off = [@expect[0] - g['x'].to_i, @expect[1] - g['y'].to_i] if @geom
          @expect = nil
        end
        @geom = g
      end

      def notify(kind, extra = {})
        send({ 'type' => kind }.merge(extra))
      end

      def cfg_from(msg)
        over = msg['cfg'] || {}
        Config.save(over) unless msg['no_save']
        Config.for_project(Config.build(over), Sketchup.active_model)
      end

      def init_payload(cfg, ui)
        { 'type' => 'init', 'cfg' => cfg, 'lang' => lang, 'version' => PLUGIN_VERSION, 'ui' => ui,
          'types' => Library.all_types, 'units' => Catalog.units_payload, 'mechs' => Mechanisms.payload,
          'devices' => Catalog.devices_payload, 'materials' => Catalog.materials, 'openings' => Openings.payload }
      end

      def callbacks
        d = @dlg
        d.add_action_callback('ready') do |_, _|
          ui = Config.read_json('ui_state_b64', {})
          send(init_payload(Config.for_project(Config.build(Config.saved)), ui))
          push_selection
        end
        d.add_action_callback('set_lang') do |_, l|
          @lang = %w[ar en].include?(l.to_s) ? l.to_s : 'ar'
          Sketchup.write_default('EGC_Builder', 'lang', @lang)
          send({ 'type' => 'lang', 'lang' => @lang })
        end
        d.add_action_callback('autofill') do |_, json|
          m = JSON.parse(json)
          cols = Kitchen.auto_columns(m['len'], 'fridge' => m['fridge'] != false, 'oven_tower' => m['tower'] == true)
          send({ 'type' => 'cols', 'run' => m['run'], 'cols' => cols })
        end
        d.add_action_callback('generate') { |_, json| guard { do_generate(JSON.parse(json)) } }
        d.add_action_callback('kitchen_run') { |_, json| guard { msg=JSON.parse(json); cfg=cfg_from(msg); enter_placement; Sketchup.active_model.select_tool(KitchenLineTool.new(cfg)) } }
        d.add_action_callback('op_insert') { |_, json| guard { do_op_insert(JSON.parse(json)) } }
        d.add_action_callback('op_edit') { |_, json| guard { do_op_edit(JSON.parse(json)) } }
        d.add_action_callback('op_move') { |_, json| guard { do_op_move(JSON.parse(json)) } }
        d.add_action_callback('op_delete') { |_, _j| guard { do_op_delete } }
        d.add_action_callback('insert_unit') { |_, json| guard { do_insert_unit(JSON.parse(json)) } }
        d.add_action_callback('beside') { |_, json| guard { do_beside(JSON.parse(json)) } }
        d.add_action_callback('apply_edit') { |_, json| guard { do_apply_edit(JSON.parse(json)) } }
        d.add_action_callback('row_select') { |_, scope| guard { choose_row(scope) } }
        d.add_action_callback('civil_export') { |_, json| guard { Civil.export(nil, cfg_from(JSON.parse(json).merge('no_save' => true))) } }
        d.add_action_callback('set_motion_speed') { |_, v| guard { Animator.set_speed(v) } }
        d.add_action_callback('get_motion_speed') { |_, _v| guard { send({ 'type' => 'motion_speed', 'v' => Animator.speed }) } }
        d.add_action_callback('dlg_geom') { |_, json| remember_geometry(JSON.parse(json)) rescue nil }
        d.add_action_callback('apply_style') { |_, json| guard { do_apply_style(JSON.parse(json)) } }
        d.add_action_callback('unit_action') { |_, json| guard { do_unit_action(JSON.parse(json)) } }
        d.add_action_callback('apply_handle') { |_, json| guard { do_apply_handle(JSON.parse(json)) } }
        d.add_action_callback('unit_material') { |_, json| guard { do_unit_material(JSON.parse(json)) } }
        d.add_action_callback('resize_start') { |_, json| guard { do_resize_start(JSON.parse(json)) } }
        d.add_action_callback('insert_mech') { |_, json| guard { do_insert_mech(JSON.parse(json)) } }
        AssistantUI::OPS.each { |op| d.add_action_callback(op) { |_, json| guard(op) { AssistantUI.call(op, (json.to_s.empty? ? {} : JSON.parse(json))) } } }
        d.add_action_callback('apply_mech') { |_, json| guard { do_apply_mech(JSON.parse(json)) } }
        d.add_action_callback('apply_kstyle') { |_, json| guard { do_apply_kstyle(JSON.parse(json)) } }
        d.add_action_callback('insert_device') { |_, json| guard { do_insert_device(JSON.parse(json)) } }
        d.add_action_callback('motion') { |_, t| guard { do_motion(t.to_f) } }
        d.add_action_callback('ghost') { |_, on| guard { do_ghost(on.to_s == 'true') } }
        d.add_action_callback('space_tool') { |_, _| guard { Sketchup.active_model.select_tool(SpaceTool.new) } }
        d.add_action_callback('space_fill') { |_, json| guard { do_space_fill(JSON.parse(json)) } }
        d.add_action_callback('set_material') { |_, json| guard { do_set_material(JSON.parse(json)) } }
        d.add_action_callback('load_kitchen') { |_, _| guard { do_load_kitchen } }
        d.add_action_callback('ward_auto') do |_, json|
          m = JSON.parse(json)
          send({ 'type' => 'ward_sections', 'sections' => Wardrobe.auto_sections(m['w'].to_f, Config.build(m['cfg']),
                                                                                  (m['target'] || 900).to_f) })
        end
        d.add_action_callback('ward_generate') { |_, json| guard { do_ward(JSON.parse(json)) } }
        d.add_action_callback('load_wardrobe') do |_, _|
          g = Sketchup.active_model.selection.grep(Sketchup::Group).find { |x| x.get_attribute('egc', 'wardrobe') }
          if g
            send({ 'type' => 'ward_params', 'params' => JSON.parse(g.get_attribute('egc', 'params', '{}')) })
          else
            send({ 'type' => 'toast', 'msg' => 'select_ward' })
          end
        end
        d.add_action_callback('analyse') { |_, json| guard { do_analyse(JSON.parse(json)) } }
        d.add_action_callback('export') { |_, json| guard('Production: cut-list export') { do_export(JSON.parse(json)) } }
        d.add_action_callback('project_pricing_get') do |_, _|
          guard('Production: project pricing') do
          model = Sketchup.active_model
          cfg = Config.for_project(Config.build(Config.saved), model)
          raw = Cutlist.collect(model, use_selection: false)
          board_types = raw[:parts].reject { |p| %w[top glass splash].include?(p[:mat].to_s) || p[:part].to_s == 'plinth' || p[:mat].to_s == 'plinth' }.map { |p| { 'mat' => p[:mat].to_s, 'thk' => p[:thk].to_f } }.uniq
          mats = board_types.map { |b| b['mat'] }.uniq
          board_requirements = board_types.to_h do |b|
            mat = b['mat']; thk = b['thk']; key = "#{mat}:#{thk}"
            parts = raw[:parts].select { |p| p[:mat].to_s == mat && p[:thk].to_f == thk }
            begin
              nested = Cutlist.nest_all(parts, cfg)[[mat, thk]]
              unit_price = (cfg['price_sheet'] || {})[key] || (cfg['price_sheet'] || {})[mat]
              [key, { 'sheets' => nested[:sheets].size, 'oversize' => nested[:oversize].size,
                      'cost' => (unit_price.to_f * nested[:sheets].size if unit_price && unit_price.to_f.positive?) }]
            rescue StandardError => e
              [key, { 'sheets' => nil, 'oversize' => nil, 'cost' => nil, 'status' => e.message.to_s.split(':').first }]
            end
          end
          apps = raw[:apps].keys.map(&:to_s).uniq
          detected_hw = raw[:hw].select { |_k, qty| qty.to_f.positive? }.keys.map(&:to_s)
          detected_hw << 'plinth_m' if raw[:parts].any? { |p| p[:part].to_s == 'plinth' }
          send({ 'type' => 'project_pricing', 'cfg' => cfg, 'materials' => mats, 'board_types' => board_types, 'board_requirements' => board_requirements, 'appliances' => apps, 'hardware' => detected_hw })
          end
        end
        d.add_action_callback('project_pricing_save') do |_, json|
          guard('Production: save project pricing') do
            Config.save_project(Sketchup.active_model, JSON.parse(json))
            send({ 'type' => 'project_pricing_saved' })
          end
        end
        d.add_action_callback('save_settings') do |_, json|
          Config.save(JSON.parse(json))
          send({ 'type' => 'toast', 'msg' => 'saved' })
        end
        d.add_action_callback('reset_settings') do |_, _|
          Config.save({})
          send(init_payload(Config.for_project(Config.build, Sketchup.active_model), {}))
        end
        register_tools(d)
      end

      # Trace line for the Ruby console, only when EGC_TRACE=1 is set: writing to the SketchUp console from inside a long action was seen to raise a
      # TypeError or to block, and it must never fail (or be reported as) the production action itself. Every failure is recorded by Diag.log anyway.
      def trace(msg)
        return unless ENV['EGC_TRACE'] == '1'

        puts(msg)
      rescue Exception # rubocop:disable Lint/RescueException
        nil
      end

      def guard(op = "ui_action")
        production = op.to_s.start_with?('Production:')
        trace("[EGC Production] ACTION #{op}") if production
        License.guard! # no valid activation key: nothing is built, changed or exported (the window still opens, to enter a key)
        result = yield
        trace("[EGC Production] OK #{op}") if production
        result
      rescue StandardError => e
        trace("[EGC Production] ERROR #{e.class}: #{e.message.to_s.gsub(/[\r\n]+/, ' ')[0, 420]}") if op.to_s.start_with?('Production:')
        id = Diag.log(op, {}, error: e)
        broadcast({ "type" => "error", "msg" => Diag.user_message(e, id), "op_id" => id })
      end

      # ---- kitchen --------------------------------------------------------
      def do_generate(msg)
        License.guard!
        cfg = cfg_from(msg)
        params = msg['params']
        fixed = Kitchen.ensure_layout(params, cfg)
        unless fixed.equal?(params)
          # the kitchen gets its corner units: the unit lists in the window follow
          (fixed['runs'] || {}).each { |rid, r| send({ 'type' => 'cols', 'run' => rid, 'cols' => r['cols'] }) if r && r['cols'] != (params['runs'][rid] || {})['cols'] }
          params = fixed
        end
        Config.write_json('ui_state_b64', msg['ui'] || {})
        warn_list = Config.validate(cfg)
        model = Sketchup.active_model
        sel = []
        if msg['replace']
          sel = model.selection.grep(Sketchup::Group).select { |g| g.get_attribute('egc', 'kitchen') }
          if sel.any?
            t = sel.first.transformation
            o = t.origin
            params = params.merge('origin' => [o.x.to_mm, o.y.to_mm, o.z.to_mm],
                                  'rot' => (Math.atan2(t.xaxis.y, t.xaxis.x) * 180.0 / Math::PI).round)
          end
        end
        if msg['mode'] == 'place'
          model.select_tool(PlaceTool.new(:kitchen, params, cfg, replacements: sel))
          send({ 'type' => 'toast', 'msg' => 'pick_point', 'warn' => warn_list })
        else
          g = begin
            EGC.safe_op(model, 'Generate / replace kitchen') do
              sel.each { |old| old.erase! if old.valid? }   # the replaced kitchen goes first: it must not overlap (or be a neighbour of) the new one
              Kitchen.generate(params, cfg, manage_operation: false, check_overlap: true)
            end
          rescue Kitchen::Cancelled
            send({ 'type' => 'toast', 'msg' => 'cancelled' })
            return
          end
          model.selection.clear
          model.selection.add(g)
          model.active_view.zoom(g)
          send({ 'type' => 'generated', 'warn' => warn_list })
        end
      end

      def do_insert_mech(msg)
        cfg = cfg_from(msg)
        it = Mechanisms.item(msg['mech'])
        raise 'Unknown mechanism' unless it

        mp = { 'kind' => it[:host], 'mech' => it[:id], 'n' => msg['n'], 'w' => (msg['w'] || it[:w]).to_f, 'tier' => msg['tier'].to_i }
        return if place_beside(mp, cfg)

        Sketchup.active_model.select_tool(PlaceTool.new(:unit, mp, cfg))
        send({ 'type' => 'toast', 'msg' => 'pick_point' })
      end

      def do_apply_mech(msg)
        cfg = cfg_from(msg)
        model = Sketchup.active_model
        sel = model.selection.grep(Sketchup::Group).select { |g| g.get_attribute('egc', 'spec') }
        if sel.empty? # fitting a mechanism needs a selected cabinet: say so instead of an error
          send({ 'type' => 'toast', 'msg' => 'select_any' })
          return
        end

        it = Mechanisms.item(msg['mech'])
        wrong = it && sel.map { |g| g.get_attribute('egc', 'kind').to_s.sub('hood', 'wall') }.find { |k| k != it[:host] }
        if wrong # a wall-unit fitting is not put into a base unit (it used to turn the unit into another kind of unit)
          names = { 'base' => 'الأرضية', 'wall' => 'العلوية', 'tall' => 'الطويلة' }
          raise "#{it[:id]}: host #{wrong} not allowed (needs #{it[:host]}) - this mechanism is for #{it[:host]} units only | هذا الميكانيزم للوحدات #{names[it[:host]] || it[:host]} فقط"
        end

        # SketchUp operations cannot nest: the outer operation owns every rebuild.
        EGC.safe_op(model, 'Apply mechanism') do
          sel.each { |g| Kitchen.rebuild_cabinet(g, { 'mech' => msg['mech'], 'n' => msg['n'] }, cfg, manage_operation: false) }
        end
        push_selection
        send({ 'type' => 'toast', 'msg' => 'updated' })
      end

      def do_insert_device(msg)
        cfg = cfg_from(msg)
        dv = Catalog.device(msg['dev'])
        raise 'Unknown device' unless dv

        p = if dv[:id].to_s == 'FRIDGE_TALL' || (dv[:id].to_s.upcase.include?('FRIDGE') && (msg['housing'] == true || dv[:h].to_f >= 1700))
              { 'kind' => 'tall', 'type' => 'fridge_bi', 'w' => (msg['w'] || 700).to_f }
            else
              { 'kind' => 'device', 'dev' => dv[:id], 'w' => (msg['w'] || dv[:w]).to_f, 'h' => (msg['h'] || dv[:h]).to_f,
                'd' => (msg['d'] || dv[:d]).to_f, 'z' => (msg['z'] || dv[:z]).to_f }
            end
        return if place_beside(p, cfg)

        Sketchup.active_model.select_tool(PlaceTool.new(:unit, p, cfg))
        send({ 'type' => 'toast', 'msg' => 'pick_point' })
      end

      # Unit panel > "fill the locked space": shelf / shelves / divider / drawers / doors / hanging rail into the space that was locked with
      # the Space tool (or 'undo' = take the last one out). The additions live in the unit's own description, so the cut list follows.
      def do_space_fill(msg)
        model = Sketchup.active_model
        u = selected_cabinet
        u = Space.locked_unit(model) unless u && u.get_attribute('egc', 'space_pt')
        raise 'Lock a space first: start the Space tool and click inside the unit. | حدّد الفراغ أولاً: شغّل أداة الفراغ واضغط جوّه الوحدة.' unless u && u.get_attribute('egc', 'space_pt')

        ng = msg['kind'].to_s == 'undo' ? (Space.remove_last_extra(u) && Space.locked_unit(model)) : Space.add_extra(u, msg['kind'].to_s, msg['n'], msg)
        ng = Space.locked_unit(model) unless ng.is_a?(Sketchup::Group) && ng.valid?
        if ng&.valid?
          model.selection.clear
          model.selection.add(ng)
        end
        push_selection
        broadcast({ 'type' => 'toast', 'msg' => 'updated' })
      end

      # See-through view while a mechanism is being moved (SketchUp's own X-ray display, nothing in the model is touched: no material,
      # layer or visibility is changed). Switching it off puts back whatever the view was set to before. A viewing aid only - it checks
      # nothing; interference is checked by Interference.check.
      def do_ghost(on)
        ro = Sketchup.active_model.rendering_options
        if on
          @ghost_prev = ro['ModelTransparency'] if @ghost_prev.nil?
          ro['ModelTransparency'] = true
        elsif !@ghost_prev.nil?
          ro['ModelTransparency'] = @ghost_prev
          @ghost_prev = nil
        end
      rescue StandardError
        @ghost_prev = nil
      end

      def do_motion(t)
        model = Sketchup.active_model
        sel = model.selection.to_a
        sel = model.entities.to_a if sel.empty?
        Animator.slider(sel, t)
      end

      # Paint one of the shared E.G.C materials (all units update at once)
      def do_set_material(msg)
        key = msg['key'].to_s
        ck = Geo::COLOR_KEY[key]
        raise 'bad material key' unless ck

        over = { ck => msg['color'] }
        over['mat_names'] = { key => msg['name'] } if msg['name']
        sk = Geo::SWATCH_KEY[key]
        over[sk] = msg['id'] if sk && msg['id']
        saved = Config.saved
        saved = Config.merge(saved, over)
        Config.save(saved)
        Geo.material(key, Config.build(saved))
        Geo.material('drawer', Config.build(saved)) if key == 'carcass' # drawer boxes follow the carcass board
        send({ 'type' => 'toast', 'msg' => 'saved' })
      end

      # the SELECTED units' own material (front / carcass swatch) - the rest of the kitchen keeps its materials. reset: back to the kitchen's.
      def do_unit_material(msg)
        sel = scoped_units(msg, Sketchup.active_model.selection.grep(Sketchup::Group).select { |g| g.get_attribute('egc', 'spec') })
        if sel.empty?
          broadcast({ 'type' => 'toast', 'msg' => 'select_any' })
          return
        end
        cfg = cfg_from(msg)
        edit = if msg['reset']
                 { 'mats' => {} }
               else
                 key = msg['key'].to_s
                 raise 'bad material key' unless %w[front carcass].include?(key) && Catalog.swatch(key, msg['code'].to_s)

                 { 'mats' => { key => msg['code'].to_s } }
               end
        EGC.safe_op(Sketchup.active_model, 'Unit material') do
          fresh = sel.map { |g| Kitchen.rebuild_cabinet(g, edit, cfg, manage_operation: false) }
          Sketchup.active_model.selection.clear
          fresh.compact.each { |g| Sketchup.active_model.selection.add(g) if g.valid? }
        end
        push_selection
        broadcast({ 'type' => 'toast', 'msg' => 'updated' })
      end

      # quick actions: the material library, set to "this unit only", for the unit under the cursor
      def start_unit_materials(g)
        model = Sketchup.active_model
        model.selection.clear
        model.selection.add(g)
        show
        go = -> { push_selection; send({ 'type' => 'unit_mats' }) }
        @dlg && @dlg.visible? ? go.call : ::UI.start_timer(0.6, false) { go.call }
      end

      def do_ward(msg)
        License.guard!
        cfg = cfg_from(msg)
        params = msg['params']
        model = Sketchup.active_model
        origin = nil
        rot = 0
        sel = []
        if msg['replace']
          sel = model.selection.grep(Sketchup::Group).select { |g| g.get_attribute('egc', 'wardrobe') }
          if sel.any?
            t = sel.first.transformation
            o = t.origin
            origin = [o.x.to_mm, o.y.to_mm, o.z.to_mm]
            rot = (Math.atan2(t.xaxis.y, t.xaxis.x) * 180.0 / Math::PI).round
          end
        end
        if msg['mode'] == 'place'
          model.select_tool(PlaceTool.new(:wardrobe, params, cfg, replacements: sel))
          send({ 'type' => 'toast', 'msg' => 'pick_point' })
        else
          g = EGC.safe_op(model, 'Generate / replace wardrobe') do
            fresh = Wardrobe.generate(params, cfg, origin || [0, 0, 0], rot, manage_operation: false)
            sel.each { |old| old.erase! if old.valid? }
            fresh
          end
          model.active_view.zoom(g)
          send({ 'type' => 'generated' })
        end
      end

      def do_load_kitchen
        g = Sketchup.active_model.selection.grep(Sketchup::Group).find { |x| x.get_attribute('egc', 'kitchen') }
        if g
          send({ 'type' => 'kitchen_params', 'params' => JSON.parse(g.get_attribute('egc', 'params', '{}')) })
        else
          send({ 'type' => 'toast', 'msg' => 'select_kitchen' })
        end
      end

      # ---- single units ---------------------------------------------------
      def do_insert_unit(msg)
        License.guard!
        cfg = cfg_from(msg)
        return if place_beside(msg['unit'], cfg)

        Sketchup.active_model.select_tool(PlaceTool.new(:unit, msg['unit'], cfg))
        send({ 'type' => 'toast', 'msg' => 'pick_point' })
      end

      # ---- ADD A UNIT BESIDE the selected one (radial menu "Add right / left", Edit toolbar): the user picks WHAT in the library, it goes
      # straight beside that unit (same snapping rules as the placement tool: touching, backs on one line, level; corner fillers included).
      def start_beside(g = nil, side = :right)
        g ||= Sketchup.active_model.selection.grep(Sketchup::Group).find { |x| x.get_attribute('egc', 'spec') }
        unless g
          ::UI.messagebox(I18n.t('select_any', lang))
          return
        end
        @beside = { g: g, side: side.to_sym }
        show
        go = -> { send({ 'type' => 'goto', 'tab' => 'units' }); send({ 'type' => 'beside', 'side' => side.to_s, 'code' => g.get_attribute('egc', 'code').to_s }) }
        @dlg && @dlg.visible? ? go.call : ::UI.start_timer(0.6, false) { go.call }
      end

      # the unit's own commands from the Edit Unit panel (the same ones the radial menu has)
      def do_unit_action(msg)
        model = Sketchup.active_model
        g = model.selection.grep(Sketchup::Group).find { |x| x.get_attribute('egc', 'spec') }
        unless g
          broadcast({ 'type' => 'toast', 'msg' => 'select_any' })
          return
        end
        case msg['act'].to_s
        when 'open' then Context.toggle_open([g])
        when 'mirror' then Context.mirror(g)
        when 'dup' then Context.duplicate(g)
        when 'beside_r' then start_beside(g, :right)
        when 'beside_l' then start_beside(g, :left)
        when 'draw' then Context.drawing([g])
        when 'strip'
          cfg = cfg_from(msg)
          on = msg['on'] ? (cfg['unit_fascia_h'].to_f.positive? ? cfg['unit_fascia_h'].to_f : 100.0) : 0.0
          if (asm = g.get_attribute('egc', 'tall_assembly')) # a tall unit in two modules: the strip belongs to the upper one
            g = g.parent.entities.grep(Sketchup::Group).find { |x| x.get_attribute('egc', 'tall_assembly') == asm && x.get_attribute('egc', 'tall_role') == 'upper' } || g
          end
          EGC.safe_op(model, 'Finish strip on top') { Kitchen.rebuild_cabinet(g, { 'top_strip' => on }, cfg, manage_operation: false) }
          model.selection.clear
          fresh = model.entities.grep(Sketchup::Group).select { |x| x.get_attribute('egc', 'spec') }.max_by(&:entityID)
          model.selection.add(fresh) if fresh
        end
        push_selection
      end

      def do_beside(msg)
        if msg['side'].to_s == 'off'
          @beside = nil
        elsif @beside
          @beside[:side] = msg['side'].to_s == 'left' ? :left : :right
        end
        send({ 'type' => 'beside', 'side' => @beside ? @beside[:side].to_s : 'off', 'code' => @beside ? @beside[:g].get_attribute('egc', 'code').to_s : '' })
      end

      # -> true when the unit was placed beside the remembered unit
      def place_beside(payload, cfg)
        b = @beside
        return false unless b && b[:g].valid?

        @beside = nil
        units = Snap.standing_units
        u = units.find { |x| x[:g] == b[:g] }
        box = PlaceTool.unit_box(payload, cfg)
        raise 'E.G.C: the unit to add beside is no longer in the model' unless u && box

        lx = b[:side] == :left ? -box[:w] / 2.0 - 5.0 : u[:w] + box[:w] / 2.0 + 5.0
        ly = -box[:d] / 2.0
        same = (box[:kind].to_s == 'wall') == (u[:kind].to_s == 'wall')
        # corner units take a unit on BOTH sides (an L): on the wall side of an L corner unit it goes to the end of the second arm, on the
        # blind side of a blind corner it is the first unit of the return run, turned a quarter turn in front of the blind lane
        if same && (hand = Snap.corner_hand(u)) && b[:side] == (hand == 'L' ? :left : :right)
          _, lx, ly = Snap.corner_arm_pose(u, hand, box[:w], box[:d], 0.0)
        elsif same && box[:kind].to_s != 'wall' && (bl = Snap.blind_edge(u)) && (b[:side] == :right) == bl[0]
          gap = Snap.corner_gap
          lx = bl[0] ? bl[1] + gap + box[:d] / 2.0 : bl[1] - gap - box[:d] / 2.0
          ly = -(u[:d] + box[:w] / 2.0)
        end
        pt = u[:tr] * Geom::Point3d.new(lx.mm, ly.mm, 0)
        pose = Snap.place_pose(units, pt, box[:w], box[:d], box[:h], box[:kind], box[:hang])
        if pose.nil? || pose[:reject] || pose[:unit] != b[:g]
          send({ 'type' => 'toast', 'msg' => 'beside_blocked', 'err' => true })
          send({ 'type' => 'beside', 'side' => 'off' })
          return true
        end
        Kitchen.place_unit(payload, cfg, [pt.x.to_mm, pt.y.to_mm, pt.z.to_mm], 0, at: pose[:tr])
        Kitchen.place_corner_filler(pose[:tr], pose[:filler], box, cfg) if pose[:filler]
        Kitchen.blind_cover_off(b[:g], cfg) if pose[:how] == :blind_return
        send({ 'type' => 'beside', 'side' => 'off' })
        push_selection
        notify('placed')
        true
      end

      # ---- doors & windows on the user's own walls -------------------------
      def selected_opening
        Sketchup.active_model.selection.grep(Sketchup::Group).find { |g| Openings.opening?(g) }
      end

      def do_op_insert(msg)
        License.guard!
        o = msg['op']
        raise 'Unknown opening type' unless Openings::TYPES[o['type']]

        Sketchup.active_model.select_tool(OpeningTool.new(o['type'], o['w'], o['h'], o['sill']))
        send({ 'type' => 'toast', 'msg' => 'pick_wall' })
      end

      def do_op_edit(msg)
        og = selected_opening
        raise 'Select a door / window first' unless og

        o = msg['op']
        Openings.edit(og, type: o['type'], w: o['w'], h: o['h'], sill: o['sill'], dx: o['dx'].to_f)
        push_selection
        send({ 'type' => 'toast', 'msg' => 'updated' })
      end

      def do_op_move(msg)
        og = selected_opening
        raise 'Select a door / window first' unless og

        p = Openings.params_of(og)
        Sketchup.active_model.select_tool(OpeningTool.new(p['type'], p['w'], p['h'], p['sill'], move: og))
        send({ 'type' => 'toast', 'msg' => 'pick_wall' })
      end

      def do_op_delete
        og = selected_opening
        raise 'Select a door / window first' unless og

        Openings.remove(og)
        push_selection
        send({ 'type' => 'toast', 'msg' => 'updated' })
      end

      def selected_cabinet
        Sketchup.active_model.selection.grep(Sketchup::Group).find { |g| g.get_attribute('egc', 'spec') }
      end

      def choose_row(scope)
        g = selected_cabinet
        raise 'Select a cabinet first' unless g
        target = RowEdit.choose(g, scope)
        raise 'No matching cabinet in the requested row' unless target
        Sketchup.active_model.selection.clear
        Sketchup.active_model.selection.add(target)
        push_selection
        broadcast({ 'type' => 'row_scope', 'scope' => scope, 'target_id' => target.persistent_id })
      end

      def selected_device
        Sketchup.active_model.selection.grep(Sketchup::Group).find { |g| g.get_attribute('egc', 'device') }
      end

      # from_observer: SketchUp reports ONE change of the selection through several callbacks (cleared + added + bulk): the same state is
      # sent to the window once, not once per callback. A call made by a command (after a rebuild) is always sent.
      def push_selection(from_observer: false)
        return unless @dlg || @pdlg

        g = selected_cabinet
        info = nil
        dvg = g ? nil : selected_device
        if dvg
          info = { 'name' => dvg.name, 'kind' => 'device', 'type' => dvg.get_attribute('egc', 'device'), 'w' => dvg.get_attribute('egc', 'dw'),
                   'h' => dvg.get_attribute('egc', 'dh'), 'd' => dvg.get_attribute('egc', 'dd'), 'mech' => '', 'cells' => [] }
        end
        if g
          info = { 'id' => g.persistent_id, 'name' => g.name, 'kind' => g.get_attribute('egc', 'kind'), 'type' => g.get_attribute('egc', 'type'),
                   'w' => g.get_attribute('egc', 'w'), 'h' => g.get_attribute('egc', 'h'),
                   'd' => g.get_attribute('egc', 'd'), 'mech' => g.get_attribute('egc', 'mech').to_s,
                   'cells' => (Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))[:cells] rescue []),
                   'exp' => (Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))[:exp] rescue nil), 'exp_eff' => (JSON.parse(g.get_attribute('egc', 'exp').to_s) rescue nil),
                   'notch' => (Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))[:notch] rescue nil),
                   'style' => (Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))[:style] rescue nil),
                   'top_strip' => (begin
                                     a = g.get_attribute('egc', 'tall_assembly')
                                     ug = a && g.parent.entities.grep(Sketchup::Group).find { |x| x.get_attribute('egc', 'tall_assembly') == a && x.get_attribute('egc', 'tall_role') == 'upper' }
                                     Cabinet.spec_from_json((ug || g).get_attribute('egc', 'spec'))[:top_strip]
                                   rescue StandardError
                                     nil
                                   end),
                   'has_hand' => (Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))[:hand].to_s != '' rescue false),
                   'handle' => (Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))[:handle] rescue nil),
                   'handle_pos' => (Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))[:handle_pos] rescue nil),
                   'mats' => (Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))[:mats] rescue nil),
                   'similar' => (similar_units(g).size rescue 1),
                   'sink_model' => (Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))[:sink_model] rescue nil),
                   'hob_model' => (Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))[:hob_model] rescue nil),
                   'has_hob' => %w[hob hob_oven].include?(g.get_attribute('egc', 'type').to_s) && g.get_attribute('egc', 'mech').to_s.empty?,
                   'gola' => (Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))[:gola] rescue nil),
                   'has_sink' => Cabinet::SINK_TYPES.include?(g.get_attribute('egc', 'type').to_s) && g.get_attribute('egc', 'mech').to_s.empty?,
                   'sink_checks' => (Cabinet::SINK_TYPES.include?(g.get_attribute('egc', 'type').to_s) ? Kitchen.sink_report(g.get_attribute('egc', 'w').to_f, g.get_attribute('egc', 'type'), Config.for_project(Config.build(Config.saved), Sketchup.active_model).merge('sink_model' => Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))[:sink_model].to_s)) : nil rescue nil),
                   'space_void' => (g.get_attribute('egc', 'space_pt') && (v = Space.locked_void(g)) ? { 'w' => v[:w].round, 'h' => v[:h].round, 'd' => v[:d].round } : nil),
                   'gap' => (Snap.neighbor_gaps(g) rescue [nil, nil]) }
        end
        og = selected_opening
        wg = g ? nil : Sketchup.active_model.selection.grep(Sketchup::Group).find { |x| x.get_attribute('egc', 'wardrobe') }
        ward = wg && { 'id' => wg.persistent_id, 'w' => wg.get_attribute('egc', 'w'), 'h' => wg.get_attribute('egc', 'h'),
                       'space_void' => (wg.get_attribute('egc', 'space_pt') && (v = Space.locked_void(wg)) ? { 'w' => v[:w].round, 'h' => v[:h].round, 'd' => v[:d].round } : nil) }
        payload = { 'type' => 'selection', 'unit' => info, 'ward' => ward, 'opening' => (og ? Openings.params_of(og) : nil) }
        key = JSON.generate(payload)
        return if from_observer && key == @sel_key && @sel_at && Time.now - @sel_at < 0.4

        @sel_key = key
        @sel_at = Time.now
        broadcast(payload)
      end

      # ------------------------------------------------------------------ "all similar units" scope (unit panel)
      # Similar = same category, type, mechanism and size (rounded mm) standing in the same place of the model as the selected unit.
      # Every unit command of the panel (size, front style, handle, materials, finish sides) can go to all of them in one undo step;
      # the production files (cut list, machine, drawings, work order) read the model, so they follow on the next export.
      def unit_sig(g)
        a = ->(k) { g.get_attribute('egc', k) }
        [a.('kind').to_s, a.('type').to_s, a.('mech').to_s] + %w[w h d].map { |k| a.(k).to_f.round }
      end

      def similar_units(g, sig = unit_sig(g))
        g.parent.entities.grep(Sketchup::Group).select { |q| q.valid? && q.get_attribute('egc', 'spec') && unit_sig(q) == sig }
      end

      def scoped_units(msg, sel)
        return sel unless msg['scope'] == 'same' && sel.any?

        sel.flat_map { |g| similar_units(g) }.uniq
      end

      # size / finish edits go unit by unit through the same row cascade as a single edit (the neighbours move with each one)
      def apply_edit_similar(g, edit, cfg, row_scope = 'both')
        sig = unit_sig(g)
        parent = g.parent
        count = similar_units(g, sig).size
        done = []
        EGC.safe_op(Sketchup.active_model, 'Edit similar E.G.C units') do
          count.times do
            q = parent.entities.grep(Sketchup::Group).find do |c|
              c.valid? && c.get_attribute('egc', 'spec') && unit_sig(c) == sig && !done.include?(c.transformation.origin.to_a.map { |v| v.to_mm.round })
            end
            break unless q

            done << q.transformation.origin.to_a.map { |v| v.to_mm.round }
            RowEdit.apply(q, edit, cfg, scope: row_scope)
          end
        end
      end

      def do_apply_edit(msg)
        dvg = selected_cabinet ? nil : selected_device
        if dvg
          Kitchen.rebuild_device(dvg, msg['edit'], cfg_from(msg))
          push_selection
          broadcast({ 'type' => 'toast', 'msg' => 'updated' })
          return
        end

        g = selected_cabinet
        raise 'No E.G.C unit selected' unless g

        if msg['target_id'] && msg['target_id'].to_i != g.persistent_id
          raise 'Selection changed. Refresh the unit editor before applying dimensions.'
        end

        cfg = cfg_from(msg)
        if msg['scope'] == 'same' && similar_units(g).size > 1
          apply_edit_similar(g, msg['edit'], cfg, msg['row_scope'] || 'both')
        else
          Kitchen.cascade_resize(g, msg['edit'], cfg, row_scope: msg['row_scope'] || 'both')
        end
        push_selection
        broadcast({ 'type' => 'toast', 'msg' => 'updated' })
      end

      # Smart front replace on every selected unit, one undo step
      # Unit panel: change the handle of the selected unit(s) only - rebuilt in place, one undo step; the cut list / drilling follow the new handle
      def do_apply_handle(msg)
        sel = scoped_units(msg, Sketchup.active_model.selection.grep(Sketchup::Group).select { |g| g.get_attribute('egc', 'spec') })
        if sel.empty?
          broadcast({ 'type' => 'toast', 'msg' => 'select_any' })
          return
        end
        narrow = false
        hob_narrow = false
        cfg = cfg_from(msg)
        EGC.safe_op(Sketchup.active_model, 'Change unit handle') do
          edit = {}
          edit['handle'] = msg['handle'].to_s unless msg['handle'].to_s.empty?
          edit['handle_pos'] = msg['handle_pos'].to_s unless msg['handle_pos'].to_s.empty?
          edit['sink_model'] = msg['sink_model'].to_s unless msg['sink_model'].to_s.empty?
          edit['hob_model'] = msg['hob_model'].to_s unless msg['hob_model'].to_s.empty?
          sel = sel.select { |g| %w[hob hob_oven].include?(g.get_attribute('egc', 'type').to_s) } if edit['hob_model'] # the hob kind only goes to units that have a hob
          edit['gola'] = msg['gola'] if msg.key?('gola') # the unit's own handle-free profile sizes (checked in Kitchen.gola_override)
          sel = sel.select { |g| Cabinet::SINK_TYPES.include?(g.get_attribute('egc', 'type').to_s) } if edit['sink_model'] # the sink kind only goes to units that have a sink
          pr = edit['sink_model'] && Kitchen.sink_profile(edit['sink_model'])
          narrow = pr && sel.any? { |g| g.get_attribute('egc', 'w').to_f < pr[:unit_min] - 0.5 } # a product sink is not squeezed into a smaller unit
          hpr = edit['hob_model'] && Kitchen::HOB_MODELS[edit['hob_model']]
          hob_narrow = false
          fresh = sel.map do |g|
            tw = hpr && Kitchen.hob_unit_w(edit['hob_model'], g.get_attribute('egc', 'type').to_s)
            if tw && (g.get_attribute('egc', 'w').to_f - tw).abs > 1.0
              # the unit takes the hob's width (owner, 1.28.55): the units beside it move, the wall unit / hood above follow the new width
              RowEdit.apply(g, edit.merge('w' => tw), cfg)
              Sketchup.active_model.selection.grep(Sketchup::Group).find { |q| q.valid? && q.get_attribute('egc', 'spec') && %w[hob hob_oven].include?(q.get_attribute('egc', 'type').to_s) }
            else
              Kitchen.rebuild_cabinet(g, edit, cfg, manage_operation: false)
            end
          end.compact
          Sketchup.active_model.selection.clear
          fresh.each { |g| Sketchup.active_model.selection.add(g) }
        end
        push_selection
        broadcast({ 'type' => 'toast', 'msg' => narrow ? 'sink_needs_unit' : (hob_narrow ? 'hob_needs_unit' : 'updated') })
      end

      # Kitchen style on units that are ALREADY built: the selected ones ('selected') or every unit standing in the model ('kitchen').
      # Each unit is regenerated from its own stored description with the handle and front style of the settings - same size, same place,
      # same permanent ID, same mechanism, same finish sides; only its own handle / front-style override is dropped so that it follows the
      # style. Colours are the shared materials. A unit that cannot take the style is left as it is and reported with the reason.
      def do_apply_kstyle(msg)
        model = Sketchup.active_model
        cfg = cfg_from(msg)
        all = Snap.standing_units.map { |u| u[:g] }.select { |g| g.get_attribute('egc', 'spec') }
        targets = msg['scope'].to_s == 'kitchen' ? all : model.selection.grep(Sketchup::Group).select { |g| g.get_attribute('egc', 'spec') }
        if targets.empty?
          broadcast({ 'type' => 'toast', 'msg' => 'select_any' })
          return
        end
        names = targets.map(&:name)
        codes = targets.map { |g| g.get_attribute('egc', 'code').to_s }
        by_code = codes.none?(&:empty?) # permanent IDs identify the units; names can repeat (two loose units of one type)
        done = []
        skipped = []
        EGC.safe_op(model, 'Apply kitchen style') do
          targets.each do |g|
            next unless g.valid? # the other module of a tall unit was already done with its partner

            nm = g.name
            if g.get_attribute('egc', 'mech').to_s == 'CHEF_TABLE' && cfg['handle'].to_s == 'gola'
              skipped << { 'name' => nm, 'why' => 'swing-out table: not behind handle-free (gola) fronts | ترابيزة الشغل لا تركب مع واجهات بدون مقبض' }
              next
            end
            begin
              Kitchen.rebuild_cabinet(g, { 'handle' => 'auto', 'style' => 'auto' }, cfg, manage_operation: false, skip_exposure: true)
              done << nm
            rescue MechanismError => e
              raise unless g.valid? # only a refusal that left the unit untouched is a skip

              skipped << { 'name' => nm, 'why' => e.message }
            end
          end
          Exposure.refresh(cfg, model, own_op: false)
        end
        model.selection.clear
        Snap.standing_units.map { |u| u[:g] }.select { |g| by_code ? codes.include?(g.get_attribute('egc', 'code').to_s) : names.include?(g.name) }.each { |g| model.selection.add(g) } unless msg['scope'].to_s == 'kitchen'
        push_selection
        broadcast({ 'type' => 'kstyle_done', 'done' => done.size, 'skipped' => skipped })
      end

      def do_apply_style(msg)
        sel = scoped_units(msg, Sketchup.active_model.selection.grep(Sketchup::Group).select { |g| g.get_attribute('egc', 'spec') })
        if sel.empty?
          broadcast({ 'type' => 'toast', 'msg' => 'select_any' })
          return
        end
        cfg = cfg_from(msg)
        EGC.safe_op(Sketchup.active_model, 'Replace front style') do
          fresh = sel.map { |g| Kitchen.rebuild_cabinet(g, { 'style' => msg['style'].to_s }, cfg, manage_operation: false) }
          Sketchup.active_model.selection.clear
          fresh.each { |g| Sketchup.active_model.selection.add(g) }
        end
        push_selection
        broadcast({ 'type' => 'toast', 'msg' => 'updated' })
      end

      # Worktop popup Apply: edits the shared worktop settings (material, thickness, overhangs, drop-lip,
      # upstand, backsplash) and immediately regenerates the countertop of the run under the selected
      # unit - same regen path Resize/Edit already use, so cutouts/cutlist/cost stay in sync, one undo step.
      def do_apply_worktop(msg)
        g = selected_cabinet
        raise 'No E.G.C unit selected' unless g
        raise 'Select a base unit (its worktop run) to edit the worktop' unless g.get_attribute('egc', 'kind').to_s == 'base'
        run = Kitchen.find_owner_group(g)
        in_generated_run = run && run.get_attribute('egc', 'run') && !run.get_attribute('egc', 'worktop_wrap')
        chain = in_generated_run ? nil : Kitchen.connected_run(g)
        raise 'No connected E.G.C run found for this unit (no aligned, touching base unit on either side)' unless in_generated_run || chain.any?

        wt = msg['top'] || {}
        over = {}
        over['top_thk'] = wt['thk'].to_f if wt['thk'].to_f > 0
        over['top_overhang'] = wt['overhang'].to_f if wt.key?('overhang')
        over['island_overhang'] = wt['back_overhang'].to_f if wt.key?('back_overhang')
        over['top_lip'] = wt['lip'].to_f if wt.key?('lip')
        over['top_lip_w'] = wt['lip_w'].to_f if wt['lip_w'].to_f > 0
        over['upstand_h'] = wt['upstand'].to_f if wt.key?('upstand')
        over['splash_on'] = !!wt['splash_on'] if wt.key?('splash_on')
        over['splash_thk'] = wt['splash_thk'].to_f if wt['splash_thk'].to_f > 0
        over['top_finish'] = wt['finish'].to_s if %w[gloss matt].include?(wt['finish'].to_s)
        if wt['mat_code'] && (entry = Catalog.swatch('top', wt['mat_code']))
          over['top_swatch'] = wt['mat_code']
          over['mat_names'] = { 'top' => entry['name'] }
        end

        saved = Config.merge(Config.saved, over)
        Config.save(saved)
        cfg = Config.build(saved)
        model = Sketchup.active_model
        EGC.safe_op(model, 'Edit worktop') do
          # a new worktop thickness: the units under it are rebuilt first (carcass + worktop = the unit height; handles stay under the slab)
          if in_generated_run
            # the whole generated kitchen: every run (and its corner pieces) takes the new worktop, so all the slabs stay on one level
            runs = run.parent.entities.grep(Sketchup::Group).select { |r| r.get_attribute('egc', 'run') && !r.get_attribute('egc', 'worktop_wrap') }
            runs = [run] if runs.empty?
            runs.each do |r|
              Kitchen.fit_units_to_top(r.entities.grep(Sketchup::Group).select { |u| Kitchen.base_kind?(u) }, cfg)
              Kitchen.rebuild_run_tops(r, cfg)
            end
          else
            fresh = Kitchen.fit_units_to_top(chain, cfg)
            chain = Kitchen.connected_run(fresh[g] || g) unless fresh.empty?
            Kitchen.rebuild_free_worktop(chain, cfg)
          end
          Geo.material('top', cfg)
          Geo.material('splash', cfg) if cfg['splash_on']
        end
        push_selection
        broadcast({ 'type' => 'toast', 'msg' => 'updated' })
      end

      def do_resize_start(msg)
        g = selected_cabinet
        unless g
          send({ 'type' => 'toast', 'msg' => 'select_any' })
          return
        end
        Sketchup.active_model.select_tool(ResizeTool.new(g, cfg_from(msg)))
      end

      # ---- cut list -------------------------------------------------------
      def do_analyse(msg)
        cfg = cfg_from(msg)
        res = Cutlist.analyse(cfg, Sketchup.active_model, use_selection: msg['scope'] == 'selection')
        l = msg['lang'] || lang
        rows = res[:rows].map do |r|
          { 'mat' => cfg['mat_names'][r[:mat]] || r[:mat], 'thk' => r[:thk], 'part' => I18n.part(r[:part], l),
            'len' => r[:len], 'wid' => r[:wid], 'qty' => r[:qty],
            'eb' => (r[:eb_l].zero? && r[:eb_w].zero?) ? '' : "L×#{r[:eb_l]} W×#{r[:eb_w]}",
            'note' => (l == 'ar' ? [r[:groove], r[:notes]].compact.join(' | ').gsub('cutout', 'فتحة').gsub(/\bhob\b/, 'بوتجاز').gsub(/\bsink\b/, 'حوض') : [r[:groove], r[:notes]].compact.join(' | ')) }
        end
        nest = res[:nest].map do |(mat, thk), n|
          { 'mat' => cfg['mat_names'][mat] || mat, 'thk' => thk, 'sheets' => n[:sheets].size,
            'waste' => n[:waste].round(1), 'over' => n[:oversize].size }
        end
        internal = Costing.internal(res, cfg, l)
        cost = internal[:lines].map do |c|
          name = c[:cat] == 'hw' ? I18n.t(c[:key], l) : c[:item]
          category = c[:cat] == 'hw' ? (c[:key].to_s.start_with?('hinge') ? 'hinges' : 'hardware') : c[:cat]
          category = 'other' if %w[edge finish service].include?(category)
          { 'item' => name, 'category' => category, 'qty' => c[:qty], 'unit' => c[:unit], 'price' => c[:price], 'amount' => c[:amount].round }
        end
        internal[:extra].each { |e| cost << { 'item' => e['name'], 'category' => 'service', 'qty' => 1, 'unit' => e['kind'], 'price' => e['value'], 'amount' => e['amount'].round } }
        cost << { 'item' => 'Labor', 'category' => 'service', 'qty' => cfg['labor_pct'], 'unit' => '%', 'price' => nil, 'amount' => internal[:labor].round } if internal[:labor].positive?
        send({ 'type' => 'analysis', 'summary' => Cutlist.summary(res, cfg, l), 'integrity' => res[:integrity].first(20).map { |b| "#{b[:cab]}/#{b[:part]}: #{b[:detail]}" }, 'rows' => rows, 'nest' => nest, 'cost' => cost, 'cabs' => res[:cabs].size,
               'parts' => EGC::Num.sum(res[:rows]) { |r| r[:qty] }, 'area' => EGC::Num.sum(res[:area].values).round(2),
               'total' => internal[:total].round, 'missing_prices' => internal[:missing], 'currency' => internal[:currency] })
      end

      def do_export(msg)
        cfg = cfg_from(msg)
        l = msg['lang'] || lang
        res = Cutlist.analyse(cfg, Sketchup.active_model, use_selection: msg['scope'] == 'selection')
        Cutlist.guard_exports!(res)
        if res[:rows].empty?
          raise 'CUTLIST_NO_MODEL_PARTS: no modeled cut-list parts were found. Generate or edit at least one E.G.C unit before exporting the cut list.'
        end
        base = Sketchup.active_model.title.to_s
        base = 'EGC_Kitchen' if base.empty?
        done = ->(_path) { send({ 'type' => 'toast', 'msg' => 'exported' }) }
        if msg['kind'] == 'work'
          Preview.document(WorkOrder.html(res, cfg, l, base), "#{base}_work_order.html", title: l == 'ar' ? 'أمر تشغيل للمصنع' : 'Factory work order', lang: l, on_saved: done)
        elsif msg['kind'] == 'csv'
          Preview.document(Families.csv(res, nil, l), "#{base}_cutlist.csv", title: l == 'ar' ? 'قائمة القطع' : 'Cut list', lang: l, on_saved: done)
        else
          Preview.document(Report.html(res, l, base), "#{base}_report.html", title: l == 'ar' ? 'تقرير الإنتاج' : 'Production report', lang: l, on_saved: done)
        end
      end
    end
  end
end
