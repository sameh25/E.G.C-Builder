# frozen_string_literal: true

module EGC
  module Proto121
    # Review dialog: state slider (0-100 %), open/close animation, view buttons.
    module Panel
      module_function

      @dialogs = {}

      HTML = <<~'HTML'
        <!doctype html><html><head><meta charset="utf-8"><style>
        body{font-family:Segoe UI,Arial,sans-serif;margin:10px;background:#f4f4f6;color:#222}
        h3{margin:0 0 6px 0;font-size:15px} .row{margin:8px 0} input[type=range]{width:100%}
        button{margin:2px;padding:5px 9px;border:1px solid #888;background:#fff;border-radius:4px;cursor:pointer}
        .pct{font-size:22px;font-weight:600} .note{font-size:11px;color:#555;line-height:1.35}
        </style></head><body>
        <h3 id="t"></h3>
        <div class="row"><span class="pct" id="p">0</span> %</div>
        <div class="row"><input id="s" type="range" min="0" max="100" step="1" value="0"></div>
        <div class="row"><button onclick="go(0)">0</button><button onclick="go(10)">10</button><button onclick="go(25)">25</button><button onclick="go(50)">50</button><button onclick="go(75)">75</button><button onclick="go(90)">90</button><button onclick="go(100)">100</button></div>
        <div class="row"><button onclick="sketchup.play('open')">Open &#9654;</button><button onclick="sketchup.play('close')">Close &#9664;</button><button onclick="sketchup.play('stop')">Stop</button></div>
        <div class="row"><button onclick="sketchup.view('front')">Front</button><button onclick="sketchup.view('side')">Side</button><button onclick="sketchup.view('side_l')">Side (other)</button><button onclick="sketchup.view('top')">Top</button><button onclick="sketchup.view('iso')">Perspective</button><button onclick="sketchup.view('detail')">Hardware</button></div>
        <div class="note" id="n"></div>
        <script>
        var s=document.getElementById('s');
        s.oninput=function(){document.getElementById('p').textContent=s.value;sketchup.set(parseInt(s.value));};
        function go(v){s.value=v;document.getElementById('p').textContent=v;sketchup.set(v);}
        function init(t,n){document.getElementById('t').textContent=t;document.getElementById('n').innerHTML=n;}
        function setv(v){s.value=v;document.getElementById('p').textContent=Math.round(v);}
        window.onload=function(){sketchup.ready();};
        </script></body></html>
      HTML

      def show(rig_name, title, note, views = {})
        rig = Proto121.rigs[rig_name]
        return UI.messagebox('Build the prototype first.') unless rig

        dlg = @dialogs[rig_name]
        dlg&.close
        dlg = UI::HtmlDialog.new(dialog_title: title, scrollable: false, resizable: true, width: 380, height: 430, style: UI::HtmlDialog::STYLE_DIALOG)
        dlg.set_html(HTML)
        timer = nil
        dlg.add_action_callback('ready') { dlg.execute_script("init(#{title.inspect},#{note.inspect})") }
        dlg.add_action_callback('set') { |_c, v| rig.apply(v.to_f / 100.0) }
        dlg.add_action_callback('play') do |_c, mode|
          UI.stop_timer(timer) if timer
          timer = nil
          next if mode == 'stop'

          dir = mode == 'open' ? 1.0 : -1.0
          timer = UI.start_timer(1.0 / 30.0, true) do
            nt = rig.t + dir * (1.0 / 90.0)
            if nt >= 1.0 || nt <= 0.0
              UI.stop_timer(timer)
              timer = nil
              nt = [[nt, 0.0].max, 1.0].min
            end
            rig.apply(nt)
            dlg.execute_script("setv(#{(nt * 100).round(1)})")
          end
        end
        dlg.add_action_callback('view') { |_c, k| views[k.to_sym]&.call }
        dlg.show
        @dialogs[rig_name] = dlg
      end
    end
  end
end
