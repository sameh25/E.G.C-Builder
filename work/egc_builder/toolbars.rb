# frozen_string_literal: true

module EGC
  # Second toolbar (Production) and extra main-toolbar commands. Every button runs the same
  # callback/subsystem the dialog uses - no parallel implementation.
  module App
    class << self
      def goto_tab(tab, focus: nil)
        was_open = @dlg && @dlg.visible?
        show
        go = -> { send({ 'type' => 'goto', 'tab' => tab, 'focus' => focus }) }
        was_open ? go.call : ::UI.start_timer(0.6, false) { go.call }
      end

      def toolbar_package(kind)
        guard("Production: toolbar #{kind}") do
          if Sketchup.active_model.nil? || ProductionPackages.unit_groups(Sketchup.active_model).empty?
            ::UI.messagebox(lang == 'ar' ? 'لا توجد وحدات E.G.C في الموديل. أنشئ مطبخاً أو وحدة أولاً.' : 'No E.G.C units in the model. Generate a kitchen or insert a unit first.')
            next
          end
          do_package({ 'cfg' => Config.saved, 'no_save' => true, 'lang' => lang }, kind)
        end
      end

      # open / close everything that moves: the selected units, or every unit of the model when nothing is selected
      def toolbar_open_all
        model = Sketchup.active_model
        sel = model.selection.grep(Sketchup::Group).select { |g| g.get_attribute('egc', 'spec') || g.get_attribute('egc', 'wardrobe') || g.get_attribute('egc', 'device') || g.get_attribute('egc', 'opening') }
        sel = ProductionPackages.unit_groups(model) if sel.empty?
        return ::UI.messagebox(lang == 'ar' ? 'لا توجد وحدات E.G.C في الموديل.' : 'No E.G.C units in the model.') if sel.empty?

        Animator.toggle(sel)
      end

      def toolbar_ghost
        do_ghost(@ghost_prev.nil?)
        Sketchup.active_model.active_view.invalidate
      end

      def ghost_on?
        !@ghost_prev.nil?
      end

      def toolbar_license
        show
        ::UI.start_timer(0.7, false) { send({ 'type' => 'license', 'status' => License.status, 'enforce' => License::ENFORCE, 'open' => true }) }
      end

      def toolbar_edit(focus)
        g = Sketchup.active_model.selection.grep(Sketchup::Group).find { |x| x.get_attribute('egc', 'spec') }
        unless g
          ::UI.messagebox(I18n.t('select_any', lang))
          return
        end
        open_unit_editor(g, focus: focus)
      end
    end
  end

  unless file_loaded?(__FILE__)
    defs = {
      prod: ['Production', 'Production panel - client / factory / site / machine outputs', 'الإنتاج - مخرجات العميل والمصنع والموقع والماكينة', 'production', -> { App.goto_tab('prod') }],
      factory: ['Factory Shop Drawings', 'Factory shop drawings (PDF) - general arrangement, unit sheets, schedules', 'رسومات التصنيع للمصنع (PDF)', 'factory', -> { App.toolbar_package('factory') }],
      site: ['Site Shop Drawings', 'Site / civil-MEP execution drawings (PDF)', 'رسومات التنفيذ في الموقع (PDF)', 'site', -> { App.toolbar_package('site') }],
      quote: ['Client Quotation', 'Client quotation - opens the Production panel', 'عرض سعر العميل - يفتح لوحة الإنتاج', 'quote', -> { App.goto_tab('prod') }],
      complete: ['Complete Package', 'Complete project package (client + factory + site + machine data)', 'حزمة المشروع الكاملة', 'package', -> { App.toolbar_package('complete') }],
      edit: ['Edit Unit', 'Edit the selected unit', 'تعديل الوحدة المحددة', 'edit', -> { App.toolbar_edit(nil) }],
      replace: ['Replace Unit', 'Replace the selected unit with another type', 'استبدال الوحدة المحددة', 'replace', -> { App.toolbar_edit('replace') }],
      organizer: ['Internal Organizer', 'Internal Organizer of the selected unit', 'المنظم الداخلي للوحدة المحددة', 'organizer', -> { App.toolbar_edit('desInfo') }],
      ai: ['AI Design Assistant', 'AI Design Assistant - dimensions / description / image to proposals', 'مساعد التصميم الذكي', 'assistant', -> { App.goto_tab('kitchen') }]
    }
    defs.merge!(
      beside: ['Add Unit Beside', 'Add a unit beside the selected one - pick which one in the library', 'إضافة وحدة جنب الوحدة المحددة - اختارها من المكتبة', 'beside', -> { App.start_beside(nil, :right) }],
      space: ['Space Tool', 'Space tool - click a free space inside a unit, then fill it (shelf, drawers, door, rail)', 'أداة الفراغ - حدّد فراغ جوّه الوحدة واملأه (رف، أدراج، ضلفة، ماسورة)', 'space', -> { Sketchup.active_model.select_tool(SpaceTool.new) }],
      openall: ['Open / Close All', 'Open / close all doors and drawers (selection, or the whole model)', 'فتح / قفل كل الضلف والأدراج (المحدد أو كل الموديل)', 'openall', -> { App.toolbar_open_all }],
      clash: ['Check Interference', 'Check interference between units, closed and on the way open', 'فحص التداخل بين الوحدات وهي مقفولة وهي بتفتح', 'clash', -> { Context.interference }],
      xray: ['See-through', 'See-through view on / off (to watch a mechanism move)', 'عرض شفاف تشغيل / إيقاف (لمتابعة حركة الميكانيزم)', 'xray', -> { App.toolbar_ghost }],
      door: ['Doors and Windows', 'Doors and windows - in a wall, or standing on their own', 'الأبواب والشبابيك - في حائط أو واقفة لوحدها', 'door', -> { App.goto_tab('units', focus: 'opIns') }],
      mech: ['Mechanisms', 'Mechanisms library', 'مكتبة الميكانيزمات', 'mech', -> { App.goto_tab('mech') }],
      appliance: ['Appliances', 'Appliances library', 'مكتبة الأجهزة', 'appliance', -> { App.goto_tab('app') }],
      license: ['Licence', 'Licence / activation key', 'الترخيص / مفتاح التفعيل', 'key', -> { App.toolbar_license }]
    )
    cmds = {}
    defs.each do |k, (name, en, ar, icon_name, blk)|
      c = ::UI::Command.new(name) { blk.call }
      c.tooltip = "#{en}  |  #{ar}"
      c.status_bar_text = en
      c.small_icon = c.large_icon = icon(icon_name)
      cmds[k] = c
    end
    sub = ::UI.menu('Extensions').add_submenu("#{PLUGIN_NAME} - Production")
    %i[prod factory site quote complete].each { |k| sub.add_item(cmds[k]) }
    ed = ::UI.menu('Extensions').add_submenu("#{PLUGIN_NAME} - Edit")
    %i[edit replace beside organizer ai].each { |k| ed.add_item(cmds[k]) }
    t2 = ::UI::Toolbar.new("#{PLUGIN_NAME} Production")
    %i[prod factory site quote complete].each { |k| t2.add_item(cmds[k]) }
    t2.restore
    t3 = ::UI::Toolbar.new("#{PLUGIN_NAME} Edit")
    %i[edit replace beside organizer ai].each { |k| t3.add_item(cmds[k]) }
    t3.restore
    cmds[:xray].set_validation_proc { App.ghost_on? ? MF_CHECKED : MF_UNCHECKED }
    tools = %i[space openall clash xray door mech appliance license]
    tm = ::UI.menu('Extensions').add_submenu("#{PLUGIN_NAME} - Tools")
    tools.each { |k| tm.add_item(cmds[k]) }
    t4 = ::UI::Toolbar.new("#{PLUGIN_NAME} Tools")
    tools.each { |k| t4.add_item(cmds[k]) }
    t4.restore
    t4.show if t4.get_last_state == TB_NEVER_SHOWN
    file_loaded(__FILE__)
  end
end
