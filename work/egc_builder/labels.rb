# frozen_string_literal: true

module EGC
  # Printable board stickers: one per physical board, QR code + text. Data = the analysed cut list rows (same numbers as every other export).
  # QR payload: ProjectName|UnitCode|PartName|RawCut_WxL|Finished_WxL|Material|Edge_L1_L2_W1_W2
  module Labels
    module_function

    def h(s)
      s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
    end

    def num(v)
      f = v.to_f
      (f - f.round).abs < 0.05 ? f.round.to_s : f.round(1).to_s
    end

    def job(cfg)
      j = (cfg['job_name'] || (Sketchup.active_model.title rescue '')).to_s
      j.empty? ? '-' : j
    end

    def edges(p)
      t = Cutlist.edge_sides(p).select { |_, b| b }.keys.map { |k| k.to_s.upcase }
      t.empty? ? '-' : t.join('_')
    end

    def payload(p, cfg, job_name = job(cfg))
      cl, cw = Cutlist.cut_size(p)
      mat = (cfg['mat_names'] || {})[p[:mat]] || p[:mat]
      [job_name, p[:code], p[:part], "#{num(cw)}x#{num(cl)}", "#{num(p[:wid])}x#{num(p[:len])}", mat, edges(p)].join('|').tr("\r\n", '  ')
    end

    def qr(text)
      QR.svg(text, '24mm')
    rescue QR::TooLong
      QR.svg(text.encode('UTF-8').byteslice(0, 500).scrub(''), '24mm')
    end

    def html(an, lang = 'en')
      cfg = an[:cfg]
      ar = lang == 'ar'
      jn = job(cfg)
      t = ar ? { raw: 'تقطيع', fin: 'نهائي', eb: 'شريط', title: 'ملصقات القطع', none: 'بدون' } : { raw: 'Cut', fin: 'Finished', eb: 'Edge', title: 'Board labels', none: 'none' }
      cards = an[:raw].sort_by { |p| [p[:code].to_s, p[:pid].to_s] }.map do |p|
        cl, cw = Cutlist.cut_size(p)
        mat = (cfg['mat_names'] || {})[p[:mat]] || p[:mat]
        eb = edges(p)
        "<div class='lb'><div class='q'>#{qr(payload(p, cfg, jn))}</div><div class='t'><div class='u'><b>#{h(p[:code])}</b><span>#{h(p[:pid])}</span></div>" \
          "<div class='p'>#{h(I18n.part(p[:part], lang))}</div><div class='s'>#{t[:raw]}: <b dir='ltr'>#{num(cl)} × #{num(cw)} × #{num(p[:thk])}</b></div>" \
          "<div class='s'>#{t[:fin]}: <span dir='ltr'>#{num(p[:len])} × #{num(p[:wid])}</span></div><div class='m'>#{h(mat)}</div>" \
          "<div class='e'>#{t[:eb]}: <span dir='ltr'>#{eb == '-' ? t[:none] : "#{eb.tr('_', ' ')} · #{num(p[:eb_t])} mm"}</span></div><div class='j'>#{h(jn)}</div></div></div>"
      end
      <<~HTML
        <!DOCTYPE html><html lang="#{ar ? 'ar' : 'en'}" dir="#{ar ? 'rtl' : 'ltr'}"><head><meta charset="utf-8"><title>#{t[:title]} - #{h(jn)}</title><style>
        @page{size:A4;margin:8mm}body{font-family:Segoe UI,Tahoma,Arial,sans-serif;margin:0;color:#111}
        .sheet{display:grid;grid-template-columns:repeat(3,1fr);gap:2mm;padding:2mm}
        .lb{display:flex;gap:2mm;align-items:center;border:0.2mm solid #999;border-radius:1.5mm;padding:1.5mm;height:30mm;box-sizing:border-box;overflow:hidden;break-inside:avoid;page-break-inside:avoid}
        .q{flex:0 0 24mm;line-height:0}.t{flex:1;min-width:0;font-size:2.5mm;line-height:1.3}.u{display:flex;justify-content:space-between;align-items:baseline}
        .u b{font-size:4.6mm}.u span{font-size:2.3mm;color:#444}.p{font-weight:600;font-size:2.9mm;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
        .m,.j{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.j{color:#555;font-size:2.2mm}
        </style></head><body><div class="sheet">#{cards.join}</div></body></html>
      HTML
    end
  end
end
