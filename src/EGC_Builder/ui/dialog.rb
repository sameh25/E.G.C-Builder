# encoding: UTF-8
# frozen_string_literal: true
#
# dialog - the HtmlDialog host for ui/ui.html.
#
# `menu.rb` and `commands.rb` reference the dialog assets through `Dialog.path`
# so the HTML/CSS/JS always resolve relative to THIS file's directory, not the
# current working directory (SketchUp does not chdir into the plugin).
#
# In a headless Ruby process `::UI::HtmlDialog` does not exist; every method
# degrades to a no-op that still reports the resolved paths, so the packaging
# test can verify the assets are present and correctly addressed.

module EGC
  module UI
    module Dialog
      module_function

      # Extension directory (…/Plugins/EGC_Builder).
      def root
        File.expand_path('..', __dir__)
      end

      def ui_dir
        File.join(root, 'ui')
      end

      def assets_dir
        File.join(root, 'assets')
      end

      def html_path
        File.join(ui_dir, 'ui.html')
      end

      def css_path
        File.join(ui_dir, 'ui.css')
      end

      def js_path
        File.join(ui_dir, 'ui.js')
      end

      # [path, exists?] for every asset the dialog needs.
      def assets
        {
          :html => html_path,
          :css => css_path,
          :js => js_path,
          :icon => File.join(assets_dir, 'icon.svg')
        }
      end

      def assets_present?
        assets.values.all? { |p| File.exist?(p) }
      end

      def sketchup?
        defined?(::UI) && ::UI.const_defined?(:HtmlDialog)
      end

      # Opens (or re-focuses) the dialog. Returns a small status hash so callers
      # can report whether a real window opened.
      def show(title = nil, opts = {})
        title ||= "#{EGC::EXTENSION_NAME} v#{EGC::VERSION}"

        unless sketchup?
          return { :opened => false, :reason => 'no HtmlDialog (headless)',
                   :html => html_path, :present => assets_present? }
        end

        @dialog ||= begin
          d = ::UI::HtmlDialog.new(
            :dialog_title => title,
            :preferences_key => 'egc_builder_dialog',
            :scrollable => true,
            :resizable => true,
            :width => opts.fetch(:width, 940),
            :height => opts.fetch(:height, 660),
            :min_width => 720,
            :min_height => 480,
            :style => ::UI::HtmlDialog::STYLE_DIALOG
          )
          d.set_file(html_path)
          register_callbacks(d)
          d
        end

        @dialog.show
        { :opened => true, :html => html_path, :present => assets_present? }
      end

      def close
        @dialog.close if @dialog
        @dialog = nil
      end

      # ---- JS <-> Ruby bridge -------------------------------------------
      # Every callback returns JSON so ui.js can parse it directly.
      def register_callbacks(d)
        d.add_action_callback('runAudit') do |_ctx, _payload|
          doc = EGC::UI::Commands.default_document
          report = EGC::Ops::Audit.run(doc, :verbose => true)
          report.merge(:stats => stats_for(doc))
        end

        d.add_action_callback('exportCutlist') do |_ctx, _payload|
          doc = EGC::UI::Commands.default_document
          rows = EGC::Ops::Cutlist.build_rows(doc)
          { :rows => rows.length, :csv => EGC::Ops::Cutlist.to_csv(doc), :stats => stats_for(doc) }
        end

        d.add_action_callback('nestPanels') do |_ctx, _payload|
          doc = EGC::UI::Commands.default_document
          res = EGC::UI::Commands.nest_panels(doc)
          { :sheets => res[:sheet_count], :yield => res[:yield],
            :unplaced => res[:unplaced_count], :stats => stats_for(doc) }
        end

        d.add_action_callback('generateWorktops') do |_ctx, _payload|
          doc = EGC::UI::Commands.default_document
          res = EGC::UI::Commands.generate_worktops(doc)
          { :segments => res[:segments], :max_top_z => res[:max_top_z],
            :towers_excluded => res[:towers_excluded], :stats => stats_for(doc) }
        end
      end

      # Header card values consumed by ui.js.
      def stats_for(doc)
        plan = EGC::Ops::ExecWorktop.plan(doc)
        {
          :version => EGC::VERSION,
          :cabinets => doc.cabinets.length,
          :parts => doc.parts.length,
          :plane => "#{EGC::Constants::STANDARD_COUNTER_HEIGHT.round} mm",
          :contract => 'OK',
          :fingerprint => "#{EGC::Constants.fingerprint[0, 12]}… (#{EGC::Constants::FROZEN.length} values)",
          :segments => plan[:segments].length
        }
      end
    end
  end
end
