const API = window.location.origin + '/api'

const pageConfig = {
  dashboard:      { title: 'Painel Geral',    sub: '',      btn: '+ Novo Agendamento' },
  agenda:         { title: 'Agenda',          sub: '',      btn: '+ Novo Agendamento' },
  clientes:       { title: 'Clientes',        sub: '',      btn: '+ Nova Cliente' },
  servicos:       { title: 'Serviços',        sub: '',      btn: '+ Novo Serviço' },
  metas:          { title: 'Metas',           sub: '',      btn: null },
  financeiro:     { title: 'Financeiro',      sub: '',      btn: '+ Novo Lançamento' },
  relatorios:     { title: 'Relatórios',      sub: 'Análise dos últimos 30 dias',      btn: '⬇ Exportar PDF' },
  configuracoes:  { title: 'Configurações',   sub: 'Gerencie seu sistema BeautyFlow',      btn: null },
}

function showPage(pageId, navEl) {
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
  } else if (pageId === 'relatorios') {
    const btn = document.getElementById('topbar-btn')
    const orig = btn.textContent
    btn.textContent = '⏳ Exportando...'
    setTimeout(() => { btn.textContent = orig }, 2000)
  }
}

function showSettingsTab(navEl, tabId) {
  document.querySelectorAll('.settings-nav-item').forEach(n => n.classList.remove('active'))
  navEl.classList.add('active')
  ;['tab-perfil','tab-horarios','tab-notif','tab-integ','tab-aparencia'].forEach(id => {
    document.getElementById(id).style.display = id === tabId ? '' : 'none'
  })
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
  list.innerHTML = clients.map((c, i) => {
    const lastDate = c.last_visit ? c.last_visit.split('T')[0].split('-').reverse().join('/') : '—'
    const statusMap = { frequente: 'Frequente', regular: 'Regular', novo: 'Novo', inativo: 'Inativo' }
    const statusClassMap = { frequente: 'status-done', regular: 'status-confirmed', novo: 'status-pending', inativo: 'status-pending' }
    const label = statusMap[c.status] || c.status
    const cls = statusClassMap[c.status] || 'status-pending'
    const spent = 'R$ ' + Number(c.total_spent).toLocaleString('pt-BR', {minimumFractionDigits:0})
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

// ── DASHBOARD ─────────────────────────────────────

async function loadDashboard() {
  try {
    const res = await fetch(API + '/stats')
    const stats = await res.json()

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
    if (s.service_revenue_breakdown && s.service_revenue_breakdown.length > 0) {
      const colors = ['#4a90d9', '#2563a8', '#3a7abf', '#b8d4f0', '#1a5fab']
      const donutColors = ['#4a90d9', '#1a5fab', '#3a7abf', '#b8d4f0', '#2563a8']
      const total = s.service_revenue_breakdown.reduce((sum, svc) => sum + svc.pct, 0) || 100
      const circumference = 2 * Math.PI * 32

      if (donutSvg) {
        let svgContent = ''
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
        donutSvg.innerHTML = svgContent +
          `<text x="45" y="48" text-anchor="middle" font-family="DM Serif Display,serif" font-size="13" fill="#0f2340">${topPct}%</text>`
      }

      if (donutLegend) {
        donutLegend.innerHTML = s.service_revenue_breakdown.map((svc, i) => `
          <div class="donut-legend-item">
            <div class="donut-legend-dot" style="background:${colors[i % colors.length]};"></div>
            ${svc.name} <span style="margin-left:auto;color:#0f2340;font-weight:500;">${svc.pct}%</span>
          </div>`).join('')
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
      const labels = metaPanel.querySelectorAll('.meta-progress-label')
      if (labels.length >= 2) {
        labels[0].textContent = 'R$ ' + s.month_revenue.toLocaleString('pt-BR', {minimumFractionDigits: 0}) + ' arrecadado'
        labels[1].textContent = 'Meta: R$ ' + s.meta_mensal.toLocaleString('pt-BR', {minimumFractionDigits: 0})
      }
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

let apptsWeekCache = []

async function loadAgenda() {
  const today = new Date()
  const monday = new Date(today)
  monday.setDate(today.getDate() - (today.getDay() === 0 ? 6 : today.getDay() - 1))
  const sunday = new Date(monday)
  sunday.setDate(monday.getDate() + 6)
  const fmt = d => d.toISOString().split('T')[0]
  const formatBR = d => d.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' }).replace('.', '')

  pageConfig.agenda.sub = formatBR(monday) + ' – ' + formatBR(sunday) + ' ' + sunday.getFullYear()
  document.getElementById('page-sub').textContent = pageConfig.agenda.sub

  try {
    const mondayStr = fmt(monday)
    const sundayStr = fmt(sunday)
    const res = await fetch(API + '/appointments/?date_from=' + mondayStr + '&date_to=' + sundayStr)
    const appts = await res.json()
    apptsWeekCache = appts

    if (!servicesCache.length) await loadServices()

    const scheduleEl = document.querySelector('.agenda-toolbar .agenda-period')
    if (scheduleEl) scheduleEl.textContent = pageConfig.agenda.sub

    const dayCols = document.querySelectorAll('.day-col')
    for (let i = 0; i < 7 && i < dayCols.length; i++) {
      const day = new Date(monday)
      day.setDate(monday.getDate() + i)
      const slots = dayCols[i]?.querySelector('.day-slots')
      if (!slots) continue

      if (day.getDay() === 0) {
        slots.querySelectorAll('.cal-event, .folga-overlay, .folga-label').forEach(el => el.remove())
        if (!slots.querySelector('.folga-overlay')) {
          slots.insertAdjacentHTML('beforeend', '<div class="folga-overlay"></div><div class="folga-label">Folga</div>')
        }
        continue
      }

      slots.querySelectorAll('.cal-event').forEach(el => el.remove())

      const dayAppts = appts.filter(a => a.appointment_date === fmt(day))
      const statusClassMap = { done: 'done', confirmed: 'confirmed', pending: 'pending', cancelled: 'cancelled' }

      dayAppts.forEach(a => {
        const timeParts = a.appointment_time.split(':')
        const hour = parseInt(timeParts[0])
        const min = parseInt(timeParts[1])
        const topPx = (hour - 8) * 52 + (min / 60) * 52
        const heightPx = Math.max(52, (a.duration / 60) * 52)

        const calEl = document.createElement('div')
        calEl.className = 'cal-event ' + (statusClassMap[a.status] || 'pending')
        calEl.style.cssText = `top:${topPx}px;height:${heightPx}px;cursor:pointer;`
        calEl.dataset.apptId = a.id
        calEl.addEventListener('click', e => {
          e.stopPropagation()
          openAppointmentDetail(a.id)
        })
        calEl.innerHTML = `<div class="ev-name">${a.client_name}</div><div class="ev-svc">${a.service}</div>`
        slots.insertAdjacentElement('beforeend', calEl)
      })

      const hourLines = slots.querySelectorAll('.hour-line')
      hourLines.forEach((hl, hi) => {
        hl.style.cursor = 'pointer'
        hl.addEventListener('click', () => {
          const hour = hi + 8
          openAppointmentModal(fmt(day), String(hour).padStart(2, '0') + ':00')
        })
      })
    }

    const summary = document.querySelector('.agenda-summary')
    if (summary) {
      summary.textContent = appts.filter(a => {
        const d = new Date(a.appointment_date)
        return d >= monday && d <= sunday
      }).length + ' atendimentos esta semana'
    }
  } catch (e) {
    console.error('Erro ao carregar agenda:', e)
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

  const body = { client_id: Number(clientId), service, appointment_date: date, appointment_time: time, status, price: Number(price), notes }

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

// ── EVENT LISTENERS ────────────────────────────────

document.querySelectorAll('.filter-tab').forEach(t => {
  t.addEventListener('click', () => {
    document.querySelectorAll('.filter-tab').forEach(x => x.classList.remove('active'))
    t.classList.add('active')
  })
})

document.querySelectorAll('.period-btn').forEach(t => {
  t.addEventListener('click', () => {
    document.querySelectorAll('.period-btn').forEach(x => x.classList.remove('active'))
    t.classList.add('active')
  })
})

document.querySelectorAll('.view-tab').forEach(t => {
  t.addEventListener('click', () => {
    document.querySelectorAll('.view-tab').forEach(x => x.classList.remove('active'))
    t.classList.add('active')
  })
})

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

;(function loadSavedSettings() {
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

  const ls = document.getElementById('loadingScreen')
  if (ls) setTimeout(() => ls.classList.add('hide'), 300)

  loadServices()
  loadDashboard()
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

document.querySelectorAll('.hour-toggle').forEach(t => {
  t.addEventListener('click', () => {
    const isOn = t.classList.contains('on')
    t.classList.toggle('on', !isOn)
    t.classList.toggle('off', isOn)
  })
})
