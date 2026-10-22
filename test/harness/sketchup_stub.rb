# encoding: UTF-8
# frozen_string_literal: true
#
# Headless harness.
#
# Provides a minimal stand-in for the SketchUp Ruby API so the entire engine
# can be exercised in a plain Ruby process (CI, this sandbox, the CLI test
# runner). The stub is intentionally faithful in the few places the engine
# touches: Length arithmetic, Geom::Point3d, AttributeDictionary semantics and
# the extension registry.
#
# It also proves the "zero console warnings" requirement: EGC::Log records
# every warning so the suite can assert on the buffer.

$LOAD_PATH.unshift(File.expand_path('../../src', __dir__))

# ---------------------------------------------------------------- SketchUp stub
module Sketchup
  VERSION = '2024.0.1'

  def self.version
    VERSION
  end

  def self.register_extension(ext, load_on_start = true)
    (@extensions ||= []) << { :ext => ext, :load => load_on_start }
    true
  end

  def self.extensions
    @extensions ||= []
  end

  def self.find_extension(name)
    extensions.map { |e| e[:ext] }.find { |e| e.respond_to?(:name) && e.name == name }
  end

  def self.statusbar
    @statusbar ||= StatusBar.new
  end

  class StatusBar
    def initialize
      @text = ''
    end

    attr_reader :text

    def set_status_text(text)
      @text = text.to_s
      true
    end
  end
end

# Length arithmetic stub: SketchUp stores lengths in inches as floats.
class Length
  attr_reader :mm

  def initialize(mm)
    @mm = mm.to_f
  end

  def to_f
    @mm / 25.4
  end

  def to_mm
    @mm
  end

  def to_s
    "#{@mm.round(3)}mm"
  end

  def ==(o)
    o.is_a?(Length) && (o.mm - mm).abs < 1e-9
  end
end

module Geom
  class Point3d
    attr_reader :x, :y, :z

    def initialize(x = 0, y = 0, z = 0)
      @x = x.to_f
      @y = y.to_f
      @z = z.to_f
    end
  end

  class BoundingBox
    attr_reader :min, :max

    def initialize(min = Point3d.new, max = Point3d.new)
      @min = min
      @max = max
    end
  end
end

class SketchupExtension
  attr_accessor :name, :description, :version, :creator, :copyright

  def initialize(name, path)
    @name = name
    @path = path
  end
end

module UI
  class MenuStub
    attr_reader :items

    def initialize
      @items = []
    end

    def add_submenu(name)
      m = MenuStub.new
      @items << { :submenu => name, :menu => m }
      m
    end

    def add_item(label, &blk)
      @items << { :label => label, :block => blk }
      true
    end

    def add_separator
      @items << { :separator => true }
      true
    end
  end

  def self.menu(name = 'Plugins')
    MenuStub.new
  end

  def self.messagebox(msg, _type = 0)
    (@messages ||= []) << msg.to_s
    true
  end

  def self.messages
    @messages ||= []
  end
end

# file_loaded? / file_loaded helpers used by the entry point
def file_loaded?(_path)
  false
end

def file_loaded(_path)
  true
end

# ---------------------------------------------------------------- harness API
module Harness
  module_function

  def reset_log!
    if defined?(EGC::Log)
      EGC::Log.clear!
      EGC::Log.reset!
    end
  end

  def warnings
    defined?(EGC::Log) ? EGC::Log.warnings : []
  end

  def errors
    defined?(EGC::Log) ? EGC::Log.errors : []
  end

  def new_document(name = 'Test Job')
    EGC::Scene::Document.new(name)
  end

  # Builds a document with n base cabinets in a row.
  def base_run(count, width: 600.0, depth: esp_depth, gap: 0.0)
    doc = new_document
    count.times do |i|
      cab = EGC::Model::Cabinet.new(
        :base, :width => width, :depth => depth,
        :origin => EGC::Geom::Vec3.new(i * (width + gap), 0.0, EGC::Constants::TOE_KICK_HEIGHT),
        :name => "B#{i + 1}"
      )
      doc.add_cabinet(cab)
      cab.rebuild!
    end
    doc
  end

  def esp_depth
    EGC::Constants::SHELF_SETBACK + EGC::Constants::SHELF_DEPTH_REDUCTION + 460.0
  end
end
