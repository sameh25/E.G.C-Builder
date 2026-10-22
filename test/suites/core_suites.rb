# encoding: UTF-8
# frozen_string_literal: true
#
# Regression suites - core layer.
# Every suite maps 1:1 to a shipped module so a failure names the culprit.

module EGC
  module Test
    SKIP = :__skip

    # ---------------------------------------------------------------- constants
    suite('core/constants') do
      test('frozen manifest is complete and deep-frozen') do
        assert(EGC::Constants::FROZEN.frozen?, 'FROZEN must be frozen')
        EGC::Constants::FROZEN.each_value { |v| assert(v.frozen?, 'constant value must be frozen') }
      end

      test('fingerprint matches the released baseline') do
        assert_equal(EGC::Constants::EXPECTED_FINGERPRINT, EGC::Constants.fingerprint,
                     'dimensional contract drifted')
      end

      test('verify! passes on the shipped values') do
        assert_equal(true, EGC::Constants.verify!)
      end

      test('kerf and border trim keep their exact contractual values') do
        assert_close(4.4,  EGC::Constants::SAW_KERF,    1e-9, 'SAW_KERF must be 4.4')
        assert_close(10.0, EGC::Constants::BORDER_TRIM, 1e-9, 'BORDER_TRIM must be 10.0')
      end

      test('vertical stack is internally consistent') do
        assert_close(900.0, EGC::Constants::STANDARD_COUNTER_HEIGHT, 1e-9)
        assert_close(EGC::Constants::TOE_KICK_HEIGHT + EGC::Constants::BASE_CARCASS_HEIGHT,
                     EGC::Constants::BASE_UNIT_NOMINAL_HEIGHT, 1e-9,
                     'plinth + carcass must equal nominal base height')
        assert_close(EGC::Constants::STANDARD_COUNTER_HEIGHT,
                     EGC::Constants::BASE_UNIT_NOMINAL_HEIGHT + EGC::Constants::COUNTER_THICKNESS,
                     1e-9, 'carcass + worktop must equal counter height')
      end

      test('tall threshold is 1100mm') do
        assert_close(1100.0, EGC::Constants::TALL_UNIT_THRESHOLD, 1e-9)
      end

      test('drill values are untouched') do
        assert_close(35.0, EGC::Constants::DRILL_HINGE_DIAMETER, 1e-9)
        assert_close(13.0, EGC::Constants::DRILL_HINGE_DEPTH, 1e-9)
        assert_close(22.5, EGC::Constants::DRILL_HINGE_EDGE_OFFSET, 1e-9)
        assert_close(5.0,  EGC::Constants::DRILL_SHELF_PIN_DIAMETER, 1e-9)
        assert_close(13.0, EGC::Constants::DRILL_SHELF_PIN_DEPTH, 1e-9)
      end
    end

    # -------------------------------------------------------------------- units
    suite('core/units') do
      test('inch <-> mm round trip') do
        assert_close(25.4, EGC::Units.inch_to_mm(1.0), 1e-9)
        assert_close(1.0,  EGC::Units.mm_to_inch(25.4), 1e-9)
      end

      test('to_mm handles nil and numerics') do
        assert_close(0.0, EGC::Units.to_mm(nil), 1e-9)
        assert_close(12.5, EGC::Units.to_mm(12.5), 1e-9)
      end

      test('fmt_mm trims trailing zeros') do
        assert_equal('600', EGC::Units.fmt_mm(600.0))
        assert_equal('600.5', EGC::Units.fmt_mm(600.5))
      end

      test('area conversion to m2') do
        assert_close(1.0, EGC::Units.m2(1_000_000.0), 1e-9)
      end

      test('clamp bounds') do
        assert_close(5.0, EGC::Units.clamp(9.0, 1.0, 5.0), 1e-9)
        assert_close(1.0, EGC::Units.clamp(-3.0, 1.0, 5.0), 1e-9)
        assert_close(3.0, EGC::Units.clamp(3.0, 1.0, 5.0), 1e-9)
      end
    end

    # -------------------------------------------------------------------- geom
    suite('core/geom') do
      test('Vec3 arithmetic and equality') do
        a = EGC::Geom::Vec3.new(1, 2, 3)
        b = EGC::Geom::Vec3.new(10, 20, 30)
        assert_equal([11.0, 22.0, 33.0], (a + b).to_a)
        assert_equal([-9.0, -18.0, -27.0], (a - b).to_a)
        assert_equal([5.0, 6.0, 7.0], a.offset(4, 4, 4).to_a)
        assert(a == EGC::Geom::Vec3.new(1, 2, 3), 'equality')
      end

      test('Box dimensions and volume') do
        # from_whd(origin, width, height, depth)
        b = EGC::Geom::Box.from_whd(EGC::Geom::Vec3.new(0, 0, 0), 600, 720, 560)
        assert_close(600.0, b.width, 1e-9)
        assert_close(560.0, b.depth, 1e-9)
        assert_close(720.0, b.height, 1e-9)
        assert_close(600.0 * 560 * 720, b.volume, 1e-6)
      end

      test('touching boxes do not overlap') do
        a = EGC::Geom::Box.new(EGC::Geom::Vec3.new(0, 0, 0), EGC::Geom::Vec3.new(10, 10, 10))
        b = EGC::Geom::Box.new(EGC::Geom::Vec3.new(10, 0, 0), EGC::Geom::Vec3.new(20, 10, 10))
        refute(a.overlaps?(b), 'shared face must not count as overlap')
        assert_close(0.0, a.overlap_volume(b), 1e-9)
      end

      test('interpenetrating boxes report overlap volume') do
        a = EGC::Geom::Box.new(EGC::Geom::Vec3.new(0, 0, 0), EGC::Geom::Vec3.new(10, 10, 10))
        b = EGC::Geom::Box.new(EGC::Geom::Vec3.new(5, 0, 0), EGC::Geom::Vec3.new(15, 10, 10))
        assert(a.overlaps?(b))
        assert_close(500.0, a.overlap_volume(b), 1e-6)
      end

      test('Rect fits and splits') do
        r = EGC::Geom::Rect.new(0, 0, 100, 50)
        assert(r.fits?(100, 50), 'exact fit')
        refute(r.fits?(101, 50), 'oversize must not fit')
        left, right = r.split_vertical(40)
        assert_close(40.0, left.right, 1e-9)
        assert_close(60.0, right.w, 1e-9)
        bottom, top = r.split_horizontal(20)
        assert_close(20.0, bottom.top, 1e-9)
        assert_close(30.0, top.h, 1e-9)
      end

      test('box_gap measures face distance') do
        a = EGC::Geom::Box.new(EGC::Geom::Vec3.new(0, 0, 0), EGC::Geom::Vec3.new(10, 10, 10))
        b = EGC::Geom::Box.new(EGC::Geom::Vec3.new(15, 0, 0), EGC::Geom::Vec3.new(25, 10, 10))
        assert_close(5.0, EGC::Geom.box_gap(a, b), 1e-9)
      end

      test('snap_to respects tolerance') do
        assert_close(64.0, EGC::Geom.snap_to(65.0, 32.0, 2.0), 1e-9)
        assert_close(65.0, EGC::Geom.snap_to(65.0, 32.0, 0.5), 1e-9)
      end
    end

    # ------------------------------------------------------------------ logger
    suite('core/logger') do
      test('warnings are captured while auditing') do
        EGC::Log.clear!
        EGC::Log.reset!
        EGC::Log.warn('deliberate test warning')
        assert_equal(1, EGC::Log.warnings.length)
        EGC::Log.stop_audit!
        EGC::Log.clear!
      end

      test('debug records are not warnings') do
        EGC::Log.clear!
        EGC::Log.reset!
        EGC::Log.debug('quiet')
        assert_equal(0, EGC::Log.warnings.length)
        EGC::Log.stop_audit!
        EGC::Log.clear!
      end

      test('check reports warnings produced by a block') do
        EGC::Log.clear!
        EGC::Log.reset!
        _, produced = EGC::Log.check('demo') { EGC::Log.warn('boom') }
        assert_equal(1, produced.length)
        EGC::Log.stop_audit!
        EGC::Log.clear!
      end
    end

    # ------------------------------------------------------------------- scene
    suite('core/scene') do
      test('document tracks cabinets and revision') do
        doc = EGC::Scene::Document.new('scene')
        assert_equal(0, doc.cabinets.length)
        cab = EGC::Model::Cabinet.new(:base, :width => 600)
        doc.add_cabinet(cab)
        assert_equal(1, doc.cabinets.length)
        assert(cab.document.equal?(doc), 'cabinet must be attached')
        assert(doc.revision.positive?, 'revision must advance')
      end

      test('find by id and name') do
        doc = EGC::Scene::Document.new('scene')
        cab = EGC::Model::Cabinet.new(:base, :width => 600, :name => 'Sink Unit')
        doc.add_cabinet(cab)
        assert(doc.find(cab.id).equal?(cab))
        assert(doc.find_by_name('Sink Unit').equal?(cab))
      end

      test('observer notification fires') do
        doc = EGC::Scene::Document.new('scene')
        seen = []
        doc.subscribe { |evt, _payload| seen << evt }
        doc.add_cabinet(EGC::Model::Cabinet.new(:base))
        assert_includes(seen, :cabinet_added)
      end

      test('attribute store round-trips values') do
        s = EGC::Scene::AttributeStore.new
        s.set('D', 'k', 42)
        assert_equal(42, s.get('D', 'k'))
        assert_equal('fallback', s.get('D', 'missing', 'fallback'))
        assert(s.dictionary?('D'))
      end

      test('signature changes when a cabinet is resized') do
        doc = EGC::Scene::Document.new('scene')
        cab = EGC::Model::Cabinet.new(:base, :width => 600)
        doc.add_cabinet(cab)
        cab.rebuild!
        before = doc.signature
        cab.resize!(:width => 800)
        refute(before == doc.signature, 'signature must change after resize')
      end
    end
  end
end
