/* E.G.C Intelligent Assistant - dialog side. Stages: INPUT > CONSTRAINTS > DESIGN > VALIDATION > EDIT > CLIENT SHOT > EXECUTION > MANUFACTURING > COST */
(function(){
const A={st:null,img:null,imgMode:'ref',ref:[],trace:[],pv:null,res:{},mode:'quick',qpath:null,qceil:'',form:{w:5400,d:3000,ceil:2800,layout:'auto',fridge:true,dish:true,cmd:'',name:'',client:'',rev:'A',margin:20,vat:14,final:false,shots:true,
  o_type:'window',o_wall:'B',o_off:2000,o_w:1200,o_h:1200,o_sill:1000,c_wall:'B',c_off:0,c_w:300,c_d:300,s_kind:'water_cold',s_wall:'B',s_off:2000,s_z:550,s_dev:'',cl:'openings',ci:'',cf:'off',cv:''}};
window.EGC_ASSIST_DEBUG=A; // read-only introspection hook for support/testing - the module state stays private otherwise
const TX={
 ar:{title:'المساعد الذكي',sub:'من الأبعاد إلى مطبخ كامل وملفات التنفيذ والتصنيع - على نفس وحدات E.G.C',
  stages:['المدخلات','القيود','التصميم','التحقق','التعديل','لقطة العميل','التنفيذ','التصنيع','التكلفة'],
  input:'١ · المدخلات',room:'الغرفة (مم)',w:'العرض',d:'العمق',ceil:'السقف',ceilbtn:'تأكيد السقف',accept:'قبول القيم المستنتجة',ceildef:'افتراضي - غير مؤكد',mkroom:'إنشاء الغرفة من الأبعاد',scan:'قراءة الحوائط من SketchUp',scanapply:'استخدام الحوائط المقروءة',dxf:'استيراد الغرفة من DXF وبناء المطبخ بالقواعد',
  img:'إرفاق صورة / كروكي',imgnote:'اضغط نقطتين على بُعد معروف ثم اكتب طوله ← المقياس. بعدها ارسم الغرفة بالنقر على الأركان (كل ما يُقرأ من الصورة = INFERRED).',refbtn:'نقطتان مرجعيتان',mm:'الطول الحقيقي (مم)',setscale:'ضبط المقياس',tracebtn:'رسم الغرفة',usetrace:'استخدام الغرفة المرسومة',clear:'مسح النقاط',
  add:'إضافة',opening:'فتحة',column:'عمود',service:'نقطة خدمة',type:'النوع',window:'شباك',door:'باب',wall:'الحائط',off:'البعد من بداية الحائط',ow:'العرض',oh:'الارتفاع',sill:'العتبة',cd:'العمق',skind:'النوع',sz:'الارتفاع من الأرضية',sdev:'الجهاز (اختياري)',
  cons:'٢ · القيود (ملخص قابل للقراءة قبل أي توليد)',correct:'تصحيح قيمة واحدة بدون إعادة رسم',list:'القائمة',id:'رقم',field:'الحقل',value:'القيمة',apply:'تطبيق',remove:'حذف',unconf:'بنود غير مؤكدة',
  design:'٣ · التصميم',layout:'التخطيط',auto:'تلقائي',fridge:'ثلاجة',dish:'غسالة أطباق',propose:'اقتراح (بدون رسم)',optsbtn:'اقتراحات A/B/C',accept:'اعتماد وبناء',noprop:'راجع اقتراحاً أولاً ثم اعتمده',unres:'غير محسوم',assum:'افتراضات',gen:'توليد التصميم في الموديل',
  valid:'٤ · التحقق',validate:'تحقق الآن',problems:'مشاكل',warnings:'تحذيرات',fix:'الحل المقترح',noprob:'لا توجد مشاكل',
  edit:'٥ · التعديل بالمحادثة (عربي / English)',cmdph:'مثال: غير الثلاجة إلى 90 سم',preview:'معاينة',applyc:'تنفيذ',undo:'تراجع (Undo)',what:'ماذا',why:'لماذا',affected:'الوحدات المتأثرة',expected:'النتيجة المتوقعة',confirm:'أؤكد فقدان التعديلات اليدوية',
  shot:'٦ · لقطة العميل',doshot:'جهّز لقطة للعميل',check:'فحص الجاهزية للريندر',fixr:'إصلاح (إغلاق الأبواب / مسح التحديد)',
  pack:'٧-٩ · التنفيذ والتصنيع والتكلفة',pname:'المشروع',pclient:'العميل',prev:'المراجعة',margin:'الهامش %',vat:'ضريبة %',final:'إصدار نهائي (ممنوع مع البنود غير المؤكدة)',shots:'تضمين لقطات العميل',dopack:'جهّز المشروع للتنفيذ والتصنيع',
  status:'حالة المستندات',outdated:'مستند قديم بعد تعديل الموديل',open:'فتح المجلد',busy:'جارٍ العمل…',cross:'الفحص المتقاطع',done:'تم',err:'خطأ',needroom:'عرّف الغرفة أولاً',
  wall_:'حائط',ready:'جاهز للتوليد',notready:'ينقصه بيانات مؤكدة',draft:'مسودة',finalr:'الإصدار النهائي مرفوض:',examples:'أمثلة',
  q_quick:'وضع سريع',q_adv:'وضع متقدم',q_toadv:'الأدوات الكاملة (وضع متقدم) ←',q_toquick:'← الوضع السريع',
  q_title:'حلّل الكروكي',q_sub:'من صورة الكروكي إلى مطبخ كامل في 4-5 خطوات فقط',
  q_s1:'الخطوة ١ · اختر صورة الكروكي',q_home:'ابدأ منين؟',o1:'١ · تصميم قياسي',o1h:'قواعد E.G.C الثابتة - من غير ذكاء اصطناعي. اكتب أبعاد الغرفة.',o2:'٢ · صورة / كروكي ← الغرفة',o2h:'صورة، كروكي عليه مقاسات (مطبوعة أو بخط اليد)، رسم كاد. المقاسات بتتقري تلقائياً والغرفة بتتبني، وبعدها تختار تصميم قياسي أو بالذكاء الاصطناعي.',o3:'٣ · تصميم بالذكاء الاصطناعي',o3h:'اقتراحات بالذكاء الاصطناعي من نموذج الغرفة (ومن صورة التصميم لو موجودة).',go:'ابدأ',img_t:'صورة / كروكي ← الغرفة',img_h:'اختار الصورة - المقاسات بتتقري تلقائياً ونموذج الغرفة بيظهر قبل أي تصميم.',img_next:'الغرفة جاهزة - اختار نوع التصميم',q_pick:'اختيار صورة',q_nopic:'لا توجد صورة؟',q_manual:'أدخل الأبعاد مباشرة بدلًا من الصورة',
  q_s2:'بديل يدوي · مقياس الصورة',q_s2h:'(بديل فقط - الطريق العادي هو قراءة المقاسات تلقائياً) انقر على طرفي أي خط تعرف طوله الحقيقي في الصورة، ثم اكتب طوله بالمم.',
  q_mm_ph:'مثلاً 600',q_s2go:'تأكيد المقياس',
  q_s3:'بديل يدوي · ارسم شكل الغرفة',q_s3h:'انقر على أركان الغرفة بالترتيب (٣ أركان على الأقل)، ثم اضغط "تم الرسم".',q_s3go:'تم رسم الغرفة',q_undo:'تراجع عن آخر نقطة',
  q_s4:'الخطوة ٤ · ارتفاع السقف',q_s4h:'قيمة واحدة حرجة ناقصة: ارتفاع السقف الحقيقي (مم). لن نفترضها.',q_s4go:'تأكيد الارتفاع',
  q_s5:'الخطوة ٥ · فهمت الغرفة كالتالي',q_confirmed:'مؤكد',q_inferred:'مستنتج من الصورة',q_note_openings:'لم يتم استخراج أبواب/شبابيك/أعمدة/نقاط خدمة من الصورة تلقائيًا - أضفها من الوضع المتقدم لو موجودة، وإلا ستُعتبر غير معروفة.',
  q_gen:'توليد التصميم الآن',q_start:'ابدأ من جديد',q_wall:'الحائط',q_len:'الطول',q_stop:'الصورة غير كافية',
  q_m_w:'العرض (مم)',q_m_d:'العمق (مم)',q_m_ceil:'ارتفاع السقف (مم)',q_m_go:'التالي',
  q_svc:'توليد نقاط الخدمات (كهرباء/سباكة)',q_svc_title:'نقاط الخدمة المقترحة من الأجهزة الفعلية',
  q_svc_note:'مواضع مقترحة من مواضع الأجهزة الحالية فقط - لا افتراض لأي قدرة كهربائية أو قاطع أو مقاس مواسير. المخططات الكاملة المقاسة: تبويب الإنتاج ← تجهيز المشروع للتنفيذ والتصنيع.',
  q_svc_none:'لا توجد أجهزة (ثلاجة/فرن/حوض/غسالة أطباق...) تحتاج نقاط خدمة في هذا التصميم بعد.',
  q_svc_id:'النقطة',q_svc_dev:'الجهاز',q_svc_unit:'الوحدة',q_svc_wall:'الحائط',q_svc_off:'البعد',q_svc_z:'الارتفاع من الأرضية'},
 en:{title:'Intelligent Assistant',sub:'From dimensions to a complete kitchen and the site / manufacturing package - on the same E.G.C units',
  stages:['INPUT','CONSTRAINTS','DESIGN','VALIDATION','EDIT','CLIENT SHOT','EXECUTION','MANUFACTURING','COST'],
  input:'1 · INPUT',room:'Room (mm)',w:'Width',d:'Depth',ceil:'Ceiling',ceilbtn:'Confirm ceiling',accept:'accept inferred values',ceildef:'default - NOT confirmed',mkroom:'Create room from dimensions',scan:'Read walls from SketchUp',scanapply:'Use the walls found',dxf:'Import the room from DXF and build by the rules',
  img:'Attach image / sketch',imgnote:'Click two points on a KNOWN dimension and type its length -> scale. Then trace the room by clicking the corners (everything read from an image stays INFERRED).',refbtn:'Reference points',mm:'Real length (mm)',setscale:'Set scale',tracebtn:'Trace room',usetrace:'Use the traced room',clear:'Clear points',
  add:'Add',opening:'Opening',column:'Column',service:'Service point',type:'Type',window:'Window',door:'Door',wall:'Wall',off:'Offset from wall start',ow:'Width',oh:'Height',sill:'Sill',cd:'Depth',skind:'Kind',sz:'Height above floor',sdev:'Device (optional)',
  cons:'2 · CONSTRAINTS (readable summary before anything is generated)',correct:'Correct one value without redrawing',list:'List',id:'ID',field:'Field',value:'Value',apply:'Apply',remove:'Delete',unconf:'unconfirmed items',
  design:'3 · DESIGN',layout:'Layout',auto:'Auto',fridge:'Refrigerator',dish:'Dishwasher',propose:'Propose (no geometry)',optsbtn:'Proposals A/B/C',accept:'Accept & build',noprop:'Review a proposal first, then accept it',unres:'Unresolved',assum:'Assumptions',gen:'Generate design in the model',
  valid:'4 · VALIDATION',validate:'Validate now',problems:'Problems',warnings:'Warnings',fix:'Suggested fix',noprob:'No problems',
  edit:'5 · EDIT by conversation (Arabic / English)',cmdph:'e.g. change the fridge to 90 cm',preview:'Preview',applyc:'Apply',undo:'Undo',what:'WHAT',why:'WHY',affected:'AFFECTED UNITS',expected:'EXPECTED RESULT',confirm:'I confirm: hand edits will be lost',
  shot:'6 · CLIENT SHOT',doshot:'Prepare Client Shot',check:'Render-ready check',fixr:'Fix (close doors / clear selection)',
  pack:'7-9 · EXECUTION · MANUFACTURING · COST',pname:'Project',pclient:'Client',prev:'Revision',margin:'Margin %',vat:'VAT %',final:'FINAL issue (refused while anything is unconfirmed)',shots:'Include client shots',dopack:'Create Site & Manufacturing Pack',
  status:'Document status',outdated:'document outdated after a model change',open:'Open folder',busy:'Working…',cross:'Cross-check',done:'Done',err:'Error',needroom:'Define the room first',
  wall_:'wall',ready:'ready to generate',notready:'confirmed data missing',draft:'DRAFT',finalr:'Final issue refused:',examples:'Examples',
  q_quick:'Quick mode',q_adv:'Advanced mode',q_toadv:'Full tools (Advanced mode) →',q_toquick:'← Quick mode',
  q_title:'Analyze the sketch',q_sub:'From a sketch photo to a full kitchen in 4-5 steps',
  q_s1:'Step 1 · Pick the sketch image',q_home:'Where do you start?',o1:'1 · Standard design',o1h:'Deterministic E.G.C rules - no AI. Type the room dimensions.',o2:'2 · Image / sketch → room',o2h:'Photo, dimensioned sketch (printed or handwritten), CAD drawing. The dimensions are read automatically and the room is rebuilt; then choose Standard or AI design.',o3:'3 · AI design',o3h:'AI proposals from the room model (and a design image if you have one).',go:'Start',img_t:'Image / sketch → room',img_h:'Choose the image - the dimensions are read automatically and the room model is shown before any design.',img_next:'Room ready - choose the design',q_pick:'Choose image',q_nopic:'No image?',q_manual:'Enter dimensions directly instead',
  q_s2:'Manual fallback · Scale the image',q_s2h:'(fallback only - the normal path reads the dimensions automatically) Click both ends of any line whose real length you know, then type its length in mm.',
  q_mm_ph:'e.g. 600',q_s2go:'Confirm scale',
  q_s3:'Manual fallback · Trace the room shape',q_s3h:'Click the room corners in order (at least 3), then press "Done tracing".',q_s3go:'Done tracing',q_undo:'Undo last point',
  q_s4:'Step 4 · Ceiling height',q_s4h:'One critical value is missing: the real ceiling height (mm). It will not be assumed.',q_s4go:'Confirm height',
  q_s5:'Step 5 · I understood the room as follows',q_confirmed:'confirmed',q_inferred:'inferred from the image',q_note_openings:'Doors/windows/columns/service points were NOT auto-extracted from the image - add them from Advanced mode if present, otherwise they stay unknown.',
  q_gen:'Generate the design now',q_start:'Start over',q_wall:'Wall',q_len:'Length',q_stop:'The image is not enough',
  q_m_w:'Width (mm)',q_m_d:'Depth (mm)',q_m_ceil:'Ceiling height (mm)',q_m_go:'Next',
  q_svc:'Generate Services (electrical/plumbing)',q_svc_title:'Proposed service points from the real appliances',
  q_svc_note:'Proposed positions from the current appliance positions only - no power rating, breaker, circuit or pipe size is assumed. Full dimensioned plans: Production tab -> Create Site & Manufacturing Pack.',
  q_svc_none:'No appliances (fridge/oven/sink/dishwasher…) need service points in this design yet.',
  q_svc_id:'Point',q_svc_dev:'Device',q_svc_unit:'Unit',q_svc_wall:'Wall',q_svc_off:'Offset',q_svc_z:'Height above floor'}};
const at=k=>(TX[S.lang]||TX.en)[k]||TX.en[k]||k;
const $$=s=>document.querySelector(s);
const esc=s=>String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const chip=st=>'<span class="ast '+st+'">'+st+'</span>';
function call(op,payload,msg){const o=Object.assign({lang:S.lang,cfg:S.cfg},payload||{});busy(msg||at('busy'));setTimeout(()=>sketchup[op](JSON.stringify(o)),40)}
function busy(m){const b=$$('#asBusy');if(b){b.textContent=m;b.style.display=m?'block':'none'}}
function ensure(){if($$('#tab-assist'))return;const s=document.createElement('section');s.className='tab';s.id='tab-assist';s.innerHTML='<div class="col" id="asCol" style="flex:1;overflow:auto"></div>';$$('main').appendChild(s);
 const st=document.createElement('style');st.textContent=`
 #asCol .stg{display:flex;gap:4px;flex-wrap:wrap;margin:4px 0 12px}#asCol .stg span{background:#efe1bd;border-radius:14px;padding:2px 10px;font-size:11.5px;font-weight:600}
 #asCol .g2{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr));gap:12px;align-items:start}
 #asCol .row{display:flex;gap:8px;flex-wrap:wrap;align-items:flex-end;margin:6px 0}#asCol .row label{display:flex;flex-direction:column;font-size:11.5px;color:var(--mut);min-width:0;flex:1 1 90px}
 #asCol input,#asCol select{font:inherit;border:1px solid #d5d2c7;border-radius:6px;padding:4px 6px;width:100%;min-width:0}
 #asCol table{width:100%;border-collapse:collapse;font-size:12px}#asCol td,#asCol th{padding:3px 6px;border-bottom:1px solid var(--line);text-align:start}
 .ast{display:inline-block;padding:1px 8px;border-radius:9px;font-size:10.5px;font-weight:700}.ast.CONFIRMED{background:#dff3e6;color:#177245}.ast.INFERRED{background:#fdf1d3;color:#8a5a00}.ast.REQUIRES_CONFIRMATION,.ast.OUTDATED,.ast.MISSING_PRICE{background:#fde0dc;color:#b42318}.ast.CURRENT{background:#dff3e6;color:#177245}.ast.NOT_GENERATED{background:#eee;color:#666}
 #asBusy{display:none;position:sticky;top:0;z-index:5;background:#1c1f24;color:#fff;padding:8px 12px;border-radius:8px;margin-bottom:8px;font-weight:600}
 #asCol .pv{background:#fff7e0;border:1px dashed var(--acc);border-radius:10px;padding:8px 12px;margin:8px 0}#asCol .pv b{color:#8a5a00}
 #asCol .bad{color:#b42318;font-weight:600}#asCol .ok{color:#177245;font-weight:600}#asCol canvas{max-width:100%;border:1px solid var(--line);cursor:crosshair;background:#fff}`;document.head.appendChild(st)}
function inp(id,type,val,extra){return '<input id="'+id+'" type="'+(type||'number')+'" value="'+esc(val)+'" '+(extra||'')+'>'}
function bind(){const c=$$('#asCol');c.querySelectorAll('[data-f]').forEach(e=>{const k=e.dataset.f;const h=()=>{A.form[k]=(e.type==='checkbox')?e.checked:e.value};e.oninput=h;e.onchange=h});
 c.querySelectorAll('[data-op]').forEach(b=>b.onclick=()=>act(b.dataset.op))}
function F(k){return A.form[k]}
function wallOpts(sel){const ws=(A.st&&A.st.walls)||[];return ws.map(w=>'<option value="'+w.id+'" '+(w.id===sel?'selected':'')+'>'+w.id+' ('+w.len+')</option>').join('')||'<option>-</option>'}
function ceilBadge(){const c=A.st&&A.st.proj&&A.st.proj.room&&A.st.proj.room.ceiling;if(c&&c.v)return '<span dir="ltr" class="ast '+(c.st==='CONFIRMED'?'CURRENT':'OUTDATED')+'" id="ceilSt">'+Math.round(c.v)+' mm · '+esc(c.st)+'</span>';return '<span class="bad" id="ceilSt">'+at('ceildef')+'</span>'}
function fld(label,id,type,extra){return '<label>'+label+'<input data-f="'+id+'" type="'+(type||'number')+'" value="'+esc(F(id))+'" '+(extra||'')+'></label>'}
function sel(label,id,opts){return '<label>'+label+'<select data-f="'+id+'">'+opts+'</select></label>'}
function o(v,l,cur){return '<option value="'+v+'" '+(String(cur)===String(v)?'selected':'')+'>'+l+'</option>'}
function summaryHtml(){const sm=A.st&&A.st.summary;if(!sm)return '';return '<table>'+sm.lines.map(l=>'<tr><td>'+esc(l.label)+'</td><td>'+esc(l.value)+'</td><td>'+chip(l.st)+'</td></tr>').join('')+'</table><div class="'+(sm.ready?'ok':'bad')+'">'+(sm.ready?at('ready'):at('notready'))+' · '+sm.unconfirmed+' '+at('unconf')+'</div>'}
function validHtml(v){if(!v)return '';const li=(a,cls)=>a.map(i=>'<li class="'+cls+'"><b>'+esc(i.code)+'</b> '+esc(i.where)+': '+esc(i.message)+(i.fix?' <i>→ '+esc(at('fix'))+': '+esc(i.fix)+'</i>':'')+'</li>').join('');
 return '<div><b>'+at('problems')+' ('+v.problems.length+')</b><ul>'+(li(v.problems,'bad')||'<li class="ok">'+at('noprob')+'</li>')+'</ul><b>'+at('warnings')+' ('+v.warnings.length+')</b><ul>'+li(v.warnings,'')+'</ul></div>'}
function pvHtml(p){if(!p)return '';if(!p.ok)return '<div class="pv bad">'+esc(p.code)+': '+esc(p.message)+(p.examples?'<br><small>'+at('examples')+': '+p.examples.map(esc).join(' · ')+'</small>':'')+(p.options?'<br><small>'+p.options.map(esc).join(' · ')+'</small>':'')+'</div>';
 return '<div class="pv"><b>'+at('what')+':</b> '+esc(p.what)+'<br><b>'+at('why')+':</b> '+esc(p.why)+'<br><b>'+at('affected')+':</b> '+(p.affected||[]).map(esc).join(', ')+'<br><b>'+at('expected')+':</b> '+esc(p.expected)+(p.warning?'<br><span class="bad">'+esc(p.warning)+'</span>':'')+'</div>'}
function packHtml(r){if(!r)return '';if(r.cancelled)return '';let h='<div class="pv"><b>'+esc(r.status)+'</b> · '+esc(r.dir)+'<br>'+Object.keys(r.files).map(k=>esc(k)+' ×'+r.files[k]).join(' · ')+'<br>'+at('cross')+': '+r.crosscheck.errors+' err / '+r.crosscheck.warnings+' warn · FINAL: <b class="'+(r.crosscheck.final_allowed?'ok':'bad')+'">'+(r.crosscheck.final_allowed?'ALLOWED':'BLOCKED')+'</b>'+(r.refused_final?'<br><span class="bad">'+at('finalr')+' '+r.unresolved.slice(0,3).map(esc).join(' | ')+'</span>':'')+
 '<br>'+(r.cost&&!r.cost.complete?'<span class="bad">MISSING PRICE ×'+r.cost.missing.length+'</span> · ':'')+'total '+(r.cost?Math.round(r.cost.total):'-')+' · sheets '+(r.takeoff?r.takeoff.sheets:'-')+' · waste '+(r.takeoff?r.takeoff.waste_pct:'-')+' % · '+(r.timing?r.timing.total_s:'-')+' s</div>';
 h+='<div class="row"><button class="btn sm" data-op="open_dir">'+at('open')+'</button></div>';return h}
const DOCN={ar:{site_plan:'مخطط الموقع',elevations:'الواجهات',electrical:'الكهرباء',plumbing:'السباكة والغاز والشفط',worktop:'سطح العمل',sections:'القطاعات',shop:'الشوب دروينج',production:'التصنيع',cost:'التكلفة الداخلية',quote:'عرض السعر',notes:'ملاحظات التركيب',client:'عرض العميل'}};
const STN={ar:{NOT_GENERATED:'لم يُنشأ',CURRENT:'حالي',OUTDATED:'قديم - أعد الإنشاء',STALE:'قديم'}};
function statusHtml(){const st=A.st&&A.st.status;if(!st||!st.length)return '';const dn=k=>(DOCN[S.lang]&&DOCN[S.lang][k])||k;return '<b>'+at('status')+'</b><table>'+st.map(s=>'<tr><td>'+esc(dn(s.key))+'</td><td><span class="ast '+s.status+'">'+((STN[S.lang]||{})[s.status]||s.status)+'</span></td><td>'+esc((s.why||[]).join('; '))+'</td></tr>').join('')+'</table>'}
function shotHtml(){const r=A.res.shot;let h='';if(r&&r.report)h+='<table>'+r.report.scenes.map(s=>'<tr><td>'+esc(s.name)+'</td><td>fov '+s.fov+'</td><td>'+esc(s.notes.join('; '))+'</td><td>'+(s.hidden_walls?('walls hidden in the scene: '+s.hidden_walls):'')+'</td></tr>').join('')+'</table><div class="'+(r.report.geometry_unchanged?'ok':'bad')+'">geometry unchanged: '+r.report.geometry_unchanged+'</div>';
 const ck=(A.res.check||(r&&r.check));if(ck)h+='<ul>'+ck.issues.map(i=>'<li class="'+(i.severity==='error'?'bad':'')+'"><b>'+esc(i.code)+'</b> '+esc(i.message)+'</li>').join('')+'</ul><div class="'+(ck.ready?'ok':'bad')+'">'+(ck.ready?'RENDER-READY':'NOT READY')+'</div>';return h}
function imageHtml(){if(!A.img)return '';return '<canvas id="asCv" width="600" height="400"></canvas><div class="row"><label>'+at('mm')+'<input data-f="scmm" type="number" value="'+esc(F('scmm')||'')+'"></label><button class="btn sm" data-op="mode_ref">'+at('refbtn')+'</button><button class="btn sm" data-op="setscale">'+at('setscale')+'</button><button class="btn sm" data-op="mode_trace">'+at('tracebtn')+'</button><button class="btn sm" data-op="usetrace">'+at('usetrace')+'</button><button class="btn sm" data-op="clearpts">'+at('clear')+'</button></div><div class="hint">'+at('imgnote')+' ('+A.imgMode+')</div>'}
window.renderAssist=function(){ensure();const c=$$('#asCol');if(!c)return;const st=A.st;
 c.innerHTML='<div id="asBusy"></div><div class="row" style="justify-content:space-between;align-items:center"><div><h2 style="margin:4px 0">'+at('title')+'</h2><div class="hint">'+at('sub')+'</div></div><button class="btn sm" data-op="q_toquick">'+at('q_toquick')+'</button></div><div class="stg">'+at('stages').map(s=>'<span>'+s+'</span>').join('')+'</div>'+
 '<div class="g2"><div>'+
 '<div class="card"><h3>'+at('input')+'</h3><div class="row">'+fld(at('pname'),'name','text')+fld(at('pclient'),'client','text')+fld(at('prev'),'rev','text')+'<button class="btn sm" data-op="project">'+at('apply')+'</button></div>'+
 '<div class="row">'+fld(at('w'),'w','number')+fld(at('d'),'d','number')+fld(at('ceil'),'ceil','number')+ceilBadge()+'<button class="btn sm" data-op="ceiling">'+at('ceilbtn')+'</button><button class="btn sm pri" data-op="room">'+at('mkroom')+'</button></div>'+
 '<div class="row"><button class="btn sm" data-op="scan">'+at('scan')+'</button><button class="btn sm" data-op="scanapply">'+at('scanapply')+'</button><button class="btn sm" data-op="dxf">'+at('dxf')+'</button><button class="btn sm" data-op="image">'+at('img')+'</button></div>'+imageHtml()+
 '<details><summary><b>'+at('opening')+'</b></summary><div class="row">'+sel(at('type'),'o_type',o('window',at('window'),F('o_type'))+o('door',at('door'),F('o_type')))+sel(at('wall'),'o_wall',wallOpts(F('o_wall')))+fld(at('off'),'o_off')+fld(at('ow'),'o_w')+fld(at('oh'),'o_h')+fld(at('sill'),'o_sill')+'<button class="btn sm" data-op="add_opening">'+at('add')+'</button></div></details>'+
 '<details><summary><b>'+at('column')+'</b></summary><div class="row">'+sel(at('wall'),'c_wall',wallOpts(F('c_wall')))+fld(at('off'),'c_off')+fld(at('ow'),'c_w')+fld(at('cd'),'c_d')+'<button class="btn sm" data-op="add_column">'+at('add')+'</button></div></details>'+
 '<details><summary><b>'+at('service')+'</b></summary><div class="row">'+sel(at('skind'),'s_kind',['water_cold','water_hot','drain','gas','elec','duct'].map(k=>o(k,k,F('s_kind'))).join(''))+sel(at('wall'),'s_wall',wallOpts(F('s_wall')))+fld(at('off'),'s_off')+fld(at('sz'),'s_z')+fld(at('sdev'),'s_dev','text')+'<button class="btn sm" data-op="add_service">'+at('add')+'</button></div></details></div>'+
 '<div class="card"><h3>'+at('cons')+'</h3>'+summaryHtml()+
 '<details><summary><b>'+at('correct')+'</b></summary><div class="row">'+sel(at('list'),'cl',['openings','columns','services'].map(k=>o(k,k,F('cl'))).join(''))+fld(at('id'),'ci','text')+sel(at('field'),'cf',['off','w','h','d','sill','z'].map(k=>o(k,k,F('cf'))).join(''))+fld(at('value'),'cv')+'<button class="btn sm" data-op="correct">'+at('apply')+'</button><button class="btn sm" data-op="remove">'+at('remove')+'</button></div></details></div></div>'+
 '<div>'+
 '<div class="card"><h3>'+at('design')+'</h3><div class="row">'+sel(at('layout'),'layout',['auto','straight','L','U','parallel','island'].map(k=>o(k,k==='auto'?at('auto'):k,F('layout'))).join(''))+'<label class="chk"><input data-f="fridge" type="checkbox" '+(F('fridge')?'checked':'')+'>'+at('fridge')+'</label><label class="chk"><input data-f="dish" type="checkbox" '+(F('dish')?'checked':'')+'>'+at('dish')+'</label><label class="chk"><input data-f="accept" type="checkbox" '+(F('accept')?'checked':'')+'>'+at('accept')+'</label></div>'+
 '<div class="row"><button class="btn sm" data-op="options">'+at('optsbtn')+'</button><button class="btn sm" data-op="propose">'+at('propose')+'</button><button class="btn sm pri" data-op="generate">'+at('gen')+'</button></div>'+optionsHtml()+(A.res.plan?optionsHtml()+'<div class="pv"><b>'+esc(A.res.plan.layout)+'</b><br>'+(A.res.plan.notes||[]).map(esc).join('<br>')+(A.res.plan.problems&&A.res.plan.problems.length?'<br><span class="bad">'+A.res.plan.problems.map(p=>esc(p.code+': '+p.message)).join('<br>')+'</span>':'')+(A.res.runs?'<br><small>'+A.res.runs.map(r=>Object.keys(r).map(k=>k+': '+r[k].cols.join(', ')).join(' | ')).join('<br>')+'</small>':'')+'</div>':'')+'</div>'+
 '<div class="card"><h3>'+at('valid')+'</h3><div class="row"><button class="btn sm" data-op="validate">'+at('validate')+'</button></div>'+validHtml(A.res.validation)+'</div>'+
 '<div class="card"><h3>'+at('edit')+'</h3><div class="row"><label style="flex:3 1 260px"><input data-f="cmd" type="text" value="'+esc(F('cmd'))+'" placeholder="'+at('cmdph')+'"></label><button class="btn sm" data-op="preview">'+at('preview')+'</button></div>'+pvHtml(A.pv)+
 (A.pv&&A.pv.ok?'<div class="row">'+(A.pv.needs_confirm?'<label class="chk"><input data-f="confirm" type="checkbox">'+at('confirm')+'</label>':'')+'<button class="btn sm pri" data-op="applycmd">'+at('applyc')+'</button></div>':'')+'<div class="row"><button class="btn sm" data-op="undo">'+at('undo')+'</button></div></div>'+
 '<div class="card"><h3>'+at('shot')+'</h3><div class="row"><button class="btn sm pri" data-op="shot">'+at('doshot')+'</button><button class="btn sm" data-op="check">'+at('check')+'</button><button class="btn sm" data-op="fixr">'+at('fixr')+'</button></div>'+shotHtml()+'</div>'+
 '<div class="card"><h3>'+at('pack')+'</h3><div class="row">'+fld(at('margin'),'margin')+fld(at('vat'),'vat')+'<label class="chk"><input data-f="shots" type="checkbox" '+(F('shots')?'checked':'')+'>'+at('shots')+'</label><label class="chk"><input data-f="final" type="checkbox" '+(F('final')?'checked':'')+'>'+at('final')+'</label></div><div class="row"><button class="btn pri" data-op="pack">'+at('dopack')+'</button></div>'+packHtml(A.res.pack)+statusHtml()+'</div>'+
 '</div></div>';bind();drawCanvas()};
function optionsHtml(){const o=A.res.options;let h='';if(A.res.provider&&A.res.provider.vision===false)h+='<div class="hint">'+esc(A.res.provider.status)+': '+esc(A.res.provider.note)+'</div>';if(A.res.room_status&&!o?.length)h+='<div class="hint bad">'+esc(r2('roomblocked'))+'</div>';if(!o||!o.length)return h;return h+o.map(x=>'<div class="pv"><b>'+esc(x.id)+' · '+esc(x.label)+'</b> — '+esc(x.layout||'')+'<br><small>'+x.runs.map(r=>Object.keys(r).map(k=>k+': '+r[k].cols.join(', ')).join(' | ')).join('<br>')+'</small><br><small>'+at('assum')+': '+(x.assumptions||[]).map(esc).join('; ')+'</small><br><small class="bad">'+at('unres')+': '+(x.unresolved||[]).map(esc).join(' | ')+'</small><div class="row"><button class="btn sm pri" data-op="acc_'+esc(x.id)+'" '+(x.buildable?'':'disabled')+'>'+at('accept')+' '+esc(x.id)+'</button></div></div>').join('')}
function drawCanvas(){const cv=$$('#asCv');if(!cv||!A.img)return;const im=new Image();im.onload=()=>{const k=Math.min(600/im.width,400/im.height);cv.width=im.width*k;cv.height=im.height*k;const x=cv.getContext('2d');x.drawImage(im,0,0,cv.width,cv.height);
  const dot=(p,c)=>{x.fillStyle=c;x.beginPath();x.arc(p[0]*k,p[1]*k,4,0,7);x.fill()};A.ref.forEach(p=>dot(p,'#b42318'));if(A.ref.length===2){x.strokeStyle='#b42318';x.beginPath();x.moveTo(A.ref[0][0]*k,A.ref[0][1]*k);x.lineTo(A.ref[1][0]*k,A.ref[1][1]*k);x.stroke()}
  x.strokeStyle='#1d4ed8';x.beginPath();A.trace.forEach((p,i)=>{i?x.lineTo(p[0]*k,p[1]*k):x.moveTo(p[0]*k,p[1]*k)});if(A.trace.length>2)x.closePath();x.stroke();A.trace.forEach(p=>dot(p,'#1d4ed8'))};
 im.src=A.img;cv.onclick=e=>{const r=cv.getBoundingClientRect();const p=[(e.clientX-r.left)*(cv.width/r.width)/(cv.width/im.width),(e.clientY-r.top)*(cv.height/r.height)/(cv.height/im.height)];
  if(A.imgMode==='ref'){if(A.ref.length>=2)A.ref=[];A.ref.push(p)}else A.trace.push(p);
  if(A.mode==='quick')renderAssistTab();else drawCanvas()}}
function act(op){const f=A.form;
 if(op==='q_toquick'){A.mode='quick';return renderAssistTab()}
 if(op==='project')return call('assist_project',{name:f.name,client:f.client,rev:f.rev});
if(op==='ceiling')return call('assist_ceiling',{ceiling:+f.ceil});
 if(op==='room')return call('assist_room',{w:+f.w,d:+f.d,ceiling:+f.ceil});
 if(op==='scan')return call('assist_scan',{});if(op==='dxf')return call('assist_dxf',{build:true});if(op==='scanapply')return call('assist_scan',{apply:true});
 if(op==='image')return call('assist_image',{});
 if(op==='mode_ref'){A.imgMode='ref';return renderAssist()}if(op==='mode_trace'){A.imgMode='trace';return renderAssist()}
 if(op==='setscale'){if(A.ref.length<2||!(+f.scmm>0))return toast(at('imgnote'),true);return call('assist_scale',{ref:A.ref,mm:+f.scmm})}
 if(op==='usetrace')return call('assist_trace',{points:A.trace});if(op==='clearpts'){A.ref=[];A.trace=[];return renderAssist()}
 if(op==='add_opening')return call('assist_add',{kind:'opening',type:f.o_type,wall:f.o_wall,off:+f.o_off,w:+f.o_w,h:+f.o_h,sill:+f.o_sill});
 if(op==='add_column')return call('assist_add',{kind:'column',wall:f.c_wall,off:+f.c_off,w:+f.c_w,d:+f.c_d});
 if(op==='add_service')return call('assist_add',{kind:'service',skind:f.s_kind,wall:f.s_wall,off:+f.s_off,z:+f.s_z,device:f.s_dev||null});
 if(op==='correct')return call('assist_correct',{list:f.cl,id:f.ci,field:f.cf,value:f.cv});if(op==='remove')return call('assist_remove',{list:f.cl,id:f.ci});
 const opts={layout:f.layout,fridge:!!f.fridge,dishwasher:!!f.dish,accept_inferred:!!f.accept};
 if(op==='propose')return call('assist_propose',{opts});if(op==='options')return call('assist_options',{opts:{layout:f.layout,dishwasher:!!f.dish,accept_inferred:!!f.accept}});if(op.indexOf('acc_')===0){const x=((A.res.options||[]).find(y=>y.id===op.slice(4)));if(!x)return toast(at('noprop'),true);return call('assist_generate',{opts:Object.assign({},x.opts,{accepted:true,accept_inferred:!!f.accept||x.opts.accept_inferred})})}if(op==='generate'){if(!A.res.plan)return toast(at('noprop'),true);return call('assist_generate',{opts:Object.assign({},opts,{accepted:true})})}if(op==='validate')return call('assist_validate',{});
 if(op==='preview'){A.pv=null;return call('assist_cmd_preview',{text:f.cmd})}if(op==='applycmd')return call('assist_cmd_apply',{confirm:!!f.confirm});if(op==='undo')return call('assist_undo',{});
 if(op==='shot')return call('assist_shot',{});if(op==='check')return call('assist_check',{});if(op==='fixr')return call('assist_fix',{});
 if(op==='pack')return call('assist_pack',{final:!!f.final,client_shots:!!f.shots,client:{name:f.client,project:f.name,margin_pct:+f.margin,vat_pct:+f.vat,discount_pct:0,valid_days:15}},at('busy')+' (site plan · elevations · services · worktop · sections · shop drawings · cut list · nesting · takeoff · cost · quote · client shots)');
 if(op==='open_dir'&&A.res.pack)return sketchup.assist_open_dir(JSON.stringify({dir:A.res.pack.dir}))}
function onAssist(op,d){busy('');onVision(op,d);
 if(d.proj){A.st=d;const p=d.proj;A.form.name=p.name||A.form.name;A.form.client=p.client||A.form.client;A.form.rev=p.rev||A.form.rev;const cc=p.room&&p.room.ceiling;if(cc&&cc.v)A.form.ceil=Math.round(cc.v)}
 if(d.image){A.img=d.image.data;A.ref=[];A.trace=[]}
 if(op==='assist_dxf'&&d.dxf&&!d.dxf.cancelled){const x=d.dxf;toast('DXF: '+x.walls.length+' walls · '+x.openings.length+' openings · '+x.columns.length+' columns · '+(x.plumbing?'plumbing on wall '+x.plumbing.wall:'no plumbing marker')+' · '+x.unit+(d.made?' · built':'')+(d.refused?' · NOT built: '+((d.plan.problems[0]||{}).message||''):''),!!d.refused);if(d.plan){A.res.plan=d.plan;A.res.roots_made=d.made}}
 if(d.found)toast((d.found.segments.length)+' wall segment(s) found'+(d.found.polygon?' · closed room':' · no closed room'));
 if(d.trace&&d.trace.error)toast(d.trace.message,true);
 if(op==='assist_options'){A.res.options=d.options;A.res.provider=d.provider}
 if(d.vision&&d.vision.ok===false)toast(d.vision.code+': '+d.vision.message,true);
 if(op==='assist_propose'||op==='assist_generate'){A.res.plan=d.plan;A.res.runs=d.runs||null}
 if(d.validation!==undefined&&d.validation!==null)A.res.validation=d.validation;
 if(op==='assist_cmd_preview')A.pv=d;
 if(op==='assist_cmd_apply'){if(d.ok){toast(at('done'));A.pv=null}else{toast(d.message||'refused',true);if(d.code==='CONFIRM_REQUIRED'){}}}
 if(op==='assist_shot'){A.res.shot=d;A.res.check=d.check}if(op==='assist_check'||op==='assist_fix')A.res.check=d.check;
 if(op==='assist_pack'){A.res.pack=d;if(!d.cancelled)call('assist_status',{})}
 if(op==='assist_generate'){A.res.roots_made=d.made;A.res.services=null;call('assist_status',{})}
 if(op==='assist_services')A.res.services=d;
 renderAssistTab()}
function renderAssistTab(){if(A.mode==='quick')return renderQuick();return renderAssist()}
const _rn=window.renderNav;window.renderNav=function(){const n=document.getElementById('nav');n.innerHTML=['kitchen','assist','units','mech','app','mat','prod'].map(k=>'<button data-k="'+k+'" class="'+(S.tab===k?'on':'')+'">'+(k==='assist'?at('title'):t('tabs.'+k))+'</button>').join('');n.onclick=e=>{const b=e.target.closest('button');if(!b)return;S.tab=b.dataset.k;showTab()}};
const _st=window.showTab;window.showTab=function(){if(S.tab==='assist'){ensure();document.querySelectorAll('.tab').forEach(x=>x.classList.remove('on'));$$('#tab-assist').classList.add('on');renderNav();const kb=document.getElementById('kmodeBar');if(kb)kb.style.display='none';renderAssistTab();if(!A.st||A.lang!==S.lang){A.lang=S.lang;call('assist_load',{})}return}return _st()};
const _ra=window.renderAll;if(_ra)window.renderAll=function(){_ra();if(S.tab==='assist'){renderAssistTab();if(A.st&&A.lang!==S.lang){A.lang=S.lang;call('assist_load',{})}}};
const _rv=EGC.recv;EGC.recv=function(m){if(m.type==='assist'){onAssist(m.op,m.data);return}if(m.type==='error'){busy('')}return _rv(m)};

/* ============================================================================================================
   QUICK MODE: image -> scale -> trace -> ceiling -> summary -> generate, one question at a time.
   Never invents a critical dimension; every image-derived value is labelled INFERRED until the user confirms it
   by moving past that step. The full toolset (openings/columns/services/edit/client shot/pack) stays reachable
   from Advanced mode - Quick mode only fast-tracks the room + first design.
   ============================================================================================================ */
function qStep(){
 if(A.qpath==='ai')return 'ai';
 if(A.qpath==='manual')return 'manual';
 if(A.qpath==='image')return 'image';
 const p=A.st&&A.st.proj;
 if(!A.img)return 'attach';
 if(!(p&&p.image&&p.image.scale))return 'calibrate';
 if(!(p&&p.room&&p.room.poly&&p.room.poly.length>=3))return 'trace';
 if(!(p&&p.room&&p.room.ceiling&&p.room.ceiling.v))return 'ceiling';
 return 'summary';
}
function qWrap(step,label,body){return '<div class="card q-step"><h3><span class="chip">'+esc(label)+'</span></h3>'+body+'</div>'}
function qHeader(){return '<div class="row" style="justify-content:space-between;align-items:center">'+
 '<div><h2 style="margin:4px 0">'+at('q_title')+'</h2><div class="hint">'+at('q_sub')+'</div></div>'+
 '<button class="btn sm" data-op="q_toadv">'+at('q_toadv')+'</button></div>'}
window.renderQuick=function(){ensure();const c=$$('#asCol');if(!c)return;
 const step=qStep();
 A.imgMode=(step==='trace')?'trace':'ref';
 let body='';
 if(step==='image'){body=qImage();
 }else if(step==='ai'){body=qAi();
 }else if(step==='manual'){
  body=qWrap('manual',at('q_s1'),'<div class="row">'+fld(at('q_m_w'),'w','number')+fld(at('q_m_d'),'d','number')+fld(at('q_m_ceil'),'ceil','number')+'</div>'+
   '<div class="row"><button class="btn sm" data-op="q_back">'+('←')+'</button><button class="btn sm pri" data-op="q_manual_go">'+at('q_m_go')+'</button></div>')+
   (A.st&&A.st.proj&&A.st.proj.room&&A.st.proj.room.ceiling&&A.st.proj.room.ceiling.v?qSummary():'');
 }else if(step==='attach'){
  const opt=(t,h,op)=>'<div class="card q-step"><h3>'+at(t)+'</h3><div class="hint">'+at(h)+'</div><div class="row"><button class="btn pri" data-op="'+op+'">'+at('go')+'</button></div></div>';
  body='<h3 style="margin:6px 0">'+at('q_home')+'</h3>'+opt('o1','o1h','q_manual_mode')+opt('o2','o2h','q_image')+opt('o3','o3h','v_open');
 }else if(step==='calibrate'){
  body=qWrap('2/5',at('q_s2'),'<div class="hint">'+at('q_s2h')+'</div>'+imageHtmlQ()+
   '<div class="row"><label style="max-width:160px">'+at('mm')+'<input data-f="scmm" type="number" placeholder="'+at('q_mm_ph')+'" value="'+esc(F('scmm')||'')+'"></label>'+
   '<button class="btn sm" data-op="clearpts">'+at('clear')+'</button><button class="btn sm pri" data-op="q_calib_go">'+at('q_s2go')+'</button></div>');
 }else if(step==='trace'){
  body=qWrap('3/5',at('q_s3'),'<div class="hint">'+at('q_s3h')+'</div>'+imageHtmlQ()+
   '<div class="row"><button class="btn sm" data-op="q_undo">'+at('q_undo')+'</button><button class="btn sm" data-op="clearpts">'+at('clear')+'</button><button class="btn sm pri" data-op="q_trace_go" '+(A.trace.length<3?'disabled':'')+'>'+at('q_s3go')+'</button></div>');
 }else if(step==='ceiling'){
  body=qWrap('4/5',at('q_s4'),'<div class="hint">'+at('q_s4h')+'</div>'+
   '<div class="row"><label style="max-width:160px">'+at('ceil')+'<input data-f="qceil" type="number" value="'+esc(A.qceil)+'"></label><button class="btn sm pri" data-op="q_ceil_go">'+at('q_s4go')+'</button></div>');
 }else{ // summary
  body=qSummary();
 }
 c.innerHTML='<div id="asBusy"></div>'+qHeader()+'<div class="stg"><span class="on">'+at('q_quick')+'</span></div>'+body;
 bindQ();vBind();drawCanvas()};
function qSummary(){
 const p=A.st&&A.st.proj;const ws=(A.st&&A.st.walls)||[];const cl=p&&p.room&&p.room.ceiling;
 const rows=[];
 if(cl)rows.push(['ceiling',at('ceil'),Math.round(cl.v)+' mm',cl.st]);
 ws.forEach(w=>rows.push(['wall',at('q_wall')+' '+w.id,Math.round(w.len)+' mm',(p.room.poly_st)||'INFERRED']));
 const badge=st=>'<span class="ast '+(st==='CONFIRMED'?'CONFIRMED':'INFERRED')+'">'+(st==='CONFIRMED'?at('q_confirmed'):at('q_inferred'))+'</span>';
 const svcBadge=st=>'<span class="ast '+(st==='CONFIRMED'?'CONFIRMED':'INFERRED')+'">'+esc(st)+'</span>';
 const made=A.res.plan&&A.res.roots_made;
 let svcHtml='';
 if(made&&A.res.services){
  const pts=A.res.services.points||[];
  svcHtml='<div class="pv" style="margin-top:10px"><b>'+esc(at('q_svc_title'))+'</b>'+
   (pts.length?'<table style="margin-top:4px"><tr><th>'+at('q_svc_id')+'</th><th>'+at('q_svc_dev')+'</th><th>'+at('q_svc_unit')+'</th><th>'+at('q_svc_wall')+'</th><th>'+at('q_svc_off')+'</th><th>'+at('q_svc_z')+'</th><th></th></tr>'+
    pts.map(pt=>'<tr><td>'+esc(pt.id)+'</td><td>'+esc(pt.label)+'</td><td>'+esc(pt.unit)+'</td><td>'+esc(pt.wall)+'</td><td>'+Math.round(pt.off)+' mm</td><td>'+Math.round(pt.z)+' mm</td><td>'+svcBadge(pt.st)+'</td></tr>').join('')+
    '</table>':'<div class="hint">'+esc(at('q_svc_none'))+'</div>')+
   '<div class="hint" style="margin-top:6px">'+esc(at('q_svc_note'))+'</div></div>';
 }
 let h=qWrap('5/5',at('q_s5'),'<table>'+rows.map(r=>'<tr><td>'+esc(r[1])+'</td><td>'+esc(r[2])+'</td><td>'+badge(r[3])+'</td></tr>').join('')+'</table>'+
  '<div class="hint" style="margin-top:6px">'+at('q_note_openings')+'</div>'+
  (A.res.plan&&A.res.plan.problems&&A.res.plan.problems.length?'<div class="pv bad">'+A.res.plan.problems.map(pp=>esc(pp.code+': '+pp.message)).join('<br>')+'</div>':'')+
  '<div class="row" style="margin-top:8px"><button class="btn sm" data-op="q_start">'+at('q_start')+'</button><button class="btn pri" data-op="q_generate">'+at('q_gen')+'</button>'+'</div>'+optionsHtml()+'<div>'+
  (made?'<button class="btn sm" data-op="q_services">'+at('q_svc')+'</button>':'')+'</div>'+
  (made?'<div class="pv ok">'+esc(at('done'))+' ('+A.res.roots_made+')</div>':'')+svcHtml);
 return h;
}
function roomFromImage(){return A.st&&A.st.room_model&&A.st.room_model.source==='image'}
function qImage(){const s=A.v.set;return '<div class="row"><button class="btn sm" data-op="q_back">←</button></div>'+
 '<div class="card q-step" id="qImgCard"><h3><span class="chip">2</span> '+at('img_t')+'</h3><div class="hint">'+at('img_h')+'</div>'+
 (A.v.site?'<img src="'+A.v.site+'" style="max-width:100%;max-height:220px;border:1px solid var(--line);border-radius:8px;display:block;margin:6px 0">':'')+
 '<div class="row"><button class="btn '+(A.v.site?'sm':'pri')+'" data-op="q_image">'+(A.v.site?vt('change'):vt('pick'))+'</button>'+(A.v.site?'<button class="btn sm" data-op="v_run">'+vt('run')+'</button>':'')+'</div>'+
 '<div class="hint">'+(s&&s.has_key?vt('provnote'):vt('localnote'))+'</div>'+(A.v.err?'<div class="pv bad">'+esc(A.v.err)+'</div>':'')+
 '<div class="hint"><a href="#" data-op="q_markfb">'+vt('markfb')+'</a></div></div>'+
 (roomFromImage()?'<div class="card"><h3>'+at('img_next')+'</h3>'+optionsHtml()+'</div>':'')}
function imageHtmlQ(){if(!A.img)return '';return '<canvas id="asCv" width="640" height="440"></canvas>'}
function bindQ(){const c=$$('#asCol');c.querySelectorAll('[data-f]').forEach(e=>{const k=e.dataset.f;const h=()=>{if(k==='qceil')A.qceil=e.value;else A.form[k]=(e.type==='checkbox')?e.checked:e.value};e.oninput=h;e.onchange=h});
 c.querySelectorAll('[data-op]').forEach(b=>b.onclick=(ev)=>{ev.preventDefault();actQ(b.dataset.op)})}
function actQ(op){const f=A.form;
 if(op.indexOf('v_')===0)return actV(op);
 if(op==='q_toadv'){A.mode='advanced';return renderAssistTab()}
 if(op==='q_manual_mode'){A.qpath='manual';return renderAssistTab()}
 if(op==='q_back'){A.qpath=null;return renderAssistTab()}
 if(op==='q_manual_go'){if(!(+f.w>0&&+f.d>0&&+f.ceil>0))return toast(at('q_stop'),true);return call('assist_room',{w:+f.w,d:+f.d,ceiling:+f.ceil})}
 if(op==='q_image'){A.qpath='image';A.v.auto=true;if(!A.v.set)call('assist_vision_settings',{});return call('assist_vision_pick',{which:'site'})}
 if(op==='q_markfb'){A.qpath=null;A.v.auto=false;return call('assist_image',{})}
 if(op==='clearpts'){A.ref=[];A.trace=[];return renderAssistTab()}
 if(op==='q_undo'){A.trace.pop();return renderAssistTab()}
 if(op==='q_calib_go'){if(A.ref.length<2||!(+f.scmm>0))return toast(at('q_s2h'),true);return call('assist_scale',{ref:A.ref,mm:+f.scmm})}
 if(op==='q_trace_go'){if(A.trace.length<3)return toast(at('q_s3h'),true);return call('assist_trace',{points:A.trace})}
 if(op==='q_ceil_go'){if(!(+A.qceil>0))return toast(at('q_s4h'),true);return call('assist_ceiling',{ceiling:+A.qceil})}
 if(op==='q_generate')return call('assist_options',{opts:{layout:'auto',accept_inferred:true}});
 if(op.indexOf('acc_')===0){const x=((A.res.options||[]).find(y=>y.id===op.slice(4)));if(!x)return toast(at('noprop'),true);return call('assist_generate',{opts:Object.assign({},x.opts,{accepted:true,accept_inferred:true})})}
 if(op==='q_services')return call('assist_services',{})
 if(op==='q_start'){A.img=null;A.ref=[];A.trace=[];A.qpath=null;A.qceil='';A.res.plan=null;return renderAssistTab()}
}

/* ============================================================================================================
   AI PATH (quick mode): site image (+ optional design image) -> read by the user's vision provider -> the user
   reviews / corrects every number -> proposal -> build. Nothing is built before the review; the API key is typed
   by the user, stored on this computer and never shown again.
   ============================================================================================================ */
A.v={site:null,design:null,set:null,read:null,ceil:'',ok:false,plan:null,runs:null,built:0,err:null,showSet:false};
const VT={ar:{entry:'من الصور بالذكاء الاصطناعي',entryh:'ارفع صورة الموقع (عليها المقاسات) وصورة التصميم، والمساعد يقرأهما ويبني المطبخ.',title:'من الصور إلى المطبخ',
  s1:'١ · الصور',site:'صورة الموقع (عليها المقاسات)',siteh:'صورة فوتوغرافية، اسكتش يدوي، SketchUp أو كاد — المهم المقاسات مكتوبة عليها',design:'صورة التصميم (اختياري)',designh:'ريندر أو صورة للمطبخ المطلوب. بدونها المساعد يصمم بنفسه.',
  pick:'اختيار',change:'تغيير',del:'حذف',prov:'مزوّد الذكاء الاصطناعي',provider:'المزوّد',model:'الموديل',base:'رابط الخدمة (Base URL)',key:'مفتاح API',keyok:'محفوظ على هذا الجهاز ✓ (اكتب مفتاحاً جديداً للتغيير)',keyno:'اكتب المفتاح هنا',save:'حفظ الإعداد',
  nokey:'لم يُدخل مفتاح API بعد — افتح إعداد المزوّد',run:'حلّل الصور',running:'جارٍ تحليل المقاسات وشكل الغرفة…',needprov:'قراءة المقاسات من الصورة تلقائياً تحتاج مزوّد ذكاء اصطناعي (مفتاحك أنت). اكتب المفتاح ثم اضغط "حلّل الصور".',markfb:'بديل: تحديد الغرفة يدوياً على الصورة',localnote:'القراءة بتتم على الجهاز ده (التعرف على النصوص في ويندوز) - من غير مزوّد ذكاء اصطناعي. المزوّد اختياري لتحسين القراءة (خصوصاً خط اليد) من صفحة التصميم بالذكاء الاصطناعي.',provnote:'القراءة بمزوّد الذكاء الاصطناعي اللي اخترته.',roomok:'تم بناء الغرفة من المقاسات - راجعها تحت قبل أي تصميم',
  s2:'٢ · ما قرأته من الصور — راجع وصحّح قبل البناء',wall:'طول الحائط (مم)',ceil:'ارتفاع السقف (مم)',ceilh:'غير مكتوب على الصورة — اكتبه',win:'شباك',door:'باب',off:'من يسار الحائط',w:'العرض',sill:'الجلسة',h:'الارتفاع',
  written:'مكتوب على الصورة',derived:'محسوب من المقاسات',assumed:'افتراضي — راجعه',svc:'نقط خدمة ظاهرة في الصورة (مواضع تقريبية، تُراجع في الموقع)',units:'الوحدات من صورة التصميم (من اليسار لليمين)',apps:'الأجهزة ومقاساتها — اكتب العرض الحقيقي لكل جهاز (مم) قبل المقترح',appw:'عرض الجهاز (مم)',typed:'أدخلته أنت',generic:'مقاس عام — اكتب المقاس الحقيقي',nodesign:'لا توجد صورة تصميم — المساعد سيقترح التوزيع',
  ok:'راجعت المقاسات وهي صحيحة',propose:'اعرض المقترح',s3:'٣ · المقترح',build:'ابنِ المطبخ',built:'تم بناء المطبخ — الوحدات عادية وقابلة للتعديل، والإنتاج من تبويب الإنتاج',back:'← رجوع',again:'ابدأ من جديد',needceil:'اكتب ارتفاع السقف أولاً',needsite:'اختر صورة الموقع أولاً',
  U:{fridge:'ثلاجة',fridge_side_by_side:'ثلاجة بابين',tall_pantry:'وحدة طويلة',tall_oven:'عمود فرن',tall_oven_microwave:'عمود فرن وميكروويف',hob_oven:'بوتاجاز + فرن',hob:'بوتاجاز',oven_base:'فرن',sink:'حوض',dishwasher:'غسالة أطباق',washing_machine:'غسالة ملابس',drawers:'أدراج',doors:'ضلف',pullout_narrow:'سحّاب ضيق',open_shelves:'أرفف مفتوحة'},
  K:{elec:'كهرباء',water_cold:'مياه',drain:'صرف',gas:'غاز'}},
 en:{entry:'From images with AI',entryh:'Upload the site image (with dimensions) and the design image; the assistant reads both and builds the kitchen.',title:'From images to a kitchen',
  s1:'1 · Images',site:'Site image (with dimensions)',siteh:'Photo, hand sketch, SketchUp or CAD - the dimensions must be written on it',design:'Design image (optional)',designh:'Render or photo of the wanted kitchen. Without it the assistant designs by itself.',
  pick:'Choose',change:'Change',del:'Remove',prov:'AI provider',provider:'Provider',model:'Model',base:'Service URL (Base URL)',key:'API key',keyok:'stored on this computer ✓ (type a new key to change it)',keyno:'type the key here',save:'Save settings',
  nokey:'No API key yet - open the provider settings',run:'Analyse the images',running:'Analyzing dimensions and room geometry…',needprov:'Reading the dimensions from the image needs an AI provider (your own key). Type the key, then press "Analyse the images".',markfb:'Fallback: mark the room by hand on the image',localnote:'Read on this computer (Windows text recognition) - no AI provider needed. A provider is optional, to improve the reading (handwriting especially), from the AI design page.',provnote:'Read with the AI provider you configured.',roomok:'Room reconstructed from the dimensions - check it below before any design',
  s2:'2 · What I read from the images - check and correct before building',wall:'Wall length (mm)',ceil:'Ceiling height (mm)',ceilh:'not written on the image - type it',win:'Window',door:'Door',off:'From the left end',w:'Width',sill:'Sill',h:'Height',
  written:'written on the image',derived:'calculated from the dimensions',assumed:'assumed - check it',svc:'service points visible in the image (approximate positions, to be checked on site)',units:'Units from the design image (left to right)',apps:'Appliances and their sizes - type the real width of each appliance (mm) before the proposal',appw:'Appliance width (mm)',typed:'typed by you',generic:'generic size - type the real one',nodesign:'No design image - the assistant will propose the arrangement',
  ok:'I checked the dimensions and they are correct',propose:'Show the proposal',s3:'3 · Proposal',build:'Build the kitchen',built:'Kitchen built - ordinary editable units; production is in the Production tab',back:'← Back',again:'Start over',needceil:'Type the ceiling height first',needsite:'Choose the site image first',
  U:{fridge:'Fridge',fridge_side_by_side:'Side-by-side fridge',tall_pantry:'Tall unit',tall_oven:'Oven tower',tall_oven_microwave:'Oven + microwave tower',hob_oven:'Hob + oven',hob:'Hob',oven_base:'Oven',sink:'Sink',dishwasher:'Dishwasher',washing_machine:'Washing machine',drawers:'Drawers',doors:'Doors',pullout_narrow:'Narrow pull-out',open_shelves:'Open shelves'},
  K:{elec:'Electrical',water_cold:'Water',drain:'Drain',gas:'Gas'}}};
const vt=k=>(VT[S.lang]||VT.en)[k]||VT.en[k]||k;
function vEntry(){return '<div class="card q-step" style="border:2px solid var(--acc)"><h3><span class="chip">AI</span> '+vt('entry')+'</h3><div class="hint">'+vt('entryh')+'</div><div class="row"><button class="btn pri" data-op="v_open">'+vt('entry')+'</button></div></div>'}
function vImg(which){const d=A.v[which];return '<div style="flex:1 1 260px;min-width:0"><b>'+vt(which)+'</b><div class="hint">'+vt(which+'h')+'</div>'+(d?'<img src="'+d+'" style="max-width:100%;max-height:220px;border:1px solid var(--line);border-radius:8px;display:block;margin:6px 0">':'')+
  '<div class="row"><button class="btn sm'+(d?'':' pri')+'" data-op="v_pick_'+which+'">'+(d?vt('change'):vt('pick'))+'</button>'+(d&&which==='design'?'<button class="btn sm" data-op="v_del_design">'+vt('del')+'</button>':'')+'</div></div>'}
function vSettings(){const s=A.v.set;if(!s)return '';const p=s.providers.find(x=>x.id===s.provider)||{};const open=A.v.showSet||!s.has_key;
  return '<details '+(open?'open':'')+'><summary><b>'+vt('prov')+'</b> — '+esc(p.label||'')+' · '+esc(s.model||'')+' '+(s.has_key?'<span class="ok">✓</span>':'<span class="bad">'+vt('nokey')+'</span>')+'</summary>'+
  '<div class="row"><label>'+vt('provider')+'<select id="vProv">'+s.providers.map(x=>'<option value="'+x.id+'" '+(x.id===s.provider?'selected':'')+'>'+esc(x.label)+'</option>').join('')+'</select></label>'+
  '<label>'+vt('model')+'<input id="vModel" type="text" dir="ltr" value="'+esc(s.model)+'"></label></div>'+
  '<div class="row"><label style="flex:2 1 260px">'+vt('base')+'<input id="vBase" type="text" dir="ltr" value="'+esc(s.base)+'"></label></div>'+
  '<div class="row"><label style="flex:2 1 260px">'+vt('key')+'<input id="vKey" type="password" dir="ltr" autocomplete="off" placeholder="'+(s.has_key?vt('keyok'):vt('keyno'))+'"></label><button class="btn sm" data-op="v_saveset">'+vt('save')+'</button></div></details>'}
function vBadge(src){const c=src==='written'?'CONFIRMED':(src==='derived'?'INFERRED':'REQUIRES_CONFIRMATION');return '<span class="ast '+c+'">'+vt(src||'assumed')+'</span>'}
function vNum(path,val){return '<input data-v="'+path+'" type="number" style="max-width:110px" value="'+(val==null?'':esc(Math.round(val)))+'">'}
function vRead(){const r=A.v.read;if(!r)return '';const s=r.site;let h='<table><tr><td>'+vt('wall')+'</td><td>'+vNum('wall',s.wall)+'</td><td>'+vBadge(s.wall?'written':'assumed')+'</td></tr>'+
  '<tr><td>'+vt('ceil')+'</td><td><input data-v="ceil" type="number" style="max-width:110px" value="'+esc(A.v.ceil)+'"></td><td>'+(s.ceiling?vBadge('written'):'<span class="bad">'+vt('ceilh')+'</span>')+'</td></tr></table>';
  s.openings.forEach((o,i)=>{const sr=o.src||{};h+='<div class="pv"><b>'+(o.type==='door'?vt('door'):vt('win'))+' '+(i+1)+'</b><table>'+
   '<tr><td>'+vt('off')+'</td><td>'+vNum('o.'+i+'.off',o.off)+'</td><td>'+vBadge(sr.off)+'</td></tr><tr><td>'+vt('w')+'</td><td>'+vNum('o.'+i+'.w',o.w)+'</td><td>'+vBadge(sr.w)+'</td></tr>'+
   '<tr><td>'+vt('sill')+'</td><td>'+vNum('o.'+i+'.sill',o.sill)+'</td><td>'+vBadge(sr.sill)+'</td></tr><tr><td>'+vt('h')+'</td><td>'+vNum('o.'+i+'.h',o.h)+'</td><td>'+vBadge(sr.h)+'</td></tr></table></div>'});
  if(r.problems&&r.problems.length)h+='<div class="pv bad">'+r.problems.map(p=>esc(p.code+': '+p.message)).join('<br>')+'</div>';
  if(s.services.length){const n={};s.services.forEach(x=>n[x.kind]=(n[x.kind]||0)+1);h+='<div class="hint">'+s.services.length+' '+vt('svc')+': '+Object.keys(n).map(k=>((vt('K')||{})[k]||k)+' ×'+n[k]).join(' · ')+'</div>'}
  const apps=(r.design?r.design.units:[]).map((u,i)=>[u,i]).filter(x=>x[0].app);
  if(apps.length)h+='<div class="pv"><b>'+vt('apps')+'</b><table>'+apps.map(x=>'<tr><td>'+esc((vt('U')||{})[x[0].type]||x[0].type)+'</td><td>'+vNum('u.'+x[1]+'.w',x[0].w)+'</td><td>'+(x[0].w_src==='typed'?'<span class="ast CONFIRMED">'+vt('typed')+'</span>':(x[0].w_src==='written'?vBadge('written'):'<span class="ast REQUIRES_CONFIRMATION">'+vt('generic')+'</span>'))+'</td></tr>').join('')+'</table></div>';
  h+=(r.design&&r.design.units.length)?'<div style="margin-top:8px"><b>'+vt('units')+'</b><div class="stg">'+r.design.units.map(u=>'<span>'+esc((vt('U')||{})[u.type]||u.type)+'</span>').join('')+'</div></div>':'<div class="hint">'+vt('nodesign')+'</div>';
  h+='<div class="row"><label class="chk"><input id="vOk" type="checkbox" '+(A.v.ok?'checked':'')+'>'+vt('ok')+'</label><button class="btn pri" data-op="v_apply">'+vt('propose')+'</button></div>';return h}
const VC={ar:{fridge_open:'ثلاجة',pantry:'وحدة طويلة',oven_tall:'عمود فرن',oven_tower:'عمود فرن وميكروويف',hob_oven:'بوتاجاز + فرن',hob:'بوتاجاز',oven:'فرن',sink:'حوض',dishwasher:'غسالة أطباق',washer:'غسالة ملابس',drawers3:'أدراج',doors:'ضلف','mech:SPICE_PULLOUT':'سحّاب',open:'أرفف مفتوحة',filler:'فيلر'},
 en:{fridge_open:'Fridge',pantry:'Tall unit',oven_tall:'Oven tower',oven_tower:'Oven + microwave tower',hob_oven:'Hob + oven',hob:'Hob',oven:'Oven',sink:'Sink',dishwasher:'Dishwasher',washer:'Washing machine',drawers3:'Drawers',doors:'Doors','mech:SPICE_PULLOUT':'Pull-out',open:'Open shelves',filler:'Filler'}};
function vCol(c){const i=c.lastIndexOf(' ');const t=c.slice(0,i),w=c.slice(i+1);return '<span style="display:inline-block;border:1px solid var(--line);border-radius:6px;padding:2px 8px;margin:2px;background:#fff">'+esc(((VC[S.lang]||VC.en)[t])||t)+' <b dir="ltr">'+esc(w)+'</b></span>'}
function vPlan(){if(!A.v.plan)return '';const p=A.v.plan;const bad=p.problems&&p.problems.length;
  return qWrap('3',vt('s3'),'<div class="pv"><b>'+esc(p.layout||'')+'</b><br>'+(A.v.runs||[]).map(r=>Object.keys(r).map(k=>r[k].cols.map(vCol).join('')+' <small dir="ltr">= '+Math.round(r[k].len)+' mm</small>').join('<br>')).join('<br>')+
   ((p.notes||[]).length?'<br><small>'+p.notes.map(esc).join('<br>')+'</small>':'')+(bad?'<br><span class="bad">'+p.problems.map(x=>esc(x.code+': '+x.message)).join('<br>')+'</span>':'')+'</div>'+
   '<div class="row"><button class="btn pri" data-op="v_build" '+(bad?'disabled':'')+'>'+vt('build')+'</button></div>'+(A.v.built?'<div class="pv ok">'+vt('built')+'</div>':''))}
function qAi(){return '<div class="row"><button class="btn sm" data-op="v_back">'+vt('back')+'</button><button class="btn sm" data-op="v_again">'+vt('again')+'</button></div>'+
  qWrap('1',vt('s1'),'<div class="row" style="align-items:flex-start">'+vImg('site')+vImg('design')+'</div>'+vSettings()+(A.v.err?'<div class="pv bad">'+esc(A.v.err)+'</div>':'')+
   '<div class="row"><button class="btn pri" data-op="v_run" '+(A.v.site?'':'disabled')+'>'+vt('run')+'</button></div>')+
  (A.v.site&&A.v.set&&!A.v.set.has_key?'<div class="pv bad">'+vt('needprov')+'</div>':'')+'<div class="hint"><a href="#" data-op="q_markfb">'+vt('markfb')+'</a></div>'+
  (A.v.read&&A.v.read.site.view==='room'?'<div class="pv ok">'+vt('roomok')+'</div>':(A.v.read?qWrap('2',vt('s2'),vRead()):''))+vPlan()+
  (roomFromImage()?'<div class="card">'+optionsHtml()+'</div>':'')}
function vCollect(){const r=A.v.read;if(!r)return;document.querySelectorAll('#asCol [data-v]').forEach(e=>{const k=e.dataset.v,v=e.value===''?null:+e.value;
  if(k==='wall')r.site.wall=v;else if(k==='ceil')A.v.ceil=e.value;else if(k.charAt(0)==='u'){const u=r.design.units[+k.split('.')[1]];if(u&&v&&Math.round(u.w)!==v){u.w=v;u.w_src='typed'}}else{const m=k.split('.');const o=r.site.openings[+m[1]];if(o&&o[m[2]]!==v){o[m[2]]=v;(o.src=o.src||{})[m[2]]='written'}}});
  const ok=document.getElementById('vOk');if(ok)A.v.ok=ok.checked}
function actV(op){
  if(op==='v_open'){A.qpath='ai';if(!A.v.set)return call('assist_vision_settings',{});return renderAssistTab()}
  if(op==='v_back'){vCollect();A.qpath=null;return renderAssistTab()}
  if(op==='v_again'){const set=A.v.set;A.v={site:null,design:null,set:set,read:null,ceil:'',ok:false,plan:null,runs:null,built:0,err:null,showSet:false};call('assist_vision_pick',{which:'site',clear:true});return call('assist_vision_pick',{which:'design',clear:true})}
  if(op==='v_pick_site'||op==='v_pick_design'){vCollect();return call('assist_vision_pick',{which:op.slice(7)})}
  if(op==='v_del_design'){vCollect();return call('assist_vision_pick',{which:'design',clear:true})}
  if(op==='v_saveset'){vCollect();A.v.showSet=true;const set={provider:$$('#vProv').value,model:$$('#vModel').value,base:$$('#vBase').value,key:$$('#vKey').value};return call('assist_vision_settings',{set:set})}
  if(op==='v_run'){vCollect();if(!A.v.site)return toast(vt('needsite'),true);A.v.err=null;return call('assist_vision_run',{},vt('running'))}
  if(op==='v_apply'){vCollect();if(!(+A.v.ceil>0))return toast(vt('needceil'),true);A.v.built=0;return call('assist_vision_apply',{read:A.v.read,confirmed:A.v.ok,ceiling:+A.v.ceil})}
  if(op==='v_build'){vCollect();return call('assist_generate',{opts:{accepted:true,accept_inferred:true,from_vision:true}})}}
function onVision(op,d){
  if(d.vision_settings){const prev=A.v.set;A.v.set=d.vision_settings;if(prev&&prev.provider!==d.vision_settings.provider)A.v.showSet=true}
  if(d.vision_image){A.v[d.vision_image.which]=d.vision_image.data;A.v.read=null;A.v.plan=null;A.v.built=0;
   if(A.v.auto&&d.vision_image.which==='site'&&d.vision_image.data){A.v.auto=false;setTimeout(()=>call('assist_vision_run',{},vt('running')),0)}}
  if(d.vision_result){if(d.vision_result.ok){A.v.read=d.vision_result.read;A.v.err=null;A.v.plan=null;A.v.ok=false;const c=A.v.read.site.ceiling;if(c)A.v.ceil=Math.round(c)}else{A.v.err=d.vision_result.message;toast(d.vision_result.message,true)}}
  if(d.vision_applied){A.v.plan=d.plan;A.v.runs=d.runs}
  if(op==='assist_generate'&&A.qpath==='ai'&&d.made)A.v.built=d.made}
function vBind(){const vp=$$('#vProv');if(!vp||!A.v.set)return;vp.onchange=()=>{const x=A.v.set.providers.find(q=>q.id===vp.value)||{};$$('#vModel').value=x.model||'';$$('#vBase').value=x.base||''}}
/* ---- room model check, visual A/B/C proposals, change impact, production gate, render source ---- */
const R2={ar:{room:'١ · الغرفة المقروءة (راجعها قبل أي اقتراح)',read:'اقرأ الغرفة من موديل SketchUp',src:'المصدر',item:'البند',val:'القيمة (مم)',st:'الحالة',roomblocked:'لا يمكن عرض مقترحات قبل استكمال قياسات الغرفة أو تأكيدها. راجع القياسات المعلّقة بالأعلى.',
  ready:'الغرفة جاهزة للاقتراحات',notready:'فيه قيم لازم تتأكد منها قبل الاقتراحات',dims:'الأبعاد المكتوبة',std:'تصميم قياسي (بدون ذكاء اصطناعي)',ai:'تصميم بالذكاء الاصطناعي',
  score:'الدرجة',why:'ليه الاقتراح ده',acc:'اعتماد وبناء',reject:'رفض الكل',back:'رجوع لتعديل القيود',plan:'مسقط',elev:'واجهة',axo:'منظور',units:'الوحدات',
  temp:'معاينة مؤقتة - مش موديل إنتاج',impact:'أثر التعديل',gate:'بوابة سلامة الإنتاج',rungate:'افحص قبل التصدير النهائي',render:'مصدر الرندر من التصميم المعتمد',
  pass:'مسموح بالتصدير النهائي',ask:'محتاج تأكيدك على دول بس',val:'التحقق الهندسي للتوزيع',notconf:'لسه مش كله مؤكد',qconfirm:'تأكيد',qedit:'تعديل القيمة',qreread:'إعادة قراءة الصورة',qsave:'حفظ',chk:'فحوصات المقاسات',clr:'المسافات',style:'اتجاه الواجهات',wall:'الحائط',type:'النوع',editp:'تعديل الاقتراح قبل البناء',applyed:'طبّق التعديل على الاقتراح',blocked:'التصدير النهائي ممنوع',crit:{space:'استغلال المساحة',workflow:'سهولة الحركة',appliances:'الأجهزة',clearance:'المسافات الآمنة',storage:'التخزين',manufacturing:'سهولة التصنيع',user:'طلباتك'}},
 en:{room:'1 · Room as read (check it before any proposal)',read:'Read the room from the SketchUp model',src:'Source',item:'Item',val:'Value (mm)',st:'Status',roomblocked:'Design proposals are blocked until missing or uncertain room measurements are completed or confirmed above.',
  ready:'Room ready for proposals',notready:'Some values must be confirmed before proposals',dims:'Printed dimensions',std:'Standard design (no AI)',ai:'AI design',
  score:'Score',why:'Why this proposal',acc:'Approve and build',reject:'Reject all',back:'Back to the constraints',plan:'Plan',elev:'Elevation',axo:'3D',units:'Units',
  temp:'temporary preview - not production geometry',impact:'Change impact',gate:'Production integrity gate',rungate:'Check before final export',render:'Render source from the approved design',
  pass:'final export allowed',ask:'Only these need your answer',val:'Layout engineering validation',notconf:'not all confirmed yet',qconfirm:'Confirm',qedit:'Edit value',qreread:'Re-read the image',qsave:'Save',chk:'Dimension checks',clr:'Clearances',style:'Front direction',wall:'Wall',type:'Type',editp:'edit the proposal before building',applyed:'Apply edits to this proposal',blocked:'final export BLOCKED',crit:{space:'space use',workflow:'workflow',appliances:'appliances',clearance:'clearances',storage:'storage',manufacturing:'manufacturing',user:'your constraints'}}};
const r2=k=>(R2[S.lang]||R2.en)[k];
const badge=st=>'<span class="ast '+esc(st||'INFERRED')+'">'+esc(st||'')+'</span>';
function egcRoomHtml(){const rm=A.st&&A.st.room_model;let h='<div class="card"><h3>'+r2('room')+'</h3><div class="row"><button class="btn sm" data-x="rm_read">'+r2('read')+'</button></div>';
 if(!rm)return h+'</div>';
 h+='<div class="'+(rm.ready?'pv ok':'pv bad')+'">'+(rm.ready?r2('ready'):r2('notready'))+(rm.ready&&!rm.confirmed&&(rm.pending||[]).length?' · <span class="bad">'+r2('notconf')+': '+rm.pending.map(esc).join(', ')+'</span>':'')+' · '+esc(rm.source)+(rm.status?' · '+esc(rm.status):'')+(rm.type?' · '+esc(rm.type):'')+(rm.engine?' · '+esc(rm.engine):'')+(rm.mock?' · <b>MOCK</b>':'')+'</div><div style="display:flex;gap:6px;flex-wrap:wrap"><div style="flex:1 1 260px;min-width:0">'+rm.svg+'</div></div>';
 h+='<table><tr><th>'+r2('item')+'</th><th>'+r2('val')+'</th><th>'+r2('st')+'</th><th>'+r2('src')+'</th></tr>'+rm.rows.map(r=>'<tr><td>'+esc(r.item)+'</td><td>'+(r.edit&&r.key?'<input data-rm="'+esc(r.key)+'" type="number" style="max-width:96px" value="'+(r.value==null?'':Math.round(r.value))+'">':(r.value==null?'-':Math.round(r.value)))+'</td><td>'+badge(r.st)+'</td><td><small>'+esc(r.src||'')+'</small></td></tr>').join('')+'</table>';
 if(rm.dims&&rm.dims.length)h+='<details><summary>'+r2('dims')+' ('+rm.dims.length+')</summary><table>'+rm.dims.map(d=>'<tr><td dir="ltr">'+esc(d.text)+'</td><td>'+esc(d.what||'')+'</td><td>'+badge(d.st)+'</td></tr>').join('')+'</table></details>';
 if(rm.problems&&rm.problems.length)h+='<div class="pv bad">'+rm.problems.map(p=>esc(p.code+': '+p.message)).join('<br>')+'</div>';
 if(rm.questions&&rm.questions.length)h+='<div class="pv" style="border:2px solid var(--acc)"><b>'+r2('ask')+'</b>'+rm.questions.map(q=>{const k=esc(q.key);let c;
   if(q.choices)c='<select data-rm="'+k+'"><option value=""></option>'+q.choices.map(x=>'<option>'+esc(x)+'</option>').join('')+'</select>';
   else if(/^dim:[^:]+:value$/.test(q.key)&&q.value!=null)c='<button class="btn sm pri" data-qc="'+k+'">'+r2('qconfirm')+' '+Math.round(q.value)+' mm</button><button class="btn sm" data-qe="'+k+'">'+r2('qedit')+'</button><button class="btn sm" data-x="reread">'+r2('qreread')+'</button>'+
    '<span data-qbox="'+k+'" style="display:none"><input data-qi="'+k+'" type="number" style="max-width:96px" value="'+Math.round(q.value)+'"> mm <button class="btn sm pri" data-qs="'+k+'">'+r2('qsave')+'</button></span>';
   else c='<input data-qi="'+k+'" type="number" style="max-width:96px" value="'+(q.value==null?'':Math.round(q.value))+'"> mm <button class="btn sm pri" data-qs="'+k+'">'+r2('qsave')+'</button>';
   return '<div class="row" style="align-items:center;flex-wrap:wrap;gap:6px;margin-top:6px"><span style="flex:2 1 260px"><b>'+esc(q.text)+'</b></span>'+c+'</div>'}).join('')+'</div>';
 if(rm.checks&&rm.checks.length)h+='<details><summary>'+r2('chk')+' ('+rm.checks.filter(c=>c.result==='PASS').length+'/'+rm.checks.length+' PASS)</summary><table>'+rm.checks.map(c=>'<tr><td>'+badge(c.result==='PASS'?'CONFIRMED':(c.result==='FAIL'?'REQUIRES_CONFIRMATION':'INFERRED'))+' '+esc(c.result)+'</td><td dir="ltr">'+esc(c.check)+'</td><td><small>'+esc(c.detail||'')+'</small></td></tr>').join('')+'</table></details>';
 return h+'</div>'};
optionsHtml=function(){const o=A.res.options;let h='<div class="row"><button class="btn sm'+(A.res.omode!=='ai'?' pri':'')+'" data-x="opt_std">'+r2('std')+'</button><button class="btn sm'+(A.res.omode==='ai'?' pri':'')+'" data-x="opt_ai">'+r2('ai')+'</button></div>';
 if(A.res.onote)h+='<div class="hint">'+esc(A.res.onote)+'</div>';if(!o||!o.length)return h;
 h+='<div class="hint">'+r2('temp')+'</div>';
 h+=o.map(x=>{const p=x.preview||{};const bars=Object.keys(x.scores||{}).map(k=>'<div style="display:flex;gap:4px;align-items:center;font-size:11px"><span style="flex:0 0 110px">'+esc(r2('crit')[k]||k)+'</span><span style="flex:1;background:#eee;height:7px;border-radius:4px"><span style="display:block;height:7px;border-radius:4px;background:var(--acc);width:'+x.scores[k]+'%"></span></span><span style="flex:0 0 28px">'+x.scores[k]+'</span></div>').join('');
  return '<div class="pv" style="margin-top:8px"><div class="row" style="justify-content:space-between"><b>'+esc(x.id)+' · '+esc(x.label)+'</b><span class="chip">'+r2('score')+' '+x.score+'/100</span></div>'+
   '<div style="display:flex;gap:10px;flex-wrap:wrap;align-items:flex-start"><div class="pcmd" style="flex:1 1 250px;min-width:230px;max-width:400px">'+
   '<div class="row"><button class="btn sm pri" data-op="acc_'+esc(x.id)+'" '+(x.buildable?'':'disabled')+'>'+r2('acc')+' '+esc(x.id)+'</button></div>'+
   '<div style="margin-top:4px">'+bars+'</div><details><summary>'+r2('why')+'</summary><ul>'+(x.why||[]).map(w=>'<li>'+esc(w)+'</li>').join('')+'</ul><small class="bad">'+(x.unresolved||[]).map(esc).join(' | ')+'</small></details>'+
   (p.validation?'<div class="'+(p.validation.ok?'pv ok':'pv bad')+'" style="padding:3px 6px;margin:4px 0"><small><b>'+r2('val')+'</b>: '+p.validation.checks.map(c=>esc(c.code)+' '+(c.result==='PASS'?'✓':'✗ '+esc(c.detail||''))).join(' · ')+'</small></div>':'')+
   unitTable(x)+(p.clearances&&p.clearances.length?'<div><small><b>'+r2('clr')+'</b>: '+p.clearances.map(c=>esc(c.what+' '+c.mm+' mm')).join(' · ')+'</small></div>':'')+(p.style?'<div><small><b>'+r2('style')+'</b>: '+esc(p.style.front+' · '+p.style.handle)+' <span style="display:inline-block;width:12px;height:12px;vertical-align:middle;border:1px solid #888;background:'+esc(p.style.color)+'"></span> <i>'+esc(p.style.source)+'</i></small></div>':'')+(x.edited&&x.problems&&x.problems.length?'<div class="pv bad">'+x.problems.map(q=>esc(q.code+': '+q.message)).join('<br>')+'</div>':'')+
   '</div><div class="pdraw" dir="ltr" style="flex:3 1 420px;min-width:0"><div style="display:flex;gap:6px;flex-wrap:wrap"><div style="flex:1 1 200px;min-width:0"><small>'+r2('plan')+'</small>'+(p.plan||'')+'</div><div style="flex:1 1 220px;min-width:0"><small>'+r2('axo')+'</small>'+(p.axo||'')+'</div></div>'+
   (p.elevations||[]).map(s=>'<div><small>'+r2('elev')+'</small>'+s+'</div>').join('')+'</div></div></div>'}).join('');
 return h+'<div class="row"><button class="btn sm" data-x="opt_reject">'+r2('reject')+'</button><button class="btn sm" data-x="opt_back">'+r2('back')+'</button></div>'};
const STORE=['doors','drawers2','drawers3','drawers4','open'];
function unitTable(x){const us=(x.preview||{}).units||[];return '<details'+(x.edited?' open':'')+'><summary>'+r2('units')+' ('+us.length+') · '+r2('editp')+'</summary><table><tr><th>ID</th><th>'+r2('wall')+'</th><th>'+r2('type')+'</th><th>W</th><th>D</th></tr>'+us.map(u=>{const st=!u.app&&STORE.indexOf(u.type)>=0;const k=esc(x.id)+'|'+esc(u.id);return '<tr><td><b>'+esc(u.id)+'</b></td><td>'+esc(u.wall||'')+'</td><td>'+(st?'<select data-oe="'+k+'|t">'+STORE.map(t=>'<option'+(t===u.type?' selected':'')+'>'+t+'</option>').join('')+'</select>':esc(u.app||u.type))+'</td><td>'+(st?'<input data-oe="'+k+'|w" type="number" step="50" style="max-width:72px" value="'+u.w+'">':u.w)+'</td><td>'+u.d+'</td></tr>'}).join('')+'</table><div class="row"><button class="btn sm" data-x="oed_'+esc(x.id)+'">'+r2('applyed')+'</button></div></details>'}
function impactHtml(){const i=A.res.impact;if(!i)return '';return '<div class="pv ok"><b>'+r2('impact')+'</b><br>'+i.lines.map(esc).join('<br>')+'</div>'}
function gateHtml(){const g=A.res.gate;let h='<div class="card"><h3>'+r2('gate')+'</h3><div class="row"><button class="btn sm" data-x="gate">'+r2('rungate')+'</button><button class="btn sm" data-x="render">'+r2('render')+'</button></div>';
 if(g)h+='<div class="'+(g.ok?'pv ok':'pv bad')+'"><b>'+(g.ok?r2('pass'):r2('blocked'))+'</b></div><table>'+g.checks.map(c=>'<tr><td>'+badge(c.status==='PASS'?'CONFIRMED':(c.status==='WARNING'?'INFERRED':'REQUIRES_CONFIRMATION'))+' '+esc(c.status)+'</td><td>'+esc(c.check)+'</td><td><small>'+esc(c.detail||'')+'</small></td></tr>').join('')+'</table>';
 return h+'</div>'}
function x2(op){if(op==='rm_read')return call('assist_room_read',{});
 if(op==='opt_std'||op==='opt_ai'){A.res.omode=op==='opt_ai'?'ai':'standard';return call('assist_options',{opts:{mode:A.res.omode,accept_inferred:true}})}
 if(op==='opt_reject'){A.res.options=null;return renderAssistTab()}
 if(op==='opt_back'){A.res.options=null;renderAssistTab();const r=document.querySelector('[data-rm]');if(r)r.scrollIntoView();return}
 if(op.indexOf('oed_')===0){const id=op.slice(4);const x=(A.res.options||[]).find(y=>y.id===id);if(!x)return;const us=(x.preview||{}).units||[];const ed=((x.opts||{}).edits||[]).slice();
  document.querySelectorAll('[data-oe^="'+id+'|"]').forEach(e=>{const [,uid,key]=e.dataset.oe.split('|');const u=us.find(v=>v.id===uid);if(!u)return;const val=key==='w'?parseFloat(e.value):e.value;if(key==='w'?Math.abs(val-u.w)<0.5:val===u.type)return;const rec={id:uid};rec[key]=val;ed.push(rec)});
  return call('assist_option_edit',{id:id,opts:Object.assign({},x.opts,{edits:ed})})}
 if(op==='reread')return call('assist_vision_run',{},vt('running'));
 if(op==='gate')return call('assist_gate',{});
 if(op==='render')return call('assist_render_pack',{})}
function inject(){const c=$$('#asCol');if(!c)return;
 c.querySelectorAll('.egc-x').forEach(e=>e.remove());
 const room=document.createElement('div');room.className='egc-x';room.innerHTML=egcRoomHtml()+(A.st&&A.st.room_model&&!c.querySelector('[data-x="opt_std"]')?'<div class="card">'+optionsHtml()+'</div>':'');
 const anchor=c.querySelector('#qImgCard');const first=c.querySelector('.card');if(anchor)anchor.after(room);else if(first&&first.parentNode)first.parentNode.insertBefore(room,first);else c.appendChild(room);
 const tail=document.createElement('div');tail.className='egc-x';tail.innerHTML=impactHtml()+gateHtml();c.appendChild(tail);
 c.querySelectorAll('[data-x]').forEach(b=>b.onclick=ev=>{ev.preventDefault();x2(b.dataset.x)});
 c.querySelectorAll('[data-qc]').forEach(b=>b.onclick=ev=>{ev.preventDefault();call('assist_room_fix',{key:b.dataset.qc.replace(/:value$/,':confirm'),value:true})});
 c.querySelectorAll('[data-qe]').forEach(b=>b.onclick=ev=>{ev.preventDefault();const s=c.querySelector('[data-qbox="'+b.dataset.qe+'"]');if(s){s.style.display='inline';const i=s.querySelector('input');if(i)i.focus()}});
 c.querySelectorAll('[data-qs]').forEach(b=>b.onclick=ev=>{ev.preventDefault();const i=c.querySelector('[data-qi="'+b.dataset.qs+'"]');const v=i&&parseFloat(i.value);if(!(v>0))return toast(r2('qsave')+': mm > 0',true);call('assist_room_fix',{key:b.dataset.qs,value:v})});
 c.querySelectorAll('[data-rm]').forEach(e=>e.onchange=()=>{if(e.value==='')return;call('assist_room_fix',{key:e.dataset.rm,value:e.tagName==='SELECT'?e.value:parseFloat(e.value)})});
 c.querySelectorAll('[data-op^="acc_"]').forEach(b=>{if(!b.onclick)b.onclick=()=>act(b.dataset.op)})}
const _rt=renderAssistTab;renderAssistTab=function(){_rt();inject()};
const _oa=onAssist;onAssist=function(op,d){if(op==='assist_options'){A.res.onote=d.note;A.res.omode=d.mode}
 if(op==='assist_cmd_apply')A.res.impact=d.impact||null;
 if(op==='assist_option_edit'&&d.option){busy('');A.res.options=(A.res.options||[]).map(y=>y.id===d.option.id?d.option:y);renderAssistTab();return}if(op==='assist_gate')A.res.gate=d.gate;
 if(op==='assist_render_pack'||op==='assist_gate'||op==='assist_room_read'||op==='assist_room_fix'){busy('');if(d.proj)A.st=d;renderAssistTab();return}
 if(op==='assist_vision_run'&&d.proj)A.st=d;
 _oa(op,d);inject()};

})();
