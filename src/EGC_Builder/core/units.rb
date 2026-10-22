# encoding: UTF-8
# frozen_string_literal: true
#
# Unit handling. Everything internal is millimetres (Float).
# SketchUp uses inches internally; conversion is explicit and lossless enough
# for cabinet work (rounded only at presentation time).

module EGC
  module Units
    MM_PER_INCH = 25.4

    module_function

    def mm_to_inch(mm)
      mm.to_f / MM_PER_INCH
    end

    def inch_to_mm(inch)
      inch.to_f * MM_PER_INCH
    end

    # SketchUp Length objects behave like floats in inches already.
    def to_mm(value)
      return 0.0 if value.nil?
      return value.to_f if value.is_a?(Numeric)
      return inch_to_mm(value) if value.respond_to?(:to_f)
      0.0
    end

    def round_mm(value, places = 1)
      value.to_f.round(places)
    end

    # 1234.5 -> "1234.5"
    def fmt_mm(value, places = 1)
      s = format("%.#{places}f", value.to_f)
      s.sub(/\.0+\z/, '')
    end

    def m2(area_mm2)
      area_mm2.to_f / 1_000_000.0
    end

    def fmt_m2(area_mm2, places = 3)
      format("%.#{places}f", m2(area_mm2))
    end

    def clamp(value, lo, hi)
      return lo if value < lo
      return hi if value > hi
      value
    end
  end
end
