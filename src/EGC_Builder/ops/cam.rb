# encoding: UTF-8
# frozen_string_literal: true
#
# CAM (§2) - toolpath generation + DXF export.
#
# TOOLPATH CONTRACT
# -----------------
# All toolpath offsets derive from the frozen constants:
#   cut offset      = SAW_KERF / 2          (tool centreline)
#   border trim     = BORDER_TRIM           (sheet edge cleanup pass)
#   drill depth     = per-hole frozen depth
# No offset is ever stored per-part; a stale toolpath is therefore impossible
# once the cache is reset. `reset_toolpaths!` drops every generated path so
# the next export regenerates from current part geometry.
#
# DXF layers:
#   CUT      closed cut contours
#   DRILL    drill centres with diameter/depth attributes
#   TRIM     sheet border trim pass
#   ENGRAVE  part labels / grain arrows

module EGC
  module Ops
    module CAM
      C = EGC::Constants

      @toolpath_cache = {}
      @generation = 0
      @last_reset_reason = nil

      class << self
        attr_reader :generation, :last_reset_reason

        def reset_toolpaths!(reason = :manual)
          @toolpath_cache.clear
          @generation += 1
          @last_reset_reason = reason
          EGC::Log.debug("CAM toolpaths reset (#{reason}) gen=#{@generation}")
          @generation
        end

        def cached_paths
          @toolpath_cache.values
        end

        def cache_size
          @toolpath_cache.length
        end
      end

      module_function

      def tool_radius
        C::SAW_KERF / 2.0
      end

      # ---- geometry helpers ---------------------------------------------
      # Cut contour for a rectangular part at sheet position (x, y).
      # The contour is the finished part outline; the tool centre runs
      # `tool_radius` outside it.
      def cut_contour(part, x, y, rotated: false)
        l = rotated ? part.width : part.length
        w = rotated ? part.length : part.width
        [
          [x, y], [x + l, y], [x + l, y + w], [x, y + w], [x, y]
        ]
      end

      def tool_centre_contour(part, x, y, rotated: false)
        r = tool_radius
        l = rotated ? part.width : part.length
        w = rotated ? part.length : part.width
        [
          [x - r, y - r], [x + l + r, y - r],
          [x + l + r, y + w + r], [x - r, y + w + r], [x - r, y - r]
        ]
      end

      # ---- per-part toolpath ---------------------------------------------
      def build_part_toolpath(part, x, y, rotated: false)
        key = "#{part.id}:#{x.round(2)}:#{y.round(2)}:#{rotated}:#{@generation}"
        return @toolpath_cache[key] if @toolpath_cache.key?(key)

        path = {
          :part_id => part.id,
          :role => part.role,
          :origin => [x.round(2), y.round(2)],
          :rotated => rotated,
          :kerf => C::SAW_KERF,
          :tool_radius => tool_radius,
          :cut => cut_contour(part, x, y, :rotated => rotated),
          :tool_centre => tool_centre_contour(part, x, y, :rotated => rotated),
          :drills => part.drills.map { |d| drill_op(d) },
          :layer => 'CUT'
        }
        @toolpath_cache[key] = path
        path
      end

      def drill_op(drill)
        {
          :x => drill[:x], :y => drill[:y],
          :diameter => drill[:diameter],
          :depth => drill[:depth],
          :layer => 'DRILL'
        }
      end

      # ---- DXF ------------------------------------------------------------
      def dxf_header(sheet_l, sheet_w)
        [
          '0', 'SECTION', '2', 'HEADER',
          '9', '$ACADVER', '1', 'AC1015',
          '9', '$INSBASE', '10', '0.0', '20', '0.0', '30', '0.0',
          '9', '$EXTMIN', '10', '0.0', '20', '0.0', '30', '0.0',
          '9', '$EXTMAX', '10', sheet_l.to_s, '20', sheet_w.to_s, '30', '0.0',
          '0', 'ENDSEC'
        ]
      end

      def dxf_tables(layers)
        out = ['0', 'SECTION', '2', 'TABLES', '0', 'TABLE', '2', 'LAYER', '70', layers.length.to_s]
        layers.each do |name|
          out += ['0', 'LAYER', '2', name, '70', '0', '62', '7', '6', 'CONTINUOUS']
        end
        out += ['0', 'ENDTAB', '0', 'ENDSEC']
        out
      end

      def dxf_polyline(points, layer)
        out = ['0', 'POLYLINE', '8', layer, '66', '1', '70', '1']
        points.each do |(x, y)|
          out += ['0', 'VERTEX', '8', layer, '10', x.round(3).to_s, '20', y.round(3).to_s, '30', '0.0']
        end
        out + ['0', 'SEQEND', '8', layer]
      end

      def dxf_circle(cx, cy, radius, layer)
        ['0', 'CIRCLE', '8', layer,
         '10', cx.round(3).to_s, '20', cy.round(3).to_s, '30', '0.0',
         '40', radius.round(3).to_s]
      end

      def dxf_text(x, y, height, text, layer)
        ['0', 'TEXT', '8', layer,
         '10', x.round(3).to_s, '20', y.round(3).to_s, '30', '0.0',
         '40', height.to_s, '1', text.to_s]
      end

      # Renders one nested sheet to DXF text.
      def sheet_to_dxf(sheet)
        l = sheet[:length] || C::SHEET_LENGTH
        w = sheet[:width]  || C::SHEET_WIDTH
        layers = ['CUT', 'DRILL', 'TRIM', 'ENGRAVE']
        out = dxf_header(l, w)
        out += dxf_tables(layers)

        out += ['0', 'SECTION', '2', 'ENTITIES']

        # border trim pass
        out += dxf_polyline(
          [[0.0, 0.0], [l, 0.0], [l, w], [0.0, w], [0.0, 0.0]], 'TRIM'
        )

        Array(sheet[:placements]).each do |pl|
          part = pl[:part]
          x = pl[:x]
          y = pl[:y]
          rotated = pl[:rotated]
          tp = build_part_toolpath(part, x, y, :rotated => rotated)
          out += dxf_polyline(tp[:cut], 'CUT')
          tp[:drills].each do |d|
            out += dxf_circle(d[:x], d[:y], d[:diameter] / 2.0, 'DRILL')
          end
          out += dxf_text(x + 5, y + 5, 8.0, "#{part.role} #{part.length.round}x#{part.width.round}", 'ENGRAVE')
        end

        out += ['0', 'ENDSEC', '0', 'EOF']
        out.join("\n")
      end

      def export_dxf(sheets)
        Array(sheets).map { |s| sheet_to_dxf(s) }
      end

      def write_dxf(sheets, path)
        File.write(path, export_dxf(sheets).join("\n"))
        path
      end

      # ---- drill generation ------------------------------------------------
      # Produces EGC-standard boring patterns from frozen constants only.
      def system32_holes(z_lo, z_hi, y_offset, diameter: C::DRILL_SHELF_PIN_DIAMETER,
                         depth: C::DRILL_SHELF_PIN_DEPTH)
        holes = []
        z = z_lo
        while z <= z_hi
          holes << { :x => y_offset, :y => z, :diameter => diameter, :depth => depth }
          z += C::SYSTEM32_PITCH
        end
        holes
      end

      def hinge_holes(door_height, leaf_count = 1)
        return [] if leaf_count.zero?
        positions =
          case door_height
          when 0..1000   then [0.15, 0.85]
          when 1000..1600 then [0.12, 0.5, 0.88]
          else [0.1, 0.35, 0.65, 0.9]
          end
        positions.map do |f|
          {
            :x => C::DRILL_HINGE_EDGE_OFFSET,
            :y => (door_height * f).round(2),
            :diameter => C::DRILL_HINGE_DIAMETER,
            :depth => C::DRILL_HINGE_DEPTH
          }
        end
      end

      def rod_bracket_holes(rod_z, span_x0, x1)
        d = C::HANGING_ROD_BRACKET_DRILL_DIAMETER
        depth = C::DRILL_SHELF_PIN_DEPTH
        [
          { :x => span_x0, :y => rod_z, :diameter => d, :depth => depth },
          { :x => x1,      :y => rod_z, :diameter => d, :depth => depth }
        ]
      end
    end
  end
end
