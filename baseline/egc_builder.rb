# frozen_string_literal: true

# E.G.C Builder - SketchUp extension loader
require 'sketchup.rb'
require 'extensions.rb'

module EGC
  PLUGIN_ID      = 'egc_builder'
  PLUGIN_NAME    = 'E.G.C Builder'
  PLUGIN_VERSION = '1.28.66'
  PLUGIN_DIR     = File.join(File.dirname(__FILE__), 'egc_builder').freeze

  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new(PLUGIN_NAME, File.join(PLUGIN_DIR, 'main'))
    ex.description = 'Parametric kitchen & cabinet builder with cut lists, nesting and cost. ' \
                     'مصمم المطابخ والخزائن الباراميتريك مع قوائم القطع والتقطيع والتكلفة.'
    ex.version   = PLUGIN_VERSION
    ex.copyright = 'E.G.C'
    ex.creator   = 'E.G.C'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end
end
