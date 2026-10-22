# frozen_string_literal: true

module EGC
  # Some third-party SketchUp extensions monkey-patch Array/Enumerable (Array#sum has been seen returning nil after
  # such a patch, crashing kitchen.rb's auto_columns with "nil can't be coerced into Float"). E.G.C's own numeric
  # totals never call #sum: they use this instead, which only relies on #each and Numeric#+ - if THAT is broken,
  # nothing in Ruby works anyway. Never monkey-patches Array/Enumerable itself.
  module Num
    module_function

    def sum(enum, init = 0)
      acc = init
      enum.each { |x| acc += (block_given? ? yield(x) : x) }
      acc
    end
  end
end
