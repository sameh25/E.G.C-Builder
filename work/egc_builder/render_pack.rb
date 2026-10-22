# frozen_string_literal: true

require 'json'
require 'fileutils'

module EGC
  # PRESENTATION RENDER SOURCE. Built only from the approved E.G.C geometry in the model (never from the room picture): camera views (shaded + line
  # control image), the geometry an AI renderer must keep (walls, openings, every unit box, appliances, worktop), materials, and the instruction text.
  # The AI renderer itself is the user's provider (D5 / V-Ray / ControlNet / image API): this pack is its input. No render is claimed here.
  module RenderPack
    module_function

    PROMPT = <<~TXT
      Photorealistic presentation render of the kitchen in the attached images.
      KEEP EXACTLY (do not move, resize, add or remove): walls, openings, every cabinet box and its fronts, appliance positions and sizes, worktop outline,
      room proportions and the camera. The line image is the control image (edges / depth) - follow it pixel for pixel.
      YOU MAY change only: surface materials and colours within the given direction, lighting, small decorative accessories on the worktop, realism.
      Never invent cabinets, appliances, windows or doors.
    TXT

    def views(model)
      bb = Geom::BoundingBox.new
      model.entities.each { |e| bb.add(e.bounds) if e.get_attribute('egc', 'cab') || e.get_attribute('egc', 'kitchen') || e.get_attribute('egc', 'assistant') || e.get_attribute('egc', 'room_shell') }
      model.entities.each { |e| bb.add(e.bounds) } if bb.empty?
      c = bb.center
      r = [bb.width, bb.height, bb.depth].max
      { 'perspective' => { eye: [c.x - r * 0.35, c.y - r * 1.15, c.z + r * 0.35], target: c.to_a, persp: true },
        'front' => { eye: [c.x, c.y - r * 2.0, c.z], target: c.to_a, persp: false } }
    end

    def geometry(model, cfg)
      proj = Assistant.load(model)
      data = SiteDocs.collect(model, proj, cfg)
      { 'units' => data[:units].map { |u| { 'id' => u['code'], 'type' => u['type'], 'unit_type' => Numbering::TYPE[u['kind'].to_s], 'w' => u['w'].to_f.round, 'h' => u['h'].to_f.round, 'd' => u['d'].to_f.round,
                                             'wall' => u['wall'], 'along' => u['along'] && u['along'].map(&:round), 'z0' => u['z0'].to_f.round, 'appliances' => u['apps'].map { |a| a['kind'] } } },
        'walls' => Assistant.walls(proj).map { |w| { 'id' => w['id'], 'len' => w['len'].round, 'open' => proj['no_build'].any? { |n| n['wall'] == w['id'] && n['w'] >= w['len'] - 1 } } },
        'openings' => proj['openings'].map { |o| o.slice('wall', 'type', 'off', 'w', 'h', 'sill') }, 'ceiling' => proj['room']['ceiling']['v'] }
    end

    # writes the pack into dir; returns { dir, files }
    def export(model, cfg, dir, lang = 'en')
      raise 'RENDER_SOURCE_NO_DESIGN: build an approved design first (the render source is the E.G.C model, not the room picture)' if Numbering.units(model).empty?

      FileUtils.mkdir_p(dir)
      view = model.active_view
      old_cam = view.camera
      ro = model.rendering_options
      old_mode = ro['RenderMode']
      old_tex = ro['Texture']
      files = []
      cams = {}
      begin
        views(model).each do |name, v|
          cam = Sketchup::Camera.new(v[:eye], v[:target], [0, 0, 1])
          cam.perspective = v[:persp]
          view.camera = cam
          view.zoom_extents unless v[:persp]
          cams[name] = { 'eye' => cam.eye.to_a.map { |q| q.to_mm.round }, 'target' => cam.target.to_a.map { |q| q.to_mm.round }, 'up' => [0, 0, 1], 'perspective' => v[:persp], 'fov' => (cam.fov rescue nil) }
          ro['RenderMode'] = 2
          f = File.join(dir, "#{name}_shaded.png")
          view.write_image(f, 1600, 1000, true)
          files << f
          ro['RenderMode'] = 1 # hidden line: the edge / control image
          f = File.join(dir, "#{name}_lines_control.png")
          view.write_image(f, 1600, 1000, true)
          files << f
        end
      ensure
        ro['RenderMode'] = old_mode
        ro['Texture'] = old_tex
        view.camera = old_cam
      end
      mats = { 'carcass' => cfg['carcass_color'], 'fronts' => cfg['front_color'], 'worktop' => cfg['top_color'], 'names' => cfg['mat_names'] }
      { 'cameras.json' => JSON.pretty_generate(cams), 'geometry_lock.json' => JSON.pretty_generate(geometry(model, cfg)), 'materials.json' => JSON.pretty_generate(mats),
        'prompt.txt' => PROMPT, 'README.txt' => "Render source exported from the approved E.G.C model (REV #{Revision.current(model) || '-'}).\r\nAI render: REQUIRES your render provider (D5 / V-Ray / ControlNet / image API) - not called by E.G.C.\r\n" }.each do |n, c|
        File.write(File.join(dir, n), c, encoding: 'utf-8')
        files << File.join(dir, n)
      end
      { dir: dir, files: files, index: File.join(dir, 'perspective_shaded.png') }
    end
  end
end
