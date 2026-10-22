# frozen_string_literal: true

module EGC
  # "Live Clear Dimensions" - a HUD that shows the selected E.G.C unit's real, current W x H x D
  # (read from its actual built geometry bounds, not the spec that built it - so it's still correct
  # after a live-resize drag or a manual stretch) directly in the 3D view, next to the unit.
  # Uses the SketchUp 2022+ Overlay API so it works alongside whatever tool is active
  # (Move/Rotate/Orbit/PlaceTool/...) instead of taking over the tool stack.
  #
  # Recomputes the target straight from model.selection on every draw() call rather than caching
  # via a SelectionObserver - simpler and proven reliable (an observer added from an Overlay's
  # lifecycle hook was not firing reliably; a plain kitchen model has at most a few hundred groups,
  # so a fresh Kitchen.find_owner_group walk-up every redraw is cheap enough not to matter).
  module LiveDims
    AVAILABLE = !!defined?(Sketchup::Overlay)

    def self.egc_group?(g)
      return false unless g.is_a?(Sketchup::Group)

      d = g.attribute_dictionary('egc')
      !!(d && (d['spec'] || d['wardrobe']))
    end

    # Walk up from whatever is selected (the unit group itself, or a part inside it after
    # double-click-editing) to the nearest E.G.C-tagged ancestor group.
    def self.owner_unit(model)
      sel = model.selection
      return nil if sel.empty?

      sel.each do |e|
        cur = e
        return cur if egc_group?(cur)

        14.times do
          cur = Kitchen.find_owner_group(cur, model.entities)
          break unless cur
          return cur if egc_group?(cur)
        end
      end
      nil
    end

    # Bounds are local to the definition. Transform each local axis as a vector,
    # preserving scale without swapping width/depth when the unit is rotated.
    def self.measure(g)
      tr = g.transformation
      owner = Kitchen.find_owner_group(g)
      while owner
        tr = owner.transformation * tr
        owner = Kitchen.find_owner_group(owner)
      end
      bb = g.definition.bounds
      sx, sy, sz = [[1, 0, 0], [0, 1, 0], [0, 0, 1]].map { |v| Geom::Vector3d.new(v).transform(tr).length }
      dims = [bb.width * sx, bb.depth * sz, bb.height * sy]
      anchor = tr * Geom::Point3d.new((bb.min.x + bb.max.x) / 2.0, (bb.min.y + bb.max.y) / 2.0, bb.max.z)
      [dims.map { |n| n.to_mm.round }, anchor]
    end

    # World transform + LOCAL bounds of the unit, following any nested owner groups (same walk as #measure).
    def self.frame(g)
      tr = g.transformation
      owner = Kitchen.find_owner_group(g)
      while owner
        tr = owner.transformation * tr
        owner = Kitchen.find_owner_group(owner)
      end
      [tr, g.definition.bounds]
    end

    if AVAILABLE
      class HudOverlay < Sketchup::Overlay
        MARGIN = 220.mm # how far outside the box each dimension line sits
        COLOR = Sketchup::Color.new(217, 164, 65)

        def initialize
          super('egc_live_dims', 'E.G.C - Live Dimensions')
        end

        # one CAD-style dimension: two witness lines from the real edge out to an offset line, arrow
        # ticks at both ends, the length in mm at the midpoint - never touches the unit's own geometry.
        def dim_line(view, p0, p1, offset_dir, label)
          o0 = p0.offset(offset_dir, MARGIN)
          o1 = p1.offset(offset_dir, MARGIN)
          view.drawing_color = COLOR
          view.line_width = 1.4
          view.line_stipple = '-'
          view.draw(GL_LINES, [p0, o0, p1, o1]) # witness lines
          view.line_stipple = ''
          view.line_width = 1.8
          view.draw(GL_LINES, [o0, o1])
          along = (o1 - o0)
          along.length > 0 ? along.normalize! : nil
          tick = along ? along.transform(Geom::Transformation.scaling(20.mm)) : Geom::Vector3d.new(0, 0, 0)
          perp = along ? along * offset_dir : Geom::Vector3d.new(0, 0, 0)
          perp.length > 0 ? perp.normalize! : nil
          perp_v = perp.transform(Geom::Transformation.scaling(10.mm))
          [[o0, tick], [o1, tick.reverse]].each do |base, dir|
            view.draw(GL_LINES, [base.offset(perp_v.reverse), base.offset(dir).offset(perp_v)])
          end
          mid = Geom::Point3d.new((o0.x + o1.x) / 2.0, (o0.y + o1.y) / 2.0, (o0.z + o1.z) / 2.0)
          s = view.screen_coords(mid)
          return if s.x.abs > 100_000

          view.drawing_color = Sketchup::Color.new(28, 31, 36, 225)
          tw = label.length * 7.2 + 10
          view.draw2d(GL_QUADS, [[s.x - tw / 2.0, s.y - 10, 0], [s.x + tw / 2.0, s.y - 10, 0], [s.x + tw / 2.0, s.y + 10, 0], [s.x - tw / 2.0, s.y + 10, 0]].map { |x, y, z| Geom::Point3d.new(x, y, z) })
          view.draw_text([s.x - tw / 2.0 + 5, s.y - 7], label, { size: 12, bold: true, color: Sketchup::Color.new(255, 255, 255) })
        rescue StandardError
          nil
        end

        def draw(view)
          return if LiveDims.suppressed?

          g = LiveDims.owner_unit(view.model)
          return unless g && g.valid?

          tr, bb = LiveDims.frame(g)
          (w, h, d), = LiveDims.measure(g)
          c = (0..7).map { |i| tr * bb.corner(i) }
          # width: front-bottom edge (corner 0->1), pushed out toward the room (front, -local Y) and down
          dim_line(view, c[0], c[1], tr.yaxis.reverse, "#{w} mm")
          # height: front-left edge (corner 0->4), pushed out to the left (-local X)
          dim_line(view, c[0], c[4], tr.xaxis.reverse, "#{h} mm")
          # depth: left-bottom edge (corner 0->2), pushed out further to the left (-local X), offset from the height line
          dp0 = c[0].offset(tr.zaxis, 260.mm)
          dp1 = c[2].offset(tr.zaxis, 260.mm)
          dim_line(view, dp0, dp1, tr.xaxis.reverse, "#{d} mm")
        rescue StandardError
          nil
        end
      end

      # Forces an immediate redraw the instant the selection changes, instead of waiting for the
      # next incidental view refresh (orbit/pan) to pick it up - draw() itself re-reads the
      # selection fresh every time, this observer only exists to call view.invalidate promptly.
      class LiveDimsSelObserver < Sketchup::SelectionObserver
        def bump(sel)
          sel.model.active_view.invalidate
        end

        def onSelectionBulkChange(sel); bump(sel); end
        def onSelectionCleared(sel); bump(sel); end
        def onSelectionAdded(sel, _e); bump(sel); end
        def onSelectionRemoved(sel, _e); bump(sel); end
      end
    end

    # Toggle on/off, persisted per-model (survives save/reopen) via a model attribute.
    # Defaults OFF: this is an explicit "Dimensions" command now, never a permanent overlay.
    def self.enabled?(model = Sketchup.active_model)
      model.get_attribute('egc', 'live_dims_on', false) == true
    end

    # Hidden while a Quick Actions / Space / Resize / Place tool has its own on-canvas UI open, so the
    # two never draw on top of each other. Any tool's activate/deactivate can push/pop this.
    def self.suppress(on)
      @suppress_n = (@suppress_n || 0) + (on ? 1 : -1)
      @suppress_n = 0 if @suppress_n.negative?
      Sketchup.active_model.active_view.invalidate rescue nil
    end

    def self.suppressed?
      (@suppress_n || 0).positive?
    end

    def self.sync(model = Sketchup.active_model)
      return false unless AVAILABLE

      existing = model.overlays.find { |o| o.overlay_id == 'egc_live_dims' }
      unless existing
        model.overlays.add(HudOverlay.new)
        existing = model.overlays.find { |o| o.overlay_id == 'egc_live_dims' }
      end
      # Overlays are added in a disabled state by default - must be switched on explicitly.
      existing.enabled = enabled?(model) if existing

      @observed_models ||= []
      unless @observed_models.include?(model)
        model.selection.add_observer(LiveDimsSelObserver.new)
        @observed_models << model
      end
      model.active_view.invalidate
      true
    end

    def self.toggle
      model = Sketchup.active_model
      model.set_attribute('egc', 'live_dims_on', !enabled?(model))
      sync(model)
    end
  end
end
