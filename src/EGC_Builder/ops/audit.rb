# encoding: UTF-8
# frozen_string_literal: true
#
# audit (§5) - system-wide self-check + zero-warning report.
#
# Runs every subsystem against a live document and proves:
#   * the frozen dimensional contract has not drifted
#   * worktop segments are clamped and clear of towers
#   * nesting output is geometrically legal
#   * wardrobe cavities resolve on doorless units
#   * interference / corner / appliance / snap produce no warnings
#
# The regression suite and the SketchUp report both call this.

module EGC
  module Ops
    module Audit
      module_function

      CHECKS = [
        :check_constants,
        :check_modules_loaded,
        :check_worktop_clamping,
        :check_wardrobe_cavities,
        :check_nesting_geometry,
        :check_interference,
        :check_auxiliary_warnings
      ].freeze

      # Returns a structured report.
      def run(doc, opts = {})
        verbose = opts.fetch(:verbose, false)
        results = []

        results << check_constants
        results << check_modules_loaded
        results << check_worktop_clamping(doc)
        results << check_wardrobe_cavities(doc)
        results << check_nesting_geometry(doc)
        results << check_interference(doc)
        results << check_auxiliary_warnings(doc)

        failures = results.reject { |r| r[:ok] }
        {
          :version => EGC::VERSION,
          :checks => results,
          :check_count => results.length,
          :passed => results.length - failures.length,
          :failed => failures.length,
          :ok => failures.empty?,
          :warnings => EGC::Log.warnings.map { |w| w[:message] },
          :verbose => verbose
        }
      end

      # ---- individual checks ------------------------------------------
      def check_constants
        EGC::Constants.verify!
        {
          :name => 'Dimensional contract (frozen constants)',
          :ok => true,
          :detail => "fingerprint #{EGC::Constants.fingerprint[0, 16]}..., #{EGC::Constants::FROZEN.length} values pinned"
        }
      rescue EGC::IntegrityError => e
        { :name => 'Dimensional contract (frozen constants)', :ok => false, :detail => e.message }
      end

      # Every manifest entry must exist on disk AND have been required by the
      # loader. (Re-requiring is not a valid test: Ruby returns false for an
      # already-loaded file.)
      def check_modules_loaded
        manifest = EGC::MODULES
        missing_files = manifest.reject { |rel| File.exist?(File.join(EGC::ROOT, "#{rel}.rb")) }
        not_loaded = manifest - EGC.loaded

        problems = []
        problems << "missing files: #{missing_files.join(', ')}" unless missing_files.empty?
        problems << "not loaded: #{not_loaded.join(', ')}" unless not_loaded.empty?

        {
          :name => 'Module load integrity',
          :ok => problems.empty?,
          :detail => problems.empty? ? "#{manifest.length} modules loaded" : problems.join('; ')
        }
      end

      def check_worktop_clamping(doc)
        plan = EGC::Ops::ExecWorktop.plan(doc)
        v = EGC::Ops::ExecWorktop.validate(plan)
        max_top = plan[:segments].map { |s| s[:z1] }.max
        {
          :name => 'Worktop plane isolation & butt termination',
          :ok => v[:ok],
          :detail => "#{plan[:segments].length} segments, max top z=#{max_top.inspect}, " \
                     "#{plan[:tower_count]} towers excluded" + (v[:ok] ? '' : "; #{v[:errors].join('; ')}")
        }
      end

      def check_wardrobe_cavities(doc)
        doorless = doc.cabinets.select(&:doorless?)
        problems = []
        doorless.each do |cab|
          begin
            v = EGC::Model::Wardrobe.detect_inner_void(cab)
            problems << "#{cab.name}: empty void" unless v.width.positive? && v.height.positive?
            zones = cab.cavity_zones
            problems << "#{cab.name}: no cavities" if zones.empty?
          rescue StandardError => e
            problems << "#{cab.name}: #{e.class}"
          end
        end
        {
          :name => 'Doorless wardrobe cavity derivation',
          :ok => problems.empty?,
          :detail => "#{doorless.length} doorless units, #{problems.empty? ? 'all cavities resolved' : problems.join('; ')}"
        }
      end

      def check_nesting_geometry(doc)
        parts = doc.parts.reject { |p| p.role == EGC::Model::Part::ROLE_ROD }
        return { :name => 'Nesting geometry', :ok => true, :detail => 'no parts' } if parts.empty?
        result = EGC::Ops::Nesting.nest(parts)
        v = EGC::Ops::Nesting.validate(result)
        {
          :name => 'Nesting geometry (no overlap, inside trim)',
          :ok => v[:ok] && result[:unplaced_count].zero?,
          :detail => "#{result[:sheet_count]} sheets, yield #{(result[:yield] * 100).round(1)}%, " \
                     "#{result[:unplaced_count]} unplaced" + (v[:ok] ? '' : "; #{v[:errors].first(3).join('; ')}")
        }
      end

      def check_interference(doc)
        r = EGC::Ops::Interference.scan_all(doc)
        {
          :name => 'Interference scan',
          :ok => r[:ok],
          :detail => "#{r[:total]} collision(s) across #{doc.cabinets.length} cabinets"
        }
      end

      # The §5 zero-warning gate: run every auxiliary tool and assert that not
      # one of them emits a warning record.
      def check_auxiliary_warnings(doc)
        EGC::Log.clear!
        EGC::Log.reset!

        EGC::Ops::Interference.scan_all(doc)
        EGC::Ops::Corner.detect(doc)
        EGC::Ops::Snap.resolve(doc, [123.0, 456.0, 789.0])
        EGC::Ops::Snap.snap_system32(777.0)
        doc.cabinets.first(3).each do |c|
          EGC::Ops::Appliances.check(c, :microwave)
        end
        EGC::Ops::SpaceTool.hit_test(doc, EGC::Geom::Vec3.new(-9999, -9999, -9999))

        produced = EGC::Log.warnings
        EGC::Log.stop_audit!
        {
          :name => 'Auxiliary tools emit zero console warnings',
          :ok => produced.empty?,
          :detail => produced.empty? ? 'interference/corner/appliances/snap/space_tool: 0 warnings' \
                                     : produced.map { |w| w[:message] }.join('; ')
        }
      end

      # ---- human-readable summary ---------------------------------------
      def format_report(report)
        lines = []
        lines << "#{EGC::EXTENSION_NAME} v#{EGC::VERSION} - System Audit"
        lines << ('=' * 62)
        report[:checks].each do |c|
          lines << format('  [%s] %-46s %s', c[:ok] ? 'PASS' : 'FAIL', c[:name], c[:detail])
        end
        lines << ('-' * 62)
        lines << "  #{report[:passed]}/#{report[:check_count]} checks passed"
        lines.join("\n")
      end
    end
  end
end
