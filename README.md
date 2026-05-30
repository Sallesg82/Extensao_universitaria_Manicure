# BeautyFlow — Extensão Universitária

Sistema de gestão para salões de beleza, composto por um **CRM completo** e um **portal de agendamento** para clientes.

---

## Tecnologias

| Categoria | Tecnologia |
|-----------|-----------|
| Backend | Python 3.14, Flask, Flask-SocketIO, Flask-CORS, Gunicorn |
| Frontend (CRM) | HTML5, CSS3, JavaScript (vanilla), Socket.IO Client |
| Frontend (Agendamento) | React 19, Vite 8, Tailwind CSS 4, Socket.IO Client |
| Banco | Supabase (PostgreSQL cloud) |
| ORM/Client | Supabase Python SDK / PostgREST |
| Realtime | WebSockets (Socket.IO) |
| Autenticação | werkzeug (hash de senha) |
| Integrações | Google Calendar API, n8n webhooks |
| Conteinerização | Docker, Docker Compose |
| Servidor (produção) | Nginx (reverse proxy) |

---

## 1. CRM BeautyFlow

> `Aplicativos/CRM BeautyFlow/` — **Porta 3001**

CRM completo para gestão de salão de beleza. Backend Flask que também serve o frontend SPA em HTML/CSS/JS puro.

### Funcionalidades

- **Dashboard** — métricas do mês: receita, despesas, lucro, ticket médio, clientes ativos; gráfico de receita diária; agendamentos do dia
- **Agenda** — visualização por dia/semana/mês/ano, criação/edição de agendamentos, arrastar para horários, respeita horários de funcionamento e duração dos serviços
- **Clientes** — cadastro, busca por nome/telefone, filtros por categoria (Todos/Frequentes/Novos/Inativos/Regulares)
- **Serviços** — CRUD de serviços com nome, duração, preço e cor
- **Financeiro** — lançamentos de receitas e despesas, gráfico de rosca por serviço, extrato diário, exportação PDF
- **Relatórios** — tendência de receita, clientes top, serviços mais vendidos, mapa de calor de horários de pico, filtro por período (7/30/90/365 dias)
- **Metas** — definição de meta mensal com barra de progresso
- **Usuários** — gerenciamento de contas de acesso
- **Integrações** — n8n (webhooks), Google Calendar (sincronia bidirecional)

### Rotas da API

| Rota | Descrição |
|------|-----------|
| `GET /api/clients/` | Listar clientes (`?search=&status=`) |
| `POST /api/clients/` | Criar cliente |
| `GET /api/appointments/` | Listar agendamentos (`?date_from=&date_to=`) |
| `POST /api/appointments/` | Criar agendamento |
| `GET /api/services/` | Listar serviços |
| `POST /api/services/` | Criar serviço |
| `GET /api/transactions/` | Listar transações (`?date_gte=&date_lte=&type=`) |
| `POST /api/transactions/` | Criar transação |
| `GET /api/users/` | Listar usuários |
| `POST /api/users/login` | Login |
| `GET /api/stats` | Estatísticas do dashboard (`?period=N`) |
| `GET /api/available-slots` | Horários disponíveis (`?date=&duration=`) |
| `GET /api/business-hours` | Horários de funcionamento |
| `GET /api/notifications/` | Notificações |
| `GET /api/integrations/` | Integrações |
| `GET /api/google/auth` | Auth Google Calendar |
| `POST /api/n8n/test` | Testar webhook n8n |
| `GET /api/settings/` | Configurações do sistema |

### Estrutura

```
CRM BeautyFlow/
├── backend/
│   ├── run.py                  # Inicialização dev
│   ├── server.py               # App Flask + todas as rotas
│   ├── wsgi.py                 # Entrada Gunicorn
│   ├── ws.py                   # Instância SocketIO
│   ├── db/
│   │   ├── database.py         # Todas as queries Supabase
│   │   └── supabase_schema.sql # Schema completo do banco
│   ├── routes/
│   │   ├── clients.py
│   │   ├── appointments.py
│   │   ├── services.py
│   │   ├── transactions.py
│   │   ├── users.py
│   │   ├── notifications.py
│   │   ├── integrations.py
│   │   └── google_calendar.py
│   └── middleware/
│       └── validation.py
├── src/
│   ├── index.html              # SPA completa
│   ├── js/app.js               # Lógica frontend
│   └── css/style.css           # Estilos
├── instalacao/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── start.sh
│   └── install.sh
└── docs/
    └── ux(Mirian Original).html
```

### Banco de Dados (Supabase)

| Tabela | Finalidade |
|--------|-----------|
| `clients` | Clientes do salão |
| `appointments` | Agendamentos |
| `services` | Serviços oferecidos |
| `transactions` | Lançamentos financeiros |
| `settings` | Configurações chave/valor |
| `business_hours` | Horários de funcionamento |
| `notifications` | Notificações do sistema |
| `integrations` | Integrações (n8n, Google) |
| `users` | Usuários do sistema |

### Iniciar

```bash
cd "Aplicativos/CRM BeautyFlow/backend"
./venv/bin/python run.py
# → http://localhost:3001
```

---

## 2. Agendamento Vinicius

> `Aplicativos/agendamento Vinicius/` — **Porta 5173**

Portal de agendamento para o cliente final. Aplicação React com Vite e Tailwind CSS. Permite que clientes visualizem horários disponíveis e façam agendamentos consumindo a API do CRM.

### Funcionalidades

- Visualização de horários disponíveis
- Agendamento online pelo cliente
- Consumo da API REST do CRM BeautyFlow
- Atualizações em tempo real via Socket.IO

### Tecnologias

- React 19
- Vite 8 (bundler)
- Tailwind CSS 4
- Socket.IO Client
- ESLint 10

### Docker (produção)

- Build multi-stage: node:22-slim → nginx:alpine
- Servido na porta 80 (conteinerizado)

### Estrutura

```
agendamento Vinicius/
├── index.html
├── vite.config.js
├── package.json
├── src/
│   ├── main.jsx
│   ├── App.jsx
│   ├── App.css
│   └── index.css
├── instalacao/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── start.sh
│   └── install.sh
└── public/
    ├── favicon.svg
    └── icons.svg
```

### Iniciar

```bash
cd "Aplicativos/agendamento Vinicius"
npm run dev
# → http://localhost:5173
```

---

## 3. Instalação Unificada

> `Aplicativos/instalacao/`

Scripts e guias para instalação completa do ecossistema BeautyFlow.

### Opções

- **Native** — instalação direta no SO (Linux/macOS/Windows)
- **Docker** — conteinerização com Docker Compose

### Scripts

| Arquivo | Finalidade |
|---------|-----------|
| `install.sh` | Instalador Linux/macOS (menu interativo) |
| `install.bat` | Launcher Windows |
| `install_windows.ps1` | Instalador Windows com GUI |
| `start.sh` | Inicia CRM + Agendamento |
| `docker-compose.yml` | Orquestração Docker (CRM + Agendamento) |

### Tutoriais

- `README.md` — instruções rápidas
- `tutorial.md` — guia completo de deploy em servidor Ubuntu com Nginx, SSL, systemd, firewall e backup

### Arquitetura (produção)

```
                    Internet
                       |
                   ┌────▼────┐
                   │ Nginx   │  porta 80/443 (SSL)
                   │ Proxy   │
                   └────┬────┘
                        │
             ┌──────────┴──────────┐
             │                     │
        ┌────▼─────┐        ┌─────▼──────┐
        │  CRM     │        │ Agendamento │
        │ :3001    │        │ :80/5173    │
        │ (Flask)  │        │ (Vite/React)│
        └────┬─────┘        └─────▲───────┘
             │                     │
             │              (chama API)
             │                     │
        ┌────▼─────────────────────┴───┐
        │  Supabase (PostgreSQL)       │
        │  Cloud ou self-hosted        │
        └──────────────────────────────┘
```

---

## Pré-requisitos

- Python 3.14+
- Node.js 22+
- npm
- Conta Supabase (gratuita em [supabase.com](https://supabase.com))
- Docker (opcional, para conteinerização)

## Variáveis de Ambiente

Crie `backend/.env` no CRM:

```env
SUPABASE_URL=https://seu-projeto.supabase.co
SUPABASE_ANON_KEY=sua_chave_anon
SUPABASE_KEY=sua_chave_service_role
```

---

## Licença

Projeto de extensão universitária — uso educacional.
