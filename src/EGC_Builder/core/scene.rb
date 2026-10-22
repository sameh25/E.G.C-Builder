# encoding: UTF-8
# frozen_string_literal: true
#
# Scene abstraction.
#
# All engine code works against EGC::Scene::Document. In SketchUp the document
# is filled from / flushed to the live model; headless (tests, CLI) it is the
# only store. This keeps every logic path testable without SketchUp installed.

require 'securerandom'

module EGC
  module Scene
    # A SketchUp-compatible attribute dictionary store.
    class AttributeStore
      def initialize
        @dicts = {}
      end

      def set(dict, key, value)
        (@dicts[dict.to_s] ||= {})[key.to_s] = value
        value
      end

      def get(dict, key, default = nil)
        d = @dicts[dict.to_s]
        return default if d.nil?
        d.key?(key.to_s) ? d[key.to_s] : default
      end

      def dictionary?(dict)
        @dicts.key?(dict.to_s)
      end

      def keys(dict)
        (@dicts[dict.to_s] || {}).keys
      end

      def to_h
        Marshal.load(Marshal.dump(@dicts))
      end

      def wipe(dict)
        @dicts.delete(dict.to_s)
      end
    end

    # Observers receive :cabinet_added / :cabinet_removed / :cabinet_changed /
    # :parts_changed / :document_reset.
    module Observable
      def subscribe(&blk)
        (@observers ||= []) << blk
        blk
      end

      def unsubscribe(blk)
        (@observers ||= []).delete(blk)
      end

      def subscribers
        @observers ||= []
      end

      def notify(event, payload = nil)
        subscribers.each do |blk|
          begin
            blk.call(event, payload)
          rescue StandardError => e
            EGC::Log.error("observer failed on #{event}: #{e.message}")
          end
        end
      end
    end

    # The authoritative in-memory model of an EGC job.
    class Document
      include Observable

      TOE  = 'EGC_TOE'
      CAB  = 'EGC_CABINET'
      PART = 'EGC_PART'
      META = 'EGC_META'

      attr_reader :attributes, :revision, :parts_index, :dirty_flags

      def initialize(name = 'EGC Document')
        @name = name
        @cabinets = []
        @by_id = {}
        @parts_index = {}
        @attributes = AttributeStore.new
        @revision = 0
        @dirty_flags = {}
        @observers = []
        @attributes.set(META, 'version', EGC::VERSION)
        @attributes.set(META, 'created_at', Time.now.strftime('%Y-%m-%dT%H:%M:%S'))
      end

      attr_reader :name

      # ---- cabinets ----------------------------------------------------
      def cabinets
        @cabinets
      end

      def add_cabinet(cab)
        raise ArgumentError, 'cabinet already belongs to a document' if cab.document && !cab.document.equal?(self)
        @cabinets << cab
        @by_id[cab.id] = cab
        cab.attach(self)
        touch!(:cabinet_added)
        notify(:cabinet_added, cab)
        cab
      end

      def remove_cabinet(cab)
        @cabinets.delete(cab)
        @by_id.delete(cab.id)
        cab.parts.each { |p| @parts_index.delete(p.id) }
        touch!(:cabinet_removed)
        notify(:cabinet_removed, cab)
        cab
      end

      def find(id)
        @by_id[id]
      end

      def find_by_name(name)
        @cabinets.find { |c| c.name == name }
      end

      def clear!
        @by_id.clear
        @cabinets = []
        @parts_index = {}
        touch!(:document_reset)
        notify(:document_reset, nil)
        self
      end

      # ---- parts -------------------------------------------------------
      # Called by Cabinet#rebuild! after part regeneration.
      def reindex_parts!(cab)
        cab.parts.each { |p| @parts_index[p.id] = p }
        notify(:parts_changed, cab)
      end

      def parts
        @parts_index.values
      end

      # ---- revisions ---------------------------------------------------
      def touch!(reason = nil)
        @revision += 1
        @dirty_flags[reason] = @revision if reason
        @revision
      end

      def dirty?(reason = nil)
        return @dirty_flags.any? if reason.nil?
        @dirty_flags.key?(reason)
      end

      def mark_clean!(reason = nil)
        if reason
          @dirty_flags.delete(reason)
        else
          @dirty_flags.clear
        end
      end

      # Stable content signature used by caches (§2).
      def signature
        parts_sig = parts.map { |p| "#{p.id}:#{p.code}:#{p.length.round(2)}x#{p.width.round(2)}x#{p.thickness.round(2)}" }.sort
        cab_sig = @cabinets.map { |c| "#{c.id}:#{format('%.2f', c.width)}x#{format('%.2f', c.height)}x#{format('%.2f', c.depth)}:#{c.effective_tag}" }.sort
        Digest::SHA256.hexdigest((parts_sig + cab_sig).join('|'))
      end

      def inspect
        "#<EGC::Scene::Document #{@name} cabinets=#{@cabinets.length} parts=#{@parts_index.length} rev=#{@revision}>"
      end
    end
  end
end
