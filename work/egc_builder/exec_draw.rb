# frozen_string_literal: true

require 'cgi'

module EGC
  # TEST_17 drawing engine: fixed-size A3 landscape sheets (420 x 297 mm) drawn as ONE SVG per sheet in millimetres, so every view has a
  # real scale (1:N), a fixed frame / title block, a dimension hierarchy and enlarged DETAIL callouts. English = LTR, Arabic = RTL
  # (title block, notes, schedules and text anchors mirror). Used by the Factory and the Site drawing sets.
  module ExecDraw
    module_function

    PW = 420.0
    PH = 297.0
    FRAME = 10.0
    TB_H = 32.0
    STD_SCALES = [1, 2, 2.5, 4, 5, 8, 10, 12.5, 15, 20, 25, 30, 40, 50, 60, 75, 100, 125, 150, 200].freeze
    FONT = "Segoe UI, Tahoma, Arial, sans-serif"

    TXT = {
      'en' => {
        'brand' => 'E.G.C Builder', 'project' => 'Project', 'client' => 'Client', 'title' => 'Drawing title', 'sheet' => 'Sheet', 'rev' => 'Revision', 'date' => 'Date',
        'scale' => 'Scale', 'status' => 'Status', 'language' => 'Language', 'lang_name' => 'English (LTR)', 'zone' => 'Unit / zone', 'draft' => 'DRAFT', 'current' => 'CURRENT',
        'front' => 'FRONT ELEVATION', 'section_a' => 'SECTION A-A (side, cut at mid width)', 'section_b' => 'PLAN SECTION B-B (cut at mid height)', 'detail' => 'DETAIL',
        'notes' => 'NOTES', 'parts' => 'PARTS', 'index' => 'DRAWING INDEX', 'cover' => 'COVER AND DRAWING INDEX', 'ga' => 'GENERAL ARRANGEMENT', 'ids' => 'UNIT IDENTIFICATION',
        'unit' => 'UNIT', 'overall' => 'OVERALL', 'carcass' => 'carcass', 'incl_front' => 'incl. front', 'width' => 'W', 'height' => 'H', 'depth' => 'D', 'nts' => 'NTS',
        'req_hinge' => 'REQUIRES HINGE SPECIFICATION - no cup drilling issued', 'req_runner' => 'REQUIRES RUNNER SPECIFICATION - no runner drilling issued',
        'req_mech' => 'REQUIRES MECHANISM SPECIFICATION - no drilling issued', 'req_app' => 'REQUIRES CONFIRMATION - appliance clearances not issued',
        'confirmed_drill' => 'CONFIRMED DRILLING', 'no_drill' => 'No confirmed drilling data for this unit.', 'unit_ids' => 'Unit and part IDs are identical in the model, drawings, cut list, labels and production data.',
        'back_groove' => 'BACK GROOVE', 'rear_edge' => 'REAR EDGE', 'offset' => 'offset', 'groove_depth' => 'depth', 'back' => 'BACK', 'side' => 'SIDE PANEL', 'sheet_of' => 'sheet',
        'material' => 'Material', 'part' => 'Part', 'qty' => 'Qty', 'length' => 'Length', 'edge' => 'Edge', 'pid' => 'Part ID', 'thk' => 'Thk', 'notes_col' => 'Notes', 'type' => 'Type',
        'item' => 'Item', 'quantity' => 'Quantity', 'verification' => 'Verification', 'mechanism' => 'Mechanism', 'appliance' => 'Appliance', 'opening' => 'Opening W x H x D',
        'data_status' => 'Data status', 'plinth_note' => 'Plastic plinth: purchased 3000 mm profile, not sheet stock', 'drawer_board' => 'Drawer box board', 'see_s08' => 'All service points with X, Z and status: see SERVICE SCHEDULE S-08.', 'detail_note' => 'dimensions: from unit left edge and unit bottom; X from datum, Z = AFFL', 'stack' => 'STACKED TALL UNIT', 'lower_mod' => 'LOWER MODULE', 'upper_mod' => 'UPPER MODULE',
        'joint' => 'carcass joint', 'assembly' => 'ASSEMBLY', 'front_zone' => 'FRONT ZONE', 'hinge_zone' => 'HINGE ZONE', 'drawer_zone' => 'DRAWER / RUNNER ZONE', 'cutout' => 'WORKTOP CUTOUT',
        'lift' => 'LIFT-UP FRONT PATH', 'appliance_opening' => 'APPLIANCE OPENING', 'filler' => 'NARROW FILLER', 'custom' => 'CUSTOM UNIT', 'organizer' => 'INTERNAL ORGANIZER', 'door_gap' => 'front gap', 'front_thk' => 'front', 'shelf' => 'shelf',
        'datum' => 'DATUM', 'ffl' => 'FFL', 'x_dim' => 'X from datum', 'z_dim' => 'Z = AFFL', 'legend' => 'LEGEND', 'services' => 'SERVICES', 'inferred_note' => 'Inferred or unconfirmed values must be verified on site.'
      },
      'ar' => {
        'brand' => 'E.G.C Builder', 'project' => 'المشروع', 'client' => 'العميل', 'title' => 'عنوان اللوحة', 'sheet' => 'اللوحة', 'rev' => 'المراجعة', 'date' => 'التاريخ',
        'scale' => 'المقياس', 'status' => 'الحالة', 'language' => 'اللغة', 'lang_name' => 'العربية (RTL)', 'zone' => 'الوحدة / المنطقة', 'draft' => 'مسودة', 'current' => 'حالي',
        'front' => 'الواجهة الأمامية', 'section_a' => 'قطاع A-A (جانبي عند منتصف العرض)', 'section_b' => 'قطاع أفقي B-B (عند منتصف الارتفاع)', 'detail' => 'تفصيل',
        'notes' => 'ملاحظات', 'parts' => 'القطع', 'index' => 'فهرس اللوحات', 'cover' => 'الغلاف وفهرس اللوحات', 'ga' => 'المخطط العام', 'ids' => 'ترقيم الوحدات',
        'unit' => 'وحدة', 'overall' => 'الإجمالي', 'carcass' => 'الهيكل', 'incl_front' => 'شامل الواجهة', 'width' => 'ع', 'height' => 'ا', 'depth' => 'ق', 'nts' => 'بدون مقياس',
        'req_hinge' => 'يتطلب مواصفة المفصلة - لا توجد ثقوب كأس صادرة', 'req_runner' => 'يتطلب مواصفة المجرى - لا توجد ثقوب مجاري صادرة',
        'req_mech' => 'يتطلب مواصفة الميكانيزم - لا توجد ثقوب صادرة', 'req_app' => 'يتطلب تأكيد - لم تصدر خلوصات الجهاز',
        'confirmed_drill' => 'ثقوب مؤكدة', 'no_drill' => 'لا توجد بيانات ثقوب مؤكدة لهذه الوحدة.', 'unit_ids' => 'أرقام الوحدات والقطع متطابقة في النموذج والرسومات وقائمة القطع والملصقات وبيانات الإنتاج.',
        'back_groove' => 'مجرى الظهر', 'rear_edge' => 'الحافة الخلفية', 'offset' => 'إزاحة', 'groove_depth' => 'عمق', 'back' => 'الظهر', 'side' => 'الجنب', 'sheet_of' => 'لوحة',
        'material' => 'الخامة', 'part' => 'القطعة', 'qty' => 'العدد', 'length' => 'الطول', 'edge' => 'الشريط', 'pid' => 'رقم القطعة', 'thk' => 'السمك', 'notes_col' => 'ملاحظات', 'type' => 'النوع',
        'item' => 'البند', 'quantity' => 'الكمية', 'verification' => 'التحقق', 'mechanism' => 'الميكانيزم', 'appliance' => 'الجهاز', 'opening' => 'الفتحة ع × ا × ق',
        'data_status' => 'حالة البيانات', 'plinth_note' => 'الوزرة بلاستيك مشتراة بطول 3000 مم وليست ألواحاً', 'drawer_board' => 'لوح صندوق الدرج', 'see_s08' => 'جميع نقاط الخدمات مع X و Z والحالة: انظر جدول الخدمات S-08.', 'detail_note' => 'الأبعاد: من الحافة اليسرى للوحدة ومن قاع الوحدة؛ X من المرجع و Z ارتفاع فوق الأرضية', 'stack' => 'وحدة طويلة مركبة', 'lower_mod' => 'الوحدة السفلية', 'upper_mod' => 'الوحدة العلوية',
        'joint' => 'وصلة الهيكل', 'assembly' => 'التجميع', 'front_zone' => 'منطقة الواجهة', 'hinge_zone' => 'منطقة المفصلات', 'drawer_zone' => 'منطقة الدرج والمجرى', 'cutout' => 'فتحة الرخام',
        'lift' => 'مسار واجهة الرفع', 'appliance_opening' => 'فتحة الجهاز', 'filler' => 'حشوة ضيقة', 'custom' => 'وحدة مخصصة', 'organizer' => 'المنظم الداخلي', 'door_gap' => 'فاصل الواجهة', 'front_thk' => 'واجهة', 'shelf' => 'رف',
        'datum' => 'المرجع', 'ffl' => 'مستوى الأرضية', 'x_dim' => 'X من المرجع', 'z_dim' => 'Z = ارتفاع فوق الأرضية', 'legend' => 'مفتاح الرموز', 'services' => 'الخدمات', 'inferred_note' => 'القيم المستنتجة أو غير المؤكدة يجب التحقق منها في الموقع.'
      }
    }.freeze

    def t(lang, key)
      (TXT[lang] || TXT['en'])[key] || TXT['en'][key] || key
    end

    def esc(s)
      CGI.escapeHTML(s.to_s)
    end

    def fmt(v)
      f = v.to_f
      (f - f.round).abs < 0.05 ? f.round.to_s : f.round(1).to_s
    end

    def scale_label(n0)
      n = n0.to_f
      return "#{(1 / n) % 1 < 0.05 ? (1 / n).round : (1 / n).round(1)}:1" if n < 1.0

      n = n.to_f
      n == 1.0 ? '1:1' : "1:#{(n % 1).zero? ? n.to_i : n}"
    end

    # largest scale (smallest N) at which a (w x h) model extent fits the (aw x ah) sheet cell
    def pick_scale(w, h, aw, ah, list = STD_SCALES)
      list.find { |n| w / n <= aw && h / n <= ah } || list.last
    end

    # approximate rendered text width in sheet mm
    def tw(str, size)
      s = str.to_s
      s.each_char.sum { |c| c.ord > 0x600 ? 0.55 : (c =~ /[A-Z0-9]/ ? 0.62 : 0.52) } * size
    end

    # wrap a text into lines that fit maxw (mm); nothing is ever cut
    def wrap(str, size, maxw)
      lines = []
      cur = +''
      str.to_s.split(' ').each do |wd|
        trial = cur.empty? ? wd : "#{cur} #{wd}"
        if tw(trial, size) > maxw && !cur.empty?
          lines << cur
          cur = wd.dup
        else
          cur = trial
        end
      end
      lines << cur unless cur.empty?
      lines
    end

    # rows of [text, color] -> same rows with long texts wrapped onto continuation rows
    def wrap_rows(rows, size, maxw)
      rows.flat_map { |txt, col| wrap(txt, size, maxw).each_with_index.map { |l, i| [i.zero? ? l : "  #{l}", col] } }
    end

    def fit_text(str, size, maxw)
      s = str.to_s
      return s if tw(s, size) <= maxw

      s = s[0, [s.length - 1, 1].max] while s.length > 1 && tw("#{s}.", size) > maxw
      "#{s}."
    end

    # --------------------------------------------------------------------------------------------------------------------- Sheet
    class Sheet
      attr_reader :lang, :rtl, :no, :title, :body, :table_bottom

      def initialize(proj, lang:, no:, title:, scale: nil, status: 'DRAFT', zone: '', rev: nil)
        @proj = (proj || {}).dup
        @proj['name'] = (Sketchup.active_model.title rescue '') if @proj['name'].to_s.empty?
        @proj['name'] = '-' if @proj['name'].to_s.empty?
        @lang = lang
        @rtl = lang == 'ar'
        @no = no
        @title = title
        @scale = scale
        @status = status
        @zone = zone
        @rev = rev || @proj['rev'] || 'A'
        @body = +''
        @clip = 0
      end

      def tr(key)
        ExecDraw.t(@lang, key)
      end

      # usable drawing area (inside the frame, above the title block)
      def area
        [FRAME + 2, FRAME + 2, PW - FRAME - 2, PH - FRAME - TB_H - 2]
      end

      def raw(s)
        @body << s
      end

      def line(x1, y1, x2, y2, w: 0.18, dash: nil, color: '#111')
        @body << "<line x1='#{r(x1)}' y1='#{r(y1)}' x2='#{r(x2)}' y2='#{r(y2)}' stroke='#{color}' stroke-width='#{w}'#{dash ? " stroke-dasharray='#{dash}'" : ''}/>"
      end

      def rect(x, y, w, h, fill: 'none', stroke: '#111', sw: 0.18, dash: nil, op: nil)
        @body << "<rect x='#{r(x)}' y='#{r(y)}' width='#{r(w)}' height='#{r(h)}' fill='#{fill}' stroke='#{stroke}' stroke-width='#{sw}'#{dash ? " stroke-dasharray='#{dash}'" : ''}#{op ? " fill-opacity='#{op}'" : ''}/>"
      end

      def poly(pts, fill: 'none', stroke: '#111', sw: 0.18, close: true, dash: nil)
        d = pts.map { |x, y| "#{r(x)},#{r(y)}" }.join(' ')
        @body << "<#{close ? 'polygon' : 'polyline'} points='#{d}' fill='#{fill}' stroke='#{stroke}' stroke-width='#{sw}' stroke-linejoin='round'#{dash ? " stroke-dasharray='#{dash}'" : ''}/>"
      end

      def circle(cx, cy, rad, fill: 'none', stroke: '#111', sw: 0.18, dash: nil)
        @body << "<circle cx='#{r(cx)}' cy='#{r(cy)}' r='#{r(rad)}' fill='#{fill}' stroke='#{stroke}' stroke-width='#{sw}'#{dash ? " stroke-dasharray='#{dash}'" : ''}/>"
      end

      # a raster picture (PNG bytes) inside the box x / y / w / h, kept in proportion
      def image(x, y, w, h, png)
        @body << "<image x='#{r(x)}' y='#{r(y)}' width='#{r(w)}' height='#{r(h)}' preserveAspectRatio='xMidYMid meet' href='data:image/png;base64,#{[png].pack('m0')}'/>"
      end

      def hatch(x, y, w, h, stroke: '#111', sw: 0.18)
        @body << "<rect x='#{r(x)}' y='#{r(y)}' width='#{r(w)}' height='#{r(h)}' fill='url(#hatch)' stroke='#{stroke}' stroke-width='#{sw}'/>"
      end

      # anchors are LOGICAL for text: :left = reading start, :right = reading end (mirrored by direction=rtl on Arabic sheets);
      # :pleft / :pright are PHYSICAL (x is the left / right edge). ltr: true keeps numbers / codes in LTR on Arabic sheets.
      def text(x, y, str, size: 3.0, anchor: :left, bold: false, rot: 0, color: '#111', italic: false, ltr: false)
        return if str.nil? || str.to_s.empty?

        rtl_mode = @rtl && !ltr
        # Latin / numeric strings (codes, 600 x 900 x 600) keep their own LTR order inside an RTL line
        str = "‪#{str}‬" if rtl_mode && str.to_s !~ /\p{Arabic}/
        a = case anchor
            when :center then 'middle'
            when :right then 'end'
            when :pleft then (rtl_mode ? 'end' : 'start')
            when :pright then (rtl_mode ? 'start' : 'end')
            else 'start'
            end
        track_text(x, y, str.to_s, size, a, rtl_mode, rot)
        tf = rot.zero? ? '' : " transform='rotate(#{-rot} #{r(x)} #{r(y)})'"
        dir = rtl_mode ? " direction='rtl' unicode-bidi='embed'" : ''
        @body << "<text x='#{r(x)}' y='#{r(y)}' font-size='#{size}' text-anchor='#{a}' fill='#{color}'#{bold ? " font-weight='700'" : ''}#{italic ? " font-style='italic'" : ''}#{tf}#{dir}>#{ExecDraw.esc(str)}</text>"
      end

      # ---- drawing lint: approximate text boxes -> out-of-frame text and text-over-text overlaps (used by the PDF QA loop)
      def track_text(x, y, str, size, anchor, rtl_mode, rot)
        w = ExecDraw.tw(str, size)
        x0, x1 = case anchor
                 when 'middle' then [x - w / 2.0, x + w / 2.0]
                 when 'end' then rtl_mode ? [x, x + w] : [x - w, x]
                 else rtl_mode ? [x - w, x] : [x, x + w]
                 end
        box = if rot.zero?
                [x0, y - size * 0.8, x1, y + size * 0.2]
              else
                ya, yb = case anchor
                         when 'middle' then [y - w / 2.0, y + w / 2.0]
                         when 'end' then [y, y + w]
                         else [y - w, y]
                         end
                [x - size * 0.8, ya, x + size * 0.2, yb]
              end
        (@boxes ||= []) << box + [str]
      end

      # => { out_of_frame: [strings], overlaps: [[a,b]...] }
      def truncated
        @truncated ||= []
      end

      def lint
        boxes = @boxes || []
        out = boxes.select { |b| b[0] < FRAME - 0.5 || b[2] > PW - FRAME + 0.5 || b[1] < FRAME - 0.5 || b[3] > PH - FRAME + 0.5 }.map { |b| "#{b[4]} @ #{b[0].round(1)},#{b[1].round(1)}..#{b[2].round(1)},#{b[3].round(1)}" }
        ov = []
        boxes.each_with_index do |a, i|
          boxes.each_with_index do |b, j|
            next if j <= i

            ix = [a[2], b[2]].min - [a[0], b[0]].max
            iy = [a[3], b[3]].min - [a[1], b[1]].max
            next unless ix > 0.6 && iy > 0.8

            ov << [a[4], b[4]] if ix * iy > 0.25 * [(a[2] - a[0]) * (a[3] - a[1]), (b[2] - b[0]) * (b[3] - b[1])].min
          end
        end
        { out_of_frame: out, overlaps: ov, truncated: truncated }
      end

      def clip_begin(x, y, w, h)
        @clip += 1
        id = "c#{@no.to_s.gsub(/\W/, '')}#{@clip}"
        @body << "<clipPath id='#{id}'><rect x='#{r(x)}' y='#{r(y)}' width='#{r(w)}' height='#{r(h)}'/></clipPath><g clip-path='url(##{id})'>"
      end

      def clip_end
        @body << '</g>'
      end

      # ---- dimensions: extension lines + dimension line with 45 degree ticks + centred text. level 1 = outermost
      def dim_h(x1, x2, y_line, label, from_y: nil, size: 2.7, color: '#8a1c12')
        return if (x2 - x1).abs < 0.4

        line(x1, from_y, x1, y_line + (y_line > from_y ? 1.2 : -1.2), w: 0.1, color: color) if from_y
        line(x2, from_y, x2, y_line + (y_line > from_y ? 1.2 : -1.2), w: 0.1, color: color) if from_y
        line(x1, y_line, x2, y_line, w: 0.13, color: color)
        [x1, x2].each { |px| line(px - 0.8, y_line + 0.8, px + 0.8, y_line - 0.8, w: 0.25, color: color) }
        lab = label.to_s
        if ExecDraw.tw(lab, size) <= (x2 - x1).abs - 0.6
          text((x1 + x2) / 2.0, y_line - 0.8, lab, size: size, anchor: :center, color: color, ltr: true)
        else
          if x2 + 1.2 + ExecDraw.tw(lab, size) > PW - FRAME - 0.8 # no room on the right: label on the left of the dimension
            text(x1 - 1.2, y_line - 0.8, lab, size: size, anchor: :pright, color: color, ltr: true)
          else
            text(x2 + 1.2, y_line - 0.8, lab, size: size, anchor: :pleft, color: color, ltr: true) # narrow span: label beside the dimension, never over geometry
          end
        end
      end

      def dim_v(y1, y2, x_line, label, from_x: nil, size: 2.7, color: '#8a1c12', side: :left)
        return if (y2 - y1).abs < 0.4

        line(from_x, y1, x_line + (x_line > from_x ? 1.2 : -1.2), y1, w: 0.1, color: color) if from_x
        line(from_x, y2, x_line + (x_line > from_x ? 1.2 : -1.2), y2, w: 0.1, color: color) if from_x
        line(x_line, y1, x_line, y2, w: 0.13, color: color)
        [y1, y2].each { |py| line(x_line - 0.8, py + 0.8, x_line + 0.8, py - 0.8, w: 0.25, color: color) }
        lab = label.to_s
        tx = side == :left ? x_line - 0.9 : x_line + 2.2
        if ExecDraw.tw(lab, size) <= (y2 - y1).abs - 0.6
          text(tx, (y1 + y2) / 2.0 + size * 0.35, lab, size: size, anchor: :center, rot: 90, color: color, ltr: true)
        else
          text(tx, y2 + 1.0 + ExecDraw.tw(lab, size), lab, size: size, anchor: :pleft, rot: 90, color: color, ltr: true)
        end
      end

      # ---- title block (bottom of the frame). English: left to right. Arabic: mirrored.
      def title_block
        x0 = FRAME
        y0 = PH - FRAME - TB_H
        w = PW - 2 * FRAME
        rect(x0, y0, w, TB_H, sw: 0.5)
        row1 = [['brand', 48, ExecDraw.t('en', 'brand'), true], ['project', 80, @proj['name'].to_s, false], ['client', 62, @proj['client'].to_s, false], ['title', 210, @title, true]]
        row2 = [['sheet', 52, @no, true], ['rev', 28, @rev.to_s, false], ['date', 40, Time.now.strftime('%Y-%m-%d'), false],
                ['scale', 44, @scale || tr('nts'), false], ['status', 64, status_text, false], ['language', 40, tr('lang_name'), false], ['zone', 132, @zone.to_s, false]]
        [[row1, y0], [row2, y0 + TB_H / 2.0]].each do |cells, yy|
          tot = cells.sum { |c| c[1] }
          x = @rtl ? x0 + w : x0
          cells.each do |key, cw, val, bold|
            cx = @rtl ? x - cw : x
            rect(cx, yy, cw, TB_H / 2.0, sw: 0.25)
            lab = key == 'brand' ? '' : tr(key)
            ax = @rtl ? cx + cw - 1.5 : cx + 1.5
            text(ax, yy + 3.2, lab, size: 2.0, anchor: :left, color: '#666') unless lab.empty?
            big = key == 'brand' ? 4.6 : (key == 'title' ? 4.4 : 3.5)
            maxw = cw - 3
            text(ax, yy + (key == 'brand' ? 10.4 : 11.2), ExecDraw.fit_text(val, big, maxw), size: big, anchor: :left, bold: bold)
            x = @rtl ? cx : cx + cw
          end
          _ = tot
        end
      end

      def status_text
        s = @status.to_s
        @rtl ? (s == 'DRAFT' ? tr('draft') : s) : s
      end

      def to_svg
        defs = "<defs><pattern id='hatch' width='1.6' height='1.6' patternUnits='userSpaceOnUse' patternTransform='rotate(45)'><line x1='0' y1='0' x2='0' y2='1.6' stroke='#444' stroke-width='0.15'/></pattern></defs>"
        frame = "<rect x='#{FRAME}' y='#{FRAME}' width='#{PW - 2 * FRAME}' height='#{PH - 2 * FRAME}' fill='none' stroke='#111' stroke-width='0.7'/>"
        saved = @body
        @body = +''
        title_block
        tb = @body
        @body = saved
        "<section class='ps' data-sheet='#{ExecDraw.esc(@no)}'><svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 #{PW} #{PH}' width='#{PW}mm' height='#{PH}mm' font-family='#{FONT}' style='background:#fff'>#{defs}#{frame}#{@body}#{tb}</svg></section>"
      end

      private

      def r(v)
        v.to_f.round(2)
      end
    end

    # --------------------------------------------------------------------------------------------------------------------- mapping
    # model (a,b) mm -> sheet mm. kind :elev (b up) or :plan (b down). `k` = sheet mm per model mm (1/N).
    Map = Struct.new(:ox, :oy, :k, :kind) do
      def x(a)
        ox + a * k
      end

      def y(b)
        kind == :plan ? oy + b * k : oy - b * k
      end

      def len(v)
        v * k
      end
    end

    # --------------------------------------------------------------------------------------------------------------------- tables
    # Schedule table sheet(s): headers, rows, column widths in mm (sum ~ 396). Returns array of Sheet (paginated).
    def table_sheets(proj, lang, no, title, headers, rows, widths, per_page: 36, notes: [], status: 'DRAFT')
      rows = [[t(lang, 'notes_col') == '' ? '-' : '(none)'] + [''] * (headers.size - 1)] if rows.empty?
      pages = rows.each_slice(per_page).to_a
      pages.each_with_index.map do |chunk, i|
        n = pages.size > 1 ? "#{no}-#{i + 1}" : no
        ttl = pages.size > 1 ? "#{title} (#{i + 1}/#{pages.size})" : title
        s = Sheet.new(proj, lang: lang, no: n, title: ttl, status: status)
        x0, y0, x1, = s.area
        total = widths.sum
        ws = widths.map { |w| w * (x1 - x0) / total }
        rh = 5.6
        fs = 2.9
        cols = s.rtl ? ws.reverse : ws
        hs = s.rtl ? headers.reverse : headers
        draw_row = lambda do |vals, y, head|
          vals = s.rtl ? vals.reverse : vals
          x = x0
          s.rect(x0, y, x1 - x0, rh, fill: head ? '#e9e4d3' : 'none', sw: 0.15, stroke: '#888')
          vals.each_with_index do |v, ci|
            cw = cols[ci]
            s.line(x, y, x, y + rh, w: 0.1, color: '#aaa') if ci.positive?
            tx = s.rtl ? x + cw - 1.2 : x + 1.2
            shown = fit_text(v.to_s, fs, cw - 2.4)
            s.truncated << v.to_s if shown != v.to_s && !head # a table cell that does not fit is a lint defect (ids must never be cut)
            s.text(tx, y + rh - 1.7, shown, size: fs, bold: head, anchor: :left)
            x += cw
          end
        end
        y = y0 + 2
        draw_row.call(headers, y, true)
        chunk.each_with_index { |row, ri| draw_row.call(row, y + rh * (ri + 1), false) }
        yy = y + rh * (chunk.size + 1) + 5
        notes.each_with_index { |n2, ni| s.text(s.rtl ? x1 : x0, yy + ni * 4.5, n2, size: 2.8, color: '#444', anchor: :left) }
        _ = hs
        s.instance_variable_set(:@table_bottom, yy + notes.size * 4.5)
        s
      end
    end

    # per-sheet lint summary (text outside the frame, text-over-text overlaps) - evidence for the PDF QA loop
    def lint_report(sheets)
      sheets.map do |s|
        l = s.lint
        { 'sheet' => s.no, 'title' => s.title, 'out_of_frame' => l[:out_of_frame].size, 'overlaps' => l[:overlaps].size, 'truncated' => l[:truncated].size, 'examples' => l[:overlaps].first(3).map { |a, b| "#{a} | #{b}" } + l[:out_of_frame].first(2) + l[:truncated].first(2).map { |t| "CUT: #{t}" } }
      end
    end

    def html_page(sheets, title: 'E.G.C', lang: 'en')
      css = "@page{size:#{PW}mm #{PH}mm;margin:0}*{box-sizing:border-box}html,body{margin:0;padding:0;background:#fff}.ps{width:#{PW}mm;height:#{PH}mm;overflow:hidden;position:relative;page-break-after:always;break-after:page}.ps svg{display:block;width:#{PW}mm;height:#{PH}mm}.ps:last-child{page-break-after:auto;break-after:auto}"
      "<!doctype html><html lang='#{lang}' dir='#{lang == 'ar' ? 'rtl' : 'ltr'}'><head><meta charset='utf-8'><title>#{esc(title)}</title><style>#{css}</style></head><body>#{sheets.map(&:to_svg).join}</body></html>"
    end
  end
end
