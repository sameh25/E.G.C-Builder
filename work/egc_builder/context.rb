# frozen_string_literal: true

module EGC
  # Right-click actions on E.G.C units + a few global menu commands.
  module Context
    module_function

    def model
      Sketchup.active_model
    end

    def units(sel = model.selection)
      sel.grep(Sketchup::Group).select { |g| g.get_attribute('egc', 'spec') || g.get_attribute('egc', 'wardrobe') || g.get_attribute('egc', 'kitchen') }
    end

    def cfg
      Config.build(Config.saved)
    end

    # open/close every mechanism in the selection (toggle)
    def toggle_open(sel = model.selection)
      sel = sel.to_a
      moving = Mechanisms.collect(sel)
      return if moving.empty?

      Animator.toggle(sel)
    end

    def toggle_explode(sel = model.selection)
      sel = sel.to_a
      parts = ViewTools.collect_ex(sel)
      return if parts.empty?

      on = parts.first.get_attribute('egc', 'exploded') == true
      EGC.safe_op(model, 'E.G.C explode') do
        ViewTools.explode(sel, on ? 0.0 : 1.0, 320)
        parts.each { |g| g.set_attribute('egc', 'exploded', !on) }
      end
    end

    # independent rebuilt copy placed next to the original (along its local X)
    def duplicate(g)
      spec = Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))
      spec[:code] = nil
      spec[:name] = "#{spec[:name]}_copy"
      EGC.safe_op(model, 'E.G.C duplicate') do
        ng = Cabinet.build(g.parent.entities, spec, cfg)
        ng.transform!(g.transformation * Geom::Transformation.translation(Geom::Vector3d.new(Geo.mm(spec[:w].to_f + 4), 0, 0)))
        Numbering.apply(model) # the copy gets its own permanent U-ID
        model.selection.clear
        model.selection.add(ng)
        ng
      end
    end

    def mirror(g)
      spec = Cabinet.spec_from_json(g.get_attribute('egc', 'spec'))
      Kitchen.rebuild_cabinet(g, { 'hand' => spec[:hand].to_s == 'R' ? 'L' : 'R' }, cfg)
    end

    def drawing(sel)
      html = Drawings.html(sel, cfg, App.lang)
      App.save_and_open(html, 'shop_drawings')
    end

    # the kitchen style of the settings on the selected units (same command as the window button)
    def apply_style(sel = model.selection)
      App.__send__(:do_apply_kstyle, { 'cfg' => Config.saved, 'no_save' => true, 'scope' => 'selected' })
    end

    # part cards / stickers with QR for the selected units, shown before saving
    def part_cards
      App.__send__(:do_production, { 'cfg' => Config.saved, 'no_save' => true, 'kind' => 'labels', 'scope' => 'selection', 'lang' => App.lang })
    rescue StandardError => e
      ::UI.messagebox("E.G.C Builder:\n#{e.message}")
    end

    def interference(sel = model.selection)
      list = sel.grep(Sketchup::Group).select { |g| g.get_attribute('egc', 'spec') }
      res = Interference.check(list.empty? ? nil : list)
      ::UI.messagebox(Interference.report(res, App.lang))
      res
    end

    # Right-click > E.G.C Builder > register for production: any hand-modelled
    # board / unit gets the same production attributes as a built part, so the
    # cut list / nesting / quote read the real model, not only generated units.
    def register_prod(sel = model.selection)
      done = []
      EGC.safe_op(model, 'Register for production') do
        sel.grep(Sketchup::Group).each do |g|
          next if g.get_attribute('egc', 'spec') || g.get_attribute('egc', 'role') == 'part'

          Cutlist.register_manual!(g)
          done << g
        end
      end
      ::UI.messagebox("#{done.size} part(s) registered for production. | تم تسجيل #{done.size} قطعة للإنتاج.") if done.any?
      done
    end

    def build_menu(menu)
      sel = model.selection
      return if units(sel).empty?

      sub = menu.add_submenu('E.G.C Builder')
      sub.add_item(I18n.t('ctx_open', App.lang)) { toggle_open }
      sub.add_item(I18n.t('ctx_explode', App.lang)) { toggle_explode }
      one = units(sel).select { |g| g.get_attribute('egc', 'spec') }
      if one.size == 1
        sub.add_item(I18n.t('ctx_edit', App.lang)) { App.show }
        sub.add_item(I18n.t('ctx_resize', App.lang)) { model.select_tool(ResizeTool.new(one.first, cfg)) }
        sub.add_item(I18n.t('ctx_dup', App.lang)) { duplicate(one.first) }
        sub.add_item(I18n.t('ctx_mirror', App.lang)) { mirror(one.first) }
        sub.add_item(I18n.t('ctx_register_prod', App.lang)) { register_prod }
      end
      sub.add_item(I18n.t('ctx_iso', App.lang)) { ViewTools.isolate(model.selection) }
      sub.add_item(I18n.t('ctx_show', App.lang)) { ViewTools.show_everything }
      sub.add_item(I18n.t('ctx_draw', App.lang)) { drawing(units(model.selection)) }
      sub.add_item(I18n.t('menu_cutlist', App.lang)) { EGC.quick_report }
      sub.add_separator
      sub.add_item(I18n.t('ctx_style', App.lang)) { apply_style }
      sub.add_item(I18n.t('ctx_cards', App.lang)) { part_cards }
      sub.add_item(I18n.t('ctx_clash', App.lang)) { interference }
    end
  end
end
