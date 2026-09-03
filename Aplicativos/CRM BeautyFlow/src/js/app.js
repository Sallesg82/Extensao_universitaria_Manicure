const API = window.location.origin + '/api'

let currentUser = null

function getLocalDateString(d = new Date()) {
  const year = d.getFullYear()
  const month = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

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
  _socket.on('dev:reload', () => {
    console.log('[Dev] Código alterado, atualizando página...')
    window.location.reload()
  })
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
    else if (currentPageId === 'despesas') loadDespesas()
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
      <label>Email ou Usuário</label>
      <input type="text" id="login-email" placeholder="admin ou seu@email.com" autocomplete="username">
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
  const userNameEl = card.querySelector('.user-name')
  if (userNameEl) {
    userNameEl.textContent = currentUser.name || ''
    userNameEl.title = currentUser.name || ''
  }
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
    agenda:    { ms: 10000, fn: refreshAgenda },
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
  despesas:       { title: 'Despesas do Mês', sub: 'Acompanhe seus gastos do mês', btn: '+ Nova Despesa' },
  relatorios:     { title: 'Relatórios',      sub: 'Análise - Mês',      btn: '⬇ Exportar PDF' },
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

  let pageEl = document.getElementById('page-' + pageId)
  if (!pageEl) {
    pageId = 'dashboard'
    pageEl = document.getElementById('page-dashboard')
    navEl = document.querySelector('.nav-item[onclick*="\'dashboard\'"]')
  }

  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'))
  pageEl.classList.add('active')

  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'))
  if (navEl) navEl.classList.add('active')

  closeMobileMenu()

  const cfg = pageConfig[pageId] || pageConfig.dashboard
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
    const defaultDate = pageId === 'agenda' && agendaDate ? _fmt(agendaDate) : null
    openAppointmentModal(defaultDate)
  } else if (pageId === 'clientes') {
    openClientModal()
  } else if (pageId === 'servicos') {
    openServiceModal()
  } else if (pageId === 'financeiro') {
    openTransactionModal('income')
  } else if (pageId === 'despesas') {
    openTransactionModal('expense')
  } else if (pageId === 'relatorios') {
    exportRelatorioPDF()
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
  ;['tab-perfil','tab-horarios','tab-notif','tab-integ','tab-aparencia','tab-empresa'].forEach(id => {
    const el = document.getElementById(id)
    if (el) el.style.display = id === tabId ? '' : 'none'
  })
  if (tabId === 'tab-perfil') updateProfileTab()
  if (tabId === 'tab-integ') { loadIntegrations() }
  if (tabId === 'tab-horarios') { loadBusinessHours() }
  if (tabId === 'tab-empresa') { loadCompanyInfo() }
  if (tabId === 'tab-notif') { loadNotificacoes() }
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
    const isAdmin = currentUser && currentUser.role === 'admin'
    tbody.innerHTML = users.map(u => {
      const date = u.created_at ? u.created_at.split('T')[0].split('-').reverse().join('/') : '—'
      const isSelf = currentUser && currentUser.id === u.id
      let actions = ''
      if (isAdmin && !isSelf) {
        actions += `<button class="btn-outline btn-sm" style="margin-right:4px;" onclick="showEditUserModal(${u.id})">Editar</button>`
      }
      if (u.role !== 'admin' || !isSelf) {
        actions += `<button class="btn-outline btn-sm btn-danger" onclick="deleteUser(${u.id},'${u.name}')">Remover</button>`
      }
      return `<tr>
        <td><div class="user-cell-name">${u.name}${isSelf ? ' <span style="color:var(--primary-500);font-size:11px;">(você)</span>' : ''}</div></td>
        <td>${u.email}</td>
        <td>${u.phone || '—'}</td>
        <td>${u.role === 'admin' ? 'Administradora' : 'Usuário'}</td>
        <td>${date}</td>
        <td>${actions}</td>
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
    setTimeout(() => {
      const parent = el.parentElement
      if (parent && parent !== document.body) parent.remove()
      else el.remove()
    }, 200)
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

function showEditUserModal(userId) {
  fetch(API + '/users/' + userId).then(r => r.json()).then(u => {
    const html = `
      <div class="modal-overlay" id="edit-user-overlay" onclick="if(event.target===this)closeEditUserModal()">
        <div class="modal-card" style="max-width:420px;">
          <div class="modal-header"><div class="modal-title">Editar Usuário</div><button class="modal-close" onclick="closeEditUserModal()">×</button></div>
          <div class="modal-body">
            <input type="hidden" id="eu-id" value="${u.id}">
            <div class="form-row"><div class="form-field full"><label class="form-label">Nome</label><input class="form-input" id="eu-name" value="${u.name.replace(/"/g,'&quot;')}"></div></div>
            <div class="form-row"><div class="form-field full"><label class="form-label">Email</label><input class="form-input" id="eu-email" type="email" value="${u.email}"></div></div>
            <div class="form-row"><div class="form-field full"><label class="form-label">Telefone</label><input class="form-input" id="eu-phone" value="${u.phone || ''}"></div></div>
            <div class="form-row"><div class="form-field full"><label class="form-label">Nova senha (deixe em branco para manter)</label><input class="form-input" id="eu-password" type="password" placeholder="••••••"></div></div>
            <div class="form-row"><div class="form-field full"><label class="form-label">Tipo</label><select class="form-input" id="eu-role"><option value="user"${u.role === 'user' ? ' selected' : ''}>Comum</option><option value="admin"${u.role === 'admin' ? ' selected' : ''}>Administrador</option></select></div></div>
            <div id="eu-msg" class="auth-msg"></div>
          </div>
          <div class="modal-footer"><button class="btn-outline" onclick="closeEditUserModal()">Cancelar</button><button class="btn-primary" onclick="saveEditUser()">Salvar</button></div>
        </div>
      </div>`
    const div = document.createElement('div')
    div.innerHTML = html
    document.body.appendChild(div)
    requestAnimationFrame(() => document.getElementById('edit-user-overlay').classList.add('open'))
    document.getElementById('eu-name').focus()
    ;['eu-name','eu-email','eu-phone','eu-password','eu-role'].forEach(id => {
      document.getElementById(id)?.addEventListener('keydown', e => {
        if (e.key === 'Enter') saveEditUser()
      })
    })
  })
}

function closeEditUserModal() {
  const el = document.getElementById('edit-user-overlay')
  if (el) {
    el.classList.remove('open')
    setTimeout(() => {
      const parent = el.parentElement
      if (parent && parent !== document.body) parent.remove()
      else el.remove()
    }, 200)
  }
}

async function saveEditUser() {
  const id = document.getElementById('eu-id').value
  const name = document.getElementById('eu-name').value.trim()
  const email = document.getElementById('eu-email').value.trim()
  const phone = document.getElementById('eu-phone').value.trim()
  const password = document.getElementById('eu-password').value
  const role = document.getElementById('eu-role').value
  const msg = document.getElementById('eu-msg')
  if (!name || !email) { msg.textContent = 'Nome e email são obrigatórios.'; msg.className = 'auth-msg error'; return }
  try {
    const body = { name, email, phone, role }
    if (password) body.password = password
    const r = await fetch(API + '/users/' + id, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    })
    const data = await r.json()
    if (r.ok) { closeEditUserModal(); loadUsuarios() }
    else { msg.textContent = data.error || 'Erro ao salvar.'; msg.className = 'auth-msg error' }
  } catch (e) { msg.textContent = 'Erro de conexão.'; msg.className = 'auth-msg error' }
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
    const activeTab = document.querySelector('.filter-tab.active')
    const filter = activeTab?.getAttribute('data-filter') || 'all'
    filterClients(filter)
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
    const statusMap = { frequente: 'Frequente', regular: 'Regular', novo: 'Novo', inativo: 'Inativo', inadimplente: 'Inadimplente' }
    const statusClassMap = { frequente: 'status-done', regular: 'status-confirmed', novo: 'status-pending', inativo: 'status-pending', inadimplente: 'status-cancelled' }
    const label = statusMap[c.status] || c.status
    const cls = statusClassMap[c.status] || 'status-pending'
    const spent = 'R$ ' + Number(c.total_spent).toLocaleString('pt-BR', {minimumFractionDigits: 0})
    const caloteiroIcon = c.status === 'inadimplente' ? '<span style="color:#c05050;font-size:13px;margin-right:4px;" title="Inadimplente">⚠</span>' : ''
    return `
      <div class="client-row${i === 0 ? ' selected' : ''}" onclick="selectClient(this, ${c.id})">
        <div class="client-info-cell">
          <div class="client-av" style="background:${c.avatar_bg};color:${c.avatar_color};">${c.avatar_initials}</div>
          <div>
            <div class="client-name-cell">${caloteiroIcon}${c.name}</div>
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
    const cpfStr = c.cpf ? ' · CPF: ' + c.cpf.replace(/^(\d{3})\d{3}(\d{3}\d{2})$/, '$1.***.***.**-$2') : ''
    document.getElementById('cd-phone').textContent = c.phone + cpfStr + (since ? ' · Cliente desde ' + since : '')
    document.getElementById('cd-visits').textContent = c.visits
    document.getElementById('cd-total').textContent = 'R$ ' + Number(c.total_spent).toLocaleString('pt-BR', {minimumFractionDigits:0})
    const avg = c.visits > 0 ? c.total_spent / c.visits : 0
    document.getElementById('cd-ticket').textContent = 'R$ ' + avg.toFixed(0)
    document.getElementById('cd-last').textContent = c.last_visit || '—'

    const btnCal = document.getElementById('btn-caloteiro')
    const btnText = document.getElementById('btn-caloteiro-text')
    if (btnCal && btnText) {
      if (c.status === 'inadimplente') {
        btnCal.style.borderColor = '#c05050'
        btnCal.style.color = '#c05050'
        btnText.textContent = 'Desmarcar Inadimplente'
      } else {
        btnCal.style.borderColor = ''
        btnCal.style.color = ''
        btnText.textContent = 'Inadimplente'
      }
    }

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

let dashSelectedMonth = new Date().getMonth() + 1
let dashSelectedYear = new Date().getFullYear()

function populateDashboardYearSelect() {
  const yEl = document.getElementById('dash-select-year')
  if (!yEl) return
  const currentYear = new Date().getFullYear()
  if (yEl.options.length > 0 && yEl.querySelector(`option[value="${dashSelectedYear}"]`)) {
    return
  }
  const startYear = Math.min(currentYear - 4, dashSelectedYear - 1)
  const endYear = Math.max(currentYear + 3, dashSelectedYear + 1)
  yEl.innerHTML = ''
  for (let y = startYear; y <= endYear; y++) {
    const opt = document.createElement('option')
    opt.value = y
    opt.textContent = y
    yEl.appendChild(opt)
  }
}

function syncDashboardControls() {
  populateDashboardYearSelect()

  const mEl = document.getElementById('dash-select-month')
  const yEl = document.getElementById('dash-select-year')
  if (mEl) mEl.value = String(dashSelectedMonth)
  if (yEl) yEl.value = String(dashSelectedYear)

  const monthNames = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
  ]
  const periodText = (monthNames[dashSelectedMonth - 1] || '') + ' de ' + dashSelectedYear
  const periodTextEl = document.getElementById('dash-period-text')
  if (periodTextEl) periodTextEl.textContent = periodText

  const now = new Date()
  const isCurrent = (dashSelectedMonth === (now.getMonth() + 1) && dashSelectedYear === now.getFullYear())
  const todayBtn = document.getElementById('dash-today-btn')
  if (todayBtn) {
    todayBtn.classList.toggle('is-current', isCurrent)
    todayBtn.title = isCurrent ? 'Você está visualizando o mês atual' : 'Voltar para o mês atual'
  }
}

function changeDashboardMonth(delta) {
  dashSelectedMonth += delta
  if (dashSelectedMonth > 12) {
    dashSelectedMonth = 1
    dashSelectedYear += 1
  } else if (dashSelectedMonth < 1) {
    dashSelectedMonth = 12
    dashSelectedYear -= 1
  }
  syncDashboardControls()
  loadDashboard()
}

function onDashboardDateSelectChange() {
  const mEl = document.getElementById('dash-select-month')
  const yEl = document.getElementById('dash-select-year')
  if (mEl && yEl) {
    dashSelectedMonth = parseInt(mEl.value, 10)
    dashSelectedYear = parseInt(yEl.value, 10)
    syncDashboardControls()
    loadDashboard()
  }
}

function resetDashboardMonth() {
  const now = new Date()
  dashSelectedMonth = now.getMonth() + 1
  dashSelectedYear = now.getFullYear()
  syncDashboardControls()
  loadDashboard()
}

async function loadDashboard() {
  try {
    const now = new Date()
    if (!dashSelectedMonth) dashSelectedMonth = now.getMonth() + 1
    if (!dashSelectedYear) dashSelectedYear = now.getFullYear()

    syncDashboardControls()

    const res = await fetch(`${API}/stats?month=${dashSelectedMonth}&year=${dashSelectedYear}`)
    const stats = await res.json()

    const dot = document.getElementById('notif-dot')
    if (dot && stats.notifications_unread !== undefined) {
      dot.classList.toggle('hidden', !stats.notifications_unread)
    }

    const today = new Date()
    const days = ['Domingo','Segunda-feira','Terça-feira','Quarta-feira','Quinta-feira','Sexta-feira','Sábado']
    const months = ['janeiro','fevereiro','março','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro']

    const isCurrentMonth = (dashSelectedMonth === (today.getMonth() + 1) && dashSelectedYear === today.getFullYear())

    if (isCurrentMonth) {
      pageConfig.dashboard.sub = days[today.getDay()] + ', ' + today.getDate() + ' de ' + months[today.getMonth()] + ' de ' + today.getFullYear()
    } else {
      pageConfig.dashboard.sub = 'Visualizando mês: ' + (stats.month_label || months[dashSelectedMonth - 1]) + ' de ' + stats.month_year
    }
    const pageSubEl = document.getElementById('page-sub')
    if (pageSubEl && (location.hash.slice(1) || 'dashboard') === 'dashboard') {
      pageSubEl.textContent = pageConfig.dashboard.sub
    }

    const setEl = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val }

    // Cards de métricas
    const todayRev = Number(stats.today_revenue || 0)
    const monthRev = Number(stats.month_revenue || 0)
    const todayCnt = Number(stats.today_count || 0)
    const monthApptCnt = Number(stats.month_appointments_count || 0)
    const activeCl = Number(stats.active_clients || 0)
    const monthCl = Number(stats.month_clients || 0)
    const avgTkt = Number(stats.avg_ticket || 0)

    if (isCurrentMonth) {
      setEl('metric-receita-label', 'Receita Hoje')
      setEl('metric-receita', 'R$ ' + todayRev.toFixed(0))
      setEl('metric-receita-change', 'R$ ' + monthRev.toLocaleString('pt-BR', {minimumFractionDigits: 0}) + ' no mês')

      setEl('metric-atendimentos-label', 'Atendimentos')
      setEl('metric-atendimentos', todayCnt)
      setEl('metric-atendimentos-change', monthApptCnt + ' no mês')

      setEl('metric-clientes-label', 'Clientes Ativos')
      setEl('metric-clientes', activeCl)
      setEl('metric-clientes-change', monthCl + ' atendidas no mês')

      setEl('metric-ticket-label', 'Ticket Médio')
      setEl('metric-ticket', 'R$ ' + avgTkt.toFixed(0))
      setEl('metric-ticket-change', '')
    } else {
      setEl('metric-receita-label', 'Receita no Mês')
      setEl('metric-receita', 'R$ ' + monthRev.toLocaleString('pt-BR', {minimumFractionDigits: 0}))
      setEl('metric-receita-change', (stats.month_label || '') + ' de ' + stats.month_year)

      setEl('metric-atendimentos-label', 'Atendimentos no Mês')
      setEl('metric-atendimentos', monthApptCnt)
      setEl('metric-atendimentos-change', (stats.month_label || '') + ' de ' + stats.month_year)

      setEl('metric-clientes-label', 'Clientes no Mês')
      setEl('metric-clientes', monthCl)
      setEl('metric-clientes-change', activeCl + ' cadastrados no total')

      setEl('metric-ticket-label', 'Ticket Médio')
      setEl('metric-ticket', 'R$ ' + avgTkt.toFixed(0))
      setEl('metric-ticket-change', '')
    }

    // ── Fluxo de Caixa ──
    const monthSub = document.getElementById('fluxo-subtitle')
    if (monthSub) monthSub.textContent = (stats.month_label || months[dashSelectedMonth - 1]) + ' ' + stats.month_year

    const profit = monthRev - Number(stats.month_expenses || 0)
    const lucroEl = document.getElementById('fluxo-lucro')
    if (lucroEl) lucroEl.textContent = 'R$ ' + profit.toLocaleString('pt-BR', {minimumFractionDigits: 0})

    const metaEl = document.getElementById('fluxo-meta')
    if (metaEl) {
      if (stats.meta_mensal > 0) {
        const above = profit >= stats.meta_mensal
        const diff = Math.abs(profit - stats.meta_mensal)
        metaEl.innerHTML = (above ? '↑' : '↓') + ' ' + diff.toLocaleString('pt-BR', {minimumFractionDigits: 0}) + ' ' + (above ? 'acima da meta' : 'abaixo da meta')
      } else {
        metaEl.textContent = ''
      }
    }

    const bars = document.querySelectorAll('.bar-fill')
    bars.forEach(b => { if (b) b.style.height = '0px' })
    if (stats.weekly_revenue && stats.weekly_revenue.length > 0) {
      const maxVal = Math.max(...stats.weekly_revenue, 1)
      stats.weekly_revenue.forEach((val, i) => {
        if (bars[i]) {
          const pct = Math.round((val / maxVal) * 60)
          bars[i].style.height = Math.max(8, pct) + 'px'
        }
      })
    }

    const srvContainer = document.getElementById('fluxo-servicos')
    if (srvContainer) {
      if (stats.service_breakdown && stats.service_breakdown.length > 0) {
        const colors = ['var(--primary-500)', 'var(--primary-600)', 'var(--primary-400)', 'var(--primary-700)', 'var(--primary-300)']
        srvContainer.innerHTML = '<div class="services-list-title">Serviços</div>' +
          stats.service_breakdown.map((svc, i) => `
            <div class="service-row">
              <div class="service-dot" style="background:${colors[i % colors.length]}"></div>
              <div class="service-name">${svc.name}</div>
              <div class="service-bar-bg"><div class="service-bar-fill" style="width:${svc.pct}%;background:${colors[i % colors.length]}"></div></div>
              <div class="service-pct">${svc.pct}%</div>
            </div>
          `).join('')
      } else {
        srvContainer.innerHTML = '<div class="services-list-title">Serviços</div><div style="padding:10px 0;text-align:center;font-size:13px;color:var(--text-secondary);">Sem serviços registrados neste mês</div>'
      }
    }

    // ── Alertas Inteligentes ──
    const iv = id => document.getElementById(id)

    const pct = Math.round(stats.month_revenue >= stats.meta_mensal ? 100 : stats.meta_pct)
    const metaVal = iv('insight-meta-value')
    if (metaVal) metaVal.textContent = pct + '%'
    const metaBar = iv('insight-meta-bar')
    if (metaBar) metaBar.style.width = pct + '%'

    const inactVal = iv('insight-inactive-value')
    if (inactVal) {
      const rev = stats.inactive_revenue || 0
      inactVal.textContent = stats.inactive_clients + ' · R$ ' + rev.toFixed(0)
    }

    const pendVal = iv('insight-pending-value')
    if (pendVal) pendVal.textContent = stats.pending_future || '0'

    const peakSub = document.getElementById('peak-hours-subtitle')
    if (peakSub) peakSub.textContent = (stats.month_label || 'Este mês') + ' ' + (stats.month_year || '')

    renderPeakHoursDashboard(stats)

    const apptList = document.querySelector('.appt-list')
    const apptBadge = document.getElementById('today-appt-badge')
    if (apptList && stats.today_appointments) {
      const statusMap = { done: 'Concluído', confirmed: 'Confirmado', pending: 'Pendente', cancelled: 'Cancelado' }
      const statusClassMap = { done: 'status-done', confirmed: 'status-confirmed', pending: 'status-pending', cancelled: 'status-pending' }
      const colorMap = { done: 'var(--success, #4e8f6a)', confirmed: 'var(--primary-500)', pending: 'var(--warning, #c9894a)', cancelled: 'var(--danger, #c05050)' }

      if (stats.today_appointments.length > 0) {
        if (apptBadge) apptBadge.textContent = stats.today_appointments.length + ' agendado' + (stats.today_appointments.length !== 1 ? 's' : '')
        apptList.innerHTML = stats.today_appointments.map(a => `
          <div class="appt-item" onclick="openAppointmentDetail(${a.id})" style="cursor:pointer;">
            <div class="appt-time">${a.appointment_time}</div>
            <div class="appt-dot" style="background:${colorMap[a.status] || 'var(--primary-500)'}"></div>
            <div class="appt-info">
              <div class="appt-name">${a.client_name}</div>
              <div class="appt-service">${a.service}</div>
            </div>
            <div class="appt-price">R$ ${Number(a.price).toFixed(0)}</div>
            <span class="appt-status ${statusClassMap[a.status] || 'status-pending'}">${statusMap[a.status] || a.status}</span>
            <span class="appt-status ${a.payment_status === 'paid' ? 'status-paid' : 'status-unpaid'}" style="margin-left:4px;">${a.payment_status === 'paid' ? 'Pago' : 'Não Pago'}</span>
          </div>
        `).join('')
      } else {
        if (apptBadge) apptBadge.textContent = ''
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
    const isDark = document.documentElement.getAttribute('data-color-scheme') === 'dark' || document.querySelector('.screen')?.getAttribute('data-color-scheme') === 'dark'
    const donutColors = ['var(--primary-500)', 'var(--primary-600)', 'var(--primary-400)', 'var(--primary-700)', 'var(--primary-300)']
    const bgStroke = isDark ? 'rgba(255, 255, 255, 0.08)' : 'var(--primary-100, #edf5fd)'
    const textColor = isDark ? '#f0f6fc' : '#0f2340'

    if (donutSvg) {
      let svgContent = ''
      const bgCircle = `<circle class="donut-bg-circle" cx="45" cy="45" r="32" fill="none" stroke="${bgStroke}" stroke-width="14"/>`
      if (s.service_revenue_breakdown && s.service_revenue_breakdown.length > 0) {
        const circumference = 2 * Math.PI * 32
        let offset = 0
        const slices = s.service_revenue_breakdown.slice(0, 4)
        slices.forEach((svc, i) => {
          const pct = svc.pct
          const dashLen = (pct / 100) * circumference
          const gapLen = circumference - dashLen
          svgContent += `<circle cx="45" cy="45" r="32" fill="none" stroke="${donutColors[i % donutColors.length]}" stroke-width="14"
            stroke-dasharray="${dashLen.toFixed(1)} ${gapLen.toFixed(1)}" stroke-dashoffset="${-offset.toFixed(1)}" transform="rotate(-90 45 45)"/>`
          offset += dashLen
        })
        const topPct = s.service_revenue_breakdown[0]?.pct || 0
        donutSvg.innerHTML = bgCircle + svgContent +
          `<text x="45" y="45" text-anchor="middle" dominant-baseline="central" class="donut-center-text" font-family="'DM Serif Display',serif" font-size="15" fill="${textColor}" font-weight="700">${topPct}%</text>`
      } else {
        donutSvg.innerHTML = bgCircle +
          `<text x="45" y="45" text-anchor="middle" dominant-baseline="central" class="donut-center-text" font-family="'DM Serif Display',serif" font-size="15" fill="${textColor}" font-weight="700">0%</text>`
      }
    }

    if (donutLegend) {
      if (s.service_revenue_breakdown && s.service_revenue_breakdown.length > 0) {
        donutLegend.innerHTML = s.service_revenue_breakdown.map((svc, i) => `
          <div class="donut-legend-item">
            <div class="donut-legend-dot" style="background:${donutColors[i % donutColors.length]};"></div>
            <span class="dl-name">${svc.name}</span> <span class="donut-legend-pct">${svc.pct}%</span>
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
      const pctInt = Math.round(s.meta_pct)
      const badge = metaPanel.querySelector('.panel-badge')
      if (badge) badge.textContent = pctInt + '%'
      const labelEl = metaPanel.querySelector('.meta-progress-label')
      const targetEl = metaPanel.querySelector('.meta-progress-target')
      if (labelEl) labelEl.textContent = 'R$ ' + s.month_revenue.toLocaleString('pt-BR', {minimumFractionDigits: 0}) + ' arrecadado'
      if (targetEl) targetEl.textContent = 'Meta: R$ ' + s.meta_mensal.toLocaleString('pt-BR', {minimumFractionDigits: 0})
      const fill = metaPanel.querySelector('.meta-progress-fill')
      if (fill) fill.style.width = Math.min(pctInt, 100) + '%'
      const note = metaPanel.querySelector('.meta-progress-note')
      if (note) {
        const msgs = {
          100: ['Meta atingida! Parabens!', 'Voce conseguiu! Incrivel!', 'Meta batida! Show!', 'Perfeito! Meta alcancada!', 'Parabens! Voce e demais!'],
          90:  ['Falta pouco! Quase la!', 'Ja esta quase no topo!', 'Mais um esforco e chega!', 'Foco total! Voce esta chegando!', 'A reta final e sua!'],
          75:  ['Passou dos 75%! Continue!', 'Rumo aos 100%! Vamos!', 'Mais 25% e voce chega!', 'A meta esta ao alcance!', 'Nao pare agora! Continue!'],
          50:  ['Metade do caminho! Vai!', 'Voce ja percorreu 50%!', 'Continue assim! Esta no meio!', 'Metade vencida! A meta vem!', 'Ja passou da metade! Rumo ao topo!'],
          25:  ['Primeiros 25%! Bora!', 'Bom comeco! Continue firme!', '25% concluidos! Vai!', 'Ja comecou! Nao pare!', 'O primeiro quarto foi! Continue!'],
          5:   ['Ja comecou! Cada passo conta!', 'Primeiro passo dado! Vamos!', 'Toda jornada comeca assim!', 'O comeco e o mais importante!', 'Foco! Voce ja esta no jogo!'],
          0:   ['Vamos comecar! Tudo e possivel!', 'Primeiro passo rumo a meta!', 'A jornada comeca agora!', 'Pronto para alcancar seus objetivos!', 'Toda grande conquista comeca aqui!'],
        }
        const keys = Object.keys(msgs).map(Number).sort((a, b) => b - a)
        for (const k of keys) {
          if (pctInt >= k) {
            note.textContent = msgs[k][Math.floor(Math.random() * msgs[k].length)]
            break
          }
        }
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
    const now = new Date()
    const monthStart = now.getFullYear() + '-' + String(now.getMonth() + 1).padStart(2, '0') + '-01'
    const lastDay = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate()
    const monthEnd = now.getFullYear() + '-' + String(now.getMonth() + 1).padStart(2, '0') + '-' + String(lastDay).padStart(2, '0')
    const pageSub = document.getElementById('page-sub')
    if (pageSub) pageSub.textContent = _monthNames[now.getMonth()] + ' ' + now.getFullYear()
    const res = await fetch(API + '/transactions/?type=expense&date_from=' + monthStart + '&date_to=' + monthEnd)
    const expenses = await res.json()

    const total = expenses.reduce((s, t) => s + Number(t.amount), 0)
    const count = expenses.length
    const maior = count > 0 ? Math.max(...expenses.map(t => Number(t.amount))) : 0
    const media = count > 0 ? total / count : 0
    const maiorTx = count > 0 ? expenses.find(t => Number(t.amount) === maior) : null

    document.getElementById('desp-total').textContent = 'R$ ' + total.toLocaleString('pt-BR', {minimumFractionDigits: 2})
    document.getElementById('desp-count').textContent = count + ' despesa' + (count !== 1 ? 's' : '')
    document.getElementById('desp-maior').textContent = 'R$ ' + maior.toLocaleString('pt-BR', {minimumFractionDigits: 2})
    document.getElementById('desp-maior-label').textContent = maiorTx?.description || '—'
    document.getElementById('desp-media').textContent = 'R$ ' + media.toLocaleString('pt-BR', {minimumFractionDigits: 2})
    document.getElementById('desp-media-label').textContent = 'média por lançamento'

    // Category breakdown
    const catMap = {}
    expenses.forEach(t => {
      const cat = t.category || 'Outros'
      catMap[cat] = (catMap[cat] || 0) + Number(t.amount)
    })
    const catKeys = Object.keys(catMap)
    const catTotal = Object.values(catMap).reduce((a, b) => a + b, 0)
    const maxCatAmount = Math.max(...Object.values(catMap), 1)

    // Top category
    const topCat = catKeys.length > 0 ? catKeys.reduce((a, b) => catMap[a] > catMap[b] ? a : b) : null
    document.getElementById('desp-top-cat').textContent = topCat || '—'
    document.getElementById('desp-top-cat-val').textContent = topCat ? 'R$ ' + catMap[topCat].toLocaleString('pt-BR', {minimumFractionDigits: 2}) : ''

    const catColors = ['#c05050','#e5825c','#f0b35e','#6fa8dc','#93c47d','#a06fb5','#5a5a5a']
    const catList = document.getElementById('desp-cat-list')
    if (catKeys.length > 0) {
      catList.innerHTML = catKeys.map((cat, i) => {
        const pct = ((catMap[cat] / catTotal) * 100).toFixed(1)
        const barW = Math.round((catMap[cat] / maxCatAmount) * 100)
        return `
          <div class="exp-row">
            <div class="service-dot" style="background:${catColors[i % catColors.length]};"></div>
            <div class="exp-name">${cat}</div>
            <div class="exp-bar-bg"><div class="exp-bar-fill" style="width:${barW}%;background:${catColors[i % catColors.length]};"></div></div>
            <div class="exp-val">R$ ${catMap[cat].toLocaleString('pt-BR', {minimumFractionDigits: 0})}</div>
            <div class="exp-pct" style="font-size:11px;color:#8aaccb;min-width:30px;text-align:right;">${pct}%</div>
          </div>`
      }).join('')
    } else {
      catList.innerHTML = '<div style="padding:20px;text-align:center;color:var(--text-secondary);font-size:13px;">Nenhuma despesa neste mês</div>'
    }

    // Load categories into the transaction modal dropdown
    loadDespesaCatDropdown()

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
            <div class="tx-amount out">−R$ ${Number(t.amount).toLocaleString('pt-BR', {minimumFractionDigits: 2})}</div>
          </div>`
      }).join('')
    } else {
      list.innerHTML = '<div style="padding:20px;text-align:center;color:var(--text-secondary);font-size:13px;">Nenhuma despesa neste mês</div>'
    }
  } catch (e) {
    console.error('Erro ao carregar despesas:', e)
  }
}

async function loadDespesaCatDropdown() {
  try {
    const r = await fetch(API + '/expense-categories')
    const cats = await r.json()
    const txSel = document.getElementById('tx-category')
    if (txSel) {
      txSel.innerHTML = '<option value="">Selecione...</option>'
      cats.forEach(c => {
        txSel.innerHTML += '<option value="' + c.name + '">' + c.name + '</option>'
      })
    }
  } catch (_) {}
}

function openCategoryModal() {
  document.getElementById('cat-name').value = ''
  document.getElementById('cat-msg').textContent = ''
  document.getElementById('category-modal-overlay').classList.add('open')
}

function closeCategoryModal() {
  document.getElementById('category-modal-overlay').classList.remove('open')
}

async function saveCategory() {
  const name = document.getElementById('cat-name').value.trim()
  if (!name) { document.getElementById('cat-msg').textContent = 'Informe o nome da categoria.'; document.getElementById('cat-msg').className = 'auth-msg error'; return }
  try {
    const r = await fetch(API + '/expense-categories', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name })
    })
    if (!r.ok) {
      const err = await r.json()
      document.getElementById('cat-msg').textContent = err.error || 'Erro ao salvar.'
      document.getElementById('cat-msg').className = 'auth-msg error'
      return
    }
    closeCategoryModal()
    showToast('Categoria criada!', 'success')
    loadDespesas()
  } catch (_) {
    document.getElementById('cat-msg').textContent = 'Erro de conexão.'
    document.getElementById('cat-msg').className = 'auth-msg error'
  }
}

let _relPeriod = 30
async function loadRelatorios(period) {
  if (period) _relPeriod = period
  try {
    const res = await fetch(API + '/stats?period=' + _relPeriod)
    const s = await res.json()

    const periodLabel = _relPeriod === 7 ? 'Semana' : _relPeriod === 30 ? 'Mês' : _relPeriod === 90 ? 'Últimos 3 Meses' : 'Esse ano'
    const pageSub = document.getElementById('page-sub')
    if (pageSub) pageSub.textContent = 'Análise - ' + periodLabel
    const sub = document.querySelector('.rpt-trend-sub')
    if (sub) sub.textContent = periodLabel
    const svcSub = document.querySelector('.rpt-services-sub')
    if (svcSub) svcSub.textContent = periodLabel
    const topSub = document.querySelector('.rpt-topclients-sub')
    if (topSub) topSub.textContent = periodLabel + ' · Por cliente (cadastro ativo)'

    const svg = document.getElementById('rpt-trend-svg')
    const daily = s.daily_breakdown || []
    const revs = daily.map(d => d.revenue)
    if (svg && revs.length > 0) {
      const w = 450, h = 130, pad = { t: 8, r: 8, b: 26, l: 36 }
      const innerW = w - pad.l - pad.r
      const innerH = h - pad.t - pad.b
      const maxVal = Math.max(...revs, 1)
      const count = revs.length
      const stepX = count > 1 ? innerW / (count - 1) : innerW / 2
      const pts = revs.map((v, i) => {
        const x = pad.l + (count > 1 ? i * stepX : innerW / 2)
        const y = pad.t + (1 - v / maxVal) * innerH
        return { x, y }
      })

      const isDark = document.documentElement.getAttribute('data-color-scheme') === 'dark' || document.querySelector('.screen')?.getAttribute('data-color-scheme') === 'dark'
      const gridColor = isDark ? 'rgba(255, 255, 255, 0.08)' : '#f0f5fb'
      const labelColor = isDark ? '#718ea8' : '#8aaccb'

      // Y-axis labels
      const yTicks = [0, 0.25, 0.5, 0.75, 1]
      let yHtml = yTicks.map(pct => {
        const yPos = pad.t + (1 - pct) * innerH
        const val = Math.round(maxVal * pct)
        return `<text x="${pad.l - 4}" y="${yPos + 3}" text-anchor="end" font-size="9" fill="${labelColor}">${val}</text>`
      }).join('')

      // Grid lines
      let gridHtml = yTicks.map(pct => {
        const yPos = pad.t + (1 - pct) * innerH
        return `<line x1="${pad.l}" y1="${yPos}" x2="${w - pad.r}" y2="${yPos}" stroke="${gridColor}" stroke-width="1"/>`
      }).join('')

      // X-axis date labels inside SVG
      const dates = daily.map(d => {
        const p = d.date.split('-')
        return parseInt(p[2]) + ' ' + ['jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez'][parseInt(p[1]) - 1]
      })
      let xHtml = ''
      if (dates.length > 0) {
        if (dates.length <= 5) {
          xHtml = dates.map((d, i) => {
            const pct = dates.length > 1 ? i / (dates.length - 1) : 0.5
            const xPos = pad.l + pct * innerW
            return `<text x="${xPos.toFixed(1)}" y="${h - 2}" text-anchor="middle" font-size="9" fill="${labelColor}">${d}</text>`
          }).join('')
        } else {
          const indices = [0, Math.floor(dates.length / 2), dates.length - 1]
          indices.forEach(idx => {
            const pct = idx / (dates.length - 1)
            const xPos = pad.l + pct * innerW
            xHtml += `<text x="${xPos.toFixed(1)}" y="${h - 2}" text-anchor="middle" font-size="9" fill="${labelColor}">${dates[idx]}</text>`
          })
        }
      }

      // Line path
      const chartColor = getComputedStyle(document.documentElement).getPropertyValue('--primary-500').trim() || '#4a90d9'
      const lineD = pts.map((p, i) => (i === 0 ? 'M' : 'L') + p.x.toFixed(1) + ' ' + p.y.toFixed(1)).join(' ')
      const areaD = lineD + ' L' + pts[pts.length - 1].x.toFixed(1) + ' ' + (pad.t + innerH) + ' L' + pad.l + ' ' + (pad.t + innerH) + 'Z'
      const defs = `<defs><linearGradient id="g1" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="${chartColor}"/><stop offset="100%" stop-color="${chartColor}" stop-opacity="0"/></linearGradient></defs>`

      let dotsHtml = pts.map((p, i) => {
        const isLast = i === pts.length - 1
        return `<circle cx="${p.x.toFixed(1)}" cy="${p.y.toFixed(1)}" r="${isLast ? 3.5 : 2.5}" fill="${isLast ? '#fff' : chartColor}" stroke="${chartColor}" stroke-width="${isLast ? 2 : 1.5}"/>`
      }).join('')

      svg.innerHTML = gridHtml + yHtml + xHtml + `
        <path d="${areaD}" fill="url(#g1)" opacity="0.25"/>
        <path d="${lineD}" fill="none" stroke="${chartColor}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
        ${dotsHtml}
        ${defs}`
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
        const isDark = document.documentElement.getAttribute('data-color-scheme') === 'dark' || document.querySelector('.screen')?.getAttribute('data-color-scheme') === 'dark'
        const rankColors = isDark
          ? ['rgba(74, 222, 128, 0.18)', 'rgba(96, 165, 250, 0.18)', 'rgba(244, 114, 182, 0.18)', 'rgba(148, 163, 184, 0.18)', 'rgba(148, 163, 184, 0.12)']
          : ['#f0f8e8', '#f4f8ff', '#f8e8f4', '#f8f8f8', '#f4f7fc']
        const rankTextColors = isDark
          ? ['#4ade80', '#60a5fa', '#f472b6', '#cbd5e1', '#94a3b8']
          : ['#4a8a2e', '#4a6888', '#8a2e6e', '#888', '#8aaccb']
        const rankLabels = ['1°', '2°', '3°', '4°', '5°']
        topDiv.innerHTML = tops.map((c, i) => {
          const lastDate = c.last_visit ? c.last_visit.split('T')[0].split('-').reverse().join('/') : '—'
          return `
            <div class="top-client-row">
              <div class="rank-badge" style="background:${rankColors[i]};color:${rankTextColors[i]};">${rankLabels[i]}</div>
              <div class="client-av" style="width:28px;height:28px;font-size:11px;">${c.avatar_initials || '?'}</div>
              <div style="flex:1;min-width:0;"><div style="font-size:13px;font-weight:500;color:var(--text-dark);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${c.name}</div><div style="font-size:11px;color:var(--text-muted);">${c.visits} visitas · última: ${lastDate}</div></div>
              <div style="font-size:14px;font-weight:600;color:var(--info);flex-shrink:0;">R$ ${Number(c.total_spent).toLocaleString('pt-BR', {minimumFractionDigits: 0})}</div>
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
        const svcColors = ['var(--primary-500)', 'var(--primary-600)', 'var(--primary-400)', 'var(--primary-700)', 'var(--primary-300)']
        svcDiv.innerHTML = svcs.map((v, i) => {
          const pct = (v.count / maxCount) * 100
          return `<div><div style="display:flex;justify-content:space-between;margin-bottom:4px;"><span style="font-size:12px;font-weight:500;color:var(--text-dark);">${v.name}</span><span style="font-size:12px;color:${svcColors[i % svcColors.length]};font-weight:600;">${v.count}x</span></div><div class="meta-progress-bar" style="height:8px;"><div class="meta-progress-fill" style="width:${pct}%;border-radius:4px;height:8px;background:${svcColors[i % svcColors.length]};"></div></div></div>`
        }).join('')
      } else {
        svcDiv.innerHTML = '<div style="padding:10px 0;color:var(--text-secondary);font-size:13px;text-align:center;">Nenhum serviço no período</div>'
      }
    }

    renderHeatmap(s, 'rpt-heatmap')

    updatePeriodBtns()
  } catch (e) {
    console.error('Erro ao carregar relatórios:', e)
  }
}

function _peakHoursFromAppointments(appts) {
  const hours = ['08h','09h','10h','11h','12h','13h','14h','15h','16h','17h']
  const days = ['Seg','Ter','Qua','Qui','Sex','Sáb']
  const hourCounts = {}
  const slotCounts = {}
  hours.forEach(h => { hourCounts[h] = 0 })
  appts.forEach(a => {
    if (!a.appointment_date || a.status === 'cancelled') return
    const d = new Date(a.appointment_date + 'T12:00')
    const dow = d.getDay()
    if (dow === 0) return
    const dayLabel = days[dow - 1]
    const h = parseInt(a.appointment_time?.split(':')[0] || '0', 10)
    if (h < 8 || h > 17) return
    const hourLabel = hours[h - 8]
    hourCounts[hourLabel] = (hourCounts[hourLabel] || 0) + 1
    const slotKey = dayLabel + ' ' + hourLabel
    slotCounts[slotKey] = (slotCounts[slotKey] || 0) + 1
  })
  const topHours = Object.entries(hourCounts)
    .filter(([, c]) => c > 0)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([label, count]) => ({ label, count }))
  const topSlots = Object.entries(slotCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([label, count]) => ({ label, count }))
  return { topHours, topSlots }
}

function renderPeakHoursDashboard(s) {
  const summary = document.getElementById('dashboard-peak-summary')
  const appts = s.month_appointments || []
  const { topHours, topSlots } = _peakHoursFromAppointments(appts)

  if (summary) {
    if (topSlots.length === 0) {
      summary.innerHTML = '<div class="peak-hours-empty">Sem agendamentos no mês para calcular horários de pico.</div>'
    } else {
      summary.innerHTML =
        '<div class="peak-hours-chips">' +
        topSlots.map((slot, i) =>
          '<div class="peak-chip' + (i === 0 ? ' peak-chip-top' : '') + '">' +
            '<span class="peak-chip-rank">' + (i + 1) + 'º</span>' +
            '<span class="peak-chip-label">' + slot.label + '</span>' +
            '<span class="peak-chip-count">' + slot.count + ' agend.</span>' +
          '</div>'
        ).join('') +
        '</div>' +
        (topHours.length > 0
          ? '<div class="peak-hours-note">Horários mais movimentados: ' +
            topHours.map(h => h.label + ' (' + h.count + ')').join(' · ') +
            '</div>'
          : '')
    }
  }

  renderHeatmap(s, 'dashboard-heatmap')
}

function renderHeatmap(s, targetId = 'rpt-heatmap') {
  const heatDiv = document.getElementById(targetId)
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
    const getLevel = (v) => {
      if (v === 0) return 0
      const pct = v / maxVal
      if (pct <= 0.25) return 1
      if (pct <= 0.5) return 2
      if (pct <= 0.75) return 3
      return 4
    }
    let html = '<div class="heatmap-hours"><div class="heatmap-day-label" style="width:24px;"></div>'
    hours.forEach(h => { html += '<div class="heatmap-hour-label">' + h + '</div>' })
    html += '</div>'
    days.forEach(d => {
      html += '<div class="heatmap-row"><div class="heatmap-day-label">' + d + '</div>'
      hours.forEach(h => {
        const v = matrix[d][h] || 0
        const lvl = getLevel(v)
        html += `<div class="hm-cell hm-lvl-${lvl}" title="${d} ${h}: ${v} agendamento(s)"></div>`
      })
      html += '</div>'
    })
    html += '<div class="heatmap-legend"><span>Menos</span><div class="heatmap-legend-bar">'
    ;[0, 1, 2, 3, 4].forEach(lvl => {
      html += `<div class="heatmap-legend-step hm-lvl-${lvl}"></div>`
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

async function exportRelatorioPDF() {
  const btn = document.getElementById('topbar-btn')
  if (btn) { btn.textContent = '⏳ Gerando PDF...'; btn.disabled = true }
  const content = document.getElementById('page-relatorios')
  if (!content) { if (btn) { btn.textContent = '⬇ Exportar PDF'; btn.disabled = false }; return }
  const title = 'Relatorio_BeautyFlow_' + getLocalDateString()

  // ── Fetch data ──────────────────────────────────
  let stats, settings, clients
  try {
    ;[stats, settings] = await Promise.all([
      fetch(API + '/stats?period=' + _relPeriod).then(r => r.json()),
      fetch(API + '/settings/').then(r => r.json())
    ])
    const clRes = await fetch(API + '/clients/')
    clients = await clRes.json()
  } catch (e) {
    showToast('Erro ao carregar dados para o PDF.', 'error')
    if (btn) { btn.textContent = '⬇ Exportar PDF'; btn.disabled = false }
    return
  }

  // ── Company info from settings ──────────────────
  const company = {
    legalName: settings.company_legal_name || 'Nome da Empresa Ltda',
    tradeName: settings.company_trade_name || 'Nome Fantasia',
    cnpj: settings.company_cnpj || '00.000.000/0001-00',
    municipalReg: settings.company_municipal_reg || '000.000',
    address: settings.company_address || 'Endereço, nº 000 - Bairro, Cidade - UF',
    phone: settings.company_phone || '(11) 0000-0000',
    email: settings.company_email || 'contato@empresa.com.br',
  }

  // ── CPF map: client_id → masked CPF ────────────
  const cpfMap = {}
  ;(clients || []).forEach(c => {
    if (c.cpf) {
      const raw = c.cpf.replace(/\D/g, '')
      cpfMap[c.id] = raw.length === 11
        ? '***.' + raw.slice(3, 6) + '.***.**'
        : c.cpf
    } else {
      cpfMap[c.id] = '—'
    }
  })

  // ── Period ──────────────────────────────────────
  const periodDays = _relPeriod || 30
  const periodEnd = new Date()
  const periodStart = new Date()
  periodStart.setDate(periodStart.getDate() - periodDays)
  const fmtPeriod = (d) => d.toLocaleDateString('pt-BR')
  const fmtDateTime = (d) => d.toLocaleString('pt-BR')

  // ── KPI calculations ────────────────────────────
  const grossRevenue = stats.month_revenue || 0
  const totalAppts = stats.month_appointments_count || 0
  const uniqueClients = stats.month_clients || 0
  const avgTicket = uniqueClients > 0 ? grossRevenue / uniqueClients : 0

  // ── Top clients (with CPF) ──────────────────────
  const topClients = (stats.top_clients || []).slice(0, 10)

  // ── Service breakdown ───────────────────────────
  const svcBreakdown = stats.service_breakdown || []
  const svcRevenue = stats.service_revenue_breakdown || []
  const svcRevenueMap = {}
  svcRevenue.forEach(s => { svcRevenueMap[s.name] = s.revenue })
  const totalSvcRevenue = svcRevenue.reduce((a, b) => a + b.revenue, 0)

  // Merge service data
  const mergedServices = svcBreakdown.map(s => {
    const rev = svcRevenueMap[s.name] || 0
    return {
      name: s.name,
      count: s.count,
      unitPrice: s.count > 0 ? rev / s.count : 0,
      revenue: rev,
      pct: totalSvcRevenue > 0 ? (rev / totalSvcRevenue) * 100 : 0
    }
  })

  // ── Build PDF HTML ─────────────────────────────
  const printWin = window.open('', '_blank')
  if (!printWin) {
    showToast('Permita pop-ups para exportar PDF.', 'info')
    if (btn) { btn.textContent = '⬇ Exportar PDF'; btn.disabled = false }
    return
  }

  printWin.document.write('<!DOCTYPE html><html><head><meta charset="utf-8"><title>' + title + '</title>')
  printWin.document.write(`
<style>
  @page { margin: 20mm 15mm 25mm; }
  @media print {
    body { font-family: 'Helvetica', 'Arial', sans-serif; font-size: 10pt; color: #1a1a2e; line-height: 1.5; }
    .no-break { page-break-inside: avoid; }
  }
  body { font-family: 'Helvetica', 'Arial', sans-serif; padding: 0; margin: 0; color: #1a1a2e; font-size: 10pt; line-height: 1.5; }
  .page { padding: 20px 30px; }
  .header-separator { border: none; border-top: 3px solid #1a3a6b; margin: 10px 0 18px; }

  /* ── Cabeçalho Corporativo ── */
  .corp-header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 6px; }
  .corp-left h1 { font-size: 16pt; color: #1a3a6b; margin: 0 0 2px; font-weight: 700; }
  .corp-left h2 { font-size: 11pt; color: #4a6a8b; margin: 0 0 8px; font-weight: 400; }
  .corp-left .info { font-size: 7.5pt; color: #6a7a8b; line-height: 1.6; }
  .corp-right { text-align: right; font-size: 7.5pt; color: #4a6a8b; }
  .corp-right strong { color: #1a3a6b; }
  .doc-title { font-size: 13pt; color: #1a3a6b; font-weight: 700; text-align: center; margin: 16px 0 4px; }
  .doc-period { font-size: 8pt; color: #6a7a8b; text-align: center; margin-bottom: 16px; }

  /* ── KPIs ── */
  .kpi-grid { display: flex; gap: 12px; margin: 14px 0; flex-wrap: wrap; }
  .kpi-card { flex: 1; min-width: 120px; background: #f4f7fc; border: 1px solid #d8e4f0; border-radius: 6px; padding: 12px 14px; text-align: center; }
  .kpi-label { font-size: 7pt; color: #6a7a8b; text-transform: uppercase; letter-spacing: 0.3px; }
  .kpi-value { font-size: 14pt; color: #1a3a6b; font-weight: 700; margin-top: 2px; }
  .kpi-sub { font-size: 6.5pt; color: #8a9aab; margin-top: 2px; }

  /* ── Tabelas ── */
  table { width: 100%; border-collapse: collapse; margin: 8px 0 16px; }
  th { background: #1a3a6b; color: #fff; font-size: 7.5pt; font-weight: 600; padding: 7px 10px; text-align: left; text-transform: uppercase; letter-spacing: 0.3px; }
  td { padding: 6px 10px; border-bottom: 1px solid #e0e6ee; font-size: 8pt; }
  tr:nth-child(even) td { background: #f8fafc; }
  tr:last-child td { border-bottom: 1px solid #c8d4e0; }
  .num { text-align: right; font-variant-numeric: tabular-nums; }
  .pct { text-align: right; color: #4a7a5a; }

  /* ── Rodapé ── */
  .footer { margin-top: 28px; border-top: 1px solid #c8d4e0; padding-top: 10px; text-align: center; }
  .footer-legal { font-size: 6.5pt; color: #8a9aab; line-height: 1.6; }
  .footer-page { font-size: 7pt; color: #6a7a8b; margin-top: 6px; }
  .section-title { font-size: 10pt; color: #1a3a6b; font-weight: 700; margin: 18px 0 6px; padding-bottom: 4px; border-bottom: 2px solid #d8e4f0; }
</style>
</head><body>
<div class="page">

  <!-- ═══════════ CABEÇALHO CORPORATIVO ═══════════ -->
  <div class="corp-header">
    <div class="corp-left">
      <h1>` + company.tradeName + `</h1>
      <h2>` + company.legalName + `</h2>
      <div class="info">
        CNPJ: ` + company.cnpj + ` · Insc. Municipal: ` + company.municipalReg + `<br>
        ` + company.address + `<br>
        E-mail: ` + company.email + ` · Tel: ` + company.phone + `
      </div>
    </div>
    <div class="corp-right">
      <strong>Emissão:</strong><br>` + fmtDateTime(new Date()) + `
    </div>
  </div>
  <hr class="header-separator">

  <div class="doc-title">Relatório Gerencial de Faturamento</div>
  <div class="doc-period">Período de apuração: ` + fmtPeriod(periodStart) + ` a ` + fmtPeriod(periodEnd) + `</div>

  <!-- ═══════════ MÉTRICAS (KPIs) ═══════════ -->
  <div class="kpi-grid no-break">
    <div class="kpi-card">
      <div class="kpi-label">Faturamento Bruto</div>
      <div class="kpi-value">R$ ` + grossRevenue.toLocaleString('pt-BR', {minimumFractionDigits: 2}) + `</div>
      <div class="kpi-sub">Período apurado</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-label">Ticket Médio</div>
      <div class="kpi-value">R$ ` + avgTicket.toLocaleString('pt-BR', {minimumFractionDigits: 2}) + `</div>
      <div class="kpi-sub">Por cliente único</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-label">Atendimentos</div>
      <div class="kpi-value">` + totalAppts + `</div>
      <div class="kpi-sub">Serviços realizados</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-label">Clientes Únicos</div>
      <div class="kpi-value">` + uniqueClients + `</div>
      <div class="kpi-sub">Atendidos no período</div>
    </div>
  </div>

  <!-- ═══════════ TOP CLIENTES ═══════════ -->
  <div class="section-title no-break">Top Clientes</div>
  <table class="no-break">
    <thead>
      <tr><th style="width:36px;">#</th><th>Nome Completo</th><th>CPF</th><th style="width:70px;" class="num">Visitas</th><th style="width:110px;" class="num">Total Pago (R$)</th></tr>
    </thead>
    <tbody>
` + (topClients.length > 0
      ? topClients.map((c, i) => {
          const cpf = cpfMap[c.id] || '—'
          return '<tr><td>' + (i + 1) + '°</td><td>' + (c.name || '—') + '</td><td>' + cpf + '</td><td class="num">' + (c.visits || 0) + '</td><td class="num">R$ ' + (c.total_spent || 0).toLocaleString('pt-BR', {minimumFractionDigits: 2}) + '</td></tr>'
        }).join('')
      : '<tr><td colspan="5" style="text-align:center;color:#8a9aab;">Nenhum cliente no período</td></tr>'
) + `
    </tbody>
  </table>

  <!-- ═══════════ SERVIÇOS MAIS POPULARES ═══════════ -->
  <div class="section-title no-break">Serviços Mais Populares</div>
  <table class="no-break">
    <thead>
      <tr><th>Serviço</th><th style="width:60px;" class="num">Qtd</th><th style="width:90px;" class="num">Preço Unit. Médio (R$)</th><th style="width:100px;" class="num">Faturamento (R$)</th><th style="width:60px;" class="num">%</th></tr>
    </thead>
    <tbody>
` + (mergedServices.length > 0
      ? mergedServices.map(s => {
          return '<tr><td>' + s.name + '</td><td class="num">' + s.count + '</td><td class="num">R$ ' + s.unitPrice.toLocaleString('pt-BR', {minimumFractionDigits: 2}) + '</td><td class="num">R$ ' + s.revenue.toLocaleString('pt-BR', {minimumFractionDigits: 2}) + '</td><td class="num pct">' + s.pct.toFixed(1) + '%</td></tr>'
        }).join('')
      : '<tr><td colspan="5" style="text-align:center;color:#8a9aab;">Nenhum serviço no período</td></tr>'
) + `
    </tbody>
  </table>

  <!-- ═══════════ RODAPÉ ═══════════ -->
  <div class="footer">
    <div class="footer-legal">
      Este documento é um relatório gerencial interno extraído do sistema BeautyFlow CRM e não substitui a emissão de<br>
      Nota Fiscal de Serviços Eletrônica (NFS-e), conforme legislação vigente.
    </div>
    <div class="footer-page" id="pdf-page">Página <span class="page-num"></span></div>
  </div>

</div>
<script>
  var pageNum = 1
  document.querySelector('.page-num').textContent = pageNum
</script>
</body></html>`)

  printWin.document.close()
  printWin.focus()
  setTimeout(() => {
    printWin.print()
    if (btn) { btn.textContent = '⬇ Exportar PDF'; btn.disabled = false }
  }, 600)
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

async function loadAgenda(reset = false) {
  if (reset || !agendaDate) {
    agendaDate = new Date()
    agendaView = 'week'
  }
  syncAgendaViewTabs()
  showAgendaView()
}

function refreshAgenda() {
  const currentPageId = location.hash.slice(1) || 'dashboard'
  if (currentPageId === 'agenda') {
    showAgendaView()
  }
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

  document.getElementById('appt-date').value = date || getLocalDateString()
  document.getElementById('appt-time').value = time || '09:00'
  document.getElementById('appt-status').value = 'pending'
  document.getElementById('appt-payment-status').value = 'unpaid'
  document.getElementById('appt-price').value = ''
  document.getElementById('appt-notes').value = ''

  await populateClientSelect()
  await populateServiceSelect()

  document.getElementById('appt-client').value = ''
  document.getElementById('appt-service').value = ''

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
  const paymentStatus = document.getElementById('appt-payment-status').value
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

  const body = { client_id: Number(clientId), service, appointment_date: date, appointment_time: time, status, payment_status: paymentStatus, price: Number(price), notes, duration }

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
    showAgendaView()
    loadDashboard()
    loadFinanceiro()
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
    const statusColors = { pending: 'var(--warning, #c9894a)', confirmed: 'var(--primary-500)', done: 'var(--success, #4e8f6a)', cancelled: 'var(--danger, #c05050)' }
    const statusEl = document.getElementById('detail-status')
    statusEl.innerHTML = '<span style="display:inline-block;width:10px;height:10px;border-radius:50%;background:' +
      (statusColors[a.status] || '#999') + ';margin-right:6px;vertical-align:middle;"></span>' +
      (statusLabels[a.status] || a.status)

    const paymentLabels = { paid: 'Pago', unpaid: 'Não Pago' }
    const paymentColors = { paid: '#4e8f6a', unpaid: '#a03030' }
    const paymentEl = document.getElementById('detail-payment-status')
    const ps = a.payment_status || 'unpaid'
    paymentEl.innerHTML = '<span style="display:inline-block;width:10px;height:10px;border-radius:50%;background:' +
      (paymentColors[ps] || '#999') + ';margin-right:6px;vertical-align:middle;"></span>' +
      (paymentLabels[ps] || ps)

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
    showAgendaView()
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
    showAgendaView()
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
    document.getElementById('appt-payment-status').value = a.payment_status || 'unpaid'
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
  document.getElementById('client-cpf').value = ''
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
  const cpf = document.getElementById('client-cpf').value.trim()
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
        body: JSON.stringify({ name, phone, cpf, email, status, notes })
      })
    } else {
      res = await fetch(API + '/clients/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, phone, cpf, email, status, notes })
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
  document.getElementById('service-buffer').value = '15'
  document.getElementById('service-price').value = ''
  document.getElementById('service-color').value = getComputedStyle(document.documentElement).getPropertyValue('--primary-500').trim() || '#4a90d9'

  if (svcId) {
    const svc = servicesCache.find(s => s.id === svcId)
    if (svc) {
      idField.value = svc.id
      title.textContent = 'Editar Serviço'
      saveBtn.textContent = 'Salvar Alterações'
      document.getElementById('service-name').value = svc.name
      document.getElementById('service-duration').value = svc.duration
      document.getElementById('service-buffer').value = svc.buffer !== undefined ? svc.buffer : 15
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
  const buffer = document.getElementById('service-buffer')?.value || 15
  const price = document.getElementById('service-price').value
  const color = document.getElementById('service-color').value
  const idField = document.getElementById('service-id')

  if (!name || name.length < 2) { showToast('Informe o nome do serviço.'); return }
  if (!duration || Number(duration) < 1) { showToast('Informe a duração do serviço.'); return }
  if (price === '' || Number(price) < 0) { showToast('Informe o preço do serviço.'); return }

  const body = { name, duration: Number(duration), buffer: Number(buffer), price: Number(price), color }

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
  const search = (document.getElementById('client-search')?.value || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
  let filtered = filter === 'all' ? clientsCache : clientsCache.filter(c => c.status === filter)
  if (search) {
    const phoneSearch = search.replace(/\D/g, '')
    filtered = filtered.filter(c => {
      const name = (c.name || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
      const phone = (c.phone || '').replace(/\D/g, '')
      return name.includes(search) || (phoneSearch && phone.includes(phoneSearch))
    })
  }
  renderClientList(filtered)
}

// ── TRANSACTION MODAL ────────────────────────────────

function openTransactionModal(type) {
  const overlay = document.getElementById('transaction-modal-overlay')
  const title = document.getElementById('tx-modal-title')
  const saveBtn = document.getElementById('tx-save-btn')
  const idField = document.getElementById('tx-id')
  idField.value = ''
  title.textContent = type === 'expense' ? 'Nova Despesa' : 'Novo Lançamento'
  saveBtn.textContent = type === 'expense' ? 'Salvar Despesa' : 'Salvar Lançamento'
  document.getElementById('tx-type').value = type || 'income'
  document.getElementById('tx-amount').value = ''
  document.getElementById('tx-description').value = ''
  document.getElementById('tx-date').value = getLocalDateString()
  loadDespesaCatDropdown()
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
    const savedType = body.type
    showToast(savedType === 'expense' ? 'Despesa salva!' : 'Lançamento salvo!', 'success')
    loadFinanceiro()
    loadDashboard()
    if (savedType === 'expense') loadDespesas()
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

async function toggleCaloteiro() {
  if (!selectedClientId) { showToast('Selecione um cliente primeiro.'); return }
  try {
    const res = await fetch(API + '/clients/' + selectedClientId)
    const c = await res.json()
    const newStatus = c.status === 'inadimplente' ? 'regular' : 'inadimplente'
    const upd = await fetch(API + '/clients/' + selectedClientId, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: newStatus })
    })
    if (!upd.ok) { showToast('Erro ao atualizar status.'); return }
    loadClients()
  } catch (e) {
    showToast('Erro ao atualizar status.')
  }
}

// ── NOTIFICAÇÕES ────────────────────────────────────

document.querySelectorAll('.hour-toggle').forEach(t => {
  t.addEventListener('click', () => {
    t.classList.toggle('on')
    t.classList.toggle('off')
  })
})

async function loadNotificacoes() {
  try {
    const res = await fetch(API + '/settings/')
    const settings = await res.json()
    const toggles = document.querySelectorAll('#tab-notif .hour-toggle')
    toggles.forEach(t => {
      const titleEl = t.closest('.toggle-row')?.querySelector('.toggle-title')
      if (!titleEl) return
      const key = 'notify_' + titleEl.textContent.trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/\s+/g, '_')
      const val = settings[key]
      if (val !== undefined) {
        t.classList.toggle('on', val === 'true')
        t.classList.toggle('off', val !== 'true')
      }
    })
  } catch (e) {
    console.error('Erro ao carregar notificações:', e)
  }
}

async function saveNotificacoes() {
  const toggles = document.querySelectorAll('#tab-notif .hour-toggle')
  const data = {}
  toggles.forEach(t => {
    const titleEl = t.closest('.toggle-row')?.querySelector('.toggle-title')
    if (!titleEl) return
    const key = 'notify_' + titleEl.textContent.trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/\s+/g, '_')
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

// ── EMPRESA (company info) ─────────────────────────

function loadCompanyInfo() {
  const tab = document.getElementById('tab-empresa')
  if (!tab || tab.style.display === 'none') return
  fetchSettings()
}

async function fetchSettings() {
  try {
    const res = await fetch(API + '/settings/')
    const s = await res.json()
    const map = {
      'company-legal-name': 'company_legal_name',
      'company-trade-name': 'company_trade_name',
      'company-cnpj': 'company_cnpj',
      'company-municipal-reg': 'company_municipal_reg',
      'company-address': 'company_address',
      'company-phone': 'company_phone',
      'company-email': 'company_email',
    }
    Object.entries(map).forEach(([id, key]) => {
      const el = document.getElementById(id)
      if (el) el.value = s[key] || ''
    })
  } catch {}
}

async function saveCompanyInfo() {
  const data = {
    company_legal_name: document.getElementById('company-legal-name')?.value || '',
    company_trade_name: document.getElementById('company-trade-name')?.value || '',
    company_cnpj: document.getElementById('company-cnpj')?.value || '',
    company_municipal_reg: document.getElementById('company-municipal-reg')?.value || '',
    company_address: document.getElementById('company-address')?.value || '',
    company_phone: document.getElementById('company-phone')?.value || '',
    company_email: document.getElementById('company-email')?.value || '',
  }
  try {
    const res = await fetch(API + '/settings/', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    })
    if (!res.ok) { showToast('Erro ao salvar dados da empresa.'); return }
    showToast('Dados da empresa salvos!', 'success')
  } catch {
    showToast('Erro ao salvar dados da empresa.')
  }
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
  if (notifPanelOpen && panel && bell && !panel.contains(e.target) && !bell.contains(e.target)) {
    notifPanelOpen = false
    panel.style.display = 'none'
  }
})

// ── EVENT LISTENERS ────────────────────────────────

document.getElementById('client-search')?.addEventListener('input', () => {
  const activeTab = document.querySelector('.filter-tab.active')
  const filter = activeTab?.getAttribute('data-filter') || 'all'
  filterClients(filter)
})

document.querySelectorAll('.filter-tab').forEach(t => {
  t.addEventListener('click', () => {
    document.querySelectorAll('.filter-tab').forEach(x => x.classList.remove('active'))
    t.classList.add('active')
    const filter = t.getAttribute('data-filter') || 'all'
    filterClients(filter)
  })
})
// ── AGENDA VIEW STATE ─────────────────────────────

const _dayNames = ['Domingo','Segunda-feira','Terça-feira','Quarta-feira','Quinta-feira','Sexta-feira','Sábado']
const _dayShort = ['Dom','Seg','Ter','Qua','Qui','Sex','Sáb']
const _monthNames = ['Janeiro','Fevereiro','Março','Abril','Maio','Junho','Julho','Agosto','Setembro','Outubro','Novembro','Dezembro']

let agendaView = 'week'
let agendaDate = new Date()

const DAYS_PT = ['domingo','segunda','terca','quarta','quinta','sexta','sabado']
const DEFAULT_HOURS = { open: '08:00', close: '18:00', closed: false }

function syncAgendaViewTabs() {
  const views = ['day', 'week', 'month', 'year']
  const tabs = document.querySelectorAll('#agenda-view-tabs .view-tab')
  tabs.forEach((t, i) => {
    t.classList.toggle('active', views[i] === agendaView)
  })
}

function setAgendaView(view, el) {
  agendaView = view
  syncAgendaViewTabs()
  showAgendaView()
}

function agendaNavPrev() {
  switch (agendaView) {
    case 'day':
      agendaDate.setDate(agendaDate.getDate() - 1)
      break
    case 'week':
      agendaDate.setDate(agendaDate.getDate() - 7)
      break
    case 'month': {
      const curYear = agendaDate.getFullYear()
      const curMonth = agendaDate.getMonth()
      agendaDate = new Date(curYear, curMonth - 1, 1, 12, 0, 0)
      break
    }
    case 'year': {
      agendaDate = new Date(agendaDate.getFullYear() - 1, 0, 1, 12, 0, 0)
      break
    }
  }
  showAgendaView()
}

function agendaNavNext() {
  switch (agendaView) {
    case 'day':
      agendaDate.setDate(agendaDate.getDate() + 1)
      break
    case 'week':
      agendaDate.setDate(agendaDate.getDate() + 7)
      break
    case 'month': {
      const curYear = agendaDate.getFullYear()
      const curMonth = agendaDate.getMonth()
      agendaDate = new Date(curYear, curMonth + 1, 1, 12, 0, 0)
      break
    }
    case 'year': {
      agendaDate = new Date(agendaDate.getFullYear() + 1, 0, 1, 12, 0, 0)
      break
    }
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
  syncAgendaViewTabs()
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

// ── RENDER DAY VIEW (horizontal list) ─────────────

async function renderDayView() {
  syncAgendaViewTabs()
  const dayStr = _fmt(agendaDate)
  updateSub(_dayNames[agendaDate.getDay()] + ', ' + agendaDate.getDate() + ' de ' + _monthNames[agendaDate.getMonth()] + ' de ' + agendaDate.getFullYear())

  const appts = await fetchAppts(dayStr, dayStr)

  let hoursMap = {}
  try {
    const r = await fetch(API + '/business-hours')
    hoursMap = await r.json()
  } catch (_) {}
  const dow = agendaDate.getDay()
  const dk = DAYS_PT[dow]
  const h = hoursMap[dk] || DEFAULT_HOURS
  const isClosed = !!h.closed

  const sc = { done: 'done', confirmed: 'confirmed', pending: 'pending', cancelled: 'cancelled' }
  const statusLabels = { done: 'Concluído', confirmed: 'Confirmado', pending: 'Pendente', cancelled: 'Cancelado' }
  const statusColors = { done: 'var(--success, #4e8f6a)', confirmed: 'var(--primary-500)', pending: 'var(--warning, #c9894a)', cancelled: 'var(--danger, #c05050)' }

  let html = '<div class="day-view-panel">'
  if (appts.length > 0) {
    appts.sort((a, b) => (a.appointment_time || '').localeCompare(b.appointment_time || ''))
    appts.forEach(a => {
      const cls = sc[a.status] || 'pending'
      const color = statusColors[a.status] || '#999'
      const payCls = a.payment_status === 'paid' ? 'status-paid' : 'status-unpaid'
      const payLabel = a.payment_status === 'paid' ? 'Pago' : 'Não Pago'
      html += '<div class="day-view-card" onclick="openAppointmentDetail(' + a.id + ')">'
      html += '<div class="dvc-time">' + (a.appointment_time || '—') + '</div>'
      html += '<div class="dvc-dot" style="background:' + color + '"></div>'
      html += '<div class="dvc-body">'
      html += '<div class="dvc-name">' + (a.client_name || 'Cliente') + '</div>'
      html += '<div class="dvc-service">' + (a.service || 'Serviço') + '</div>'
      html += '</div>'
      html += '<div class="dvc-price">R$ ' + Number(a.price || 0).toFixed(2) + '</div>'
      html += '<span class="appt-status status-' + cls + '">' + (statusLabels[a.status] || a.status) + '</span>'
      html += '<span class="appt-status ' + payCls + '" style="margin-left:4px;">' + payLabel + '</span>'
      html += '</div>'
    })
  } else if (isClosed) {
    html += '<div class="day-view-empty"><div class="day-view-off">Folga</div><div class="day-view-off-sub">Estabelecimento fechado neste dia</div><button class="btn-primary" style="margin-top:14px;" onclick="openAppointmentModal(\'' + dayStr + '\')">+ Agendar Mesmo Assim</button></div>'
  } else {
    html += '<div class="day-view-empty"><div>Nenhum agendamento neste dia</div><button class="btn-primary" style="margin-top:14px;" onclick="openAppointmentModal(\'' + dayStr + '\')">+ Novo Agendamento</button></div>'
  }
  html += '</div>'

  document.getElementById('agenda-day-view').innerHTML = html
  document.getElementById('agenda-day-view').style.display = ''
  document.getElementById('agenda-summary').textContent = appts.length + ' atendimento' + (appts.length !== 1 ? 's' : '') + ' neste dia'
}

// ── POPULATE WEEK GRID ────────────────────────────

async function populateWeekGrid(numDays) {
  syncAgendaViewTabs()
  const weekStart = new Date(agendaDate)
  weekStart.setHours(12, 0, 0, 0)
  if (numDays === 7) {
    weekStart.setDate(agendaDate.getDate() - agendaDate.getDay())
  }
  const weekEnd = new Date(weekStart)
  weekEnd.setDate(weekStart.getDate() + numDays - 1)

  const isDayView = numDays === 1
  if (isDayView) {
    updateSub(_dayNames[agendaDate.getDay()] + ', ' + agendaDate.getDate() + ' de ' + _monthNames[agendaDate.getMonth()] + ' de ' + agendaDate.getFullYear())
  } else {
    updateSub(_fmtBR(weekStart) + ' – ' + _fmtBR(weekEnd) + ' ' + weekEnd.getFullYear())
  }

  const weekGrid = document.getElementById('agenda-week-grid')
  weekGrid.classList.toggle('day-view', isDayView)

  const appts = await fetchAppts(_fmt(weekStart), _fmt(weekEnd))
  if (!servicesCache.length) await loadServices()
  const todayStr = _fmt(new Date())

  // Load business hours
  let hoursMap = {}
  try {
    const r = await fetch(API + '/business-hours')
    hoursMap = await r.json()
  } catch (_) {}

  // Safe time parser helper
  function parseTime(str, def) {
    if (!str || typeof str !== 'string' || !str.includes(':')) return def
    const parts = str.split(':')
    const h = parseInt(parts[0], 10)
    const m = parseInt(parts[1], 10)
    return (!isNaN(h) && !isNaN(m)) ? h * 60 + m : def
  }

  // Find global min/max across visible days
  let globalOpen = 8 * 60, globalClose = 18 * 60
  for (let i = 0; i < numDays; i++) {
    const day = new Date(weekStart)
    day.setDate(weekStart.getDate() + i)
    const dow = day.getDay()
    const dk = DAYS_PT[dow]
    const h = hoursMap[dk] || DEFAULT_HOURS
    if (!h.closed) {
      const o = parseTime(h.open, 8 * 60)
      const c = parseTime(h.close, 18 * 60)
      if (o < globalOpen) globalOpen = o
      if (c > globalClose) globalClose = c
    }
  }

  // Expand globalOpen/globalClose if any appointment falls outside
  appts.forEach(a => {
    if (!a.appointment_time) return
    const start = parseTime(a.appointment_time, -1)
    if (start >= 0) {
      const dur = Math.max(15, Number(a.duration || 60))
      const end = start + dur
      if (start < globalOpen) globalOpen = Math.floor(start / 60) * 60
      if (end > globalClose) globalClose = Math.ceil(end / 60) * 60
    }
  })

  const hourStep = 60
  const numSlots = Math.max(1, Math.round((globalClose - globalOpen) / hourStep))

  // Calculate slot height to fill available viewport space
  function calcSlotHeight() {
    const topbarEl = document.querySelector('.topbar')
    const toolbarEl = document.querySelector('.agenda-toolbar')
    const legendEl = document.querySelector('.agenda-legend')
    if (!topbarEl || !toolbarEl || !legendEl) return 52
    const topbarH = topbarEl.offsetHeight
    const toolbarH = toolbarEl.offsetHeight
    const legendH = legendEl.offsetHeight + 4
    const contentPad = 48
    const pageGap = 20
    const borderH = 2
    const headerH = 44
    const available = window.innerHeight - topbarH - contentPad - pageGap - toolbarH - legendH - borderH - headerH
    const perSlot = Math.floor(available / numSlots)
    return Math.max(32, perSlot)
  }
  const slotHeight = calcSlotHeight()

  let timeHtml = '<div class="time-col-header"></div>'
  for (let t = globalOpen; t < globalClose; t += hourStep) {
    const hh = Math.floor(t / 60)
    const mm = t % 60
    const label = mm === 0 ? hh + 'h' : hh + ':' + String(mm).padStart(2, '0')
    timeHtml += '<div class="time-slot-label" style="height:' + slotHeight + 'px;">' + label + '</div>'
  }
  document.getElementById('agenda-time-col').innerHTML = timeHtml

  let dayHtml = ''
  for (let i = 0; i < numDays; i++) {
    const day = new Date(weekStart)
    day.setDate(weekStart.getDate() + i)
    const dayStr = _fmt(day)
    const isToday = dayStr === todayStr
    const dow = day.getDay()
    const dayKey = DAYS_PT[dow]
    const dayInfo = hoursMap[dayKey] || DEFAULT_HOURS
    const isClosed = !!dayInfo.closed
    const dayOpenMin = isClosed ? 0 : parseTime(dayInfo.open, 8 * 60)
    const dayCloseMin = isClosed ? 0 : parseTime(dayInfo.close, 18 * 60)

    dayHtml += '<div class="day-col" style="' + (isDayView ? 'flex:1;' : '') + '">'
    dayHtml += '<div class="day-header"><div class="day-name">' + _dayShort[dow] + '</div><div class="day-num' + (isToday ? ' today' : '') + '">' + day.getDate() + '</div></div>'
    dayHtml += '<div class="day-slots" style="height:' + (numSlots * slotHeight) + 'px;position:relative;">'

    if (isClosed) {
      for (let t = globalOpen; t < globalClose; t += hourStep) {
        dayHtml += '<div class="hour-line closed-slot" style="height:' + slotHeight + 'px;"></div>'
      }
      dayHtml += '<div class="folga-overlay"></div><div class="folga-label">Folga</div>'
    } else {
      for (let t = globalOpen; t < dayOpenMin; t += hourStep) {
        dayHtml += '<div class="hour-line closed-slot" style="height:' + slotHeight + 'px;"></div>'
      }
      for (let t = dayOpenMin; t < dayCloseMin; t += hourStep) {
        const hh = Math.floor(t / 60)
        const mm = t % 60
        dayHtml += '<div class="hour-line" style="height:' + slotHeight + 'px;" data-date="' + dayStr + '" data-hour="' + String(hh).padStart(2,'0') + ':' + String(mm).padStart(2,'0') + '"></div>'
      }
      for (let t = dayCloseMin; t < globalClose; t += hourStep) {
        dayHtml += '<div class="hour-line closed-slot" style="height:' + slotHeight + 'px;"></div>'
      }
    }

    const dayAppts = appts.filter(a => a.appointment_date === dayStr)
    if (dayAppts.length > 0) {
      const sortedAppts = [...dayAppts].sort((x, y) => {
        const tx = (x.appointment_time || '00:00').localeCompare(y.appointment_time || '00:00')
        return tx !== 0 ? tx : (Number(y.duration || 60) - Number(x.duration || 60))
      })

      const parsedEvents = sortedAppts.map(a => {
        const start = parseTime(a.appointment_time, globalOpen)
        const dur = Math.max(15, Number(a.duration || 60))
        return { appt: a, start, end: start + dur }
      })

      const columns = []
      parsedEvents.forEach(ev => {
        let placed = false
        for (let c = 0; c < columns.length; c++) {
          const lastInCol = columns[c][columns[c].length - 1]
          if (ev.start >= lastInCol.end) {
            columns[c].push(ev)
            ev.col = c
            placed = true
            break
          }
        }
        if (!placed) {
          ev.col = columns.length
          columns.push([ev])
        }
      })

      parsedEvents.forEach(ev => {
        const overlapping = parsedEvents.filter(other => ev.start < other.end && ev.end > other.start)
        ev.totalCols = Math.max(...overlapping.map(o => o.col + 1), 1)
      })

      const sc = { done: 'done', confirmed: 'confirmed', pending: 'pending', cancelled: 'cancelled' }
      parsedEvents.forEach(ev => {
        const a = ev.appt
        const top = Math.max(0, ((ev.start - globalOpen) / hourStep) * slotHeight)
        const height = Math.max(slotHeight - 2, ((ev.end - ev.start) / hourStep) * slotHeight - 2)
        const widthPct = (100 / ev.totalCols)
        const leftPct = (ev.col * widthPct)
        const payMark = a.payment_status === 'paid' ? '✓' : '✗'
        const svcInfo = servicesCache.find(s => s.name === a.service)
        const svcColor = svcInfo?.color ? 'border-left-color:' + svcInfo.color + ';' : ''

        dayHtml += '<div class="cal-event ' + (sc[a.status] || 'pending') + ' ' + (a.payment_status === 'paid' ? 'pay-paid' : 'pay-unpaid') + '" style="top:' + top + 'px;height:' + height + 'px;left:calc(' + leftPct + '% + 2px);width:calc(' + widthPct + '% - 4px);' + svcColor + 'cursor:pointer;" data-id="' + a.id + '">'
        dayHtml += '<div class="ev-name">' + (a.client_name || 'Cliente') + '<span class="ev-pay-mark">' + payMark + '</span></div><div class="ev-svc">' + (a.service || '') + '</div></div>'
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
  syncAgendaViewTabs()
  const year = agendaDate.getFullYear()
  const month = agendaDate.getMonth()
  updateSub(_monthNames[month] + ' ' + year)

  const firstDay = new Date(year, month, 1, 12, 0, 0)
  const lastDay = new Date(year, month + 1, 0, 12, 0, 0)
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
    const ds = _fmt(new Date(year, month, d, 12, 0, 0))
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
      syncAgendaViewTabs()
      showAgendaView()
    })
  })

  document.getElementById('agenda-summary').textContent = appts.length + ' atendimento' + (appts.length !== 1 ? 's' : '') + ' no mês'
}

// ── RENDER YEAR VIEW ──────────────────────────────

async function renderYearView() {
  syncAgendaViewTabs()
  const year = agendaDate.getFullYear()
  updateSub('' + year)

  const firstOfYear = `${year}-01-01`
  const lastOfYear = `${year}-12-31`
  const allAppts = await fetchAppts(firstOfYear, lastOfYear)

  const apptsByMonth = Array.from({ length: 12 }, () => [])
  allAppts.forEach(a => {
    if (a.appointment_date) {
      const m = parseInt(a.appointment_date.split('-')[1], 10) - 1
      if (m >= 0 && m < 12) apptsByMonth[m].push(a)
    }
  })

  const panels = []
  for (let m = 0; m < 12; m++) {
    const first = new Date(year, m, 1, 12, 0, 0)
    const last = new Date(year, m + 1, 0, 12, 0, 0)
    const appts = apptsByMonth[m]
    const total = appts.reduce((s, a) => s + Number(a.price || 0), 0)
    const startOff = first.getDay()

    const byDay = {}
    appts.forEach(a => { byDay[a.appointment_date] = (byDay[a.appointment_date] || 0) + 1 })

    let cellHtml = ''
    for (let i = 0; i < startOff; i++) cellHtml += '<div class="year-month-cell empty"></div>'
    for (let d = 1; d <= last.getDate(); d++) {
      const ds = _fmt(new Date(year, m, d, 12, 0, 0))
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
        + '<div class="year-month-summary">' + appts.length + ' atend. · R$ ' + total.toLocaleString('pt-BR', {minimumFractionDigits: 0}) + '</div>'
        + '</div>'
    })
  }

  document.getElementById('agenda-year-view').innerHTML = '<div class="year-grid">' + panels.map(p => p.html).join('') + '</div>'
  document.getElementById('agenda-year-view').style.display = ''

  document.querySelectorAll('#agenda-year-view .year-month-panel').forEach(el => {
    el.style.cursor = 'pointer'
    el.addEventListener('click', function() {
      agendaDate = new Date(year, +this.dataset.month, 1, 12, 0, 0)
      agendaView = 'month'
      syncAgendaViewTabs()
      showAgendaView()
    })
  })

  document.getElementById('agenda-summary').textContent = allAppts.length + ' atendimentos em ' + year
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
  document.documentElement.setAttribute('data-theme', theme)
  const screen = document.querySelector('.screen')
  if (screen) screen.setAttribute('data-theme', theme)
  document.querySelectorAll('.theme-option').forEach(o => o.classList.remove('active'))
  if (el) el.classList.add('active')
  localStorage.setItem('beautyflow-theme', theme)

  const activePage = document.querySelector('.page:not(.hide)')
  if (activePage) {
    if (activePage.id === 'page-dashboard') loadDashboard()
    else if (activePage.id === 'page-financeiro') loadFinanceiro()
    else if (activePage.id === 'page-relatorios') loadReports()
    else if (activePage.id === 'page-agenda') renderAgenda()
  }
}

function setFontSize(size, el) {
  document.documentElement.setAttribute('data-font-size', size)
  const screen = document.querySelector('.screen')
  if (screen) screen.setAttribute('data-font-size', size)
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
  document.documentElement.setAttribute('data-color-scheme', scheme)
  const screen = document.querySelector('.screen')
  if (screen) screen.setAttribute('data-color-scheme', scheme)
  document.querySelectorAll('.scheme-option').forEach(o => o.classList.remove('active'))
  if (el) el.classList.add('active')
  localStorage.setItem('beautyflow-scheme', scheme)

  const activePage = document.querySelector('.page:not(.hide)')
  if (activePage) {
    if (activePage.id === 'page-dashboard') loadDashboard()
    else if (activePage.id === 'page-financeiro') loadFinanceiro()
    else if (activePage.id === 'page-relatorios') loadReports()
    else if (activePage.id === 'page-agenda') renderAgenda()
  }
}

;(function init() {
  const screen = document.querySelector('.screen')
  const savedTheme = localStorage.getItem('beautyflow-theme') || 'default'
  document.documentElement.setAttribute('data-theme', savedTheme)
  if (screen) screen.setAttribute('data-theme', savedTheme)
  document.querySelectorAll('.theme-option').forEach(o => o.classList.remove('active'))
  const activeTheme = document.querySelector(`.theme-option[data-theme="${savedTheme}"]`)
  if (activeTheme) activeTheme.classList.add('active')

  const savedScheme = localStorage.getItem('beautyflow-scheme') || 'light'
  document.documentElement.setAttribute('data-color-scheme', savedScheme)
  if (screen) screen.setAttribute('data-color-scheme', savedScheme)
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
