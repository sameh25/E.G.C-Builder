# frozen_string_literal: true

require 'json'

module EGC
  # Presentation tools: tags (client view), exploded view, scenes, isolate.
  module ViewTools
    TAGS = ['EGC Carcass', 'EGC Fronts', 'EGC Hardware', 'EGC Appliances', 'EGC Countertop', 'EGC Glass'].freeze
    module_function

    def model
      Sketchup.active_model
    end

    def set_tag(name, visible)
      l = model.layers[name]
      l.visible = visible if l
    end

    def tag_states
      TAGS.map { |n| { 'name' => n, 'visible' => (model.layers[n] ? model.layers[n].visible? : true), 'exists' => !model.layers[n].nil? } }
    end

    # client view: hide hardware (runners, hinges, rails...) and keep everything else
    def client_view(on)
      EGC.safe_op(model, 'E.G.C client view') { set_tag('EGC Hardware', !on) }
    end

    def show_only(names)
      EGC.safe_op(model, 'E.G.C tags') { TAGS.each { |n| set_tag(n, names.include?(n)) } }
    end

    def show_all_tags
      show_only(TAGS)
    end

    # ---- exploded view ---------------------------------------------------------
    def collect_ex(list, acc = [])
      list.each do |e|
        next unless e.is_a?(Sketchup::Group)

        acc << e if e.get_attribute('egc', 'ex')
        collect_ex(e.entities.to_a, acc)
      end
      acc
    end

    # [group, transformation of its parent in model space] for every part that takes part in the exploded view
    def collect_ex_world(list, tr = Geom::Transformation.new, acc = [])
      list.each do |e|
        next unless e.is_a?(Sketchup::Group) && e.valid?

        acc << [e, tr] if e.get_attribute('egc', 'ex') || Panel::EX.key?(e.get_attribute('egc', 'part').to_s)
        collect_ex_world(e.entities.to_a, tr * e.transformation, acc)
      end
      acc
    end

    def explode(list, t, amount = 300.0)
      t = [[t.to_f, 0.0].max, 1.0].min
      parts = collect_ex_world(list)
      parts.each do |g, _|
        v = Panel::EX[g.get_attribute('egc', 'part').to_s] || g.get_attribute('egc', 'ex') # today's table, also for units built by an earlier version
        orig = g.get_attribute('egc', 'orig')
        next unless v && orig

        tr = Geom::Transformation.translation(
          Geom::Vector3d.new(Geo.mm(v[0] * amount * t), -Geo.mm(v[1] * amount * t), Geo.mm(v[2] * amount * t))
        )
        g.transformation = tr * Geom::Transformation.new(orig)
      end
      size_labels(parts, t > 0.05)
    end

    # The size of every board (length x width x thickness, as in the cut list) written on it while the view is exploded; removed when it closes.
    EX_LABEL = 'ex_label'

    def size_labels(parts, on)
      ents = model.entities
      old = ents.grep(Sketchup::Text).select { |x| x.get_attribute('egc', EX_LABEL) }
      return ents.erase_entities(old) unless on

      have = old.to_h { |x| [x.get_attribute('egc', EX_LABEL), x] }
      seen = {}
      parts.each do |g, ptr|
        next unless g.get_attribute('egc', 'role').to_s == 'part' && g.get_attribute('egc', 'len').to_f.positive?

        key = g.persistent_id
        b = g.bounds # in the parent's space
        pt = ptr * Geom::Point3d.new(b.center.x, b.min.y - 12.mm, b.max.z + 12.mm) # just off the top front edge, so the board itself does not hide its label
        seen[key] = true
        if (tx = have[key]) && tx.valid?
          tx.point = pt
        else
          tx = ents.add_text([g.get_attribute('egc', 'len'), g.get_attribute('egc', 'wid'), g.get_attribute('egc', 'thk')].map { |n| n.to_f.round(1).to_s.sub(/\.0\z/, '') }.join(' × '), pt)
          tx.set_attribute('egc', EX_LABEL, key)
        end
      end
      ents.erase_entities(old.select { |x| x.valid? && !seen[x.get_attribute('egc', EX_LABEL)] })
    end

    # ---- isolate -----------------------------------------------------------------
    def isolate(sel)
      keep = sel.to_a
      return false if keep.empty?

      EGC.safe_op(model, 'E.G.C isolate') do
        model.entities.each { |e| e.visible = keep.include?(e) if e.respond_to?(:visible=) }
      end
      true
    end

    def show_everything
      EGC.safe_op(model, 'E.G.C show all') do
        model.entities.each { |e| e.visible = true if e.respond_to?(:visible=) }
      end
    end

    # ---- scenes -----------------------------------------------------------------
    def bbox_of(list)
      bb = Geom::BoundingBox.new
      list.each { |e| bb.add(e.bounds) }
      bb
    end

    def look(view, eye, target, up, persp, fov = 30)
      cam = Sketchup::Camera.new(eye, target, up)
      cam.perspective = persp
      cam.fov = fov if persp
      view.camera = cam
    end

    def scene_targets(m, targets = nil)
      targets ||= m.entities.grep(Sketchup::Group).select { |g| g.get_attribute('egc', 'kitchen') || g.get_attribute('egc', 'wardrobe') }
      targets = m.entities.grep(Sketchup::Group).select { |g| g.get_attribute('egc') } if targets.empty?
      targets
    end

    # Creates scenes for the given E.G.C kitchen groups (or every E.G.C group in the model)
    def build_scenes(targets = nil)
      m = model
      view = m.active_view
      targets = scene_targets(m, targets)
      return [] if targets.empty?

      bb = bbox_of(targets)
      c = bb.center
      diag = bb.diagonal
      names = []
      EGC.safe_op(m, 'E.G.C scenes') do
        add = lambda do |name|
          old = m.pages[name]
          m.pages.erase(old) if old
          m.pages.add(name)
          names << name
        end
        # iso
        look(view, c.offset(Geom::Vector3d.new(0.7, -1.0, 0.55), diag * 1.7), c, Geom::Vector3d.new(0, 0, 1), true)
        add.call('EGC 1 - Perspective')
        # plan
        look(view, Geom::Point3d.new(c.x, c.y, bb.max.z + diag * 2), c, Geom::Vector3d.new(0, 1, 0), false)
        view.zoom(targets)
        add.call('EGC 2 - Plan')
        # front elevation
        look(view, Geom::Point3d.new(c.x, bb.min.y - diag * 2, c.z), c, Geom::Vector3d.new(0, 0, 1), false)
        view.zoom(targets)
        add.call('EGC 3 - Front elevation')
        # left / right elevations (for L and U kitchens)
        look(view, Geom::Point3d.new(bb.max.x + diag * 2, c.y, c.z), c, Geom::Vector3d.new(0, 0, 1), false)
        view.zoom(targets)
        add.call('EGC 4 - Right side elevation')
        look(view, Geom::Point3d.new(bb.min.x - diag * 2, c.y, c.z), c, Geom::Vector3d.new(0, 0, 1), false)
        view.zoom(targets)
        add.call('EGC 5 - Left side elevation')
      end
      names
    end

    def export_scenes(dir, w = 1600, h = 900)
      m = model
      view = m.active_view
      FileUtils.mkdir_p(dir)
      files = []
      m.pages.each do |pg|
        next unless pg.name.start_with?('EGC ')

        m.pages.selected_page = pg
        file = File.join(dir, "#{pg.name.gsub(/[^\w\-]+/, '_')}.png")
        view.write_image(file, w, h, true)
        files << file
      end
      # Extra client-presentation shot with every mechanism open, reusing the "Perspective" scene's
      # camera - ported from the old tool's reference-video feature notes ("saved scenes with
      # drawers/doors open"), which even the old tool itself only ever got as far as planning.
      # A real open-mechanisms *Scene* page can't work (SketchUp pages don't record arbitrary group
      # transformations, only camera/style/visibility), so this is a plain extra exported image
      # instead: open every mechanism, capture, then always restore back to closed - even if the
      # capture itself raises - so the model is never left sitting open after an export.
      persp = m.pages['EGC 1 - Perspective']
      if persp
        targets = scene_targets(m)
        unless targets.empty?
          m.pages.selected_page = persp
          begin
            Mechanisms.set_state(targets, 1.0)
            file = File.join(dir, 'EGC_6_-_Mechanisms_open.png')
            view.write_image(file, w, h, true)
            files << file
          ensure
            Mechanisms.set_state(targets, 0.0)
          end
        end
      end
      html = +"<!doctype html><meta charset='utf-8'><title>E.G.C scenes</title><style>body{font-family:Segoe UI,Arial;background:#f6f4ee;margin:20px}img{width:100%;max-width:1000px;border:1px solid #ddd;margin:8px 0}</style><h2>E.G.C Builder – #{m.title}</h2>"
      files.each { |f| html << "<h3>#{File.basename(f, '.png')}</h3><img src='#{File.basename(f)}'>" }
      File.write(File.join(dir, 'scenes.html'), html)
      files
    end
  end
end
