# frozen_string_literal: true

# Original EGC geometry; installation envelopes are documented in assets/representatives/references.json.
# These are generic working mechanisms, not manufacturer-certified CAD or load-rated simulations.
module EGC
  module Representative
    module_function

    def material(kind)
      scales = { 'metal' => 120, 'plastic' => 40, 'glass' => 600, 'wood' => 900 }
      m = Sketchup.active_model.materials["EGC Sample #{kind}"] || Sketchup.active_model.materials.add("EGC Sample #{kind}")
      unless m.texture
        m.texture = File.join(EGC::DIR, 'assets', 'representatives', "#{kind}.png")
        m.texture.size = scales.fetch(kind).mm
      end
      m.alpha = 0.32 if kind == 'glass'
      if m.respond_to?(:roughness_factor=)
        m.roughness_enabled = true
        m.roughness_factor = { 'metal'=>0.24, 'plastic'=>0.62, 'glass'=>0.06, 'wood'=>0.48 }.fetch(kind)
        m.metalness_enabled = kind == 'metal'
        m.metallic_factor = 0.9 if kind == 'metal'
      end
      m
    end

    def mark(g, name, fixed = false)
      g.name = name
      g.set_attribute('egc', 'role', 'hw')
      g.set_attribute('egc', 'part', name)
      g.set_attribute('egc', 'rep_fixed', true) if fixed
      g
    end

    # Two rigid links, equal length, connecting the mounting plate to the moving cup.
    # The door remains a rigid body. No geometry is scaled during motion.
    def joints(m, t)
      a = Geo.p3(*m['plate'])
      c = Mechanisms.rot_tr(m['door'], t) * Geo.p3(*m['cup'])
      dx, dy = (c.x-a.x).to_mm, (c.y-a.y).to_mm
      d = Math.hypot(dx,dy)
      l = m['length']
      raise 'Hinge linkage outside reach' if d > 2*l-0.01 || d < 0.01
      off = Math.sqrt(l*l-d*d/4)
      sign = m['hand']
      e = Geom::Point3d.new((a.x+c.x)/2 + (-dy/d*off*sign).mm,
                            (a.y+c.y)/2 + (dx/d*off*sign).mm, a.z)
      [a,e,c]
    end

    def link_transform(m,t)
      points = joints(m,t)
      a,b = points[m['segment']],points[m['segment']+1]
      angle = Math.atan2(b.y-a.y,b.x-a.x)
      Geom::Transformation.translation(a.to_a) * Geom::Transformation.rotation(ORIGIN,Z_AXIS,angle)
    end
  end

  module RepresentativeMotion
    def move_transform(m,t)
      return Representative.link_transform(m,phase(m,t)) if m['type']=='egc_rigid_link'
      super
    end
  end
  Mechanisms.singleton_class.prepend(RepresentativeMotion)

  module RepresentativeCabinet
    def appliance(cell,zf,hf)
      dv=device_for(cell[:app].to_s)
      return super unless cell[:app].to_s=='oven' && (!dv || (dv[:kind].to_s=='oven' && dv[:w].to_f<=600 && dv[:h].to_f<=600)) && cell[:h]>=595 && @w>=596 # a 60 cm built-in oven looks and stands the same whether it was picked from the catalogue or not
      return super if @cd-@bk<550 || @w-2*@t<560 || cell[:front] || cell[:open]
      # Face overlaps the niche sides, while the narrower body stays inside them.
      g=Appliances.place(@cur||@e,"#{@name}_oven",'oven',(@w-594)/2,@cd-526,cell[:z0],594,548,595,@c)
      mark_opening(g,dv,@w-2*@t,cell[:h],@cd-@bk)
    end

    def sample_hinge?
      !@s.to_h[:corner] && !@s.to_h[:notch] && %w[flat shaker].include?(front_style) && @ft >= 16
    end

    def door_hinges(k,n,x,dw,zf,hf)
      return super unless sample_hinge?
      left,outer=hinge_side(k,n)
      return super unless outer
      owner=(@cur||@e).parent.instances.find{|i|i.get_attribute('egc','move')} rescue nil
      @rep_doors||={}
      @rep_doors[[k,x,zf]]=[owner.name,JSON.parse(owner.get_attribute('egc','move'))] if owner
      xc=left ? x+21.5 : x+dw-21.5
      metal=Representative.material('metal')
      hinge_zs(zf,hf).each do |zc|
        # Cup enters the door from its rear face; 35 mm diameter and 13 mm drilling depth.
        cup=(@cur||@e).add_group
        Representative.mark(cup,'sample_hinge_cup')
        Appliances.ring(cup.entities,xc,@cd,zc,17.5,15.5,12,metal)
        Appliances.cyl(cup.entities,xc,@cd+11.5,zc,15.5,1.5,metal,:y,32)
        # The lip stays within the bored diameter; external fixing ears clear the carcass side.
        # A wider coplanar ring would overlap the uncut wooden rear face.
        # CUP FLANGE as on the owner's dimensioned hinge drawing: a plate 22 x 62 on the half of the cup AWAY from the door edge, its two
        # screws 48 apart; the dish itself (35 dia, open) reaches toward the door edge, where the arm comes in.
        fx0=left ? xc-2 : xc-20
        fx1=fx0+22
        [[zc-31,19.0],[zc+12,19.0]].each{|ez,eh|Appliances.box(cup.entities,fx0,@cd-1.6,ez,22,1.6,eh,metal)}
        Appliances.box(cup.entities,left ? fx1-8 : fx0,@cd-1.6,zc-12,8,1.6,24,metal)
        [-24,24].each do |oz|
          Appliances.cyl(cup.entities,fx0+11,@cd-3.0,zc+oz,3.6,1.4,metal,:y,14)
        end
        # link pin: carried by two thin cheeks that rise from the bottom of the dish to just above the door face, where the links can reach it
        # without cutting the door (straight links)
        [zc-9,zc+7].each{|cz|Appliances.box(cup.entities,xc-4,@cd-5,cz,8,16,2,metal)}
        Appliances.cyl(cup.entities,xc,@cd-2,zc-9,2.2,18,metal,:z,12)
        panel=(@cur||@e).grep(Sketchup::Group).find{|p|p.get_attribute('egc','part')=='door'}
        next unless panel
        point=panel.transformation.inverse*Geo.p3(xc,@cd,zc)
        edges=panel.entities.add_circle(point,Y_AXIS,17.5.mm,32)
        face=edges.flat_map(&:faces).uniq.select{|f|f.normal.parallel?(Y_AXIS)}.min_by(&:area)
        face.pushpull((face.normal.y>0 ? -12 : 12).mm) if face
        bores=JSON.parse(panel.get_attribute('egc','bore','[]')) rescue []
        unless bores.any?{|b|b['dia'].to_f==35 && (b['y'].to_f-point.z.to_mm).abs<0.6}
          bores<<{'t'=>'hinge cup','x'=>point.x.to_mm.round(1),'y'=>point.z.to_mm.round(1),'dia'=>35,'depth'=>12,'ref'=>'back face; x from left edge, y from bottom edge'}
        end
        bores.each{|b|b['depth']=12 if b['dia'].to_f==35}
        panel.set_attribute('egc','bore',JSON.generate(bores))
      end
    end

    LINK_LEN=23.0 # each of the two hinge links: together they span arm tip -> cup with the door square open
    def door_plates(k,n,x,dw,zf,hf)
      return super unless sample_hinge?
      left,outer=hinge_side(k,n)
      return super unless outer
      metal=Representative.material('metal')
      xc=left ? x+21.5 : x+dw-21.5
      edge=left ? ix0 : ix1
      px=left ? edge+4 : edge-4
      dd=@cd-37
      source=@rep_doors && @rep_doors[[k,x,zf]]
      dm=source ? source[1] : door_move(k,n,x,dw,zf,hf,false)
      hinge_zs(zf,hf).each do |zc|
        plate=@e.add_group
        Representative.mark(plate,'sample_hinge_plate',true)
        # Cruciform mounting plate as on the reference block: an upright wing with two screws, a horizontal bar the arm sits on, and a raised seat.
        Appliances.box(plate.entities,left ? edge : edge-2,dd-8,zc-25,2,30,50,metal)
        Appliances.box(plate.entities,left ? edge : edge-2,dd-32,zc-7,2,62,14,metal)
        Appliances.box(plate.entities,left ? edge+2 : edge-5,dd-26,zc-6,3,44,12,metal)
        # two fixing screws 32 mm apart, 37 mm from the carcass front edge (published plate pattern: 32 mm system, edge distance 37)
        [-16,16].each{|zz|[dd,dd+14].each{|hd|Appliances.cyl(plate.entities,left ? edge+2 : edge-3.4,hd,zc+zz,hd==dd ? 3.6 : 2.6,1.4,metal,:x,14)}}
        # HINGE ARM: a boxed channel FIXED on the plate (it does not swing), ending 8 mm behind the carcass front - the whole hinge is about 60 mm
        # from plate to cup when closed, as on the reference hinge. Only the two short links at its tip move.
        # arm about 62 long and 18 high with its raised cover cap (reference hinge), reaching the carcass front edge
        ax=left ? edge+5 : edge-16
        Appliances.box(plate.entities,ax,@cd-62,zc-9,11,60,18,metal)
        Appliances.box(plate.entities,left ? ax+11 : ax-2,@cd-58,zc-7,2,36,14,metal)
        # knuckle at the arm tip: the pin the links turn on, between two cheeks
        Appliances.cyl(plate.entities,apx_k=(left ? edge+10 : edge-10),@cd-2,zc-10,2.6,20,metal,:z,12)
        [@cd-50,@cd-30].each{|sd|Appliances.cyl(plate.entities,left ? ax+13 : ax-3.2,sd,zc,3.0,1.2,metal,:x,14)}
        apx=left ? edge+10 : edge-10
        # link length = half the longest plate-to-cup distance of the whole swing (+0.15): stretched almost straight with the door open, and
        # with the door CLOSED the two links fold back INTO the carcass, inside the arm channel - never through the door.
        pa=Geo.p3(apx,@cd-2,zc)
        reach=(0..20).map{|i|(Mechanisms.rot_tr(dm,i/20.0)*Geo.p3(xc,@cd-2,zc)).distance(pa).to_mm}.max
        link_len=reach/2.0+0.15
        2.times do |segment|
          spec={'type'=>'egc_rigid_link','plate'=>[apx,@cd-2,zc],'cup'=>[xc,@cd-2,zc],
        'door'=>dm,'length'=>link_len,'segment'=>segment,'hand'=>left ? -1 : 1,'phase'=>dm['phase']}
          arm=asm("sample_link_#{k}_#{zc}_#{segment}",spec)
          arm.set_attribute('egc','link',source ? source[0] : "#{@name}_door#{k+1}")
          if segment==0
            # inner link, between the two cheeks of the outer one
            Appliances.box(arm.entities,0,-3.5,-4,link_len,7,8,metal)
          else
            # outer link pair carrying the cup
            Appliances.box(arm.entities,0,-3.5,-7,link_len,7,2.0,metal)
            Appliances.box(arm.entities,0,-3.5,5,link_len,7,2.0,metal)
          end
          [0,link_len].each{|xx|Appliances.cyl(arm.entities,xx,0,-8,2.4,16,metal,:z,14)}
          arm.transformation=Representative.link_transform(spec,0)
        end
      end
    end

    def fam_pullout(o)
      return super unless @s[:mech].to_s=='PULLOUT_BASKET'
      return fam_wire_p1(o)
      return fam_wire_p1(o)
      b=bnd
      len=rail_len(b[:d1]-b[:d0]+30)
      travel=len.to_f
      z=b[:z0]+8
      x0,x1=b[:x0],b[:x1]
      d0=@cd-len-12
      metal=Representative.material('metal')
      plastic=Representative.material('plastic')
      fixed=@e.add_group
      Representative.mark(fixed,'sample_fixed_runners',true)
      # 12.7 mm side-space, 45.7 mm outer height: Accuride 3832 installation envelope.
      [[x0,1],[x1-12.7,-1]].each do |xx,hand|
        MechParts.channel(fixed.entities,xx,d0,z,len,12.7,45.7,1.2,hand,metal)
        [37,165,len-35].each do |pd|
          Appliances.cyl(fixed.entities,xx+(hand==1 ? 0 : 11.5),d0+pd,z+22,2.2,1.2,metal,:x,12)
        end
      end
      mid=asm('sample_mid_runner',{'type'=>'lin','v'=>[0,travel/2,0]})
      mid.set_attribute('egc','link',"#{@name}_pullout")
      [[x0+2.2,1],[x1-10.5,-1]].each{|xx,hand|MechParts.channel(mid.entities,xx,d0+3,z+3,len-6,8.3,39.7,1,hand,metal)}
      moving=asm('pullout',{'type'=>'lin','v'=>[0,travel,0]})
      moving.set_attribute('egc','representative','basket')
      in_asm(moving) do
        [[x0+4.5,1],[x1-8.2,-1]].each{|xx,hand|MechParts.channel(@cur,xx,d0+5,z+8,len-10,3.7,29.7,1,hand,metal)}
        bx=x0+14
        bw=x1-x0-28
        levels=[z+48,z+(@hc-2*@t)*0.56]
        [d0+20,d0+len-40].each{|pd|Appliances.box(@cur,x0+8,pd,z+25,x1-x0-16,20,14,metal)}
        [bx+4,bx+bw-12].each do |xx|
          [d0+24,d0+len-44].each do |pd|
            Appliances.box(@cur,xx,pd,z+39,8,8,levels.last+100-(z+39),metal)
            levels.each do |zz|
              Appliances.box(@cur,xx-2,pd-2,zz-5,12,12,10,plastic)
            end
          end
          Appliances.box(@cur,xx,@cd-8,z+30,8,8,levels.last+60-z,metal)
          [z+40,levels.last+40].each{|zz|Appliances.box(@cur,xx,d0+len-40,zz,8,@cd-(d0+len-40),8,metal)}
        end
        levels.each{|zz|MechParts.wire_basket(@cur,bx,d0+12,zz,bw,len-28,100,metal,4)}
        zf,hf=full_front
        front('door',@gap/2,@w-@gap,zf,hf,:top,grain: :z)
      end
      @hw['basket']+=2
      @hw['slide_pair']+=1
    end
  end
  Cabinet.prepend(RepresentativeCabinet)

  module RepresentativeOven
    def oven(ents,x,d,z,w,dep,h,cfg={})
      return super if h<595 || w<590 || dep<548
      metal=Representative.material('metal')
      glass=Representative.material('glass')
      plastic=Representative.material('plastic')
      p=pal
      fw=w>=590 ? w : 594.0
      fx=x+(w-fw)/2
      front=d+dep
      body_w=558.0
      bx=x+(w-body_w)/2
      body_d=front-548
      fixed=ents.add_group
      Representative.mark(fixed,'sample_oven_fixed',true)
      # Structural housing, enamel cavity, fan cover and fixed shelf supports.
      shell(fixed.entities,bx,body_d,z+4,body_w,524,504,12,p[:enamel],p[:enamel])
      [bx+24,bx+body_w-48].each do |xx|
        [body_d+24,body_d+470].each{|dd|box(fixed.entities,xx,dd,z,24,24,4,plastic)}
      end
      4.times{|i|[bx+13,bx+body_w-17].each{|xx|box(fixed.entities,xx,body_d+32,z+70+i*85,4,460,4,metal)}}
      wire_rack(fixed.entities,bx+17,body_d+35,z+246,body_w-34,452,metal)
      ring(fixed.entities,x+w/2,body_d+15,z+255,78,67,4,metal)
      8.times{|i|box(fixed.entities,x+w/2-48+i*12,body_d+20,z+205,3,2,100,metal)}
      # control fascia: brushed steel, deep enough to sit on the housing; black glass display with a lit read-out, chrome knobs
      # the control fascia sits ON the oven: the housing goes on up to the top behind it (electronics / cooling channel), the fascia
      # covers it from the door top to the top of the oven - nothing floats (owner, 1.28.55)
      box(fixed.entities,bx,body_d,z+508,body_w,front-22-body_d,87,p[:grey_dk] || p[:enamel])
      # only the 22 mm face is as wide as the oven front: it lies on the carcass front edges (covers them), nothing wide goes back into the side panels
      slab(fixed.entities,fx,z+505,fw,90,front,22,p[:door])
      slab(fixed.entities,x+w/2-65,z+540,130,32,front,2,p[:black],-0.5)
      slab(fixed.entities,x+w/2-34,z+551,68,9,front,2,p[:blue],-2.0)
      [fx+58,fx+fw-58].each{|xx|knob(fixed.entities,xx,front,z+558,16,p[:chrome])}
      vent_slots(fixed.entities,fx+80,z+508,fw-160,8,front,p[:black],2,20)
      # Fixed hinge sockets and moving pins share the bottom pivot, 2 mm clear of the cavity.
      [fx+35,fx+fw-43].each{|xx|box(fixed.entities,xx,front-26,z,8,24,4,metal)}
      door=mov(ents,'sample_oven_door',{'type'=>'rot','pivot'=>[x+w/2,front-2,z+2],'axis'=>[1,0,0],'deg'=>90})
      de=door.entities
      # A frame around a real transparent window, not glass laid on an opaque slab.
      # black glass door: the frame is the black outer pane, the window a smoked pane - the cavity shows dimly, as on a real oven
      slab(de,fx+2,z+2,fw-4,64,front,18,p[:black])
      slab(de,fx+2,z+446,fw-4,58,front,18,p[:black])
      [fx+2,fx+fw-51].each{|xx|slab(de,xx,z+66,49,380,front,18,p[:black])}
      slab(de,fx+51,z+66,fw-102,380,front-4,4,p[:smoke])
      bezel(de,fx+49,z+64,fw-98,384,front,3,p[:chrome],2,-0.5)
      hbar(de,fx+45,fx+fw-45,z+475,front,p[:chrome],32,6)
      [fx+35,fx+fw-43].each{|xx|cyl(de,xx,front-2,z+2,2,8,metal,:x,16)}
      door.set_attribute('egc','representative','oven')
    end
  end
  Appliances.singleton_class.prepend(RepresentativeOven)
end
