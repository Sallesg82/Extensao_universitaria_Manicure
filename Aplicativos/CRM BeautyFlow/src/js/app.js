const API = window.location.origin + '/api'

let currentUser = null

// ── Socket.IO ────────────────────────────────────────
let _socket = null
let _pageRefreshPending = {}

function connectSocket() {
  if (typeof io === 'undefined') return
  _socket = io(window.location.origin, {
    transports: ['websocket', 'polling'],
    reconnection: true,
    reconnectionDelay: 2000,
  })
  _socket.on('connect', () => console.log('[WS] Conectado'))
  _socket.on('disconnect', () => console.log('[WS] Desconectado'))

  _socket.on('data:changed', (data) => {
    _requestPageRefresh(data.type)
  })
  _socket.on('appointment:created', () => _requestPageRefresh('appointment'))
  _socket.on('appointment:updated', () => _requestPageRefresh('appointment'))
  _socket.on('appointment:deleted', () => _requestPageRefresh('appointment'))
  _socket.on('client:created', () => _requestPageRefresh('client'))
  _socket.on('client:updated', () => _requestPageRefresh('client'))
  _socket.on('client:deleted', () => _requestPageRefresh('client'))
  _socket.on('service:changed', () => _requestPageRefresh('service'))
  _socket.on('transaction:created', () => _requestPageRefresh('transaction'))
  _socket.on('transaction:updated', () => _requestPageRefresh('transaction'))
  _socket.on('transaction:deleted', () => _requestPageRefresh('transaction'))
}

function _requestPageRefresh(type) {
  const pageId = (location.hash.slice(1) || 'dashboard')
  const key = pageId + ':' + type
  if (_pageRefreshPending[key]) return
  _pageRefreshPending[key] = true
  setTimeout(() => {
    delete _pageRefreshPending[key]
    const activePage = document.querySelector('.page.active')
    if (!activePage) return
    // Always refresh the notification dot
    loadNotifDot()
    // Only refresh if the user is still on the same page
    if (document.hidden) return
    const currentPageId = location.hash.slice(1) || 'dashboard'
    if (currentPageId !== pageId) return

    if (currentPageId === 'dashboard') loadDashboard()
    else if (currentPageId === 'agenda') showAgendaView()
    else if (currentPageId === 'clientes') loadClients()
    else if (currentPageId === 'relatorios') loadRelatorios()
    else if (currentPageId === 'financeiro') loadFinanceiro()
    else if (currentPageId === 'servicos') loadServicos()
  }, 300)
}

// Connect after login (when user is authenticated)
document.addEventListener('DOMContentLoaded', () => {
  const saved = localStorage.getItem('bf_user')
  if (saved) connectSocket()
})

function renderLoginForm() {
  const form = document.getElementById('auth-form')
  form.innerHTML = `
    <div class="auth-field">
      <label>Email</label>
      <input type="email" id="login-email" placeholder="seu@email.com" autocomplete="email">
    </div>
    <div class="auth-field">
      <label>Senha</label>
      <input type="password" id="login-password" placeholder="••••••" autocomplete="current-password">
    </div>
    <button class="auth-btn" id="auth-btn" onclick="handleLogin()">Entrar</button>
  `
  document.getElementById('auth-msg').textContent = ''
  document.getElementById('auth-msg').className = 'auth-msg'
  document.getElementById('auth-link').innerHTML = '<a onclick="renderRegisterForm()">Não tem conta? Registre-se</a>'
  document.getElementById('login-email').addEventListener('keydown', e => { if (e.key === 'Enter') handleLogin() })
  document.getElementById('login-password').addEventListener('keydown', e => { if (e.key === 'Enter') handleLogin() })
  document.getElementById('login-email').focus()
}

function renderRegisterForm() {
  const form = document.getElementById('auth-form')
  form.innerHTML = `
    <div class="auth-name-row">
      <div class="auth-field">
        <label>Nome</label>
        <input type="text" id="reg-name" placeholder="Seu nome" autocomplete="name">
      </div>
      <div class="auth-field">
        <label>Telefone</label>
        <input type="text" id="reg-phone" placeholder="(11) 99999-8888" autocomplete="tel">
      </div>
    </div>
    <div class="auth-field">
      <label>Email</label>
      <input type="email" id="reg-email" placeholder="seu@email.com" autocomplete="email">
    </div>
    <div class="auth-field">
      <label>Senha</label>
      <input type="password" id="reg-password" placeholder="••••••" autocomplete="new-password">
    </div>
    <button class="auth-btn" id="auth-btn" onclick="handleRegister()">Criar Conta</button>
  `
  document.getElementById('auth-msg').textContent = ''
  document.getElementById('auth-msg').className = 'auth-msg'
  document.getElementById('auth-link').innerHTML = '<a onclick="renderLoginForm()">Já tem conta? Faça login</a>'
  document.getElementById('reg-name').focus()
}

function showAuthMessage(msg, type) {
  const el = document.getElementById('auth-msg')
  el.textContent = msg
  el.className = 'auth-msg ' + type
}

async function handleLogin() {
  const email = document.getElementById('login-email').value.trim()
  const password = document.getElementById('login-password').value
  if (!email || !password) { showAuthMessage('Preencha todos os campos.', 'error'); return }
  const btn = document.getElementById('auth-btn')
  btn.disabled = true; btn.textContent = 'Entrando...'
  try {
    const r = await fetch(API + '/users/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    })
    const data = await r.json()
    if (!r.ok) { showAuthMessage(data.error || 'Erro ao entrar.', 'error'); btn.disabled = false; btn.textContent = 'Entrar'; return }
    currentUser = data
    localStorage.setItem('bf_user', JSON.stringify(data))
    showApp()
  } catch (e) { showAuthMessage('Erro de conexão.', 'error'); btn.disabled = false; btn.textContent = 'Entrar' }
}

async function handleRegister() {
  const name = document.getElementById('reg-name').value.trim()
  const phone = document.getElementById('reg-phone').value.trim()
  const email = document.getElementById('reg-email').value.trim()
  const password = document.getElementById('reg-password').value
  if (!name || !email || !password) { showAuthMessage('Preencha nome, email e senha.', 'error'); return }
  const btn = document.getElementById('auth-btn')
  btn.disabled = true; btn.textContent = 'Criando...'
  try {
    const r = await fetch(API + '/users/', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, email, password, phone })
    })
    const data = await r.json()
    if (!r.ok) { showAuthMessage(data.error || 'Erro ao criar conta.', 'error'); btn.disabled = false; btn.textContent = 'Criar Conta'; return }
    currentUser = data
    localStorage.setItem('bf_user', JSON.stringify(data))
    showApp()
  } catch (e) { showAuthMessage('Erro de conexão.', 'error'); btn.disabled = false; btn.textContent = 'Criar Conta' }
}

function logout() {
  currentUser = null
  localStorage.removeItem('bf_user')
  const ls = document.getElementById('loadingScreen')
  if (ls) ls.classList.remove('hide')
  setTimeout(() => {
    if (ls) ls.classList.add('hide')
    document.getElementById('auth-page').classList.remove('hide')
    document.querySelector('.screen').style.display = 'none'
    renderLoginForm()
  }, 100)
}

function showApp() {
  document.getElementById('auth-page').classList.add('hide')
  document.querySelector('.screen').style.display = 'flex'
  navigateFromHash()
  updateUserCard()
  connectSocket()
}

function updateUserCard() {
  const card = document.querySelector('.user-card')
  if (!card || !currentUser) return
  const ini = (currentUser.name || '').split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase()
  card.querySelector('.avatar').textContent = ini || '?'
  card.querySelector('.user-name').textContent = currentUser.name || ''
  card.querySelector('.user-role').textContent = currentUser.role === 'admin' ? 'Administradora' : 'Usuário'

  const nav = document.querySelector('.usuarios-nav')
  if (nav) nav.style.display = currentUser.role === 'admin' ? '' : 'none'
  document.querySelector('#settings-nav-integ')?.classList.toggle('hide', currentUser.role !== 'admin')
}

async function checkAuth() {
  const saved = localStorage.getItem('bf_user')
  if (saved) {
    try {
      currentUser = JSON.parse(saved)
      showApp()
      return
    } catch (e) { localStorage.removeItem('bf_user') }
  }
  renderLoginForm()
}
let ignoreHash = false
let refreshTimer = null

function startPageRefresh(pageId) {
  stopPageRefresh()
  const map = {
    dashboard: { ms: 10000, fn: loadDashboard },
    agenda:    { ms: 10000, fn: loadAgenda },
    clientes:  { ms: 30000, fn: loadClients },
    relatorios: { ms: 30000, fn: loadRelatorios },
    financeiro: { ms: 15000, fn: loadFinanceiro },
  }
  const c = map[pageId]
  if (!c) return
  refreshTimer = setInterval(() => {
    if (!document.hidden) c.fn()
  }, c.ms)
}

let _notifTimer
function startNotifPoll() {
  if (_notifTimer) return
  loadNotifDot()
  // Notification polling is a fallback - socket events will also trigger it
  _notifTimer = setInterval(() => {
    if (!document.hidden) loadNotifDot()
  }, 15000)
}

function stopPageRefresh() {
  if (refreshTimer) { clearInterval(refreshTimer); refreshTimer = null }
}

function navigateFromHash() {
  const pageId = location.hash.slice(1) || 'dashboard'
  const navEl = document.querySelector(`.nav-item[onclick*="'${pageId}'"]`)
  showPage(pageId, navEl)
}

window.addEventListener('hashchange', () => {
  if (ignoreHash) { ignoreHash = false; return }
  navigateFromHash()
})

const pageConfig = {
  dashboard:      { title: 'Painel Geral',    sub: '',      btn: '+ Novo Agendamento' },
  agenda:         { title: 'Agenda',          sub: '',      btn: '+ Novo Agendamento' },
  clientes:       { title: 'Clientes',        sub: '',      btn: '+ Nova Cliente' },
  servicos:       { title: 'Serviços',        sub: '',      btn: '+ Novo Serviço' },
  metas:          { title: 'Metas',           sub: '',      btn: null },
  financeiro:     { title: 'Financeiro',      sub: '',      btn: '+ Novo Lançamento' },
  despesas:       { title: 'Despesas do Mês', sub: 'Acompanhe seus gastos', btn: null },
  relatorios:     { title: 'Relatórios',      sub: 'Análise dos últimos 30 dias',      btn: '⬇ Exportar PDF' },
  usuarios:       { title: 'Usuários',        sub: 'Gerenciar contas de acesso',          btn: null },
  configuracoes:  { title: 'Configurações',   sub: 'Gerencie seu sistema BeautyFlow',      btn: null },
}

function showPage(pageId, navEl) {
  stopPageRefresh()

  if (pageId === 'usuarios' && currentUser && currentUser.role !== 'admin') {
    pageId = 'dashboard'
    navEl = document.querySelector('.nav-item[onclick*="\'dashboard\'"]')
  }
  if (pageId === 'configuracoes' && currentUser && currentUser.role !== 'admin') {
    document.querySelector('#settings-nav-integ')?.classList.add('hide')
  } else {
    document.querySelector('#settings-nav-integ')?.classList.remove('hide')
  }

  if (location.hash !== '#' + pageId) {
    ignoreHash = true
    location.hash = pageId
  }

  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'))
  document.getElementById('page-' + pageId).classList.add('active')

  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'))
  if (navEl) navEl.classList.add('active')

  closeMobileMenu()

  const cfg = pageConfig[pageId]
  document.getElementById('page-title').textContent = cfg.title
  document.getElementById('page-sub').textContent = cfg.sub
  const btn = document.getElementById('topbar-btn')
  if (cfg.btn) { btn.textContent = cfg.btn; btn.style.display = '' }
  else { btn.style.display = 'none' }

  if (pageId === 'dashboard') loadDashboard()
  else if (pageId === 'clientes') loadClients()
  else if (pageId === 'servicos') loadServicos()
  else if (pageId === 'metas') loadMetas()
  else if (pageId === 'agenda') loadAgenda()
  else if (pageId === 'financeiro') loadFinanceiro()
  else if (pageId === 'despesas') loadDespesas()
  else if (pageId === 'usuarios') loadUsuarios()
  else if (pageId === 'relatorios') loadRelatorios()
  else if (pageId === 'configuracoes') updateProfileTab()

  startPageRefresh(pageId)
}

function handleTopbarBtn() {
  const activePage = document.querySelector('.page.active')
  if (!activePage) return
  const pageId = activePage.id.replace('page-', '')
  if (pageId === 'dashboard' || pageId === 'agenda') {
    openAppointmentModal()
  } else if (pageId === 'clientes') {
    openClientModal()
  } else if (pageId === 'servicos') {
    openServiceModal()
  } else if (pageId === 'financeiro') {
    openTransactionModal()
  } else if (pageId === 'relatorios') {
    loadRelatorios()
    const btn = document.getElementById('topbar-btn')
    const orig = btn.textContent
    btn.textContent = '⏳ Exportando...'
    setTimeout(() => { btn.textContent = orig }, 2000)
  } else if (pageId === 'usuarios') {
    loadUsuarios()
  }
}

function showSettingsTab(navEl, tabId) {
  if (tabId === 'tab-integ' && currentUser && currentUser.role !== 'admin') {
    tabId = 'tab-perfil'
    navEl = document.querySelector('.settings-nav-item.active')
  }
  document.querySelectorAll('.settings-nav-item').forEach(n => n.classList.remove('active'))
  navEl.classList.add('active')
  ;['tab-perfil','tab-horarios','tab-notif','tab-integ','tab-aparencia'].forEach(id => {
    document.getElementById(id).style.display = id === tabId ? '' : 'none'
  })
  if (tabId === 'tab-perfil') updateProfileTab()
  if (tabId === 'tab-integ') { loadIntegrations() }
  if (tabId === 'tab-horarios') { loadBusinessHours() }
}

// ── BUSINESS HOURS ──────────────────────────────────

async function loadBusinessHours() {
  const body = document.getElementById('business-hours-body')
  if (!body) return
  try {
    const res = await fetch(API + '/business-hours')
    const data = await res.json()
    const days = [
      { key: 'segunda', label: 'Segunda-feira' },
      { key: 'terca',   label: 'Terça-feira' },
      { key: 'quarta',  label: 'Quarta-feira' },
      { key: 'quinta',  label: 'Quinta-feira' },
      { key: 'sexta',   label: 'Sexta-feira' },
      { key: 'sabado',  label: 'Sábado' },
      { key: 'domingo',  label: 'Domingo' },
    ]
    body.innerHTML = days.map(d => {
      const h = data[d.key] || { open: '08:00', close: '18:00', closed: false }
      const closed = h.closed
      return `
        <div class="hours-day-row" data-day="${d.key}">
          <div class="hours-day-label">${d.label}</div>
          <label class="toggle-switch hours-toggle">
            <input type="checkbox" class="hours-closed-chk" ${closed ? '' : 'checked'}>
            <span class="toggle-slider"></span>
          </label>
          <span class="hours-status-label">${closed ? 'Fechado' : 'Aberto'}</span>
          <div class="hours-time-fields" style="${closed ? 'opacity:0.4;pointer-events:none;' : ''}">
            <input type="time" class="form-input hours-open" value="${h.open || '08:00'}" style="width:120px;">
            <span class="hours-sep">até</span>
            <input type="time" class="form-input hours-close" value="${h.close || '18:00'}" style="width:120px;">
          </div>
        </div>`
    }).join('') + `
      <div class="save-bar">
        <button class="btn-primary" onclick="saveBusinessHours()">Salvar Horários</button>
        <span id="hours-status" class="integ-status" style="margin-left:12px;"></span>
      </div>`

    // Toggle closed/open
    body.querySelectorAll('.hours-closed-chk').forEach(chk => {
      chk.addEventListener('change', function() {
        const row = this.closest('.hours-day-row')
        const fields = row.querySelector('.hours-time-fields')
        const status = row.querySelector('.hours-status-label')
        if (this.checked) {
          fields.style.opacity = '1'
          fields.style.pointerEvents = ''
          status.textContent = 'Aberto'
        } else {
          fields.style.opacity = '0.4'
          fields.style.pointerEvents = 'none'
          status.textContent = 'Fechado'
        }
      })
    })
  } catch (e) {
    body.innerHTML = '<div class="integ-empty">Erro ao carregar horários.</div>'
  }
}

async function saveBusinessHours() {
  const body = document.getElementById('business-hours-body')
  const status = document.getElementById('hours-status')
  if (!body || !status) return
  const rows = body.querySelectorAll('.hours-day-row')
  const data = {}
  rows.forEach(row => {
    const key = row.dataset.day
    const chk = row.querySelector('.hours-closed-chk')
    const open = row.querySelector('.hours-open')
    const close = row.querySelector('.hours-close')
    data[key] = {
      open: chk.checked ? (open.value || '08:00') : '',
      close: chk.checked ? (close.value || '18:00') : '',
      closed: !chk.checked,
    }
  })
  status.textContent = 'Salvando...'
  status.className = 'integ-status wait'
  try {
    const res = await fetch(API + '/business-hours', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    })
    if (res.ok) {
      status.textContent = 'Horários salvos com sucesso!'
      status.className = 'integ-status ok'
    } else {
      status.textContent = 'Erro ao salvar.'
      status.className = 'integ-status err'
    }
  } catch (e) {
    status.textContent = 'Erro de conexão.'
    status.className = 'integ-status err'
  }
}

function updateProfileTab() {
  if (!currentUser) return
  const avatar = document.getElementById('profile-avatar')
  const name = document.getElementById('profile-name')
  const role = document.getElementById('profile-role')
  const ini = (currentUser.name || '').split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase()
  if (avatar) avatar.textContent = ini || '?'
  if (name) name.textContent = currentUser.name || ''
  if (role) role.textContent = currentUser.role === 'admin' ? 'Administradora' : 'Usuário'
  const inputName = document.getElementById('profile-input-name')
  const inputEmail = document.getElementById('profile-input-email')
  const inputPhone = document.getElementById('profile-input-phone')
  const inputRole = document.getElementById('profile-input-role')
  if (inputName) inputName.value = currentUser.name || ''
  if (inputEmail) inputEmail.value = currentUser.email || ''
  if (inputPhone) inputPhone.value = currentUser.phone || ''
  if (inputRole) inputRole.value = currentUser.role === 'admin' ? 'Administradora' : 'Usuário'
}

async function saveProfile() {
  if (!currentUser || !currentUser.id) return
  const name = document.getElementById('profile-input-name').value.trim()
  const phone = document.getElementById('profile-input-phone').value.trim()
  if (!name) return
  try {
    const r = await fetch(API + '/users/' + currentUser.id, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, phone })
    })
    const data = await r.json()
    if (r.ok) {
      currentUser = data
      localStorage.setItem('bf_user', JSON.stringify(data))
      updateProfileTab()
      updateUserCard()
    }
  } catch (e) {}
}

// ── USUÁRIOS ────────────────────────────────────

async function loadUsuarios() {
  try {
    const r = await fetch(API + '/users/')
    const users = await r.json()
    const tbody = document.getElementById('users-tbody')
    if (!tbody) return
    if (users.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;padding:20px;color:var(--text-secondary);">Nenhum usuário cadastrado</td></tr>'
      return
    }
    tbody.innerHTML = users.map(u => {
      const date = u.created_at ? u.created_at.split('T')[0].split('-').reverse().join('/') : '—'
      const isSelf = currentUser && currentUser.id === u.id
      return `<tr>
        <td><div class="user-cell-name">${u.name}${isSelf ? ' <span style="color:var(--primary-500);font-size:11px;">(você)</span>' : ''}</div></td>
        <td>${u.email}</td>
        <td>${u.phone || '—'}</td>
        <td>${u.role === 'admin' ? 'Administradora' : 'Usuário'}</td>
        <td>${date}</td>
        <td>${u.role !== 'admin' || !isSelf ? `<button class="btn-outline btn-sm btn-danger" onclick="deleteUser(${u.id},'${u.name}')">Remover</button>` : ''}</td>
      </tr>`
    }).join('')
  } catch (e) {
    console.error('Erro ao carregar usuários:', e)
  }
}

function showCreateUserModal() {
  const html = `
    <div class="modal-overlay" id="create-user-overlay" onclick="if(event.target===this)closeCreateUserModal()">
      <div class="modal-card" style="max-width:420px;">
        <div class="modal-header"><div class="modal-title">Novo Usuário</div><button class="modal-close" onclick="closeCreateUserModal()">×</button></div>
        <div class="modal-body">
          <div class="form-row"><div class="form-field full"><label class="form-label">Nome</label><input class="form-input" id="cu-name" placeholder="Nome completo"></div></div>
          <div class="form-row"><div class="form-field full"><label class="form-label">Email</label><input class="form-input" id="cu-email" type="email" placeholder="email@exemplo.com"></div></div>
          <div class="form-row"><div class="form-field full"><label class="form-label">Telefone</label><input class="form-input" id="cu-phone" placeholder="(11) 99999-8888"></div></div>
          <div class="form-row"><div class="form-field full"><label class="form-label">Senha</label><input class="form-input" id="cu-password" type="password" placeholder="••••••"></div></div>
          <div class="form-row"><div class="form-field full"><label class="form-label">Tipo</label><select class="form-input" id="cu-role"><option value="user">Comum</option><option value="admin">Administrador</option></select></div></div>
          <div id="cu-msg" class="auth-msg"></div>
        </div>
        <div class="modal-footer"><button class="btn-outline" onclick="closeCreateUserModal()">Cancelar</button><button class="btn-primary" onclick="createUser()">Criar</button></div>
      </div>
    </div>`
  const div = document.createElement('div')
  div.innerHTML = html
  document.body.appendChild(div)
  requestAnimationFrame(() => document.getElementById('create-user-overlay').classList.add('open'))
  document.getElementById('cu-name').focus()
  ;['cu-name','cu-email','cu-phone','cu-password','cu-role'].forEach(id => {
    document.getElementById(id)?.addEventListener('keydown', e => {
      if (e.key === 'Enter') createUser()
    })
  })
}

function closeCreateUserModal() {
  const el = document.getElementById('create-user-overlay')
  if (el) {
    el.classList.remove('open')
    setTimeout(() => el.remove(), 200)
  }
}

async function createUser() {
  const name = document.getElementById('cu-name').value.trim()
  const email = document.getElementById('cu-email').value.trim()
  const phone = document.getElementById('cu-phone').value.trim()
  const password = document.getElementById('cu-password').value
  const msg = document.getElementById('cu-msg')
  if (!name || !email || !password) { msg.textContent = 'Preencha nome, email e senha.'; msg.className = 'auth-msg error'; return }
  try {
    const r = await fetch(API + '/users/', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, email, password, phone, role: document.getElementById('cu-role').value })
    })
    const data = await r.json()
    if (r.ok) { closeCreateUserModal(); loadUsuarios() }
    else { msg.textContent = data.error || 'Erro ao criar.'; msg.className = 'auth-msg error' }
  } catch (e) { msg.textContent = 'Erro de conexão.'; msg.className = 'auth-msg error' }
}

async function deleteUser(id, name) {
  if (!confirm(`Remover usuário "${name}"?`)) return
  try {
    const r = await fetch(API + '/users/' + id, { method: 'DELETE' })
    if (r.ok) loadUsuarios()
  } catch (e) {}
}

async function changePassword() {
  const pwd = document.getElementById('pwd-new').value
  const confirm = document.getElementById('pwd-confirm').value
  const msg = document.getElementById('pwd-msg')
  if (!pwd || pwd.length < 4) { msg.textContent = 'A senha deve ter no mínimo 4 caracteres.'; msg.className = 'auth-msg error'; return }
  if (pwd !== confirm) { msg.textContent = 'As senhas não conferem.'; msg.className = 'auth-msg error'; return }
  if (!currentUser || !currentUser.id) return
  try {
    const r = await fetch(API + '/users/' + currentUser.id + '/password', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ password: pwd })
    })
    const data = await r.json()
    if (r.ok) { msg.textContent = 'Senha alterada com sucesso!'; msg.className = 'auth-msg success'; document.getElementById('pwd-new').value = ''; document.getElementById('pwd-confirm').value = '' }
    else { msg.textContent = data.error || 'Erro ao alterar senha.'; msg.className = 'auth-msg error' }
  } catch (e) { msg.textContent = 'Erro de conexão.'; msg.className = 'auth-msg error' }
}

// ── N8N INTEGRAÇÃO ─────────────────────────────────

async function loadN8nConfig() {
  const status = document.getElementById('n8n-status')
  try {
    const r = await fetch(API + '/n8n/config')
    const data = await r.json()
    const g = id => document.getElementById(id)
    if (g('n8n-url')) g('n8n-url').value = data.n8n_webhook_url || ''
    if (g('n8n-enabled')) g('n8n-enabled').checked = data.n8n_enabled !== 'false'
    if (g('n8n-timeout')) g('n8n-timeout').value = data.n8n_timeout || 8
    if (g('n8n-header-name')) g('n8n-header-name').value = data.n8n_header_name || ''
    if (g('n8n-header-value')) g('n8n-header-value').value = data.n8n_header_value || ''

    const events = (data.n8n_events || 'create,update,delete').split(',')
    ;['n8n-ev-create','n8n-ev-update','n8n-ev-delete'].forEach(id => {
      const el = g(id)
      if (el) el.checked = events.includes(el.value)
    })

    if (status) {
      const hasUrl = !!data.n8n_webhook_url
      status.textContent = hasUrl ? 'Configuração carregada.' : 'Nenhuma URL configurada.'
      status.className = 'integ-status'
    }
  } catch (e) {
    if (status) { status.textContent = 'Erro ao carregar config.'; status.className = 'integ-status err' }
  }
}

async function saveN8nConfig() {
  const status = document.getElementById('n8n-status')
  if (!status) return
  const g = id => document.getElementById(id)
  const events = ['n8n-ev-create','n8n-ev-update','n8n-ev-delete']
    .filter(id => g(id)?.checked)
    .map(id => g(id).value)
    .join(',')

  const body = {
    n8n_webhook_url: (g('n8n-url')?.value || '').trim(),
    n8n_enabled: g('n8n-enabled')?.checked ? 'true' : 'false',
    n8n_events: events || 'create,update,delete',
    n8n_timeout: g('n8n-timeout')?.value || '8',
    n8n_header_name: (g('n8n-header-name')?.value || '').trim(),
    n8n_header_value: (g('n8n-header-value')?.value || '').trim(),
  }
  if (g('n8n-url')) g('n8n-url').value = body.n8n_webhook_url

  status.textContent = 'Salvando...'
  status.className = 'integ-status wait'
  try {
    const r = await fetch(API + '/n8n/config', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    })
    if (r.ok) {
      status.textContent = 'Configuração salva com sucesso!'
      status.className = 'integ-status ok'
    } else {
      const err = await r.json()
      status.textContent = err.error || 'Erro ao salvar.'
      status.className = 'integ-status err'
    }
  } catch (e) {
    status.textContent = 'Erro de conexão.'
    status.className = 'integ-status err'
  }
}

async function testN8n() {
  const status = document.getElementById('n8n-status')
  const input = document.getElementById('n8n-url')
  if (!status) return
  const url = (input ? input.value : '').trim()
  status.textContent = 'Enviando webhook de teste...'
  status.className = 'integ-status wait'
  try {
    const r = await fetch(API + '/n8n/test', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ webhook_url: url || undefined })
    })
    const data = await r.json()
    if (r.ok) {
      status.textContent = '✓ ' + (data.message || 'Webhook funcionando!')
      status.className = 'integ-status ok'
    } else {
      status.textContent = '✗ ' + (data.error || 'Falha no teste.')
      status.className = 'integ-status err'
    }
  } catch (e) {
    status.textContent = '✗ Erro de conexão com o servidor.'
    status.className = 'integ-status err'
  }
}

// ── GOOGLE CALENDAR INTEGRAÇÃO ────────────────────

async function loadGoogleConfig() {
  const cid = document.getElementById('google-client-id')
  const sec = document.getElementById('google-client-secret')
  const status = document.getElementById('google-status')
  const connectRow = document.getElementById('google-connect-row')
  const connectBtn = document.getElementById('google-connect-btn')
  const disconnectBtn = document.getElementById('google-disconnect-btn')
  if (!cid) return
  try {
    const r = await fetch(API + '/google/config')
    const data = await r.json()
    cid.value = data.client_id || ''
    const sr = await fetch(API + '/google/status')
    const gs = await sr.json()
    if (gs.connected) {
      connectRow.style.display = ''
      connectBtn.style.display = 'none'
      disconnectBtn.style.display = ''
      if (status) { status.textContent = '✓ Conectado ao Google Calendar'; status.className = 'integ-status ok' }
    } else {
      const hasCreds = data.client_id && data.client_secret !== ''
      if (hasCreds) {
        connectRow.style.display = ''
        connectBtn.style.display = ''
        disconnectBtn.style.display = 'none'
        if (status) { status.textContent = 'Clique em "Conectar com Google" para autorizar.'; status.className = 'integ-status' }
      } else {
        connectRow.style.display = 'none'
        if (status) { status.textContent = 'Preencha Client ID e Client Secret acima.'; status.className = 'integ-status' }
      }
    }
  } catch (e) {
    if (status) { status.textContent = 'Erro ao carregar config.'; status.className = 'integ-status err' }
  }
}

async function saveGoogleConfig() {
  const cid = document.getElementById('google-client-id')
  const sec = document.getElementById('google-client-secret')
  const status = document.getElementById('google-status')
  if (!status) return
  status.textContent = 'Salvando...'
  status.className = 'integ-status wait'
  try {
    const r = await fetch(API + '/google/config', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ client_id: (cid.value || '').trim(), client_secret: (sec.value || '').trim() })
    })
    if (r.ok) {
      status.textContent = 'Credenciais salvas! Conecte com o Google abaixo.'
      status.className = 'integ-status ok'
      loadGoogleConfig()
    } else {
      status.textContent = 'Erro ao salvar.'
      status.className = 'integ-status err'
    }
  } catch (e) {
    status.textContent = 'Erro de conexão.'
    status.className = 'integ-status err'
  }
}

async function connectGoogle() {
  const status = document.getElementById('google-status')
  if (!status) return
  status.textContent = 'Redirecionando para o Google...'
  status.className = 'integ-status wait'
  try {
    const r = await fetch(API + '/google/auth')
    const data = await r.json()
    if (data.auth_url) {
      window.location.href = data.auth_url
    } else {
      status.textContent = data.error || 'Erro ao obter URL de autorização.'
      status.className = 'integ-status err'
    }
  } catch (e) {
    status.textContent = 'Erro de conexão.'
    status.className = 'integ-status err'
  }
}

async function disconnectGoogle() {
  if (!confirm('Desconectar Google Calendar? Os agendamentos não serão mais sincronizados.')) return
  const status = document.getElementById('google-status')
  try {
    await fetch(API + '/google/disconnect', { method: 'POST' })
    if (status) { status.textContent = 'Desconectado.'; status.className = 'integ-status' }
    loadGoogleConfig()
  } catch (e) {
    if (status) { status.textContent = 'Erro ao desconectar.'; status.className = 'integ-status err' }
  }
}

async function checkGoogleStatus() {
  const status = document.getElementById('google-status')
  if (!status) return
  status.textContent = 'Verificando...'
  status.className = 'integ-status wait'
  try {
    const r = await fetch(API + '/google/status')
    const data = await r.json()
    if (data.connected) {
      status.textContent = '✓ Conectado ao Google Calendar'
      status.className = 'integ-status ok'
    } else {
      status.textContent = '✗ Não conectado.'
      status.className = 'integ-status err'
    }
    const connectBtn = document.getElementById('google-connect-btn')
    const disconnectBtn = document.getElementById('google-disconnect-btn')
    const connectRow = document.getElementById('google-connect-row')
    if (connectBtn && disconnectBtn && connectRow) {
      if (data.connected) {
        connectBtn.style.display = 'none'
        disconnectBtn.style.display = ''
      } else {
        connectBtn.style.display = ''
        disconnectBtn.style.display = 'none'
      }
    }
  } catch (e) {
    status.textContent = 'Erro de conexão.'
    status.className = 'integ-status err'
  }
}

async function syncDetailToGoogle() {
  const id = document.getElementById('detail-id').value
  const btn = document.getElementById('detail-google-btn')
  const gs = document.getElementById('detail-google-status')
  if (!id || !gs) return
  gs.textContent = 'Sincronizando...'
  if (btn) btn.disabled = true
  try {
    const r = await fetch(API + '/appointments/' + id)
    const a = await r.json()
    const body = {
      action: a.google_event_id ? 'update' : 'create',
      appointment_id: a.id,
      client_name: a.client_name,
      client_phone: a.client_phone,
      service: a.service,
      price: a.price,
      status: a.status,
      appointment_date: a.appointment_date,
      appointment_time: a.appointment_time,
      duration: a.duration || 60,
      google_event_id: a.google_event_id || '',
    }
    const sr = await fetch(API + '/google/sync', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    })
    const sd = await sr.json()
    if (sd.status === 'ok') {
      gs.textContent = '✓ Sincronizado!'
      gs.className = 'integ-status ok'
      if (sd.html_link) {
        gs.innerHTML = '✓ <a href="' + sd.html_link + '" target="_blank" style="color:var(--primary-600)">Ver no Google Calendar</a>'
      }
      openAppointmentDetail(id)
    } else {
      gs.textContent = '✗ ' + (sd.error || 'Falha ao sincronizar.')
      gs.className = 'integ-status err'
    }
  } catch (e) {
    gs.textContent = '✗ Erro de conexão.'
    gs.className = 'integ-status err'
  }
  if (btn) btn.disabled = false
}

// ── CLIENTES ──────────────────────────────────────

let clientsCache = []
let selectedClientId = null

async function loadClients() {
  try {
    const res = await fetch(API + '/clients/')
    const clients = await res.json()
    clientsCache = clients
    renderClientList(clients)
    pageConfig.clientes.sub = clients.length + ' clientes cadastrados'
    document.getElementById('page-sub').textContent = pageConfig.clientes.sub
  } catch (e) {
    console.error('Erro ao carregar clientes:', e)
  }
}

function renderClientList(clients) {
  const list = document.getElementById('client-list')
  if (!list) return

  if (clients.length === 0) {
    list.innerHTML = ''
    clearClientDetail()
    return
  }

  list.innerHTML = clients.map((c, i) => {
    const lastDate = c.last_visit ? c.last_visit.split('T')[0].split('-').reverse().join('/') : '—'
    const statusMap = { frequente: 'Frequente', regular: 'Regular', novo: 'Novo', inativo: 'Inativo' }
    const statusClassMap = { frequente: 'status-done', regular: 'status-confirmed', novo: 'status-pending', inativo: 'status-pending' }
    const label = statusMap[c.status] || c.status
    const cls = statusClassMap[c.status] || 'status-pending'
    const spent = 'R$ ' + Number(c.total_spent).toLocaleString('pt-BR', {minimumFractionDigits: 0})
    return `
      <div class="client-row${i === 0 ? ' selected' : ''}" onclick="selectClient(this, ${c.id})">
        <div class="client-info-cell">
          <div class="client-av" style="background:${c.avatar_bg};color:${c.avatar_color};">${c.avatar_initials}</div>
          <div>
            <div class="client-name-cell">${c.name}</div>
            <div class="client-phone">${c.phone}</div>
          </div>
        </div>
        <div class="td">${lastDate}</div>
        <div class="td">${c.visits}</div>
        <div class="td money">${spent}</div>
        <span class="appt-status ${cls}">${label}</span>
      </div>`
  }).join('')

  if (clients.length > 0) {
    const firstRow = document.querySelector('.client-row')
    if (firstRow) selectClient(firstRow, clients[0].id)
  }
}

async function selectClient(row, clientId) {
  selectedClientId = clientId
  const detail = document.getElementById('client-detail')
  if (detail) detail.style.display = ''
  document.querySelectorAll('.client-row').forEach(r => r.classList.remove('selected'))
  if (row) row.classList.add('selected')

  try {
    const res = await fetch(API + '/clients/' + clientId)
    const c = await res.json()

    document.getElementById('cd-av').textContent = c.avatar_initials
    document.getElementById('cd-av').style.background = c.avatar_bg
    document.getElementById('cd-av').style.color = c.avatar_color
    document.getElementById('cd-name').textContent = c.name
    const since = c.created_at ? c.created_at.split('T')[0] : ''
    document.getElementById('cd-phone').textContent = c.phone + (since ? ' · Cliente desde ' + since : '')
    document.getElementById('cd-visits').textContent = c.visits
    document.getElementById('cd-total').textContent = 'R$ ' + Number(c.total_spent).toLocaleString('pt-BR', {minimumFractionDigits:0})
    const avg = c.visits > 0 ? c.total_spent / c.visits : 0
    document.getElementById('cd-ticket').textContent = 'R$ ' + avg.toFixed(0)
    document.getElementById('cd-last').textContent = c.last_visit || '—'

    const hist = document.getElementById('cd-history')
    if (c.appointments && c.appointments.length > 0) {
      hist.innerHTML = c.appointments.map(a => {
        const dateParts = a.appointment_date.split('-')
        const dateStr = dateParts.reverse().join('/')
        return `
          <div class="history-item">
            <div class="history-date">${dateStr}</div>
            <div class="history-svc">${a.service}</div>
            <div class="history-price">R$ ${a.price.toFixed(0)}</div>
          </div>`
      }).join('')
    } else {
      hist.innerHTML = '<div class="history-item" style="color:var(--text-secondary);">Nenhum atendimento registrado</div>'
    }
  } catch (e) {
    console.error('Erro ao carregar detalhes do cliente:', e)
  }
}

function clearClientDetail() {
  const el = id => document.getElementById(id)
  const detail = el('client-detail')
  if (detail) detail.style.display = 'none'
  if (el('cd-av')) { el('cd-av').textContent = '—'; el('cd-av').style.background = '#e8e8e8'; el('cd-av').style.color = '#999' }
  if (el('cd-name')) el('cd-name').textContent = 'Nenhum cliente selecionado'
  if (el('cd-phone')) el('cd-phone').textContent = ''
  if (el('cd-visits')) el('cd-visits').textContent = '0'
  if (el('cd-total')) el('cd-total').textContent = 'R$ 0'
  if (el('cd-ticket')) el('cd-ticket').textContent = 'R$ 0'
  if (el('cd-last')) el('cd-last').textContent = '—'
  if (el('cd-history')) el('cd-history').innerHTML = ''
  selectedClientId = null
}

// ── DASHBOARD ─────────────────────────────────────

async function loadDashboard() {
  try {
    const res = await fetch(API + '/stats')
    const stats = await res.json()

    const dot = document.getElementById('notif-dot')
    if (dot && stats.notifications_unread !== undefined) {
      dot.classList.toggle('hidden', !stats.notifications_unread)
    }

    const today = new Date()
    const days = ['Domingo','Segunda-feira','Terça-feira','Quarta-feira','Quinta-feira','Sexta-feira','Sábado']
    const months = ['janeiro','fevereiro','março','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro']
    pageConfig.dashboard.sub = days[today.getDay()] + ', ' + today.getDate() + ' de ' + months[today.getMonth()] + ' de ' + today.getFullYear()
    document.getElementById('page-sub').textContent = pageConfig.dashboard.sub

    const metrics = document.querySelectorAll('.metric-card')
    if (metrics.length >= 4) {
      metrics[0].querySelector('.metric-value').textContent = 'R$ ' + stats.today_revenue.toFixed(0)
      metrics[1].querySelector('.metric-value').textContent = stats.today_count
      metrics[2].querySelector('.metric-value').textContent = stats.active_clients
      metrics[3].querySelector('.metric-value').textContent = 'R$ ' + stats.avg_ticket.toFixed(0)
      metrics[3].querySelector('.metric-label').textContent = 'Ticket Médio'
    }

    // ── Fluxo de Caixa ──
    const financePanel = document.querySelector('.finance-panel')
    if (financePanel) {
      const monthSub = financePanel.querySelector('.panel-subtitle')
      if (monthSub) monthSub.textContent = stats.month_label + ' 2026'

      const profit = stats.month_revenue - stats.month_expenses
      const financeNum = financePanel.querySelector('.finance-number')
      if (financeNum) financeNum.textContent = 'R$ ' + profit.toLocaleString('pt-BR', {minimumFractionDigits: 0})

      const financeSub = financePanel.querySelector('.finance-sub')
      if (financeSub) {
        if (stats.meta_mensal > 0) {
          const above = profit >= stats.meta_mensal
          const diff = Math.abs(profit - stats.meta_mensal)
          financeSub.innerHTML = (above ? '↑' : '↓') + ' ' + diff.toLocaleString('pt-BR', {minimumFractionDigits: 0}) + ' ' + (above ? 'acima da meta' : 'abaixo da meta')
        } else {
          financeSub.textContent = ''
        }
      }

      const bars = financePanel.querySelectorAll('.bar-fill')
      if (stats.weekly_revenue && stats.weekly_revenue.length > 0) {
        const maxVal = Math.max(...stats.weekly_revenue, 1)
        stats.weekly_revenue.forEach((val, i) => {
          if (bars[i]) {
            const pct = Math.round((val / maxVal) * 60)
            bars[i].style.height = Math.max(8, pct) + 'px'
          }
        })
      }

      const srvRows = financePanel.querySelectorAll('.service-row')
      if (stats.service_breakdown && stats.service_breakdown.length > 0) {
        const colors = ['#4a90d9', '#2563a8', '#3a7abf', '#b8d4f0', '#1a5fab']
        stats.service_breakdown.forEach((svc, i) => {
          if (srvRows[i]) {
            srvRows[i].querySelector('.service-dot').style.background = colors[i % colors.length]
            srvRows[i].querySelector('.service-name').textContent = svc.name
            srvRows[i].querySelector('.service-bar-fill').style.width = svc.pct + '%'
            srvRows[i].querySelector('.service-bar-fill').style.background = colors[i % colors.length]
            srvRows[i].querySelector('.service-pct').textContent = svc.pct + '%'
          }
        })
        for (let i = stats.service_breakdown.length; i < srvRows.length; i++) {
          srvRows[i].style.display = 'none'
        }
      }
    }

    // ── Alertas Inteligentes ──
    const metaText = document.getElementById('meta-alert-text')
    if (metaText) {
      const falta = Math.max(0, stats.meta_mensal - stats.month_revenue)
      const metaVal = 'R$ ' + Number(stats.meta_mensal).toLocaleString('pt-BR', {minimumFractionDigits: 0})
      const receita = 'R$ ' + stats.month_revenue.toLocaleString('pt-BR', {minimumFractionDigits: 0})
      if (stats.month_revenue >= stats.meta_mensal) {
        metaText.innerHTML = '<b style="font-weight:500;">Meta de ' + metaVal + ' atingida!</b> 🎉 Receita atual: ' + receita
      } else {
        metaText.innerHTML = '<b style="font-weight:500;">' + stats.meta_pct + '% da meta</b> — Faltam R$ ' + falta.toLocaleString('pt-BR', {minimumFractionDigits: 0}) + ' de ' + metaVal
      }
    }

    const apptList = document.querySelector('.appt-list')
    if (apptList && stats.today_appointments) {
      const statusMap = { done: 'Concluído', confirmed: 'Confirmado', pending: 'Pendente', cancelled: 'Cancelado' }
      const statusClassMap = { done: 'status-done', confirmed: 'status-confirmed', pending: 'status-pending', cancelled: 'status-pending' }
      const colorMap = { done: '#4e8f6a', confirmed: '#4a90d9', pending: '#c9894a', cancelled: '#c05050' }

      if (stats.today_appointments.length > 0) {
        apptList.innerHTML = stats.today_appointments.map(a => `
          <div class="appt-item" onclick="openAppointmentDetail(${a.id})" style="cursor:pointer;">
            <div class="appt-time">${a.appointment_time}</div>
            <div class="appt-dot" style="background:${colorMap[a.status] || '#4a90d9'}"></div>
            <div class="appt-info">
              <div class="appt-name">${a.client_name}</div>
              <div class="appt-service">${a.service}</div>
            </div>
            <div class="appt-price">R$ ${Number(a.price).toFixed(0)}</div>
            <span class="appt-status ${statusClassMap[a.status] || 'status-pending'}">${statusMap[a.status] || a.status}</span>
          </div>
        `).join('')
      } else {
        apptList.innerHTML = '<div style="padding:20px;text-align:center;color:var(--text-secondary);">Nenhum agendamento para hoje</div>'
      }
    }
  } catch (e) {
    console.error('Erro ao carregar dashboard:', e)
  }
}

// ── FINANCEIRO ─────────────────────────────────────

async function loadFinanceiro() {
  try {
    const res = await fetch(API + '/stats')
    const s = await res.json()
    const finPage = document.getElementById('page-financeiro')
    if (!finPage) return

    const monthYearLabel = s.month_label + ' ' + s.month_year
    pageConfig.financeiro.sub = monthYearLabel
    document.getElementById('page-sub').textContent = monthYearLabel

    // Metric cards
    const fm = finPage.querySelectorAll('.metrics .metric-card')
    if (fm.length >= 4) {
      const profit = s.month_revenue - s.month_expenses
      fm[0].querySelector('.metric-value').textContent = 'R$ ' + s.month_revenue.toLocaleString('pt-BR', {minimumFractionDigits: 0})
      fm[1].querySelector('.metric-value').textContent = 'R$ ' + s.month_expenses.toLocaleString('pt-BR', {minimumFractionDigits: 0})
      fm[2].querySelector('.metric-value').textContent = 'R$ ' + profit.toLocaleString('pt-BR', {minimumFractionDigits: 0})
      fm[3].querySelector('.metric-value').textContent = 'R$ ' + s.meta_mensal.toLocaleString('pt-BR', {minimumFractionDigits: 0})

      const margin = s.month_revenue > 0 ? Math.round((profit / s.month_revenue) * 100) : 0
      fm[2].querySelector('.metric-change').innerHTML = '<svg width="11" height="11" viewBox="0 0 12 12" fill="none"><path d="M6 2v8M2 5l4-3 4 3" stroke="#4e8f6a" stroke-width="1.3" stroke-linecap="round"/></svg>Margem ' + margin + '%'
      fm[3].querySelector('.metric-change').textContent = s.meta_pct + '% atingido'
    }

    // Panel title
    const chartTitle = finPage.querySelector('.big-chart .panel-title')
    if (chartTitle) chartTitle.textContent = 'Receita vs Despesas — ' + monthYearLabel

    // Daily bar chart
    const bars = finPage.querySelectorAll('.month-bar-group')
    if (s.daily_breakdown && s.daily_breakdown.length > 0) {
      const maxVal = Math.max(...s.daily_breakdown.map(d => Math.max(d.revenue, d.expense, 1)))
      s.daily_breakdown.forEach((d, i) => {
        if (bars[i]) {
          const revH = Math.round((d.revenue / maxVal) * 120)
          const expH = Math.round((d.expense / maxVal) * 120)
          bars[i].querySelector('.month-bar.rev').style.height = Math.max(1, revH) + 'px'
          bars[i].querySelector('.month-bar.exp').style.height = Math.max(1, expH) + 'px'
        }
      })
      for (let i = s.daily_breakdown.length; i < bars.length; i++) {
        bars[i].style.display = 'none'
      }
    }

    // Recent transactions
    const txTable = finPage.querySelector('.transactions-table')
    if (txTable && s.recent_transactions) {
      if (s.recent_transactions.length > 0) {
        txTable.innerHTML = s.recent_transactions.map(t => {
          const isIncome = t.type === 'income'
          const desc = t.description || (t.client_name ? t.client_name : '')
          const dateStr = t.date ? t.date.split('-').reverse().join('/') : ''
          const method = t.payment_method || ''
          return `
            <div class="tx-row">
              <div class="tx-icon ${isIncome ? 'in' : 'out'}">
                <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
                  <path d="M8 ${isIncome ? '12V4M4 8l4-4 4 4' : '4v8M4 8l4 4 4-4'}" stroke="${isIncome ? '#4e8f6a' : '#c05050'}" stroke-width="1.3" stroke-linecap="round"/>
                </svg>
              </div>
              <div class="tx-desc">
                <div class="tx-name">${desc}</div>
                <div class="tx-date">${dateStr}${method ? ' · ' + method : ''}</div>
              </div>
              <div class="tx-amount ${isIncome ? 'in' : 'out'}">${isIncome ? '+' : '−'}R$ ${Number(t.amount).toFixed(2)}</div>
            </div>`
        }).join('')
      } else {
        txTable.innerHTML = '<div style="padding:20px;text-align:center;color:var(--text-secondary);">Nenhum lançamento no mês</div>'
      }
    }

    // Revenue by service (donut + legend)
    const donutLegend = finPage.querySelector('.donut-legend')
    const donutSvg = finPage.querySelector('.donut-wrap svg')
    const donutColors = ['#4a90d9', '#2563a8', '#3a7abf', '#b8d4f0', '#1a5fab']
    if (donutSvg) {
      let svgContent = ''
      const bgCircle = '<circle cx="45" cy="45" r="32" fill="none" stroke="#e8f2fc" stroke-width="14"/>'
      if (s.service_revenue_breakdown && s.service_revenue_breakdown.length > 0) {
        const circumference = 2 * Math.PI * 32
        let offset = 0
        const slices = s.service_revenue_breakdown.slice(0, 4)
        slices.forEach((svc, i) => {
          const pct = svc.pct
          const dashLen = (pct / 100) * circumference
          const gapLen = circumference - dashLen
          svgContent += `<circle cx="45" cy="45" r="32" fill="none" stroke="${donutColors[i]}" stroke-width="14"
            stroke-dasharray="${dashLen.toFixed(1)} ${gapLen.toFixed(1)}" stroke-dashoffset="${-offset.toFixed(1)}" transform="rotate(-90 45 45)"/>`
          offset += dashLen
        })
        const topPct = s.service_revenue_breakdown[0]?.pct || 0
        donutSvg.innerHTML = bgCircle + svgContent +
          `<text x="45" y="49" text-anchor="middle" font-family="DM Serif Display,serif" font-size="14" fill="#0f2340" font-weight="600">${topPct}%</text>`
      } else {
        donutSvg.innerHTML = bgCircle +
          '<text x="45" y="49" text-anchor="middle" font-family="DM Serif Display,serif" font-size="14" fill="#0f2340" font-weight="600">0%</text>'
      }
    }

    if (donutLegend) {
      if (s.service_revenue_breakdown && s.service_revenue_breakdown.length > 0) {
        donutLegend.innerHTML = s.service_revenue_breakdown.map((svc, i) => `
          <div class="donut-legend-item">
            <div class="donut-legend-dot" style="background:${donutColors[i % donutColors.length]};"></div>
            <span class="dl-name">${svc.name}</span> <span style="margin-left:auto;color:#0f2340;font-weight:600;">${svc.pct}%</span>
          </div>`).join('')
      } else {
        donutLegend.innerHTML = '<div style="color:var(--text-secondary);font-size:12px;">Nenhum serviço no período</div>'
      }
    }

    // Expenses by category
    const expBreakdown = finPage.querySelector('.expense-breakdown')
    if (expBreakdown && s.expenses_by_category) {
      const expColors = ['#c05050', '#c9894a', '#8aaccb', '#b8d4f0']
      const maxExp = Math.max(...s.expenses_by_category.map(e => e.amount), 1)
      if (s.expenses_by_category.length > 0) {
        expBreakdown.innerHTML = s.expenses_by_category.map((e, i) => `
          <div class="exp-row">
            <div class="service-dot" style="background:${expColors[i % expColors.length]};"></div>
            <div class="exp-name">${e.category}</div>
            <div class="exp-bar-bg"><div class="exp-bar-fill" style="width:${Math.round((e.amount / maxExp) * 100)}%;background:${expColors[i % expColors.length]};"></div></div>
            <div class="exp-val">R$ ${e.amount.toLocaleString('pt-BR', {minimumFractionDigits: 0})}</div>
          </div>`).join('')
      } else {
        expBreakdown.innerHTML = '<div style="padding:10px 0;color:var(--text-secondary);font-size:13px;">Nenhuma despesa registrada</div>'
      }
    }

    // Meta progress
    const metaPanel = finPage.querySelector('.finance-right .panel:last-child')
    if (metaPanel) {
      const badge = metaPanel.querySelector('.panel-badge')
      if (badge) badge.textContent = s.meta_pct + '%'
      const labelEl = metaPanel.querySelector('.meta-progress-label')
      const targetEl = metaPanel.querySelector('.meta-progress-target')
      if (labelEl) labelEl.textContent = 'R$ ' + s.month_revenue.toLocaleString('pt-BR', {minimumFractionDigits: 0}) + ' arrecadado'
      if (targetEl) targetEl.textContent = 'Meta: R$ ' + s.meta_mensal.toLocaleString('pt-BR', {minimumFractionDigits: 0})
      const fill = metaPanel.querySelector('.meta-progress-fill')
      if (fill) fill.style.width = Math.min(s.meta_pct, 100) + '%'
      const note = metaPanel.querySelector('.meta-progress-note')
      if (note) {
        const falta = Math.max(0, s.meta_mensal - s.month_revenue)
        note.textContent = falta > 0
          ? 'Faltam R$ ' + falta.toLocaleString('pt-BR', {minimumFractionDigits: 0}) + ' para bater a meta!'
          : 'Meta atingida!'
      }
    }

    const txPanel = finPage.querySelector('.transactions-table')?.closest('.panel')
    const txBadge = txPanel?.querySelector('.panel-badge')
    if (txBadge) txBadge.textContent = monthYearLabel

  } catch (e) {
    console.error('Erro ao carregar financeiro:', e)
  }
}

async function loadDespesas() {
  try {
    const res = await fetch(API + '/stats?period=30')
    const s = await res.json()
    const expenses = (s.recent_transactions || []).filter(t => t.type === 'expense')

    const total = expenses.reduce((sum, t) => sum + Number(t.amount), 0)
    const count = expenses.length
    const maior = count > 0 ? Math.max(...expenses.map(t => Number(t.amount))) : 0
    const media = count > 0 ? total / count : 0
    const maiorCat = count > 0 ? expenses.find(t => Number(t.amount) === maior) : null

    document.getElementById('desp-total').textContent = 'R$ ' + total.toFixed(2)
    document.getElementById('desp-count').textContent = count + ' despesa' + (count !== 1 ? 's' : '')
    document.getElementById('desp-maior').textContent = 'R$ ' + maior.toFixed(2)
    document.getElementById('desp-maior-cat').textContent = maiorCat?.category || '—'
    document.getElementById('desp-media').textContent = 'R$ ' + media.toFixed(2)
    document.getElementById('desp-media-label').innerHTML = 'média por lançamento'

    // Category breakdown
    const catMap = {}
    expenses.forEach(t => {
      const cat = t.category || 'Outros'
      catMap[cat] = (catMap[cat] || 0) + Number(t.amount)
    })
    const catTotal = Object.values(catMap).reduce((a, b) => a + b, 0)
    const catColors = ['#c05050','#e5825c','#f0b35e','#6fa8dc','#93c47d','#a06fb5','#5a5a5a']
    const catKeys = Object.keys(catMap)
    const catList = document.getElementById('desp-cat-list')
    if (catKeys.length > 0) {
      catList.innerHTML = catKeys.map((cat, i) => {
        const pct = ((catMap[cat] / catTotal) * 100).toFixed(1)
        return `
          <div class="donut-legend-item" style="padding:6px 0;">
            <span class="dl-dot" style="background:${catColors[i % catColors.length]}"></span>
            <span class="dl-name">${cat}</span>
            <span class="dl-val">R$ ${catMap[cat].toFixed(2)}</span>
            <span class="dl-pct" style="margin-left:auto;font-weight:600;">${pct}%</span>
          </div>`
      }).join('')
    } else {
      catList.innerHTML = '<div style="padding:10px 0;color:var(--text-secondary);font-size:13px;">Nenhuma despesa</div>'
    }

    // List all expenses
    const list = document.getElementById('desp-list')
    const badge = document.getElementById('desp-list-badge')
    if (badge) badge.textContent = count + ' registro' + (count !== 1 ? 's' : '')
    if (expenses.length > 0) {
      list.innerHTML = expenses.map(t => {
        const desc = t.description || ''
        const dateStr = t.date ? t.date.split('-').reverse().join('/') : ''
        return `
          <div class="tx-row">
            <div class="tx-icon out">
              <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
                <path d="M8 4v8M4 8l4 4 4-4" stroke="#c05050" stroke-width="1.3" stroke-linecap="round"/>
              </svg>
            </div>
            <div class="tx-desc">
              <div class="tx-name">${desc}</div>
              <div class="tx-date">${dateStr}${t.category ? ' · ' + t.category : ''}</div>
            </div>
            <div class="tx-amount out">−R$ ${Number(t.amount).toFixed(2)}</div>
          </div>`
      }).join('')
    } else {
      list.innerHTML = '<div style="padding:20px;text-align:center;color:var(--text-secondary);">Nenhuma despesa no mês</div>'
    }
  } catch (e) {
    console.error('Erro ao carregar despesas:', e)
  }
}

let _relPeriod = 30
async function loadRelatorios(period) {
  if (period) _relPeriod = period
  try {
    const res = await fetch(API + '/stats?period=' + _relPeriod)
    const s = await res.json()

    const sub = document.querySelector('.rpt-trend-sub')
    if (sub) sub.textContent = 'Últimos ' + _relPeriod + ' dias'

    const svg = document.getElementById('rpt-trend-svg')
    const daily = s.daily_breakdown || []
    const revs = daily.map(d => d.revenue)
    if (svg && revs.length > 0) {
      const w = 450, h = 130, padB = 40, padT = 20
      const maxVal = Math.max(...revs, 1)
      const count = revs.length
      const stepX = count > 1 ? w / (count - 1) : w / 2
      const pts = revs.map((v, i) => {
        const x = count > 1 ? i * stepX : w / 2
        const y = padT + (1 - v / maxVal) * (h - padT - padB)
        return { x, y }
      })
      let lineD = pts.map((p, i) => (i === 0 ? 'M' : 'L') + p.x.toFixed(1) + ' ' + p.y.toFixed(1)).join(' ')
      let areaD = lineD + ' L' + pts[pts.length - 1].x.toFixed(1) + ' ' + (h - padB) + ' L0 ' + (h - padB) + 'Z'
      const defs = '<defs><linearGradient id="g1" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="#4a90d9"/><stop offset="100%" stop-color="#4a90d9" stop-opacity="0"/></linearGradient></defs>'
      svg.innerHTML = `
        <line x1="0" y1="20" x2="450" y2="20" stroke="#f0f5fb" stroke-width="1"/>
        <line x1="0" y1="55" x2="450" y2="55" stroke="#f0f5fb" stroke-width="1"/>
        <line x1="0" y1="90" x2="450" y2="90" stroke="#f0f5fb" stroke-width="1"/>
        <path d="${areaD}" fill="url(#g1)" opacity="0.3"/>
        <path d="${lineD}" fill="none" stroke="#4a90d9" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
        <circle cx="${pts[pts.length - 1].x.toFixed(1)}" cy="${pts[pts.length - 1].y.toFixed(1)}" r="4" fill="#4a90d9"/>
        ${defs}`
    }

    const labels = document.getElementById('rpt-trend-labels')
    if (labels) {
      const now = new Date()
      const endStr = now.getDate() + ' ' + now.toLocaleString('pt-BR', { month: 'short' })
      const start = new Date(now)
      start.setDate(start.getDate() - _relPeriod)
      const startStr = start.getDate() + ' ' + start.toLocaleString('pt-BR', { month: 'short' })
      labels.innerHTML = `
        <span style="font-size:9px;color:#8aaccb;">${startStr}</span>
        <span style="font-size:9px;color:#8aaccb;">${endStr}</span>`
    }

    const total = revs.reduce((a, b) => a + b, 0)
    const avg = revs.length > 0 ? total / revs.length : 0
    const cs = document.querySelectorAll('.trend-chart-wrap .chart-stat-value')
    if (cs.length >= 2) {
      cs[0].textContent = 'R$ ' + total.toLocaleString('pt-BR', { minimumFractionDigits: 0 })
      cs[1].textContent = 'R$ ' + avg.toLocaleString('pt-BR', { minimumFractionDigits: 0 })
      if (cs[2]) {
        const prev = s.month_revenue_prev || 0
        const growth = prev > 0 ? ((s.month_revenue - prev) / prev * 100) : 0
        if (growth !== 0 || prev > 0) {
          cs[2].textContent = (growth >= 0 ? '+' : '') + growth.toFixed(0) + '%'
          cs[2].className = 'chart-stat-value' + (growth >= 0 ? ' green' : '')
        } else {
          cs[2].textContent = '—'
          cs[2].className = 'chart-stat-value'
        }
      }
    }

    const topDiv = document.getElementById('rpt-top-clients')
    if (topDiv) {
      const tops = s.top_clients || []
      if (tops.length > 0) {
        topDiv.innerHTML = tops.map((c, i) => {
          const rankColors = ['#f0f8e8', '#f4f8ff', '#f8e8f4', '#f8f8f8', '#f4f7fc']
          const rankTextColors = ['#4a8a2e', '#4a6888', '#8a2e6e', '#888', '#8aaccb']
          const rankLabels = ['1°', '2°', '3°', '4°', '5°']
          const lastDate = c.last_visit ? c.last_visit.split('T')[0].split('-').reverse().join('/') : '—'
          return `
            <div class="top-client-row">
              <div class="rank-badge" style="background:${rankColors[i]};color:${rankTextColors[i]};">${rankLabels[i]}</div>
              <div class="client-av" style="width:28px;height:28px;font-size:11px;">${c.avatar_initials || '?'}</div>
              <div style="flex:1;min-width:0;"><div style="font-size:13px;font-weight:500;color:#0f2340;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${c.name}</div><div style="font-size:11px;color:#8aaccb;">${c.visits} visitas · última: ${lastDate}</div></div>
              <div style="font-size:14px;font-weight:600;color:#1a5fab;flex-shrink:0;">R$ ${Number(c.total_spent).toLocaleString('pt-BR', {minimumFractionDigits: 0})}</div>
            </div>`
        }).join('')
      } else {
        topDiv.innerHTML = '<div style="padding:16px;color:var(--text-secondary);font-size:13px;text-align:center;">Nenhum cliente no período</div>'
      }
    }

    const svcDiv = document.getElementById('rpt-services')
    if (svcDiv) {
      const svcs = s.service_breakdown || []
      if (svcs.length > 0) {
        const maxCount = Math.max(...svcs.map(v => v.count), 1)
        const svcColors = ['#4a90d9', '#2563a8', '#3a7abf', '#b8d4f0', '#1a5fab']
        svcDiv.innerHTML = svcs.map((v, i) => {
          const pct = (v.count / maxCount) * 100
          return `<div><div style="display:flex;justify-content:space-between;margin-bottom:4px;"><span style="font-size:12px;font-weight:500;color:#0f2340;">${v.name}</span><span style="font-size:12px;color:${svcColors[i % svcColors.length]};font-weight:600;">${v.count}x</span></div><div class="meta-progress-bar" style="height:8px;"><div class="meta-progress-fill" style="width:${pct}%;border-radius:4px;height:8px;background:${svcColors[i % svcColors.length]};"></div></div></div>`
        }).join('')
      } else {
        svcDiv.innerHTML = '<div style="padding:10px 0;color:var(--text-secondary);font-size:13px;text-align:center;">Nenhum serviço no período</div>'
      }
    }

    renderHeatmap(s)

    updatePeriodBtns()
  } catch (e) {
    console.error('Erro ao carregar relatórios:', e)
  }
}

function renderHeatmap(s) {
  const heatDiv = document.getElementById('rpt-heatmap')
  if (!heatDiv) return
  const appts = s.month_appointments || s.today_appointments || []
  if (appts.length === 0) {
    heatDiv.innerHTML = '<div style="padding:16px;color:var(--text-secondary);font-size:13px;text-align:center;">Sem dados de agendamento</div>'
    return
  }
  try {
    const hours = ['08h','09h','10h','11h','12h','13h','14h','15h','16h','17h']
    const days = ['Seg','Ter','Qua','Qui','Sex','Sáb']
    const matrix = {}
    days.forEach(d => { matrix[d] = {}; hours.forEach(h => { matrix[d][h] = 0 }) })
    appts.forEach(a => {
      if (!a.appointment_date) return
      if (a.status === 'cancelled') return
      const d = new Date(a.appointment_date + 'T12:00')
      const dow = d.getDay()
      if (dow === 0) return
      const dayLabel = days[dow - 1]
      const h = parseInt(a.appointment_time?.split(':')[0] || '0')
      if (h >= 8 && h <= 17) {
        matrix[dayLabel][hours[h - 8]] = (matrix[dayLabel][hours[h - 8]] || 0) + 1
      }
    })
    const maxVal = Math.max(...Object.values(matrix).flatMap(d => Object.values(d)), 1)
    const getColor = (v) => {
      const pct = v / maxVal
      if (pct === 0) return '#f0f5fb'
      if (pct <= 0.25) return '#daeaf8'
      if (pct <= 0.5) return '#b8d4f0'
      if (pct <= 0.75) return '#7ab0e8'
      return '#4a90d9'
    }
    let html = '<div class="heatmap-hours"><div class="heatmap-day-label" style="width:24px;"></div>'
    hours.forEach(h => { html += '<div class="heatmap-hour-label">' + h + '</div>' })
    html += '</div>'
    days.forEach(d => {
      html += '<div class="heatmap-row"><div class="heatmap-day-label">' + d + '</div>'
      hours.forEach(h => {
        const v = matrix[d][h] || 0
        html += '<div class="hm-cell" style="background:' + getColor(v) + ';" title="' + d + ' ' + h + ': ' + v + ' agendamento(s)"></div>'
      })
      html += '</div>'
    })
    html += '<div class="heatmap-legend"><span>Menos</span><div class="heatmap-legend-bar">'
    ;[0, 0.25, 0.5, 0.75, 1].forEach(pct => {
      const fakeV = Math.round(pct * maxVal) || 1
      html += '<div class="heatmap-legend-step" style="background:' + getColor(fakeV) + ';"></div>'
    })
    html += '</div><span>Mais</span></div>'
    heatDiv.innerHTML = html
  } catch (e) {
    heatDiv.innerHTML = '<div style="padding:16px;color:var(--text-secondary);font-size:13px;text-align:center;">Erro ao gerar mapa de calor</div>'
  }
}

function updatePeriodBtns() {
  document.querySelectorAll('.period-btn').forEach(b => {
    b.classList.toggle('active', parseInt(b.getAttribute('onclick')?.match(/\d+/)?.[0] || '0') === _relPeriod)
  })
}

function exportRelatorioPDF() {
  const btn = document.querySelector('.period-selector .btn-outline')
  if (btn) { btn.textContent = '⏳ Gerando PDF...'; btn.disabled = true }
  const content = document.getElementById('page-relatorios')
  if (!content) return
  const title = 'Relatorio_BeautyFlow_' + new Date().toISOString().split('T')[0]
  const printWin = window.open('', '_blank')
  if (!printWin) {
    showToast('Permita pop-ups para exportar PDF.', 'info')
    if (btn) { btn.textContent = '⬇ Exportar PDF'; btn.disabled = false }
    return
  }
  const periodLabel = document.querySelector('.period-btn.active')?.textContent || '30 dias'
  printWin.document.write('<html><head><title>' + title + '</title>')
  printWin.document.write('<style>')
  printWin.document.write('body { font-family: Arial, sans-serif; padding: 20px; color: #333; }')
  printWin.document.write('h1 { color: #1a5fab; font-size: 22px; }')
  printWin.document.write('h2 { color: #2563a8; font-size: 16px; margin-top: 20px; }')
  printWin.document.write('table { width: 100%; border-collapse: collapse; margin: 10px 0; }')
  printWin.document.write('th, td { padding: 8px 12px; border: 1px solid #d8e4f0; text-align: left; font-size: 12px; }')
  printWin.document.write('th { background: #e8f2fc; color: #0f2340; }')
  printWin.document.write('.header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }')
  printWin.document.write('.stats { display: flex; gap: 20px; margin: 16px 0; flex-wrap: wrap; }')
  printWin.document.write('.stat-box { background: #f4f7fc; border: 1px solid #d8e4f0; border-radius: 8px; padding: 12px 20px; }')
  printWin.document.write('.stat-box .label { font-size: 11px; color: #8aaccb; text-transform: uppercase; }')
  printWin.document.write('.stat-box .value { font-size: 18px; color: #0f2340; font-weight: 600; }')
  printWin.document.write('.footer { margin-top: 30px; font-size: 10px; color: #8aaccb; text-align: center; border-top: 1px solid #d8e4f0; padding-top: 10px; }')
  printWin.document.write('</style></head><body>')
  printWin.document.write('<div class="header"><h1>Relatório BeautyFlow</h1><span style="color:#8aaccb;font-size:12px;">' + new Date().toLocaleDateString('pt-BR') + ' · Período: ' + periodLabel + '</span></div>')
  const totalEl = document.querySelector('.chart-stat:nth-child(1) .chart-stat-value')
  const avgEl = document.querySelector('.chart-stat:nth-child(2) .chart-stat-value')
  if (totalEl || avgEl) {
    printWin.document.write('<div class="stats">')
    if (totalEl) printWin.document.write('<div class="stat-box"><div class="label">Receita Total</div><div class="value">' + totalEl.textContent + '</div></div>')
    if (avgEl) printWin.document.write('<div class="stat-box"><div class="label">Média/dia</div><div class="value">' + avgEl.textContent + '</div></div>')
    printWin.document.write('</div>')
  }
  const topClients = document.querySelectorAll('#rpt-top-clients .top-client-row')
  if (topClients.length > 0) {
    printWin.document.write('<h2>Top Clientes</h2><table><tr><th>#</th><th>Cliente</th><th>Visitas</th><th>Total Gasto</th></tr>')
    topClients.forEach((row, i) => {
      const name = row.querySelector('.top-client-row div:nth-child(3) div:first-child')?.textContent || ''
      const visits = row.querySelector('.top-client-row div:nth-child(3) div:last-child')?.textContent?.split('·')[0] || ''
      const spent = row.querySelector('.top-client-row div:last-child')?.textContent || ''
      printWin.document.write('<tr><td>' + (i + 1) + '°</td><td>' + name.replace(' visitas', '').replace('última: ', '') + '</td><td>' + visits.replace(' visitas', '') + '</td><td>' + spent + '</td></tr>')
    })
    printWin.document.write('</table>')
  }
  const svcRows = document.querySelectorAll('#rpt-services > div')
  if (svcRows.length > 0) {
    printWin.document.write('<h2>Serviços Mais Populares</h2><table><tr><th>Serviço</th><th>Qtd</th></tr>')
    svcRows.forEach(row => {
      const name = row.querySelector('span:first-child')?.textContent || ''
      const count = row.querySelector('span:last-child')?.textContent || ''
      printWin.document.write('<tr><td>' + name + '</td><td>' + count + '</td></tr>')
    })
    printWin.document.write('</table>')
  }
  printWin.document.write('<div class="footer">Gerado por BeautyFlow CRM em ' + new Date().toLocaleString('pt-BR') + '</div>')
  printWin.document.write('</body></html>')
  printWin.document.close()
  printWin.focus()
  setTimeout(() => {
    printWin.print()
    if (btn) { btn.textContent = '⬇ Exportar PDF'; btn.disabled = false }
  }, 500)
}

// ── AGENDA ─────────────────────────────────────────

let servicesCache = []

async function loadServices() {
  try {
    const res = await fetch(API + '/services/')
    servicesCache = await res.json()
  } catch (e) {
    console.error('Erro ao carregar serviços:', e)
  }
}

async function loadServicos() {
  try {
    const res = await fetch(API + '/services/')
    const services = await res.json()
    servicesCache = services
    pageConfig.servicos.sub = services.length + ' serviços cadastrados'
    document.getElementById('page-sub').textContent = pageConfig.servicos.sub

    const list = document.getElementById('services-list')
    if (!list) return
    if (services.length === 0) {
      list.innerHTML = '<div style="padding:30px;text-align:center;color:var(--text-secondary);">Nenhum serviço cadastrado. Clique em "+ Novo Serviço" para começar.</div>'
      return
    }
    list.innerHTML = services.map(s => {
      const dur = s.duration >= 60
        ? (s.duration % 60 === 0 ? (s.duration / 60) + 'h' : Math.floor(s.duration / 60) + 'h ' + (s.duration % 60) + 'min')
        : s.duration + ' min'
      return `
        <div class="service-item">
          <div class="service-color-dot" style="background:${s.color};"></div>
          <div class="service-item-info">
            <div class="service-item-name">${s.name}</div>
            <div class="service-item-dur">⏱ ${dur}</div>
          </div>
          <div class="service-item-price">R$ ${Number(s.price).toFixed(0)}</div>
          <button class="service-item-edit" onclick="editService(${s.id})">Editar</button>
          <button class="service-item-delete" onclick="deleteService(${s.id})">Excluir</button>
        </div>`
    }).join('')
  } catch (e) {
    console.error('Erro ao carregar serviços:', e)
  }
}

async function loadMetas() {
  try {
    const res = await fetch(API + '/settings/')
    const settings = await res.json()
    const meta = settings.meta_mensal || 7000
    const input = document.getElementById('meta-input')
    if (input) input.value = meta
    pageConfig.metas.sub = 'Meta: R$ ' + Number(meta).toLocaleString('pt-BR', {minimumFractionDigits: 0})
    document.getElementById('page-sub').textContent = pageConfig.metas.sub
    updateMetaPreview(meta)
  } catch (e) {
    console.error('Erro ao carregar metas:', e)
  }
}

async function saveMeta() {
  const val = document.getElementById('meta-input').value
  if (!val || Number(val) < 1) { showToast('Informe um valor de meta válido.'); return }
  const meta = Number(val)
  try {
    const res = await fetch(API + '/settings/', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ meta_mensal: meta })
    })
    if (!res.ok) { showToast('Erro ao salvar meta.'); return }
    showToast('Meta salva com sucesso!', 'success')
    pageConfig.metas.sub = 'Meta: R$ ' + meta.toLocaleString('pt-BR', {minimumFractionDigits: 0})
    document.getElementById('page-sub').textContent = pageConfig.metas.sub
    updateMetaPreview(meta)
    loadDashboard()
  } catch (e) {
    showToast('Erro ao salvar meta.')
  }
}

async function updateMetaPreview(meta) {
  try {
    const res = await fetch(API + '/stats')
    const s = await res.json()
    const fill = document.getElementById('meta-preview-fill')
    const label = document.getElementById('meta-preview-label')
    const statsEl = document.getElementById('meta-stats')
    if (fill) fill.style.width = Math.min(s.month_revenue / meta * 100, 100) + '%'
    if (label) label.textContent = Math.round(s.month_revenue / meta * 100) + '%'
    if (statsEl) {
      const falta = Math.max(0, meta - s.month_revenue)
      statsEl.innerHTML = '<span>Receita atual: <b>R$ ' + s.month_revenue.toLocaleString('pt-BR', {minimumFractionDigits: 0}) + '</b></span>' +
        '<span>Faltam: <b>R$ ' + falta.toLocaleString('pt-BR', {minimumFractionDigits: 0}) + '</b></span>'
    }
  } catch (e) {}
}

async function loadAgenda() {
  agendaDate = new Date()
  agendaView = 'week'
  showAgendaView()
}

// ── MODAL AGENDAMENTO (criar/editar) ──────────────

async function openAppointmentModal(date, time) {
  const overlay = document.getElementById('modal-overlay')
  const title = document.getElementById('modal-title')
  const saveBtn = document.getElementById('modal-save-btn')
  const idField = document.getElementById('appt-id')

  idField.value = ''
  title.textContent = 'Novo Agendamento'
  saveBtn.textContent = 'Salvar Agendamento'

  document.getElementById('appt-date').value = date || new Date().toISOString().split('T')[0]
  document.getElementById('appt-time').value = time || '09:00'
  document.getElementById('appt-status').value = 'pending'
  document.getElementById('appt-price').value = ''
  document.getElementById('appt-notes').value = ''

  await populateClientSelect()
  await populateServiceSelect()

  overlay.classList.add('open')
}

async function populateClientSelect() {
  const sel = document.getElementById('appt-client')
  if (!clientsCache.length) {
    try {
      const res = await fetch(API + '/clients/')
      clientsCache = await res.json()
    } catch (e) { return }
  }
  sel.innerHTML = '<option value="">Selecione um cliente...</option>' +
    clientsCache.map(c => `<option value="${c.id}">${c.name}</option>`).join('')
}

async function populateServiceSelect() {
  const sel = document.getElementById('appt-service')
  if (!servicesCache.length) {
    try {
      const res = await fetch(API + '/services/')
      servicesCache = await res.json()
    } catch (e) { return }
  }
  sel.innerHTML = '<option value="">Selecione um serviço...</option>' +
    servicesCache.map(s => `<option value="${s.name}" data-price="${s.price}" data-dur="${s.duration}">${s.name} — R$ ${s.price}</option>`).join('')
}

function updateApptPriceFromService() {
  const sel = document.getElementById('appt-service')
  const opt = sel.options[sel.selectedIndex]
  if (opt && opt.dataset.price) {
    document.getElementById('appt-price').value = opt.dataset.price
  }
}

async function saveAppointment() {
  const idField = document.getElementById('appt-id')
  const clientId = document.getElementById('appt-client').value
  const service = document.getElementById('appt-service').value
  const date = document.getElementById('appt-date').value
  const time = document.getElementById('appt-time').value
  const status = document.getElementById('appt-status').value
  const price = document.getElementById('appt-price').value
  const notes = document.getElementById('appt-notes').value

  if (!clientId) { showToast('Selecione um cliente.'); return }
  if (!service) { showToast('Selecione um serviço.'); return }
  if (!date) { showToast('Selecione uma data.'); return }
  if (!time) { showToast('Selecione um horário.'); return }
  if (!price || Number(price) <= 0) { showToast('Informe um valor válido.'); return }

  const svcSel = document.getElementById('appt-service')
  const svcOpt = svcSel.options[svcSel.selectedIndex]
  const duration = svcOpt?.dataset?.dur ? Number(svcOpt.dataset.dur) : 60

  const body = { client_id: Number(clientId), service, appointment_date: date, appointment_time: time, status, price: Number(price), notes, duration }

  try {
    let res
    if (idField.value) {
      res = await fetch(API + '/appointments/' + idField.value, {
        method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
      })
    } else {
      res = await fetch(API + '/appointments/', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
      })
    }
    if (!res.ok) {
      const err = await res.json()
      showToast('Erro: ' + (err.details ? err.details.join(', ') : err.error))
      return
    }
    closeModal()
    showToast(idField.value ? 'Agendamento atualizado!' : 'Agendamento criado!', 'success')
    loadAgenda()
    loadDashboard()
  } catch (e) {
    showToast('Erro ao salvar agendamento.')
  }
}

function closeModal() {
  document.getElementById('modal-overlay').classList.remove('open')
}

// ── MODAL DETALHES (visualizar agendamento) ──────

async function openAppointmentDetail(apptId) {
  const overlay = document.getElementById('detail-overlay')
  const idField = document.getElementById('detail-id')
  idField.value = apptId

  try {
    const res = await fetch(API + '/appointments/' + apptId)
    const a = await res.json()

    document.getElementById('detail-client').textContent = a.client_name + ' (' + a.client_phone + ')'
    document.getElementById('detail-service').textContent = a.service
    document.getElementById('detail-date').textContent = a.appointment_date.split('-').reverse().join('/')
    document.getElementById('detail-time').textContent = a.appointment_time

    const statusLabels = { pending: 'Pendente', confirmed: 'Confirmado', done: 'Concluído', cancelled: 'Cancelado' }
    const statusColors = { pending: '#c9894a', confirmed: '#4a90d9', done: '#4e8f6a', cancelled: '#c05050' }
    const statusEl = document.getElementById('detail-status')
    statusEl.innerHTML = '<span style="display:inline-block;width:10px;height:10px;border-radius:50%;background:' +
      (statusColors[a.status] || '#999') + ';margin-right:6px;vertical-align:middle;"></span>' +
      (statusLabels[a.status] || a.status)

    document.getElementById('detail-price').textContent = 'R$ ' + Number(a.price).toFixed(2)
    document.getElementById('detail-notes').textContent = a.notes || '—'

    const cancelBtn = document.getElementById('detail-cancel-btn')
    const deleteBtn = document.getElementById('detail-delete-btn')
    const editBtn = document.getElementById('detail-edit-btn')

    cancelBtn.style.display = (a.status === 'cancelled' || a.status === 'done') ? 'none' : ''
    deleteBtn.style.display = ''

    const googleBtn = document.getElementById('detail-google-btn')
    const googleStatus = document.getElementById('detail-google-status')
    if (googleBtn && googleStatus) {
      if (a.google_event_id) {
        googleStatus.textContent = 'Verificando...'
        googleStatus.className = 'integ-status wait'
        try {
          const vr = await fetch(API + '/google/verify-event', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ event_id: a.google_event_id })
          })
          const vd = await vr.json()
          if (!vd.exists) {
            a.google_event_id = ''
            a.google_html_link = ''
            await fetch(API + '/appointments/' + a.id, {
              method: 'PUT',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ google_event_id: '', google_html_link: '' })
            })
          }
        } catch (e) {}
      }
      if (a.google_event_id) {
        googleBtn.textContent = a.google_html_link ? 'Ver no Google Calendar' : 'Atualizar no Google'
        googleBtn.onclick = a.google_html_link ? (() => window.open(a.google_html_link, '_blank')) : (() => syncDetailToGoogle())
        googleBtn.style.display = ''
        googleStatus.textContent = '✓ Sincronizado'
        googleStatus.className = 'integ-status ok'
      } else {
        googleBtn.textContent = 'Sincronizar com Google'
        googleBtn.onclick = syncDetailToGoogle
        googleBtn.style.display = ''
        googleStatus.textContent = 'Não sincronizado (evento removido do Google)'
        googleStatus.className = 'integ-status err'
      }
    }

    overlay.classList.add('open')
  } catch (e) {
    console.error('Erro ao carregar detalhes:', e)
  }
}

async function cancelAppointment() {
  const id = document.getElementById('detail-id').value
  if (!confirm('Tem certeza que deseja cancelar este agendamento?')) return
  try {
    const res = await fetch(API + '/appointments/' + id, {
      method: 'PUT', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'cancelled' })
    })
    if (!res.ok) { showToast('Erro ao cancelar.'); return }
    closeDetail()
    loadAgenda()
    loadDashboard()
  } catch (e) { showToast('Erro ao cancelar.') }
}

async function deleteAppointment() {
  const id = document.getElementById('detail-id').value
  if (!confirm('Tem certeza que deseja excluir este agendamento? Esta ação não pode ser desfeita.')) return
  try {
    const res = await fetch(API + '/appointments/' + id, { method: 'DELETE' })
    if (!res.ok) { showToast('Erro ao excluir.'); return }
    closeDetail()
    loadAgenda()
    loadDashboard()
  } catch (e) { showToast('Erro ao excluir.') }
}

async function editFromDetail() {
  const id = document.getElementById('detail-id').value
  closeDetail()
  try {
    const res = await fetch(API + '/appointments/' + id)
    const a = await res.json()

    const overlay = document.getElementById('modal-overlay')
    document.getElementById('modal-title').textContent = 'Editar Agendamento'
    document.getElementById('modal-save-btn').textContent = 'Salvar Alterações'
    document.getElementById('appt-id').value = a.id

    await populateClientSelect()
    document.getElementById('appt-client').value = a.client_id

    await populateServiceSelect()
    document.getElementById('appt-service').value = a.service
    document.getElementById('appt-date').value = a.appointment_date
    document.getElementById('appt-time').value = a.appointment_time
    document.getElementById('appt-status').value = a.status
    document.getElementById('appt-price').value = a.price
    document.getElementById('appt-notes').value = a.notes || ''

    overlay.classList.add('open')
  } catch (e) {
    console.error('Erro ao carregar para edição:', e)
  }
}

function closeDetail() {
  document.getElementById('detail-overlay').classList.remove('open')
}

// ── CLIENT MODAL ───────────────────────────────────

function openClientModal() {
  const overlay = document.getElementById('client-modal-overlay')
  overlay.dataset.editId = ''
  overlay.querySelector('.modal-title').textContent = 'Nova Cliente'
  overlay.querySelector('.btn-primary').textContent = 'Salvar Cliente'
  document.getElementById('client-name').value = ''
  document.getElementById('client-phone').value = ''
  document.getElementById('client-email').value = ''
  document.getElementById('client-status').value = 'regular'
  document.getElementById('client-notes').value = ''
  overlay.classList.add('open')
  document.getElementById('client-name').focus()
}

function closeClientModal() {
  document.getElementById('client-modal-overlay').classList.remove('open')
}

async function saveClient() {
  const name = document.getElementById('client-name').value.trim()
  const phone = document.getElementById('client-phone').value.trim()
  const email = document.getElementById('client-email').value.trim()
  const status = document.getElementById('client-status').value
  const notes = document.getElementById('client-notes').value.trim()

  if (!name || name.length < 2) { showToast('O nome deve ter pelo menos 2 caracteres.'); return }
  if (!phone || phone.length < 8) { showToast('Informe um telefone válido.'); return }

  const isEdit = document.getElementById('client-modal-overlay').dataset.editId
  try {
    let res
    if (isEdit) {
      res = await fetch(API + '/clients/' + isEdit, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, phone, email, status, notes })
      })
    } else {
      res = await fetch(API + '/clients/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, phone, email, status, notes })
      })
    }
    if (!res.ok) {
      const err = await res.json()
      showToast('Erro: ' + (err.details ? err.details.join(', ') : err.error))
      return
    }
    closeClientModal()
    loadClients()
    loadDashboard()
  } catch (e) {
    showToast('Erro ao salvar cliente.')
  }
}

// ── SERVICE MODAL ───────────────────────────────────

function openServiceModal(svcId) {
  const overlay = document.getElementById('service-modal-overlay')
  const title = document.getElementById('service-modal-title')
  const saveBtn = document.getElementById('service-save-btn')
  const idField = document.getElementById('service-id')

  idField.value = ''
  title.textContent = 'Novo Serviço'
  saveBtn.textContent = 'Salvar Serviço'
  document.getElementById('service-name').value = ''
  document.getElementById('service-duration').value = ''
  document.getElementById('service-price').value = ''
  document.getElementById('service-color').value = '#4a90d9'

  if (svcId) {
    const svc = servicesCache.find(s => s.id === svcId)
    if (svc) {
      idField.value = svc.id
      title.textContent = 'Editar Serviço'
      saveBtn.textContent = 'Salvar Alterações'
      document.getElementById('service-name').value = svc.name
      document.getElementById('service-duration').value = svc.duration
      document.getElementById('service-price').value = svc.price
      document.getElementById('service-color').value = svc.color
    }
  }

  overlay.classList.add('open')
}

function closeServiceModal() {
  document.getElementById('service-modal-overlay').classList.remove('open')
}

async function saveService() {
  const name = document.getElementById('service-name').value.trim()
  const duration = document.getElementById('service-duration').value
  const price = document.getElementById('service-price').value
  const color = document.getElementById('service-color').value
  const idField = document.getElementById('service-id')

  if (!name || name.length < 2) { showToast('Informe o nome do serviço.'); return }
  if (!duration || Number(duration) < 1) { showToast('Informe a duração do serviço.'); return }
  if (price === '' || Number(price) < 0) { showToast('Informe o preço do serviço.'); return }

  const body = { name, duration: Number(duration), price: Number(price), color }

  try {
    let res
    if (idField.value) {
      res = await fetch(API + '/services/' + idField.value, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      })
    } else {
      res = await fetch(API + '/services/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      })
    }
    if (!res.ok) {
      const err = await res.json()
      showToast('Erro: ' + (err.error || 'Erro ao salvar serviço'))
      return
    }
    closeServiceModal()
    servicesCache = []
    loadServicos()
  } catch (e) {
    showToast('Erro ao salvar serviço.')
  }
}

async function editService(svcId) {
  openServiceModal(svcId)
}

async function deleteService(svcId) {
  if (!confirm('Tem certeza que deseja remover este serviço? Esta ação não pode ser desfeita.')) return
  try {
    const res = await fetch(API + '/services/' + svcId, { method: 'DELETE' })
    if (!res.ok) { showToast('Erro ao remover serviço.'); return }
    servicesCache = []
    loadServicos()
  } catch (e) {
    showToast('Erro ao remover serviço.')
  }
}

function filterClients(filter) {
  if (!clientsCache.length) return
  const filtered = filter === 'all' ? clientsCache : clientsCache.filter(c => c.status === filter)
  renderClientList(filtered)
}

// ── TRANSACTION MODAL ────────────────────────────────

function openTransactionModal() {
  const overlay = document.getElementById('transaction-modal-overlay')
  const title = document.getElementById('tx-modal-title')
  const saveBtn = document.getElementById('tx-save-btn')
  const idField = document.getElementById('tx-id')
  idField.value = ''
  title.textContent = 'Novo Lançamento'
  saveBtn.textContent = 'Salvar Lançamento'
  document.getElementById('tx-type').value = 'income'
  document.getElementById('tx-amount').value = ''
  document.getElementById('tx-description').value = ''
  document.getElementById('tx-date').value = new Date().toISOString().split('T')[0]
  document.getElementById('tx-category').value = ''
  document.getElementById('tx-payment').value = ''
  document.getElementById('tx-msg').textContent = ''
  document.getElementById('tx-appt-field').style.display = 'none'
  overlay.classList.add('open')
}

function closeTransactionModal() {
  document.getElementById('transaction-modal-overlay').classList.remove('open')
}

async function saveTransaction() {
  const type = document.getElementById('tx-type').value
  const amount = document.getElementById('tx-amount').value
  const description = document.getElementById('tx-description').value.trim()
  const date = document.getElementById('tx-date').value
  const category = document.getElementById('tx-category').value
  const payment = document.getElementById('tx-payment').value
  const msg = document.getElementById('tx-msg')

  if (!amount || Number(amount) <= 0) { msg.textContent = 'Informe um valor válido.'; msg.className = 'auth-msg error'; return }
  if (!description || description.length < 2) { msg.textContent = 'Informe uma descrição.'; msg.className = 'auth-msg error'; return }
  if (!date) { msg.textContent = 'Selecione uma data.'; msg.className = 'auth-msg error'; return }

  const body = {
    type, amount: Number(amount), description, date,
    category: category || '',
    payment_method: payment || '',
  }

  try {
    const r = await fetch(API + '/transactions/', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    })
    if (!r.ok) {
      const err = await r.json()
      msg.textContent = err.error || 'Erro ao salvar.'
      msg.className = 'auth-msg error'
      return
    }
    closeTransactionModal()
    showToast('Lançamento salvo!', 'success')
    loadFinanceiro()
    loadDashboard()
  } catch (e) {
    msg.textContent = 'Erro de conexão.'
    msg.className = 'auth-msg error'
  }
}

// ── TOAST ──────────────────────────────────────────

function showToast(msg, type) {
  let container = document.getElementById('toast-container')
  if (!container) {
    container = document.createElement('div')
    container.id = 'toast-container'
    container.className = 'toast-container'
    document.body.appendChild(container)
  }
  const el = document.createElement('div')
  el.className = 'toast'
  if (type === 'success') el.classList.add('toast-success')
  else if (type === 'info') el.classList.add('toast-info')
  el.textContent = msg
  el.onclick = () => { el.style.animation = 'none'; el.remove() }
  container.appendChild(el)
  setTimeout(() => { if (el.parentNode) el.remove() }, 5000)
}

// ── CLIENT EDIT / DELETE ───────────────────────────

async function editClient() {
  if (!selectedClientId) { showToast('Selecione um cliente primeiro.'); return }
  try {
    const res = await fetch(API + '/clients/' + selectedClientId)
    const c = await res.json()

    document.getElementById('client-name').value = c.name
    document.getElementById('client-phone').value = c.phone
    document.getElementById('client-email').value = c.email || ''
    document.getElementById('client-status').value = c.status || 'regular'
    document.getElementById('client-notes').value = c.notes || ''

    const overlay = document.getElementById('client-modal-overlay')
    overlay.classList.add('open')
    overlay.dataset.editId = selectedClientId
    overlay.querySelector('.modal-title').textContent = 'Editar Cliente'
    overlay.querySelector('.btn-primary').textContent = 'Salvar Alterações'
  } catch (e) {
    showToast('Erro ao carregar dados da cliente.')
  }
}

async function deleteClient() {
  if (!selectedClientId) { showToast('Selecione um cliente primeiro.'); return }
  if (!confirm('Tem certeza que deseja remover esta cliente? Esta ação não pode ser desfeita.')) return
  try {
    const res = await fetch(API + '/clients/' + selectedClientId, { method: 'DELETE' })
    if (!res.ok) { showToast('Erro ao remover cliente.'); return }
    selectedClientId = null
    loadClients()
    loadDashboard()
  } catch (e) {
    showToast('Erro ao remover cliente.')
  }
}

// ── NOTIFICAÇÕES ────────────────────────────────────

document.querySelectorAll('.hour-toggle').forEach(t => {
  t.addEventListener('click', () => {
    t.classList.toggle('on')
    t.classList.toggle('off')
  })
})

async function saveNotificacoes() {
  const toggles = document.querySelectorAll('.hour-toggle')
  const data = {}
  toggles.forEach(t => {
    const titleEl = t.closest('.toggle-row')?.querySelector('.toggle-title')
    if (!titleEl) return
    const key = 'notify_' + titleEl.textContent.trim().toLowerCase().replace(/\s+/g, '_')
    data[key] = t.classList.contains('on') ? 'true' : 'false'
  })
  try {
    const res = await fetch(API + '/settings/', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    })
    if (!res.ok) { showToast('Erro ao salvar preferências.'); return }
    showToast('Preferências salvas!', 'success')
  } catch {
    showToast('Erro ao salvar preferências.')
  }
}

// ── NOTIFICATION PANEL ─────────────────────────────

let notifPanelOpen = false

async function loadNotifDot() {
  try {
    const res = await fetch(API + '/notifications/unread-count')
    const data = await res.json()
    const dot = document.getElementById('notif-dot')
    if (dot) {
      dot.classList.toggle('hidden', !data.count)
    }
  } catch {}
}

// ── INTEGRAÇÕES ─────────────────────────────────────

async function loadIntegrations() {
  const list = document.getElementById('integrations-list')
  if (!list) return
  try {
    const res = await fetch(API + '/integrations/')
    const data = await res.json()
    if (!data.length) {
      list.innerHTML = '<div class="integ-empty">Nenhuma integração criada. Clique em "Nova Integração" para começar.</div>'
      return
    }
    const typeLabels = { webhook: 'Webhook', n8n: 'n8n', google_calendar: 'Google Calendar' }
    const typeIcons = {
      webhook: '<svg width="16" height="16" viewBox="0 0 20 20" fill="none"><path d="M4 10a6 6 0 1 1 12 0" stroke="currentColor" stroke-width="1.5" fill="none"/><path d="M8 10l2-2 2 2-2 2z" fill="currentColor"/></svg>',
      n8n: '<svg width="16" height="16" viewBox="0 0 20 20" fill="none"><circle cx="5" cy="10" r="3" stroke="currentColor" stroke-width="1.5"/><circle cx="15" cy="5" r="3" stroke="currentColor" stroke-width="1.5"/><circle cx="15" cy="15" r="3" stroke="currentColor" stroke-width="1.5"/><path d="M8 10h3l1.5-3M8 10h3l1.5 3" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/></svg>',
      google_calendar: '<svg width="16" height="16" viewBox="0 0 20 20" fill="none"><rect x="2" y="3" width="16" height="15" rx="2" stroke="currentColor" stroke-width="1.3"/><path d="M2 7h16M7 2v3M13 2v3" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/><text x="10" y="16" text-anchor="middle" font-size="7" fill="currentColor" font-weight="700">GC</text></svg>',
    }
    list.innerHTML = data.map(integ => {
      const canTest = integ.type === 'webhook' || integ.type === 'n8n'
      return `
      <div class="integ-list-item">
        <div class="integ-list-icon ${integ.type}">${typeIcons[integ.type] || ''}</div>
        <div class="integ-list-body">
          <div class="integ-list-name">${integ.name}</div>
          <div class="integ-list-type">${typeLabels[integ.type] || integ.type}</div>
        </div>
        <div class="integ-list-enabled">
          <label class="toggle-switch">
            <input type="checkbox" ${integ.enabled ? 'checked' : ''} onchange="toggleInteg(${integ.id}, this.checked)">
            <span class="toggle-slider"></span>
          </label>
        </div>
        <div class="integ-list-actions">
          ${canTest ? `<button class="integ-list-btn" onclick="testInteg(${integ.id})" title="Testar">&#9654;</button>` : ''}
          <button class="integ-list-btn" onclick="editInteg(${integ.id})" title="Editar">&#9998;</button>
          <button class="integ-list-btn danger" onclick="deleteInteg(${integ.id})" title="Excluir">&#10005;</button>
        </div>
      </div>`
    }).join('')
  } catch {
    list.innerHTML = '<div class="integ-empty">Erro ao carregar integrações.</div>'
  }
}

async function toggleInteg(id, enabled) {
  try {
    await fetch(API + '/integrations/' + id, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ enabled })
    })
  } catch {}
}

async function deleteInteg(id) {
  if (!confirm('Excluir esta integração?')) return
  try {
    await fetch(API + '/integrations/' + id, { method: 'DELETE' })
    loadIntegrations()
    showToast('Integração removida.', 'info')
  } catch {
    showToast('Erro ao remover integração.')
  }
}

function showCreateIntegrationModal() {
  document.getElementById('integ-id').value = ''
  document.getElementById('integ-modal-title').textContent = 'Nova Integração'
  document.getElementById('integ-save-btn').textContent = 'Criar Integração'
  document.getElementById('integ-name').value = ''
  document.getElementById('integ-status').textContent = ''
  document.getElementById('integ-status').className = 'integ-status'
  document.getElementById('integ-config-fields').style.display = 'none'
  document.getElementById('integ-config-fields').innerHTML = ''
  window._integSavedConfig = {}
  document.querySelectorAll('.integ-type-option').forEach(el => {
    el.classList.remove('selected')
    el.style.opacity = ''
    el.style.cursor = ''
  })
  document.getElementById('integ-modal-overlay').classList.add('open')
}

function closeIntegModal() {
  const ov = document.getElementById('integ-modal-overlay')
  if (ov) ov.classList.remove('open')
}

let _selectedIntegType = ''

function selectIntegType(type, el) {
  _selectedIntegType = type
  document.querySelectorAll('.integ-type-option').forEach(e => e.classList.remove('selected'))
  el.classList.add('selected')
  renderIntegConfigFields(type)
}

function renderIntegConfigFields(type) {
  const container = document.getElementById('integ-config-fields')
  container.style.display = 'block'
  const editing = !!document.getElementById('integ-id').value
  const saved = window._integSavedConfig || {}

  const getVal = (key, def) => (saved[key] !== undefined ? saved[key] : def)

  if (type === 'webhook' || type === 'n8n') {
    const brand = type === 'n8n' ? 'n8n' : 'Webhook'
    container.innerHTML = `
      <hr class="integ-divider" style="margin:16px 0;">
      <div class="integ-section-title">Configuração do ${brand}</div>
      <div class="integ-field" style="margin-bottom:12px;">
        <label class="form-label">URL do Webhook</label>
        <div style="display:flex;gap:8px;">
          <input class="form-input" id="integ-cfg-url" placeholder="https://..." value="${getVal('url', '')}" style="flex:1;">
          <button class="btn-outline" onclick="testIntegUrl()" style="flex-shrink:0;">Testar</button>
        </div>
      </div>
      <div class="integ-field" style="margin-bottom:12px;">
        <label class="form-label">Eventos</label>
        <div class="checkbox-group">
          <label class="checkbox-card">
            <input type="checkbox" id="integ-cfg-ev-create" value="create" ${getVal('events', '').includes('create') ? 'checked' : ''}>
            <div class="checkbox-card-content">
              <div class="checkbox-card-title">Agendamento Criado</div>
              <div class="checkbox-card-desc">Dispara quando um novo agendamento é registrado</div>
            </div>
          </label>
          <label class="checkbox-card">
            <input type="checkbox" id="integ-cfg-ev-update" value="update" ${getVal('events', '').includes('update') ? 'checked' : ''}>
            <div class="checkbox-card-content">
              <div class="checkbox-card-title">Agendamento Atualizado</div>
              <div class="checkbox-card-desc">Dispara quando um agendamento existente é modificado</div>
            </div>
          </label>
          <label class="checkbox-card">
            <input type="checkbox" id="integ-cfg-ev-delete" value="delete" ${getVal('events', '').includes('delete') ? 'checked' : ''}>
            <div class="checkbox-card-content">
              <div class="checkbox-card-title">Agendamento Cancelado</div>
              <div class="checkbox-card-desc">Dispara quando um agendamento é cancelado ou removido</div>
            </div>
          </label>
        </div>
      </div>
      <div class="form-row">
        <div class="form-field" style="max-width:120px;">
          <label class="form-label">Timeout (s)</label>
          <input class="form-input" id="integ-cfg-timeout" type="number" value="${getVal('timeout', '8')}" min="1" max="60">
        </div>
      </div>
      <div class="integ-field">
        <label class="form-label">Cabeçalho personalizado (opcional)</label>
        <div class="integ-header-row" style="margin-top:6px;">
          <div class="integ-header-field">
            <input class="form-input" id="integ-cfg-header-name" placeholder="Authorization" value="${getVal('header_name', '')}">
          </div>
          <span class="integ-header-sep">:</span>
          <div class="integ-header-field">
            <input class="form-input" id="integ-cfg-header-value" type="password" placeholder="Bearer ..." value="${getVal('header_value', '')}">
          </div>
        </div>
      </div>`
  } else if (type === 'google_calendar') {
    container.innerHTML = `
      <hr class="integ-divider" style="margin:16px 0;">
      <div class="integ-section-title">Credenciais do Google</div>
      <div class="integ-helper" style="margin-bottom:12px;">Crie um projeto no <a href="https://console.cloud.google.com/apis/credentials" target="_blank">Google Cloud Console</a> e gere um Client ID e Client Secret.</div>
      <div class="form-row">
        <div class="form-field">
          <label class="form-label">Client ID</label>
          <input class="form-input" id="integ-cfg-google-client-id" placeholder="xxxx.apps.googleusercontent.com" value="${getVal('client_id', '')}">
        </div>
        <div class="form-field">
          <label class="form-label">Client Secret</label>
          <input class="form-input" id="integ-cfg-google-client-secret" type="password" placeholder="GOCSPX-..." value="${getVal('client_secret', '')}">
        </div>
      </div>
      <hr class="integ-divider" style="margin:16px 0;">
      <div class="integ-section-title">Autenticação</div>
      <div class="integ-helper" style="margin-bottom:12px;">Após salvar as credenciais, clique em "Conectar com Google" para autorizar o acesso à sua agenda.</div>
      <div id="integ-google-status" class="integ-status" style="margin-bottom:12px;">${getVal('_google_connected', false) ? '✓ Conectado ao Google Calendar' : 'Aguardando conexão...'}</div>
      <div style="display:flex;gap:8px;">
        <button class="btn-primary" onclick="integConnectGoogle()" id="integ-google-connect-btn">Conectar com Google</button>
        <button class="btn-outline" onclick="integDisconnectGoogle()" id="integ-google-disconnect-btn" style="${getVal('_google_connected', false) ? '' : 'display:none;'}">Desconectar</button>
      </div>`
    // check real google status
    fetch(API + '/google/status').then(r => r.json()).then(gs => {
      const st = document.getElementById('integ-google-status')
      const dc = document.getElementById('integ-google-disconnect-btn')
      if (gs.connected) {
        if (st) { st.textContent = '✓ Conectado ao Google Calendar'; st.className = 'integ-status ok' }
        if (dc) dc.style.display = ''
      } else {
        const hasCreds = getVal('client_id', '') && getVal('client_secret', '')
        if (st) {
          st.textContent = hasCreds ? 'Clique em "Conectar com Google" para autorizar.' : 'Preencha Client ID e Client Secret e salve, depois conecte.'
          st.className = 'integ-status'
        }
      }
    }).catch(() => {})
  }
}

async function saveInteg() {
  const id = document.getElementById('integ-id').value
  const name = document.getElementById('integ-name').value.trim()
  const status = document.getElementById('integ-status')
  if (!name) { showToast('Informe um nome para a integração.'); return }
  if (!_selectedIntegType) { showToast('Selecione um tipo de integração.'); return }

  let config = {}
  if (_selectedIntegType === 'webhook' || _selectedIntegType === 'n8n') {
    const events = ['integ-cfg-ev-create','integ-cfg-ev-update','integ-cfg-ev-delete']
      .filter(el => document.getElementById(el)?.checked)
      .map(el => document.getElementById(el).value)
    config = {
      url: (document.getElementById('integ-cfg-url')?.value || '').trim(),
      events: events.join(','),
      timeout: document.getElementById('integ-cfg-timeout')?.value || '8',
      header_name: (document.getElementById('integ-cfg-header-name')?.value || '').trim(),
      header_value: (document.getElementById('integ-cfg-header-value')?.value || '').trim(),
    }
  } else if (_selectedIntegType === 'google_calendar') {
    config = {
      client_id: (document.getElementById('integ-cfg-google-client-id')?.value || '').trim(),
      client_secret: (document.getElementById('integ-cfg-google-client-secret')?.value || '').trim(),
    }
  }

  status.textContent = 'Salvando...'
  status.className = 'integ-status wait'

  try {
    if (id) {
      const res = await fetch(API + '/integrations/' + id, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, config })
      })
      if (!res.ok) { showToast('Erro ao atualizar.'); return }
      showToast('Integração atualizada!', 'success')
    } else {
      const res = await fetch(API + '/integrations/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, type: _selectedIntegType, config })
      })
      if (!res.ok) { showToast('Erro ao criar.'); return }
      showToast('Integração criada!', 'success')
    }
    closeIntegModal()
    loadIntegrations()
  } catch {
    showToast('Erro de conexão.')
  }
}

async function editInteg(id) {
  try {
    const res = await fetch(API + '/integrations/' + id)
    const integ = await res.json()
    if (!integ) { showToast('Integração não encontrada.'); return }

    document.getElementById('integ-id').value = integ.id
    document.getElementById('integ-modal-title').textContent = 'Editar Integração'
    document.getElementById('integ-save-btn').textContent = 'Salvar'
    document.getElementById('integ-name').value = integ.name
    document.getElementById('integ-status').textContent = ''
    document.getElementById('integ-status').className = 'integ-status'

    _selectedIntegType = integ.type

    document.querySelectorAll('.integ-type-option').forEach(el => {
      el.classList.toggle('selected', el.dataset.type === integ.type)
      el.style.opacity = '0.6'
      el.style.cursor = 'default'
    })

    const cfg = integ.config || {}
    window._integSavedConfig = cfg
    renderIntegConfigFields(integ.type)

    document.getElementById('integ-modal-overlay').classList.add('open')
  } catch {
    showToast('Erro ao carregar integração.')
  }
}

async function testInteg(id) {
  try {
    const res = await fetch(API + '/integrations/' + id)
    const integ = await res.json()
    if (!integ) { showToast('Integração não encontrada.'); return }
    const url = (integ.config && integ.config.url) || ''
    if (!url) { showToast('Configure a URL primeiro.'); return }
    const tr = await fetch(API + '/n8n/test', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ webhook_url: url })
    })
    const data = await tr.json()
    if (tr.ok) {
      showToast('✓ ' + (data.message || 'Webhook funcionando!'), 'success')
    } else {
      showToast('✗ ' + (data.error || 'Falha no teste.'))
    }
  } catch {
    showToast('Erro ao testar integração.')
  }
}

async function testIntegUrl() {
  const url = (document.getElementById('integ-cfg-url')?.value || '').trim()
  if (!url) { showToast('Informe a URL do webhook.'); return }
  try {
    const r = await fetch(API + '/n8n/test', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ webhook_url: url })
    })
    const data = await r.json()
    if (r.ok) {
      showToast('✓ ' + (data.message || 'Webhook funcionando!'), 'success')
    } else {
      showToast('✗ ' + (data.error || 'Falha no teste.'))
    }
  } catch {
    showToast('Erro ao testar.')
  }
}

async function integConnectGoogle() {
  const cid = document.getElementById('integ-cfg-google-client-id')?.value?.trim()
  const sec = document.getElementById('integ-cfg-google-client-secret')?.value?.trim()
  if (!cid || !sec) { showToast('Preencha Client ID e Client Secret primeiro.'); return }

  // save credentials to settings first (needed by google auth endpoint)
  await fetch(API + '/google/config', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ client_id: cid, client_secret: sec })
  })

  // also save the integration config
  const id = document.getElementById('integ-id')?.value
  if (id) {
    await fetch(API + '/integrations/' + id, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ config: { client_id: cid, client_secret: sec } })
    })
  }

  try {
    const r = await fetch(API + '/google/auth')
    const data = await r.json()
    if (data.auth_url) {
      window.location.href = data.auth_url
    } else {
      showToast(data.error || 'Erro ao conectar.')
    }
  } catch {
    showToast('Erro de conexão.')
  }
}

async function integDisconnectGoogle() {
  if (!confirm('Desconectar Google Calendar?')) return
  try {
    await fetch(API + '/google/disconnect', { method: 'POST' })
    showToast('Google Calendar desconectado.', 'info')
    const st = document.getElementById('integ-google-status')
    if (st) { st.textContent = 'Desconectado.'; st.className = 'integ-status' }
    const dc = document.getElementById('integ-google-disconnect-btn')
    if (dc) dc.style.display = 'none'
  } catch {
    showToast('Erro ao desconectar.')
  }
}

async function loadNotifPanel() {
  const list = document.getElementById('notif-list')
  if (!list) return
  try {
    const res = await fetch(API + '/notifications/')
    const notifs = await res.json()
    if (!notifs.length) {
      list.innerHTML = '<div class="notif-empty">Nenhuma notificação</div>'
      return
    }
    const iconMap = {
      appointment_created: 'info',
      appointment_cancelled: 'danger',
      meta_atingida: 'success',
    }
    const iconChars = {
      appointment_created: '&#10003;',
      appointment_cancelled: '&#10007;',
      meta_atingida: '&#9733;',
    }
    list.innerHTML = notifs.map(n => {
      const icon = iconMap[n.type] || 'info'
      const ch = iconChars[n.type] || '&#9679;'
      const time = n.created_at ? new Date(n.created_at + 'Z').toLocaleString('pt-BR') : ''
      return `
        <div class="notif-item${n.read ? ' read' : ' unread'}" onclick="${n.read ? '' : "markNotifRead(" + n.id + ")"}">
          <div class="notif-item-icon ${icon}">${ch}</div>
          <div class="notif-item-body">
            <div class="notif-item-title">${n.title}</div>
            <div class="notif-item-msg">${n.message}</div>
            <div class="notif-item-time">${time}</div>
          </div>
          <div class="notif-mark-read"></div>
        </div>`
    }).join('')
  } catch {
    list.innerHTML = '<div class="notif-empty">Erro ao carregar notificações</div>'
  }
}

function toggleNotifPanel() {
  const panel = document.getElementById('notif-panel')
  if (!panel) return
  notifPanelOpen = !notifPanelOpen
  panel.style.display = notifPanelOpen ? 'flex' : 'none'
  if (notifPanelOpen) loadNotifPanel()
}

async function markNotifRead(id) {
  try {
    await fetch(API + '/notifications/read/' + id, { method: 'POST' })
    loadNotifPanel()
    loadNotifDot()
  } catch {}
}

async function readAllNotifs() {
  try {
    await fetch(API + '/notifications/read-all', { method: 'POST' })
    loadNotifPanel()
    loadNotifDot()
  } catch {}
}

document.addEventListener('click', function(e) {
  const panel = document.getElementById('notif-panel')
  const bell = document.querySelector('.badge-notif')
  if (notifPanelOpen && panel && bell && !bell.contains(e.target)) {
    notifPanelOpen = false
    panel.style.display = 'none'
  }
})

// ── EVENT LISTENERS ────────────────────────────────

document.querySelectorAll('.filter-tab').forEach(t => {
  t.addEventListener('click', () => {
    document.querySelectorAll('.filter-tab').forEach(x => x.classList.remove('active'))
    t.classList.add('active')
    if (typeof filterClients === 'function') {
      const filter = t.getAttribute('onclick')?.match(/'([^']+)'/)
      if (filter) filterClients(filter[1])
    }
  })
})
// ── AGENDA VIEW STATE ─────────────────────────────

const _dayNames = ['Domingo','Segunda-feira','Terça-feira','Quarta-feira','Quinta-feira','Sexta-feira','Sábado']
const _dayShort = ['Dom','Seg','Ter','Qua','Qui','Sex','Sáb']
const _monthNames = ['Janeiro','Fevereiro','Março','Abril','Maio','Junho','Julho','Agosto','Setembro','Outubro','Novembro','Dezembro']

let agendaView = 'week'
let agendaDate = new Date()

const DAYS_PT = ['segunda','terca','quarta','quinta','sexta','sabado','domingo']
const DEFAULT_HOURS = { open: '08:00', close: '18:00', closed: false }

function setAgendaView(view, el) {
  agendaView = view
  document.querySelectorAll('#agenda-view-tabs .view-tab').forEach(x => x.classList.remove('active'))
  if (el) el.classList.add('active')
  showAgendaView()
}

function agendaNavPrev() {
  switch (agendaView) {
    case 'day': agendaDate.setDate(agendaDate.getDate() - 1); break
    case 'week': agendaDate.setDate(agendaDate.getDate() - 7); break
    case 'month': agendaDate.setMonth(agendaDate.getMonth() - 1); break
    case 'year': agendaDate.setFullYear(agendaDate.getFullYear() - 1); break
  }
  showAgendaView()
}

function agendaNavNext() {
  switch (agendaView) {
    case 'day': agendaDate.setDate(agendaDate.getDate() + 1); break
    case 'week': agendaDate.setDate(agendaDate.getDate() + 7); break
    case 'month': agendaDate.setMonth(agendaDate.getMonth() + 1); break
    case 'year': agendaDate.setFullYear(agendaDate.getFullYear() + 1); break
  }
  showAgendaView()
}

function agendaNavToday() {
  agendaDate = new Date()
  showAgendaView()
}

function _fmt(d) {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return y + '-' + m + '-' + day
}

function _fmtBR(d) {
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' }).replace('.', '')
}

function showAgendaView() {
  document.getElementById('agenda-week-grid').style.display = 'none'
  document.getElementById('agenda-day-view').style.display = 'none'
  document.getElementById('agenda-month-view').style.display = 'none'
  document.getElementById('agenda-year-view').style.display = 'none'

  switch (agendaView) {
    case 'day': renderDayView(); break
    case 'week': populateWeekGrid(7); break
    case 'month': renderMonthView(); break
    case 'year': renderYearView(); break
  }
}

// ── POPULATE WEEK GRID ────────────────────────────

// ── RENDER DAY VIEW (horizontal list) ─────────────

async function renderDayView() {
  const dayStr = _fmt(agendaDate)
  updateSub(_dayNames[agendaDate.getDay()] + ', ' + agendaDate.getDate() + ' de ' + _monthNames[agendaDate.getMonth()] + ' de ' + agendaDate.getFullYear())

  const appts = await fetchAppts(dayStr, dayStr)

  const sc = { done: 'done', confirmed: 'confirmed', pending: 'pending', cancelled: 'cancelled' }
  const statusLabels = { done: 'Concluído', confirmed: 'Confirmado', pending: 'Pendente', cancelled: 'Cancelado' }
  const statusColors = { done: '#4e8f6a', confirmed: '#4a90d9', pending: '#c9894a', cancelled: '#c05050' }

  let html = '<div class="day-view-panel">'
  if (agendaDate.getDay() === 0) {
    html += '<div class="day-view-empty"><div class="day-view-off">Folga</div><div class="day-view-off-sub">Você não atende aos domingos</div></div>'
  } else if (appts.length === 0) {
    html += '<div class="day-view-empty">Nenhum agendamento neste dia</div>'
  } else {
    appts.sort((a, b) => a.appointment_time.localeCompare(b.appointment_time))
    appts.forEach(a => {
      const cls = sc[a.status] || 'pending'
      const color = statusColors[a.status] || '#999'
      html += '<div class="day-view-card" onclick="openAppointmentDetail(' + a.id + ')">'
      html += '<div class="dvc-time">' + a.appointment_time + '</div>'
      html += '<div class="dvc-dot" style="background:' + color + '"></div>'
      html += '<div class="dvc-body">'
      html += '<div class="dvc-name">' + a.client_name + '</div>'
      html += '<div class="dvc-service">' + a.service + '</div>'
      html += '</div>'
      html += '<div class="dvc-price">R$ ' + Number(a.price).toFixed(2) + '</div>'
      html += '<span class="appt-status status-' + cls + '">' + (statusLabels[a.status] || a.status) + '</span>'
      html += '</div>'
    })
  }
  html += '</div>'

  document.getElementById('agenda-day-view').innerHTML = html
  document.getElementById('agenda-day-view').style.display = ''
  document.getElementById('agenda-summary').textContent = appts.length + ' atendimento' + (appts.length !== 1 ? 's' : '') + ' neste dia'
}

async function populateWeekGrid(numDays) {
  const monday = new Date(agendaDate)
  if (numDays === 7) {
    monday.setDate(agendaDate.getDate() - (agendaDate.getDay() === 0 ? 6 : agendaDate.getDay() - 1))
  }
  const sunday = new Date(monday)
  sunday.setDate(monday.getDate() + numDays - 1)

  const isDayView = numDays === 1
  if (isDayView) {
    updateSub(_dayNames[agendaDate.getDay()] + ', ' + agendaDate.getDate() + ' de ' + _monthNames[agendaDate.getMonth()] + ' de ' + agendaDate.getFullYear())
  } else {
    updateSub(_fmtBR(monday) + ' – ' + _fmtBR(sunday) + ' ' + sunday.getFullYear())
  }

  const weekGrid = document.getElementById('agenda-week-grid')
  weekGrid.classList.toggle('day-view', isDayView)

  const appts = await fetchAppts(_fmt(monday), _fmt(sunday))
  if (!servicesCache.length) await loadServices()
  const todayStr = _fmt(new Date())

  // Load business hours
  let hoursMap = {}
  try {
    const r = await fetch(API + '/business-hours')
    hoursMap = await r.json()
  } catch (_) {}

  // Find global min/max across visible days
  let globalOpen = 8 * 60, globalClose = 17 * 60
  for (let i = 0; i < numDays; i++) {
    const day = new Date(monday)
    day.setDate(monday.getDate() + i)
    const dow = day.getDay()
    const dk = DAYS_PT[dow]
    const h = hoursMap[dk] || DEFAULT_HOURS
    if (!h.closed) {
      const o = parseInt(h.open) * 60 + parseInt(h.open?.split(':')[1] || '0')
      const c = parseInt(h.close) * 60 + parseInt(h.close?.split(':')[1] || '0')
      if (o < globalOpen) globalOpen = o
      if (c > globalClose) globalClose = c
    }
  }

  const hourStep = isDayView ? 30 : 60
  const slotHeight = isDayView ? 26 : 52

  let timeHtml = '<div class="time-col-header"></div>'
  for (let t = globalOpen; t <= globalClose; t += hourStep) {
    const hh = Math.floor(t / 60)
    const mm = t % 60
    const label = mm === 0 ? hh + 'h' : hh + ':' + String(mm).padStart(2, '0')
    timeHtml += '<div class="time-slot-label" style="height:' + slotHeight + 'px;">' + label + '</div>'
  }
  document.getElementById('agenda-time-col').innerHTML = timeHtml

  let dayHtml = ''
  for (let i = 0; i < numDays; i++) {
    const day = new Date(monday)
    day.setDate(monday.getDate() + i)
    if (isDayView && i === 0) { const d2 = new Date(agendaDate); d2.setHours(12); day.setTime(d2.getTime()) }
    const dayStr = _fmt(day)
    const isToday = dayStr === todayStr
    const dow = day.getDay()
    const dayKey = DAYS_PT[dow]
    const dayInfo = hoursMap[dayKey] || DEFAULT_HOURS
    const isClosed = dayInfo.closed
    const dayOpenMin = isClosed ? 0 : parseInt(dayInfo.open) * 60 + parseInt(dayInfo.open?.split(':')[1] || '0')
    const dayCloseMin = isClosed ? 0 : parseInt(dayInfo.close) * 60 + parseInt(dayInfo.close?.split(':')[1] || '0')

    dayHtml += '<div class="day-col" style="' + (isDayView ? 'flex:1;' : '') + '">'
    dayHtml += '<div class="day-header"><div class="day-name">' + _dayShort[dow] + '</div><div class="day-num' + (isToday ? ' today' : '') + '">' + day.getDate() + '</div></div>'
    dayHtml += '<div class="day-slots">'

    if (isClosed) {
      dayHtml += '<div class="folga-overlay"></div><div class="folga-label">Folga</div>'
    } else {
      // Empty slots before open
      for (let t = globalOpen; t < dayOpenMin; t += hourStep) {
        dayHtml += '<div class="hour-line closed-slot" style="height:' + slotHeight + 'px;background:#f8f9fc;"></div>'
      }
      // Open slots
      for (let t = dayOpenMin; t <= dayCloseMin; t += hourStep) {
        const hh = Math.floor(t / 60)
        const mm = t % 60
        dayHtml += '<div class="hour-line" style="height:' + slotHeight + 'px;" data-date="' + dayStr + '" data-hour="' + String(hh).padStart(2,'0') + ':' + String(mm).padStart(2,'0') + '"></div>'
      }
      // Empty slots after close
      for (let t = dayCloseMin + hourStep; t <= globalClose; t += hourStep) {
        dayHtml += '<div class="hour-line closed-slot" style="height:' + slotHeight + 'px;background:#f8f9fc;"></div>'
      }

      const dayAppts = appts.filter(a => a.appointment_date === dayStr)
      const sc = { done: 'done', confirmed: 'confirmed', pending: 'pending', cancelled: 'cancelled' }
      dayAppts.forEach(a => {
        const [h, m] = a.appointment_time.split(':').map(Number)
        const top = ((h * 60 + m) - globalOpen) / hourStep * slotHeight
        const height = Math.max(slotHeight, (a.duration / hourStep) * slotHeight)
        dayHtml += '<div class="cal-event ' + (sc[a.status] || 'pending') + '" style="top:' + top + 'px;height:' + height + 'px;cursor:pointer;" data-id="' + a.id + '">'
        dayHtml += '<div class="ev-name">' + a.client_name + '</div><div class="ev-svc">' + a.service + '</div></div>'
      })
    }
    dayHtml += '</div></div>'
  }

  const grid = document.getElementById('agenda-days-grid')
  grid.innerHTML = dayHtml
  grid.style.gridTemplateColumns = isDayView ? '1fr' : 'repeat(7, 1fr)'
  weekGrid.style.display = ''
  document.getElementById('agenda-summary').textContent = appts.length + ' atendimento' + (appts.length !== 1 ? 's' : '')

  document.querySelectorAll('#agenda-days-grid .cal-event').forEach(el => {
    el.addEventListener('click', function(e) { e.stopPropagation(); openAppointmentDetail(+this.dataset.id) })
  })
  document.querySelectorAll('#agenda-days-grid .hour-line:not(.closed-slot)').forEach(el => {
    el.style.cursor = 'pointer'
    el.addEventListener('click', function() { openAppointmentModal(this.dataset.date, this.dataset.hour) })
  })
}

async function fetchAppts(from, to) {
  try {
    const r = await fetch(API + '/appointments/?date_from=' + from + '&date_to=' + to)
    return await r.json()
  } catch (e) { return [] }
}

function updateSub(label) {
  document.getElementById('agenda-period').textContent = label
  document.getElementById('page-sub').textContent = label
  pageConfig.agenda.sub = label
}

// ── RENDER MONTH VIEW ─────────────────────────────

async function renderMonthView() {
  const year = agendaDate.getFullYear()
  const month = agendaDate.getMonth()
  updateSub(_monthNames[month] + ' ' + year)

  const firstDay = new Date(year, month, 1)
  const lastDay = new Date(year, month + 1, 0)
  const daysInMonth = lastDay.getDate()
  const startOffset = firstDay.getDay()
  const todayStr = _fmt(new Date())
  const appts = await fetchAppts(_fmt(firstDay), _fmt(lastDay))

  const byDay = {}
  appts.forEach(a => { byDay[a.appointment_date] = (byDay[a.appointment_date] || 0) + 1 })

  let html = '<div class="month-grid"><div class="month-grid-header">'
  _dayShort.forEach(d => { html += '<div class="month-grid-header-cell">' + d + '</div>' })
  html += '</div><div class="month-grid-body">'
  for (let i = 0; i < startOffset; i++) html += '<div class="month-grid-cell empty"></div>'
  for (let d = 1; d <= daysInMonth; d++) {
    const ds = _fmt(new Date(year, month, d))
    const isToday = ds === todayStr
    const cnt = byDay[ds] || 0
    html += '<div class="month-grid-cell' + (isToday ? ' today' : '') + '" data-date="' + ds + '">'
    html += '<div class="month-grid-day">' + d + '</div>'
    if (cnt) html += '<div class="month-grid-count">' + cnt + ' agend.</div>'
    html += '</div>'
  }
  html += '</div></div>'

  document.getElementById('agenda-month-view').innerHTML = html
  document.getElementById('agenda-month-view').style.display = ''

  document.querySelectorAll('#agenda-month-view .month-grid-cell:not(.empty)').forEach(el => {
    el.style.cursor = 'pointer'
    el.addEventListener('click', function() {
      agendaDate = new Date(this.dataset.date + 'T12:00:00')
      agendaView = 'day'
      document.querySelectorAll('#agenda-view-tabs .view-tab').forEach(x => x.classList.remove('active'))
      document.querySelector('#agenda-view-tabs .view-tab:first-child').classList.add('active')
      showAgendaView()
    })
  })

  document.getElementById('agenda-summary').textContent = appts.length + ' atendimento' + (appts.length !== 1 ? 's' : '') + ' no mês'
}

// ── RENDER YEAR VIEW ──────────────────────────────

async function renderYearView() {
  const year = agendaDate.getFullYear()
  updateSub('' + year)

  const panels = []
  for (let m = 0; m < 12; m++) {
    const first = new Date(year, m, 1)
    const last = new Date(year, m + 1, 0)
    const appts = await fetchAppts(_fmt(first), _fmt(last))
    const total = appts.reduce((s, a) => s + a.price, 0)
    const startOff = first.getDay()

    const byDay = {}
    appts.forEach(a => { byDay[a.appointment_date] = (byDay[a.appointment_date] || 0) + 1 })

    let cellHtml = ''
    for (let i = 0; i < startOff; i++) cellHtml += '<div class="year-month-cell empty"></div>'
    for (let d = 1; d <= last.getDate(); d++) {
      const ds = _fmt(new Date(year, m, d))
      const hasAppt = !!byDay[ds]
      cellHtml += '<div class="year-month-cell' + (hasAppt ? ' has-appt' : '') + '"><span>' + d + '</span></div>'
    }

    panels.push({
      month: m,
      html: '<div class="year-month-panel" data-month="' + m + '">'
        + '<div class="year-month-name">' + _monthNames[m] + '</div>'
        + '<div class="year-month-grid">'
        + _dayShort.map(d => '<div class="year-month-header-cell">' + d + '</div>').join('')
        + cellHtml + '</div>'
        + '<div class="year-month-summary">' + appts.length + ' atend. · R$ ' + total.toFixed(0) + '</div>'
        + '</div>'
    })
  }

  document.getElementById('agenda-year-view').innerHTML = '<div class="year-grid">' + panels.map(p => p.html).join('') + '</div>'
  document.getElementById('agenda-year-view').style.display = ''

  document.querySelectorAll('#agenda-year-view .year-month-panel').forEach(el => {
    el.style.cursor = 'pointer'
    el.addEventListener('click', function() {
      agendaDate = new Date(year, +this.dataset.month, 1)
      agendaView = 'month'
      document.querySelectorAll('#agenda-view-tabs .view-tab').forEach(x => x.classList.remove('active'))
      document.querySelectorAll('#agenda-view-tabs .view-tab')[2].classList.add('active')
      showAgendaView()
    })
  })

  document.getElementById('agenda-summary').textContent = '' + year
}

// Botão "+ Nova Cliente" no toolbar
document.querySelector('.clients-toolbar .btn-primary')?.addEventListener('click', openClientModal)

function toggleMobileMenu() {
  const sidebar = document.getElementById('sidebar')
  const overlay = document.getElementById('sidebar-overlay')
  const btn = document.getElementById('menu-toggle')
  sidebar.classList.toggle('open')
  overlay.classList.toggle('open')
  btn.classList.toggle('open')
}

function closeMobileMenu() {
  document.getElementById('sidebar').classList.remove('open')
  document.getElementById('sidebar-overlay').classList.remove('open')
  document.getElementById('menu-toggle').classList.remove('open')
}

function setTheme(theme, el) {
  document.querySelector('.screen').setAttribute('data-theme', theme)
  document.querySelectorAll('.theme-option').forEach(o => o.classList.remove('active'))
  if (el) el.classList.add('active')
  localStorage.setItem('beautyflow-theme', theme)
}

function setFontSize(size, el) {
  document.querySelector('.screen').setAttribute('data-font-size', size)
  document.querySelectorAll('.font-size-option').forEach(o => o.classList.remove('active'))
  if (el) el.classList.add('active')
  localStorage.setItem('beautyflow-fontsize', size)
}

function setSidebarMode(mode, el) {
  const sidebar = document.getElementById('sidebar')
  if (mode === 'collapsed') sidebar.classList.add('collapsed')
  else sidebar.classList.remove('collapsed')
  localStorage.setItem('beautyflow-sidebar', mode)
}

function toggleSidebarMode() {
  const sidebar = document.getElementById('sidebar')
  sidebar.classList.toggle('collapsed')
  localStorage.setItem('beautyflow-sidebar', sidebar.classList.contains('collapsed') ? 'collapsed' : 'expanded')
}

function setLayoutMode(mode, el) {
  const screen = document.querySelector('.screen')
  if (mode === 'horizontal') screen.classList.add('layout-horizontal')
  else screen.classList.remove('layout-horizontal')
  document.querySelectorAll('.layout-mode-option').forEach(o => o.classList.remove('active'))
  if (el) el.classList.add('active')
  localStorage.setItem('beautyflow-layout', mode)
}

function setColorScheme(scheme, el) {
  document.querySelector('.screen').setAttribute('data-color-scheme', scheme)
  document.querySelectorAll('.scheme-option').forEach(o => o.classList.remove('active'))
  if (el) el.classList.add('active')
  localStorage.setItem('beautyflow-scheme', scheme)
}

;(function init() {
  const screen = document.querySelector('.screen')
  const savedTheme = localStorage.getItem('beautyflow-theme') || 'default'
  screen.setAttribute('data-theme', savedTheme)
  document.querySelectorAll('.theme-option').forEach(o => o.classList.remove('active'))
  const activeTheme = document.querySelector(`.theme-option[data-theme="${savedTheme}"]`)
  if (activeTheme) activeTheme.classList.add('active')

  const savedScheme = localStorage.getItem('beautyflow-scheme') || 'light'
  screen.setAttribute('data-color-scheme', savedScheme)
  document.querySelectorAll('.scheme-option').forEach(o => o.classList.remove('active'))
  const activeScheme = document.querySelector(`.scheme-option[data-scheme="${savedScheme}"]`)
  if (activeScheme) activeScheme.classList.add('active')

  const savedLayout = localStorage.getItem('beautyflow-layout') || 'vertical'
  if (savedLayout === 'horizontal') screen.classList.add('layout-horizontal')
  document.querySelectorAll('.layout-mode-option').forEach(o => o.classList.remove('active'))
  const activeLayout = document.querySelector(`.layout-mode-option[data-layout="${savedLayout}"]`)
  if (activeLayout) activeLayout.classList.add('active')

  const savedFontSize = localStorage.getItem('beautyflow-fontsize') || 'small'
  screen.setAttribute('data-font-size', savedFontSize)
  document.querySelectorAll('.font-size-option').forEach(o => o.classList.remove('active'))
  const activeFont = document.querySelector(`.font-size-option[data-size="${savedFontSize}"]`)
  if (activeFont) activeFont.classList.add('active')

  const savedSidebar = localStorage.getItem('beautyflow-sidebar') || 'expanded'
  if (savedSidebar === 'collapsed') document.getElementById('sidebar').classList.add('collapsed')

  screen.style.display = 'none'

  const ls = document.getElementById('loadingScreen')
  if (ls) setTimeout(() => ls.classList.add('hide'), 300)

  loadServices()
  checkAuth()
  startNotifPoll()
})()

document.querySelectorAll('.btn-primary, .btn-outline').forEach(btn => {
  btn.addEventListener('click', function(e) {
    const rect = this.getBoundingClientRect()
    const x = ((e.clientX - rect.left) / rect.width) * 100
    const y = ((e.clientY - rect.top) / rect.height) * 100
    this.style.setProperty('--ripple-x', x + '%')
    this.style.setProperty('--ripple-y', y + '%')
  })
})
