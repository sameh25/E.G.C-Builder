# encoding: UTF-8
# frozen_string_literal: true
#
# Loader. Requires every engine file in dependency order.
# No SketchUp API calls happen at load time except the guarded boot block at
# the bottom, so this file is safe to require from a plain Ruby process.

require 'digest'

module EGC
  ROOT = File.dirname(__FILE__) unless defined?(ROOT)

  # Dependency-ordered manifest. The regression suite walks this list to prove
  # every module loads and exposes its expected API (§5 "31+ modules audit").
  MODULES = [
    'core/version',
    'core/errors',
    'core/units',
    'core/logger',
    'core/geom',
    'core/constants',
    'core/scene',
    'model/materials',
    'model/edgeband',
    'model/part',
    'model/hardware',
    'model/carcass',
    'model/doors',
    'model/cabinet',
    'model/wardrobe',
    'ops/production_sync',
    'ops/cutlist',
    'ops/cam',
    'ops/nesting',
    'ops/exec_worktop',
    'ops/assistant_edit',
    'ops/space_tool',
    'ops/interference',
    'ops/corner',
    'ops/appliances',
    'ops/snap',
    'ops/audit',
    'core/aliases',
    'ui/menu',
    'ui/commands',
    'ui/dialog'
  ].freeze

  def self.load_all!
    @loaded = []
    MODULES.each do |rel|
      path = File.join(ROOT, "#{rel}.rb")
      raise EGC::Error, "missing module #{path}" unless File.exist?(path)
      require path
      @loaded << rel
    end
    true
  end

  # Files that this loader actually required, in order.
  def self.loaded
    @loaded ||= []
  end

  def self.loaded_modules
    MODULES.map { |m| m.split('/').last }
  end
end

EGC.load_all!
