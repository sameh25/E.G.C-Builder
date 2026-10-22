# frozen_string_literal: true

require 'json'

module EGC
  # Parametric dressing / wardrobe designer: one carcass with shared dividers,
  # sections (hanging, double hanging, shelves, drawers, shoes...), hinged or sliding doors.
  module Wardrobe
    ATTR = 'egc'
    TYPES = %w[hanging double long shelves drawers shoes mixed].freeze
    module_function

    def auto_sections(w, cfg, target = 900)
      t = cfg['thk'].to_f
      inner = w.to_f - 2 * t
      n = [(inner / target).round, 1].max
      sw = (inner - (n - 1) * t) / n
      seq = %w[double hanging shelves mixed long drawers]
      Array.new(n) { |i| { 't' => seq[i % seq.size], 'w' => sw.round(1) } }
    end

    def pieces(total, maxlen)
      n = [(total / maxlen).ceil, 1].max
      seg = total / n
      Array.new(n) { |i| [i * seg, seg] }
    end

    # params: 'w','h','d','doors'(hinged|sliding|none),'sliding_n','fascia','sections'=>[{'t','w'}],'name'
    def generate(params, cfg, origin = nil, rot = 0, manage_operation: true)
      model = Sketchup.active_model
      model.start_operation('E.G.C Wardrobe', true) if manage_operation
      Panel.reset_ids
      g = Builder.new(params, cfg).build(model.entities)
      g.transform!(Kitchen.placement(origin, rot)) if origin
      model.selection.clear
      model.selection.add(g)
      model.commit_operation if manage_operation
      g
    rescue StandardError
      model.abort_operation if manage_operation
      raise
    end

    # the same wardrobe built again from changed parameters, in place (Space tool: additions inside it)
    def rebuild(unit, params, cfg)
      Panel.reset_ids
      g = Builder.new(params, cfg).build(unit.parent.entities)
      g.transformation = unit.transformation
      g.layer = unit.layer
      unit.erase!
      g
    end

    class Builder
      include MechBuilders

      def initialize(p, cfg)
        @p = p
        @c = cfg
      end

      def build(parent)
        c = @c
        p = @p
        @t = c['thk'].to_f
        @bk = c['back_thk'].to_f
        @ft = c['front_thk'].to_f
        @gap = c['gap'].to_f
        @w = p['w'].to_f
        @h = p['h'].to_f
        @dd = (p['d'] || 600).to_f
        @cd = @dd - @ft
        @pl = c['plinth'].to_f
        @z0 = @pl
        @hc = @h - @pl
        @doors = (p['doors'] || 'hinged').to_s
        @name = p['name'] || 'EGC_Wardrobe'
        @hw = Hash.new(0.0)
        @g = parent.add_group
        @g.name = @name
        @e = @g.entities
        @carcass_stock = Config.stock_dimensions(c, 'carcass', c['thk'])
        @back_stock = Config.stock_dimensions(c, 'back', c['back_thk'])
        raise 'STOCK_SIZE_REQUIRED: configure internal and back-board sheet dimensions in Project Pricing before generating this wardrobe.' unless @carcass_stock && @back_stock
        @max_l = @carcass_stock[0] - 2 * c['trim'].to_f - 20
        @tracks = @doors == 'sliding' ? [[sliding_count, 3].min, 2].max : 0
        @fd = case @doors
              when 'hinged' then @cd - @ft - 3
              when 'sliding' then @cd - @tracks * (@ft + 4) - 3
              else @cd - @ft
              end
        carcass
        sections
        extras
        front_doors
        plinth_fascia
        finish
        @g
      end

      private

      def pn(part, x, d, z, sx, sd, sz, mat, o = {})
        Panel.add(@cur || @e, @name, part, x, d, z, sx, sd, sz, mat, @c, o.merge(code: 'WD'))
      end

      def sliding_count
        n = (@p['sliding_n'] || 0).to_i
        n = [(@w / 1000.0).ceil, 2].max if n < 2
        [n, 6].min
      end

      def carcass
        t = @t
        cdp = @cd - @bk
        pn('side_l', 0, @bk, @z0, t, cdp, @hc, 'carcass', grain: :z, eb: [1, 0])
        pn('side_r', @w - t, @bk, @z0, t, cdp, @hc, 'carcass', grain: :z, eb: [1, 0])
        Wardrobe.pieces(@w - 2 * t, @max_l).each do |x, len|
          pn('bottom', t + x, @bk, @z0, len, cdp, t, 'carcass', grain: :x, eb: [1, 0])
          pn('top', t + x, @bk, @z0 + @hc - t, len, cdp, t, 'carcass', grain: :x, eb: [1, 0])
        end
        Wardrobe.pieces(@w, [@back_stock[1] - 2 * @c['trim'].to_f - 20, @back_stock[0] - 2 * @c['trim'].to_f - 20].min).each do |x, len|
          pn('back', x, 0, @z0, len, @bk, @hc, 'back', grain: :z)
        end
        @hw['leg'] += ((@w / 800.0).ceil + 1) * 2
      end

      def interior_sections
        secs = (@p['sections'] || []).map(&:dup)
        secs = Wardrobe.auto_sections(@w, @c) if secs.empty?
        # 1.28.67: a doorless dressing unit is built from its carcass alone, and a
        # params hash with no sections could leave this empty - the old code then
        # indexed secs[-1] (nil) and raised NoMethodError: undefined method '[]='
        # for nil. Fall back to the inner gable-to-gable width instead.
        if secs.empty?
          inner = [@w - 2 * @t, 100].max
          return [{ 't' => 'hanging', 'w' => inner }]
        end
        avail = @w - 2 * @t - (secs.size - 1) * @t
        sum = EGC::Num.sum(secs[0...-1]) { |s| s['w'].to_f }
        secs[-1] = (secs[-1] || {}) # never index into nil
        secs[-1]['w'] = [avail - sum, 100].max
        secs
      end

      def sections
        secs = interior_sections
        x = @t
        zb = @z0 + @t
        zt = @z0 + @hc - @t
        secs.each_with_index do |s, i|
          sw = s['w'].to_f
          section(s['t'].to_s, x, sw, zb, zt)
          x += sw
          if i < secs.size - 1
            pn('vdivider', x, @bk, zb, @t, @cd - @bk, zt - zb, 'carcass', grain: :z, eb: [1, 0])
            x += @t
          end
        end
      end

      def shelf(sx, sw, z, fixed = false)
        pn('shelf', sx + 1, @bk, z, sw - 2, @cd - @bk - 20, @t, 'carcass', grain: :x, eb: [1, 0])
        @hw['shelf_pin'] += 4 unless fixed
      end

      def rod(sx, sw, z)
        pn('rod', sx, @bk + (@fd - @bk) / 2.0 - 12, z, sw, 25, 25, 'appliance', role: 'hw')
        hb('rod_bracket', sx, @bk + (@fd - @bk) / 2.0 - 14, z - 12, 6, 28, 40, 'profile')
        hb('rod_bracket', sx + sw - 6, @bk + (@fd - @bk) / 2.0 - 14, z - 12, 6, 28, 40, 'profile')
        @hw['rod_m'] += sw / 1000.0
        @hw['rod_bracket'] += 2
      end

      def shelf_and_rod(sx, sw, z_shelf)
        shelf(sx, sw, z_shelf, true)
        rod(sx, sw, z_shelf - 90)
      end

      def even_shelves(sx, sw, z0, z1, n)
        return if n <= 0

        sp = (z1 - z0 - n * @t) / (n + 1.0)
        n.times { |i| shelf(sx, sw, z0 + sp * (i + 1) + @t * i) }
      end

      def section(type, sx, sw, zb, zt)
        hi = zt - zb
        case type
        when 'hanging'
          shelf_and_rod(sx, sw, zt - 350)
        when 'long'
          rod(sx, sw, zt - 90)
        when 'double'
          if hi > 1800
            shelf_and_rod(sx, sw, zt - 350)
            mid = zb + 1050
            shelf(sx, sw, mid, true)
            rod(sx, sw, mid - 90)
          else
            shelf_and_rod(sx, sw, zt - 350)
          end
        when 'shelves'
          even_shelves(sx, sw, zb, zt, ((hi / 350.0).round).clamp(3, 10))
        when 'shoes'
          even_shelves(sx, sw, zb, zt, ((hi / 230.0).floor).clamp(3, 12))
        when 'drawers'
          n = 4
          top = drawer_stack(sx, sw, zb, n)
          shelf(sx, sw, top, true)
          even_shelves(sx, sw, top + @t, zt, [((zt - top - @t) / 350.0).floor - 1, 0].max)
        when 'mixed'
          top = drawer_stack(sx, sw, zb, 2)
          shelf(sx, sw, top, true)
          shelf_and_rod(sx, sw, zt - 350)
        end
      end

      # Space tool additions (params['extras'], unit frame, mm): shelf / divider / hanging rail / inner drawers in one free space.
      # An addition that no longer fits inside the carcass is skipped.
      def extras
        zb = @z0 + @t
        zt = @z0 + @hc - @t
        Array(@p['extras']).each do |e|
          v = ->(k) { e[k] || e[k.to_sym] }
          x0 = [v['x0'].to_f, @t].max
          x1 = [v['x1'].to_f, @w - @t].min
          case v['type'].to_s
          when 'shelf'
            z = v['z'].to_f
            shelf(x0, x1 - x0, z) unless x1 - x0 < 60 || z < zb || z + @t > zt
          when 'divider'
            x = v['x'].to_f
            z0 = [v['z0'].to_f, zb].max
            z1 = [v['z1'].to_f, zt].min
            pn('vdivider', x, @bk, z0, @t, @cd - @bk - 20, z1 - z0, 'carcass', grain: :z, eb: [1, 0]) unless z1 - z0 < 60 || x < @t || x + @t > @w - @t
          when 'rail'
            z = v['z'].to_f
            rod(x0, x1 - x0, z + 2.5) unless x1 - x0 < 200 || z < zb || z + 28 > zt # stored for a 30 mm rail: the 25 mm rod keeps the same centre
          when 'fill'
            z0 = [v['z0'].to_f, zb].max
            z1 = [v['z1'].to_f, zt].min
            next if v['cell'].to_s != 'drawers' || x1 - x0 < 250 || z1 - z0 < 100

            ratio = Array(v['ratio']).map(&:to_f).select(&:positive?)
            ratio = Array.new(v['n'].to_i.clamp(1, 6), 1.0) if ratio.empty?
            avail = z1 - z0 - 6 - @gap * (ratio.size - 1)
            z = z0 + 3
            ratio.each do |r|
              dh = avail * r / ratio.sum
              drawer(x0, x1 - x0, z, dh)
              z += dh + @gap
            end
          end
        end
      end

      # returns z of the top of the drawer zone
      def drawer_stack(sx, sw, zb, n)
        dh = 200.0
        n.times { |i| drawer(sx, sw, zb + 3 + i * (dh + @gap), dh) }
        zb + 3 + n * (dh + @gap)
      end

      def drawer(sx, sw, z, dh)
        fh = dh
        fz = z
        if @doors == 'none' && @c['handle'] == 'profile'
          ph = @c['profile_h'].to_f
          fh = dh - ph
          pn('profile', sx + 1.5, @fd, z + fh, sw - 3, @ft, ph, 'profile', role: 'hw')
          @hw['profile_mm'] += sw - 3
        end
        slide = (((@fd - @bk - 30) / 50.0).floor * 50).clamp(250, 550)
        drawer_spec = Config.drawer_spec(@c)
        dt = drawer_spec[:thickness]
        finish_note = drawer_spec[:finish].to_s.strip.empty? ? nil : "Drawer finish: #{drawer_spec[:finish]}"
        bw = sw - 26
        bx = sx + 13
        d0 = @fd - slide
        bh = [dh - 70, 60.0].max
        bz = z + 25
        das = asm('drawer', { 'type' => 'lin', 'v' => [0, slide * 0.9, 0] })
        @link_to=das.name
        @cur = das.entities
        pn('drawer_front', sx + 1.5, @fd, fz, sw - 3, @ft, fh, 'front', grain: :x, eb: [2, 2], eb_t: 2.0)
        runners_side(bx, d0, slide, bz + bh / 2.0 - 22, slide * 0.9, sx, sx + sw)
        pn('drawer_side', bx, d0, bz, dt, slide, bh, 'carcass', grain: :d, eb: [1, 0], notes: finish_note)
        pn('drawer_side', bx + bw - dt, d0, bz, dt, slide, bh, 'carcass', grain: :d, eb: [1, 0], notes: finish_note)
        pn('drawer_back', bx + dt, d0, bz, bw - 2 * dt, dt, bh, 'carcass', grain: :x, notes: finish_note)
        pn('drawer_subfront', bx + dt, d0 + slide - dt, bz, bw - 2 * dt, dt, bh, 'carcass', grain: :x, eb: [1, 0], notes: finish_note)
        pn('drawer_bottom', bx, d0, bz + 8, bw, slide, drawer_spec[:bottom_thickness], 'back', grain: :d)
        @cur = nil
        @link_to=nil
        @hw['slide_pair'] += 1
      end

      def hinge_count(h)
        return 2 if h <= 900
        return 3 if h <= 1600
        return 4 if h <= 2000

        5
      end

      def side_handle(part, x, w, z, h, pos, dplane, glass: false)
        ph = @c['profile_h'].to_f
        px = x
        pw = w
        prof = nil
        bar = nil
        case @c['handle']
        when 'profile'
          if pos == :side_r
            pw = w - ph
            prof = [x + w - ph, z, ph, h]
          else
            px = x + ph
            pw = w - ph
            prof = [x, z, ph, h]
          end
        when 'bar'
          bl = [160.0, h - 40].min
          bx = pos == :side_r ? x + w - 48 : x + 36
          bar = [bx, z + h / 2 - bl / 2, 12, 12, bl]
        end
        pn(part, px, dplane, z, pw, @ft, h, glass ? 'glass' : 'front', grain: :z, eb: [2, 2], eb_t: 2.0)
        if prof
          pn('profile', prof[0], dplane, prof[1], prof[2], @ft, prof[3], 'profile', role: 'hw')
          @hw['profile_mm'] += h
        end
        return unless bar

        pn('handle', bar[0], dplane + @ft, bar[1], bar[2], bar[3], bar[4], 'profile', role: 'hw')
        @hw['handle'] += 1
      end

      def front_doors
        case @doors
        when 'hinged'
          n = (@w / 550.0).ceil
          n = 2 if n < 2 && @w > 600
          n = [n, 1].max
          total = @w - @gap
          dw = (total - @gap * (n - 1)) / n
          hz = @z0 + @gap / 2.0
          hh = @hc - @gap
          n.times do |k|
            x = @gap / 2.0 + k * (dw + @gap)
            pos = (n == 1 || k < n / 2.0) ? :side_r : :side_l
            pos = k.even? ? :side_r : :side_l if n.odd? && k == n / 2
            a = asm("door#{k + 1}", door_move(k, n, x, dw, hz, hh, false))
            in_asm(a) do
              side_handle('door', x, dw, hz, hh, pos, @cd)
              door_hinges(k, n, x, dw, hz, hh)
            end
            door_plates(k, n, x, dw, hz, hh)
            @hw['hinge'] += hinge_count(hh)
          end
        when 'sliding'
          n = sliding_count
          inner = @w - 2 * @t
          ov = 30.0
          pw = (inner + (n - 1) * ov) / n
          zb = @z0 + @t + 14
          hh = @hc - 2 * @t - 40
          n.times do |i|
            layer = i % @tracks
            x = @t + i * (pw - ov)
            dplane = @cd - (layer + 1) * (@ft + 4)
            a = asm("slide#{i + 1}", { 'type' => 'lin', 'v' => [(i.even? ? 1 : -1) * (pw - ov) * 0.9, 0, 0] })
            in_asm(a) do
              side_handle('sliding_door', x, pw, zb, hh, i.even? ? :side_r : :side_l, dplane)
              hb('roller', x + 40, dplane + 2, zb + hh, 22, @ft - 4, 16, 'profile')
              hb('roller', x + pw - 62, dplane + 2, zb + hh, 22, @ft - 4, 16, 'profile')
            end
            @hw['slide_wheel'] += 2
            @hw['slide_guide'] += 2
          end
          td0 = @cd - @tracks * (@ft + 4) - 2
          tl = @tracks * (@ft + 4) + 2
          hb('track_top', @t, td0, @z0 + @hc - @t - 22, inner, tl, 22)
          hb('track_bottom', @t, td0, @z0 + @t, inner, tl, 10)
          @hw['slide_track_m'] += 2 * inner / 1000.0 * (@tracks > 0 ? 1 : 0)
        end
      end

      def plinth_fascia
        Wardrobe.pieces(@w, @max_l).each do |x, len|
          pn('plinth', x, @dd - 50 - @t, 0, len, @t, @pl, 'carcass', grain: :x, eb: [1, 0]) if @pl > 0
        end
        fh = @c['ceiling'].to_f - @h
        return if fh < 1 || @p['fascia'] == false

        Wardrobe.pieces(@w, @max_l).each do |x, len|
          pn('fascia', x, @dd - @ft, @h, len, @ft, fh, 'front', grain: :x, eb: [2, 0], eb_t: 2.0)
        end
      end

      def finish
        @g.set_attribute(ATTR, 'wardrobe', true)
        @g.set_attribute(ATTR, 'code', 'WD')
        @g.set_attribute(ATTR, 'kind', 'wardrobe')
        @g.set_attribute(ATTR, 'type', @doors)
        @g.set_attribute(ATTR, 'w', @w)
        @g.set_attribute(ATTR, 'h', @h)
        @g.set_attribute(ATTR, 'd', @dd)
        @g.set_attribute(ATTR, 'hw', JSON.generate(@hw))
        @g.set_attribute(ATTR, 'params', JSON.generate(@p))
      end
    end
  end
end
