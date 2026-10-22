# encoding: UTF-8
# frozen_string_literal: true
#
# menu - SketchUp menu wiring.
#
# Every SketchUp API reference is behind `sketchup?`. The file therefore loads
# and can be unit-tested in a plain Ruby process without defining stubs.

module EGC
  module UI
    module Menu
      module_function

      def sketchup?
        defined?(::Sketchup) && ::Sketchup.respond_to?(:version)
      end

      # Menu item descriptors. Built without touching the API so tests can
      # assert the command surface without a SketchUp host.
      def items
        [
          { :id => 'egc_audit',            :label => 'System Audit',          :command => :run_audit },
          { :id => 'egc_worktop',          :label => 'Generate Worktops',     :command => :generate_worktops },
          { :id => 'egc_cutlist',          :label => 'Export Cutlist CSV',    :command => :export_cutlist },
          { :id => 'egc_nesting',          :label => 'Nest Panels',           :command => :nest_panels },
          { :id => 'egc_dxf',              :label => 'Export DXF',            :command => :export_dxf },
          { :id => 'egc_space_tool',       :label => 'Space Tool',            :command => :space_tool },
          { :id => 'egc_resync',           :label => 'Resync Production Data', :command => :resync },
          { :separator => true },
          { :id => 'egc_selftest',         :label => 'Run Regression Suite',  :command => :run_regression }
        ]
      end

      def build(submenu = nil)
        return items unless sketchup?
        menu = submenu || ::UI.menu('Extensions').add_submenu(EGC::EXTENSION_NAME)
        items.each do |it|
          if it[:separator]
            menu.add_separator
            next
          end
          menu.add_item(it[:label]) { EGC::UI::Commands.dispatch(it[:command]) }
        end
        menu
      end
    end
  end
end
