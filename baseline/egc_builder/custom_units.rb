# frozen_string_literal: true

require 'json'

module EGC
  # Native custom units. A custom unit is a registered TEMPLATE of the native E.G.C unit model (kind, W/H/D, internal zones). Placing it goes
  # through the same Kitchen.place_unit / Cabinet.build path as every library unit, so it takes part in Edit, Move, Snap, Resize, Replace,
  # the Internal Organizer, pricing, cut list, nesting, labels, hardware, drawings and production data. There is no separate custom logic.
  module CustomUnits
    module_function

    KEY = 'custom_units_b64'

    def list
      Config.read_json(KEY, [])
    end

    def save_list(arr)
      Config.write_json(KEY, arr)
    end

    # register the selected native unit as a template
    def register(g, name)
      spec = Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))
      raise 'CUSTOM_UNIT_ERROR: only a native E.G.C unit (not a mechanism unit or an appliance) can be registered.' if spec[:mech] || spec[:kind].nil?
      raise 'CUSTOM_UNIT_ERROR: give the custom unit a name.' if name.to_s.strip.empty?

      cells = (spec[:cells] || []).map { |c| c.transform_keys(&:to_s).transform_values { |v| v.is_a?(Symbol) ? v.to_s : v } }
      id = "CU#{format('%02d', list.size + 1)}"
      item = { 'id' => id, 'name' => name.to_s.strip[0, 40], 'kind' => spec[:kind].to_s, 'w' => spec[:w].to_f, 'h' => spec[:h].to_f, 'd' => spec[:d].to_f, 'cells' => cells,
               'base_type' => spec[:type].to_s, 'created' => Time.now.strftime('%Y-%m-%d') }
      save_list(list.reject { |x| x['name'] == item['name'] } << item)
      item
    end

    def delete(id)
      save_list(list.reject { |x| x['id'] == id.to_s })
    end

    def find(id)
      list.find { |x| x['id'] == id.to_s }
    end

    # placement parameters for Kitchen.place_unit / PlaceTool (native unit hash)
    def params(id, w: nil)
      t = find(id)
      raise "CUSTOM_UNIT_ERROR: custom unit #{id} not found." unless t

      { 'kind' => t['kind'], 'type' => 'custom', 'w' => (w || t['w']).to_f, 'h' => t['h'], 'd' => t['d'], 'cells' => t['cells'], 'custom_id' => t['id'], 'custom_name' => t['name'] }
    end

    def payload
      list.map { |t| t.slice('id', 'name', 'kind', 'w', 'h', 'd', 'created').merge('zones' => t['cells'].size) }
    end
  end
end
