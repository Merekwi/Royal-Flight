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
  document.getElementById('profileShortcut').addEventListener('click',()=>openPage('profile'));
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const date=v=>v?new Date(v).toLocaleString('ru-RU',{day:'2-digit',month:'short',hour:'2-digit',minute:'2-digit'}):'—';
  const money=(v,c='RUB')=>new Intl.NumberFormat('ru-RU',{style:'currency',currency:c,maximumFractionDigits:2}).format(Number(v||0));
  async function call(action,extra={}){if(!tg?.initData)throw new Error('Откройте приложение через Telegram.');const r=await fetch(URL+'/functions/v1/rf-api',{method:'POST',headers:{'Content-Type':'application/json','apikey':KEY},body:JSON.stringify({initData:tg.initData,action,...extra}),cache:'no-store'});const d=await r.json();if(!r.ok)throw new Error(d.message||d.error||'Ошибка сервера');return d}
  async function signIn(){
    if(!tg?.initData)return;
    try{
      const r=await fetch(URL+'/functions/v1/telegram-auth',{method:'POST',headers:{'Content-Type':'application/json','apikey':KEY},body:JSON.stringify({initData:tg.initData}),cache:'no-store'});
      const d=await r.json();if(!r.ok||!d.profile){console.warn('Telegram authentication is not configured yet:',d.error);return}
      const p=d.profile,name=p.display_name||'Пассажир Royal Flight';
      document.getElementById('profileName').textContent=name;
      document.getElementById('welcomeName').textContent=name+', добро пожаловать в Royal Flight';
      document.getElementById('telegramIdentity').textContent=p.telegram_username?'@'+p.telegram_username:'Telegram ID: '+p.telegram_id;
      const initials=name.split(/\s+/).slice(0,2).map(x=>x[0]||'').join('').toUpperCase()||'RF';
      document.getElementById('avatarInitials').textContent=initials;document.getElementById('profileAvatar').textContent=initials;
      if(p.role==='admin'||p.role==='owner')document.getElementById('adminNav').hidden=false;
      await loadDashboard();
    }catch(e){console.warn('Royal Flight backend is not ready yet.')}
  }
  async function loadDashboard(){try{dashboard=await call('dashboard');render(dashboard)}catch(e){console.warn('Dashboard unavailable:',e.message)}}
  function render(d){
    const p=d.profile||{},m=Number(p.miles||0).toLocaleString('ru-RU');
    document.getElementById('milesBalance').textContent=m;document.getElementById('milesBalanceDetail').textContent=m;
    document.getElementById('robloxStatus').textContent=p.roblox_username?'Roblox: '+p.roblox_username:'Roblox не привязан';
    document.getElementById('robloxProfileText').textContent=p.roblox_username||'Не привязан';
    const fc=document.getElementById('flightCatalog');
    if(fc){fc.innerHTML=d.flights?.length?'<div class="data-list">'+d.flights.map(f=>'<article class="data-card"><div class="data-card-top"><span class="flight-tag">'+esc(f.flight_number||'RF FLIGHT')+'</span><span class="muted">'+esc(date(f.departure_at))+'</span></div><h3>'+esc(f.title)+'</h3><div class="route-line"><strong>'+esc(f.origin)+'</strong><span>✈ ─── ✈</span><strong>'+esc(f.destination)+'</strong></div><p class="muted">'+esc(f.aircraft||'Самолёт уточняется')+'</p>'+(f.description?'<p class="data-description">'+esc(f.description)+'</p>':'')+'</article>').join('')+'</div>':'<div class="empty-state"><div class="empty-orbit">✈</div><h3>Расписание готовится</h3><p>Когда администрация опубликует рейсы, они появятся здесь.</p></div>'}
    const sc=document.getElementById('serviceCatalog');
    if(sc){sc.innerHTML=d.services?.length?'<div class="service-list">'+d.services.map(s=>'<article class="data-card service-card"><div class="data-card-top"><span class="flight-tag">'+esc(s.code)+'</span><span class="service-duration">'+Number(s.duration_days)+' дней</span></div><h3>'+esc(s.name)+'</h3><p class="data-description">'+esc(s.description||'Временная привилегия Royal Flight.')+'</p><div class="service-buy-row"><strong>'+money(s.price,s.currency)+'</strong><button class="primary-button" data-buy="'+esc(s.id)+'">Оформить</button></div></article>').join('')+'</div>':'<div class="empty-state"><div class="empty-orbit">♛</div><h3>Каталог скоро откроется</h3><p>Все услуги будут доступны в одном месте с историей заказов и продлением доступа.</p></div>';sc.querySelectorAll('[data-buy]').forEach(b=>b.addEventListener('click',()=>createOrder(b.dataset.buy)))}
    const oh=document.getElementById('ordersHistory');
    if(oh){const orders=d.orders||[];oh.innerHTML='<h2 class="subheading orders-heading">Мои заказы</h2>'+(orders.length?'<div class="data-list">'+orders.map(o=>{const labels={awaiting_payment:'Ожидает оплаты',awaiting_review:'На проверке',paid:'Оплачен',rejected:'Отклонён',cancelled:'Отменён'};return '<article class="data-card order-card"><div class="data-card-top"><strong>'+esc(o.order_number)+'</strong><span class="order-status status-'+esc(o.status)+'">'+esc(labels[o.status]||o.status)+'</span></div><p class="muted">'+money(o.amount,o.currency)+' · '+date(o.created_at)+'</p>'+(o.admin_note?'<p class="data-description">'+esc(o.admin_note)+'</p>':'')+(o.status==='awaiting_payment'?'<button class="secondary-button" data-mark-paid="'+esc(o.id)+'">Я оплатил</button>':'')+'</article>'}).join('')+'</div>':'<div class="empty-card"><span class="empty-icon">▣</span><div><strong>Заказов пока нет</strong><p>Оформленные услуги появятся здесь.</p></div></div>');oh.querySelectorAll('[data-mark-paid]').forEach(b=>b.addEventListener('click',()=>markPaid(b.dataset.markPaid)))}
    const announcement=document.querySelector('#page-home .empty-card');
    if(announcement&&d.announcements?.length){announcement.outerHTML='<div class="data-list">'+d.announcements.map(n=>'<article class="data-card"><h3>'+esc(n.title)+'</h3><p class="data-description">'+esc(n.body)+'</p><p class="muted">'+date(n.sent_at||n.created_at)+'</p></article>').join('')+'</div>'}
    if(d.admin&&(p.role==='admin'||p.role==='owner'))renderAdmin(d.admin);
  }
  async function createOrder(serviceId){
    const methods=dashboard?.paymentMethods||[];if(!methods.length){notify('Администрация ещё не добавила реквизиты оплаты.');return}
    const choice=prompt('Выберите способ оплаты, введя номер:\n'+methods.map((m,i)=>(i+1)+'. '+m.label+' — '+(m.recipient_name||'получатель не указан')).join('\n'),'1');
    if(choice===null)return;const method=methods[Number(choice)-1];if(!method){notify('Неверный способ оплаты.');return}
    try{const x=await call('create_order',{serviceId,paymentMethodId:method.id}),o=x.order;const info=['Заказ: '+o.order_number,'Сумма: '+money(o.amount,o.currency),'Карта: '+method.card_number,method.recipient_name?'Получатель: '+method.recipient_name:'',method.instructions||'','Комментарий к переводу: '+o.order_number].filter(Boolean).join('\n');alert('Переведите точную сумму и обязательно укажите номер заказа в комментарии к платежу.\n\n'+info);await loadDashboard();openPage('services')}catch(e){notify(e.message)}
  }
  async function markPaid(id){const note=prompt('Комментарий для администрации (необязательно):','');if(note===null)return;try{await call('mark_paid',{orderId:id,userNote:note});notify('Заявка отправлена на проверку.');await loadDashboard()}catch(e){notify(e.message)}}
  function renderAdmin(a){
    const box=document.getElementById('adminPayments');if(!box)return;const orders=a.pendingOrders||[];
    box.innerHTML='<h2 class="subheading orders-heading">Заявки на оплату <span class="count-badge">'+orders.length+'</span></h2>'+(orders.length?'<div class="data-list">'+orders.map(o=>'<article class="data-card order-card"><div class="data-card-top"><strong>'+esc(o.order_number)+'</strong><span class="order-status status-awaiting_review">На проверке</span></div><p class="muted">'+money(o.amount,o.currency)+' · '+date(o.created_at)+'</p>'+(o.user_note?'<p class="data-description">'+esc(o.user_note)+'</p>':'')+(o.proof_url?'<p><a class="proof-link" target="_blank" rel="noopener" href="'+esc(o.proof_url)+'">Открыть подтверждение</a></p>':'')+'<div class="button-row"><button class="primary-button" data-paid="'+esc(o.id)+'">Оплачено</button><button class="secondary-button" data-reject="'+esc(o.id)+'">Не оплачено</button></div></article>').join('')+'</div>':'<div class="empty-card"><span class="empty-icon">✓</span><div><strong>Нет ожидающих заявок</strong><p>Заявки появятся после нажатия пользователем «Я оплатил».</p></div></div>');
    box.querySelectorAll('[data-paid]').forEach(b=>b.addEventListener('click',()=>review(b.dataset.paid,true)));
    box.querySelectorAll('[data-reject]').forEach(b=>b.addEventListener('click',()=>review(b.dataset.reject,false)));
  }
  async function review(id,paid){const note=prompt(paid?'Комментарий к подтверждению (необязательно):':'Причина отказа (обязательно):','');if(note===null)return;if(!paid&&!note.trim()){notify('Укажи причину отказа.');return}try{await call('admin_review_order',{orderId:id,paid,note});notify(paid?'Оплата подтверждена, услуга активирована.':'Заявка отклонена.');await loadDashboard()}catch(e){notify(e.message)}}
  async function adminAction(section){
    try{
      if(section==='payments'){openPage('admin');document.getElementById('adminPayments')?.scrollIntoView({behavior:'smooth'});return}
      if(section==='flights'){const title=prompt('Название рейса:');if(!title)return;const origin=prompt('Город вылета:');if(!origin)return;const destination=prompt('Город прилёта:');if(!destination)return;const departureAt=prompt('Дата и время вылета в ISO, например 2026-11-01T18:00:00+03:00:');if(!departureAt)return;const flightNumber=prompt('Номер рейса (необязательно):','RF001')||'';const aircraft=prompt('Самолёт (необязательно):','Boeing 737-800')||'';const cap=prompt('Количество мест (необязательно):','')||'';await call('admin_create_flight',{flight:{title,origin,destination,departureAt,flightNumber,aircraft,capacity:cap?Number(cap):null}});notify('Рейс создан.');await loadDashboard();openPage('flights');return}
      if(section==='services'){const code=prompt('Код услуги, например BUSINESS:');if(!code)return;const name=prompt('Название услуги:');if(!name)return;const price=prompt('Стоимость:','300');if(price===null)return;const durationDays=prompt('Срок действия в днях:','30');if(durationDays===null)return;const description=prompt('Описание (необязательно):','')||'';await call('admin_save_service',{service:{code,name,price:Number(price),durationDays:Number(durationDays),description,currency:'RUB'}});notify('Услуга добавлена.');await loadDashboard();return}
      if(section==='settings'){const rate=prompt('Миль за минуту онлайн:','10');if(rate===null)return;await call('admin_set_miles_rate',{milesPerMinute:Number(rate)});notify('Ставка обновлена.');return}
      if(section==='notifications'){const title=prompt('Заголовок уведомления:');if(!title)return;const body=prompt('Текст уведомления:');if(!body)return;const audience=prompt('Аудитория: all / admins / roblox_linked / active_service','all')||'all';const scheduledAt=prompt('Время отправки ISO (пусто — сохранить черновик):','')||null;await call('admin_create_notification',{notification:{title,body,audience,scheduledAt}});notify('Уведомление сохранено. Отправку ботом подключим отдельно.');return}
      notify('Управление участниками подключим следующим этапом.')
    }catch(e){notify(e.message||'Действие не выполнено.')}
  }
  document.querySelectorAll('[data-admin]').forEach(b=>b.addEventListener('click',()=>adminAction(b.dataset.admin)));
  window.RoyalFlightApp={openPage,notify,telegramInitData:tg?.initData||null};
  signIn();
})();