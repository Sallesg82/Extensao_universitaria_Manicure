# Resumo Técnico — BeautyFlow CRM

## Arquitetura

BeautyFlow CRM — sistema de gestão para salão de beleza, SPA com backend Flask + Supabase (PostgreSQL) e frontend vanilla JS.

```
src/                          # Frontend SPA
├── index.html                # 7 páginas: Dashboard, Agenda, Clientes, Serviços,
│                             #   Financeiro, Despesas, Relatórios
├── css/style.css             # 5 temas, dark/light, responsivo (5477 linhas)
└── js/app.js                 # Lógica completa (~4000 linhas)

backend/                      # API Flask + WebSocket
├── server.py                 # Flask app, SocketIO, rotas principais (/api/stats, /api/settings)
├── run.py / wsgi.py          # Entry point (porta 3001)
├── ws.py                     # SocketIO instance
├── db/database.py            # Camada de dados — todas as queries Supabase
├── db/supabase_schema.sql    # Schema completo (8 tabelas + views)
├── routes/                   # Blueprints CRUD
│   ├── clients.py            #   CRUD clientes (97 linhas)
│   ├── appointments.py       #   CRUD agendamentos + auto-criação de transações (313 linhas)
│   ├── transactions.py       #   CRUD transações financeiras (92 linhas)
│   ├── services.py           #   CRUD serviços (72 linhas)
│   ├── users.py              #   CRUD usuários + login (108 linhas)
│   ├── notifications.py      #   Notificações (26 linhas)
│   ├── integrations.py       #   Integrações webhook/n8n/Google Calendar (64 linhas)
│   └── google_calendar.py    #   OAuth + sync Google Calendar (232 linhas)
└── middleware/validation.py  # Decorators de validação
```

---

## Banco de Dados (Supabase PostgreSQL)

8 tabelas + 3 views:

| Tabela | Função |
|--------|--------|
| `clients` | Cadastro com avatar, status (regular/frequente/novo/inativo/inadimplente) |
| `appointments` | Agendamentos com FK → clients, status (pending/confirmed/done/cancelled), payment_status (unpaid/paid) |
| `services` | Catálogo de serviços com preço, duração, buffer, cor |
| `transactions` | Lançamentos financeiros (income/expense) com appointment_id opcional e nome_completo |
| `settings` | Chave-valor (meta_mensal, notificações, trash de agendamentos) |
| `business_hours` | Horários de funcionamento por dia da semana |
| `notifications` | Notificações do sistema (meta atingida, etc.) |
| `users` | Usuários com autenticação (bcrypt) |
| `v_clients` | View: clientes com visitas, total_gasto, última_visita |
| `v_month_stats` | View: receita/despesas/agendamentos do mês |
| `v_daily_stats` | View: receita/despesa por dia |

### Schema da tabela `transactions`

```sql
CREATE TABLE transactions (
    id                SERIAL PRIMARY KEY,
    type              TEXT NOT NULL CHECK(type IN ('income', 'expense')),
    description       TEXT NOT NULL,
    amount            REAL NOT NULL,
    category          TEXT DEFAULT '',
    payment_method    TEXT DEFAULT '',
    date              DATE NOT NULL,
    appointment_id    INTEGER REFERENCES appointments(id) ON DELETE SET NULL,
    nome_completo     TEXT DEFAULT '',
    created_at        TIMESTAMPTZ DEFAULT NOW()
);
```

---

## API — ~50 Endpoints REST + WebSocket

Rota principal de métricas:

```
GET /api/stats?period=7|30|90|365  →  JSON com ~25 campos
```

### Blueprints

| Blueprint | Prefixo | Endpoints |
|-----------|---------|-----------|
| clients_bp | `/api/clients/` | GET list, GET/:id, POST, PUT/:id, DELETE/:id |
| appointments_bp | `/api/appointments/` | GET list, GET/:id, POST, PUT/:id, DELETE/:id |
| services_bp | `/api/services/` | GET list, POST, PUT/:id, DELETE/:id |
| transactions_bp | `/api/transactions/` | GET list, GET/:id, POST, PUT/:id, DELETE/:id |
| users_bp | `/api/users/` | GET list, GET/exists, GET/:id, POST, PUT/:id, DELETE/:id, PUT/:id/password, POST/login |
| notifications_bp | `/api/notifications/` | GET list, GET/unread-count, POST/read/:id, POST/read-all |
| integrations_bp | `/api/integrations/` | GET list, GET/:id, POST, PUT/:id, DELETE/:id |
| google_bp | `/api/google/` | GET/PUT config, GET auth, GET callback, GET status, POST disconnect, POST verify-event, POST sync |

### Rotas diretas em server.py

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/` | Serve index.html (SPA) |
| GET | `/api/stats` | Métricas do dashboard |
| GET/PUT | `/api/settings/` | Configurações do sistema |
| GET/PUT | `/api/business-hours` | Horários de funcionamento |
| GET | `/api/available-slots` | Slots disponíveis |
| GET | `/api/migrate/sql` | Schema SQL completo |
| GET/POST | `/api/expense-categories` | Categorias de despesa |
| GET/PUT | `/api/n8n/config` | Configuração n8n |
| POST | `/api/n8n/test` | Testa webhook n8n |
| POST | `/api/n8n/sync-calendar` | Sincroniza com n8n |
| GET | `/api/n8n/status` | Status da conexão n8n |

---

## Sistema de Cálculos e Relatórios

### Parâmetros de Período (`get_stats(period)`)

| period | Escopo |
|--------|--------|
| `None` (padrão) | Mês atual (01 até hoje) |
| `7` | Semana atual (segunda até hoje) |
| `30` | Mês atual |
| `90` | Últimos 3 meses |
| `365` | Ano atual (01/jan até hoje) |

### Fórmulas Financeiras

| Métrica | Origem | Fórmula |
|---------|--------|---------|
| **Receita Hoje** | `transactions WHERE type='income' AND date=today` | `SUM(amount)` |
| *Fallback* | `appointments WHERE payment_status='paid' AND date=today` | `SUM(price)` |
| **Receita do Mês** | `transactions WHERE type='income' AND date IN [month_start, today]` | `SUM(amount)` |
| **Receita Total (all-time)** | `transactions WHERE type='income'` (sem filtro) | `SUM(amount)` |
| **Despesas do Mês** | `transactions WHERE type='expense' AND date IN [month_start, today]` | `SUM(amount)` |
| **Lucro Líquido** | Calculado no frontend | `month_revenue - month_expenses` |
| **Ticket Médio** | All-time | `total_revenue_all / count(income_transactions)` |
| **Meta %** | Config `meta_mensal` (default R$ 7.000) | `round(month_revenue / meta_mensal × 100, 1)` |
| **Margem %** | Calculado no frontend | `round(lucro / month_revenue × 100)` |
| **Receita Semanal** | Agrupamento por `(day-1)//7` dentro do mês | Array de 4 valores |
| **Receita Mês Anterior** | Transactions do mês anterior | `SUM(amount)` |

### Gráficos (11 no total)

| # | Gráfico | Página | Tipo de Visualização |
|---|---------|--------|---------------------|
| 1 | **Receita Hoje / Atendimentos / Clientes Ativos / Ticket Médio** | Dashboard | Cards numéricos (4 métricas) |
| 2 | **Receita Semanal** | Dashboard | Barras verticais (4 semanas) |
| 3 | **Serviços Mais Realizados** | Dashboard | Barras horizontais (top 5) |
| 4 | **Progresso da Meta** | Dashboard | Barra de progresso + % |
| 5 | **Horários de Pico** (6 dias × 10 horas) | Dashboard + Relatórios | Heatmap (grid) |
| 6 | **Pagamentos Recentes** | Dashboard | Lista vertical |
| 7 | **Receita vs Despesas** (diário) | Financeiro | Barras emparelhadas |
| 8 | **Receita por Serviço** | Financeiro | Donut (SVG, até 4 fatias) |
| 9 | **Despesas por Categoria** | Financeiro | Barras horizontais |
| 10 | **Meta do Mês** | Financeiro | Barra de progresso |
| 11 | **Tendência de Receita** | Relatórios | Linha (SVG) |

### Métricas Operacionais

| Métrica | Cálculo |
|---------|---------|
| Clientes ativos | `COUNT(clients.id)` |
| Clientes no mês | `COUNT(DISTINCT client_id)` de appointments no período |
| Atendimentos hoje | `COUNT(appointments WHERE date=today)` |
| Pendentes hoje | `COUNT(appointments WHERE date=today AND status='pending')` |
| Pendentes futuros | `COUNT(appointments WHERE status='pending' AND date >= today)` |
| Top 5 clientes | Ordenado por `total_spent` decrescente no período |
| Clientes inativos | Sem visita há 30+ dias (via `v_clients.last_visit`) |
| Pix pendentes | `COUNT(transactions WHERE type='income' AND payment_method='Pix')` |

### Regras de Negócio

- **Receita** primariamente lida de `transactions` (snapshot imutável); se vazio, fallback para `appointments.price WHERE payment_status='paid'`
- **Transações de income** são auto-criadas quando `payment_status` muda para `'paid'`, com `nome_completo` do cliente (sobrevive à exclusão do cliente)
- **Soft-delete** de agendamentos via tabela `settings` (chave `trash_appt_{id}`) com restauração
- **Horários de pico** calculados agregando `appointment_time` (08:00–17:00, Seg–Sáb), grid 6×10
- **Notificação de meta** criada automaticamente quando `month_revenue >= meta_mensal`
- **Integrações**: Google Calendar (OAuth, sync bidirecional), n8n (webhooks para eventos), Socket.IO (tempo real)

---

## Fluxo de Dados — Financeiro

```
Agendamento pago (payment_status='paid')
  │
  ├── Auto-cria transação income com nome_completo
  │
  └── get_stats() lê transactions.type='income'
        │
        ├── today_revenue    ← filtro date=today
        ├── month_revenue    ← filtro date IN [mês]
        ├── total_revenue_all ← sem filtro
        └── recent_income    ← últimas 20 income
              │
              └── Frontend renderiza cards, gráficos, listas
```

```
Despesa manual
  │
  ├── POST /api/transactions/ { type: 'expense', ... }
  │
  └── get_stats() lê transactions.type='expense'
        │
        ├── month_expenses   ← SUM no período
        └── expenses_by_category ← GROUP BY category
```
