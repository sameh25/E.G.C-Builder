# encoding: UTF-8
# frozen_string_literal: true
#
# Cutlist (§2) - aggregated bill of panels with a content-addressed cache.
#
# CACHE CONTRACT
# --------------
# The cache key is a SHA-256 over the *current part geometry*. Any resize
# changes that signature, so the next read recomputes. `invalidate_cache!`
# is still called explicitly by ProductionSync so a read that happens in the
# same tick as an edit can never return stale rows.
#
# Outputs: array of rows, CSV, and a per-material summary.

require 'csv'

module EGC
  module Ops
    module Cutlist
      module_function

      @cache = {}
      @generation = 0
      @last_reason = nil

      class << self
        attr_reader :generation, :last_reason

        def invalidate_cache!(reason = :manual)
          @cache.clear
          @generation += 1
          @last_reason = reason
          EGC::Log.debug("cutlist cache invalidated (#{reason}) gen=#{@generation}")
          @generation
        end

        def cache_size
          @cache.length
        end

        def cached?(doc)
          @cache.key?(key_for(doc))
        end

        private
      end

      def key_for(doc)
        "#{doc.object_id}:#{doc.signature}:#{@generation}"
      end

      # ---- collection ---------------------------------------------------
      def parts_for(doc, include_worktop: true)
        list = doc.parts.dup
        list.reject! { |p| p.role == EGC::Model::Part::ROLE_ROD } unless include_worktop
        list
      end

      # Collapse identical parts into rows with quantity.
      def build_rows(doc)
        key = key_for(doc)
        cached = @cache[key]
        return cached if cached

        groups = {}
        parts_for(doc).each do |p|
          gk = p.group_key
          if groups.key?(gk)
            groups[gk][:qty] += 1
            groups[gk][:ids] << p.id
          else
            groups[gk] = {
              :role => p.role,
              :material => p.material.key,
              :length => p.length.round(1),
              :width => p.width.round(1),
              :thickness => p.thickness.round(1),
              :cut_length => p.cut_length,
              :cut_width => p.cut_width,
              :edgeband => p.edgeband.to_code,
              :grain => p.grain?,
              :qty => 1,
              :ids => [p.id],
              :cabinet_id => p.cabinet_id,
              :area_m2 => 0.0
            }
          end
        end

        rows = groups.values.map do |r|
          r[:area_m2] = (r[:length] * r[:width] / 1_000_000.0 * r[:qty]).round(4)
          r
        end

        rows.sort_by! { |r| [r[:material].to_s, -r[:length], -r[:width]] }
        @cache[key] = rows
        rows
      end

      # ---- CSV -----------------------------------------------------------
      HEADER = ['Role', 'Material', 'Length mm', 'Width mm', 'Thickness mm',
                'Cut L mm', 'Cut W mm', 'Edgeband', 'Grain', 'Qty', 'Area m2', 'Cabinet'].freeze

      def to_csv(doc)
        CSV.generate do |csv|
          csv << HEADER
          build_rows(doc).each do |r|
            csv << [r[:role], r[:material], r[:length], r[:width], r[:thickness],
                    r[:cut_length], r[:cut_width], r[:edgeband],
                    (r[:grain] ? 'Y' : 'N'), r[:qty], r[:area_m2], r[:cabinet_id]]
          end
        end
      end

      def write_csv(doc, path)
        data = to_csv(doc)
        File.write(path, data)
        path
      end

      # ---- public entry point (§2 / Test 2) -------------------------------
      # Kept for compatibility with the released test scripts and the legacy
      # call-sites: EGC::Cutlist.generate(doc) returns the row set.
      def generate(doc, opts = {})
        rows = build_rows(doc)
        return rows unless opts[:format]
        case opts[:format].to_sym
        when :csv then to_csv(doc)
        when :rows, :array then rows
        when :summary then by_material(doc)
        else rows
        end
      end

      # ---- summary --------------------------------------------------------
      def by_material(doc)
        out = {}
        build_rows(doc).each do |r|
          m = (out[r[:material]] ||= { :qty => 0, :area_m2 => 0.0, :parts => 0 })
          m[:qty] += r[:qty]
          m[:area_m2] = (m[:area_m2] + r[:area_m2]).round(4)
          m[:parts] += 1
        end
        out
      end

      def total_parts(doc)
        build_rows(doc).sum { |r| r[:qty] }
      end

      def total_area_m2(doc)
        build_rows(doc).sum { |r| r[:area_m2] }.round(4)
      end
    end
  end
end
