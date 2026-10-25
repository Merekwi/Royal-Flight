(() => {
  const tg = window.Telegram?.WebApp;
  if (tg) { tg.ready(); tg.expand(); try { tg.setHeaderColor('#07111f'); tg.setBackgroundColor('#07111f'); } catch (_) {} }
  const pages = [...document.querySelectorAll('.page')], navItems = [...document.querySelectorAll('.nav-item')], toast = document.getElementById('toast');
  let toastTimer;
  function notify(message) { toast.textContent=message; toast.classList.add('show'); clearTimeout(toastTimer); toastTimer=setTimeout(()=>toast.classList.remove('show'),2600); if(tg?.HapticFeedback) tg.HapticFeedback.impactOccurred('light'); }
  function openPage(name) { const target=document.getElementById('page-'+name); if(!target)return; pages.forEach(p=>p.classList.toggle('active',p===target)); navItems.forEach(n=>n.classList.toggle('active',n.dataset.page===name)); window.scrollTo({top:0,behavior:'smooth'}); if(tg?.HapticFeedback)tg.HapticFeedback.selectionChanged(); }
  document.querySelectorAll('[data-page]').forEach(el=>el.addEventListener('click',()=>openPage(el.dataset.page)));
  document.getElementById('profileShortcut').addEventListener('click',()=>openPage('profile'));
  const user=tg?.initDataUnsafe?.user;
  if(user){const name=[user.first_name,user.last_name].filter(Boolean).join(' ');document.getElementById('welcomeName').textContent=name?name+', добро пожаловать в Royal Flight':'Ваша программа лояльности Royal Flight';document.getElementById('profileName').textContent=name||'Пассажир Royal Flight';document.getElementById('telegramIdentity').textContent=user.username?'@'+user.username:'Telegram ID: '+user.id;const initials=[user.first_name,user.last_name].filter(Boolean).map(v=>v[0]).join('').slice(0,2).toUpperCase()||'RF';document.getElementById('avatarInitials').textContent=initials;document.getElementById('profileAvatar').textContent=initials;}else{document.getElementById('welcomeName').textContent='Откройте приложение через Telegram, чтобы войти в личный кабинет.';document.getElementById('telegramIdentity').textContent='Откройте Mini App через кнопку бота';}
  document.querySelectorAll('[data-admin]').forEach(button=>button.addEventListener('click',()=>{const names={payments:'Проверка оплат',flights:'Управление расписанием',services:'Каталог услуг',notifications:'Уведомления',users:'Участники',settings:'Настройки'};notify('Раздел «'+names[button.dataset.admin]+'» подключим на следующем этапе.');}));
  // Identity and authorization must be validated by a server function using Telegram initData.
  // initDataUnsafe is used here only to personalize the temporary interface, never for access control.
  window.RoyalFlightApp={openPage,notify,telegramInitData:tg?.initData||null};
})();