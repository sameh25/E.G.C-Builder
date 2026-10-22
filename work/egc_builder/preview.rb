# frozen_string_literal: true

require 'cgi'
require 'fileutils'
require 'tmpdir'
require 'json'

module EGC
  # PREVIEW BEFORE SAVE. Every production / shop-drawing output is first written to a temporary staging folder and shown in one window
  # (file list + the document itself); nothing reaches the user's disk until Save is pressed, and what is saved is byte-for-byte the staged
  # files that were shown (copied, never regenerated). Cancel / closing the window discards the staging folder.
  module Preview
    module_function

    WRAPPER = '_egc_preview.html'
    VIEWS = '_egc_views' # generated viewer pages for non-HTML files (CSV table, DXF drawing, text) - never saved

    class << self
      attr_reader :stage, :job, :dlg, :shown # shown: names of the files the window really displayed (reported by the page itself)
    end

    def h(v)
      CGI.escapeHTML(v.to_s)
    end

    def new_stage
      discard
      @stage = Dir.mktmpdir('egc_preview_')
    end

    def discard
      d = @dlg
      @dlg = nil
      begin
        d.close if d && d.visible?
      rescue StandardError
        nil
      end
      begin
        FileUtils.rm_rf(@stage) if @stage && File.directory?(@stage)
      rescue StandardError
        nil
      end
      @stage = nil
      job = @job
      @job = nil
      begin
        job[:on_cancel].call if job && job[:on_cancel] && !job[:saved]
      rescue StandardError => e
        Diag.log('preview_cancel', {}, error: e) if defined?(Diag)
      end
    end

    # ONE document. kind: :file (saved as is) | :pdf (the previewed HTML is converted to PDF on save).
    def document(content, filename, title:, lang: 'en', kind: :file, save_name: nil, on_saved: nil)
      dir = new_stage
      File.binwrite(File.join(dir, filename), content.to_s.encode('UTF-8'))
      open_window(title: title, lang: lang, kind: kind, entry: filename, save_name: save_name || filename, on_saved: on_saved)
    end

    # A whole package: the block receives the staging folder and builds into it; returns its result hash (kept in job[:result]).
    def package(title:, folder_name:, lang: 'en', entry: nil, open_after: nil, on_saved: nil, on_cancel: nil)
      dir = new_stage
      result = begin
        yield(dir)
      rescue StandardError
        discard
        raise
      end
      open_window(title: title, lang: lang, kind: :folder, entry: entry, save_name: folder_name, on_saved: on_saved, result: result, open_after: open_after, on_cancel: on_cancel)
    end

    def files
      return [] unless @stage

      Dir.glob(File.join(@stage, '**', '*')).select { |f| File.file?(f) }.map { |f| f[(@stage.size + 1)..] }
         .reject { |r| r == WRAPPER || r.start_with?("#{VIEWS}/") }.sort_by { |r| [r.count('/'), r.downcase] }
    end

    # ---------------------------------------------------------------------------------------------------------------- viewer pages
    def parse_csv(text)
      rows = []
      row = []
      cell = +''
      q = false
      chars = text.delete_prefix("﻿").chars
      i = 0
      while i < chars.size
        c = chars[i]
        if q
          if c == '"' && chars[i + 1] == '"'
            cell << '"'
            i += 1
          elsif c == '"' then q = false
          else cell << c
          end
        elsif c == '"' then q = true
        elsif c == ',' || c == ';' && !text.include?(',')
          row << cell
          cell = +''
        elsif c == "\n"
          row << cell
          rows << row
          row = []
          cell = +''
        elsif c != "\r" then cell << c
        end
        i += 1
      end
      row << cell unless cell.empty? && row.empty?
      rows << row unless row.empty?
      rows
    end

    VIEW_CSS = 'body{font:13px Segoe UI,Arial,sans-serif;margin:14px;color:#1c2530}table{border-collapse:collapse;width:100%}th,td{border:1px solid #c9d1da;padding:4px 8px;text-align:start;white-space:nowrap}' \
               'th{background:#17324d;color:#fff;position:sticky;top:0}tr:nth-child(even) td{background:#f4f7fa}.meta{color:#56616d;margin:0 0 10px}pre{white-space:pre-wrap;font:12px Consolas,monospace}' \
               'svg{background:#fff;border:1px solid #c9d1da;max-width:100%;height:auto}.note{padding:18px;background:#fff7e0;border:1px solid #e3c96b;border-radius:6px}'

    def view_page(body, lang)
      "<!doctype html><html lang='#{lang}' dir='#{lang == 'ar' ? 'rtl' : 'ltr'}'><head><meta charset='utf-8'><style>#{VIEW_CSS}</style></head><body>#{body}<script>try{parent.postMessage('egc-view-ok','*')}catch(e){}</script></body></html>"
    end

    def csv_view(text, lang)
      rows = parse_csv(text)
      return view_page("<p class='note'>#{lang == 'ar' ? 'الملف فارغ' : 'Empty file'}</p>", lang) if rows.empty?

      head = rows.first
      body = rows[1..]
      meta = lang == 'ar' ? "#{body.size} صف × #{head.size} عمود" : "#{body.size} rows x #{head.size} columns"
      view_page("<p class='meta'>#{meta}</p><table><thead><tr>#{head.map { |c| "<th>#{h(c)}</th>" }.join}</tr></thead><tbody>" \
                "#{body.map { |r| "<tr>#{r.map { |c| "<td>#{h(c)}</td>" }.join}</tr>" }.join}</tbody></table>", lang)
    end

    # The DXF written by Nesting.dxf holds only LINE + TEXT entities: draw exactly those (what the machine will read).
    def dxf_view(text, lang)
      ls = text.lines.map(&:strip)
      ents = []
      cur = nil
      i = 0
      while i + 1 < ls.size
        code = ls[i]
        val = ls[i + 1]
        if code == '0'
          ents << cur if cur
          cur = %w[LINE TEXT CIRCLE].include?(val) ? { t: val } : nil
        elsif cur
          cur[code] = val
        end
        i += 2
      end
      ents << cur if cur
      lines = ents.select { |e| e[:t] == 'LINE' }
      return view_page("<p class='note'>DXF: #{lang == 'ar' ? 'لا توجد خطوط' : 'no line entities'}</p>", lang) if lines.empty?

      xs = lines.flat_map { |e| [e['10'].to_f, e['11'].to_f] }
      ys = lines.flat_map { |e| [e['20'].to_f, e['21'].to_f] }
      x0, x1 = xs.minmax
      y0, y1 = ys.minmax
      pad = 80.0
      w = x1 - x0 + 2 * pad
      ht = y1 - y0 + 2 * pad + 60
      col = ->(layer) { layer.to_s.start_with?('GROOVE') ? '#c0392b' : { 'SHEET' => '#111', 'PARTS' => '#1f5fa8', 'OUTLINE' => '#1f5fa8', 'BACK_EDGE' => '#2e8b57', 'DRILL_5MM' => '#0a7d3b', 'DRILL_8MM' => '#b8860b', 'POCKET_35MM' => '#7b2fbf' }.fetch(layer.to_s, '#555') }
      sw = [w / 900.0, 1.0].max
      s = +"<svg xmlns='http://www.w3.org/2000/svg' viewBox='#{(x0 - pad).round(1)} #{(-y1 - pad - 60).round(1)} #{w.round(1)} #{ht.round(1)}'>"
      lines.each { |e| s << "<line x1='#{e['10']}' y1='#{-e['20'].to_f}' x2='#{e['11']}' y2='#{-e['21'].to_f}' stroke='#{col.call(e['8'])}' stroke-width='#{(e['8'] == 'SHEET' ? 2.2 * sw : 1.2 * sw).round(2)}'/>" }
      ents.select { |e| e[:t] == 'CIRCLE' }.each { |e| s << "<circle cx='#{e['10']}' cy='#{-e['20'].to_f}' r='#{e['40']}' fill='none' stroke='#{col.call(e['8'])}' stroke-width='#{(1.2 * sw).round(2)}'/>" }
      ents.select { |e| e[:t] == 'TEXT' }.each { |e| s << "<text x='#{e['10']}' y='#{-e['20'].to_f}' font-size='#{e['40']}' font-family='Arial' fill='#222'>#{h(e['1'])}</text>" }
      s << '</svg>'
      meta = lang == 'ar' ? "#{lines.size} خط — الأسود: اللوح، الأزرق: القطع، الأحمر: المجاري، الأخضر: ثقوب 5، البنفسجي: كوب المفصلة 35" : "#{lines.size} lines - black: sheet, blue: parts, red: grooves, green: 5 mm holes, purple: 35 mm hinge cups"
      view_page("<p class='meta'>#{meta}</p>#{s}", lang)
    end

    def text_view(text, lang)
      view_page("<pre>#{h(text)}</pre>", lang)
    end

    # relative path of the page the window shows for a staged file
    def viewer_for(rel, lang)
      ext = File.extname(rel).downcase
      return rel if %w[.html .htm .svg .png .jpg .jpeg].include?(ext)

      src = File.join(@stage, rel)
      body = case ext
             when '.csv' then csv_view(File.read(src, encoding: 'bom|utf-8'), lang)
             when '.dxf' then dxf_view(File.read(src, encoding: 'utf-8'), lang)
             when '.pdf'
               view_page("<p class='note'>#{lang == 'ar' ? 'ملف PDF للطباعة: نفس لوحات ملف HTML المعروض في القائمة (صفحة لكل لوحة). يُحفظ مع الحزمة.' : 'Print PDF: the same sheets as the HTML drawing set in this list (one sheet per page). It is saved with the package.'}</p>", lang)
             else text_view(File.read(src, encoding: 'bom|utf-8'), lang)
             end
      out = File.join(@stage, VIEWS, "#{rel.gsub(%r{[/\\]}, '__')}.html")
      FileUtils.mkdir_p(File.dirname(out))
      File.binwrite(out, body.encode('UTF-8'))
      "#{VIEWS}/#{File.basename(out)}"
    end

    # ---------------------------------------------------------------------------------------------------------------- window
    def wrapper_html(title, lang, list, entry)
      ar = lang == 'ar'
      items = list.map { |rel, view| { 'name' => rel, 'view' => view.split('/').map { |s| CGI.escape(s).gsub('+', '%20') }.join('/') } }
      first = items.find { |i| i['name'] == entry } || items.find { |i| i['name'] =~ /\.html?$/i && i['name'] !~ /index\.html$/i } || items.first
      <<~HTML
        <!doctype html><html lang="#{lang}" dir="#{ar ? 'rtl' : 'ltr'}"><head><meta charset="utf-8"><title>#{h(title)}</title><style>
        *{box-sizing:border-box}html,body{height:100%;margin:0}body{font:14px Segoe UI,Tahoma,Arial,sans-serif;display:flex;flex-direction:column;background:#eef1f4;color:#1c2530}
        header{display:flex;align-items:center;gap:12px;padding:10px 14px;background:#17324d;color:#fff}header h1{font-size:16px;margin:0;flex:1;font-weight:600}
        .tag{background:#f0b429;color:#3a2a00;border-radius:4px;padding:3px 9px;font-size:12px;font-weight:700}
        button{font:inherit;border:0;border-radius:6px;padding:9px 20px;cursor:pointer;font-weight:600}#save{background:#22a35a;color:#fff}#save:hover{background:#1b8a4b}#cancel{background:#dfe5ea;color:#1c2530}
        main{flex:1;display:flex;min-height:0}nav{width:270px;overflow:auto;background:#fff;border-inline-end:1px solid #c9d1da;padding:8px}
        nav.one{display:none}nav a{display:block;padding:7px 9px;border-radius:5px;color:#17324d;text-decoration:none;font-size:13px;word-break:break-all;cursor:pointer}
        nav a:hover{background:#eef3f8}nav a.on{background:#17324d;color:#fff}nav .grp{font-size:11px;color:#6b7783;margin:10px 6px 3px;text-transform:uppercase}
        iframe{flex:1;border:0;background:#fff;min-width:0}footer{padding:6px 14px;font-size:12px;color:#56616d;background:#fff;border-top:1px solid #c9d1da}
        </style></head><body>
        <header><span class="tag">#{ar ? 'معاينة — لم يُحفظ بعد' : 'PREVIEW - NOT SAVED YET'}</span><h1>#{h(title)}</h1>
        <button id="cancel">#{ar ? 'إلغاء' : 'Cancel'}</button><button id="save">#{ar ? 'حفظ' : 'Save'}</button></header>
        <main><nav id="nav" class="#{items.size <= 1 ? 'one' : ''}"></nav><iframe id="view"></iframe></main>
        <footer id="foot"></footer>
        <script>
        const ITEMS=#{JSON.generate(items)},FIRST=#{JSON.generate(first && first['name'])},AR=#{ar};
        const nav=document.getElementById('nav'),view=document.getElementById('view'),foot=document.getElementById('foot');
        function show(n){const it=ITEMS.find(i=>i.name===n);if(!it)return;view.src=it.view;[...nav.querySelectorAll('a')].forEach(a=>a.classList.toggle('on',a.dataset.n===n));
          foot.textContent=(AR?'الملف المعروض: ':'Showing: ')+n+(AR?'  —  عدد الملفات: ':'  -  files: ')+ITEMS.length}
        let grp=null;ITEMS.forEach(it=>{const g=it.name.includes('/')?it.name.slice(0,it.name.lastIndexOf('/')):'';
          if(g!==grp){grp=g;if(g){const d=document.createElement('div');d.className='grp';d.textContent=g;nav.appendChild(d)}}
          const a=document.createElement('a');a.dataset.n=it.name;a.textContent=g?it.name.slice(g.length+1):it.name;a.onclick=()=>show(it.name);nav.appendChild(a)});
        let CUR=null;const _show=show;show=function(n){CUR=n;_show(n)};
        const tell=()=>{if(window.sketchup&&sketchup.pv_shown&&CUR)sketchup.pv_shown(CUR)};
        view.addEventListener('load',tell);window.addEventListener('message',e=>{if(e.data==='egc-view-ok')tell()});
        if(FIRST)show(FIRST);
        const call=n=>{if(window.sketchup&&sketchup[n])sketchup[n]()};
        document.getElementById('save').onclick=()=>call('pv_save');document.getElementById('cancel').onclick=()=>call('pv_cancel');
        </script></body></html>
      HTML
    end

    def open_window(title:, lang:, kind:, entry:, save_name:, on_saved:, result: nil, open_after: nil, on_cancel: nil)
      list = files.map { |rel| [rel, viewer_for(rel, lang)] }
      raise 'PREVIEW_EMPTY: the export produced no files.' if list.empty?

      File.binwrite(File.join(@stage, WRAPPER), wrapper_html(title, lang, list, entry).encode('UTF-8'))
      @job = { title: title, lang: lang, kind: kind, entry: entry || list.first.first, save_name: save_name, on_saved: on_saved, result: result, open_after: open_after, on_cancel: on_cancel }
      @dlg = ::UI::HtmlDialog.new(dialog_title: "E.G.C - #{title}", preferences_key: 'EGC_Builder_Preview', scrollable: false, resizable: true,
                                  width: 1280, height: 860, min_width: 700, min_height: 480, style: ::UI::HtmlDialog::STYLE_DIALOG)
      @dlg.set_file(File.join(@stage, WRAPPER))
      @dlg.add_action_callback('pv_save') { |_| guarded { save! } }
      @dlg.add_action_callback('pv_cancel') { |_| discard }
      @shown = []
      @dlg.add_action_callback('pv_shown') { |_, name| @shown << name.to_s unless @shown.include?(name.to_s) }
      stage = @stage
      @dlg.set_on_closed { discard if @stage == stage }
      @dlg.show
      @job
    end

    def guarded
      yield
    rescue StandardError => e
      Diag.log('preview_save', {}, error: e) if defined?(Diag)
      ::UI.messagebox(e.message.to_s[0, 600])
    end

    def default_dir
      m = Sketchup.active_model
      m.path.to_s.empty? ? nil : File.dirname(m.path)
    end

    # Writes the staged files to the place the user picks. Returns the saved path (nil when the user cancels the file dialog - the preview stays open).
    def save!
      job = @job
      raise 'PREVIEW_CLOSED: nothing is staged for saving.' unless job && @stage

      ar = job[:lang] == 'ar'
      saved = case job[:kind]
              when :folder
                root = ::UI.select_directory(title: ar ? 'اختر مكان حفظ الحزمة' : 'Choose where to save the package')
                return nil unless root

                target = File.join(root, job[:save_name])
                target += "_#{Time.now.strftime('%H%M%S')}" if File.exist?(target) # never overwrite / merge into an older issue

                files.each do |rel|
                  dst = File.join(target, rel)
                  FileUtils.mkdir_p(File.dirname(dst))
                  FileUtils.cp(File.join(@stage, rel), dst)
                end
                target
              when :pdf
                path = ::UI.savepanel(ar ? 'حفظ PDF' : 'Save PDF', default_dir, job[:save_name])
                return nil unless path

                path += '.pdf' unless path.downcase.end_with?('.pdf')
                PdfExport.html_to_pdf(File.read(File.join(@stage, job[:entry]), encoding: 'utf-8'), path)
              else
                path = ::UI.savepanel(ar ? 'حفظ الملف' : 'Save file', default_dir, job[:save_name])
                return nil unless path

                FileUtils.cp(File.join(@stage, job[:entry]), path)
                path
              end
      open_path = case job[:kind]
                  when :folder then File.join(saved, job[:open_after] || job[:entry])
                  when :pdf then saved
                  else saved =~ /\.html?$/i ? saved : nil
                  end
      ::UI.openURL("file:///#{open_path.tr('\\', '/')}") if open_path && File.exist?(open_path)
      cb = job[:on_saved]
      job[:saved] = true
      discard
      cb&.call(saved)
      saved
    end
  end
end
