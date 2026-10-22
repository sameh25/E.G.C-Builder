# frozen_string_literal: true

require 'json'
require 'time'

module EGC
  # Local diagnostic log (JSON lines). One line per important operation result: operation_id, plugin version, what was being
  # built (unit / mechanism / device id), the requested dimensions, the exception with a short stack trace and the resulting state.
  # Only technical data about the operation is written - no model content, file paths of the user's files or personal data.
  # The user only sees a short message plus the operation id; the details live in this file.
  module Diag
    module_function

    MAX_BYTES = 2_000_000
    @seq = 0

    def dir
      base = ENV['APPDATA'] || ENV['HOME'] || Dir.pwd
      File.join(base, 'EGC_Builder')
    end

    def path
      @path_override || File.join(dir, 'diagnostics.log')
    end

    # tests / tools may redirect the log
    def path=(p)
      @path_override = p
    end

    def new_id(name)
      @seq += 1
      "#{name.to_s.gsub(/\W+/, '_')}-#{Time.now.strftime('%H%M%S')}-#{@seq}"
    end

    def version
      defined?(EGC::PLUGIN_VERSION) ? EGC::PLUGIN_VERSION : (defined?(PLUGIN_VERSION) ? PLUGIN_VERSION : '?')
    end

    # ctx: { unit:, mechanism:, device:, w:, h:, d:, ... }  state: 'ok' | 'refused' | 'failed' | 'simplified' ...
    def log(op, ctx = {}, error: nil, state: nil, id: nil)
      id ||= new_id(op)
      rec = { 'operation_id' => id, 'time' => Time.now.utc.iso8601, 'egc_version' => version, 'operation' => op.to_s,
              'context' => ctx.transform_keys(&:to_s), 'state' => state || (error ? 'failed' : 'ok') }
      if error
        rec['exception'] = { 'class' => error.class.name, 'message' => error.message.to_s[0, 400],
                             'backtrace' => (error.backtrace || []).first(12).map { |l| l.to_s.sub(%r{\A.*/egc_builder/}, 'egc_builder/') } }
      end
      FileUtils.mkdir_p(File.dirname(path)) if defined?(FileUtils) || require('fileutils')
      File.rename(path, "#{path}.1") if File.file?(path) && File.size(path) > MAX_BYTES
      File.open(path, 'a:UTF-8') { |f| f.puts(JSON.generate(rec)) }
      id
    rescue StandardError
      id
    end

    # Short user-facing text. Controlled refusals (fit / mechanism rules) already carry a readable reason; anything else is
    # reduced to a one-line message + the operation id that can be found in the log.
    def user_message(error, id)
      message = error.message.to_s.gsub(/[\r\n\t]+/, ' ').strip
      message = error.class.name if message.empty?
      message = message[0, 420]
      "#{message} [#{id}]"
    end

    def read_last(n = 20)
      return [] unless File.file?(path)

      File.readlines(path, chomp: true).last(n).map { |l| JSON.parse(l) rescue nil }.compact
    end
  end
end
