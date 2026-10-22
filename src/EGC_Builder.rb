# encoding: UTF-8
# frozen_string_literal: true
#
# E.G.C Builder v1.28.67 - SketchUp extension entry point.
#
# This file is what SketchUp loads from the .rbz. It registers the extension
# and defers all engine loading until the extension actually starts, so a
# disabled extension costs nothing.
#
# In a headless Ruby process there is no Sketchup module; the engine can still
# be loaded by requiring 'egc_builder' directly, which is what the regression
# suite does.

require 'sketchup.rb'
require 'extensions.rb'

module EGC
  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('E.G.C Builder', 'EGC_Builder/main')
    ex.description = 'Cabinet & joinery production suite - cutlists, nesting, CAM, wardrobes.'
    ex.version     = '1.28.67'
    ex.creator     = 'E.G.C'
    ex.copyright   = 'E.G.C'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end
end
