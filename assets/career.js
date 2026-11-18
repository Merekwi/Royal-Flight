
(function(){
'use strict';
const api=()=>window.RoyalFlightApp;
const $=id=>document.getElementById(id);
const labels={draft:'Черновик',open:'Приём открыт',closed:'Приём закрыт',archived:'В архиве',submitted:'Отправлена',reviewing:'На рассмотрении',interview:'Собеседование',accepted:'Одобрена',rejected:'Отклонена'};
const types={text:'Короткий текст',textarea:'Развёрнутый ответ',email:'Электронная почта',number:'Число',date:'Дата',url:'Ссылка',select:'Один вариант',multiselect:'Несколько вариантов',yesno:'Да / Нет'};
let builder=null;
const esc=v=>api().esc(v);
const when=v=>v?new Date(v).toLocaleString('ru-RU',{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'}):'Без срока';
const status=v=>'career-status career-status-'+String(v||'').replace(/[^a-z_]/g,'');
const schemaOf=f=>f&&f.schema&&Array.isArray(f.schema.sections)?f.schema:{sections:[]};
const uid=()=>window.crypto?.randomUUID?crypto.randomUUID().replace(/-/g,''):('q'+Date.now().toString(36)+Math.random().toString(36).slice(2,9));
const empty=(a,b)=>'<div class="career-empty"><span>✧</span><strong>'+esc(a)+'</strong><p>'+esc(b)+'</p></div>';
const fieldsOf=s=>(s.sections||[]).flatMap(x=>x.fields||[]);
function conditionMatches(rule,answers){
 if(!rule||!rule.fieldId)return true;
 if(!Object.prototype.hasOwnProperty.call(answers,rule.fieldId))return false;
 const value=answers[rule.fieldId];
 const matched=Array.isArray(value)?value.map(String).includes(String(rule.value)):String(value??'')===String(rule.value);
 return rule.operator==='not_equals'?!matched:matched;
}
function pruneHiddenAnswers(form,answers){
 const schema=schemaOf(form),visible=new Set(),known=new Set();
 schema.sections.forEach(section=>{
  const sectionVisible=conditionMatches(section.visibleWhen,answers);
  (section.fields||[]).forEach(field=>{
   known.add(field.id);
   if(sectionVisible&&conditionMatches(field.visibleWhen,answers))visible.add(field.id);
   else delete answers[field.id];
  });
 });
 Object.keys(answers).forEach(id=>{if(!known.has(id)||!visible.has(id))delete answers[id]});
}
function visibleItems(form,answers){
 pruneHiddenAnswers(form,answers);
 const out=[];schemaOf(form).sections.forEach(section=>{
  if(!conditionMatches(section.visibleWhen,answers))return;
  out.push({section});
  (section.fields||[]).forEach(field=>{if(conditionMatches(field.visibleWhen,answers))out.push({field})});
 });return out;
}
function render(data){
 if(!data)return;
 renderOpen(data.careerForms||[],data.myCareerApplications||[]);
 renderMine(data.myCareerApplications||[]);
 renderAdmin(data.admin);
}
function renderOpen(forms,apps){
 const host=$('careerOpenings');if(!host)return;
 const applied=new Set(apps.map(x=>x.form_id));
 const open=forms.filter(f=>f.status==='open'&&(!f.closes_at||Date.parse(f.closes_at)>Date.now()));
 if($('careerOpenCount'))$('careerOpenCount').textContent=open.length+' открыто';
 if(!open.length){host.innerHTML=empty('Сейчас нет открытого набора','Новые вакансии появятся здесь, когда администрация '+api().getAirlineName()+' откроет приём заявок.');return}
 host.innerHTML='<div class="career-opening-grid">'+open.map(f=>{
  const count=fieldsOf(schemaOf(f)).length;
  return '<article class="career-opening-card"><div class="career-opening-top"><span class="career-department">'+esc(f.department||api().getAirlineName())+'</span><span class="'+status('open')+'">НАБОР ОТКРЫТ</span></div><h3>'+esc(f.title)+'</h3><p>'+esc(f.description||'Администрация ждёт вашу анкету.')+'</p><div class="career-opening-meta"><span>▤ '+count+' вопросов</span><span>◷ '+esc(f.closes_at?'До '+when(f.closes_at):'Срок не ограничен')+'</span></div><div class="career-opening-actions">'+(applied.has(f.id)?'<button class="secondary-button" disabled>Заявка уже отправлена</button>':'<button class="primary-button career-submit-button" data-career-apply="'+esc(f.id)+'">Заполнить анкету ↗</button>')+'</div></article>';
 }).join('')+'</div>';
 host.querySelectorAll('[data-career-apply]').forEach(b=>b.addEventListener('click',()=>openApplicantForm(open.find(x=>x.id===b.dataset.careerApply))));
}
function renderMine(apps){
 const host=$('myCareerApplications');if(!host)return;
 if(!apps.length){host.innerHTML=empty('Вы ещё не отправляли заявки','Когда вы заполните анкету, здесь появятся статус, дата отправки и комментарий администрации.');return}
 host.innerHTML=apps.map(a=>'<article class="career-application-card"><div class="career-application-head"><strong>'+esc(a.formTitle||'Заявка на трудоустройство')+'</strong><span class="'+status(a.status)+'">'+esc(labels[a.status]||a.status)+'</span></div><p>'+esc(a.department||api().getAirlineName())+' · Отправлена '+esc(when(a.created_at))+'</p>'+(a.admin_note?'<div class="career-review-note">'+esc(a.admin_note)+'</div>':'')+'</article>').join('');
}
function renderQuestion(f,ans){
 const id=f.id,v=ans[id];
 const label='<label for="cq-'+esc(id)+'">'+esc(f.label)+(f.required?' <i class="career-required">*</i>':'')+'</label>';
 if(f.type==='textarea')return '<div class="career-form-question">'+label+'<textarea id="cq-'+esc(id)+'" data-answer="'+esc(id)+'" placeholder="'+esc(f.placeholder||'')+'">'+esc(v||'')+'</textarea></div>';
 if(f.type==='select'||f.type==='yesno'){
  const opts=f.type==='yesno'?['Да','Нет']:(f.options||[]);
  const values=f.type==='yesno'?['yes','no']:opts;
  return '<div class="career-form-question">'+label+'<select id="cq-'+esc(id)+'" data-answer="'+esc(id)+'"><option value="">Выберите ответ</option>'+opts.map((o,i)=>'<option value="'+esc(values[i])+'"'+(String(v||'')===values[i]?' selected':'')+'>'+esc(o)+'</option>').join('')+'</select></div>';
 }
 if(f.type==='multiselect')return '<div class="career-form-question">'+label+'<div class="career-choice-list">'+(f.options||[]).map(o=>'<label class="career-choice"><input type="checkbox" data-multi="'+esc(id)+'" value="'+esc(o)+'"'+((Array.isArray(v)&&v.includes(o))?' checked':'')+'><span>'+esc(o)+'</span></label>').join('')+'</div></div>';
 const t=f.type==='number'?'number':f.type==='date'?'date':f.type==='email'?'email':f.type==='url'?'url':'text';
 return '<div class="career-form-question">'+label+'<input id="cq-'+esc(id)+'" data-answer="'+esc(id)+'" type="'+t+'" value="'+esc(v??'')+'" placeholder="'+esc(f.placeholder||'')+'"></div>';
}
function openApplicantForm(form){
 if(!form)return;const ans={};
 const markup='<p class="muted">'+esc(form.department||api().getAirlineName())+' · '+esc(form.description||'Заполните обязательные поля. Дополнительные вопросы появятся в зависимости от ваших ответов.')+'</p><div id="careerQuestions"></div><p class="modal-hint">Анкета доступна только администрации '+esc(api().getAirlineName())+'. После отправки ответ изменить нельзя.</p>';
 api().showModal({title:form.title,subtitle:'Анкета кандидата · '+api().getAirlineName(),content:markup,actions:[
  {label:'Отмена',onClick:api().closeModal},
  {label:'Отправить заявку',primary:true,onClick:async()=>{
   sync();const all=visibleItems(form,ans).filter(x=>x.field).map(x=>x.field);
   for(const f of all){const v=ans[f.id],blank=v===undefined||v===null||v===''||(Array.isArray(v)&&!v.length);if(blank&&f.required){api().notify('Заполните обязательное поле: '+f.label);return}if(f.type==='email'&&!blank&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(v))){api().notify('Проверьте адрес электронной почты');return}}
   const btn=$('appModal').querySelector('[data-modal-action="1"]');btn.disabled=true;btn.textContent='Отправляем…';
   try{await api().call('submit_career_application',{formId:form.id,answers:ans});api().closeModal();api().notify('Заявка отправлена. Статус можно отслеживать в разделе «Мои заявки».');await api().loadDashboard()}
   catch(e){btn.disabled=false;btn.textContent='Отправить заявку';api().notify(e.message||'Не удалось отправить заявку')}
  }}
 ]});
 function sync(){
  const root=$('appModal');root.querySelectorAll('[data-answer]').forEach(x=>{ans[x.dataset.answer]=x.value});
  const ids=new Set(Array.from(root.querySelectorAll('[data-multi]')).map(x=>x.dataset.multi));
  ids.forEach(k=>{ans[k]=Array.from(root.querySelectorAll('[data-multi="'+k+'"]:checked')).map(x=>x.value)});
 }
 function redraw(restore=null){
  const host=$('careerQuestions');
  const active=restore||document.activeElement;
  const answerId=active?.dataset?.answer||'';
  const multiId=active?.dataset?.multi||'';
  const multiValue=active?.value||'';
  const selectionStart=typeof active?.selectionStart==='number'?active.selectionStart:null;
  const selectionEnd=typeof active?.selectionEnd==='number'?active.selectionEnd:null;
  sync();
  pruneHiddenAnswers(form,ans);
  host.innerHTML=visibleItems(form,ans).map(x=>x.section?
   '<div class="career-form-section"><h3>'+esc(x.section.title)+'</h3>'+(x.section.description?'<p>'+esc(x.section.description)+'</p>':'')+'</div>'
   :renderQuestion(x.field,ans)).join('');
  host.querySelectorAll('input,textarea,select').forEach(el=>{
   const rerender=()=>{sync();redraw(el)};
   if(el.matches('select,input[type="checkbox"]'))el.addEventListener('change',rerender);
   else el.addEventListener('input',rerender);
  });
  let next=null;
  if(answerId)next=host.querySelector('[data-answer="'+answerId+'"]');
  else if(multiId)next=Array.from(host.querySelectorAll('[data-multi="'+multiId+'"]')).find(x=>x.value===multiValue);
  if(next){
   next.focus();
   if(selectionStart!==null&&typeof next.setSelectionRange==='function'){
    try{next.setSelectionRange(selectionStart,selectionEnd)}catch(_){}
   }
  }
 }
 redraw();
}
function renderAdmin(a){
 const host=$('adminCareer');if(!host)return;
 if(!a){host.innerHTML='';return}
 const forms=a.careerForms||[],apps=a.careerApplications||[];
 host.innerHTML='<div class="career-admin-toolbar"><div><p class="eyebrow">RECRUITMENT DESK</p><h3>Карьера · '+esc(api().getAirlineName())+'</h3><p class="muted">Конструктор анкет, открытый набор и управление кандидатами</p></div><button class="primary-button" id="careerNew">Создать форму</button></div><div class="career-admin-toolbar"><h3>Вакансии и наборы <span class="count-badge">'+forms.length+'</span></h3></div>'+
 (forms.length?forms.map(f=>{
  const count=fieldsOf(schemaOf(f)).length,n=apps.filter(x=>x.form_id===f.id).length;
  return '<article class="career-admin-form-card"><div class="career-application-head"><h4>'+esc(f.title)+'</h4><span class="'+status(f.status)+'">'+esc(labels[f.status]||f.status)+'</span></div><p>'+esc(f.department||'Без подразделения')+' · '+count+' вопросов · '+n+' заявок</p><p>'+esc(f.closes_at?'Приём до '+when(f.closes_at):'Без ограничения по дате')+'</p><div class="career-admin-form-actions"><button class="secondary-button" data-edit-form="'+esc(f.id)+'">Редактировать</button>'+(f.status==='archived'?'':'<button class="primary-button" data-form-status="'+esc(f.id)+'" data-next="'+(f.status==='open'?'closed':'open')+'">'+(f.status==='open'?'Закрыть приём':'Открыть приём')+'</button>')+(f.status==='archived'?'':'<button class="secondary-button" data-form-status="'+esc(f.id)+'" data-next="archived">В архив</button>')+'</div></article>';
 }).join(''):empty('Форм пока нет','Создайте первую анкету и опубликуйте набор.'))+
 '<div class="career-admin-toolbar"><div><p class="eyebrow">CANDIDATE PIPELINE</p><h3>Отправленные заявки <span class="count-badge">'+apps.length+'</span></h3></div><div class="career-admin-controls"><select id="careerFilter"><option value="all">Все статусы</option><option value="submitted">Новые</option><option value="reviewing">На рассмотрении</option><option value="interview">Собеседование</option><option value="accepted">Одобрены</option><option value="rejected">Отклонены</option></select></div></div><div id="careerAdminApps">'+adminAppsHtml(apps)+'</div>';
 $('careerNew')?.addEventListener('click',newForm);
 host.querySelectorAll('[data-edit-form]').forEach(b=>b.addEventListener('click',()=>editForm(forms.find(x=>x.id===b.dataset.editForm))));
 host.querySelectorAll('[data-form-status]').forEach(b=>b.addEventListener('click',()=>setFormStatus(b.dataset.formStatus,b.dataset.next)));
 $('careerFilter')?.addEventListener('change',e=>{const filtered=e.target.value==='all'?apps:apps.filter(x=>x.status===e.target.value);$('careerAdminApps').innerHTML=adminAppsHtml(filtered);bindApps(filtered)});
 bindApps(apps);
}
function adminAppsHtml(apps){
 if(!apps.length)return empty('Заявок пока нет','После первой отправки анкеты кандидатом она появится в этом списке.');
 return apps.map(a=>{
  const p=a.applicant||{},name=p.display_name||p.telegram_username||'Кандидат';
  return '<article class="career-application-card"><div class="career-application-head"><strong>'+esc(name)+'</strong><span class="'+status(a.status)+'">'+esc(labels[a.status]||a.status)+'</span></div><p>'+esc(a.form?.title||'Вакансия')+' · '+esc(p.telegram_username?'@'+p.telegram_username:'Telegram ID '+(p.telegram_id||'—'))+' · '+esc(when(a.created_at))+'</p><div class="career-admin-form-actions"><button class="secondary-button" data-view-app="'+esc(a.id)+'">Открыть анкету и решение</button></div></article>';
 }).join('');
}
function bindApps(apps){document.querySelectorAll('[data-view-app]').forEach(b=>b.addEventListener('click',()=>viewApp(apps.find(x=>x.id===b.dataset.viewApp))))}
function viewApp(a){
 if(!a)return;const schema=schemaOf(a.form),answers=a.answers||{};
 const sections=schema.sections.filter(s=>conditionMatches(s.visibleWhen,answers)).map(s=>{
  const fields=(s.fields||[]).filter(f=>conditionMatches(f.visibleWhen,answers)).map(f=>{
   let value=answers[f.id];if(Array.isArray(value))value=value.join(', ');if(value===undefined||value===null||value==='')return '';
   if(f.type==='yesno')value=value==='yes'?'Да':'Нет';
   return '<div class="career-answer-block"><small>'+esc(f.label)+'</small><strong>'+esc(value)+'</strong></div>';
  }).join('');
  return fields?'<div class="career-form-section"><h3>'+esc(s.title)+'</h3><div class="career-answer-list">'+fields+'</div></div>':'';
 }).join('');
 const person=a.applicant||{};
 const content='<div><strong>'+esc(person.display_name||'Кандидат')+'</strong><p class="muted">'+esc(person.telegram_username?'@'+person.telegram_username:'Telegram ID '+(person.telegram_id||'—'))+' · '+esc(when(a.created_at))+'</p></div><div class="career-answer-list">'+(sections||'<p class="muted">Ответы отсутствуют.</p>')+'</div><div class="career-form-question"><label for="careerReviewStatus">Статус заявки</label><select id="careerReviewStatus" class="modal-input">'+['reviewing','interview','accepted','rejected'].map(x=>'<option value="'+x+'"'+(a.status===x?' selected':'')+'>'+labels[x]+'</option>').join('')+'</select></div><div class="career-form-question"><label for="careerReviewNote">Комментарий кандидату</label><textarea id="careerReviewNote" class="modal-textarea" placeholder="Например, дата собеседования или причина отказа">'+esc(a.admin_note||'')+'</textarea></div><p class="modal-hint">После сохранения кандидат увидит новый статус и получит уведомление в Telegram.</p>';
 api().showModal({title:a.form?.title||'Заявка кандидата',subtitle:'Карточка кандидата · '+api().getAirlineName(),content,actions:[
  {label:'Закрыть',onClick:api().closeModal},
  {label:'Сохранить решение',primary:true,onClick:async()=>{
   const btn=$('appModal').querySelector('[data-modal-action="1"]');btn.disabled=true;btn.textContent='Сохраняем…';
   try{await api().call('admin_review_career_application',{applicationId:a.id,status:$('careerReviewStatus').value,note:$('careerReviewNote').value});api().closeModal();api().notify('Решение сохранено, кандидат уведомлён.');await api().loadDashboard()}
   catch(e){btn.disabled=false;btn.textContent='Сохранить решение';api().notify(e.message||'Не удалось сохранить решение')}
  }}
 ]});
}
async function setFormStatus(formId,next){
 try{await api().call('admin_update_career_form_status',{formId,status:next});api().notify(next==='open'?'Приём заявок открыт.':'Статус формы изменён.');await api().loadDashboard()}
 catch(e){api().notify(e.message||'Не удалось изменить статус')}
}
function beforeFields(sectionIndex,fieldIndex){
 const out=[];builder.schema.sections.forEach((s,i)=>{if(i<sectionIndex)out.push(...s.fields);else if(i===sectionIndex)out.push(...(fieldIndex<0?s.fields:s.fields.slice(0,fieldIndex)))});return out;
}
function beforeSections(sectionIndex){
 const out=[];builder.schema.sections.slice(0,sectionIndex).forEach(s=>out.push(...s.fields));return out;
}
function conditionText(rule,fields){
 if(!rule||!rule.fieldId)return 'Показывать всегда';
 const f=fields.find(x=>x.id===rule.fieldId);
 return 'Показывать, если «'+(f?.label||'вопрос')+'» '+(rule.operator==='not_equals'?'не равно':'равно')+' «'+rule.value+'»';
}
function newForm(){
 builder={id:null,title:'Набор в команду',department:'Бортпроводники',description:'Расскажите о себе и своём опыте. Мы свяжемся с вами после рассмотрения анкеты.',closes_at:null,schema:{version:1,sections:[{id:uid(),title:'Основная информация',description:'Ответьте на вопросы анкеты.',visibleWhen:null,fields:[]}]}};showBuilder();
}
function editForm(f){if(!f)return;builder=JSON.parse(JSON.stringify(f));builder.schema=builder.schema||{sections:[]};showBuilder()}
function localInput(v){if(!v)return '';const d=new Date(v),p=n=>String(n).padStart(2,'0');return d.getFullYear()+'-'+p(d.getMonth()+1)+'-'+p(d.getDate())+'T'+p(d.getHours())+':'+p(d.getMinutes())}
function syncMeta(){document.querySelectorAll('[data-meta]').forEach(x=>builder[x.dataset.meta]=x.value)}
function conditionOperatorHtml(field,selected){
 const multi=field?.type==='multiselect';
 return '<option value="equals"'+(selected!=='not_equals'?' selected':'')+'>'+(multi?'Содержит':'Равно')+'</option><option value="not_equals"'+(selected==='not_equals'?' selected':'')+'>'+(multi?'Не содержит':'Не равно')+'</option>';
}
function conditionValueHtml(field,value,prefix){
 if(!field)return '<input class="modal-input" id="'+prefix+'Value" value="'+esc(value||'')+'" placeholder="Сначала выберите вопрос" disabled>';
 let options=null;
 if(field.type==='yesno')options=[{value:'yes',label:'Да'},{value:'no',label:'Нет'}];
 else if(['select','multiselect'].includes(field.type))options=(field.options||[]).map(x=>({value:x,label:x}));
 if(options){
  const selected=options.some(x=>x.value===value)?value:(options[0]?.value||'');
  return '<select class="modal-input" id="'+prefix+'Value">'+options.map(x=>'<option value="'+esc(x.value)+'"'+(selected===x.value?' selected':'')+'>'+esc(x.label)+'</option>').join('')+'</select>';
 }
 const inputType=field.type==='number'?'number':field.type==='date'?'date':'text';
 return '<input class="modal-input" id="'+prefix+'Value" type="'+inputType+'" value="'+esc(value||'')+'" placeholder="Точное значение ответа">';
}
function logicHtml(fields,rule,prefix){
 const selectedField=fields.find(f=>f.id===rule?.fieldId)||null;
 const opts='<option value="">Показывать всегда</option>'+fields.map(f=>'<option value="'+esc(f.id)+'"'+(rule?.fieldId===f.id?' selected':'')+'>'+esc(f.label)+'</option>').join('');
 return '<div class="career-builder-logic"><strong>УСЛОВИЕ ОТОБРАЖЕНИЯ</strong><div class="career-builder-logic-grid"><select id="'+prefix+'Source" '+(!fields.length?'disabled':'')+'>'+opts+'</select><select id="'+prefix+'Operator">'+conditionOperatorHtml(selectedField,rule?.operator)+'</select><div id="'+prefix+'ValueWrap">'+conditionValueHtml(selectedField,rule?.value,prefix)+'</div></div><small class="muted">'+(fields.length?'Для вопросов с вариантами ответов значение можно выбрать из списка.':'Чтобы добавить логику, сначала создайте вопрос выше.')+'</small></div>';
}
function wireLogic(prefix,fields){
 const source=$(prefix+'Source'),operator=$(prefix+'Operator'),wrap=$(prefix+'ValueWrap');
 if(!source||!operator||!wrap)return;
 source.addEventListener('change',()=>{
  const field=fields.find(x=>x.id===source.value)||null;
  const previous=$ (prefix+'Value');
  const previousValue=previous?.value||'';
  operator.innerHTML=conditionOperatorHtml(field,'equals');
  wrap.innerHTML=conditionValueHtml(field,previousValue,prefix);
 });
}
function readLogic(prefix){
 const source=$(prefix+'Source')?.value||'',value=$(prefix+'Value')?.value||'';
 if(!source)return null;if(!String(value).trim())throw new Error('Укажите ответ, который включает этот блок.');
 return {fieldId:source,operator:$(prefix+'Operator').value,value:String(value).trim()};
}
function builderHtml(){
 return '<div class="career-builder"><div class="career-builder-meta"><div class="modal-field career-builder-wide"><label class="modal-field-label">Название набора</label><input class="modal-input" data-meta="title" maxlength="120" value="'+esc(builder.title)+'"></div><div class="modal-field"><label class="modal-field-label">Подразделение / должность</label><input class="modal-input" data-meta="department" maxlength="100" value="'+esc(builder.department)+'"></div><div class="modal-field"><label class="modal-field-label">Окончание приёма</label><input class="modal-input" data-meta="closes_at" type="datetime-local" value="'+esc(localInput(builder.closes_at))+'"></div><div class="modal-field career-builder-wide"><label class="modal-field-label">Описание для кандидатов</label><textarea class="modal-textarea" data-meta="description" rows="3" maxlength="2500">'+esc(builder.description)+'</textarea></div></div><div><p class="eyebrow">FORM STRUCTURE</p><h3 class="subheading">Разделы и вопросы</h3><p class="muted">Разделы объединяют вопросы в смысловые блоки. Раздел или отдельный вопрос можно показывать только при определённом ответе.</p></div>'+
 builder.schema.sections.map((s,si)=>{
  const prev=beforeSections(si);
  return '<section class="career-builder-section"><div class="career-builder-section-head"><div><strong>'+esc(s.title)+'</strong><small>'+esc(s.description||'')+'</small><small>'+esc(conditionText(s.visibleWhen,prev))+'</small></div><button class="career-mini-action" data-edit-section="'+si+'">Настроить</button></div><div class="career-builder-items">'+(s.fields.length?s.fields.map((f,fi)=>'<div class="career-builder-item"><span>?</span><div><strong>'+esc(f.label)+'</strong><small>'+esc(types[f.type])+(f.required?' · обязательно':' · необязательно')+' · '+esc(conditionText(f.visibleWhen,beforeFields(si,fi)))+'</small></div><button data-edit-question="'+si+':'+fi+'">Изменить</button><button data-remove-question="'+si+':'+fi+'">×</button></div>').join(''):'<p class="muted">В этом разделе пока нет вопросов.</p>')+'</div><div class="career-builder-section-actions"><button class="secondary-button" data-add-question="'+si+'">+ Добавить вопрос</button><button class="secondary-button" data-remove-section="'+si+'">Удалить раздел</button></div></section>';
 }).join('')+'<button class="career-builder-add" data-add-section>+ Добавить раздел / модуль</button><p class="modal-hint">В условии можно указать, какой ответ на предыдущий вопрос должен быть выбран, чтобы открыть следующий блок.</p></div>';
}
function showBuilder(){
 api().showModal({title:builder.id?'Редактор анкеты':'Конструктор формы трудоустройства',subtitle:'Форма · '+api().getAirlineName(),content:builderHtml(),actions:[
  {label:'Закрыть',onClick:api().closeModal},
  {label:'Сохранить форму',primary:true,onClick:async()=>{
   syncMeta();
   if(!builder.title.trim()||!builder.department.trim()||!builder.description.trim()){api().notify('Заполните название, подразделение и описание');return}
   if(!builder.schema.sections.length||!fieldsOf(builder.schema).length){api().notify('Добавьте хотя бы один вопрос');return}
   const btn=$('appModal').querySelector('[data-modal-action="1"]');btn.disabled=true;btn.textContent='Сохраняем…';
   try{
    const close=builder.closes_at?new Date(builder.closes_at).toISOString():null;
    await api().call('admin_save_career_form',{form:{id:builder.id||undefined,title:builder.title,department:builder.department,description:builder.description,closesAt:close,schema:builder.schema}});
    api().closeModal();api().notify('Форма сохранена. Можно открыть приём заявок.');await api().loadDashboard();
   }catch(e){btn.disabled=false;btn.textContent='Сохранить форму';api().notify(e.message||'Ошибка сохранения')}
  }}
 ]});
 const root=$('appModal');
 root.querySelector('[data-add-section]')?.addEventListener('click',()=>{syncMeta();builder.schema.sections.push({id:uid(),title:'Новый раздел',description:'',visibleWhen:null,fields:[]});editSection(builder.schema.sections.length-1)});
 root.querySelectorAll('[data-edit-section]').forEach(b=>b.addEventListener('click',()=>{syncMeta();editSection(+b.dataset.editSection)}));
 root.querySelectorAll('[data-remove-section]').forEach(b=>b.addEventListener('click',()=>{syncMeta();builder.schema.sections.splice(+b.dataset.removeSection,1);showBuilder()}));
 root.querySelectorAll('[data-add-question]').forEach(b=>b.addEventListener('click',()=>{syncMeta();editQuestion(+b.dataset.addQuestion,-1)}));
 root.querySelectorAll('[data-edit-question]').forEach(b=>b.addEventListener('click',()=>{syncMeta();const [s,f]=b.dataset.editQuestion.split(':').map(Number);editQuestion(s,f)}));
 root.querySelectorAll('[data-remove-question]').forEach(b=>b.addEventListener('click',()=>{syncMeta();const [s,f]=b.dataset.removeQuestion.split(':').map(Number);builder.schema.sections[s].fields.splice(f,1);showBuilder()}));
}
function editSection(i){
 const s=builder.schema.sections[i];
 api().showModal({title:'Настройка раздела',subtitle:'Раздел анкеты',content:'<div class="career-builder"><div class="modal-field"><label class="modal-field-label">Название раздела</label><input class="modal-input" id="csTitle" maxlength="100" value="'+esc(s.title)+'"></div><div class="modal-field"><label class="modal-field-label">Описание / инструкция</label><textarea class="modal-textarea" id="csDescription" rows="3">'+esc(s.description||'')+'</textarea></div>'+logicHtml(beforeSections(i),s.visibleWhen,'cs')+'</div>',actions:[
  {label:'Назад',onClick:showBuilder},{label:'Сохранить раздел',primary:true,onClick:()=>{try{const title=$('csTitle').value.trim();if(!title)throw new Error('Укажите название раздела.');s.title=title;s.description=$('csDescription').value.trim();s.visibleWhen=readLogic('cs');api().closeModal();showBuilder()}catch(e){api().notify(e.message)}}}
 ]});
 wireLogic('cs',beforeSections(i));
}
function editQuestion(si,fi){
 const section=builder.schema.sections[si],old=fi>=0?section.fields[fi]:null;
 const f=old||{id:uid(),label:'Новый вопрос',type:'text',required:true,placeholder:'',options:[],visibleWhen:null};
 api().showModal({title:old?'Редактирование вопроса':'Новый вопрос',subtitle:'Тип ответа, обязательность и условия показа',content:
 '<div class="career-builder"><div class="modal-field"><label class="modal-field-label">Текст вопроса</label><input class="modal-input" id="qLabel" maxlength="150" value="'+esc(f.label)+'"></div><div class="modal-field"><label class="modal-field-label">Тип ответа</label><select class="modal-input" id="qType">'+Object.keys(types).map(k=>'<option value="'+k+'"'+(f.type===k?' selected':'')+'>'+types[k]+'</option>').join('')+'</select></div><div class="modal-field"><label class="modal-field-label">Обязательное поле</label><select class="modal-input" id="qRequired"><option value="true"'+(f.required?' selected':'')+'>Да</option><option value="false"'+(!f.required?' selected':'')+'>Нет</option></select></div><div class="modal-field"><label class="modal-field-label">Подсказка / пример</label><input class="modal-input" id="qPlaceholder" maxlength="180" value="'+esc(f.placeholder||'')+'"></div><div class="modal-field" id="qOptionsWrap"><label class="modal-field-label">Варианты ответа, каждый с новой строки</label><textarea class="modal-textarea" id="qOptions" rows="4">'+esc((f.options||[]).join('\n'))+'</textarea></div>'+logicHtml(beforeFields(si,fi),f.visibleWhen,'qLogic')+'</div>',actions:[
  {label:'Назад',onClick:showBuilder},{label:'Сохранить вопрос',primary:true,onClick:()=>{
   const label=$('qLabel').value.trim(),type=$('qType').value;if(!label){api().notify('Введите текст вопроса');return}
   const opts=['select','multiselect'].includes(type)?$('qOptions').value.split('\n').map(x=>x.trim()).filter(Boolean):[];
   if(['select','multiselect'].includes(type)&&(opts.length<2||opts.length>20||new Set(opts).size!==opts.length)){api().notify('Добавьте от 2 до 20 разных вариантов ответа');return}
   try{f.label=label;f.type=type;f.required=$('qRequired').value==='true';f.placeholder=$('qPlaceholder').value.trim();f.options=opts;f.visibleWhen=readLogic('qLogic');if(old)section.fields[fi]=f;else section.fields.push(f);api().closeModal();showBuilder()}catch(e){api().notify(e.message)}
  }}
 ]});
 wireLogic('qLogic',beforeFields(si,fi));
 const type=$('qType'),wrap=$('qOptionsWrap');const toggle=()=>wrap.hidden=!['select','multiselect'].includes(type.value);type.addEventListener('change',toggle);toggle();
}
document.querySelectorAll('[data-career-admin]').forEach(b=>b.addEventListener('click',()=>{api().openPage('admin');setTimeout(()=>$('adminCareer')?.scrollIntoView({behavior:'smooth',block:'start'}),80)}));
window.RoyalFlightCareer={render};
})();
