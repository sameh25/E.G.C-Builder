# encoding: UTF-8
# frozen_string_literal: true
#
# Pure-geometry primitives (no SketchUp dependency) so the whole engine can be
# regression-tested headlessly. All units are millimetres.

module EGC
  module Geom
    EPS = 1e-6

    # Immutable 3-D point / vector in millimetres.
    class Vec3
      attr_reader :x, :y, :z

      def initialize(x, y, z)
        @x = x.to_f
        @y = y.to_f
        @z = z.to_f
        freeze
      end

      def +(o)
        Vec3.new(x + o.x, y + o.y, z + o.z)
      end

      def -(o)
        Vec3.new(x - o.x, y - o.y, z - o.z)
      end

      def offset(dx, dy, dz)
        Vec3.new(x + dx, y + dy, z + dz)
      end

      def to_a
        [x, y, z]
      end

      def ==(o)
        o.is_a?(Vec3) && (x - o.x).abs < EPS && (y - o.y).abs < EPS && (z - o.z).abs < EPS
      end
      alias eql? ==

      def hash
        [x.round(4), y.round(4), z.round(4)].hash
      end

      def inspect
        format('Vec3(%.2f, %.2f, %.2f)', x, y, z)
      end
    end

    # Axis-aligned box defined by min/max corners.
    class Box
      attr_reader :min, :max

      def initialize(min, max)
        @min = min
        @max = max
        freeze
      end

      def self.from_whd(origin, width, height, depth)
        new(origin, origin.offset(width, depth, height))
      end

      def width
        max.x - min.x
      end

      def depth
        max.y - min.y
      end

      def height
        max.z - min.z
      end

      def volume
        width * depth * height
      end

      def bottom
        min.z
      end

      def top
        max.z
      end

      def center
        Vec3.new((min.x + max.x) / 2.0, (min.y + max.y) / 2.0, (min.z + max.z) / 2.0)
      end

      def overlaps?(other, tol = 0.0)
        return false unless min.x < other.max.x - tol && max.x > other.min.x + tol
        return false unless min.y < other.max.y - tol && max.y > other.min.y + tol
        return false unless min.z < other.max.z - tol && max.z > other.min.z + tol
        true
      end

      def overlap_volume(other, tol = 0.0)
        return 0.0 unless overlaps?(other, tol)
        dx = [max.x, other.max.x].min - [min.x, other.min.x].max
        dy = [max.y, other.max.y].min - [min.y, other.min.y].max
        dz = [max.z, other.max.z].min - [min.z, other.min.z].max
        [dx, 0.0].max * [dy, 0.0].max * [dz, 0.0].max
      end

      def expanded(tol)
        new(min.offset(-tol, -tol, -tol), max.offset(tol, tol, tol))
      end

      def translate(v)
        Box.new(min + v, max + v)
      end

      def corners
        [
          min,
          Vec3.new(max.x, min.y, min.z),
          Vec3.new(max.x, max.y, min.z),
          Vec3.new(min.x, max.y, min.z),
          Vec3.new(min.x, min.y, max.z),
          Vec3.new(max.x, min.y, max.z),
          max,
          Vec3.new(min.x, max.y, max.z)
        ]
      end

      def inspect
        format('Box(%.1f,%.1f,%.1f .. %.1f,%.1f,%.1f)', min.x, min.y, min.z, max.x, max.y, max.z)
      end
    end

    # 2-D axis-aligned rectangle used by the nesting engine (lower-left origin).
    class Rect
      attr_reader :x, :y, :w, :h

      def initialize(x, y, w, h)
        @x = x.to_f
        @y = y.to_f
        @w = w.to_f
        @h = h.to_f
      end

      def right
        x + w
      end

      def top
        y + h
      end

      def area
        w * h
      end

      def empty?
        w <= EPS || h <= EPS
      end

      def fits?(rw, rh)
        rw <= w + EPS && rh <= h + EPS
      end

      def contains_rect?(o)
        o.x >= x - EPS && o.y >= y - EPS && o.right <= right + EPS && o.top <= top + EPS
      end

      def intersects?(o)
        x < o.right - EPS && right > o.x + EPS && y < o.top - EPS && top > o.y + EPS
      end

      def rotate90
        Rect.new(x, y, h, w)
      end

      def inset(d)
        Rect.new(x + d, y + d, w - 2 * d, h - 2 * d)
      end

      # Split along x = x + pos  ->  [left strip, right strip]
      def split_vertical(pos)
        p = x + pos
        [Rect.new(x, y, pos, h), Rect.new(p, y, right - p, h)]
      end

      # Split along y = y + pos  ->  [bottom strip, top strip]
      def split_horizontal(pos)
        p = y + pos
        [Rect.new(x, y, w, pos), Rect.new(x, p, w, top - p)]
      end

      def to_a
        [x, y, w, h]
      end

      def inspect
        format('Rect(%.1f,%.1f %.1fx%.1f)', x, y, w, h)
      end
    end

    module_function

    # Distance between two boxes' nearest faces (0 when touching/overlapping).
    def box_gap(a, b)
      dx = [0.0, [b.min.x - a.max.x, a.min.x - b.max.x].max].max
      dy = [0.0, [b.min.y - a.max.y, a.min.y - b.max.y].max].max
      dz = [0.0, [b.min.z - a.max.z, a.min.z - b.max.z].max].max
      Math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    # Snap a coordinate to the nearest multiple of `step` within `tol`.
    def snap_to(value, step, tol)
      return value if step.nil? || step <= 0
      nearest = (value / step).round * step
      (value - nearest).abs <= tol ? nearest : value
    end
  end
end
