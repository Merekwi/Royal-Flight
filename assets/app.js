(() => {
  const tg=window.Telegram?.WebApp;
  if(tg){tg.ready();tg.expand();try{tg.setHeaderColor('#07111f');tg.setBackgroundColor('#07111f')}catch(_){}}
  const pages=[...document.querySelectorAll('.page')], nav=[...document.querySelectorAll('.nav-item')], toast=document.getElementById('toast');
  let timer=null, dashboard=null;
  const URL='https://iotwbzzlwltjfddrmhvg.supabase.co';
  const KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlvdHdienpsd2x0amZkZHJtaHZnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI5NTEwNDksImV4cCI6MjEwODUyNzA0OX0.Bg-ww-s0WVpVwuJymjREB3z6eeY0S_8ZfFE5tnqUYz0';
  function notify(s){toast.textContent=s;toast.classList.add('show');clearTimeout(timer);timer=setTimeout(()=>toast.classList.remove('show'),2800);if(tg?.HapticFeedback)tg.HapticFeedback.impactOccurred('light')}
  function openPage(name){const p=document.getElementById('page-'+name);if(!p)return;pages.forEach(x=>x.classList.toggle('active',x===p));nav.forEach(x=>x.classList.toggle('active',x.dataset.page===name));window.scrollTo({top:0,behavior:'smooth'});if(tg?.HapticFeedback)tg.HapticFeedback.selectionChanged()}
  document.querySelectorAll('[data-page]').forEach(x=>x.addEventListener('click',()=>openPage(x.dataset.page)));
  document.getElementById('profileShortcut')?.addEventListener('click',()=>openPage('profile'));
  const airlines={
    royal:{name:'ROYAL FLIGHT',sub:'PASSENGER CLUB',miles:'ROYAL MILES',initials:'RF',logo:'./assets/royal-flight-logo.svg',title:'Royal Flight',theme:'royal'},
    azal:{name:'AZAL',sub:'AZERBAIJAN AIRLINES',miles:'AZAL CLUB',initials:'AZ',logo:'https://upload.wikimedia.org/wikipedia/commons/4/4d/Azerbaijan_Airlines_logo.svg',title:'AZAL',theme:'azal'}
  };
  function applyAirline(key){
    const a=airlines[key]||airlines.royal;
    document.body.classList.toggle('azal-theme',key==='azal');
    const logo=document.querySelector('.brand-logo');if(logo){logo.src=a.logo;logo.alt=a.title}
    const brand=document.querySelector('.brand-copy');if(brand){brand.querySelector('strong').textContent=a.name;brand.querySelector('small').textContent=a.sub}
    const pill=document.querySelector('.miles-card .pill');if(pill) pill.innerHTML='<span class="status-dot"></span> '+a.miles;
    const home=document.querySelector('#page-home #welcomeName');
    if(home&&!dashboard?.profile?.display_name)home.textContent='Ваша программа лояльности '+a.title;
    document.querySelector('#page-flights .eyebrow').textContent=a.name;
    document.querySelector('#page-profile .page-heading .muted').textContent='Ваш профиль в '+a.title+'.';
    const select=document.getElementById('airlineSwitcher');if(select)select.value=key;
    document.title=a.title+' — личный кабинет';
    try{localStorage.setItem('rf_selected_airline',key)}catch(_){}
  }
  const airlineSelect=document.getElementById('airlineSwitcher');
  const selectedAirline=(()=>{try{return localStorage.getItem('rf_selected_airline')||'royal'}catch(_){return 'royal'}})();
  applyAirline(selectedAirline);
  airlineSelect?.addEventListener('change',()=>{applyAirline(airlineSelect.value);notify('Выбрана авиакомпания: '+airlines[airlineSelect.value].title)});
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const date=v=>v?new Date(v).toLocaleString('ru-RU',{day:'2-digit',month:'short',hour:'2-digit',minute:'2-digit'}):'—';
  const money=(v,c='RUB')=>new Intl.NumberFormat('ru-RU',{style:'currency',currency:c,maximumFractionDigits:2}).format(Number(v||0));
  async function call(action,extra={}){if(!tg?.initData)throw new Error('Откройте приложение через Telegram.');const r=await fetch(URL+'/functions/v1/rf-api',{method:'POST',headers:{'Content-Type':'application/json','apikey':KEY},body:JSON.stringify({initData:tg.initData,action,...extra}),cache:'no-store'});const d=await r.json();if(!r.ok)throw new Error(d.message||d.error||'Ошибка сервера');return d}
  async function signIn(){
    const identity=document.getElementById('telegramIdentity');
    if(!tg?.initData){
      if(identity)identity.textContent='Telegram не передал данные входа. Закройте окно и откройте Mini App кнопкой в боте Royal Flight.';
      document.getElementById('profileName').textContent='Ожидание авторизации';
      return;
    }
    if(identity)identity.textContent='Проверяем данные Telegram…';
    try{
      const r=await fetch(URL+'/functions/v1/telegram-auth',{method:'POST',headers:{'Content-Type':'application/json','apikey':KEY},body:JSON.stringify({initData:tg.initData}),cache:'no-store'});
      const d=await r.json();if(!r.ok||!d.profile){console.warn('Telegram authentication failed:',d);if(identity)identity.textContent=d.message||('Ошибка авторизации: '+(d.error||r.status));return}
      const p=d.profile,name=p.display_name||'Пассажир Royal Flight';
      document.getElementById('profileName').textContent=name;
      document.getElementById('welcomeName').textContent=name+', добро пожаловать в '+(airlineSelect?.value==='azal'?'AZAL':'Royal Flight');
      document.getElementById('telegramIdentity').textContent=p.telegram_username?'@'+p.telegram_username:'Telegram ID: '+p.telegram_id;
      const initials=name.split(/\s+/).slice(0,2).map(x=>x[0]||'').join('').toUpperCase()||'RF';
      const avatarInitials=document.getElementById('avatarInitials');if(avatarInitials)avatarInitials.textContent=initials;document.getElementById('profileAvatar').textContent=initials;
      if(p.role==='admin'||p.role==='owner')document.getElementById('adminNav').hidden=false;
      await loadDashboard();
    }catch(e){console.warn('Royal Flight backend is not ready yet:',e);if(identity)identity.textContent='Не удалось связаться с сервером. Проверьте подключение и перезапустите Mini App.'}
  }
  async function loadDashboard(){try{dashboard=await call('dashboard');render(dashboard)}catch(e){console.warn('Dashboard unavailable:',e.message)}}
  function render(d){
    const p=d.profile||{},m=Number(p.miles||0).toLocaleString('ru-RU');
    document.getElementById('milesBalance').textContent=m;document.getElementById('milesBalanceDetail').textContent=m;
    document.getElementById('robloxStatus').textContent=p.roblox_username?'Roblox: '+p.roblox_username:'Roblox не привязан';
    document.getElementById('robloxProfileText').textContent=p.roblox_username||'Не привязан';
    const linkBtn=document.getElementById('robloxLinkButton');if(linkBtn){linkBtn.hidden=!!p.roblox_username;document.getElementById('robloxProfileState').textContent=p.roblox_username?'Привязан':'Не подключён';}
    const ledgerBox=document.getElementById('mileLedger');if(ledgerBox){const ledger=d.mileLedger||[];ledgerBox.innerHTML=ledger.length?'<div class="data-list">'+ledger.map(x=>'<article class="data-card ledger-card"><div><strong>'+esc(x.reason==='roblox_online_minutes'?'Время на сервере Roblox':x.reason)+'</strong><p class="muted">'+date(x.created_at)+'</p></div><strong class="ledger-delta">'+(Number(x.delta)>0?'+':'')+Number(x.delta).toLocaleString('ru-RU')+'</strong></article>').join('')+'</div>':'<div class="empty-state compact"><div class="empty-orbit">↻</div><h3>Операций пока нет</h3><p>Начисления и списания будут отображаться здесь.</p></div>'}
    const fc=document.getElementById('flightCatalog');
    if(fc){fc.innerHTML=d.flights?.length?'<div class="data-list">'+d.flights.map(f=>'<article class="data-card"><div class="data-card-top"><span class="flight-tag">'+esc(f.flight_number||'RF FLIGHT')+'</span><span class="muted">'+esc(date(f.departure_at))+'</span></div><h3>'+esc(f.title)+'</h3><div class="route-line"><strong>'+esc(f.origin)+'</strong><span>✈ ─── ✈</span><strong>'+esc(f.destination)+'</strong></div><p class="muted">'+esc(f.aircraft||'Самолёт уточняется')+'</p>'+(f.description?'<p class="data-description">'+esc(f.description)+'</p>':'')+'</article>').join('')+'</div>':'<div class="empty-state"><div class="empty-orbit">✈</div><h3>Расписание готовится</h3><p>Когда администрация опубликует рейсы, они появятся здесь.</p></div>'}
    const sc=document.getElementById('serviceCatalog');
    if(sc){sc.innerHTML=d.services?.length?'<div class="service-list">'+d.services.map(s=>'<article class="data-card service-card"><div class="data-card-top"><span class="flight-tag">'+esc(s.code)+'</span><span class="service-duration">'+Number(s.duration_days)+' дней</span></div><h3>'+esc(s.name)+'</h3><p class="data-description">'+esc(s.description||'Временная привилегия Royal Flight.')+'</p><div class="service-buy-row"><strong>'+money(s.price,s.currency)+'</strong><button class="primary-button" data-buy="'+esc(s.id)+'">Оформить</button></div></article>').join('')+'</div>':'<div class="empty-state"><div class="empty-orbit">♛</div><h3>Каталог скоро откроется</h3><p>Все услуги будут доступны в одном месте с историей заказов и продлением доступа.</p></div>';sc.querySelectorAll('[data-buy]').forEach(b=>b.addEventListener('click',()=>createOrder(b.dataset.buy)))}
    const oh=document.getElementById('ordersHistory');
    if(oh){const orders=d.orders||[];oh.innerHTML='<h2 class="subheading orders-heading">Мои заказы</h2>'+(orders.length?'<div class="data-list">'+orders.map(o=>{const labels={awaiting_payment:'Ожидает оплаты',awaiting_review:'На проверке',paid:'Оплачен',rejected:'Отклонён',cancelled:'Отменён'};return '<article class="data-card order-card"><div class="data-card-top"><strong>'+esc(o.order_number)+'</strong><span class="order-status status-'+esc(o.status)+'">'+esc(labels[o.status]||o.status)+'</span></div><p class="muted">'+money(o.amount,o.currency)+' · '+date(o.created_at)+'</p>'+(o.admin_note?'<p class="data-description">'+esc(o.admin_note)+'</p>':'')+(o.status==='awaiting_payment'?'<div class="button-row"><button class="secondary-button" data-show-payment="'+esc(o.id)+'">Реквизиты</button><button class="primary-button" data-mark-paid="'+esc(o.id)+'">Я оплатил</button></div>':'')+'</article>'}).join('')+'</div>':'<div class="empty-card"><span class="empty-icon">▣</span><div><strong>Заказов пока нет</strong><p>Оформленные услуги появятся здесь.</p></div></div>');oh.querySelectorAll('[data-mark-paid]').forEach(b=>b.addEventListener('click',()=>markPaid(b.dataset.markPaid)));oh.querySelectorAll('[data-show-payment]').forEach(b=>b.addEventListener('click',()=>showPayment(b.dataset.showPayment)))}
    const homeFlight=document.getElementById('homeFlightPreview');
    if(homeFlight){const next=(d.flights||[])[0];homeFlight.innerHTML=next?'<article class="home-flight-card"><div class="home-flight-top"><span class="flight-tag">'+esc(next.flight_number||'UPCOMING FLIGHT')+'</span><span class="muted">'+esc(date(next.departure_at))+'</span></div><div class="home-route"><div><strong>'+esc(next.origin)+'</strong><small>ОТПРАВЛЕНИЕ</small></div><span class="home-route-plane">✈</span><div><strong>'+esc(next.destination)+'</strong><small>ПРИБЫТИЕ</small></div></div><div class="home-flight-bottom"><span>'+esc(next.aircraft||'Самолёт уточняется')+'</span><button class="text-link" data-page="flights">Все рейсы&nbsp; ↗</button></div></article>':'<div class="home-flight-empty"><span class="home-flight-empty-icon">✈</span><div><strong>Пока нет запланированных рейсов</strong><p>Новые вылеты появятся здесь после публикации расписания.</p></div><button class="text-link" data-page="flights">Расписание&nbsp; ↗</button></div>';homeFlight.querySelectorAll('[data-page]').forEach(b=>b.addEventListener('click',()=>openPage(b.dataset.page)))}
    const announcement=document.getElementById('announcementList');
    if(announcement){const news=d.announcements||[];announcement.innerHTML=news.length?'<div class="data-list">'+news.map(n=>'<article class="data-card announcement-card"><div class="data-card-top"><span class="flight-tag">НОВОСТИ</span><span class="muted">'+date(n.sent_at||n.created_at)+'</span></div><h3>'+esc(n.title)+'</h3><p class="data-description">'+esc(n.body)+'</p></article>').join('')+'</div>':'<div class="empty-card"><span class="empty-icon">◌</span><div><strong>Пока нет объявлений</strong><p>Здесь появятся новости и уведомления авиакомпании.</p></div></div>'}
    if(d.admin&&(p.role==='admin'||p.role==='owner'))renderAdmin(d.admin);
  }
  const modalRoot=document.getElementById('appModal');
  function closeModal(){if(!modalRoot)return;modalRoot.hidden=true;modalRoot.innerHTML='';}
  function showModal({title,subtitle='',content='',actions=[]}){
    if(!modalRoot)return;
    modalRoot.hidden=false;
    modalRoot.innerHTML='<div class="modal-backdrop"><section class="modal-sheet" role="dialog" aria-modal="true" aria-labelledby="modalTitle"><div class="modal-grabber"></div><div class="modal-head"><div><p class="eyebrow">ROYAL FLIGHT · PASSENGER CLUB</p><h2 id="modalTitle">'+esc(title)+'</h2>'+(subtitle?'<p class="modal-subtitle">'+esc(subtitle)+'</p>':'')+'</div><button class="modal-close" type="button" aria-label="Закрыть">×</button></div><div class="modal-content">'+content+'</div><div class="modal-actions">'+actions.map((a,i)=>'<button type="button" class="'+(a.primary?'primary-button':'secondary-button')+'" data-modal-action="'+i+'">'+esc(a.label)+'</button>').join('')+'</div></section></div>';
    modalRoot.querySelector('.modal-close')?.addEventListener('click',closeModal);
    modalRoot.querySelector('.modal-backdrop')?.addEventListener('click',e=>{if(e.target.classList.contains('modal-backdrop'))closeModal()});
    actions.forEach((a,i)=>modalRoot.querySelector('[data-modal-action="'+i+'"]')?.addEventListener('click',a.onClick));
    modalRoot.querySelector('input,textarea,button')?.focus();
  }
  function paymentDetailsContent(o,m){
    return '<div class="payment-summary"><span>Сумма к оплате</span><strong>'+esc(money(o.amount,o.currency))+'</strong><small>Заказ '+esc(o.order_number)+'</small></div><div class="payment-detail-list"><div class="payment-detail"><span>Номер карты</span><strong>'+esc(m.card_number)+'</strong><button type="button" class="copy-value" data-copy="'+esc(m.card_number)+'">Копировать</button></div>'+(m.recipient_name?'<div class="payment-detail"><span>Получатель</span><strong>'+esc(m.recipient_name)+'</strong></div>':'')+'<div class="payment-detail"><span>Комментарий к переводу</span><strong>'+esc(o.order_number)+'</strong><button type="button" class="copy-value" data-copy="'+esc(o.order_number)+'">Копировать</button></div></div>'+(m.instructions?'<p class="modal-note">'+esc(m.instructions)+'</p>':'')+'<p class="modal-hint">Переведите точную сумму и укажите номер заказа в комментарии к платежу.</p>';
  }
  function wireCopyButtons(){
    modalRoot?.querySelectorAll('[data-copy]').forEach(b=>b.addEventListener('click',async()=>{
      const value=b.dataset.copy||'';
      try{await navigator.clipboard.writeText(value);notify('Скопировано')}catch(_){const input=document.createElement('textarea');input.value=value;document.body.appendChild(input);input.select();try{document.execCommand('copy');notify('Скопировано')}catch(__){notify('Не удалось скопировать')}input.remove()}
    }));
  }
  async function createOrder(serviceId){
    const methods=dashboard?.paymentMethods||[];
    if(!methods.length){notify('Администрация ещё не добавила реквизиты оплаты.');return}
    const content='<div class="payment-choice-list">'+methods.map((m,i)=>'<label class="payment-choice"><input type="radio" name="paymentChoice" value="'+esc(m.id)+'" '+(i===0?'checked':'')+'><span class="payment-choice-mark"></span><span><strong>'+esc(m.label)+'</strong><small>'+esc(m.recipient_name||'Получатель не указан')+'</small></span><span class="payment-choice-arrow">›</span></label>').join('')+'</div>';
    showModal({title:'Способ оплаты',subtitle:'Выберите удобный способ для оформления заказа.',content,actions:[{label:'Отмена',onClick:closeModal},{label:'Продолжить',primary:true,onClick:async()=>{
      const chosen=modalRoot.querySelector('input[name="paymentChoice"]:checked')?.value;
      const method=methods.find(m=>m.id===chosen);if(!method){notify('Выберите способ оплаты');return}
      const next=modalRoot.querySelector('[data-modal-action="1"]');if(next){next.disabled=true;next.textContent='Создаём заказ…'}
      try{
        const x=await call('create_order',{serviceId,paymentMethodId:method.id}),o=x.order;
        closeModal();await loadDashboard();openPage('services');
        showModal({title:'Заказ создан',subtitle:'Осталось выполнить перевод и отправить заявку на проверку.',content:paymentDetailsContent(o,method),actions:[{label:'Закрыть',onClick:closeModal},{label:'Я оплатил',primary:true,onClick:()=>{closeModal();markPaid(o.id)}}]});
        wireCopyButtons();
      }catch(e){if(next){next.disabled=false;next.textContent='Продолжить'}notify(e.message)}
    }}]});
  }
  function showPayment(id){
    const o=(dashboard?.orders||[]).find(x=>x.id===id);if(!o)return;
    const m=(dashboard?.paymentMethods||[]).find(x=>x.id===o.payment_method_id);
    if(!m){notify('Реквизиты недоступны. Напишите администрации.');return}
    showModal({title:'Реквизиты оплаты',subtitle:'Заказ '+o.order_number,content:paymentDetailsContent(o,m),actions:[{label:'Закрыть',onClick:closeModal},{label:'Я оплатил',primary:true,onClick:()=>{closeModal();markPaid(o.id)}}]});
    wireCopyButtons();
  }
  async function markPaid(id){
    showModal({title:'Подтверждение оплаты',subtitle:'Заявка поступит администрации на проверку.',content:'<label class="modal-field-label" for="paymentNote">Комментарий <span>необязательно</span></label><textarea id="paymentNote" class="modal-textarea" rows="3" placeholder="Например, имя отправителя или время перевода"></textarea>',actions:[{label:'Назад',onClick:closeModal},{label:'Отправить заявку',primary:true,onClick:async()=>{
      const note=modalRoot.querySelector('#paymentNote')?.value||'',btn=modalRoot.querySelector('[data-modal-action="1"]');if(btn){btn.disabled=true;btn.textContent='Отправляем…'}
      try{await call('mark_paid',{orderId:id,userNote:note});closeModal();notify('Заявка отправлена на проверку.');await loadDashboard()}
      catch(e){if(btn){btn.disabled=false;btn.textContent='Отправить заявку'}notify(e.message)}
    }}]});
  }
  function renderAdmin(a){
    const box=document.getElementById('adminPayments');if(!box)return;const orders=a.pendingOrders||[];
    box.innerHTML='<h2 class="subheading orders-heading">Заявки на оплату <span class="count-badge">'+orders.length+'</span></h2>'+(orders.length?'<div class="data-list">'+orders.map(o=>'<article class="data-card order-card"><div class="data-card-top"><strong>'+esc(o.order_number)+'</strong><span class="order-status status-awaiting_review">На проверке</span></div><p class="muted">'+money(o.amount,o.currency)+' · '+date(o.created_at)+'</p>'+(o.user_note?'<p class="data-description">'+esc(o.user_note)+'</p>':'')+(o.proof_url?'<p><a class="proof-link" target="_blank" rel="noopener" href="'+esc(o.proof_url)+'">Открыть подтверждение</a></p>':'')+'<div class="button-row"><button class="primary-button" data-paid="'+esc(o.id)+'">Оплачено</button><button class="secondary-button" data-reject="'+esc(o.id)+'">Не оплачено</button></div></article>').join('')+'</div>':'<div class="empty-card"><span class="empty-icon">✓</span><div><strong>Нет ожидающих заявок</strong><p>Заявки появятся после нажатия пользователем «Я оплатил».</p></div></div>');
    box.querySelectorAll('[data-paid]').forEach(b=>b.addEventListener('click',()=>review(b.dataset.paid,true)));
    box.querySelectorAll('[data-reject]').forEach(b=>b.addEventListener('click',()=>review(b.dataset.reject,false)));
    const usersBox=document.getElementById('adminUsers');
    if(usersBox){
      const users=a.users||[];const isOwner=dashboard?.profile?.role==='owner';
      usersBox.innerHTML='<h2 class="subheading orders-heading">Участники <span class="count-badge">'+users.length+'</span></h2>'+(users.length?'<div class="data-list">'+users.map(u=>'<article class="data-card user-card"><div class="data-card-top"><strong>'+esc(u.display_name||u.telegram_username||('ID '+u.telegram_id))+'</strong><span class="order-status">'+esc(u.role)+'</span></div><p class="muted">'+(u.telegram_username?'@'+esc(u.telegram_username)+' · ':'')+'Telegram ID: '+esc(u.telegram_id)+'</p><p class="data-description">'+(u.roblox_username?'Roblox: '+esc(u.roblox_username)+' · ':'')+'Баланс: '+Number(u.miles||0).toLocaleString('ru-RU')+' миль</p><div class="button-row">'+(isOwner&&u.role!=='owner'?'<button class="secondary-button" data-role-user="'+esc(u.id)+'" data-role="'+(u.role==='admin'?'member':'admin')+'">'+(u.role==='admin'?'Снять админа':'Назначить админом')+'</button>':'')+'<button class="secondary-button" data-miles-user="'+esc(u.id)+'">Изменить мили</button></div></article>').join('')+'</div>':'<div class="empty-card"><strong>Участников пока нет</strong><p>Профили появятся после первого запуска Mini App.</p></div>');
      usersBox.querySelectorAll('[data-role-user]').forEach(b=>b.addEventListener('click',async()=>{try{await call('admin_manage_user',{profileId:b.dataset.roleUser,role:b.dataset.role});notify('Роль участника обновлена.');await loadDashboard()}catch(e){notify(e.message)}}));
      usersBox.querySelectorAll('[data-miles-user]').forEach(b=>b.addEventListener('click',()=>showAdminForm({title:'Изменить баланс',subtitle:'Укажите количество миль. Для списания используйте отрицательное число.',fields:[{name:'milesDelta',label:'Изменение баланса',type:'number',value:'100',required:true}],submitLabel:'Сохранить',onSubmit:async values=>{const delta=Number(values.milesDelta);if(!Number.isInteger(delta)){notify('Введите целое число');return false}await call('admin_manage_user',{profileId:b.dataset.milesUser,milesDelta:delta});notify('Баланс обновлён.');await loadDashboard();return true}})));
    }
  }
  async function review(id,paid){
    showAdminForm({title:paid?'Подтвердить оплату':'Отклонить оплату',subtitle:paid?'После подтверждения услуга будет активирована.':'Укажите причину отказа, она будет отправлена участнику.',fields:[{name:'note',label:paid?'Комментарий':'Причина отказа',type:'textarea',rows:3,required:!paid,placeholder:paid?'Комментарий для участника':'Почему оплата не подтверждена?'}],submitLabel:paid?'Подтвердить':'Отклонить заявку',onSubmit:async values=>{
      if(!paid&&!values.note.trim()){notify('Укажите причину отказа');return false}
      await call('admin_review_order',{orderId:id,paid,note:values.note});closeModal();notify(paid?'Оплата подтверждена, услуга активирована.':'Заявка отклонена.');await loadDashboard();return true;
    }});
  }
  function showAdminForm({title,subtitle='',fields,submitLabel='Сохранить',onSubmit}){
    const markup=fields.map(f=>{
      const label='<label class="modal-field-label" for="field-'+esc(f.name)+'">'+esc(f.label)+(f.required?'':' <span>необязательно</span>')+'</label>';
      let control='';
      if(f.type==='select')control='<select class="modal-input" id="field-'+esc(f.name)+'" name="'+esc(f.name)+'">'+(f.options||[]).map(o=>'<option value="'+esc(o.value)+'">'+esc(o.label)+'</option>').join('')+'</select>';
      else if(f.type==='textarea')control='<textarea class="modal-textarea" id="field-'+esc(f.name)+'" name="'+esc(f.name)+'" rows="'+Number(f.rows||3)+'" placeholder="'+esc(f.placeholder||'')+'" '+(f.required?'required':'')+'>'+esc(f.value||'')+'</textarea>';
      else control='<input class="modal-input" id="field-'+esc(f.name)+'" name="'+esc(f.name)+'" type="'+esc(f.type||'text')+'" value="'+esc(f.value||'')+'" placeholder="'+esc(f.placeholder||'')+'" '+(f.required?'required':'')+'>';
      return '<div class="modal-field">'+label+control+'</div>';
    }).join('');
    showModal({title,subtitle,content:'<div class="admin-form-grid">'+markup+'</div>',actions:[{label:'Отмена',onClick:closeModal},{label:submitLabel,primary:true,onClick:async()=>{
      const values={};fields.forEach(f=>{values[f.name]=modalRoot.querySelector('[name="'+f.name+'"]')?.value?.trim()||''});
      const btn=modalRoot.querySelector('[data-modal-action="1"]');if(btn){btn.disabled=true;btn.textContent='Сохраняем…'}
      try{const result=await onSubmit(values);if(result!==false)closeModal()}
      catch(e){notify(e.message||'Не удалось сохранить изменения')}
      finally{if(btn&&btn.isConnected){btn.disabled=false;btn.textContent=submitLabel}}
    }}]});
  }
  async function adminAction(section){
    if(section==='payments'){openPage('admin');document.getElementById('adminPayments')?.scrollIntoView({behavior:'smooth'});return}
    if(section==='users'){openPage('admin');document.getElementById('adminUsers')?.scrollIntoView({behavior:'smooth'});return}
    if(section==='flights'){
      showAdminForm({title:'Новый рейс',subtitle:'Заполните данные нового рейса в расписании.',fields:[
        {name:'title',label:'Название рейса',required:true,placeholder:'Например, Москва — Анталья'},
        {name:'origin',label:'Город вылета',required:true,placeholder:'Москва'},
        {name:'destination',label:'Город прилёта',required:true,placeholder:'Анталья'},
        {name:'departureAt',label:'Дата и время вылета',type:'datetime-local',required:true},
        {name:'flightNumber',label:'Номер рейса',value:'RF001'},
        {name:'aircraft',label:'Самолёт',value:'Boeing 737-800'},
        {name:'capacity',label:'Количество мест',type:'number',placeholder:'Например, 189'}
      ],submitLabel:'Создать рейс',onSubmit:async v=>{
        if(!v.title||!v.origin||!v.destination||!v.departureAt){notify('Заполните обязательные поля');return false}
        await call('admin_create_flight',{flight:{title:v.title,origin:v.origin,destination:v.destination,departureAt:new Date(v.departureAt).toISOString(),flightNumber:v.flightNumber,aircraft:v.aircraft,capacity:v.capacity?Number(v.capacity):null}});
        notify('Рейс создан');await loadDashboard();openPage('flights');return true;
      }});return;
    }
    if(section==='services'){
      showAdminForm({title:'Новая услуга',subtitle:'Добавьте привилегию в каталог пассажиров.',fields:[
        {name:'code',label:'Код услуги',required:true,placeholder:'BUSINESS'},
        {name:'name',label:'Название услуги',required:true,placeholder:'Business Class'},
        {name:'price',label:'Стоимость',type:'number',value:'300',required:true},
        {name:'durationDays',label:'Срок действия, дней',type:'number',value:'30',required:true},
        {name:'description',label:'Описание',type:'textarea',rows:3,placeholder:'Краткое описание привилегии'}
      ],submitLabel:'Добавить услугу',onSubmit:async v=>{
        if(!v.code||!v.name||!v.price||!v.durationDays){notify('Заполните обязательные поля');return false}
        await call('admin_save_service',{service:{code:v.code,name:v.name,price:Number(v.price),durationDays:Number(v.durationDays),description:v.description,currency:'RUB'}});
        notify('Услуга добавлена');await loadDashboard();return true;
      }});return;
    }
    if(section==='notifications'){
      showAdminForm({title:'Новое объявление',subtitle:'Создайте уведомление для участников приложения.',fields:[
        {name:'title',label:'Заголовок',required:true,placeholder:'Важная информация'},
        {name:'body',label:'Текст объявления',type:'textarea',rows:4,required:true,placeholder:'Сообщение для пассажиров'},
        {name:'audience',label:'Кому отправить',type:'select',options:[{value:'all',label:'Всем участникам'},{value:'admins',label:'Администраторам'},{value:'roblox_linked',label:'Привязавшим Roblox'},{value:'active_service',label:'С активной услугой'}]},
        {name:'scheduledAt',label:'Отложенная отправка',type:'datetime-local'}
      ],submitLabel:'Опубликовать',onSubmit:async v=>{
        if(!v.title||!v.body){notify('Заполните заголовок и текст');return false}
        await call('admin_create_notification',{notification:{title:v.title,body:v.body,audience:v.audience||'all',scheduledAt:v.scheduledAt?new Date(v.scheduledAt).toISOString():null}});
        notify('Объявление сохранено');await loadDashboard();return true;
      }});return;
    }
    if(section==='settings'){
      showModal({title:'Настройки клуба',subtitle:'Выберите параметр, который нужно изменить.',content:'<div class="settings-action-list"><button class="settings-action" data-setting="rate"><span class="settings-action-icon">✦</span><span><strong>Начисление миль</strong><small>Мили за минуту на сервере</small></span><b>›</b></button><button class="settings-action" data-setting="payment"><span class="settings-action-icon">▤</span><span><strong>Способ оплаты</strong><small>Добавить платёжные реквизиты</small></span><b>›</b></button><button class="settings-action" data-setting="places"><span class="settings-action-icon">⌖</span><span><strong>Серверы Roblox</strong><small>Разрешённые Place ID</small></span><b>›</b></button></div>',actions:[{label:'Закрыть',onClick:closeModal}]});
      modalRoot.querySelector('[data-setting="rate"]')?.addEventListener('click',()=>{
        closeModal();showAdminForm({title:'Начисление миль',subtitle:'Установите количество миль за минуту на сервере.',fields:[{name:'rate',label:'Миль за минуту',type:'number',value:'10',required:true}],submitLabel:'Сохранить',onSubmit:async v=>{const rate=Number(v.rate);if(!Number.isInteger(rate)||rate<0||rate>10000){notify('Укажите целое число от 0 до 10000');return false}await call('admin_set_miles_rate',{milesPerMinute:rate});notify('Ставка обновлена');return true}});
      });
      modalRoot.querySelector('[data-setting="payment"]')?.addEventListener('click',()=>{
        closeModal();showAdminForm({title:'Реквизиты оплаты',subtitle:'Добавьте способ оплаты для оформления услуг.',fields:[
          {name:'label',label:'Название способа',required:true,placeholder:'Перевод на карту'},
          {name:'cardNumber',label:'Номер карты или счёта',required:true,placeholder:'Номер для оплаты'},
          {name:'recipientName',label:'Получатель',placeholder:'Имя получателя'},
          {name:'instructions',label:'Инструкция',type:'textarea',rows:3,placeholder:'Что указать в комментарии к платежу'}
        ],submitLabel:'Добавить реквизиты',onSubmit:async v=>{if(!v.label||!v.cardNumber){notify('Укажите название и номер карты');return false}await call('admin_add_payment_method',{paymentMethod:{label:v.label,cardNumber:v.cardNumber,recipientName:v.recipientName,instructions:v.instructions,active:true}});notify('Реквизиты добавлены');return true}});
      });
      modalRoot.querySelector('[data-setting="places"]')?.addEventListener('click',()=>{
        closeModal();showAdminForm({title:'Серверы Roblox',subtitle:'Укажите Place ID через запятую.',fields:[{name:'ids',label:'Разрешённые Place ID',type:'textarea',rows:3,required:true,placeholder:'123456789, 987654321'}],submitLabel:'Сохранить',onSubmit:async v=>{const ids=v.ids.split(',').map(x=>x.trim()).filter(Boolean);if(!ids.length){notify('Укажите хотя бы один ID');return false}await call('admin_set_roblox_places',{placeIds:ids});notify('Список серверов обновлён');return true}});
      });return;
    }
  }
  document.getElementById('robloxLinkButton')?.addEventListener('click',async()=>{
    const button=document.getElementById('robloxLinkButton');if(button){button.disabled=true;button.textContent='Создаём код…'}
    try{
      const r=await call('create_roblox_link');
      showModal({title:'Привязка Roblox',subtitle:'Откройте игру Royal Flight и введите этот одноразовый код в окне привязки.',content:'<div class="roblox-code-card"><span>ВАШ КОД</span><strong>'+esc(r.linkCode)+'</strong><small>Действует 10 минут</small><button class="copy-value" type="button" data-copy="'+esc(r.linkCode)+'">Копировать код</button></div><p class="modal-hint">Пароль от Roblox не требуется. Не передавайте этот код другим людям.</p>',actions:[{label:'Понятно',primary:true,onClick:closeModal}]});
      wireCopyButtons();
    }catch(e){notify(e.message)}
    finally{if(button){button.disabled=false;button.textContent='Привязать Roblox'}}
  });
  document.querySelectorAll('[data-admin]').forEach(b=>b.addEventListener('click',()=>adminAction(b.dataset.admin)));
  window.RoyalFlightApp={openPage,notify,telegramInitData:tg?.initData||null};
  signIn();
})();