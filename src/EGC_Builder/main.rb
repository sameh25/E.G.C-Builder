# encoding: UTF-8
# frozen_string_literal: true
#
# main.rb - deferred engine bootstrap, called once by SketchUp when the
# extension is registered.
#
# Kept deliberately thin: it loads the engine, verifies the frozen dimension
# contract, then wires the menu. If the integrity check fails the extension
# refuses to start rather than shipping wrong sizes to a saw.

require_relative 'loader'

module EGC
  module Bootstrap
    module_function

    def start
      # Refuse to run on a drifted dimensional contract.
      begin
        EGC::Constants.verify!
      rescue EGC::IntegrityError => e
        EGC::Log.error(e.message)
        raise
      end

      # Optional data overlay (never overrides built-in grain/thickness).
      json = File.join(EGC::ROOT, 'materials.json')
      EGC::Model::Materials.load_from_json!(json)

      EGC::UI::Menu.build if EGC::UI::Menu.sketchup?

      EGC::Log.info("E.G.C Builder v#{EGC::VERSION} started")
      true
    end
  end
end

EGC::Bootstrap.start
