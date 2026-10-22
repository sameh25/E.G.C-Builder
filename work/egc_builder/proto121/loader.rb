# frozen_string_literal: true

Sketchup.require(File.join(File.dirname(__FILE__), 'core'))
Sketchup.require(File.join(File.dirname(__FILE__), 'hinge'))
Sketchup.require(File.join(File.dirname(__FILE__), 'bifold'))
Sketchup.require(File.join(File.dirname(__FILE__), 'imove'))
Sketchup.require(File.join(File.dirname(__FILE__), 'ui'))

module EGC
  # E.G.C 1.21.1 MECHANISM PROTOTYPES R2 (review build). Standalone scenes only - nothing here changes cabinet generation.
  module Proto121
    module_function

    # parallel-projection camera looking at `center` (builder frame); height = visible height in mm
    def ortho(kind, center, height)
      cam = camera(kind, center, 4000.0)
      cam.perspective = false
      cam.height = height.to_f.mm
      Sketchup.active_model.active_view.camera = cam
    end

    def persp(center, dist)
      cam = camera(:iso, center, dist)
      cam.perspective = true
      Sketchup.active_model.active_view.camera = cam
    end

    def find_group(name, ents = Sketchup.active_model.entities)
      ents.grep(Sketchup::Group).each do |x|
        return x if x.name == name

        r = find_group(name, x.entities)
        return r if r
      end
      nil
    end

    def show_group(name, vis)
      gr = find_group(name)
      gr.visible = vis if gr
    end

    def open_hinge
      rig = HingeProto.build
      Panel.show('EGC_REAL_HINGE_REFERENCE', 'Prototype A - concealed hinge (L + R)',
                 'Chain: carcass panel -> mounting plate -> U-channel arm -> two constant-length links -> cup carrier in the 35 mm bore -> door. Door pose is SOLVED from the linkage (door swings OUTWARD, never enters the carcass). Link pivot positions = INFERRED (fitted to the Petlia / Hinge-simplified CAD envelope; the simplified CAD has no links). <b>USER APPROVAL PENDING.</b>',
                 top: -> { HingeProto.section(false); ortho(:top, [450, -150, 110], 760) },
                 front: -> { HingeProto.section(false); ortho(:front, [450, 0, 110], 420) },
                 side: -> { HingeProto.section(false); ortho(:side, [0, -150, 110], 520) },
                 side_l: -> { HingeProto.section(false); ortho(:side_l, [900, -150, 110], 520) },
                 iso: -> { HingeProto.section(false); persp([450, -100, 110], 1100) },
                 detail: -> { HingeProto.section(true); ortho(:top, [30, -20, 110], 130) })
      rig
    end

    def open_bifold
      rig = BifoldProto.build
      bf = BifoldProto
      Panel.show('EGC_REAL_BIFOLD_REFERENCE', 'Prototype B - bi-fold lift (Blum AVENTOS HF type)',
                 'Chain: fixed lift body -> lever rod + telescopic arm (locked length) -> bracket on the upper front -> centre hinge -> lower front. The upper front is the coupler of the four-bar, so its motion is SOLVED from the link lengths (not keyframed). Pivot positions / link lengths = INFERRED (offline fit to the Blum video end pose, no collision); internal spring / power unit not modelled. <b>USER APPROVAL PENDING.</b>',
                 front: -> { show_group('panel_R', true); ortho(:front, [bf::W / 2, 0, bf::H / 2 + 150], 1500) },
                 side: -> { show_group('panel_R', false); ortho(:side, [bf::W / 2, 280, bf::H / 2 + 150], 1500) },
                 side_l: -> { show_group('panel_R', true); ortho(:side_l, [bf::W / 2, 280, bf::H / 2 + 150], 1500) },
                 top: -> { show_group('panel_R', true); ortho(:top, [bf::W / 2, 250, 300], 900) },
                 iso: -> { show_group('panel_R', true); persp([bf::W / 2, bf::D / 2, bf::H / 2 + 120], 2200) },
                 detail: -> { show_group('panel_R', false); ortho(:side, [bf::W / 2, 380, 520], 800) })
      rig
    end

    def open_imove
      rig = IMoveProto.build
      im = IMoveProto
      Panel.show('EGC_REAL_IMOVE_REFERENCE', 'Prototype C - Kesseboehmer iMove double tray (600)',
                 'Geometry AND pivots OBSERVED in the supplied manufacturer STEP (two arm plates, 275 mm, parallelogram: housing hubs -> side plate, handle on arm 1). Swing end derived from the official 340 mm drop. Spring / cam / lock not modelled. <b>USER APPROVAL PENDING.</b>',
                 front: -> { show_group('panel_R', true); ortho(:front, [0, 0, im::CAB_H / 2], 1200) },
                 side: -> { show_group('panel_R', false); ortho(:side, [0, 160, im::CAB_H / 2], 1200) },
                 side_l: -> { show_group('panel_R', true); ortho(:side_l, [0, 160, im::CAB_H / 2], 1200) },
                 top: -> { show_group('panel_R', true); ortho(:top, [0, 160, 300], 800) },
                 iso: -> { show_group('panel_R', true); persp([0, 140, im::CAB_H / 2], 2300) },
                 detail: -> { show_group('panel_R', false); ortho(:side, [0, 140, 330], 700) })
      rig
    end

    def about
      UI.messagebox("E.G.C 1.21.1 MECHANISM PROTOTYPES R2 (review build)\n\n" \
                    "A - concealed hinge (four-bar, left + right)\nB - bi-fold lift (Blum AVENTOS HF type)\nC - Kesseboehmer iMove double tray\n\n" \
                    "Standalone scenes for review only. No production cabinet uses these mechanisms yet.\n" \
                    "Status of every item: USER APPROVAL PENDING. Remaining limitations are listed in CHANGELOG_1.21.1_R2.md.")
    end

    unless file_loaded?(__FILE__)
      menu = ::UI.menu('Extensions').add_submenu('E.G.C Mechanism Prototypes (1.21.1 R2 review)')
      menu.add_item('A - Concealed hinge (left + right)') { open_hinge }
      menu.add_item('B - Bi-fold lift (Aventos HF type)') { open_bifold }
      menu.add_item('C - Kesseboehmer iMove double tray') { open_imove }
      menu.add_separator
      menu.add_item('About these prototypes') { about }
      file_loaded(__FILE__)
    end
  end
end
