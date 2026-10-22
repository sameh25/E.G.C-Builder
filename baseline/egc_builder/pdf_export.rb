# frozen_string_literal: true

require 'cgi'
require 'fileutils'
require 'tmpdir'
require 'uri'
require 'timeout'

module EGC
  # Controlled PDF conversion for user-facing production documents. Chromium is
  # an explicit external runtime dependency; failures are reported to the action UI.
  module PdfExport
    module_function

    def browser
      candidates = []
      if Sketchup.platform == :platform_win
        roots = [ENV['PROGRAMFILES(X86)'], ENV['PROGRAMFILES'], ENV['LOCALAPPDATA']].compact
        roots.each do |root|
          candidates << File.join(root, 'Microsoft', 'Edge', 'Application', 'msedge.exe')
          candidates << File.join(root, 'Google', 'Chrome', 'Application', 'chrome.exe')
        end
      end
      candidates.find { |path| File.file?(path) }
    end

    def html_to_pdf(html, output_path)
      exe = browser
      raise 'PDF_BROWSER_MISSING: install Microsoft Edge or Google Chrome to export PDF documents.' unless exe

      output_path = File.expand_path(output_path)
      FileUtils.mkdir_p(File.dirname(output_path))
      tmp = Dir.mktmpdir('egc_pdf_')
      begin
        html_path = File.join(tmp, 'document.html')
        profile = File.join(tmp, 'profile')
        log_path = File.join(tmp, 'chromium.log')
        File.binwrite(html_path, html.to_s.encode('UTF-8'))
        uri_path = URI::DEFAULT_PARSER.escape(html_path.tr('\\', '/'), /[^A-Za-z0-9\-_.~\/:]/)
        uri = "file:///#{uri_path}"
        args = [exe, '--headless=new', '--disable-gpu', '--no-pdf-header-footer', "--user-data-dir=#{profile}", "--print-to-pdf=#{output_path}", uri]
        status = Timeout.timeout(180) do
          pid = Process.spawn(*args, out: log_path, err: log_path)
          begin
            Process.wait2(pid).last
          rescue Timeout::Error
            Process.kill('KILL', pid) rescue nil
            raise
          end
        end
        # Chromium can exit non-zero after a complete print (second export right after the first): a COMPLETE PDF (header + %%EOF trailer) is accepted
        complete = File.file?(output_path) && File.size(output_path) > 500 && File.binread(output_path, 5) == '%PDF-' && File.binread(output_path)[-1024..].to_s.include?('%%EOF')
        unless complete
          File.delete(output_path) if File.file?(output_path)
          details = File.file?(log_path) ? File.read(log_path, encoding: 'UTF-8').strip[0, 240] : ''
          raise "PDF_EXPORT_FAILED: Chromium did not create a valid PDF. #{details}"
        end
      ensure
        # Chromium helper processes can still hold files for a moment: cleanup must never fail the export.
        begin
          FileUtils.rm_rf(tmp)
        rescue StandardError
          nil
        end
      end
      output_path
    rescue Timeout::Error
      raise 'PDF_EXPORT_TIMEOUT: PDF conversion exceeded 180 seconds; close other browser print jobs and retry.'
    end

    def combine_html(files, title:, lang: 'en')
      styles = []
      bodies = files.map do |path|
        html = File.read(path, encoding: 'UTF-8')
        styles.concat(html.scan(/<style[^>]*>(.*?)<\/style>/mi).flatten)
        html[/<body[^>]*>(.*?)<\/body>/mi, 1] || html
      end
      dir = lang == 'ar' ? 'rtl' : 'ltr'
      css = "@page{size:A3 landscape;margin:8mm}body{margin:0;background:#fff} .sheet{max-width:none;margin:0;padding:4mm 4mm 30mm 4mm;border:2px solid #222;min-height:250mm;position:relative;break-after:page;page-break-after:always}.sheet>table.tb{position:absolute;left:4mm;right:4mm;bottom:3mm;width:calc(100% - 8mm);margin:0}.draw{text-align:center}.draw:has(~ table.data) svg{max-height:112mm}.draw svg{max-height:170mm;width:auto;max-width:100%;margin:0 auto;display:block}.ud-l{float:left;width:52%}.ud-r{float:right;width:46%}.ud-r table.data{font-size:9px;margin:4px 0}.ud-r table.data th,.ud-r table.data td{padding:1px 4px}.views{display:flex;gap:16px;align-items:flex-end;flex-wrap:wrap}.views figure{margin:0}.views svg{max-height:105mm;width:auto}}"
      "<!doctype html><html lang='#{CGI.escapeHTML(lang)}' dir='#{dir}'><head><meta charset='utf-8'><title>#{CGI.escapeHTML(title)}</title><style>#{SvgDraw::CSS}\n#{styles.join("\n")}\n#{css}</style></head><body>#{bodies.join("\n\n")}</body></html>"
    end
  end
end
