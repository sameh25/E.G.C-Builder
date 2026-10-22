# encoding: UTF-8
# frozen_string_literal: true
#
# Centralised logging + warning audit.
# The regression suite asserts that the warning buffer stays empty for every
# auxiliary tool (§5 "zero console warnings").

module EGC
  module Log
    LEVELS = { :debug => 0, :info => 1, :warn => 2, :error => 3 }.freeze

    @level    = :warn
    @buffer   = []
    @auditing = false

    class << self
      attr_reader :buffer

      def level=(value)
        raise ArgumentError, "unknown log level #{value.inspect}" unless LEVELS.key?(value)
        @level = value
      end

      def level
        @level
      end

      def enabled?(lvl)
        LEVELS.fetch(lvl, 1) >= LEVELS.fetch(@level, 2)
      end

      def reset!
        @buffer = []
        @auditing = true
        self
      end

      def stop_audit!
        @auditing = false
        self
      end

      def auditing?
        @auditing
      end

      def warnings
        @buffer.select { |r| r[:level] == :warn }
      end

      def errors
        @buffer.select { |r| r[:level] == :error }
      end

      def records
        @buffer.dup
      end

      def clear!
        @buffer = []
        self
      end

      def emit(lvl, message, context = nil)
        rec = { :level => lvl, :message => message.to_s, :context => context, :at => Time.now }
        @buffer << rec if @auditing || lvl != :debug
        return rec unless enabled?(lvl)
        $stderr.puts(format_line(rec)) if lvl == :error
        $stdout.puts(format_line(rec)) if lvl == :warn
        rec
      end

      def debug(msg, ctx = nil)
        emit(:debug, msg, ctx)
      end

      def info(msg, ctx = nil)
        emit(:info, msg, ctx)
      end

      def warn(msg, ctx = nil)
        emit(:warn, msg, ctx)
      end

      def error(msg, ctx = nil)
        emit(:error, msg, ctx)
      end

      # Runs a block and reports any warning it produced. Never raises.
      def check(label)
        before = warnings.length
        result = yield
        produced = warnings[before..-1] || []
        [result, produced.map { |r| "#{label}: #{r[:message]}" }]
      end

      private

      def format_line(rec)
        ctx = rec[:context] ? " [#{rec[:context]}]" : ''
        "[EGC #{rec[:level].to_s.upcase}] #{rec[:message]}#{ctx}"
      end
    end
  end
end
