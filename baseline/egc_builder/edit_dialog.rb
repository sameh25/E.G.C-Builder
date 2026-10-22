# frozen_string_literal: true

require 'json'

module EGC
  # Dedicated, low-clutter editor for numeric unit changes.
  # This is intentionally separate from the full Units/Library page and from Live Resize.
  module EditDialog
    module_function

    def selected_unit
      Sketchup.active_model.selection.grep(Sketchup::Group).find { |g| g.get_attribute('egc', 'spec') }
    end

    def labels
      ar = App.lang.to_s == 'ar'
      {
        title: ar ? 'تعديل E.G.C' : 'E.G.C Edit',
        unit: ar ? 'تعديل الوحدة المحددة' : 'Edit selected unit',
        kitchen: ar ? 'تعديل المطبخ بالكامل' : 'Edit whole kitchen',
        no_unit: ar ? 'حدد وحدة E.G.C في الموديل أولاً.' : 'Select an E.G.C unit in the model first.',
        type: ar ? 'الوحدة' : 'Unit',
        kind: ar ? 'نوع الوحدة' : 'Unit family',
        width: ar ? 'العرض (مم)' : 'Width (mm)',
        height: ar ? 'الارتفاع (مم)' : 'Height (mm)',
        depth: ar ? 'العمق (مم)' : 'Depth (mm)',
        apply: ar ? 'تنفيذ تعديل الوحدة' : 'Apply unit edit',
        open_kitchen: ar ? 'فتح تعديل المطبخ' : 'Open kitchen editor',
        close: ar ? 'إغلاق' : 'Close',
        live: ar ? 'التعديل الحي بالسحب موجود كأداة منفصلة — لا يستخدم هنا.' : 'Live drag resize is kept as a separate tool — this editor uses typed dimensions.',
        result: ar ? 'تم تنفيذ التعديل.' : 'Edit applied.'
      }
    end

    def html
      l = labels
      <<~HTML
        <!doctype html><html><head><meta charset="utf-8">
        <style>
          *{box-sizing:border-box}body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:#f5f3ef;color:#20242a}
          .wrap{padding:18px}.title{font-size:20px;font-weight:700;margin-bottom:14px}.hint{color:#666;font-size:12px;line-height:1.45}
          .scope{display:flex;gap:8px;margin-bottom:14px}.scope button{flex:1;border:1px solid #c8c3ba;background:#fff;border-radius:8px;padding:10px;font-weight:600;cursor:pointer}
          .scope button.on{background:#2e333a;color:#fff;border-color:#2e333a}.card{background:#fff;border:1px solid #d8d2c8;border-radius:10px;padding:14px;margin-bottom:12px}
          .unitname{font-weight:700;margin-bottom:3px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:12px}
          label{font-size:12px;color:#555}input{width:100%;margin-top:5px;border:1px solid #bbb5aa;border-radius:6px;padding:9px;font-size:15px}
          .actions{display:flex;gap:8px;margin-top:14px}.btn{flex:1;border:1px solid #b9b3a9;background:#fff;border-radius:7px;padding:10px;cursor:pointer;font-weight:600}.pri{background:#d9a441;border-color:#c18e2b;color:#151515}
          .warn{padding:12px;border-radius:8px;background:#fff4d6;border:1px solid #e1c47b}.hidden{display:none}
        </style></head><body><div class="wrap">
        <div class="title">#{l[:title]}</div>
        <div class="scope"><button id="unitTab" class="on">#{l[:unit]}</button><button id="kitchenTab">#{l[:kitchen]}</button></div>
        <div id="unitPane" class="card"></div>
        <div id="kitchenPane" class="card hidden">
          <div class="hint">#{l[:kitchen]}</div>
          <p class="hint">#{l[:live]}</p>
          <div class="actions"><button class="btn pri" id="openKitchen">#{l[:open_kitchen]}</button></div>
        </div>
        <div class="actions"><button class="btn" id="close">#{l[:close]}</button></div>
        </div>
        <script>
          const L=#{JSON.generate(l)};
          let state=null;
          function esc(x){return String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
          function render(){
            const p=document.getElementById('unitPane');
            if(!state){p.innerHTML='<div class="warn">'+esc(L.no_unit)+'</div>';return}
            p.innerHTML='<div class="unitname">'+esc(state.code||state.name||L.type)+'</div><div class="hint">'+esc(state.type||'')+' · '+Math.round(state.w)+' × '+Math.round(state.h)+' × '+Math.round(state.d)+' mm</div>'+
              '<label style="display:block;margin-top:12px">'+esc(L.kind)+'<select id="kind"><option value="base" '+(state.kind==='base'?'selected':'')+'>Lower</option><option value="wall" '+(state.kind==='wall'?'selected':'')+'>Upper</option><option value="tall" '+(state.kind==='tall'?'selected':'')+'>Tall</option></select></label>'+
              '<div class="grid"><label>'+esc(L.width)+'<input id="w" type="number" min="150" step="1" value="'+Math.round(state.w)+'"></label>'+
              '<label>'+esc(L.height)+'<input id="h" type="number" min="50" step="1" value="'+Math.round(state.h)+'"></label>'+
              '<label>'+esc(L.depth)+'<input id="d" type="number" min="50" step="1" value="'+Math.round(state.d)+'"></label></div>'+
              '<div class="hint" style="margin-top:10px">'+esc(L.live)+'</div><div class="actions"><button class="btn pri" id="apply">'+esc(L.apply)+'</button></div>';
            document.getElementById('apply').onclick=()=>{
              const payload={target_id:state.id,edit:{w:Number(document.getElementById('w').value),h:Number(document.getElementById('h').value),d:Number(document.getElementById('d').value),kind:document.getElementById('kind').value}};
              sketchup.edit_dialog_apply(JSON.stringify(payload));
            };
          }
          document.getElementById('close').onclick=()=>sketchup.edit_dialog_close();
          document.getElementById('openKitchen').onclick=()=>sketchup.edit_dialog_open_kitchen();
          sketchup.ready();
        </script></body></html>
      HTML
    end

    def show
      unless defined?(@dlg) && @dlg && @dlg.visible?
        @dlg = ::UI::HtmlDialog.new(
          dialog_title: labels[:title], preferences_key: 'EGC_Builder_EditDialog',
          scrollable: false, resizable: false, width: 430, height: 430,
          style: ::UI::HtmlDialog::STYLE_DIALOG
        )
        @dlg.set_html(html)
        @dlg.add_action_callback('ready') { |_, _| refresh }
        @dlg.add_action_callback('edit_dialog_apply') { |_, json| apply(JSON.parse(json)) }
        @dlg.add_action_callback('edit_dialog_close') { |_, _| close }
        @dlg.add_action_callback('edit_dialog_open_kitchen') { |_, _| open_kitchen }
        @dlg.set_on_closed { @dlg = nil }
      end
      @dlg.show
      refresh
    rescue StandardError => e
      ::UI.messagebox("E.G.C Builder:\n#{e.message}")
    end

    def refresh
      return unless @dlg
      g = selected_unit
      if g
        @dlg.execute_script("state=#{JSON.generate(unit_state(g))};render()")
      else
        @dlg.execute_script('state=null;render()')
      end
    rescue StandardError
      nil
    end

    def unit_state(g)
      {
        id: g.persistent_id, code: g.get_attribute('egc', 'code'), name: g.name,
        type: g.get_attribute('egc', 'type'), kind: g.get_attribute('egc', 'kind').to_s, w: g.get_attribute('egc', 'w').to_f,
        h: g.get_attribute('egc', 'h').to_f, d: g.get_attribute('egc', 'd').to_f
      }
    end

    def apply(msg)
      g = selected_unit
      raise 'Select the same E.G.C unit again before applying dimensions.' unless g && msg['target_id'].to_i == g.persistent_id
      cfg = Config.for_project(Config.build(Config.saved), Sketchup.active_model)
      edit = {}
      %w[w h d].each do |k|
        v = msg.dig('edit', k).to_f
        edit[k] = v if v.positive?
      end
      raise 'Enter at least one positive dimension.' if edit.empty?
      Kitchen.cascade_resize(g, edit, cfg)
      App.push_selection
      refresh
    rescue StandardError => e
      ::UI.messagebox("E.G.C Builder:\n#{e.message}")
    end


    def close
      @dlg&.close
    end
  end
end
