# frozen_string_literal: true

require 'json'

module EGC
  # The 1.21.1 R2 reference prototypes (bi-fold lift linkage, iMove double tray) INSIDE production cabinets.
  # A prototype is built by its own code - geometry and solved motion unchanged - into the cabinet group; its own review carcass is dropped and its
  # state rig is turned into ordinary 'move' attributes ('samples': the rig's transformation sampled over the stroke), so the standard motion tools
  # (open / close, slider, animation) drive it like every other mechanism. Fixed-size units: the prototypes were measured at one size.
  module ProtoBridge
    N = 40
    PANELS = %w[panel_L panel_R panel_bottom panel_top panel_back].freeze

    # stands in for the model so that a prototype's build() works inside any entities collection
    class Shim
      def initialize(ents)
        @ents = ents
      end

      def entities
        @ents
      end

      def materials
        Sketchup.active_model.materials
      end

      def start_operation(*)
        true
      end

      def commit_operation(*)
        true
      end

      def abort_operation(*)
        true
      end
    end

    module_function

    # -> the prototype's root group, inside ents, moved by shift [x, d, z] (builder frame), its moving parts carrying 'samples' moves
    def embed(ents, proto, part:, shift: [0, 0, 0], phase: nil)
      before = ents.grep(Sketchup::Group).to_a
      rig = proto.build(Shim.new(ents))
      root = (ents.grep(Sketchup::Group).to_a - before).first
      Proto121.rigs.delete(rig.name)
      rig.items.each do |it|
        e = it[:e]
        next unless e.valid?

        m = (0..N).map { |i| (it[:fn].call(i / N.to_f) * it[:base]).to_a.map { |v| v.round(6) } }
        mv = { 'type' => 'samples', 'm' => m }
        mv['phase'] = phase if phase
        e.set_attribute('egc', 'move', JSON.generate(mv))
        e.transformation = Geom::Transformation.new(m.first)
      end
      root.entities.grep(Sketchup::Group).each { |g| g.erase! if PANELS.include?(g.name) }
      root.transformation = Geom::Transformation.translation(Proto121.vec(*shift))
      root.name = part
      root.set_attribute('egc', 'role', 'hw')
      root.set_attribute('egc', 'part', part)
      root
    end
  end

  # 'samples' move: the sampled transformations of a solved linkage, interpolated between neighbours
  module ProtoMotion
    def move_transform(m, t)
      return super unless m['type'] == 'samples'

      a = m['m']
      x = phase(m, t) * (a.size - 1)
      i = [[x.floor, 0].max, a.size - 2].min
      Geom::Transformation.interpolate(Geom::Transformation.new(a[i]), Geom::Transformation.new(a[i + 1]), x - i)
    end
  end
  Mechanisms.singleton_class.prepend(ProtoMotion)

  module ProtoFamilies
    # Pull-down double tray (reference: Kesseboehmer iMove 600 STEP - measured plates, arms, housing, parallelogram). 600 wide wall unit, two doors:
    # the doors open first, then the trays swing forward and down.
    def fam_imove(_o)
      im = Proto121::IMoveProto
      unless (@w - 600.0).abs < 1.0 && @hc >= im::CAB_H - 1.0 && @cd - im::CAB_D >= @bk + 2.0
        raise MechanismError.new(:fixed_size, "the pull-down double tray is a fixed-size unit: 600 wide, at least #{im::CAB_H.round} high and #{(im::CAB_D + @bk + 2 + @ft).ceil} deep (asked: #{@w.round} x #{@hc.round} x #{@dd.round})")
      end

      zf, hf = full_front
      @door_phase = [0.0, 0.3]
      doors({ t: :doors }, zf, hf, false)
      @door_phase = nil
      ProtoBridge.embed(@e, im, part: 'imove_double_tray', shift: [@w / 2.0, @cd - im::CAB_D, @z0], phase: [0.35, 1.0]) # on the cabinet bottom, whatever the cabinet height
    end

    # Bi-fold lift with the R2 reference linkage (lift body, primary + secondary lever, coupling rod; the upper front is the coupler of the solved
    # four-bar). 800 x 560 x 320 carcass, as the prototype. The two fronts are real production boards carried by the prototype's motion.
    def fam_bifold_ref(_o)
      bf = Proto121::BifoldProto
      unless (@w - bf::W).abs < 1.0 && (@hc - bf::H).abs < 1.0 && (@cd - bf::D).abs < 1.0
        raise MechanismError.new(:fixed_size, "the reference bi-fold lift is a fixed-size unit: #{bf::W.round} x #{bf::H.round} x #{(bf::D + @ft).round} (asked: #{@w.round} x #{@hc.round} x #{@dd.round})")
      end

      root = ProtoBridge.embed(@e, bf, part: 'bifold_lift_ref')
      up = root.entities.grep(Sketchup::Group).find { |g| g.name == 'upper_front' }
      lo = root.entities.grep(Sketchup::Group).find { |g| g.name == 'lower_front' }
      # the prototype's plain front slabs make way for production fronts (cut list, edge band, handle) inside the same moving groups
      # (erased inside in_asm: its guide point keeps the group alive while it is momentarily without loose geometry)
      strip = ->(g) { g.entities.erase_entities(g.entities.select { |x| x.is_a?(Sketchup::Face) || x.is_a?(Sketchup::Edge) }) }
      fw = bf::W - 4.0
      in_asm(up) do
        strip.call(up)
        front('flap_upper', 2.0, fw, bf::CZ0 + bf::GAP / 2.0, bf::FH, :none, grain: :z)
        [bf::W * 0.17, bf::W * 0.83].each { |hx| h_rod('fold_hinge', hx - 22, bf::D - bf::FA - 5.5, bf::CZ0 - 5.5, :x, 44, 11, :chrome, 16) }
      end
      in_asm(lo) do
        strip.call(lo)
        front('flap_lower', 2.0, fw, bf::CZ0 - bf::GAP / 2.0 - bf::FH, bf::FH, :bottom, grain: :z)
      end
      @hw['bifold_lift'] += 1
    end
  end

  class Cabinet
    include ProtoFamilies
  end
end
