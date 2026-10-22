# encoding: UTF-8
# frozen_string_literal: true
#
# Headless regression runner.
#
#   ruby test/run_tests.rb            # full suite
#   ruby test/run_tests.rb --verbose  # per-test output
#   ruby test/run_tests.rb --suite ops/nesting
#
# Exit code 0 = all green, 1 = failures. Safe for CI.

require_relative 'harness/sketchup_stub'
require_relative 'harness/framework'
require 'EGC_Builder/loader'

# Suites are registered as a side effect of requiring these files.
require_relative 'suites/core_suites'
require_relative 'suites/model_suites'
require_relative 'suites/ops_suites'
require_relative 'suites/ui_suites'

module EGC
  module Test
    module Runner
      module_function

      def run(argv = [])
        verbose = argv.include?('--verbose')
        only = argv.each_with_index.find { |a, _| a == '--suite' }&.then { |(_, i)| argv[i + 1] }

        suite_count = EGC::Test.suites.length
        ctx = EGC::Test::Context.new

        results = if only
                    EGC::Test.suites.select { |s| s.name == only }.flat_map { |s| s.run(ctx) }
                  else
                    EGC::Test.suites.flat_map { |s| s.run(ctx) }
                  end

        failures = results.reject { |r| r[:ok] }

        if verbose
          results.each do |r|
            puts format('  %s %-28s %s', r[:ok] ? 'ok  ' : 'FAIL', r[:suite], r[:test])
            puts "        #{r[:error]}" unless r[:ok]
          end
          puts
        end

        # Grouped failure report
        unless failures.empty?
          puts "\nFAILURES"
          puts '=' * 78
          failures.group_by { |f| f[:suite] }.each do |suite, list|
            puts "\n#{suite}:"
            list.each do |f|
              puts "  x #{f[:test]}"
              puts "      #{f[:error]}"
            end
          end
          puts
        end

        puts '=' * 78
        puts format('EGC %s regression: %d suites, %d tests, %d passed, %d failed',
                    EGC::VERSION, suite_count, results.length, results.length - failures.length, failures.length)
        puts '=' * 78

        failures.empty?
      end
    end
  end
end

ok = EGC::Test::Runner.run(ARGV)
exit(ok ? 0 : 1)
