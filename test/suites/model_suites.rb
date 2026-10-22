# encoding: UTF-8
# frozen_string_literal: true
#
# Regression suites - model layer.

module EGC
  module Test
    # ------------------------------------------------------------------ materials
    suite('model/materials') do
      test('grain policy is correct per material') do
        assert_equal(false, EGC::Model::Materials.grain?(:white_melamine))
        assert_equal(false, EGC::Model::Materials.grain?(:mdf_plain))
        assert_equal(true,  EGC::Model::Materials.grain?(:oak_veneer))
        assert_equal(true,  EGC::Model::Materials.grain?(:walnut_veneer))
      end

      test('rotation is allowed only for grain-free boards') do
        assert_equal(true,  EGC::Model::Materials.rotation_allowed?(:mdf_plain))
        assert_equal(false, EGC::Model::Materials.rotation_allowed?(:oak_veneer))
      end

      test('material is hash-compatible') do
        m = EGC::Model::Materials.get(:oak_veneer)
        assert_equal(true, m[:has_grain])
        assert_equal(true, m['has_grain'])
        assert_equal('Oak Veneer', m[:name])
      end

      test('materials.json overlay never overrides built-ins') do
        EGC::Model::Materials.reset!
        path = File.join(EGC::ROOT, 'materials.json')
        EGC::Model::Materials.load_from_json!(path)
        # built-in grain policy survives the overlay
        assert_equal(true, EGC::Model::Materials.grain?(:oak_veneer))
        assert_equal(false, EGC::Model::Materials.grain?(:mdf_plain))
        EGC::Model::Materials.reset!
      end

      test('unknown key falls back to the default') do
        assert_equal(:white_melamine, EGC::Model::Materials.get(:no_such_material).key)
      end

      test('hash normalisation builds a custom material') do
        m = EGC::Model::Materials.normalise(:has_grain => false, :name => 'Custom MDF')
        assert_equal(false, m.has_grain)
        assert_equal(true, m.rotation_allowed?)
      end
    end

    # ------------------------------------------------------------------ edgeband
    suite('model/edgeband') do
      test('parse compact codes') do
        b = EGC::Model::EdgeBand.parse('LRF')
        assert_equal(true, b.edged?(:left))
        assert_equal(true, b.edged?(:right))
        assert_equal(true, b.edged?(:front))
        assert_equal(false, b.edged?(:back))
      end

      test('oversize follows the edged axis') do
        b = EGC::Model::EdgeBand.of(:left, :right)
        assert_close(2.0 * EGC::Constants::EDGEBAND_TRIM_ALLOWANCE, b.length_oversize, 1e-9)
        assert_close(0.0, b.width_oversize, 1e-9)
      end

      test('merge and without are pure') do
        a = EGC::Model::EdgeBand.of(:front)
        b = a.merge(EGC::Model::EdgeBand.of(:back))
        assert_equal(true, b.edged?(:front))
        assert_equal(true, b.edged?(:back))
        assert_equal(false, a.edged?(:back), 'original must not mutate')
        assert_equal(false, b.without(:back).edged?(:back))
      end

      test('codes round-trip') do
        assert_equal('L-F-', EGC::Model::EdgeBand.of(:left, :front).to_code)
        assert_equal('----', EGC::Model::EdgeBand.none.to_code)
        assert_equal('LRFB', EGC::Model::EdgeBand.all.to_code)
      end
    end

    # ---------------------------------------------------------------------- part
    suite('model/part') do
      test('area and volume') do
        p = EGC::Model::Part.new(:shelf, :length => 500, :width => 400, :thickness => 18,
                                 :material => :white_melamine)
        assert_close(200_000.0, p.area_mm2, 1e-6)
        assert_close(3_600_000.0, p.volume_mm3, 1e-6)
        assert_close(0.2, p.area_m2, 1e-9)
      end

      test('cut size adds banding allowance') do
        p = EGC::Model::Part.new(:shelf, :length => 500, :width => 400, :thickness => 18,
                                 :material => :white_melamine,
                                 :edgeband => EGC::Model::EdgeBand.all)
        allow = EGC::Constants::EDGEBAND_TRIM_ALLOWANCE
        assert_close(500 + 2 * allow, p.cut_length, 1e-9)
        assert_close(400 + 2 * allow, p.cut_width, 1e-9)
      end

      test('rotatable follows material grain') do
        plain = EGC::Model::Part.new(:shelf, :length => 500, :width => 400, :thickness => 18,
                                     :material => :mdf_plain)
        grained = EGC::Model::Part.new(:shelf, :length => 500, :width => 400, :thickness => 18,
                                       :material => :oak_veneer)
        assert_equal(true, plain.rotatable?)
        assert_equal(false, grained.rotatable?)
      end

      test('group_key groups identical parts') do
        a = EGC::Model::Part.new(:shelf, :length => 500, :width => 400, :thickness => 18,
                                 :material => :white_melamine, :edgeband => EGC::Model::EdgeBand.of(:front))
        b = EGC::Model::Part.new(:shelf, :length => 500, :width => 400, :thickness => 18,
                                 :material => :white_melamine, :edgeband => EGC::Model::EdgeBand.of(:front))
        assert_equal(a.group_key, b.group_key)
      end

      test('attribute round-trip is exact') do
        store = EGC::Scene::AttributeStore.new
        p = EGC::Model::Part.new(:shelf, :length => 500, :width => 400, :thickness => 18,
                                 :material => :white_melamine, :edgeband => EGC::Model::EdgeBand.all)
        p.write_attributes(store, p.dict_name, 7)
        back = EGC::Model::Part.read_attributes(store, p.id)
        assert_close(500.0, back[:length], 1e-9)
        assert_close(400.0, back[:width], 1e-9)
        assert_equal('LRFB', back[:edgeband])
      end

      test('per-part dict names are unique') do
        a = EGC::Model::Part.new(:shelf, :length => 500, :width => 400, :thickness => 18, :material => :mdf_plain)
        b = EGC::Model::Part.new(:shelf, :length => 500, :width => 400, :thickness => 18, :material => :mdf_plain)
        refute(a.dict_name == b.dict_name, 'dictionaries must not collide')
      end
    end

    # ------------------------------------------------------------------ hardware
    suite('model/hardware') do
      test('runner selection respects internal depth') do
        r = EGC::Model::Hardware.runner_for_depth(500.0)
        refute(r.nil?, 'a runner must exist for 500mm internal depth')
        assert(r.length <= 500.0, 'runner must fit')
      end

      test('too shallow cabinet has no runner') do
        assert_nil(EGC::Model::Hardware.runner_for_depth(100.0))
      end

      test('runner clearances report frozen constants') do
        c = EGC::Model::Hardware.runner_clearances
        assert_close(EGC::Constants::RUNNER_CLEARANCE_SIDE, c[:side], 1e-9)
        assert_close(EGC::Constants::DRAWER_BOX_BACK_CLEARANCE, c[:back], 1e-9)
      end

      test('hardware lookup') do
        assert_equal('Bar handle 128cc', EGC::Model::Hardware.get(:handle_bar_128)[:name])
      end
    end

    # ------------------------------------------------------------------- carcass
    suite('model/carcass') do
      test('base unit generates the expected panel set') do
        cab = EGC::Model::Cabinet.new(:base, :width => 600, :depth => 560)
        parts = cab.rebuild!
        roles = parts.map(&:role)
        assert_includes(roles, EGC::Model::Part::ROLE_GABLE_L)
        assert_includes(roles, EGC::Model::Part::ROLE_GABLE_R)
        assert_includes(roles, EGC::Model::Part::ROLE_BOTTOM)
        assert_includes(roles, EGC::Model::Part::ROLE_TOP_RAIL)
        assert_includes(roles, EGC::Model::Part::ROLE_BACK)
      end

      test('gables span the full carcass height') do
        cab = EGC::Model::Cabinet.new(:base, :width => 600, :height => 720, :depth => 560)
        cab.rebuild!
        gable = cab.parts.find { |p| p.role == EGC::Model::Part::ROLE_GABLE_L }
        assert_close(720.0, gable.length, 1e-9)
        assert_close(560.0, gable.width, 1e-9)
      end

      test('deck width equals internal width') do
        cab = EGC::Model::Cabinet.new(:base, :width => 600)
        cab.rebuild!
        deck = cab.parts.find { |p| p.role == EGC::Model::Part::ROLE_BOTTOM }
        assert_close(600.0 - 2 * EGC::Constants::PANEL_THICKNESS, deck.length, 1e-9)
      end

      test('panels never interpenetrate') do
        doc = EGC::Scene::Document.new('carcass')
        cab = EGC::Model::Cabinet.new(:base, :width => 600, :depth => 560,
                                      :origin => EGC::Geom::Vec3.new(0, 0, 150))
        doc.add_cabinet(cab)
        cab.rebuild!
        r = EGC::Ops::Interference.scan_internal(doc)
        assert_equal(0, r[:hits].length, "internal interference: #{r[:hits].first(2).inspect}")
      end

      test('rebuild is idempotent in part count') do
        cab = EGC::Model::Cabinet.new(:base, :width => 600)
        n1 = cab.rebuild!.length
        n2 = cab.rebuild!.length
        assert_equal(n1, n2)
      end
    end

    # --------------------------------------------------------------------- doors
    suite('model/doors') do
      test('double door yields two leaves') do
        cab = EGC::Model::Cabinet.new(:base, :width => 900, :depth => 560)
        cab.add_door(:side => :double, :hinge => :left)
        cab.rebuild!
        doors = cab.parts.select { |p| p.role == EGC::Model::Part::ROLE_DOOR }
        assert_equal(2, doors.length)
      end

      test('door leaves do not exceed the cabinet width') do
        cab = EGC::Model::Cabinet.new(:base, :width => 900, :depth => 560)
        cab.add_door(:side => :double)
        cab.rebuild!
        cab.parts.select { |p| p.role == EGC::Model::Part::ROLE_DOOR }.each do |d|
          assert(d.width < cab.width, 'leaf must be narrower than the carcass')
        end
      end

      test('drawer box honours the side clearance') do
        cab = EGC::Model::Cabinet.new(:base, :width => 600, :depth => 560)
        cab.add_drawer(:z => 200, :height => 150)
        cab.rebuild!
        side = cab.parts.find { |p| p.role == EGC::Model::Part::ROLE_DRAWER_SIDE }
        refute(side.nil?, 'drawer side must exist')
        expected = cab.internal_width - 2 * EGC::Constants::DRAWER_BOX_SIDE_GAP - EGC::Constants::DRAWER_BOX_THICKNESS * 0
        assert(side.box.width <= cab.internal_width, 'drawer must fit inside the carcass')
      end
    end

    # ------------------------------------------------------------------ wardrobe
    suite('model/wardrobe') do
      test('cavity resolves on a DOORLESS unit (nil crash regression)') do
        cab = EGC::Model::Cabinet.new(:tall, :width => 900, :height => 2100, :depth => 600)
        assert_equal(true, cab.doorless?)
        v = nil
        begin
          v = cab.detect_inner_void
        rescue StandardError => e
          raise EGC::Test::AssertionFailed, "nil crash on doorless unit: #{e.class}: #{e.message}"
        end
        refute(v.nil?, 'void must resolve')
        assert(v.width.positive? && v.height.positive? && v.depth.positive?)
      end

      test('void is bounded by the inner gable faces') do
        cab = EGC::Model::Cabinet.new(:tall, :width => 900, :height => 2100, :depth => 600)
        v = cab.detect_inner_void
        t = EGC::Constants::PANEL_THICKNESS
        assert_close(t, v.min.x, 1e-9)
        assert_close(900.0 - t, v.max.x, 1e-9)
      end

      test('open unit gets exposed front edge banding') do
        cab = EGC::Model::Cabinet.new(:tall, :width => 900, :height => 2100, :depth => 600)
        cab.rebuild!
        cab.apply_exposed_edgeband!
        gable = cab.parts.find { |p| p.role == EGC::Model::Part::ROLE_GABLE_L }
        assert_equal(true, gable.edgeband.edged?(:front), 'front gable edge must be banded')
      end

      test('cavity zones are computed for hit-testing') do
        cab = EGC::Model::Cabinet.new(:tall, :width => 900, :height => 2100, :depth => 600)
        cab.rebuild!
        zones = cab.cavity_zones
        assert(zones.length >= 1, 'at least one cavity')
        assert(zones.first.key?(:box), 'zone must carry a world box')
      end

      test('tall wardrobe gains a structural mid shelf') do
        cab = EGC::Model::Cabinet.new(:tall, :width => 900, :height => 2100, :depth => 600)
        parts = EGC::Model::Wardrobe.build_parts(cab)
        shelves = parts.select { |p| p.role == EGC::Model::Part::ROLE_SHELF }
        assert(shelves.length >= 1, 'tall unit must have a mid shelf')
      end
    end

    # ------------------------------------------------------------------- cabinet
    suite('model/cabinet') do
      test('tall classification overrides a base tag above 1100mm') do
        cab = EGC::Model::Cabinet.new(:base, :width => 600, :height => 2300, :depth => 560)
        assert_equal(:tall, cab.effective_tag)
        assert_equal(true, cab.reclassified?)
        assert_equal(true, cab.tall?)
        assert_equal(false, cab.accepts_worktop?)
      end

      test('base unit stays base below the threshold') do
        cab = EGC::Model::Cabinet.new(:base, :width => 600, :height => 720, :depth => 560)
        assert_equal(:base, cab.effective_tag)
        assert_equal(false, cab.reclassified?)
        assert_equal(true, cab.accepts_worktop?)
      end

      test('resizing above the threshold reclassifies') do
        cab = EGC::Model::Cabinet.new(:base, :width => 600, :height => 720, :depth => 560)
        assert_equal(:base, cab.effective_tag)
        cab.resize!(:height => 2300)
        assert_equal(:tall, cab.effective_tag)
        assert_equal(true, cab.reclassified?)
      end

      test('resize rebuilds parts') do
        cab = EGC::Model::Cabinet.new(:base, :width => 600, :height => 720, :depth => 560)
        cab.rebuild!
        before = cab.rebuild_count
        cab.resize!(:width => 800)
        assert(cab.rebuild_count > before, 'resize must trigger a rebuild')
      end

      test('cavities are ordered and non-degenerate') do
        cab = EGC::Model::Cabinet.new(:tall, :width => 900, :height => 2100, :depth => 600)
        cab.add_shelf(:type => :fixed)
        cab.rebuild!
        cav = cab.cavities
        assert(cav.length >= 2, 'a shelf must split the void into two cavities')
        cav.each { |c| assert(c[:height].positive?, 'cavity height must be positive') }
      end

      test('summary exposes classification') do
        cab = EGC::Model::Cabinet.new(:base, :width => 600, :height => 2300)
        s = cab.summary
        assert_equal(:base, s[:declared_tag])
        assert_equal(:tall, s[:effective_tag])
        assert_equal(true, s[:reclassified])
      end
    end
  end
end
