# encoding: UTF-8
# frozen_string_literal: true
#
# commands - the single dispatch table behind every menu item.
#
# Each command is a pure function of (document, options) so it can be invoked
# from a menu, from the Ruby Console, or from the regression suite with
# identical behaviour.

module EGC
  module UI
    module Commands
      module_function

      # Active document. In SketchUp this is rebuilt from the live model; in
      # headless runs the caller supplies one.
      def default_document
        @document ||= EGC::Scene::Document.new('Untitled')
      end

      def document=(doc)
        @document = doc
      end

      def sketchup?
        defined?(::Sketchup) && ::Sketchup.respond_to?(:version)
      end

      def dispatch(command, doc = nil, opts = {})
        doc ||= default_document
        case command.to_sym
        when :run_audit          then run_audit(doc, opts)
        when :generate_worktops  then generate_worktops(doc, opts)
        when :export_cutlist     then export_cutlist(doc, opts)
        when :nest_panels        then nest_panels(doc, opts)
        when :export_dxf         then export_dxf(doc, opts)
        when :space_tool         then space_tool(doc, opts)
        when :resync             then resync(doc, opts)
        when :run_regression     then run_regression(doc, opts)
        else
          raise ArgumentError, "unknown command #{command.inspect}"
        end
      end

      # ---- commands -------------------------------------------------------
      def run_audit(doc, _opts = {})
        EGC::Ops::Audit.run(doc)
      end

      def generate_worktops(doc, opts = {})
        plan = EGC::Ops::ExecWorktop.plan(doc, opts)
        parts = EGC::Ops::ExecWorktop.to_parts(plan)
        {
          :plan => plan,
          :parts => parts,
          :segments => plan[:segments].length,
          :max_top_z => plan[:segments].map { |s| s[:z1] }.max,
          :towers_excluded => plan[:tower_count]
        }
      end

      def export_cutlist(doc, opts = {})
        if opts[:path]
          EGC::Ops::Cutlist.write_csv(doc, opts[:path])
          { :path => opts[:path], :rows => EGC::Ops::Cutlist.build_rows(doc).length }
        else
          { :csv => EGC::Ops::Cutlist.to_csv(doc), :rows => EGC::Ops::Cutlist.build_rows(doc).length }
        end
      end

      def nest_panels(doc, opts = {})
        parts = doc.parts.reject { |p| p.role == EGC::Model::Part::ROLE_ROD }
        result = EGC::Ops::Nesting.nest(parts, opts)
        result.merge(:validation => EGC::Ops::Nesting.validate(result))
      end

      def export_dxf(doc, opts = {})
        nested = opts[:nest_result] || nest_panels(doc, opts)
        if opts[:path]
          EGC::Ops::CAM.write_dxf(nested[:sheets], opts[:path])
          { :path => opts[:path], :sheets => nested[:sheet_count] }
        else
          { :sheets => nested[:sheet_count], :dxf => EGC::Ops::CAM.export_dxf(nested[:sheets]) }
        end
      end

      def space_tool(doc, opts = {})
        point = opts[:point]
        raise ArgumentError, 'space_tool requires :point => [x,y,z]' if point.nil?
        hit = EGC::Ops::SpaceTool.hit_test(doc, EGC::Geom::Vec3.new(*point))
        return { :hit => nil } if hit.nil?
        hl = EGC::Ops::SpaceTool.highlight(hit)
        if opts[:insert]
          { :hit => hit, :highlight => hl,
            :inserted => EGC::Ops::SpaceTool.insert(hit, opts[:insert], opts[:params] || {}) }
        else
          { :hit => hit, :highlight => hl }
        end
      end

      def resync(doc, _opts = {})
        n = EGC::Ops::ProductionSync.resync_document!(doc)
        { :parts_refreshed => n, :cutlist_generation => EGC::Ops::Cutlist.generation,
          :cam_generation => EGC::Ops::CAM.generation }
      end

      def run_regression(doc, _opts = {})
        EGC::Ops::Audit.run(doc)
      end
    end
  end
end
