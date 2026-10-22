# frozen_string_literal: true

# Headless test for the 1.28.68 worktop hard-barrier rule.
#
# kitchen.rb loads without SketchUp, so the pure geometry decisions can be exercised
# directly with stub groups. This is the check that proves the marble stops at a
# tower instead of bridging it - syntax checking alone cannot show that.
#
#   ruby test/test_worktop_barrier.rb

$LOAD_PATH.unshift(File.expand_path('../work/egc_builder', __dir__))
require 'kitchen'
# kitchen.rb itself only requires 'json'. In the real extension main.rb loads every
# module, so EGC::Cabinet is present when base_kind? runs; the harness must do the
# same or base_kind? rescues to false and the height assertions prove nothing.
require 'cabinet'

K = EGC::Kitchen

# --- minimal stand-ins for SketchUp types -----------------------------------
class FakeLen
  def initialize(mm) = @mm = mm
  def to_mm = @mm
end

class FakeOrigin
  def initialize(x) = @x = x
  def x = FakeLen.new(@x)
end

class FakeTr
  def initialize(x) = @x = x
  def origin = FakeOrigin.new(@x)
end

# A cabinet group: x origin, width, height, stored kind, optional conversion flag.
# A real cabinet always carries a 'spec' JSON attribute and base_kind? derives from
# it, so the fixture must provide one - otherwise base_kind? rescues to false and a
# height test would "pass" through the cfg fallback instead of proving exclusion.
class FakeCab
  attr_reader :name

  def initialize(x, w, h, kind: 'base', conv: false, name: nil)
    @x = x
    @w = w
    @h = h
    @kind = kind
    @conv = conv
    @name = name || "#{kind}@#{x}"
  end

  def valid? = true
  def transformation = FakeTr.new(@x)

  def get_attribute(_dict, key)
    case key
    when 'w' then @w
    when 'h' then @h
    when 'kind' then @kind
    when 'spec' then JSON.generate({ 'kind' => @kind, 'w' => @w, 'h' => @h })
    when 'converted_from_code' then @conv ? 'C01' : nil
    end
  end
end

$pass = 0
$fail = 0

def check(label, got, want)
  if got == want
    $pass += 1
    puts "  PASS  #{label}"
  else
    $fail += 1
    puts "  FAIL  #{label}\n        got:  #{got.inspect}\n        want: #{want.inspect}"
  end
end

def spans_of(runs)
  runs.map { |seg| K.run_span(seg).map(&:round) }
end

puts '== barrier detection =='
check('900 mm base is not a barrier', K.worktop_barrier?(FakeCab.new(0, 600, 900)), false)
check('1100 mm exactly is not a barrier (rule is strictly >)', K.worktop_barrier?(FakeCab.new(0, 600, 1100)), false)
check('1101 mm base is a barrier', K.worktop_barrier?(FakeCab.new(0, 600, 1101)), true)
check('2300 mm resized base is a barrier (kind still base)', K.worktop_barrier?(FakeCab.new(0, 600, 2300)), true)
check('kind tall at 900 mm is a barrier', K.worktop_barrier?(FakeCab.new(0, 600, 900, kind: 'tall')), true)
check('converted-from code is a barrier', K.worktop_barrier?(FakeCab.new(0, 600, 900, conv: true)), true)

puts
puts '== THE REPORTED BUG: base resized to tower with bases on both sides =='
# base 0-600, tower 600-1200 (resized base, h 2300), base 1200-1800
b1 = FakeCab.new(0, 600, 900)
tw = FakeCab.new(600, 600, 2300)
b2 = FakeCab.new(1200, 600, 900)
all = [b1, tw, b2]

carriers = all.reject { |g| K.worktop_barrier?(g) }
check('tower is dropped from the carriers', carriers.map(&:name), [b1.name, b2.name])

runs = K.worktop_runs(carriers)
check('carriers split into TWO separate slab runs', runs.size, 2)
check('run spans butt at the tower gables', spans_of(runs), [[0, 600], [1200, 1800]])

# The old rule: one min()/max() across the survivors -> one slab straight over it.
old_start = carriers.map { |g| g.transformation.origin.x.to_mm }.min
old_end = carriers.map { |g| g.transformation.origin.x.to_mm + g.get_attribute('egc', 'w').to_f }.max
check('OLD behaviour bridged the tower (this is the bug)', [old_start, old_end], [0, 1800])
new_spans = spans_of(runs)
check('NEW behaviour never spans a 600..1200 crossing',
      new_spans.any? { |(a, b)| a < 600 && b > 1200 }, false)

puts
puts '== contiguous run is NOT split =='
check('three touching bases stay one run',
      spans_of(K.worktop_runs([FakeCab.new(0, 600, 900), FakeCab.new(600, 600, 900), FakeCab.new(1200, 600, 900)])),
      [[0, 1800]])
check('unit overlapping its neighbour does not open a gap',
      spans_of(K.worktop_runs([FakeCab.new(0, 600, 900), FakeCab.new(598, 600, 900)])), [[0, 1198]])

puts
puts '== island end cases =='
check('tower at the start: one run after it',
      spans_of(K.worktop_runs([FakeCab.new(0, 600, 900), FakeCab.new(600, 600, 900)].reject { false })), [[0, 1200]])
check('tower first then base: run starts at the tower gable',
      spans_of(K.worktop_runs([FakeCab.new(600, 600, 900)])), [[600, 1200]])
check('only a tower: no carriers left -> no runs',
      K.worktop_runs([].reject { false }), [])

puts
puts '== slab height never follows a tower =='
cfg = { 'base_h' => 900.0 }
check('tower does not vote on slab height',
      K.slab_reference_h([b1, tw, b2], cfg), 900.0)
check('a 2300 mm base does not lift the plane',
      K.slab_reference_h([FakeCab.new(0, 600, 2300)], cfg), 900.0)
check('genuine base height is used when below the counter',
      K.slab_reference_h([FakeCab.new(0, 600, 850)], cfg), 850.0)

puts
puts "#{$fail.zero? ? 'ALL CHECKS PASSED' : "#{$fail} FAILED"} (#{$pass} passed, #{$fail} failed)"
exit($fail.zero? ? 0 : 1)
