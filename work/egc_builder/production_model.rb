# frozen_string_literal: true

require 'json'
require 'digest'

module EGC
  # MASTER PRODUCTION DATA. Every production output (cut list, nesting, CNC DXF, labels, drawings' part tables, BOM, packages) is derived from ONE
  # analysis of the model (Cutlist.analyse): the boards stored on the units with their Part IDs. This module freezes that analysis into a snapshot
  # (units, parts, hardware), compares snapshots (change impact, revisions) and classifies every board into its production family.
  module ProductionModel
    module_function

    FAMILY_ORDER = %w[CARCASS EXTERIOR BACK WORKTOP PLINTH SPECIAL].freeze

    # production family of one board: CARCASS (sides, top, bottom, shelves, dividers, rails), EXTERIOR / FINISH (doors, drawer fronts, end / decorative
    # panels, fillers), BACK, WORKTOP (worktop, splash), PLINTH (purchased profile), SPECIAL (glass, hardware boards ...)
    def family(p)
      mat = p[:mat].to_s
      part = p[:part].to_s
      return 'PLINTH' if part == 'plinth' || mat == 'plinth'
      return 'WORKTOP' if %w[top splash].include?(mat)
      return 'BACK' if mat == 'back'
            return 'SPECIAL' if mat == 'glass'
      return 'EXTERIOR' if mat == 'front' || %w[door door1 door2 drawer_front flap flap_upper flap_lower end_panel filler trim fascia].include?(part)

      'CARCASS'
    end

    def snapshot(an)
      parts = {}
      an[:raw].each do |p|
        cl, cw = Cutlist.cut_size(p)
        parts[p[:pid].to_s] = { 'unit' => p[:code].to_s, 'part' => p[:part].to_s, 'mat' => p[:mat].to_s, 'family' => family(p), 'thk' => p[:thk], 'len' => p[:len], 'wid' => p[:wid],
                                'cut' => [cl, cw], 'eb' => [p[:eb_l], p[:eb_w], p[:eb_t]], 'machining' => Digest::MD5.hexdigest([p[:bore], p[:back_groove], p[:groove_geo], p[:notch]].to_s)[0, 10] }
      end
      units = {}
      an[:cabs].each { |c| units[c[:code].to_s] = { 'type' => c[:type], 'kind' => c[:kind], 'w' => c[:w], 'h' => c[:h], 'd' => c[:d], 'hw' => c[:hw] } }
      body = JSON.generate([units.sort, parts.sort])
      { 'units' => units, 'parts' => parts, 'hw' => an[:hw].to_h, 'hash' => Digest::SHA256.hexdigest(body)[0, 16] }
    end

    def capture(cfg, model = Sketchup.active_model)
      snapshot(Cutlist.analyse(cfg, model, use_selection: false))
    end

    # -> { 'parts' => { 'added', 'removed', 'modified' }, 'units' => { ... }, 'fronts' => n, 'machining' => n, 'hw' => { item => [before, after] } }
    def diff(a, b)
      pa = a['parts']
      pb = b['parts']
      added = pb.keys - pa.keys
      removed = pa.keys - pb.keys
      modified = (pa.keys & pb.keys).reject { |k| pa[k] == pb[k] }
      ua = a['units']
      ub = b['units']
      umod = (ua.keys & ub.keys).reject { |k| ua[k] == ub[k] }
      hw = (a['hw'].keys | b['hw'].keys).filter_map { |k| [k, [a['hw'][k].to_f, b['hw'][k].to_f]] if (a['hw'][k].to_f - b['hw'][k].to_f).abs > 1e-6 }.to_h
      touched = (added + removed + modified)
      fam = ->(k) { (pb[k] || pa[k])['family'] }
      { 'parts' => { 'added' => added, 'removed' => removed, 'modified' => modified }, 'units' => { 'added' => ub.keys - ua.keys, 'removed' => ua.keys - ub.keys, 'modified' => umod },
        'fronts' => touched.count { |k| fam.call(k) == 'EXTERIOR' }, 'machining' => modified.count { |k| pa[k]['machining'] != pb[k]['machining'] } + added.size,
        'families' => touched.map { |k| fam.call(k) }.tally, 'hw' => hw }
    end

    # CHANGE IMPACT report of one edit (before / after snapshots of the SAME master data)
    def impact(before, after, code, what)
      d = diff(before, after)
      u0 = before['units'][code] || {}
      u1 = after['units'][code] || {}
      ch = %w[w h d type].filter_map { |k| "#{k} #{u0[k].is_a?(Numeric) ? u0[k].round : u0[k]} -> #{u1[k].is_a?(Numeric) ? u1[k].round : u1[k]}" if u0[k] != u1[k] }
      others = d['units']['modified'] - [code]
      p = d['parts']
      lines = ["#{code} changed: #{ch.empty? ? what : ch.join(', ')}",
               'Geometry: UPDATED',
               "Parts: #{p['modified'].size} modified, #{p['added'].size} added, #{p['removed'].size} removed",
               "Fronts: #{d['fronts']} changed",
               "Hardware: #{d['hw'].empty? ? 'unchanged' : d['hw'].map { |k, (a, b)| "#{k} #{a.round(2)} -> #{b.round(2)}" }.join(', ')}",
               "Other units touched: #{others.empty? ? 'none' : others.join(', ')}"]
      %w[Cut\ List Nesting DXF/CNC Shop\ Drawing BOM Labels Factory\ Package Site\ Package].each { |o| lines << "#{o}: UPDATED (generated from the master data on the next export)" }
      { 'unit' => code, 'diff' => d, 'lines' => lines, 'others' => others }
    end
  end

  # REVISIONS: every issued package records the master-data snapshot; a different snapshot opens the next revision letter (A, B, C ...) with what was
  # added / removed / modified. The current letter is written on every drawing sheet and package.
  module Revision
    module_function

    KEY = 'egc_revisions'

    def list(model = Sketchup.active_model)
      JSON.parse(model.get_attribute(KEY, 'list', '[]'))
    rescue StandardError
      []
    end

    def current(model = Sketchup.active_model)
      (list(model).last || {})['rev']
    end

    def next_letter(rev)
      return 'A' if rev.nil? || rev.empty?

      rev.succ
    end

    # -> the revision record that matches the model now (a new one when the master data changed since the last issue)
    def issue(cfg, model = Sketchup.active_model, reason = 'issue')
      snap = ProductionModel.capture(cfg, model)
      revs = list(model)
      last = revs.last
      return last.merge('new' => false) if last && last['hash'] == snap['hash']

      prev = last && last['snap']
      d = prev ? ProductionModel.diff(prev, snap) : nil
      sheets = d ? (d['units']['modified'] + d['units']['added'] + d['units']['removed']).uniq : []
      summary = if d
                  dp = d['parts']
                  ["#{sheets.join(', ')} changed", "#{dp['modified'].size} part(s) modified", "#{dp['added'].size} part(s) added", "#{dp['removed'].size} part(s) removed",
                   "#{sheets.size} unit drawing(s) updated", "#{d['machining']} CNC operation set(s) updated"]
                else
                  ['first issue']
                end
      rec = { 'rev' => next_letter(last && last['rev']), 'at' => Time.now.utc.strftime('%Y-%m-%d %H:%M UTC'), 'reason' => reason, 'hash' => snap['hash'], 'summary' => summary,
              'changed_units' => sheets, 'diff' => d && { 'added' => d['parts']['added'], 'removed' => d['parts']['removed'], 'modified' => d['parts']['modified'] }, 'snap' => snap }
      revs << rec
      model.set_attribute(KEY, 'list', JSON.generate(revs.last(12)))
      proj = Assistant.load(model)
      proj['rev'] = rec['rev']
      Assistant.save(proj, model)
      rec.merge('new' => true)
    end

    def text(model = Sketchup.active_model)
      list(model).map { |r| "REV #{r['rev']}  #{r['at']}  #{r['reason']}\r\n  #{r['summary'].join("\r\n  ")}" }.join("\r\n\r\n")
    end
  end
end
