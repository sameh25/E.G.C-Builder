# frozen_string_literal: true

require 'json'
require 'base64'

module EGC
  # IMAGE -> KITCHEN. A vision-capable AI provider reads two pictures:
  #   SITE image    (photo / hand sketch / SketchUp or CAD drawing WITH written dimensions) -> wall length, openings, sill, visible service points
  #   DESIGN image  (render / photo of the wanted kitchen, optional)                       -> the ordered list of units, left to right
  # Nothing read from a picture is trusted silently: written dimensions are cross-checked (left + opening + right = wall), every value goes into the
  # constraint model as INFERRED (CONFIRMED only when the user ticks "I checked these dimensions"), positions that are only ESTIMATED from the
  # picture (service points) are labelled as such, and the design is built by the normal E.G.C planner / library (ordinary editable units).
  # The provider is the user's choice (their own API key, typed by them in the dialog and stored on this computer only).
  module AssistantVision
    module_function

    PREF = 'EGC_Builder'
    PROVIDERS = {
      'openai' => { 'label' => 'OpenAI', 'api' => 'openai', 'base' => 'https://api.openai.com/v1', 'model' => 'gpt-4o' },
      'gemini' => { 'label' => 'Google Gemini', 'api' => 'gemini', 'base' => 'https://generativelanguage.googleapis.com/v1beta', 'model' => 'gemini-2.5-flash' },
      'custom' => { 'label' => 'OpenAI-compatible (custom URL)', 'api' => 'openai', 'base' => '', 'model' => '' }
    }.freeze
    MAX_IMAGE = 8_000_000
    ROOM_DEPTH_ASSUMED = 3000.0 # mm - an elevation picture shows ONE wall; the depth is only a placeholder for a straight run (flagged in the notes)

    # design unit vocabulary -> E.G.C column. :fix = fixed width, :flex = [min, preferred, max]
    UNITS = {
      'fridge'              => { t: 'fridge_open', dev: 'FRIDGE_TALL', fridge: true, app: [450, 600, 1300] },
      'fridge_side_by_side' => { t: 'fridge_open', dev: 'FRIDGE_SBS', fridge: true, app: [450, 900, 1300] },
      'tall_pantry'         => { t: 'pantry', flex: [400, 600, 600] },
      'tall_oven'           => { t: 'oven_tall', fix: 600 },
      'tall_oven_microwave' => { t: 'oven_tower', fix: 600 },
      'hob_oven'            => { t: 'hob_oven', fix: 600, app: [600, 600, 900] },
      'hob'                 => { t: 'hob', flex: [600, 600, 900] },
      'oven_base'           => { t: 'oven', fix: 600, app: [600, 600, 900] },
      'sink'                => { t: 'sink', flex: [600, 800, 1000] },
      'dishwasher'          => { t: 'dishwasher', fix: 600, app: [450, 600, 600] },
      'washing_machine'     => { t: 'washer', fix: 600, app: [450, 600, 700] },
      'drawers'             => { t: 'drawers3', flex: [400, 600, 900] },
      'doors'               => { t: 'doors', flex: [300, 600, 1000] },
      'pullout_narrow'      => { t: 'mech:SPICE_PULLOUT', flex: [150, 200, 300] },
      'open_shelves'        => { t: 'open', flex: [300, 400, 900] }
    }.freeze
    UPPERS = { 'doors' => 'doors', 'none' => 'none', 'hood' => 'hood', 'dish_rack' => 'mech:DISH_RACK', 'glass' => 'glass', 'open' => 'open', 'flap' => 'flap' }.freeze

    PROMPT = <<~TXT
      You read pictures for a kitchen cabinet maker. Answer with ONE JSON object only (no markdown, no comments).

      IMAGE "SITE": a photo, hand sketch, SketchUp or CAD drawing of the place where the kitchen goes, with dimensions written on it
      (printed, typed or HANDWRITTEN, Arabic or Western digits, with or without a unit).
      IMAGE "DESIGN" (may be absent): a render / photo / drawing of the kitchen the client wants.

      YOUR FIRST JOB is to UNDERSTAND THE ROOM from its dimensions - you do not design anything and you do not compute anything.
      Describe the room in "site.room" (the other "site" fields may stay null):
       "room": {
        "view": "plan"|"perspective"|"elevation"|"sketch",
        "type": "single_wall"|"two_wall"|"L"|"U"|"parallel"|"peninsula"|"island"|"irregular",
        "unit": "mm"|"cm"|"m"|null,                  // the unit the drawing uses, null when not written anywhere
        "walls": [ { "id": "W1", "label": "left"|"main"|"right"|"back"|string, "open": false,
                     "angle_to_next": 90,                // inside corner angle to the NEXT wall in the list (90 = square corner)
                     "next": "W2"|null,                   // null = not connected to another wall (e.g. two parallel walls)
                     "px": [[x,y],[x,y]]|null } ],        // the wall line in image pixels (plan / elevation drawings)
                   // list the walls in order walking around the room with the room on your RIGHT (seen from inside: left wall, then main wall, then right wall).
                   // A side with no wall (open to another space) is a wall with "open": true.
        "openings": [ { "id": "O1", "wall": "W2", "type": "window"|"door"|"opening" } ],
        "dimensions": [ { "id": "D1", "text": "exactly as written", "value": number|null, "unit": "mm"|"cm"|"m"|null,
                          "kind": "wall_overall"|"segment"|"opening_width"|"opening_offset"|"opening_offset_end"|"opening_height"|"sill"|"above"|"ceiling"|"wall_distance",
                          "target": "W1"|"O1"|["W1","W2"]|null,   // the wall / opening it measures; null if you cannot tell
                          "chain": "C1"|null, "order": 0,           // pieces of one dimension chain along a wall, in order from the start of the wall
                          "handwritten": true|false, "confidence": 0.0-1.0,
                          "px": [[x,y],[x,y]]|null } ],             // end points of the dimension line in image pixels
        "ambiguities": [ "what you could not decide" ]
       }
      Dimension rules:
      - One entry per written dimension. Never invent a number, never add numbers up, never convert units yourself.
      - "wall_overall" = the whole length of a wall. "segment" = a piece of a chain along a wall. "opening_width" = the width of an opening
        (also when it is a piece of a chain, e.g. 2600 + 800 + 2600: segment, opening_width, segment with the same chain id).
        "opening_offset" = wall start to the opening, "opening_offset_end" = opening to the wall end, "opening_height" = height of the opening,
        "sill" = floor to the bottom of the opening, "above" = top of the opening to the ceiling, "ceiling" = floor to ceiling,
        "wall_distance" = clear distance between two walls (target = both walls) or the depth of the room in front of a single wall.
      - Handwriting you are not sure about: give your best reading with a LOW confidence; never hide a dimension because it is hard to read.

      Rules:
      - Copy every written dimension EXACTLY as written. Never invent a dimension that is not written. Use null when it is not written.
      - "unit" is the unit of the written numbers: "mm", "cm" or "m" (a kitchen wall is normally 2-7 m long: 500 means cm, 5000 means mm, 5.0 means m).
      - Left / right are as seen in the picture.
      - If the SITE picture shows ONE wall from the front (photo or elevation) use "view":"elevation". If it is a top view of the room use "view":"plan".
      - If it is a PERSPECTIVE view of a room showing two or more walls meeting at corners use "view":"perspective" and describe EVERY visible wall in "walls".
        Never merge two walls into one elevation.

      JSON shape:
      {
       "site": {
        "view": "elevation" | "plan" | "perspective",
        "walls": [ { "name": "left"|"main"|"right", "length": number|null, "chain": [numbers]|null } ]|null, // perspective only, in picture order from LEFT to RIGHT
        "unit": "mm" | "cm" | "m",
        "wall_length": number|null,            // elevation: full length of the wall
        "ceiling_height": number|null,
        "corners": [[x,y],...]|null,           // plan only: room corners in order, in the written unit, first corner [0,0]
        "kitchen_wall": integer|null,          // plan only: index of the wall (edge from corner i to i+1) the kitchen stands on, if it is clear
        "openings": [ { "type": "window"|"door", "wall": integer|null, "left": number|null, "width": number|null, "right": number|null,
                        "sill": number|null, "height": number|null, "above": number|null } ],
        "services": [ { "kind": "elec"|"water"|"drain"|"gas", "x_fraction": number, "z_fraction": number } ],
        "written_numbers": [numbers you saw],
        "notes": [strings]
       },
       "design": null | {
        "layout": "straight"|"L"|"U"|"parallel"|"island",
        "units": [ { "type": TYPE, "rel_width": number, "upper": UPPER, "width_mm": number|null } ],
        "fronts_color": "#rrggbb"|null, "worktop": string|null, "notes": [strings]
       }
      }
      "walls" (perspective): "length" = the written overall length of that wall, "chain" = the written pieces along that wall from its left end (for example 2600, 800, 2600) when the wall is dimensioned in pieces.
      "openings" (perspective): "wall" = the NAME of the wall it is in; "left"/"width"/"right" along that wall; "sill" = floor to the bottom of the opening; "above" = top of the opening to the ceiling.
      "openings" (elevation): "left" = distance from the LEFT end of the wall to the opening, "right" = from the opening to the RIGHT end, "sill" = floor to the bottom of the window.
      "openings" (plan): "wall" = index of the wall edge, "left" = distance from corner i (the start of that edge) to the opening, "right" = from the opening to corner i+1.
      "corners" (plan): x grows to the right and y grows UP as seen in the picture.
      "services": only points you can SEE (sockets, water outlets, drain holes, gas). x_fraction = horizontal position along the wall, 0 = left end, 1 = right end.
      z_fraction = height above the floor divided by the ceiling height (0 = floor). These are estimates.
      "design.units": every floor-standing unit of the MAIN run, in order from LEFT to RIGHT, one entry per cabinet / appliance.
      TYPE is one of: "fridge", "fridge_side_by_side", "tall_pantry", "tall_oven", "tall_oven_microwave", "hob_oven" (oven under a hob), "hob", "oven_base",
      "sink", "dishwasher", "washing_machine", "drawers", "doors", "pullout_narrow", "open_shelves".
      IMPORTANT classification rule: use "tall_pantry" ONLY when the image clearly shows a full-height pantry/tall storage cabinet. A normal 600 mm floor cabinet is "doors" or "drawers" (unless the image clearly shows an appliance/mechanism).
      "rel_width" = width of the unit divided by the whole run length (all rel_width add up to about 1).
      The run fitter is allowed to widen ordinary cabinet units to consume real available run space; do not create a 50 mm filler merely because the pictured cabinet is approximately 600 mm if that 50 mm can be absorbed by the ordinary cabinet within its engineering range.
      "width_mm" = the real width of that unit / appliance in millimetres ONLY when it is written on an image, otherwise null.
      UPPER = what hangs on the wall above that unit: "doors", "none" (nothing / a window), "hood", "dish_rack", "glass", "open", "flap". Use "none" for tall units.
    TXT

    class << self
      attr_accessor :transport # test hook: ->(url, headers, body) { |status, text| ... }
    end

    # ---------------------------------------------------------------------------------------------------------------- settings
    def read(key, default = '')
      Sketchup.read_default(PREF, key, default).to_s
    rescue StandardError
      default
    end

    def settings
      prov = read('vision_provider', 'openai')
      prov = 'openai' unless PROVIDERS.key?(prov)
      d = PROVIDERS[prov]
      model = read("vision_model_#{prov}")
      base = read("vision_base_#{prov}")
      { 'provider' => prov, 'model' => model.empty? ? d['model'] : model, 'base' => base.empty? ? d['base'] : base, 'has_key' => !read("vision_key_#{prov}").empty?,
        'providers' => PROVIDERS.map { |k, v| { 'id' => k, 'label' => v['label'], 'model' => v['model'], 'base' => v['base'] } } }
    end

    # the key is written only when a non-empty one is given; it is never sent back to the dialog
    def save_settings(h)
      prov = h['provider'].to_s
      raise 'VISION_PROVIDER_UNKNOWN' unless PROVIDERS.key?(prov)

      Sketchup.write_default(PREF, 'vision_provider', prov)
      Sketchup.write_default(PREF, "vision_model_#{prov}", h['model'].to_s.strip) if h.key?('model')
      Sketchup.write_default(PREF, "vision_base_#{prov}", h['base'].to_s.strip.sub(%r{/+\z}, '')) if h.key?('base')
      Sketchup.write_default(PREF, "vision_key_#{prov}", h['key'].to_s.strip) unless h['key'].to_s.strip.empty?
      Sketchup.write_default(PREF, "vision_key_#{prov}", '') if h['clear_key'] == true
      settings
    end

    # ---------------------------------------------------------------------------------------------------------------- request
    def image_part(path)
      raise "VISION_IMAGE_MISSING: #{path}" unless path && File.file?(path)

      bytes = File.binread(path)
      raise 'VISION_IMAGE_TOO_LARGE: the image is larger than 8 MB.' if bytes.size > MAX_IMAGE

      mime = case File.extname(path).downcase
             when '.png' then 'image/png'
             when '.webp' then 'image/webp'
             else 'image/jpeg'
             end
      [mime, Base64.strict_encode64(bytes)]
    end

    def build_request(site_path, design_path, st = settings)
      prov = st['provider']
      key = read("vision_key_#{prov}")
      raise 'VISION_KEY_MISSING: enter the API key of your AI provider first (it is stored on this computer only).' if key.empty?
      raise 'VISION_MODEL_MISSING: enter the model name of your AI provider.' if st['model'].to_s.empty?
      raise 'VISION_URL_MISSING: enter the base URL of your OpenAI-compatible provider.' if st['base'].to_s.empty?

      images = [['SITE', image_part(site_path)]]
      images << ['DESIGN', image_part(design_path)] if design_path
      intro = design_path ? 'Two images follow: first SITE, then DESIGN.' : 'One image follows: SITE. There is no DESIGN image ("design": null).'
      if PROVIDERS[prov]['api'] == 'gemini'
        parts = [{ 'text' => intro }]
        images.each { |label, (mime, b64)| parts << { 'text' => "IMAGE \"#{label}\":" } << { 'inline_data' => { 'mime_type' => mime, 'data' => b64 } } }
        body = { 'systemInstruction' => { 'parts' => [{ 'text' => PROMPT }] }, 'contents' => [{ 'role' => 'user', 'parts' => parts }],
                 'generationConfig' => { 'responseMimeType' => 'application/json' } }
        { 'url' => "#{st['base']}/models/#{st['model']}:generateContent", 'headers' => { 'Content-Type' => 'application/json', 'x-goog-api-key' => key }, 'body' => JSON.generate(body), 'api' => 'gemini' }
      else
        content = [{ 'type' => 'text', 'text' => intro }]
        images.each { |label, (mime, b64)| content << { 'type' => 'text', 'text' => "IMAGE \"#{label}\":" } << { 'type' => 'image_url', 'image_url' => { 'url' => "data:#{mime};base64,#{b64}" } } }
        body = { 'model' => st['model'], 'messages' => [{ 'role' => 'system', 'content' => PROMPT }, { 'role' => 'user', 'content' => content }] }
        body['response_format'] = { 'type' => 'json_object' } if prov == 'openai'
        { 'url' => "#{st['base']}/chat/completions", 'headers' => { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{key}" }, 'body' => JSON.generate(body), 'api' => 'openai' }
      end
    end

    def post(req, &done)
      return AssistantVision.transport.call(req['url'], req['headers'], req['body'], &done) if AssistantVision.transport

      r = Sketchup::Http::Request.new(req['url'], Sketchup::Http::POST)
      r.headers = req['headers']
      r.body = req['body']
      (@pending ||= []) << r # keep it alive until the answer arrives
      r.start do |request, response|
        @pending.delete(request)
        done.call(response.status_code, response.body.to_s)
      end
    end

    # provider answer -> the JSON object the model wrote
    def extract(api, status, text)
      data = begin
        JSON.parse(text.to_s.dup.force_encoding('UTF-8'))
      rescue JSON::ParserError
        nil
      end
      err = data.is_a?(Hash) && data['error']
      if status.to_i != 200 || err
        msg = err.is_a?(Hash) ? err['message'] : (err || text.to_s[0, 200])
        raise "VISION_PROVIDER_ERROR (HTTP #{status}): #{msg}"
      end
      out = if api == 'gemini'
              Array(data.dig('candidates', 0, 'content', 'parts')).map { |p| p['text'].to_s }.join
            else
              c = data.dig('choices', 0, 'message', 'content')
              c.is_a?(Array) ? c.map { |p| p['text'].to_s }.join : c.to_s
            end
      json = out[/\{.*\}/m]
      raise 'VISION_NO_JSON: the AI provider did not return the expected JSON answer.' unless json

      JSON.parse(json)
    rescue JSON::ParserError
      raise 'VISION_BAD_JSON: the AI provider returned an answer that is not valid JSON. Try again.'
    end

    # Runs the analysis; the block gets { 'ok' => true, 'read' => normalised } or { 'ok' => false, 'message' => }.
    def analyze(site_path, design_path)
      req = build_request(site_path, design_path)
      post(req) do |status, text|
        res = begin
          { 'ok' => true, 'read' => normalize(extract(req['api'], status, text)) }
        rescue StandardError => e
          Diag.log('vision', {}, error: e) if defined?(Diag)
          { 'ok' => false, 'message' => e.message }
        end
        yield res
      end
    end

    # ---------------------------------------------------------------------------------------------------------------- normalise + cross-check
    def num(v)
      v.is_a?(Numeric) ? v.to_f : (v.to_s =~ /\A\s*-?\d+(\.\d+)?\s*\z/ ? v.to_f : nil)
    end

    def unit_factor(unit, sample)
      case unit.to_s.downcase
      when 'mm' then 1.0
      when 'cm' then 10.0
      when 'm' then 1000.0
      else
        s = sample.to_f
        s < 30 ? 1000.0 : (s < 1500 ? 10.0 : 1.0)
      end
    end

    # -> { 'site' => { view, wall, ceiling, corners, kitchen_wall, openings:[{type, wall, off, w, sill, h, src:{field=>'written'|'derived'|'assumed'}}], services, notes },
    #      'design' => { layout, units }, 'problems' => [..], 'unit' => 'cm' }      (all lengths in mm)
    def normalize(raw)
      site = raw['site'] || {}
      if site['room'].is_a?(Hash) # dimension-first room read
        design, dnotes = normalize_design(raw)
        return { 'unit' => site['room']['unit'].to_s, 'problems' => [], 'mock' => site['room']['source'].to_s.upcase == 'MOCK',
                 'site' => { 'view' => 'room', 'room' => site['room'], 'openings' => [], 'services' => [], 'written' => [], 'notes' => Array(site['notes']).map(&:to_s) + dnotes }, 'design' => design }
      end
      problems = []
      notes = Array(site['notes']).map(&:to_s)
      wall = num(site['wall_length'])
      corners = site['corners'].is_a?(Array) ? site['corners'].map { |p| [num(p[0]), num(p[1])] } : nil
      corners = nil if corners && (corners.size < 3 || corners.flatten.any?(&:nil?))
      pwalls = site['view'].to_s == 'perspective' && site['walls'].is_a?(Array) ? site['walls'].select { |w| w.is_a?(Hash) } : nil
      view = site['view'].to_s == 'plan' && corners ? 'plan' : (pwalls && pwalls.any? ? 'perspective' : 'elevation')
      sample = view == 'plan' ? corners.flatten.map(&:abs).max : (view == 'perspective' ? pwalls.flat_map { |w| [num(w['length'])] + Array(w['chain']).map { |c| num(c) } }.compact.max : wall)
      k = unit_factor(site['unit'], sample)
      mm = ->(v) { n = num(v); n && (n * k).round(1) }
      wall_mm = mm.call(wall)
      corners_mm = corners && corners.map { |x, y| [(x * k).round(1), (y * k).round(1)] }
      walls_mm = (pwalls || []).map do |w|
        len = mm.call(w['length'])
        chain = Array(w['chain']).map { |c| mm.call(c) }
        chain = nil if chain.empty? || chain.any?(&:nil?)
        csum = chain && chain.sum.round(1)
        problems << { 'code' => 'DIMENSIONS_DO_NOT_ADD_UP', 'message' => "wall #{w['name']}: written #{len.round} mm but its pieces add up to #{csum.round} mm" } if len && csum && (len - csum).abs > 1
        { 'name' => w['name'].to_s, 'len' => len || csum, 'chain' => chain, 'src' => len ? 'written' : (csum ? 'chain' : nil) }
      end
      if view == 'elevation'
        if wall_mm.nil? then problems << { 'code' => 'WALL_LENGTH_NOT_WRITTEN', 'message' => 'The wall length is not written on the site image: type it.' }
        elsif wall_mm < 1200 || wall_mm > 12_000 then problems << { 'code' => 'WALL_LENGTH_SUSPECT', 'message' => "Wall length #{wall_mm.round} mm looks wrong: check the unit / the number." }
        end
      end
      wall_len_of = lambda do |idx|
        if view == 'perspective'
          ww = walls_mm.find { |x| x['name'] == idx.to_s } || walls_mm.max_by { |x| x['len'].to_f }
          next ww && ww['len']
        end
        next wall_mm if view == 'elevation' || idx.nil?

        a = corners_mm[idx % corners_mm.size]
        b = corners_mm[(idx + 1) % corners_mm.size]
        Math.hypot(b[0] - a[0], b[1] - a[1])
      end
      openings = Array(site['openings']).map do |o|
        wl = wall_len_of.call(o['wall'])
        l = mm.call(o['left'])
        w = mm.call(o['width'])
        r = mm.call(o['right'])
        src = {}
        src['off'] = l ? 'written' : nil
        src['w'] = w ? 'written' : nil
        if wl
          if l && r && w.nil?
            w = (wl - l - r).round(1)
            src['w'] = 'derived'
          elsif l.nil? && w && r
            l = (wl - w - r).round(1)
            src['off'] = 'derived'
          elsif l && w && r && (l + w + r - wl).abs > [wl * 0.02, 30].max
            problems << { 'code' => 'DIMENSIONS_DO_NOT_ADD_UP', 'message' => "#{o['type']}: #{l.round} + #{w.round} + #{r.round} = #{(l + w + r).round} mm but the wall is #{wl.round} mm." }
          end
        end
        if l.nil? || w.nil? || w <= 0
          problems << { 'code' => 'OPENING_INCOMPLETE', 'message' => "#{o['type']}: its position or width is not written on the image: type it." }
        end
        type = o['type'].to_s == 'door' ? 'door' : 'window'
        sill = mm.call(o['sill'])
        src['sill'] = sill ? 'written' : 'assumed'
        sill ||= type == 'door' ? 0.0 : 1000.0
        h = mm.call(o['height'])
        above = mm.call(o['above'])
        cm = mm.call(site['ceiling_height'])
        if cm && above && h && !o['sill'] # floor-to-opening not written but ceiling - head - height is
          sill = (cm - above - h).round(1)
          src['sill'] = 'derived'
        end
        src['h'] = h ? 'written' : 'assumed'
        h ||= type == 'door' ? 2100.0 : 1200.0
        if cm && above.nil? && h && sill
          above = (cm - sill - h).round(1)
        elsif cm && above && h && sill && (sill + h + above - cm).abs > 1
          problems << { 'code' => 'DIMENSIONS_DO_NOT_ADD_UP', 'message' => "#{type}: sill #{sill.round} + height #{h.round} + above #{above.round} = #{(sill + h + above).round} mm but the ceiling is #{cm.round} mm" }
        end
        { 'type' => type, 'wall' => o['wall'], 'off' => l, 'w' => w, 'sill' => sill, 'h' => h, 'above' => above, 'src' => src }
      end
      ceiling = mm.call(site['ceiling_height'])
      zref = ceiling || 2700.0
      services = Array(site['services']).filter_map do |s|
        xf = num(s['x_fraction'])
        zf = num(s['z_fraction'])
        next unless xf && zf && wall_mm && %w[elec water drain gas].include?(s['kind'].to_s)

        { 'kind' => s['kind'] == 'water' ? 'water_cold' : s['kind'].to_s, 'off' => (xf.clamp(0.0, 1.0) * wall_mm).round(-1), 'z' => (zf.clamp(0.0, 1.0) * zref).round(-1), 'estimated' => true }
      end
      design, dnotes = normalize_design(raw)
      notes.concat(dnotes)
      { 'unit' => site['unit'].to_s, 'problems' => problems,
        'site' => { 'view' => view, 'walls' => walls_mm, 'wall' => view == 'perspective' ? (walls_mm.max_by { |x| x['len'].to_f } || {})['len'] : wall_mm, 'ceiling' => ceiling, 'corners' => corners_mm, 'kitchen_wall' => site['kitchen_wall'], 'openings' => openings, 'services' => services,
                    'written' => Array(site['written_numbers']), 'notes' => notes },
        'design' => design }
    end

    def normalize_design(raw)
      notes = []
      design = raw['design'].is_a?(Hash) ? raw['design'] : nil
      units = design ? Array(design['units']).filter_map do |u|
        next unless UNITS.key?(u['type'].to_s)

        d = UNITS[u['type'].to_s]
        h = { 'type' => u['type'].to_s, 'rel' => [num(u['rel_width']).to_f, 0.01].max, 'upper' => UPPERS.key?(u['upper'].to_s) ? u['upper'].to_s : 'doors' }
        if d[:app] # an appliance: its REAL width decides the layout - written on the image, else the generic size until the user types the real one
          wr = num(u['width_mm'])
          h['app'] = true
          h['w'] = (wr && wr.between?(d[:app][0], d[:app][2]) ? wr : d[:app][1]).to_f
          h['w_src'] = wr && wr.between?(d[:app][0], d[:app][2]) ? 'written' : 'assumed'
        end
        h
      end : []
      skipped = design ? Array(design['units']).size - units.size : 0
      notes << "#{skipped} design unit(s) of an unknown type were ignored." if skipped.positive?
      [design && { 'layout' => %w[straight L U parallel island].include?(design['layout'].to_s) ? design['layout'].to_s : 'straight', 'units' => units,
                   'fronts_color' => design['fronts_color'], 'worktop' => design['worktop'], 'notes' => Array(design['notes']).map(&:to_s) }, notes]
    end

    # ---------------------------------------------------------------------------------------------------------------- into the constraint model
    WALL_IDS = ('A'..'Z').to_a.freeze

    # read: normalised result (possibly corrected by the user in the dialog). confirmed: the user ticked "I checked these dimensions".
    def apply(read, proj, confirmed: false, paths: {})
      site = read['site']
      st = confirmed ? Assistant::CONFIRMED : Assistant::INFERRED
      %w[openings services columns].each { |k| proj[k].reject! { |e| e['src'] == 'vision' } }
      flip = ->(o) { o } # opening as stored (wall index + offset from the wall start)
      if site['view'] == 'room'
        rm = RoomReader.solve(site['room'])
        rm['poly'].size >= 3 ? RoomModel.apply(rm, proj) : proj['room_model'] = rm
        proj['vision'] = { 'at' => Time.now.to_i, 'wall' => rm['main_wall'], 'view' => 'room', 'site_image' => paths['site'], 'design_image' => paths['design'],
                           'design' => read['design'], 'confirmed' => confirmed, 'assumed' => rm['depth'] ? ["room depth #{rm['depth']['v'].round} mm (only one wall is visible)"] : [], 'mock' => rm['mock'] }
        return proj
      end
      if site['view'] == 'perspective'
        rm = RoomModel.from_vision(read)
        RoomModel.apply(rm, proj)
        proj['openings'].each { |o| o['st'] = Assistant::CONFIRMED if confirmed && o['src'] == 'room_model' }
        proj['vision'] = { 'at' => Time.now.to_i, 'wall' => rm['main_wall'] || 'B', 'view' => 'perspective', 'site_image' => paths['site'], 'design_image' => paths['design'],
                           'design' => read['design'], 'confirmed' => confirmed, 'assumed' => [] }
        return proj
      end
      if site['view'] == 'plan'
        n = site['corners'].size
        reversed = Assistant.signed_area(site['corners']) > 0 # set_room stores the corners clockwise: a reversed list renumbers the walls and mirrors offsets
        Assistant.set_room(proj, site['corners'], st)
        edge = ->(idx) { reversed ? (n - 2 - idx.to_i) % n : idx.to_i }
        wall_id = site['kitchen_wall'] && WALL_IDS[edge.call(site['kitchen_wall'])]
        id_of = ->(idx) { WALL_IDS[edge.call(idx)] }
        if reversed
          flip = lambda do |o|
            w = Assistant.walls(proj).find { |x| x['id'] == id_of.call(o['wall']) }
            o.merge('off' => (w['len'] - o['off'] - o['w']).round(1))
          end
        end
      else
        raise 'VISION_WALL_LENGTH_REQUIRED: type the wall length first.' unless site['wall'].to_f.positive?

        Assistant.room_from_dims(proj, site['wall'].to_f, ROOM_DEPTH_ASSUMED, st)
        wall_id = 'B' # room_from_dims: wall B is the width wall, offsets run left -> right for someone facing it from inside the room
        id_of = ->(_idx) { 'B' }
      end
      Assistant.set_ceiling(proj, site['ceiling'].to_f, st) if site['ceiling'].to_f.positive?
      site['openings'].each do |o|
        next unless o['off'] && o['w'].to_f.positive?

        o = flip.call(o)
        e = Assistant.add_opening(proj, id_of.call(o['wall']), o['type'], o['off'], o['w'], o['h'], o['sill'], st)
        e['src'] = 'vision'
        e['assumed'] = o['src'].select { |_k, v| v == 'assumed' }.keys if o['src'].is_a?(Hash) && o['src'].value?('assumed')
      end
      site['services'].each do |s|
        e = Assistant.add_service(proj, s['kind'], wall_id || 'B', s['off'], s['z'], nil, Assistant::INFERRED) # a position estimated from a picture is never CONFIRMED
        e['src'] = 'vision'
      end
      proj['vision'] = { 'at' => Time.now.to_i, 'wall' => wall_id, 'view' => site['view'], 'site_image' => paths['site'], 'design_image' => paths['design'],
                         'design' => read['design'], 'confirmed' => confirmed,
                         'assumed' => site['view'] == 'elevation' ? ["room depth #{ROOM_DEPTH_ASSUMED.round} mm (only one wall is known)"] : [] }
      proj
    end

    # ---------------------------------------------------------------------------------------------------------------- design units -> run columns
    # Fits the ordered design units to the REAL wall length: appliances keep their real widths, cabinets share what is left in the proportions seen
    # in the design image, on a 50 mm grid inside each type's limits. -> { 'cols' => [...], 'notes' => [...], 'problems' => [...] }
    def fit(units, len, cfg)
      notes = []
      problems = []
      items = units.map do |u|
        d = UNITS[u['type']]
        it = { u: u, d: d }
        aw = d[:app] && u['w'].to_f.positive? ? u['w'].to_f.round : nil
        if aw && !aw.between?(d[:app][0], d[:app][2])
          problems << { 'code' => 'APPLIANCE_SIZE_SUSPECT', 'severity' => 'error', 'message' => "#{u['type']}: width #{aw} mm is outside #{d[:app][0]}-#{d[:app][2]} mm" }
          aw = nil
        end
        if d[:fridge]
          # the housing is sized from the client's real refrigerator (generic record only when its width is the generic one)
          it[:dev] = aw && aw != Catalog.device(d[:dev])[:w] ? "FRIDGE_W#{aw}" : d[:dev]
          it[:w] = Kitchen.fridge_open_min_w(cfg, it[:dev]).ceil(-1).to_f
        elsif d[:fix]
          it[:w] = (aw || d[:fix]).to_f
        end
        it
      end
      fixed = EGC::Num.sum(items.select { |i| i[:w] }) { |i| i[:w] }
      flex = items.reject { |i| i[:w] }
      free = len - fixed
      min_sum = EGC::Num.sum(flex) { |i| i[:d][:flex][0] }
      if free < min_sum - 0.5
        problems << { 'code' => 'DESIGN_DOES_NOT_FIT', 'severity' => 'error',
                      'message' => "the #{units.size} units of the design need at least #{(fixed + min_sum).round} mm but the wall has #{len.round} mm free" }
        return { 'cols' => [], 'notes' => notes, 'problems' => problems }
      end
      rel = EGC::Num.sum(flex) { |i| i[:u]['rel'] }
      flex.each do |i|
        lo, _pref, hi = i[:d][:flex]
        i[:w] = ((free * i[:u]['rel'] / rel) / 50.0).round * 50.0
        i[:w] = i[:w].clamp(lo, hi).to_f
      end
      # hand the rounding / clamping difference to the units that can still take it (widest plain cabinets first)
      # (10 mm at a time, always to the cabinet that is furthest out, so equal cabinets stay equal)
      2000.times do
        diff = len - EGC::Num.sum(items) { |i| i[:w] }
        break if diff.abs < 0.5

        cands = flex.select { |i| diff.positive? ? i[:w] < i[:d][:flex][2] - 0.5 : i[:w] > i[:d][:flex][0] + 0.5 }
        break if cands.empty?

        i = cands.min_by { |c| [%w[doors drawers].include?(c[:u]['type']) ? 0 : 1, diff.positive? ? c[:w] : -c[:w]] }
        step = diff.positive? ? [diff, 10.0, i[:d][:flex][2] - i[:w]].min : [diff, -10.0, i[:d][:flex][0] - i[:w]].max
        i[:w] = (i[:w] + step).round(1)
      end
      left = len - EGC::Num.sum(items) { |i| i[:w] }
      cols = items.map do |i|
        c = { 't' => i[:d][:t], 'w' => i[:w].round(1) }
        c['dev'] = i[:dev] || i[:d][:dev] if i[:dev] || i[:d][:dev]
        up = UPPERS[i[:u]['upper']]
        if up == 'none'
          c['w1'] = 'none'
          c['w2'] = 'none'
        elsif up && up != 'doors'
          c['w1'] = up
        end
        c
      end
      if left > 0.9
        cols << { 't' => 'filler', 'w' => left.round(1) }
        notes << "#{left.round} mm left at the end of the run: closed with a filler"
      elsif left < -0.9
        problems << { 'code' => 'DESIGN_DOES_NOT_FIT', 'severity' => 'error', 'message' => "the design is #{(-left).round} mm longer than the wall" }
      end
      notes << 'unit order and types follow the design image; widths are fitted to the real wall (appliances keep their real size)'
      { 'cols' => cols, 'notes' => notes, 'problems' => problems }
    end
  end
end
