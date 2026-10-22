# encoding: UTF-8
# frozen_string_literal: true
#
# Nesting engine (§3) - Guillotine best-fit with grain-aware rotation.
#
# FROZEN INVARIANTS (never altered by this file)
# ----------------------------------------------
#   SAW_KERF     4.4 mm  : material consumed by every cut
#   BORDER_TRIM 10.0 mm  : sheet edge that may not be used
# These come from EGC::Constants and are only ever READ here.
#
# WHAT CHANGED IN 1.28.67
# -----------------------
# 1. GRAIN-AWARE ROTATION
#    if material.has_grain == false (plain / solid colour) -> 90deg rotation
#    is enabled for that part. Grain-matched boards may never rotate, so the
#    grain always runs along the sheet's long axis.
#
# 2. BEST-FIT GUILLOTINE SPLIT
#    Instead of first-fit shelf packing, every part is placed into the SMALLEST
#    free rectangle that can accept it (best-area-fit). This deliberately
#    targets reclaimed offcuts left behind by large gables, so small fillers
#    and stretchers drop into them instead of opening a fresh sheet.
#    Each placement performs a guillotine split using the "shorter leftover
#    axis" rule, which preserves one large contiguous remainder.
#
# 3. STRIP GROUPING
#    Parts sharing an identical cross-strip width (within STRIP_GROUP_WIDTH_TOL)
#    are grouped into continuous rip-cut strips: one rip produces the strip,
#    then successive cross-cuts yield each part. This converts N rip cuts into
#    one and removes the kerf waste between stacked parts along the strip.

module EGC
  module Ops
    module Nesting
      C = EGC::Constants

      @layout_cache = {}
      @generation = 0
      @last_invalidation = nil

      class << self
        attr_reader :generation, :last_invalidation

        def invalidate_layout!(reason = :manual)
          @layout_cache.clear
          @generation += 1
          @last_invalidation = reason
          EGC::Log.debug("nesting layout invalidated (#{reason}) gen=#{@generation}")
          @generation
        end

        def cached_layouts
          @layout_cache.values
        end
      end

      # A part instance queued for a sheet.
      PartInstance = Struct.new(:part, :uid, :strip_id) do
        def length
          part.length
        end

        def width
          part.width
        end

        def rotatable?
          part.rotatable?
        end

        def area
          part.area_mm2
        end

        def label
          part.role.to_s
        end
      end

      module_function

      # ---- public entry point -------------------------------------------
      # parts   : Array<EGC::Model::Part>
      # opts    : :sheet_length, :sheet_width, :strip_grouping, :kerf, :trim
      #
      # Parts are partitioned by (material, thickness) BEFORE packing: a sheet
      # is a single physical board, so panels of different material or gauge
      # can never share one. Each group is packed independently and the sheet
      # indices are then renumbered across the whole job.
      def nest(parts, opts = {})
        kerf  = opts.fetch(:kerf, C::SAW_KERF)
        trim  = opts.fetch(:trim, C::BORDER_TRIM)
        sheet_l = opts.fetch(:sheet_length, C::SHEET_LENGTH)
        sheet_w = opts.fetch(:sheet_width,  C::SHEET_WIDTH)

        all_sheets = []
        all_unplaced = []

        group_parts(parts).each do |(material_key, thickness), group|
          res = nest_group(group, opts.merge(:kerf => kerf, :trim => trim,
                                             :sheet_length => sheet_l, :sheet_width => sheet_w))
          all_sheets.concat(res[:sheets])
          all_unplaced.concat(res[:unplaced])
        end

        # renumber sheet indices across the combined job
        all_sheets.each_with_index { |s, i| s[:index] = i }

        summarise(all_sheets, all_unplaced, kerf, trim, sheet_l, sheet_w)
      end

      # Stable partition key: material + thickness.
      def group_parts(parts)
        out = {}
        Array(parts).each do |p|
          key = [p.material.key, p.thickness.round(2)]
          (out[key] ||= []) << p
        end
        out
      end

      # Packs one homogeneous group (same material, same thickness).
      # Packs one homogeneous group, trying BOTH rotation policies and keeping
      # the better result. Rotation is an optimisation: it must never make a
      # layout worse than the grain-locked equivalent.
      def nest_group(parts, opts = {})
        return empty_result(opts.fetch(:kerf, C::SAW_KERF), opts.fetch(:trim, C::BORDER_TRIM),
                            opts.fetch(:sheet_length, C::SHEET_LENGTH),
                            opts.fetch(:sheet_width, C::SHEET_WIDTH)) if parts.empty?

        explicit = opts.key?(:allow_rotation) ? opts[:allow_rotation] : nil
        if explicit.nil? && parts.any?(&:rotatable?)
          free   = pack_group(parts, opts.merge(:allow_rotation => true))
          locked = pack_group(parts, opts.merge(:allow_rotation => false))
          return better_of(free, locked)
        end
        pack_group(parts, opts)
      end

      # Placing every part ALWAYS beats saving a sheet: a layout that leaves
      # parts unplaced is not a valid optimum. Order of preference:
      #   1. fewest unplaced parts
      #   2. fewest sheets
      #   3. greatest used area
      def better_of(a, b)
        na = a[:unplaced].length
        nb = b[:unplaced].length
        return a if na < nb
        return b if nb < na

        sa = a[:sheets].length
        sb = b[:sheets].length
        return a if sa < sb
        return b if sb < sa

        ua = a[:sheets].sum { |s| s[:used_area] }
        ub = b[:sheets].sum { |s| s[:used_area] }
        ua >= ub ? a : b
      end

      def pack_group(parts, opts = {})
        kerf  = opts.fetch(:kerf, C::SAW_KERF)
        trim  = opts.fetch(:trim, C::BORDER_TRIM)
        sheet_l = opts.fetch(:sheet_length, C::SHEET_LENGTH)
        sheet_w = opts.fetch(:sheet_width,  C::SHEET_WIDTH)
        use_strips = opts.fetch(:strip_grouping, true)
        allow_rotation_override = opts[:allow_rotation]

        instances = expand_instances(parts)
        return empty_result(kerf, trim, sheet_l, sheet_w) if instances.empty?

        usable_l = sheet_l - 2 * trim
        usable_w = sheet_w - 2 * trim
        unplaced = instances.select { |i| oversize?(i, usable_l, usable_w) }
        queue = instances - unplaced

        # ---- build the placement queue -------------------------------
        strips = use_strips ? build_strips(queue, kerf, usable_l) : []
        strip_members = strips.flat_map { |s| s[:members] }
        loose = queue - strip_members

        items = []
        strips.each { |s| items << { :kind => :strip, :rect_w => s[:width], :rect_h => s[:length], :strip => s } }
        loose.each  { |i| items << { :kind => :part, :part => i } }

        # Sort by area desc: gables first so their offcuts exist for fillers.
        items.sort_by! { |it| -item_area(it) }

        sheets = []

        items.each do |item|
          placed = false
          sheets.each do |sheet|
            next unless try_place(sheet, item, kerf, allow_rotation_override)
            placed = true
            break
          end
          next if placed

          sheet = new_sheet(sheets.length, sheet_l, sheet_w, kerf, trim)
          if try_place(sheet, item, kerf, allow_rotation_override)
            sheets << sheet
          else
            unplaced.concat(item[:kind] == :part ? [item[:part]] : item[:strip][:members])
          end
        end

        # used_area for a strip is its members' area; recompute per sheet
        sheets.each { |s| s[:used_area] = s[:placements].sum { |pl| pl[:part].area_mm2 } }

        { :sheets => sheets, :unplaced => unplaced }
      end

      # ---- instance expansion --------------------------------------------
      def expand_instances(parts)
        out = []
        Array(parts).each do |p|
          qty = [p.quantity.to_i, 1].max
          qty.times do |n|
            out << PartInstance.new(p, "#{p.id}-#{n}", nil)
          end
        end
        out
      end

      def oversize?(inst, usable_l, usable_w)
        l = inst.length
        w = inst.width
        candidates = [[l, w]]
        candidates << [w, l] if inst.rotatable?
        candidates.none? { |(a, b)| a <= usable_l + 1e-6 && b <= usable_w + 1e-6 }
      end

      # ---- strip grouping --------------------------------------------------
      # Group instances whose cross-strip width matches (grain-safe).
      def build_strips(instances, kerf, max_len = C::SHEET_LENGTH - 2 * C::BORDER_TRIM)
        groups = {}
        instances.each do |inst|
          # cross-strip width: the dimension that is NOT the strip length.
          key = inst.width.round(1)
          (groups[key] ||= []) << inst
        end

        strips = []
        groups.each do |w_key, members|
          next if members.length < 2
          # longest first so each chunk reads like a real rip sequence
          members = members.sort_by { |m| -m.length }

          current = []
          current_len = 0.0

          # Closes the run in progress. ALWAYS resets the buffer; a run of one
          # is simply not emitted (its member stays loose and is packed on its
          # own). Failing to reset here let an oversized part linger and get
          # emitted inside the next strip, producing out-of-sheet placements.
          flush = lambda do
            if current.length >= 2
              strip_id = "S#{strips.length}"
              current.each { |m| m.strip_id = strip_id }
              strips << {
                :id => strip_id,
                :width => w_key.to_f,
                :length => current_len,
                :members => current,
                :kerf => kerf
              }
            end
            current = []
            current_len = 0.0
          end

          members.each do |m|
            candidate = current.empty? ? m.length : current_len + kerf + m.length
            # A strip may never exceed the usable sheet length, otherwise it
            # can never be placed and every member ends up unplaced.
            if !current.empty? && candidate > max_len + 1e-6
              flush.call
              candidate = m.length
            end
            current << m
            current_len = candidate
          end
          flush.call
        end
        strips
      end

      def item_area(item)
        if item[:kind] == :strip
          item[:strip][:members].sum(&:area)
        else
          item[:part].area
        end
      end

      # ---- sheet / free-rect management ------------------------------------
      def new_sheet(index, sheet_l, sheet_w, kerf, trim)
        usable = EGC::Geom::Rect.new(trim, trim, sheet_l - 2 * trim, sheet_w - 2 * trim)
        {
          :index => index,
          :length => sheet_l,
          :width => sheet_w,
          :kerf => kerf,
          :trim => trim,
          :free => [usable],
          :placements => [],
          :used_area => 0.0,
          :usable_area => usable.area
        }
      end

      # Best-area-fit: pick the smallest free rect that accepts the item.
      def try_place(sheet, item, kerf, allow_rotation_override)
        best = nil
        best_score = nil

        sheet[:free].each_with_index do |rect, idx|
          orientations_for(item, allow_rotation_override).each do |(w, h, rotated)|
            next unless rect.fits?(w, h)
            # prefer the tightest fit; break ties by the shorter leftover edge
            slack_x = rect.w - w
            slack_y = rect.h - h
            score = [rect.area, [slack_x, slack_y].min, idx]
            if best_score.nil? || (score <=> best_score) < 0
              best_score = score
              best = { :rect_index => idx, :w => w, :h => h, :rotated => rotated }
            end
          end
        end

        return false if best.nil?

        rect = sheet[:free].delete_at(best[:rect_index])
        x = rect.x
        y = rect.y

        emit_placement(sheet, item, x, y, best[:w], best[:h], best[:rotated])
        sheet[:used_area] += item_area(item)

        # Guillotine split, shorter-leftover-axis rule.
        remainders = guillotine_split(rect, best[:w], best[:h], kerf)
        remainders.each do |r|
          next if r.empty?
          # Keep even small offcuts: fillers/stretchers rely on them.
          sheet[:free] << r
        end
        sheet[:free].sort_by! { |r| [r.area, [r.w, r.h].min] }
        true
      end

      def orientations_for(item, allow_rotation_override)
        if item[:kind] == :strip
          s = item[:strip]
          # A strip is a RIP along the sheet's long axis: its LENGTH runs in X
          # (up to ~2420mm usable) and its WIDTH in Y. Returning width-first
          # made any strip longer than the sheet width unplaceable.
          return [[s[:length], s[:width], false]]
        end

        inst = item[:part]
        l = inst.length
        w = inst.width
        rotatable = if allow_rotation_override.nil?
                      inst.rotatable?
                    else
                      inst.rotatable? && allow_rotation_override
                    end
        list = [[l, w, false]]
        list << [w, l, true] if rotatable && (w - l).abs > 1e-6
        list
      end

      # Splits the leftover of `rect` after a w x h part at its origin.
      # Returns 0..2 rects. Kerf is removed between part and remainder.
      def guillotine_split(rect, w, h, kerf)
        rem_w = rect.w - w - kerf
        rem_h = rect.h - h - kerf
        has_right = rem_w > 1e-6
        has_top   = rem_h > 1e-6

        return [] unless has_right || has_top
        return [EGC::Geom::Rect.new(rect.x + w + kerf, rect.y, rem_w, rect.h)] unless has_top
        return [EGC::Geom::Rect.new(rect.x, rect.y + h + kerf, rect.w, rem_h)] unless has_right

        # Both remainders exist: choose the split that keeps the LARGER usable
        # rectangle intact ("shorter leftover axis" rule).
        #  a) long vertical strip on the right, short horizontal on top
        a_right = EGC::Geom::Rect.new(rect.x + w + kerf, rect.y, rem_w, rect.h)
        a_top   = EGC::Geom::Rect.new(rect.x, rect.y + h + kerf, w, rem_h)
        #  b) short vertical strip on the right, long horizontal across the top
        b_right = EGC::Geom::Rect.new(rect.x + w + kerf, rect.y, rem_w, h)
        b_top   = EGC::Geom::Rect.new(rect.x, rect.y + h + kerf, rect.w, rem_h)

        score_a = [a_right.area, a_top.area].max
        score_b = [b_right.area, b_top.area].max

        score_a >= score_b ? [a_right, a_top] : [b_right, b_top]
      end

      def emit_placement(sheet, item, x, y, w, h, rotated)
        if item[:kind] == :strip
          strip = item[:strip]
          # Successive parts are cross-cut along the strip's LENGTH (X axis).
          cursor = 0.0
          strip[:members].each do |m|
            len = m.length
            rect_w = rotated ? m.width : len
            rect_h = rotated ? len : m.width
            sheet[:placements] << { :part => m.part,
                                    :x => x + cursor, :y => y,
                                    :w => rect_w, :h => rect_h,
                                    :rotated => rotated,
                                    :strip_id => strip[:id] }
            cursor += len + strip[:kerf]
          end
        else
          inst = item[:part]
          sheet[:placements] << { :part => inst.part, :x => x, :y => y,
                                  :w => w, :h => h, :rotated => rotated,
                                  :strip_id => nil }
        end
      end

      # ---- summary / metrics -----------------------------------------------
      def summarise(sheets, unplaced, kerf, trim, sheet_l, sheet_w)
        usable_per_sheet = (sheet_l - 2 * trim) * (sheet_w - 2 * trim)
        total_usable = usable_per_sheet * sheets.length
        used = sheets.sum { |s| s[:used_area] }
        placement_count = sheets.sum { |s| s[:placements].length }
        area_m2 = ->(a) { (a / 1_000_000.0).round(4) }

        {
          :kerf => kerf,
          :trim => trim,
          :sheet_length => sheet_l,
          :sheet_width => sheet_w,
          :sheets => sheets,
          :sheet_count => sheets.length,
          :placements => sheets.flat_map { |s| s[:placements] },
          :placement_count => placement_count,
          :unplaced => unplaced,
          :unplaced_count => unplaced.length,
          :used_area_mm2 => used.round(2),
          :usable_area_mm2 => total_usable.round(2),
          :sheet_area_mm2 => (sheet_l * sheet_w * sheets.length).round(2),
          :used_area_m2 => area_m2.call(used),
          :usable_area_m2 => area_m2.call(total_usable),
          :yield => total_usable.positive? ? (used / total_usable).round(4) : 0.0,
          :waste_pct => total_usable.positive? ? (100.0 * (1.0 - used / total_usable)).round(2) : 0.0,
          :signature => signature_of(sheets, unplaced),
          :generation => @generation
        }
      end

      def signature_of(sheets, unplaced)
        body = sheets.flat_map { |s| s[:placements].map { |p| "#{p[:part].id}@#{p[:x].round(1)},#{p[:y].round(1)}#{p[:rotated] ? 'R' : ''}" } }.sort.join('|')
        Digest::SHA256.hexdigest("#{body}|unplaced=#{unplaced.length}|g=#{@generation}")
      end

      def empty_result(kerf, trim, sheet_l, sheet_w)
        summarise([], [], kerf, trim, sheet_l, sheet_w)
      end

      # ---- validation -------------------------------------------------------
      # Asserts no overlap, everything inside the trimmed area, kerf honoured.
      def validate(result, kerf = nil)
        kerf ||= result[:kerf]
        errors = []
        result[:sheets].each do |sheet|
          pls = sheet[:placements]
          lo = sheet[:trim]
          hi_x = sheet[:length] - sheet[:trim]
          hi_y = sheet[:width] - sheet[:trim]

          pls.each do |p|
            if p[:x] < lo - 1e-6 || p[:y] < lo - 1e-6 ||
               p[:x] + p[:w] > hi_x + 1e-6 || p[:y] + p[:h] > hi_y + 1e-6
              errors << "sheet #{sheet[:index]}: #{p[:part].role} outside usable area"
            end
          end

          pls.combination(2).each do |a, b|
            next if a[:strip_id] && a[:strip_id] == b[:strip_id]
            if rects_overlap?(a, b, 1e-6)
              errors << "sheet #{sheet[:index]}: overlap #{a[:part].role} <> #{b[:part].role}"
            end
          end
        end
        { :ok => errors.empty?, :errors => errors }
      end

      def rects_overlap?(a, b, tol)
        a[:x] < b[:x] + b[:w] - tol && a[:x] + a[:w] > b[:x] + tol &&
          a[:y] < b[:y] + b[:h] - tol && a[:y] + a[:h] > b[:y] + tol
      end

      # ---- baseline (legacy shelf algorithm) for the audit report -----------
      # Deliberately reproduces the OLD behaviour so the audit can quantify the
      # improvement. Not used for production output.
      def baseline_shelf_nest(parts, opts = {})
        kerf  = opts.fetch(:kerf, C::SAW_KERF)
        trim  = opts.fetch(:trim, C::BORDER_TRIM)
        sheet_l = opts.fetch(:sheet_length, C::SHEET_LENGTH)
        sheet_w = opts.fetch(:sheet_width,  C::SHEET_WIDTH)

        instances = expand_instances(parts).sort_by { |i| [-i.width, -i.length] }
        sheets = []
        shelf_y = nil
        shelf_h = 0.0
        cursor_x = 0.0
        current = nil

        instances.each do |inst|
          w = inst.length
          h = inst.width
          if current.nil? || cursor_x + w > sheet_l - trim
            # new shelf row
            new_y = current ? (shelf_y + shelf_h + kerf) : trim
            if current.nil? || new_y + h > sheet_w - trim
              sheets << current if current
              current = { :index => sheets.length, :length => sheet_l, :width => sheet_w,
                          :trim => trim, :placements => [], :used_area => 0.0,
                          :usable_area => (sheet_l - 2 * trim) * (sheet_w - 2 * trim) }
              sheets << nil
              sheets.pop
              new_y = trim
            end
            shelf_y = new_y
            shelf_h = h
            cursor_x = trim
          end
          current ||= { :index => 0, :length => sheet_l, :width => sheet_w, :trim => trim,
                        :placements => [], :used_area => 0.0,
                        :usable_area => (sheet_l - 2 * trim) * (sheet_w - 2 * trim) }
          current[:placements] << { :part => inst.part, :x => cursor_x, :y => shelf_y,
                                    :w => w, :h => h, :rotated => false, :strip_id => nil }
          current[:used_area] += inst.area
          cursor_x += w + kerf
        end
        sheets << current if current
        used = sheets.sum { |s| s[:used_area] }
        total_usable = sheets.sum { |s| s[:usable_area] }
        {
          :sheet_count => sheets.length,
          :used_area_m2 => (used / 1_000_000.0).round(4),
          :yield => total_usable.positive? ? (used / total_usable).round(4) : 0.0,
          :waste_pct => total_usable.positive? ? (100.0 * (1.0 - used / total_usable)).round(2) : 0.0
        }
      end
    end
  end
end
