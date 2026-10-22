# frozen_string_literal: true
module EGC
  # Original generic geometry. Published product installation references are recorded separately;
  # these assemblies do not claim exact manufacturer certification or rated-load equivalence.
  module HardwareRevision
    def mpm
      palette=super
      palette.each do |key,material|
        kind=%i[plastic rubber damper black white].include?(key) ? 'plastic' : 'metal'
        next if material.get_attribute('egc','hardware_texture')==kind
        original_color=material.color
        material.texture=File.join(EGC::DIR,'assets','representatives',kind+'.png')
        material.texture.size=(kind=='metal' ? 120 : 40).mm
        material.color=original_color
        material.set_attribute('egc','hardware_texture',kind)
      end
      palette
    end
    # Pull-clear, then swivel: unlike the old back-pivot path, every tray stays inside
    # the clear opening until it is fully beyond the front plane. Front travels with its carrier.
    def fam_magic(o)
      b=bnd;zf,hf=full_front
      right=(o[:blind]||'right').to_s=='right'
      cw=b[:x1]-b[:x0];cd=b[:d1]-b[:d0]
      mdw=Kitchen.magic_door_w(@w,@c) # a wide (1200) corner unit: door 450-600, blind lane = the other run's depth + 50
      blind=mdw ? (@w-@gap-mdw).round : (cw*0.36).round;wa=cw-blind
      len=rail_len(cd+30);travel=len.to_f
      x=b[:x0]+14;d=@cd+@ft+10-travel
      dep=b[:d1]-d-12;fw=wa-40
      sz=b[:z0]+6;levels=2;pitch=(b[:z1]-sz-170)/2.0
      # Build once in right-hand coordinates, then mirror the complete hardware/front subtree.
      original_entities=@e
      unless right
        holder=@e.add_group
        holder.name='left_corner_hardware'
        holder.transformation=Geom::Transformation.translation([@w.mm,0,0])*Geom::Transformation.scaling(-1,1,1)
        @e=holder.entities
      end
      slide_fixed_mid(b[:x0],b[:x0]+wa-10,b[:d0],sz,len,travel,[0.05,0.5])
      carrier=asm('corner_slide',MotionProfiles.linear_slide([0,travel,0],[0.05,0.5]))
      in_asm(carrier) do
        slide_inner(b[:x0],b[:x0]+wa-10,b[:d0],sz,len)
        carriage_frame(x,b[:d0]+10,sz+22,fw,len-24)
        h_rod('corner_turntable',x-16,d-16,sz+34,:z,18,32,:steel,32)
        swing=asm('corner_swivel',MotionProfiles.rotate([x,d,0],-90,[0.5,0.78]))
        in_asm(swing) do
          set_baskets(x,d,sz+66,fw,dep,levels,pitch,80)
          carriage_frame(x,d,sz+50,fw,dep)
          h_rod('corner_carrier_pivot',x-13,d-13,sz+34,:z,24,26,:zinc,32)
          [x+16,x+fw-32].each do |xx|
            h_slab('corner_front_stile',xx,@cd-8,sz+54,16,8,zf+hf-20-(sz+54),:steel)
            [sz+66,sz+66+pitch].each{|zz|h_slab('corner_front_tie',xx,d+dep-16,zz,16,@cd-(d+dep-16),16,:steel)}
          end
          front('door',@gap/2.0,@w-@gap-blind,zf,hf,:top,grain: :z)
        end
      end
      rx=b[:x0]+wa+10;rw=[blind-26,wa-20].min;rd=b[:d0]+18;rdep=cd-65 # the rear set must fit the opening lane it slides into
      sx=-(wa-4)
      # Cross-slide first positions the rear set in the now-vacant opening lane.
      [rd+25,rd+rdep-35].each{|dd|h_slab('corner_cross_rail',x,dd,sz+50,rx+rw-x,18,12,:zinc)}
      cross=asm('corner_cross_carriage',MotionProfiles.linear_slide([sx,0,0],[0.78,0.9]))
      in_asm(cross) do
        [rd+25,rd+rdep-35].each{|dd|h_slab('corner_cross_bearing',rx,dd+2,sz+62,rw,14,8,:dark)}
        # These rails are fixed to the cross carriage, not to the moving rear basket.
        [rx,rx+rw-12.7].each{|xx|h_chan('corner_rear_fixed',xx,rd,sz+70,len,12.7,36,1.2,1,:zinc)}
        middle=asm('corner_rear_mid',MotionProfiles.linear_slide([0,travel/2,0],[0.9,1.0]))
        in_asm(middle){[rx+2,rx+rw-10.7].each{|xx|h_chan('corner_rear_mid',xx,rd+2,sz+72,len-4,8.7,32,1,1,:zinc)}}
        rear=asm('corner_rear_basket',MotionProfiles.linear_slide([0,travel,0],[0.9,1.0]))
        in_asm(rear) do
          [rx+4,rx+rw-8.7].each{|xx|h_chan('corner_rear_inner',xx,rd+4,sz+74,len-8,4.7,28,1,1,:zinc)}
          set_baskets(rx+14,rd+10,sz+112,rw-28,rdep-20,levels,pitch,80)
          carriage_frame(rx+8,rd+8,sz+94,rw-16,rdep-16)
        end
      end
      pn('filler',@w-blind-@gap/2.0,@cd,zf,blind,@ft,hf,'front',grain: :z,eb:[2,2],eb_t:2)
      @hw['basket']+=4;@hw['slide_pair']+=2;@hw['corner_pivot']+=1
    ensure
      @e=original_entities if original_entities
    end
    def h_tube(part,xc,p0,p1,dia,mat=:zinc)
      return super unless %w[lift_arm_outer lift_arm_guide].include?(part)
      a=Geo.p3(xc,*p0);b=Geo.p3(xc,*p1);v=b-a
      g=tgt.add_group
      bore=part=='lift_arm_guide' ? 4.8 : 5.0
      Appliances.ring(g.entities,0,0,0,dia/2,bore,v.length.to_mm,mpm[mat],:z)
      dir=v.normalize
      g.transformation=Geom::Transformation.axes(a,X_AXIS,(dir*X_AXIS).normalize,dir)
      hw_tag(g,part)
    end
    def slide_fixed_mid(x0,x1,d0,z,len,travel,phase=nil)
      super(x0,x1,d0,z,len,travel,phase||@runner_phase)
    end

    # Three nested concealed stages with a fixed side-mount bracket and moving release catches.
    # The outer drawer and its approved board dimensions are preserved.
    def runners_under(bx,bw,d0,slide,bz,travel)
      moving=@cur
      phase=@runner_phase
      drawer_thk=Config.drawer_thickness!(@c)
      xs=[bx+drawer_thk+1,bx+bw-drawer_thk-19]
      metal=Representative.material('metal')
      plastic=Representative.material('plastic')
      @cur=nil
      xs.each_with_index do |xx,i|
        side=i==0 ? ix0 : ix1
        h_chan('runner_under_fixed',xx,d0,bz-12,slide,18,20,1.2,i==0 ? 1 : -1,:zinc)
        [d0+30,d0+slide-60].each do |dd|
          h_slab('runner_under_mount',[side,xx].min,dd,bz-12,(side-xx).abs+(i==0 ? 18 : 0),24,2,:zinc)
        end
      end
      mid=asm('runner_under_mid',MotionProfiles.linear_slide([0,travel/2,0],phase))
      mid.set_attribute('egc','link',@link_to) if @link_to
      in_asm(mid) do
        xs.each_with_index{|xx,i|h_chan('runner_under_mid',xx+2,d0+3,bz-10,slide-6,14,16,1,i==0 ? 1 : -1,:zinc)}
      end
      @cur=moving
      xs.each_with_index do |xx,i|
        h_chan('runner_under_drawer',xx+4,d0+6,bz-8,slide-12,10,12,1,i==0 ? 1 : -1,:steel)
        h_slab('runner_under_bearing',xx+4,d0+25,bz+4,10,slide-55,4,:dark)
        lock=Appliances.box(@cur,xx,d0+slide-45,bz-8,18,28,12,plastic)
        hw_tag(lock,'runner_lock')
        h_rod('runner_lock_pin',xx+6,d0+slide-35,bz+4,:z,4,5,:chrome,16)
      end
    ensure
      @cur=moving
    end

    # A sleeve must be hollow: solid cylinders previously occupied the fixed carousel pole.
    def h_rod(part,x,d,z,axis,len,dia,mat=:chrome,segs=8)
      if %w[carousel_hub carousel_sleeve pole_bearing corner_turntable].include?(part) && axis==:z
        g=tgt.add_group
        Appliances.ring(g.entities,x+dia/2,d+dia/2,z,dia/2,part=='corner_turntable' ? 14 : 21,len,mpm[mat],:z)
        return hw_tag(g,part)
      end
      super
    end

    # Upright closed arms fold forward/down about side-mounted spring housings.
    def fam_liftrail(_o)
      b=bnd
      # the pull-down rail hangs behind the wardrobe doors: they open first, then the rail swings forward and down
      zf,hf=full_front
      @door_phase=[0.0,0.3]
      doors({t: :doors},zf,hf,false)
      @door_phase=nil
      pd=b[:d1]-70
      length=[(b[:z1]-b[:z0])*0.35,550].min
      pz=b[:z1]-length-45
      left=b[:x0]+22;right=b[:x1]-22
      [b[:x0],b[:x1]-18].each do |xx|
        h_slab('lift_housing',xx,pd-36,pz-52,18,72,104,:dark)
        [pz-34,pz+34].each{|zz|h_rod('lift_mount_screw',xx,pd-3,zz,:x,18,5,:zinc,16)}
      end
      [left-10,right-10].each{|xx|h_rod('lift_pivot',xx,pd-6,pz-6,:x,20,12,:chrome,24)}
      g=asm('lift_rail',MotionProfiles.lift([@w/2,pd,pz],95,[0.35,1.0]))
      in_asm(g) do
        [left,right].each do |xx|
          h_slab('lift_arm',xx-6,pd-8,pz,12,16,length,:zinc)
          h_rod('lift_cross_joint',xx-10,pd-12,pz+length-12,:x,20,24,:dark,24)
        end
        h_rod('lift_rail_bar',left,pd-12,pz+length-12,:x,right-left,25,:chrome,32)
        h_rod('lift_pull_handle',@w/2-5,pd+5,pz+length-360,:z,350,10,:dark,24)
        h_rod('lift_handle_grip',@w/2-55,pd+2,pz+length-365,:x,110,16,:dark,24)
      end
    end
  end
  Cabinet.prepend(HardwareRevision)

  module WardrobeHardware
    def ix0;@wardrobe_sx||@t;end
    def ix1;@wardrobe_ex||(@w-@t);end
    def front_style;'flat';end
    def sample_hinge?;@ft>=16;end
    def front_doors
      return super unless @doors=='hinged'
      sx=@t;counter=0;secs=interior_sections
      secs.each_with_index do |section,si|
        sw=section['w'].to_f
        @wardrobe_sx=sx;@wardrobe_ex=sx+sw
        left=si==0 ? 0 : sx-@t/2.0
        right=si==secs.length-1 ? @w : sx+sw+@t/2.0
        # Each section has only two structural mounting sides; a third leaf has no host.
        n=[[((right-left)/600.0).ceil,1].max,2].min
        width=(right-left-@gap*n)/n
        z=@z0+@gap/2.0;h=@hc-@gap
        @s={hand:(n==1 && si==secs.length-1 ? 'R' : 'L')}
        n.times do |k|
          x=left+@gap/2.0+k*(width+@gap);counter+=1
          leaf=asm("door#{counter}",door_move(k,n,x,width,z,h,false))
          in_asm(leaf) do
            side_handle('door',x,width,z,h,hinge_side(k,n)[0] ? :side_r : :side_l,@cd)
            door_hinges(k,n,x,width,z,h)
          end
          door_plates(k,n,x,width,z,h)
          @hw['hinge']+=hinge_count(h)
        end
        sx+=sw+@t
      end
    ensure
      @wardrobe_sx=@wardrobe_ex=nil
    end

    def hb(part,x,d,z,sx,sd,sz,mat='appliance',move=nil)
      if part=='roller'
        metal=Representative.material('metal')
        hw_tag(MechParts.rod(@cur||@e,x+5,d+2,z+6,:d,[sd-4,4].max,12,metal,24),'roller_wheel')
        hw_tag(Appliances.box(@cur||@e,x,d,z-4,sx,sd,6,metal),'roller_bracket')
        hw_tag(Appliances.box(@cur||@e,x+5,d,@z0+@t+6,10,sd,10,Representative.material('plastic')),'bottom_guide')
        return
      elsif %w[track_top track_bottom].include?(part)
        metal=Representative.material('metal')
        hw_tag(Appliances.box(@e,x,d,z,sx,sd,2,metal),part+'_web')
        [d,d+sd-2].each{|dd|hw_tag(Appliances.box(@e,x,dd,z+2,sx,2,sz-2,metal),part+'_lip')}
        return
      end
      super
    end
    def rod(sx,sw,z)
      center=@bk+(@fd-@bk)/2.0
      m=Representative.material('metal')
      hw_tag(Appliances.cyl(@cur||@e,sx,center,z+12.5,12.5,sw,m,:x,32),'rod')
      [sx,sx+sw-6].each do |xx|
        hw_tag(Appliances.box(@cur||@e,xx,center-16,z-4,6,32,34,m),'rod_socket')
      end
      @hw['rod_m']+=sw/1000.0;@hw['rod_bracket']+=2
    end
  end
  # The original wardrobe builder called side runners without including their family helpers.
  Wardrobe::Builder.include(FamilyBuilders)
  Wardrobe::Builder.prepend(HardwareRevision)
  bridge=Module.new
  [:door_hinges,:door_plates].each{|method|bridge.define_method(method,RepresentativeCabinet.instance_method(method))}
  Wardrobe::Builder.prepend(bridge)
  Wardrobe::Builder.prepend(WardrobeHardware)
end
