# frozen_string_literal: true
module EGC
  module Civil
    module_function
    # Drawing datums derived from cabinet backs, without adding walls or floor to the model.
    def reference_lines(model)
      found=Exposure.collect(model)
      records=found[:units]+found[:blockers].select{|u|u.kind=='device'}
      groups=records.group_by do |u|
        a=u.tr.xaxis.normalize;p=u.tr.origin
        [Math.atan2(a.y,a.x).round(4),((-a.y*p.x+a.x*p.y).to_mm/5).round]
      end
      groups.values.each_with_index.map do |units,i|
        a=units.first.tr.xaxis.normalize;o=units.first.tr.origin
        extents=units.flat_map{|u|u.corners.map{|p|(p-o).dot(a).to_mm}}
        lo,hi=extents.minmax
        p=o+Snap.scaled(a,lo.mm);q=o+Snap.scaled(a,hi.mm)
        {'id'=>"R#{i+1}",'p0'=>[p.x.to_mm,p.y.to_mm],'p1'=>[q.x.to_mm,q.y.to_mm],
         'dir'=>[a.x,a.y],'len'=>hi-lo,'angle'=>Math.atan2(a.y,a.x)*180/Math::PI,'st'=>'INFERRED','reference_only'=>true}
      end
    end
    # Same room-side, distance and finite-span checks as cabinet association.
    # Unmatched appliances remain in the output instead of disappearing.
    def wall_match(record, walls)
      front = record.tr.yaxis.reverse.normalize
      walls.filter_map do |wall|
        next unless front.x * wall['dir'][1] - front.y * wall['dir'][0] > 0.9
        a0, a1, d0, d1, = AssistantValidate.in_wall_frame(record, wall)
        next unless d0 > -60 && d0 < 900 && AssistantValidate.ov(a0, a1, 0, wall['len']) > 50 && d1 - d0 > 100
        [wall, [a0, a1], [d0, d1]]
      end.min_by { |match| match[2][0].abs }
    end

    def device_units(blockers,walls,cfg)
      blockers.select{|u|u.kind=='device'}.filter_map do |u|
        attrs=u.g.attribute_dictionary('egc');kind=attrs['part'].to_s
        next if kind.empty?
        pts=u.corners;ctr=Geom::BoundingBox.new;pts.each{|p|ctr.add(p)};c=ctr.center
        match=wall_match(u,walls)
        wall,along,offsets=match || []
        # Report actual local dimensions even when no drawing datum matches.
        local=pts.map{|p|u.tr.inverse*p}
        xs=local.map{|p|p.x.to_mm}.minmax
        ys=local.map{|p|p.y.to_mm}.minmax
        id=attrs['dev_id']||SiteDocs::DEFAULT_DEV[kind]
        app={'kind'=>kind,'dev'=>id,'center'=>[c.x.to_mm,c.y.to_mm,c.z.to_mm],'z'=>[ctr.min.z.to_mm,ctr.max.z.to_mm],'opening'=>nil,'dev_src'=>'model'}
        {'rec'=>u,'name'=>u.g.name,'code'=>attrs['code']||"APP#{u.g.persistent_id}",'kind'=>'device','type'=>kind,
         'w'=>xs[1]-xs[0],'d'=>ys[1]-ys[0],'h'=>ctr.depth.to_mm,'z0'=>ctr.min.z.to_mm,
         'fp'=>[0,2,6,4].map{|i|[pts[i].x.to_mm,pts[i].y.to_mm]},'wall'=>wall && wall['id'],'along'=>along,'out'=>offsets,'apps'=>[app],
         'requires'=>match ? [] : [{'item'=>'Wall/reference association','detail'=>'Appliance has no matching direction, distance and span; service positions require site confirmation.'}]}
      end
    end
    # dir nil (the dialog button): the set is built into the preview staging folder and shown; Save there writes it.
    def export(dir=nil,cfg=nil,model=Sketchup.active_model,flat:false)
      require 'fileutils'
      cfg||=Config.build(Config.saved)
      if dir.nil?
        Preview.package(title:(App.lang=='ar' ? 'رسومات تجهيز الموقع' : 'Site preparation drawings'),folder_name:'EGC_Civil_'+Time.now.strftime('%Y%m%d_%H%M%S'),lang:App.lang,entry:'01_site_plan.html',open_after:'index.html'){|stage|export(stage,cfg,model,flat:true);{}}
        return nil
      end
      out=flat ? dir : File.join(dir,'EGC_Civil_'+Time.now.strftime('%Y%m%d_%H%M%S'))
      FileUtils.mkdir_p(out)
      proj=Assistant.load(model);data=SiteDocs.collect(model,proj,cfg)
      raise 'No cabinets / لا توجد وحدات' if data[:units].empty?
      lang=App.lang;st={status:'DRAFT',doc:'CURRENT'}
      sheets={
        '01_site_plan'=>SiteDocs.site_plan(data,lang,st),
        '02_electrical'=>SiteDocs.services_plan(data,%w[elec],'Electrical preparation','تجهيز برايز الكهرباء','E',lang,st),
        '03_plumbing'=>SiteDocs.services_plan(data,%w[water_cold water_hot drain],'Water and drain preparation','تجهيز المياه والصرف','P',lang,st),
        '04_gas_duct'=>SiteDocs.services_plan(data,%w[gas duct],'Gas and hood duct','الغاز ومخرج الشفاط','G',lang,st),
        '05_appliances'=>SiteDocs.appliance_sheet(data,lang,st),
        '06_installation'=>SiteDocs.installation(data,lang,st)
      }
      SiteDocs.used_walls(data).each{|w|sheets['elevation_'+w['id']]=SiteDocs.elevation(data,w,lang,st)}
      sheets.each{|name,body|File.write(File.join(out,name+'.html'),SvgDraw.page(name,body,lang))}
      groups=Exposure.collect(model)[:units].map(&:g).select{|g|g.get_attribute('egc','spec')}
      Phase1Docs.outputs(data,groups,cfg,lang,st).each{|name,html|File.write(File.join(out,name),html.encode('UTF-8'))}
      services=SiteDocs.services(data)
      File.write(File.join(out,'service_points.csv'),SitePack.service_csv(services['points']))
      File.write(File.join(out,'service_points.json'),JSON.pretty_generate(services))
      links=sheets.keys.map{|n|"<li><a href='#{n}.html'>#{n}</a></li>"}.join
      links << %w[K-01_general_elevation.html K-02_unit_identification.html K-03_representative_unit.html E-01_electrical_services.html P-01_plumbing_drain.html A-01_appliance_service_schedule.html].map{|n|"<li><a href='#{n}'>#{n}</a></li>"}.join
      File.write(File.join(out,'index.html'),"<meta charset='utf-8'><h1>E.G.C — تجهيز الموقع</h1><p>برايز الكهرباء والصرف والأجهزة وأبعاد التركيب. محاور R مستنتجة من ظهور الوحدات، وليست حوائط مقاسة. نقاط الخدمات المقترحة تحتاج ضبطًا حسب الجهاز والموقع.</p><ul>#{links}</ul>")
      index_body = "<h2>#{lang == 'ar' ? 'رسومات التنفيذ للمشروع' : 'Project execution drawings'}</h2><ul>#{links}</ul>"
      File.write(File.join(out,'index.html'),SvgDraw.page('E.G.C Civil / MEP',SvgDraw.sheet(proj,title:lang == 'ar' ? 'فهرس رسومات المشروع' : 'PROJECT DRAWING INDEX',sheet_no:'00',zone:'ALL',status:st[:status],lang:lang,body:index_body),lang),encoding:'UTF-8')
      out
    end
  end
end
