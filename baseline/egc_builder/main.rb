# frozen_string_literal: true

require 'sketchup.rb'
require 'json'

module EGC
  DIR = File.dirname(__FILE__)
end

%w[num i18n config appliance_clearances diag geo appliances appliances_v2 appliances_v3 appliances_v16 cabinet tall_stack custom_units exec_draw exec_views exec_factory exec_unit exec_stack exec_ga exec_worktop exec_site exec_site2 mechanisms mech_motion mech_parts mech_families mech_family_builders lemans_kin interference mech_catalog2 mech_motion_builders animator corner kitchen wardrobe catalog nesting cutlist cam drill_map qr labels numbering room_dxf room_model room_reader image_local proposals production_model packages render_pack report work_order viewtools
   edit_dialog
   audit quote drawings ui resize_tool radial_menu exposure kitchen_line_tool ui_tools context license
   live_dims motion_tool openings space_tool snap validator assistant assistant_design assistant_options assistant_i18n assistant_validate assistant_vision assistant_edit client_shot svgdraw pdf_export preview costing site_docs site_pack assistant_ui representatives hardware_revision row_edit civil phase1_docs production_packages].each { |f| Sketchup.require(File.join(EGC::DIR, f)) } # Sketchup.require: also loads the files when the package is encrypted (.rbe)

module EGC
  def self.icon(name)
    File.join(DIR, 'icons', "#{name}.svg")
  end

  # Wraps a model edit in exactly one undo step and guarantees the operation is always either
  # committed or aborted - a start_operation left open by a mid-way exception (no matching
  # commit_operation/abort_operation) corrupts the undo stack for the rest of the session.
  def self.safe_op(model, name)
    model.start_operation(name, true)
    result = yield
    model.commit_operation
    result
  rescue StandardError
    model.abort_operation
    raise
  end

  # Live Dimensions overlay is per-model - re-attach it to every model the user opens/creates.
  class LiveDimsAppObserver < ::Sketchup::AppObserver
    def onNewModel(model); LiveDims.sync(model); end
    def onOpenModel(model); LiveDims.sync(model); end
  end

# Factory work order for the selection (or the whole model): shown in the preview window first, saved from there
def self.work_order
  cfg = Config.build(Config.saved)
  l = App.lang
  res = Cutlist.analyse(cfg, Sketchup.active_model, use_selection: true)
  Cutlist.guard_exports!(res)
  base = Sketchup.active_model.title.to_s
  base = 'EGC_Kitchen' if base.empty?
  Preview.document(WorkOrder.html(res, cfg, l, base), "#{base}_work_order.html", title: l == 'ar' ? 'أمر تشغيل للمصنع' : 'Factory work order', lang: l)
rescue StandardError => e
  ::UI.messagebox("E.G.C Builder:\n#{e.message}")
end

def self.quick_report
    cfg = Config.build(Config.saved)
    l = App.lang
    res = Cutlist.analyse(cfg, Sketchup.active_model, use_selection: true)
    begin
      Cutlist.guard_exports!(res)
    rescue Cutlist::IntegrityError => e
      ::UI.messagebox(e.message)
      return
    end
    if res[:rows].empty?
      ::UI.messagebox(I18n.t('nothing', l))
      return
    end
    base = Sketchup.active_model.title.to_s
    base = 'EGC_Kitchen' if base.empty?
    path = File.join(Dir.tmpdir, "#{base}_egc_report.html")
    File.binwrite(path, Report.html(res, l, base).encode('UTF-8'))
    ::UI.openURL("file:///#{path.tr('\\', '/')}")
  end

  unless file_loaded?(__FILE__)
    cmd_open = ::UI::Command.new(PLUGIN_NAME) { App.show }
    cmd_open.tooltip = 'E.G.C Builder'
    cmd_open.status_bar_text = 'Open E.G.C Builder — kitchen & cabinet designer'
    cmd_open.small_icon = cmd_open.large_icon = icon('main')

    cmd_report = ::UI::Command.new('Cut list') { quick_report }
    cmd_report.tooltip = 'Cut list & report (selection or whole model)'
    cmd_report.small_icon = cmd_report.large_icon = icon('cutlist')

    cmd_unit = ::UI::Command.new('Edit Unit') { EditDialog.show }
    cmd_unit.tooltip = 'Dedicated numeric editor for the selected E.G.C unit'
    cmd_unit.status_bar_text = 'Edit the selected unit by typed dimensions (W / H / D)'
    cmd_unit.small_icon = cmd_unit.large_icon = icon('unit')

    # Dedicated kitchen-edit entry point: keeps whole-kitchen editing separate from the
    # numeric single-unit editor instead of forcing both workflows into the Units panel.
    cmd_kitchen_edit = ::UI::Command.new('Edit Kitchen') do
      App.show
      ::UI.start_timer(0.30, false) { App.send({ 'type' => 'goto', 'tab' => 'kitchen' }) }
    end
    cmd_kitchen_edit.tooltip = 'Open the dedicated kitchen editor'
    cmd_kitchen_edit.status_bar_text = 'Edit the kitchen layout, runs, styles and kitchen-wide settings'
    cmd_kitchen_edit.small_icon = cmd_kitchen_edit.large_icon = icon('main')

    cmd_radial = ::UI::Command.new('Quick Menu') { Sketchup.active_model.select_tool(RadialMenuTool.new) }
    cmd_radial.tooltip = 'Quick action menu - click a unit, move to a slice, click to run it. ' \
                          '"More" holds rotate / add left-right / snap.'
    cmd_radial.small_icon = cmd_radial.large_icon = icon('radial')

    cmd_kline = ::UI::Command.new('Kitchen Run Line') do
      model = Sketchup.active_model
      Sketchup.active_model.select_tool(KitchenLineTool.new(Config.for_project(Config.build(Config.saved), model)))
    end
    cmd_kline.tooltip = 'Kitchen Run Line / Polyline - draw the kitchen path in the model'
    cmd_kline.status_bar_text = 'Click points to draw a kitchen run; Enter or double-click to finish'
    cmd_kline.small_icon = cmd_kline.large_icon = icon('kline')

    cmd_resize = ::UI::Command.new('Live Resize') do
      g = Sketchup.active_model.selection.grep(Sketchup::Group).find { |x| x.get_attribute('egc', 'spec') }
      if g
        Sketchup.active_model.select_tool(ResizeTool.new(g, Config.for_project(Config.build(Config.saved), Sketchup.active_model)))
      else
        ::UI.messagebox(I18n.t('select_any', App.lang))
      end
    end
    cmd_resize.tooltip = 'Live resize (drag) the selected unit'
    cmd_resize.small_icon = cmd_resize.large_icon = icon('resize')

    cmd_client = ::UI::Command.new('Client View') do
      l = Sketchup.active_model.layers['EGC Hardware']
      ViewTools.client_view(!(l && !l.visible?))
    end
    cmd_client.tooltip = 'Client view (hide hardware)'
    cmd_client.small_icon = cmd_client.large_icon = icon('client')
    cmd_client.set_validation_proc do
      l = Sketchup.active_model.layers['EGC Hardware']
      (l && !l.visible?) ? MF_CHECKED : MF_UNCHECKED
    end

    cmd_explode = ::UI::Command.new('Exploded View') { Context.toggle_explode }
    cmd_explode.tooltip = 'Exploded view on / off (selection, or whole model)'
    cmd_explode.small_icon = cmd_explode.large_icon = icon('explode')

    cmd_audit = ::UI::Command.new('Preflight') do
      cfg = Config.build(Config.saved)
      lang = App.lang
      r = Audit.run(cfg, Sketchup.active_model, use_selection: false)
      msg = if r[:issues].reject { |i| i['code'] == 'empty' }.empty?
              "#{I18n.t('preflight_ok', lang)} (#{r[:parts]})"
            else
              r[:issues].first(14).map { |i| "#{i['level'] == 'error' ? '⛔' : (i['level'] == 'warn' ? '⚠' : 'ℹ')} " \
                "#{Audit.message(i['code'], lang)} — #{i['where']} #{i['detail']}" }.join("\n")
            end
      ::UI.messagebox(msg)
    end
    cmd_audit.tooltip = 'Preflight check (whole model)'
    cmd_audit.small_icon = cmd_audit.large_icon = icon('audit')

    cmd_scenes = ::UI::Command.new('Scenes') { ViewTools.build_scenes }
    cmd_scenes.tooltip = 'Create presentation scenes (perspective, plan, elevations)'
    cmd_scenes.small_icon = cmd_scenes.large_icon = icon('scenes')

    cmd_dims = ::UI::Command.new('Live Dimensions') { LiveDims.toggle }
    cmd_dims.tooltip = 'Live clear dimensions (W x H x D on the selected unit)'
    cmd_dims.small_icon = cmd_dims.large_icon = icon('dims')
    cmd_dims.set_validation_proc { LiveDims.enabled? ? MF_CHECKED : MF_UNCHECKED }

    cmd_motion = ::UI::Command.new('Motion Click') { Sketchup.active_model.select_tool(MotionTool.new) }
    cmd_motion.tooltip = 'Click any unit in the model to open/close it (client walkthrough mode)'
    cmd_motion.small_icon = cmd_motion.large_icon = icon('motion')

    # bilingual tooltips (English | Arabic) - the toolbar shows both, whatever the UI language
    { cmd_open => 'فتح E.G.C Builder - مصمم المطابخ والوحدات', cmd_kitchen_edit => 'تعديل المطبخ بالكامل - التخطيط والصفوف والاستايل والإعدادات', cmd_report => 'قائمة القطع والتقرير (المحدد أو كل الموديل)', cmd_unit => 'تعديل الوحدة المحددة بالمقاس - بدون سحب الماوس',
      cmd_radial => 'قائمة الإجراءات السريعة - اضغط وحدة ثم اختر شريحة. "المزيد" فيها تدوير/إضافة يمين-شمال/سناب',
      cmd_kline => 'خط المطبخ - ارسم مسار المطبخ في الموديل', cmd_resize => 'تحجيم حي للوحدة المحددة (سحب)', cmd_client => 'عرض العميل (إخفاء الهاردوير)',
      cmd_explode => 'العرض المفجّر تشغيل / إيقاف', cmd_audit => 'فحص ما قبل التسليم (كل الموديل)', cmd_scenes => 'إنشاء مشاهد العرض (منظور، مسقط، واجهات)',
      cmd_dims => 'أبعاد حية للوحدة المحددة (عرض × ارتفاع × عمق)', cmd_motion => 'اضغط أي باب أو درج لفتحه/قفله (وضع العرض على العميل)' }.each do |c, ar|
      c.tooltip = "#{c.tooltip}  |  #{ar}"
    end

    # One predictable command map.  Commands themselves are unchanged; only
    # their presentation is grouped so production commands are not mixed with
    # building and quick modelling actions.
    menu = ::UI.menu('Extensions').add_submenu(PLUGIN_NAME)
    build_menu = menu.add_submenu('Build  |  إنشاء')
    build_menu.add_item(cmd_open)
    build_menu.add_item(cmd_kline)
    edit_menu = menu.add_submenu('Edit  |  تعديل')
    edit_menu.add_item(cmd_kitchen_edit)
    edit_menu.add_item(cmd_unit)
    edit_menu.add_item(cmd_resize)
    quick_menu = menu.add_submenu('Quick Actions  |  إجراءات سريعة')
    quick_menu.add_item(cmd_radial)
    quick_menu.add_item(cmd_client)
    quick_menu.add_item(cmd_explode)
    quick_menu.add_item(cmd_dims)
    quick_menu.add_item(cmd_motion)
    prod = menu.add_submenu('Production  |  الإنتاج')
    prod.add_item(cmd_audit)
    prod.add_item(cmd_report)
    prod.add_item(cmd_scenes)
    prod.add_item('Factory work order  |  أمر تشغيل للمصنع') { work_order }
    ::UI.add_context_menu_handler { |m| Context.build_menu(m) }

    # Primary toolbar: only the commands used while designing/editing.
    # Production commands live in their own toolbar so the main bar stays compact.
    tb = ::UI::Toolbar.new(PLUGIN_NAME)
    tb.add_item(cmd_open)
    tb.add_item(cmd_kitchen_edit)
    tb.add_item(cmd_unit)
    tb.add_item(cmd_kline)
    tb.add_item(cmd_radial)
    tb.restore

    tools_tb = ::UI::Toolbar.new(PLUGIN_NAME + ' Tools')
    tools_tb.add_item(cmd_resize)
    tools_tb.add_item(cmd_client)
    tools_tb.add_item(cmd_explode)
    tools_tb.add_item(cmd_dims)
    tools_tb.add_item(cmd_motion)
    tools_tb.restore

    prod_tb = ::UI::Toolbar.new(PLUGIN_NAME + ' Production')
    prod_tb.add_item(cmd_audit)
    prod_tb.add_item(cmd_report)
    prod_tb.add_item(cmd_scenes)
    prod_tb.add_item(::UI::Command.new('Factory Work Order') { work_order })
    prod_tb.restore

    # Attach the Live Dimensions overlay to the model already open when the extension loads.
    begin
      LiveDims.sync(Sketchup.active_model) if Sketchup.active_model
    rescue StandardError
      nil
    end
    ::Sketchup.add_observer(LiveDimsAppObserver.new)

    file_loaded(__FILE__)
  end
end

Sketchup.require(File.join(EGC::DIR, 'toolbars'))

Sketchup.require(File.join(EGC::DIR, 'proto121', 'loader'))
Sketchup.require(File.join(EGC::DIR, 'proto_bridge'))
Sketchup.require(File.join(EGC::DIR, 'p1_basket'))
