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
  // Public browser configuration only; never place service-role/secret keys here.
  const SUPABASE_URL = 'https://iotwbzzlwltjfddrmhvg.supabase.co';
  const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlvdHdienpsd2x0amZkZHJtaHZnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI5NTEwNDksImV4cCI6MjEwODUyNzA0OX0.Bg-ww-s0WVpVwuJymjREB3z6eeY0S_8ZfFE5tnqUYz0';

  async function authenticateTelegram() {
    if (!tg?.initData) return;
    try {
      const response = await fetch(SUPABASE_URL + '/functions/v1/telegram-auth', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'apikey': SUPABASE_ANON_KEY },
        body: JSON.stringify({ initData: tg.initData }),
        cache: 'no-store'
      });
      const payload = await response.json();
      if (!response.ok || !payload.profile) {
        console.warn('Royal Flight sign-in is not ready:', payload.error || response.status);
        return;
      }
      const p = payload.profile;
      const miles = Number(p.miles || 0).toLocaleString('ru-RU');
      document.getElementById('milesBalance').textContent = miles;
      document.getElementById('milesBalanceDetail').textContent = miles;
      document.getElementById('robloxStatus').textContent = p.roblox_username ? 'Roblox: ' + p.roblox_username : 'Roblox не привязан';
      document.getElementById('robloxProfileText').textContent = p.roblox_username || 'Не привязан';
      const state = document.querySelector('.setting-state');
      if (state && p.roblox_username) state.textContent = 'Привязан';
      if (p.role === 'admin' || p.role === 'owner') {
        const adminNav = document.getElementById('adminNav');
        if (adminNav) adminNav.hidden = false;
      }
      window.RoyalFlightApp.profile = p;
    } catch (error) {
      console.warn('Royal Flight API temporarily unavailable.');
    }
  }
  // initDataUnsafe is used only for display personalization; authorization is server-verified.
  window.RoyalFlightApp={openPage,notify,telegramInitData:tg?.initData||null};
  authenticateTelegram();
})();