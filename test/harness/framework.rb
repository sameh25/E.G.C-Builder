# encoding: UTF-8
# frozen_string_literal: true
#
# Minimal assertion framework + suite registry.
# Deliberately dependency-free so it runs identically in this sandbox and in
# the SketchUp Ruby Console.

module EGC
  module Test
    class AssertionFailed < StandardError; end

    # One named suite = one module/file under ops, model, core or ui.
    class Suite
      attr_reader :name, :cases

      def initialize(name)
        @name = name
        @cases = []
      end

      def test(description, &blk)
        @cases << { :description => description, :block => blk }
      end

      def run(ctx)
        results = []
        @cases.each do |c|
          begin
            # instance_exec so assertion helpers resolve as bare method calls
            # inside the test block (the block's lexical self is the Suite).
            ctx.instance_exec(&c[:block])
            results << { :suite => @name, :test => c[:description], :ok => true, :error => nil }
          rescue AssertionFailed => e
            results << { :suite => @name, :test => c[:description], :ok => false, :error => e.message }
          rescue StandardError => e
            results << { :suite => @name, :test => c[:description], :ok => false,
                         :error => "#{e.class}: #{e.message}" }
          end
        end
        results
      end
    end

    # Shared assertion helpers available inside every test block.
    module Assertions
      def assert(cond, message = 'assertion failed')
        raise AssertionFailed, message unless cond
        true
      end

      def assert_equal(expected, actual, message = nil)
        return true if expected == actual
        raise AssertionFailed,
              "#{message || 'values differ'}: expected #{expected.inspect}, got #{actual.inspect}"
      end

      def assert_close(expected, actual, tol = 1e-6, message = nil)
        return true if (expected.to_f - actual.to_f).abs <= tol
        raise AssertionFailed,
              "#{message || 'values differ'}: expected #{expected} +/- #{tol}, got #{actual}"
      end

      def refute(cond, message = 'expected falsy')
        raise AssertionFailed, message if cond
        true
      end

      def assert_nil(value, message = 'expected nil')
        raise AssertionFailed, "#{message}: got #{value.inspect}" unless value.nil?
        true
      end

      def assert_raises(klass = StandardError, message = nil)
        yield
      rescue klass => e
        return e
      rescue StandardError => e
        raise AssertionFailed,
              "#{message || 'wrong error'}: expected #{klass}, got #{e.class}: #{e.message}"
      else
        raise AssertionFailed, "#{message || 'expected an error'} but nothing was raised"
      end

      def assert_includes(collection, item, message = nil)
        return true if collection.include?(item)
        raise AssertionFailed, "#{message || 'not included'}: #{item.inspect} not in #{collection.inspect}"
      end

      def assert_match(pattern, string, message = nil)
        return true if string.to_s =~ pattern
        raise AssertionFailed, "#{message || 'no match'}: #{pattern.inspect} vs #{string.inspect}"
      end
    end

    # Fixture builders shared by every suite. Mixed into the run context so
    # test blocks can call `base(doc, ...)` directly.
    #
    # NOTE: these take a positional options hash (`opts = {}`) rather than
    # keyword arguments so that both call styles work under Ruby 3:
    #     base(doc, x: 0.0)          # keyword-looking -> collected into opts
    #     base(doc, :x => 0.0)       # explicit hash
    module Fixtures
      # Resolved lazily: framework.rb may be required before the engine.
      def toe
        EGC::Constants::TOE_KICK_HEIGHT
      end

      def d(opts, key, default)
        opts.key?(key) ? opts[key] : default
      end

      def base(doc, opts = {})
        cab = EGC::Model::Cabinet.new(
          :base,
          :width => d(opts, :width, 600.0),
          :depth => d(opts, :depth, 560.0),
          :height => d(opts, :height, nil),
          :origin => EGC::Geom::Vec3.new(d(opts, :x, 0.0), 0.0, toe),
          :name => d(opts, :name, nil),
          :material => d(opts, :material, nil)
        )
        doc.add_cabinet(cab)
        cab.rebuild!
        cab
      end

      def tower(doc, opts = {})
        cab = EGC::Model::Cabinet.new(
          d(opts, :tag, :tall),
          :width => d(opts, :width, 600.0),
          :depth => d(opts, :depth, 560.0),
          :height => d(opts, :height, 2100.0),
          :origin => EGC::Geom::Vec3.new(d(opts, :x, 0.0), 0.0, d(opts, :z, 0.0)),
          :name => d(opts, :name, nil)
        )
        doc.add_cabinet(cab)
        cab.rebuild!
        cab
      end

      # Doorless tall wardrobe, the §4 regression subject.
      def open_wardrobe(doc = nil, opts = {})
        doc ||= EGC::Scene::Document.new('wardrobe')
        cab = EGC::Model::Cabinet.new(
          :tall,
          :width => d(opts, :width, 900.0),
          :height => d(opts, :height, 2100.0),
          :depth => d(opts, :depth, 600.0),
          :origin => EGC::Geom::Vec3.new(d(opts, :x, 0.0), 0.0, 0.0),
          :name => 'Open'
        )
        doc.add_cabinet(cab)
        cab.rebuild!
        [doc, cab]
      end

      # A job of `count` base cabinets, returned as a flat part list.
      def nest_parts(count, opts = {})
        material = d(opts, :material, :mdf_plain)
        width = d(opts, :width, 600.0)
        doc = EGC::Scene::Document.new('nest')
        count.times do |i|
          cab = EGC::Model::Cabinet.new(
            :base, :width => width, :depth => 560.0,
            :origin => EGC::Geom::Vec3.new(i * width, 0.0, toe),
            :material => material, :name => "N#{i}"
          )
          doc.add_cabinet(cab)
          cab.rebuild!
        end
        doc.parts.reject { |p| p.role == EGC::Model::Part::ROLE_ROD }
      end
    end

    # The object every test block runs against.
    class Context
      include Assertions
      include Fixtures
    end

    # ---- registry -----------------------------------------------------------
    @suites = []

    class << self
      attr_reader :suites

      def suite(name, &blk)
        s = Suite.new(name)
        s.instance_eval(&blk)
        @suites << s
        s
      end

      def reset!
        @suites = []
      end

      # Runs everything; returns a result hash.
      def run_all(ctx = nil)
        ctx ||= Context.new
        all = @suites.flat_map { |s| s.run(ctx) }
        failures = all.reject { |r| r[:ok] }
        {
          :total => all.length,
          :passed => all.length - failures.length,
          :failed => failures.length,
          :ok => failures.empty?,
          :results => all,
          :failures => failures,
          :suites => @suites.length
        }
      end
    end
  end
end
