# encoding: UTF-8
# frozen_string_literal: true
#
# Regression suites - UI layer + packaging layout.
#
# These exist because of the v1.28.67 startup failure:
#
#   LoadError -- Could not find such file -- EGC_Builder/main
#
# The engine was healthy; the ARCHIVE was wrong. A nested EGC_Builder/EGC_Builder
# directory pushed main.rb one level too deep, so the path registered by
# EGC_Builder.rb ('EGC_Builder/main') did not resolve after extraction.
#
# The assertions below pin the two things that made that failure invisible to
# the functional suites: (a) the flat source layout, and (b) that every asset
# the dialog advertises actually exists on disk.

module EGC
  module Test
    # Repository root, derived from this file's location (test/suites/).
    REPO_ROOT = File.expand_path('../..', __dir__) unless defined?(REPO_ROOT)
    SRC_ROOT  = File.join(REPO_ROOT, 'src') unless defined?(SRC_ROOT)

    # ------------------------------------------------------------- ui/dialog
    suite('ui/dialog') do
      test('every referenced dialog asset exists on disk') do
        EGC::UI::Dialog.assets.each do |kind, path|
          assert(File.exist?(path), "missing dialog asset #{kind}: #{path}")
        end
      end

      test('asset paths resolve inside the extension directory') do
        root = EGC::UI::Dialog.root
        EGC::UI::Dialog.assets.each_value do |path|
          assert(path.start_with?(root), "#{path} escapes the extension root #{root}")
        end
      end

      test('ui.html links its stylesheet, script and icon') do
        html = File.read(EGC::UI::Dialog.html_path)
        assert_match(/ui\.css/, html, 'ui.html must link ui.css')
        assert_match(/ui\.js/, html, 'ui.html must link ui.js')
        assert_match(/assets\/icon\.svg/, html, 'ui.html must reference the icon')
      end

      test('the icon shipped in assets/ is a real SVG, not a stub') do
        svg = File.read(File.join(EGC::UI::Dialog.assets_dir, 'icon.svg'))
        assert_match(/\A\s*(<\?xml|<svg)/, svg, 'icon must begin with an SVG document')
        assert_match(/<\/svg>\s*\z/, svg, 'icon must be a complete SVG document')
      end

      test('show degrades to a no-op hash without HtmlDialog') do
        res = EGC::UI::Dialog.show
        assert_equal(false, res[:opened], 'headless show must not claim a window')
        assert_equal(true, res[:present], 'headless show must still report asset presence')
      end

      test('stats_for exposes the live contract values') do
        stats = EGC::UI::Dialog.stats_for(EGC::Scene::Document.new('stats'))
        assert_equal(EGC::VERSION, stats[:version])
        assert_equal("#{EGC::Constants::STANDARD_COUNTER_HEIGHT.round} mm", stats[:plane])
        assert_equal('OK', stats[:contract])
        assert_match(/\A0a4c347975b8/, stats[:fingerprint],
                     'header must surface the unchanged dimensional fingerprint')
      end
    end

    # ----------------------------------------------------------- ui/commands
    suite('ui/commands') do
      test('dispatch routes :open_dialog to a defined command') do
        res = EGC::UI::Commands.dispatch(:open_dialog)
        assert_equal(:open_dialog, res[:command])
        assert_equal(false, res[:opened], 'headless dispatch must not open a window')
        assert(res[:stats].key?(:fingerprint), 'dispatch must return header stats')
      end

      test('every menu command is dispatchable') do
        defined = EGC::UI::Menu.items.reject { |it| it[:separator] }
        defined.each do |it|
          assert(EGC::UI::Commands.respond_to?(it[:command]),
                 "menu item #{it[:id]} points at undefined command #{it[:command]}")
        end
      end

      test('menu exposes the panel entry first') do
        first = EGC::UI::Menu.items.first
        assert_equal('egc_dialog', first[:id])
        assert_equal(:open_dialog, first[:command])
        assert_equal(true, EGC::UI::Menu.items[1][:separator], 'panel must be separated from tools')
      end

      test('dispatch still rejects unknown commands') do
        assert_raises(ArgumentError) { EGC::UI::Commands.dispatch(:not_a_command) }
      end

      test('open_dialog is safe to call from the Ruby console with no arguments') do
        assert(EGC::UI::Commands.open_dialog(EGC::Scene::Document.new('console')).is_a?(Hash))
      end
    end

    # --------------------------------------------------------- package layout
    # Guards the exact bug that shipped: a nested EGC_Builder directory.
    suite('package/layout') do
      test('src root contains exactly EGC_Builder.rb and one EGC_Builder directory') do
        entries = Dir.children(SRC_ROOT).reject { |e| e.start_with?('.') }
        assert_includes(entries, 'EGC_Builder.rb')
        assert_includes(entries, 'EGC_Builder')
        dirs = entries.select { |e| File.directory?(File.join(SRC_ROOT, e)) }
        assert_equal(['EGC_Builder'], dirs,
                     "src/ must hold a single extension directory, found #{dirs.inspect}")
      end

      test('there is no nested EGC_Builder directory anywhere in src/') do
        nested = Dir.glob(File.join(SRC_ROOT, '**', 'EGC_Builder'))
                    .reject { |p| File.dirname(p) == SRC_ROOT }
        assert_equal([], nested, "nested extension directories would break 'EGC_Builder/main'")
      end

      test('required runtime paths are present in the extension directory') do
        ext = File.join(SRC_ROOT, 'EGC_Builder')
        %w[loader.rb main.rb materials.json core model ops ui assets].each do |rel|
          assert(File.exist?(File.join(ext, rel)), "missing EGC_Builder/#{rel}")
        end
      end

      test('main.rb sits exactly where EGC_Builder.rb registers it') do
        # 'EGC_Builder/main' relative to Plugins/ == src/EGC_Builder/main.rb here.
        registered = File.join(SRC_ROOT, 'EGC_Builder', 'main.rb')
        assert(File.exist?(registered), "registered path 'EGC_Builder/main' does not resolve")
      end

      test('the root loader registers the flat path, never a doubled one') do
        src = File.read(File.join(SRC_ROOT, 'EGC_Builder.rb'))
        assert_match(/SketchupExtension\.new\(\s*'E\.G\.C Builder'\s*,\s*'EGC_Builder\/main'\s*\)/, src,
                     'register_extension must ask for EGC_Builder/main')
        refute(src.include?('EGC_Builder/EGC_Builder'), 'loader must not register a nested path')
      end

      test('every loadable module is listed exactly once in the manifest') do
        mods = EGC::MODULES
        assert(mods.length >= 31, "expected 31+ modules, manifest has #{mods.length}")
        assert_equal(mods.length, mods.uniq.length, 'manifest contains duplicates')
        assert_includes(mods, 'ui/dialog')
        assert_includes(mods, 'ui/commands')
        assert_includes(mods, 'ui/menu')
      end

      test('every manifest entry has a corresponding file') do
        EGC::MODULES.each do |rel|
          assert(File.exist?(File.join(SRC_ROOT, 'EGC_Builder', "#{rel}.rb")),
                 "manifest lists #{rel} but the file is missing")
        end
      end

      test('the dimensional contract was not touched by packaging work') do
        assert_equal('0a4c347975b826b427f848f73d5abb14516e718f14e46dccb819b097984b297f',
                     EGC::Constants.fingerprint)
        assert_equal(68, EGC::Constants::FROZEN.length, 'frozen value count must stay at 68')
        assert_close(4.4,  EGC::Constants::SAW_KERF,    1e-9, 'kerf must stay 4.4')
        assert_close(10.0, EGC::Constants::BORDER_TRIM, 1e-9, 'trim must stay 10.0')
      end
    end
  end
end
