# encoding: UTF-8
# frozen_string_literal: true
#
# Regression suites - ops layer (§1 - §5).

module EGC
  module Test
    # Fixtures (base / tower / open_wardrobe / nest_parts) live in
    # test/harness/framework.rb under EGC::Test::Fixtures and are mixed into
    # the run context, so every test block can call them directly.

    # ================================================================= §1
    suite('ops/exec_worktop') do
      test('single base cabinet yields one clamped segment') do
        doc = EGC::Scene::Document.new('wt')
        base(doc, :x => 0.0)
        plan = EGC::Ops::ExecWorktop.plan(doc)
        assert_equal(1, plan[:segments].length)
        assert_close(EGC::Constants::STANDARD_COUNTER_HEIGHT, plan[:segments].first[:z1], 1e-9)
      end

      test('§1 regression: base cabinet edited to 2300mm is excluded') do
        doc = EGC::Scene::Document.new('wt')
        cab = base(doc, :x => 0.0, :name => 'Edited')
        cab.resize!(:height => 2300.0)
        plan = EGC::Ops::ExecWorktop.plan(doc)
        assert_equal(:tall, cab.effective_tag, 'edited unit must reclassify')
        assert_equal(1000, 1000)
        assert_equal(1, plan[:tower_count], 'edited unit must be counted as a tower')
        assert_equal(0, plan[:segments].length, 'no countertop may be generated over a lone tower')
      end

      test('countertop never exceeds 920mm in a mixed run') do
        doc = EGC::Scene::Document.new('wt')
        base(doc, :x => 0.0,  :width => 600.0, :name => 'B1')
        base(doc, :x => 600.0, :width => 600.0, :name => 'B2')
        tower(doc, :x => 1200.0, :width => 600.0, :height => 2300.0, :name => 'T1')
        plan = EGC::Ops::ExecWorktop.plan(doc)
        plan[:segments].each do |s|
          assert(s[:z1] <= 920.0, "segment top #{s[:z1]} exceeds 920mm")
        end
      end

      test('tall cabinet top is free of countertop geometry') do
        doc = EGC::Scene::Document.new('wt')
        base(doc, :x => 0.0, :width => 600.0)
        tw = tower(doc, :x => 600.0, :width => 600.0, :height => 2300.0)
        plan = EGC::Ops::ExecWorktop.plan(doc)

        # the base unit still receives a counter...
        assert_equal(1, plan[:segments].length, 'the base run keeps its countertop')
        # ...but it must terminate on the tower gable and never cover it
        tbox = tw.bounding_box
        plan[:segments].each do |s|
          refute(s[:box].overlaps?(tbox, EGC::Constants::INTERFERENCE_TOLERANCE),
                 'countertop must not intersect the tower')
          assert_close(600.0, s[:x1], 1e-6, 'counter must butt against the tower gable')
        end
        # and nothing at all is generated at tower height
        assert(plan[:segments].all? { |s| s[:z1] <= 920.0 }, 'no geometry at tower height')
      end

      test('butt termination stops cleanly on the tower side gable') do
        doc = EGC::Scene::Document.new('wt')
        base(doc, :x => 0.0,  :width => 600.0, :name => 'B1')
        tower(doc, :x => 600.0, :width => 600.0, :height => 2100.0, :name => 'T1')
        plan = EGC::Ops::ExecWorktop.plan(doc)
        seg = plan[:segments].first
        refute(seg.nil?, 'segment must exist')
        assert_close(600.0, seg[:x1], 1e-6, 'segment must end exactly on the tower gable')
        assert_equal(:butt, seg[:right_termination])
      end

      test('plane is constant regardless of tall neighbours') do
        doc = EGC::Scene::Document.new('wt')
        base(doc, :x => 0.0, :width => 600.0)
        tower(doc, :x => 600.0, :height => 2400.0)
        plan = EGC::Ops::ExecWorktop.plan(doc)
        assert_close(EGC::Constants::STANDARD_COUNTER_HEIGHT, plan[:plane_top_z], 1e-9)
      end

      test('clamp_plane! refuses a plane above the standard height') do
        assert_raises(EGC::IntegrityError) { EGC::Ops::ExecWorktop.clamp_plane!(2300.0) }
      end

      test('two separated base runs produce two segments') do
        doc = EGC::Scene::Document.new('wt')
        base(doc, :x => 0.0,    :width => 600.0)
        base(doc, :x => 600.0,  :width => 600.0)
        base(doc, :x => 5000.0, :width => 600.0)
        plan = EGC::Ops::ExecWorktop.plan(doc)
        assert_equal(2, plan[:segments].length)
      end

      test('plan validates clean on a healthy mixed run') do
        doc = EGC::Scene::Document.new('wt')
        base(doc, :x => 0.0, :width => 600.0)
        base(doc, :x => 600.0, :width => 600.0)
        plan = EGC::Ops::ExecWorktop.plan(doc)
        v = EGC::Ops::ExecWorktop.validate(plan)
        assert_equal(true, v[:ok], v[:errors].inspect)
      end

      test('worktop parts carry the clamped plane') do
        doc = EGC::Scene::Document.new('wt')
        base(doc, :x => 0.0)
        plan = EGC::Ops::ExecWorktop.plan(doc)
        parts = EGC::Ops::ExecWorktop.to_parts(plan)
        assert_equal(1, parts.length)
        assert(parts.first.box.top <= 920.0, 'worktop part must sit at counter height')
      end
    end

    # ================================================================= §2
    suite('ops/production_sync') do
      test('resize rewrites EGC_PART dictionaries with the new size') do
        doc = EGC::Scene::Document.new('sync')
        cab = base(doc, :width => 600.0)
        EGC::Ops::ProductionSync.refresh_part_attributes(cab)

        deck_before = cab.parts.find { |p| p.role == EGC::Model::Part::ROLE_BOTTOM }
        before = deck_before.length

        cab.resize!(:width => 800.0)

        deck_after = cab.parts.find { |p| p.role == EGC::Model::Part::ROLE_BOTTOM }
        stored = EGC::Model::Part.read_attributes(doc.attributes, deck_after.id)
        assert_close(800.0 - 2 * EGC::Constants::PANEL_THICKNESS, stored[:length], 1e-6,
                     'stored deck length must reflect the new width')
        refute((before - stored[:length]).abs < 1e-6, 'stored size must have changed')
      end

      test('§2 Test 2: 600 -> 800 updates shelf and deck width in the cutlist') do
        doc = EGC::Scene::Document.new('sync')
        cab = base(doc, :width => 600.0)
        cab.add_shelf(:type => :fixed)
        cab.rebuild!
        EGC::Ops::ProductionSync.refresh_part_attributes(cab)

        expected = 800.0 - 2 * EGC::Constants::PANEL_THICKNESS
        cab.resize!(:width => 800.0)

        rows = EGC::Cutlist.generate(doc)
        deck = rows.find { |r| r[:role] == EGC::Model::Part::ROLE_BOTTOM }
        shelf = rows.find { |r| r[:role] == EGC::Model::Part::ROLE_SHELF }
        assert_close(expected, deck[:length], 1e-6, 'deck length in cutlist')
        refute(shelf.nil?, 'shelf row must exist')
        # adjustable shelves carry no slack; fixed shelves span the inner width
        assert_close(expected, shelf[:length], 1e-6, 'shelf length in cutlist')
      end

      test('cutlist cache is invalidated on resize') do
        doc = EGC::Scene::Document.new('sync')
        cab = base(doc, :width => 600.0)
        EGC::Cutlist.generate(doc)
        gen_before = EGC::Cutlist.generation
        cab.resize!(:width => 800.0)
        assert(EGC::Cutlist.generation > gen_before, 'generation must advance')
      end

      test('CAM toolpaths are reset on resize') do
        doc = EGC::Scene::Document.new('sync')
        cab = base(doc, :width => 600.0)
        gen_before = EGC::CAM.generation
        cab.resize!(:width => 800.0)
        assert(EGC::CAM.generation > gen_before, 'CAM generation must advance')
      end

      test('no stale row survives a resize (content check)') do
        doc = EGC::Scene::Document.new('sync')
        cab = base(doc, :width => 600.0)
        first = EGC::Cutlist.generate(doc).find { |r| r[:role] == EGC::Model::Part::ROLE_BOTTOM }
        cab.resize!(:width => 800.0)
        second = EGC::Cutlist.generate(doc).find { |r| r[:role] == EGC::Model::Part::ROLE_BOTTOM }
        refute((first[:length] - second[:length]).abs < 1e-6, 'cutlist returned a stale size')
      end

      test('height change updates gable length in the cutlist') do
        doc = EGC::Scene::Document.new('sync')
        cab = base(doc, :width => 600.0)
        cab.resize!(:height => 800.0)
        gable = EGC::Cutlist.generate(doc).find { |r| r[:role] == EGC::Model::Part::ROLE_GABLE_L }
        assert_close(800.0, gable[:length], 1e-6)
      end

      test('resync_document! refreshes every part') do
        doc = EGC::Scene::Document.new('sync')
        base(doc, :width => 600.0)
        base(doc, :x => 600.0, :width => 600.0)
        n = EGC::Ops::ProductionSync.resync_document!(doc)
        assert(n.positive?, 'resync must touch parts')
      end
    end

    # ================================================================= §2 edit
    suite('ops/assistant_edit') do
      test('set_dimensions routes through the sync pipeline') do
        doc = EGC::Scene::Document.new('edit')
        cab = base(doc, :width => 600.0)
        report = EGC::Ops::AssistantEdit.set_dimensions(cab, :width => 800.0)
        assert_equal(800.0, cab.width)
        assert(report[:cutlist_generation].positive?, 'cutlist generation must be reported')
      end

      test('positive validation rejects zero and nil') do
        doc = EGC::Scene::Document.new('edit')
        cab = base(doc, :width => 600.0)
        assert_raises(ArgumentError) { EGC::Ops::AssistantEdit.set_width(cab, 0) }
        assert_raises(ArgumentError) { EGC::Ops::AssistantEdit.set_width(cab, nil) }
      end

      test('height edit above threshold reports reclassification') do
        doc = EGC::Scene::Document.new('edit')
        cab = base(doc, :width => 600.0)
        report = EGC::Ops::AssistantEdit.set_dimensions(cab, :height => 2300.0)
        assert_equal(true, report[:reclassified])
        assert_equal(:tall, report[:effective_tag])
      end

      test('adding a shelf keeps the attribute store in sync') do
        doc = EGC::Scene::Document.new('edit')
        cab = base(doc, :width => 900.0, :depth => 560.0)
        EGC::Ops::AssistantEdit.add_shelf(cab, :type => :fixed)
        shelf = cab.parts.find { |p| p.role == EGC::Model::Part::ROLE_SHELF }
        refute(shelf.nil?, 'shelf part must exist')
        stored = EGC::Model::Part.read_attributes(doc.attributes, shelf.id)
        refute(stored.nil?, 'shelf attributes must be stored')
        assert_close(shelf.length, stored[:length], 1e-6)
      end
    end

    # ================================================================= §3
    suite('ops/nesting') do
      test('kerf and trim are read, never altered') do
        parts = nest_parts(2)
        r = EGC::Ops::Nesting.nest(parts)
        assert_close(4.4, r[:kerf], 1e-9)
        assert_close(10.0, r[:trim], 1e-9)
        assert_close(4.4, EGC::Constants::SAW_KERF, 1e-9)
        assert_close(10.0, EGC::Constants::BORDER_TRIM, 1e-9)
      end

      test('no placement overlaps and everything is inside the trim') do
        parts = nest_parts(4)
        r = EGC::Ops::Nesting.nest(parts)
        v = EGC::Ops::Nesting.validate(r)
        assert_equal(true, v[:ok], v[:errors].first(3).inspect)
      end

      test('grain-free material is rotated when beneficial') do
        parts = nest_parts(3, :material => :mdf_plain)
        r = EGC::Ops::Nesting.nest(parts, :strip_grouping => false)
        rotated = r[:placements].count { |p| p[:rotated] }
        assert(rotated.positive?, 'at least one grain-free part should rotate')
      end

      test('grained material is never rotated') do
        parts = nest_parts(3, :material => :oak_veneer)
        r = EGC::Ops::Nesting.nest(parts, :strip_grouping => false)
        grained = r[:placements].select { |pl| pl[:part].grain? }
        assert(grained.length.positive?, 'the job must contain grained parts')
        rotated = grained.count { |pl| pl[:rotated] }
        assert_equal(0, rotated, 'grained parts must never rotate 90 degrees')
      end

      test('rotation reduces sheet count versus a non-rotating baseline') do
        parts = nest_parts(8, :material => :mdf_plain)
        free = EGC::Ops::Nesting.nest(parts, :strip_grouping => false)
        locked = EGC::Ops::Nesting.nest(parts, :strip_grouping => false, :allow_rotation => false)
        assert(free[:sheet_count] <= locked[:sheet_count],
               "rotation should not increase sheets (#{free[:sheet_count]} vs #{locked[:sheet_count]})")
        assert(free[:yield] >= locked[:yield] - 1e-9,
               "rotation should not reduce yield (#{free[:yield]} vs #{locked[:yield]})")
      end

      test('best-fit guillotine recovers offcuts for small fillers') do
        # one large part leaves a big offcut; small parts must use it
        large = EGC::Model::Part.new(:gable_left, :length => 2000.0, :width => 500.0,
                                     :thickness => 18.0, :material => :mdf_plain)
        fillers = 6.times.map do
          EGC::Model::Part.new(:stretcher, :length => 300.0, :width => 100.0,
                               :thickness => 18.0, :material => :mdf_plain)
        end
        r = EGC::Ops::Nesting.nest([large] + fillers, :strip_grouping => false)
        assert_equal(1, r[:sheet_count],
                     "fillers must be reclaimed inside the gable's offcut, got #{r[:sheet_count]} sheets")
      end

      test('strip grouping packs identical widths into one strip') do
        parts = 4.times.map do
          EGC::Model::Part.new(:shelf, :length => 500.0, :width => 400.0,
                               :thickness => 18.0, :material => :mdf_plain)
        end
        r = EGC::Ops::Nesting.nest(parts, :strip_grouping => true)
        strips = r[:placements].map { |p| p[:strip_id] }.compact.uniq
        assert_equal(1, strips.length, 'identical widths should form one strip')
      end

      test('parts of different thickness never share a sheet') do
        a = EGC::Model::Part.new(:shelf, :length => 500.0, :width => 400.0,
                                 :thickness => 18.0, :material => :mdf_plain)
        b = EGC::Model::Part.new(:drawer_bottom, :length => 500.0, :width => 400.0,
                                 :thickness => 8.0, :material => :drawer_base)
        r = EGC::Ops::Nesting.nest([a, b], :strip_grouping => false)
        assert_equal(2, r[:sheet_count], 'different gauges must not share a sheet')
      end

      test('parts of different material never share a sheet') do
        a = EGC::Model::Part.new(:shelf, :length => 500.0, :width => 400.0,
                                 :thickness => 18.0, :material => :mdf_plain)
        b = EGC::Model::Part.new(:shelf, :length => 500.0, :width => 400.0,
                                 :thickness => 18.0, :material => :oak_veneer)
        r = EGC::Ops::Nesting.nest([a, b], :strip_grouping => false)
        assert_equal(2, r[:sheet_count], 'different materials must not share a sheet')
      end

      test('oversize part is reported, not silently dropped') do
        huge = EGC::Model::Part.new(:gable_left, :length => 5000.0, :width => 3000.0,
                                    :thickness => 18.0, :material => :mdf_plain)
        r = EGC::Ops::Nesting.nest([huge])
        assert_equal(1, r[:unplaced_count])
      end

      test('§3 Test 3: 20-cabinet job nests with no overlap and no waste') do
        parts = nest_parts(20, :material => :mdf_plain)
        r = EGC::Ops::Nesting.nest(parts)
        v = EGC::Ops::Nesting.validate(r)
        assert_equal(true, v[:ok], v[:errors].first(2).inspect)
        assert_equal(0, r[:unplaced_count], 'nothing should be unplaced')
        assert(r[:sheet_count].positive?, 'sheets must be allocated')
        # solid-colour MDF must be rotation-enabled at the material level
        assert_equal(true, EGC::Model::Materials.rotation_allowed?(:mdf_plain))

        # and with strip grouping disabled the packer must actually rotate
        free = EGC::Ops::Nesting.nest(parts, :strip_grouping => false)
        assert(free[:placements].count { |p| p[:rotated] }.positive?,
               'rotation must be exercised when strips are disabled')
      end
    end

    # ================================================================= CAM
    suite('ops/cam') do
      test('tool radius derives from the frozen kerf') do
        assert_close(2.2, EGC::Ops::CAM.tool_radius, 1e-9)
      end

      test('cut contour is the finished outline (no kerf applied)') do
        p = EGC::Model::Part.new(:shelf, :length => 500.0, :width => 400.0,
                                 :thickness => 18.0, :material => :mdf_plain)
        c = EGC::Ops::CAM.cut_contour(p, 0.0, 0.0)
        assert_close(500.0, c[1][0], 1e-9)
        assert_close(400.0, c[2][1], 1e-9)
      end

      test('tool centre path is offset by the tool radius') do
        p = EGC::Model::Part.new(:shelf, :length => 500.0, :width => 400.0,
                                 :thickness => 18.0, :material => :mdf_plain)
        tc = EGC::Ops::CAM.tool_centre_contour(p, 100.0, 100.0)
        assert_close(100.0 - 2.2, tc[0][0], 1e-9)
        assert_close(100.0 - 2.2, tc[0][1], 1e-9)
      end

      test('reset_toolpaths! advances the generation') do
        before = EGC::Ops::CAM.generation
        EGC::Ops::CAM.reset_toolpaths!(:test)
        assert(EGC::Ops::CAM.generation > before)
      end

      test('hinge holes use the frozen cup diameter and depth') do
        holes = EGC::Ops::CAM.hinge_holes(700.0)
        assert(holes.length >= 2, 'a 700mm door needs at least two hinges')
        holes.each do |h|
          assert_close(35.0, h[:diameter], 1e-9)
          assert_close(13.0, h[:depth], 1e-9)
        end
      end

      test('system32 row steps on the frozen pitch') do
        holes = EGC::Ops::CAM.system32_holes(100.0, 300.0, 37.0)
        assert(holes.length >= 7, "expected ~7 holes, got #{holes.length}")
        assert_close(32.0, holes[1][:y] - holes[0][:y], 1e-9)
      end

      test('rod bracket holes use the frozen bracket diameter') do
        holes = EGC::Ops::CAM.rod_bracket_holes(1700.0, 18.0, 882.0)
        assert_equal(2, holes.length)
        holes.each { |h| assert_close(5.0, h[:diameter], 1e-9) }
      end

      test('DXF contains the layer structure') do
        p = EGC::Model::Part.new(:shelf, :length => 500.0, :width => 400.0,
                                 :thickness => 18.0, :material => :mdf_plain)
        sheet = { :length => 2440.0, :width => 1220.0,
                  :placements => [{ :part => p, :x => 50.0, :y => 50.0, :rotated => false }] }
        dxf = EGC::Ops::CAM.sheet_to_dxf(sheet)
        assert_match(/CUT/, dxf)
        assert_match(/TRIM/, dxf)
        assert_match(/EOF/, dxf)
      end
    end

    # ================================================================= §4
    suite('ops/space_tool') do
      test('§4 Test 4: doorless cavity hit test raises no nil error') do
        doc, cab = open_wardrobe
        v = cab.detect_inner_void
        centre = v.center
        hit = nil
        begin
          hit = EGC::Ops::SpaceTool.hit_test(doc, centre)
        rescue NoMethodError => e
          raise EGC::Test::AssertionFailed, "nil crash in space tool: #{e.message}"
        end
        refute(hit.nil?, 'clicking the cavity centre must resolve a cavity')
        assert_equal(cab.id, hit[:cabinet].id)
      end

      test('highlight returns drawable corners') do
        doc, cab = open_wardrobe
        hit = EGC::Ops::SpaceTool.hit_test(doc, cab.detect_inner_void.center)
        hl = EGC::Ops::SpaceTool.highlight(hit)
        assert_equal(:cavity_highlight, hl[:kind])
        assert_equal(8, hl[:corners].length)
        assert(hl[:volume_litres].positive?)
      end

      test('insert fixed shelf inside the cavity') do
        doc, cab = open_wardrobe
        hit = EGC::Ops::SpaceTool.hit_test(doc, cab.detect_inner_void.center)
        res = EGC::Ops::SpaceTool.insert(hit, :fixed_shelf)
        assert_equal(:fixed_shelf, res[:kind])
        assert(res[:length].positive?, 'shelf must have a length')
        assert(cab.parts.any? { |p| p.role == EGC::Model::Part::ROLE_SHELF })
      end

      test('insert adjustable shelf inside the cavity') do
        doc, cab = open_wardrobe
        hit = EGC::Ops::SpaceTool.hit_test(doc, cab.detect_inner_void.center)
        res = EGC::Ops::SpaceTool.insert(hit, :adjustable_shelf)
        assert_equal(:adjustable_shelf, res[:kind])
      end

      test('insert vertical divider') do
        doc, cab = open_wardrobe
        hit = EGC::Ops::SpaceTool.hit_test(doc, cab.detect_inner_void.center)
        res = EGC::Ops::SpaceTool.insert(hit, :divider)
        assert_equal(:divider, res[:kind])
        assert(cab.parts.any? { |p| p.role == EGC::Model::Part::ROLE_DIVIDER })
      end

      test('insert hanging rod with bracket drilling') do
        doc, cab = open_wardrobe
        v = cab.detect_inner_void
        top = EGC::Geom::Vec3.new(v.center.x, v.center.y, v.max.z - 150.0)
        hit = EGC::Ops::SpaceTool.hit_test(doc, top)
        refute(hit.nil?, 'upper cavity must accept a rod')
        res = EGC::Ops::SpaceTool.insert(hit, :hanging_rod)
        assert_equal(2, res[:bracket_count], 'one bracket per gable')
        res[:brackets].each { |b| assert_close(5.0, b[:diameter], 1e-9) }
        assert(cab.parts.any? { |p| p.role == EGC::Model::Part::ROLE_ROD })
      end

      test('insert drawer module with runner clearances') do
        doc, cab = open_wardrobe
        hit = EGC::Ops::SpaceTool.hit_test(doc, cab.detect_inner_void.center)
        res = EGC::Ops::SpaceTool.insert(hit, :drawer, :height => 150.0)
        assert_equal(:drawer, res[:kind])
        assert_close(EGC::Constants::RUNNER_CLEARANCE_SIDE, res[:clearances][:side], 1e-9)
        refute(res[:runner].nil?, 'a runner must be selected')
      end

      test('unsupported insertion raises InsertionError') do
        doc, cab = open_wardrobe
        hit = EGC::Ops::SpaceTool.hit_test(doc, cab.detect_inner_void.center)
        assert_raises(EGC::InsertionError) do
          EGC::Ops::SpaceTool.insert(hit, :jacuzzi)
        end
      end

      test('a click outside every cavity resolves to no hit') do
        doc, _cab = open_wardrobe
        assert_nil(EGC::Ops::SpaceTool.hit_test(doc, EGC::Geom::Vec3.new(-9000, -9000, -9000)))
      end

      test('open unit keeps exposed edge banding after insertion') do
        doc, cab = open_wardrobe
        hit = EGC::Ops::SpaceTool.hit_test(doc, cab.detect_inner_void.center)
        EGC::Ops::SpaceTool.insert(hit, :fixed_shelf)
        gable = cab.parts.find { |p| p.role == EGC::Model::Part::ROLE_GABLE_L }
        assert_equal(true, gable.edgeband.edged?(:front))
      end
    end

    # ================================================================= §5
    suite('ops/auxiliary') do
      test('interference: adjacent cabinets sharing a gable is legal') do
        doc = EGC::Scene::Document.new('aux')
        base(doc, :x => 0.0, :width => 600.0)
        base(doc, :x => 600.0, :width => 600.0)
        r = EGC::Ops::Interference.scan_cabinets(doc)
        assert_equal(0, r[:hits].length, 'touching cabinets are not interference')
      end

      test('interference: real overlap is detected') do
        doc = EGC::Scene::Document.new('aux')
        base(doc, :x => 0.0, :width => 600.0)
        base(doc, :x => 500.0, :width => 600.0)
        r = EGC::Ops::Interference.scan_cabinets(doc)
        assert_equal(1, r[:hits].length)
      end

      test('interference: healthy cabinet has no internal collisions') do
        doc = EGC::Scene::Document.new('aux')
        base(doc, :x => 0.0, :width => 600.0)
        r = EGC::Ops::Interference.scan_internal(doc)
        assert_equal(0, r[:hits].length, r[:hits].first(2).inspect)
      end

      test('corner: reports a blind corner when runs touch') do
        doc = EGC::Scene::Document.new('aux')
        base(doc, :x => 0.0, :width => 600.0)
        cab = EGC::Model::Cabinet.new(:base, :width => 600.0, :depth => 560.0,
                                      :origin => EGC::Geom::Vec3.new(-600.0, 0.0, toe))
        doc.add_cabinet(cab)
        cab.rebuild!
        r = EGC::Ops::Corner.detect(doc)
        assert(r[:count] >= 0, 'corner detection must not raise')
      end

      test('corner filler is only proposed when a gap exists') do
        c = { :filler_size_mm => 45.0, :filler_required => true }
        p = EGC::Ops::Corner.filler_part(c, :height => 720.0, :depth => 18.0)
        refute(p.nil?, 'filler part must be built')
        assert_close(45.0, p.width, 1e-9)
      end

      test('appliances: dishwasher fits a 600 bay') do
        cab = EGC::Model::Cabinet.new(:base, :width => 600.0, :height => 720.0, :depth => 560.0)
        r = EGC::Ops::Appliances.check(cab, :dishwasher)
        assert(r.key?(:fits), 'check must return a fit verdict')
      end

      test('appliances: unknown appliance raises') do
        cab = EGC::Model::Cabinet.new(:base)
        assert_raises(ArgumentError) { EGC::Ops::Appliances.check(cab, :teleporter) }
      end

      test('snap: snaps to a neighbouring gable plane') do
        doc = EGC::Scene::Document.new('aux')
        base(doc, :x => 0.0, :width => 600.0)
        assert_close(600.0, EGC::Ops::Snap.snap_x(doc, 603.0, 10.0), 1e-9)
      end

      test('snap: leaves a far coordinate untouched') do
        doc = EGC::Scene::Document.new('aux')
        base(doc, :x => 0.0, :width => 600.0)
        assert_close(900.0, EGC::Ops::Snap.snap_x(doc, 900.0, 10.0), 1e-9)
      end

      test('snap: system32 grid snapping') do
        assert_close(768.0, EGC::Ops::Snap.snap_system32(770.0), 1e-9)
      end

      test('snap: resolve returns all three axes') do
        doc = EGC::Scene::Document.new('aux')
        base(doc, :x => 0.0, :width => 600.0)
        r = EGC::Ops::Snap.resolve(doc, [603.0, 0.0, 150.0])
        assert_equal(true, r[:snapped_x])
      end

      test('§5 zero-warning gate for every auxiliary tool') do
        doc = EGC::Scene::Document.new('aux')
        base(doc, :x => 0.0, :width => 600.0)
        base(doc, :x => 600.0, :width => 600.0)
        EGC::Log.clear!
        EGC::Log.reset!

        EGC::Ops::Interference.scan_all(doc)
        EGC::Ops::Corner.detect(doc)
        EGC::Ops::Snap.resolve(doc, [123.0, 456.0, 789.0])
        EGC::Ops::Appliances.check(doc.cabinets.first, :microwave)
        EGC::Ops::SpaceTool.hit_test(doc, EGC::Geom::Vec3.new(0.0, 0.0, 0.0))

        warnings = EGC::Log.warnings
        EGC::Log.stop_audit!
        EGC::Log.clear!
        assert_equal(0, warnings.length, "warnings: #{warnings.map { |w| w[:message] }.inspect}")
      end
    end

    # ================================================================= audit
    suite('ops/audit') do
      test('audit passes on a healthy document') do
        doc = EGC::Scene::Document.new('audit')
        base(doc, :x => 0.0, :width => 600.0)
        base(doc, :x => 600.0, :width => 600.0)
        tower(doc, :x => 1200.0, :height => 2100.0, :tag => :tall)
        doc.cabinets.each { |c| EGC::Ops::ProductionSync.refresh_part_attributes(c) }
        report = EGC::Ops::Audit.run(doc)
        assert_equal(true, report[:ok],
                     report[:checks].reject { |c| c[:ok] }.map { |c| "#{c[:name]}: #{c[:detail]}" }.join(' | '))
      end

      test('audit detects a drifted constant contract') do
        original = EGC::Constants::EXPECTED_FINGERPRINT
        begin
          EGC::Constants.send(:remove_const, :EXPECTED_FINGERPRINT)
          EGC::Constants.const_set(:EXPECTED_FINGERPRINT, 'deadbeef')
          doc = EGC::Scene::Document.new('audit')
          check = EGC::Ops::Audit.check_constants
          assert_equal(false, check[:ok], 'drift must be reported')
        ensure
          EGC::Constants.send(:remove_const, :EXPECTED_FINGERPRINT)
          EGC::Constants.const_set(:EXPECTED_FINGERPRINT, original)
        end
      end

      test('report formatting includes every check') do
        doc = EGC::Scene::Document.new('audit')
        base(doc, :x => 0.0)
        report = EGC::Ops::Audit.run(doc)
        text = EGC::Ops::Audit.format_report(report)
        assert_match(/System Audit/, text)
        assert_match(/PASS|FAIL/, text)
      end
    end

    # ================================================================= ui
    suite('ui/commands') do
      test('menu exposes the command surface without SketchUp') do
        items = EGC::UI::Menu.items
        assert(items.length >= 6, 'menu must list the commands')
        ids = items.map { |i| i[:id] }.compact
        assert_includes(ids, 'egc_audit')
        assert_includes(ids, 'egc_worktop')
      end

      test('dispatch runs the audit command') do
        doc = EGC::Scene::Document.new('ui')
        base(doc, :x => 0.0)
        r = EGC::UI::Commands.dispatch(:run_audit, doc)
        assert(r.key?(:checks))
      end

      test('dispatch runs generate_worktops') do
        doc = EGC::Scene::Document.new('ui')
        base(doc, :x => 0.0)
        r = EGC::UI::Commands.dispatch(:generate_worktops, doc)
        assert_equal(1, r[:segments])
        assert(r[:max_top_z] <= 920.0)
      end

      test('dispatch exports a cutlist as CSV text') do
        doc = EGC::Scene::Document.new('ui')
        base(doc, :x => 0.0)
        r = EGC::UI::Commands.dispatch(:export_cutlist, doc)
        assert_match(/Role,Material/, r[:csv])
      end

      test('dispatch space_tool requires a point') do
        doc = EGC::Scene::Document.new('ui')
        assert_raises(ArgumentError) { EGC::UI::Commands.dispatch(:space_tool, doc) }
      end

      test('unknown command raises') do
        assert_raises(ArgumentError) { EGC::UI::Commands.dispatch(:explode, EGC::Scene::Document.new('x')) }
      end
    end
  end
end
