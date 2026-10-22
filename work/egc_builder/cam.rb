# frozen_string_literal: true

require 'json'

module EGC
  # CAM / CNC hand-off. One layered DXF per sheet material (the SAME nest as nesting.csv / the laser list), one cut list per material.
  # Layers: SHEET, OUTLINE (through cut, RAW size), DRILL_5MM, DRILL_8MM, POCKET_35MM, GROOVE_<w>MM (back panel groove), GROOVE_LED, NOTES, PART_ID.
  # Every feature comes from data the builder stored on the board (bore / back_groove / groove_geo); nothing is invented here. Circle and
  # groove entities carry the machining depth as a negative Z (group 30). Each board is drawn as the view of its MACHINED face:
  #   carcass side  -> inner face, X = bottom to top, front edge at Y = 0 (right side) / at Y = width (left side, mirror image)
  #   door / front  -> back face,  X = bottom to top, Y from the edge the builder measured the cup from
  module Cam
    module_function

    HINGE_CUP = { dia: 35.0, depth: 12.0, setback: 21.5 }.freeze # standard cup boring: 35 dia, 12 deep (11.5 - 12), bore edge 4 mm from the door edge (K = 4)

    def layer_for(dia)
      d = dia.to_f
      return 'POCKET_35MM' if (d - 35).abs < 0.01
      return 'DRILL_5MM' if (d - 5).abs < 0.01
      return 'DRILL_8MM' if (d - 8).abs < 0.01

      "DRILL_#{d.round(1).to_s.sub(/\.0\z/, '')}MM"
    end

    # Features of one board in FINISHED-panel coordinates (u along the length, v along the width), mm.
    # Returns { circles: [[layer, u, v, dia, depth]], rects: [[layer, u0, v0, u1, v1, depth]], notes: [String] }
    def features(it)
      fl = it[:fin_l].to_f
      fw = it[:fin_w].to_f
      out = { circles: [], rects: [], notes: [] }
      mirror = it[:part].to_s.end_with?('_l')
      len_is_z = it[:la].to_s.empty? || it[:la].to_s == 'z'
      out[:notes] << 'LENGTH AXIS NOT RECORDED (unit built by an older version): drilling placed for an upright board - rebuild the unit to confirm' if it[:la].to_s.empty? && it[:bore]
      bores = begin; JSON.parse(it[:bore].to_s); rescue StandardError; []; end
      bores.each do |h|
        bx = h['x'].to_f
        by = h['y'].to_f
        u, v = len_is_z ? [by, bx] : [bx, by]
        v = fw - v if mirror
        dia = h['dia'].to_f
        depth = (dia - 35).abs < 0.01 ? HINGE_CUP[:depth] : h['depth'].to_f
        if u < -0.01 || v < -0.01 || u > fl + 0.01 || v > fw + 0.01
          out[:notes] << "#{h['t']} at #{bx}/#{by} is outside the board - NOT exported"
          next
        end
        if (dia - 35).abs < 0.01 # hinge cup: the centre is set on the E.G.C standard setback from the door edge it was modeled next to
          e = [v, fw - v, u, fl - u]
          case e.index(e.min)
          when 0 then v = HINGE_CUP[:setback]
          when 1 then v = fw - HINGE_CUP[:setback]
          when 2 then u = HINGE_CUP[:setback]
          else u = fl - HINGE_CUP[:setback]
          end
        end
        out[:circles] << [layer_for(dia), u, v, dia, depth]
      end
      bg = begin; JSON.parse(it[:back_groove].to_s); rescue StandardError; nil; end
      if bg.is_a?(Hash) && bg['width'].to_f.positive? && bg['depth'].to_f.positive?
        off = bg['offset'].to_f
        gw = bg['width'].to_f
        v0 = mirror ? off : fw - off - gw
        out[:rects] << ["GROOVE_#{gw.round(1).to_s.sub(/\.0\z/, '')}MM", 0.0, v0, fl, v0 + gw, bg['depth'].to_f]
      end
      geo = begin; JSON.parse(it[:groove_geo].to_s); rescue StandardError; nil; end
      if geo.is_a?(Hash) && geo['axis'] == 'len' && %w[wid0 wid1].include?(geo['ref']) && geo['w'].to_f.positive?
        v0 = geo['ref'] == 'wid0' ? geo['off'].to_f : fw - geo['off'].to_f - geo['w'].to_f
        out[:rects] << ['GROOVE_LED', 0.0, v0, fl, v0 + geo['w'].to_f, geo['d'].to_f]
      end
      (begin; JSON.parse(it[:notch].to_s); rescue StandardError; []; end).each do |nt| # gola channel cut-outs: through the board, at the front edge
        v0, v1 = mirror ? [fw - nt['x1'].to_f, fw - nt['x0'].to_f] : [nt['x0'].to_f, nt['x1'].to_f]
        out[:rects] << ['NOTCH_GOLA', nt['y0'].to_f, v0, nt['y1'].to_f, v1, it[:thk].to_f]
      end
      out[:notes] << it[:notes].to_s if it[:notes].to_s =~ /L-cut|cutout/i
      out
    end

    # Shift from finished to RAW coordinates: a thick band on BOTH opposite edges moves every feature by one band thickness.
    def band_shift(it)
      t = it[:eb_t].to_f
      return [0.0, 0.0, nil] if t < Cutlist::EDGE_DEDUCT_MIN

      odd = it[:eb_w].to_i == 1 || it[:eb_l].to_i == 1
      [it[:eb_w].to_i == 2 ? t : 0.0, it[:eb_l].to_i == 2 ? t : 0.0, odd ? "#{t} mm band on ONE edge only: set the datum on the un-banded edge" : nil]
    end

    class Dxf
      def initialize; @o = +"0\nSECTION\n2\nENTITIES\n"; end

      def line(layer, x1, y1, x2, y2, z = 0)
        @o << "0\nLINE\n8\n#{layer}\n10\n#{x1.round(3)}\n20\n#{y1.round(3)}\n30\n#{z}\n11\n#{x2.round(3)}\n21\n#{y2.round(3)}\n31\n#{z}\n"
      end

      def rect(layer, x0, y0, x1, y1, z = 0)
        [[x0, y0, x1, y0], [x1, y0, x1, y1], [x1, y1, x0, y1], [x0, y1, x0, y0]].each { |a| line(layer, *a, z) }
      end

      def circle(layer, x, y, r, z = 0)
        @o << "0\nCIRCLE\n8\n#{layer}\n10\n#{x.round(3)}\n20\n#{y.round(3)}\n30\n#{z}\n40\n#{r.round(3)}\n"
      end

      def text(layer, x, y, h, str)
        @o << "0\nTEXT\n8\n#{layer}\n10\n#{x.round(3)}\n20\n#{y.round(3)}\n30\n0\n40\n#{h}\n1\n#{str.to_s.gsub(/[\r\n]+/, ' ')}\n"
      end

      def to_s; @o + "0\nENDSEC\n0\nEOF\n"; end
    end

    # One nested, layered DXF for a single material ([mat, thk] => nest entry of Cutlist.nest_all).
    def nest_dxf(mat, thk, n, gap = 400)
      d = Dxf.new
      sl, sw = n[:sheet]
      count = Hash.new(0)
      n[:sheets].each_with_index do |sh, i|
        ox = i * (sl + gap)
        d.rect('SHEET', ox, 0, ox + sl, sw)
        d.text('NOTES', ox, sw + 40, 40, "#{mat} #{thk} mm - sheet #{i + 1}/#{n[:sheets].size} - #{sl.round} x #{sw.round} - RAW cut sizes, machined face up")
        sh[:placed].each do |p|
          it = p[:item]
          x = ox + p[:x]
          y = p[:y]
          d.rect('OUTLINE', x, y, x + p[:w], y + p[:h], -thk.to_f)
          th = [[p[:h] / 8.0, 24].min, 6].max.round
          d.text('PART_ID', x + 8, y + 8, th, "#{it[:id]} #{it[:code]} #{it[:part]}")
          f = features(it)
          du, dv, warn = band_shift(it)
          cw = it[:w].to_f # raw width
          map = lambda do |u, v| # raw part coordinates -> sheet (a rotated part is turned 90 degrees, never mirrored)
            u -= du
            v -= dv
            p[:rotated] ? [x + cw - v, y + u] : [x + u, y + v]
          end
          f[:circles].each do |lay, u, v, dia, depth|
            cx, cy = map.call(u, v)
            d.circle(lay, cx, cy, dia / 2.0, -depth)
            count[lay] += 1
          end
          f[:rects].each do |lay, u0, v0, u1, v1, depth|
            u0 = [u0, du].max
            u1 = [u1, du + it[:l].to_f].min
            a = map.call(u0, v0)
            b = map.call(u1, v1)
            d.rect(lay, [a[0], b[0]].min, [a[1], b[1]].min, [a[0], b[0]].max, [a[1], b[1]].max, -depth)
            count[lay] += 1
          end
          ([warn] + f[:notes]).compact.each_with_index { |t, k| d.text('NOTES', x + 8, y + 8 + (k + 1) * th * 1.4, [th * 0.7, 5].max.round, t) }
        end
      end
      { dxf: d.to_s, count: count }
    end

    def slug(mat, thk)
      "#{mat.to_s.gsub(/[^A-Za-z0-9]+/, '_')}_#{thk.to_f.round(1).to_s.sub(/\.0\z/, '')}mm"
    end

    # Cut list of ONE material + thickness (finished and raw sizes side by side).
    def material_csv(an, mat, thk, lang = 'en')
      cfg = an[:cfg]
      head = ['Part ID', 'Unit', 'Part', 'Material', 'Thk', 'Finished L', 'Finished W', 'Cut L (raw)', 'Cut W (raw)', 'Edge L1', 'Edge L2', 'Edge W1', 'Edge W2', 'Edge mm', 'Notes']
      rows = an[:raw].select { |p| p[:mat] == mat && p[:thk] == thk }.sort_by { |p| [p[:code].to_s, p[:pid].to_s] }.map do |p|
        cl, cw = Cutlist.cut_size(p)
        [p[:pid], p[:code], I18n.part(p[:part], lang), (cfg['mat_names'] || {})[mat] || mat, thk, p[:len], p[:wid], cl, cw,
         *Cutlist.edge_sides(p).values.map { |b| b ? 'x' : '' }, p[:eb_t], [p[:groove], p[:notes]].compact.join(' ')]
      end
      "﻿" + ([head] + rows).map { |r| r.map { |v| "\"#{v.to_s.gsub('"', '""')}\"" }.join(',') }.join("\r\n")
    end

    # { relative file name => contents } + a status text. Sheet materials only (the same set that is nested).
    def files(an, lang = 'en')
      out = {}
      status = ['CAM / CNC DATA STATUS', 'Outline = RAW cut size (finished size minus 2 mm banding per banded edge on fronts and visible panels). Depth = negative Z of each entity.']
      an[:nest].each do |(mat, thk), n|
        s = slug(mat, thk)
        r = nest_dxf(mat, thk, n)
        out["cam/CAM_#{s}.dxf"] = r[:dxf]
        out["cutlists/cutlist_#{s}.csv"] = material_csv(an, mat, thk, lang)
        status << "#{mat} #{thk} mm: #{n[:sheets].size} sheet(s), #{n[:sheets].sum { |x| x[:placed].size }} board(s); " + (r[:count].empty? ? 'outlines only' : r[:count].sort.map { |k, v| "#{k}=#{v}" }.join(', '))
      end
      cups = an[:raw].flat_map { |p| (JSON.parse(p[:bore].to_s) rescue []).select { |h| h['dia'].to_f == 35 }.map { |h| [p, h] } }
      off = cups.map { |p, h| [h['x'].to_f, p[:wid].to_f - h['x'].to_f, h['y'].to_f, p[:len].to_f - h['y'].to_f].min.round(1) }.tally
      status << "POCKET_35MM: #{cups.size} hinge cup(s), depth #{HINGE_CUP[:depth]} mm. Cup centre exported at the E.G.C standard #{HINGE_CUP[:setback]} mm from the FINISHED door edge (the 3D model shows a generic hinge at #{off.keys.join(' / ')} mm). Confirm against the selected hinge before machining." if cups.any?
      status << 'Carcass joints: gable FACE bores only (5 mm connecting bolt + 8 mm dowel at the bottom / top joints, 37 mm from the front edge and 37 mm in front of the back panel). Edge bores and cam housings of the horizontal boards are NOT issued (edge drilling). Joints of fixed mid dividers are NOT issued.'
      status << 'NOTCH_GOLA: issued only for units built with the gola handle (L at the top-front corner, C between fronts; sizes = the profile sizes in the settings). The 3D gable carries the same cut-outs.'
      status << 'L-shaped corner base: outlines only. Its L-cut bottom / top are listed with their bounding size (see the note on the board) and its gables carry no joint bores - machine it from the unit sheet.' if an[:raw].any? { |p| p[:cab].to_s.include?('corner_l') }
      status << 'Left / right carcass sides are mirror images (inner face up). Check machine-side orientation on the first sheet before a full run.'
      out['cam/CAM_STATUS.txt'] = status.join("\r\n")
      out
    end
  end
end
