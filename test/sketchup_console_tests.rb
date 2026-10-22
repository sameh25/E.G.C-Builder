# encoding: UTF-8
# frozen_string_literal: true
#
# IN-SKETCHUP TEST SUITE (§2 of the task specification)
# ---------------------------------------------------------------------------
# Paste this file's contents into the SketchUp Ruby Console, or:
#
#     load 'C:/path/to/EGC_Builder_1.28.67/test/sketchup_console_tests.rb'
#
# It runs the four mandated practical tests against REAL extension code paths
# and prints PASS/FAIL for each assertion. It does not need a model open; it
# builds its own document, but it does go through the same modules the menus
# call, so a failure here means a real regression.
#
# The last line prints the summary you can paste back for verification.

begin
  require 'sketchup.rb'
rescue LoadError
  # Headless run (CI / plain Ruby). The engine itself has no SketchUp
  # dependency, so the suite still exercises the real code paths.
end

# ---------------------------------------------------------------------------
# Headless bootstrap.
#
# Inside SketchUp the engine is already loaded by main.rb, so this is skipped.
# In a plain Ruby process it is REQUIRED: without it the `defined?(Sketchup)`
# guard at the bottom of this file is false, run_all never runs, and the
# process exits 0 having asserted nothing -- a silent false pass. Load the
# engine instead so the suite genuinely executes.
# ---------------------------------------------------------------------------
unless defined?(EGC::VERSION)
  if File.exist?(File.expand_path('../harness/sketchup_stub.rb', __dir__))
    # Plain-Ruby run: pull in the headless SketchUp API stand-in (it also puts
    # src/ on the load path). Skipped inside a real SketchUp install.
    require_relative '../harness/sketchup_stub'
  end
  begin
    require_relative '../src/EGC_Builder/loader'
  rescue LoadError
    begin
      require 'EGC_Builder/loader'
    rescue LoadError
      warn '[EGC] console suite could not load the engine; it would assert nothing.'
    end
  end
end

module EGC
  module ConsoleTests
    module_function

    @results = []

    def check(label, cond, detail = nil)
      @results << { :label => label, :ok => !!cond, :detail => detail }
      mark = cond ? 'PASS' : 'FAIL'
      puts format('  [%s] %s%s', mark, label, detail ? "  (#{detail})" : '')
      !!cond
    end

    def section(title)
      puts "\n#{title}"
      puts '-' * 70
    end

    def summary
      failed = @results.reject { |r| r[:ok] }
      puts "\n" + ('=' * 70)
      puts format('EGC %s in-SketchUp test suite: %d checks, %d passed, %d failed',
                  EGC::VERSION, @results.length, @results.length - failed.length, failed.length)
      failed.each { |f| puts "  FAILED: #{f[:label]} #{f[:detail]}" }
      puts '=' * 70
      failed.empty?
    end

    # Build a fresh document each run.
    def fresh_doc(name)
      EGC::Scene::Document.new(name)
    end

    def add_base(doc, x:, width: 600.0, depth: 560.0, name: nil)
      cab = EGC::Model::Cabinet.new(
        :base, :width => width, :depth => depth,
        :origin => EGC::Geom::Vec3.new(x, 0.0, EGC::Constants::TOE_KICK_HEIGHT),
        :name => name
      )
      doc.add_cabinet(cab)
      cab.rebuild!
      cab
    end

    def add_tower(doc, x:, width: 600.0, depth: 560.0, height: 2300.0, name: nil)
      cab = EGC::Model::Cabinet.new(
        :tall, :width => width, :depth => depth, :height => height,
        :origin => EGC::Geom::Vec3.new(x, 0.0, 0.0),
        :name => name
      )
      doc.add_cabinet(cab)
      cab.rebuild!
      cab
    end

    # =====================================================================
    # TEST 1 - Height modification & worktop clamping
    # =====================================================================
    def test1
      section 'TEST 1  Height modification & worktop clamping'
      doc = fresh_doc('T1')
      cab = add_base(doc, :x => 0.0, :width => 600.0, :name => 'Base 600')
      check('base cabinet inserted at 720mm carcass height',
            (cab.height - 720.0).abs < 1e-6, "h=#{cab.height}")
      check('classification is :base before the edit', cab.effective_tag == :base)

      # edit to 2300mm through the sanctioned edit path
      EGC::Ops::AssistantEdit.set_height(cab, 2300.0)
      check('height edit applied', (cab.height - 2300.0).abs < 1e-6, "h=#{cab.height}")
      check('auto-reclassified to :tall', cab.effective_tag == :tall,
            "effective=#{cab.effective_tag}")
      check('reclassification flagged', cab.reclassified?)

      plan = EGC::Ops::ExecWorktop.plan(doc)
      max_top = plan[:segments].map { |s| s[:z1] }.max
      check('countertop top does not exceed 920mm',
            max_top.nil? || max_top <= 920.0, "max_top=#{max_top.inspect}")
      check('edited tower tops out at 2300mm but carries no counter',
            plan[:segments].none? { |s| s[:z1] > 920.0 })

      # now add a genuine base run next to a tower and verify butt termination
      doc2 = fresh_doc('T1b')
      add_base(doc2, :x => 0.0, :width => 600.0, :name => 'B1')
      tw = add_tower(doc2, :x => 600.0, :width => 600.0, :height => 2300.0, :name => 'Tall')
      plan2 = EGC::Ops::ExecWorktop.plan(doc2)
      seg = plan2[:segments].first
      check('base run still receives a countertop next to a tower', !seg.nil?)
      if seg
        check('counter terminates on the tower side gable (butt)',
              (seg[:x1] - 600.0).abs < 1e-6 && seg[:right_termination] == :butt,
              "x1=#{seg[:x1]} term=#{seg[:right_termination]}")
        check('counter does not intersect the tower volume',
              !seg[:box].overlaps?(tw.bounding_box, EGC::Constants::INTERFERENCE_TOLERANCE))
      end
      v = EGC::Ops::ExecWorktop.validate(plan2)
      check('worktop plan validates clean', v[:ok], v[:errors].inspect)
    end

    # =====================================================================
    # TEST 2 - Two-way cutlist update
    # =====================================================================
    def test2
      section 'TEST 2  Two-way cutlist update verification'
      doc = fresh_doc('T2')
      cab = add_base(doc, :x => 0.0, :width => 600.0, :name => 'Base')
      cab.add_shelf(:type => :fixed)
      cab.rebuild!
      EGC::Ops::ProductionSync.refresh_part_attributes(cab)

      EGC::Ops::AssistantEdit.set_width(cab, 800.0)
      check('width edit applied', (cab.width - 800.0).abs < 1e-6, "w=#{cab.width}")

      expected = 800.0 - 2 * EGC::Constants::PANEL_THICKNESS
      rows = EGC::Cutlist.generate(doc)

      deck = rows.find { |r| r[:role] == EGC::Model::Part::ROLE_BOTTOM }
      shelf = rows.find { |r| r[:role] == EGC::Model::Part::ROLE_SHELF }
      check('top/bottom panel width in CSV == 800 - 2 x gable', deck && (deck[:length] - expected).abs < 1e-6,
            "deck=#{deck && deck[:length]} expected=#{expected}")
      check('shelf width in CSV reflects the new internal width',
            shelf && (shelf[:length] - expected).abs < 1e-6,
            "shelf=#{shelf && shelf[:length]} expected=#{expected}")

      # the stored attribute dictionary must agree with the CSV
      deck_part = cab.parts.find { |p| p.role == EGC::Model::Part::ROLE_BOTTOM }
      stored = EGC::Model::Part.read_attributes(doc.attributes, deck_part.id)
      check('EGC_PART dictionary updated synchronously',
            stored && (stored[:length] - expected).abs < 1e-6,
            "stored=#{stored && stored[:length]}")

      check('cutlist cache invalidated on edit', EGC::Cutlist.generation.positive?,
            "gen=#{EGC::Cutlist.generation}")
      check('CAM toolpaths reset on edit', EGC::CAM.generation.positive?,
            "gen=#{EGC::CAM.generation}")

      csv = EGC::Cutlist.to_csv(doc)
      check('CSV header present', csv.start_with?('Role,Material'))
    end

    # =====================================================================
    # TEST 3 - Nesting sheet count & rotation
    # =====================================================================
    def test3
      section 'TEST 3  Nesting sheet count & rotation (solid-colour MDF)'
      doc = fresh_doc('T3')
      20.times do |i|
        cab = EGC::Model::Cabinet.new(
          :base, :width => 600.0, :depth => 560.0,
          :origin => EGC::Geom::Vec3.new(i * 600.0, 0.0, EGC::Constants::TOE_KICK_HEIGHT),
          :material => :mdf_plain, :name => "N#{i}"
        )
        doc.add_cabinet(cab)
        cab.rebuild!
      end
      parts = doc.parts.reject { |p| p.role == EGC::Model::Part::ROLE_ROD }

      check('material is grain-free (rotation permitted)',
            EGC::Model::Materials.rotation_allowed?(:mdf_plain))

      free = EGC::Ops::Nesting.nest(parts, :strip_grouping => false)
      locked = EGC::Ops::Nesting.nest(parts, :strip_grouping => false, :allow_rotation => false)
      stripped = EGC::Ops::Nesting.nest(parts)

      check('rotation is exercised on grain-free parts',
            free[:placements].count { |p| p[:rotated] }.positive?,
            "rotated=#{free[:placements].count { |p| p[:rotated] }}")
      check('rotation never needs more sheets than grain-locked',
            free[:sheet_count] <= locked[:sheet_count],
            "free=#{free[:sheet_count]} locked=#{locked[:sheet_count]}")
      check('kerf preserved at 4.4mm', (free[:kerf] - 4.4).abs < 1e-9)
      check('border trim preserved at 10.0mm', (free[:trim] - 10.0).abs < 1e-9)

      vf = EGC::Ops::Nesting.validate(free)
      check('rotated layout is geometrically legal (no overlap, inside trim)', vf[:ok],
            vf[:errors].first(3).inspect)
      vs = EGC::Ops::Nesting.validate(stripped)
      check('strip-grouped layout is legal', vs[:ok], vs[:errors].first(3).inspect)
      check('nothing unplaced in the production layout', stripped[:unplaced_count].zero?,
            "unplaced=#{stripped[:unplaced_count]}")
      check('strip grouping does not increase sheet count',
            stripped[:sheet_count] <= locked[:sheet_count],
            "strips=#{stripped[:sheet_count]} locked=#{locked[:sheet_count]}")

      # grained boards must never rotate
      grained_doc = fresh_doc('T3g')
      4.times do |i|
        cab = EGC::Model::Cabinet.new(
          :base, :width => 600.0, :depth => 560.0,
          :origin => EGC::Geom::Vec3.new(i * 600.0, 0.0, EGC::Constants::TOE_KICK_HEIGHT),
          :material => :oak_veneer, :name => "G#{i}"
        )
        grained_doc.add_cabinet(cab)
        cab.rebuild!
      end
      gparts = grained_doc.parts.reject { |p| p.role == EGC::Model::Part::ROLE_ROD }
      gres = EGC::Ops::Nesting.nest(gparts, :strip_grouping => false)
      grot = gres[:placements].select { |p| p[:part].grain? }.count { |p| p[:rotated] }
      check('grained parts never rotate 90 degrees', grot.zero?, "rotated=#{grot}")
    end

    # =====================================================================
    # TEST 4 - Doorless dressing room cavities
    # =====================================================================
    def test4
      section 'TEST 4  Doorless dressing room cavities & Space Tool'
      doc = fresh_doc('T4')
      cab = EGC::Model::Cabinet.new(
        :tall, :width => 900.0, :height => 2100.0, :depth => 600.0,
        :origin => EGC::Geom::Vec3.new(0.0, 0.0, 0.0), :name => 'Open Wardrobe'
      )
      doc.add_cabinet(cab)
      cab.rebuild!

      check('unit is doorless', cab.doorless?)

      void = nil
      begin
        void = cab.detect_inner_void
        check('inner void resolves with ZERO nil errors', true)
      rescue NoMethodError => e
        check('inner void resolves with ZERO nil errors', false, "#{e.class}: #{e.message}")
      end

      if void
        t = EGC::Constants::PANEL_THICKNESS
        check('void bounded by the left gable inner face', (void.min.x - t).abs < 1e-6,
              "x0=#{void.min.x}")
        check('void bounded by the right gable inner face',
              (void.max.x - (900.0 - t)).abs < 1e-6, "x1=#{void.max.x}")
        check('void has positive volume', void.volume.positive?,
              "vol=#{(void.volume / 1_000_000.0).round(2)} L")
      end

      centre = void.center
      hit = EGC::Ops::SpaceTool.hit_test(doc, centre)
      check('Space Tool single-click resolves the cavity', !hit.nil?)

      if hit
        hl = EGC::Ops::SpaceTool.highlight(hit)
        check('cavity highlight is produced', hl[:kind] == :cavity_highlight)

        shelf = EGC::Ops::SpaceTool.insert(hit, :fixed_shelf)
        check('fixed shelf inserted at internal bounds',
              shelf[:kind] == :fixed_shelf && shelf[:length].positive?,
              "len=#{shelf[:length]}")

        # re-resolve after the shelf changed the cavity layout
        hit = EGC::Ops::SpaceTool.hit_test(doc, centre) || hit
        div = EGC::Ops::SpaceTool.insert(hit, :divider)
        check('vertical divider inserted', div[:kind] == :divider)

        rod_z = void.max.z - 150.0
        rod_hit = EGC::Ops::SpaceTool.hit_test(
          doc, EGC::Geom::Vec3.new(centre.x, centre.y, rod_z)
        )
        check('upper cavity resolves for a hanging rod', !rod_hit.nil?)
        if rod_hit
          rod = EGC::Ops::SpaceTool.insert(rod_hit, :hanging_rod)
          check('hanging rod inserted with bracket drilling',
                rod[:bracket_count] == 2, "brackets=#{rod[:bracket_count]}")
          check('rod bracket drill diameter is the frozen 5.0mm',
                rod[:brackets].all? { |b| (b[:diameter] - 5.0).abs < 1e-9 })
        end

        drawer_hit = EGC::Ops::SpaceTool.hit_test(doc, centre)
        if drawer_hit
          dr = EGC::Ops::SpaceTool.insert(drawer_hit, :drawer, :height => 150.0)
          check('drawer module inserted with runner clearances',
                dr[:kind] == :drawer &&
                (dr[:clearances][:side] - EGC::Constants::RUNNER_CLEARANCE_SIDE).abs < 1e-9,
                "runner=#{dr[:runner]}")
        end
      end

      gable = cab.parts.find { |p| p.role == EGC::Model::Part::ROLE_GABLE_L }
      check('open unit gable front edge auto-banded',
            gable && gable.edgeband.edged?(:front),
            gable && gable.edgeband.to_code)
    end

    # =====================================================================
    # Auxiliary: zero console warnings (§5)
    # =====================================================================
    def test5_aux
      section 'AUX  Zero-warning regression for auxiliary tools (§5)'
      doc = fresh_doc('AUX')
      add_base(doc, :x => 0.0, :width => 600.0)
      add_base(doc, :x => 600.0, :width => 600.0)

      EGC::Log.clear!
      EGC::Log.reset!

      EGC::Ops::Interference.scan_all(doc)
      EGC::Ops::Corner.detect(doc)
      EGC::Ops::Snap.resolve(doc, [123.0, 456.0, 789.0])
      EGC::Ops::Snap.snap_system32(777.0)
      EGC::Ops::Appliances.check(doc.cabinets.first, :microwave)
      EGC::Ops::SpaceTool.hit_test(doc, EGC::Geom::Vec3.new(-9999, -9999, -9999))

      warnings = EGC::Log.warnings
      EGC::Log.stop_audit!
      EGC::Log.clear!

      check('interference/corner/appliances/snap/space_tool emit 0 warnings',
            warnings.empty?, warnings.map { |w| w[:message] }.inspect)

      report = EGC::Ops::Audit.run(doc)
      check('full system audit passes', report[:ok],
            report[:checks].reject { |c| c[:ok] }.map { |c| "#{c[:name]}: #{c[:detail]}" }.join(' | '))
      puts "\n" + EGC::Ops::Audit.format_report(report)
    end

    # =====================================================================
    def run_all
      @results = []
      puts "\n" + ('=' * 70)
      puts "E.G.C Builder v#{EGC::VERSION} - In-SketchUp verification suite"
      puts "SketchUp: #{defined?(Sketchup) ? Sketchup.version : 'n/a'}   Ruby: #{RUBY_VERSION}"
      puts ('=' * 70)

      # integrity gate first
      begin
        EGC::Constants.verify!
        check('dimensional contract intact', true,
              "#{EGC::Constants::FROZEN.length} frozen values, #{EGC::Constants.fingerprint[0, 12]}...")
      rescue EGC::IntegrityError => e
        check('dimensional contract intact', false, e.message)
      end

      test1
      test2
      test3
      test4
      test5_aux
      summary
    end
  end
end

# Run when the engine is available -- inside SketchUp it always is, and in a
# plain Ruby process the headless bootstrap above loads it. Gating on
# `defined?(Sketchup)` instead would make a headless run assert nothing and
# still exit 0, hiding real regressions.
EGC::ConsoleTests.run_all if defined?(EGC::ConsoleTests)
