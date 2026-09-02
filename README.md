# 💅 BeautyFlow — Sistema de Gestão para Salões de Beleza

> Projeto de Extensão Universitária — SENAI

Sistema completo de gestão para salões de beleza composto por dois aplicativos integrados: um **CRM de gestão** para o profissional e um **portal de agendamento online** para os clientes, conectados em **tempo real** via WebSockets.

---

## 📋 Índice

- [Visão Geral](#-visão-geral)
- [Tecnologias Utilizadas](#-tecnologias-utilizadas)
- [CRM BeautyFlow](#-1-crm-beautyflow)
- [Portal de Agendamento](#-2-portal-de-agendamento-online)
- [Banco de Dados](#-banco-de-dados)
- [Instalação](#-instalação)
- [Arquitetura](#-arquitetura-de-produção)
- [Variáveis de Ambiente](#-variáveis-de-ambiente)
- [Documentação](#-documentação)
- [Licença](#-licença)

---

## 🔭 Visão Geral

O **BeautyFlow** é um ecossistema de software desenvolvido como projeto de extensão do SENAI, pensado para resolver as necessidades reais de salões de beleza e profissionais autônomos da área de estética. O sistema é dividido em:

| Aplicativo | Descrição | Porta |
|---|---|---|
| **CRM BeautyFlow** | Painel completo de gestão (agenda, clientes, financeiro, relatórios, integrações) | `3001` |
| **Portal de Agendamento** | Interface conversacional para o cliente final agendar serviços online | `5173` |

Ambos se comunicam em **tempo real** — quando um cliente agenda pelo portal, o profissional recebe a notificação instantaneamente no CRM.

---

## 🛠 Tecnologias Utilizadas

### Backend

| Tecnologia | Versão | Finalidade |
|---|---|---|
| Python | 3.11+ | Linguagem principal do servidor |
| Flask | 3.0.3 | Framework web (API REST + serve o frontend SPA) |
| Flask-SocketIO | 5.3.6 | WebSockets para sincronização em tempo real |
| Flask-CORS | 4.0.1 | Habilitação de requisições cross-origin |
| Psycopg 3 | 3.1.18 | Driver nativo PostgreSQL com connection pooling |
| Werkzeug | — | Hash de senhas (PBKDF2/SHA-256) |
| Google API Client | 2.133.0 | Integração OAuth 2.0 + Google Calendar API v3 |
| Requests | 2.32.3 | Webhooks HTTP (n8n e integrações externas) |
| Python-Dotenv | 1.0.1 | Gerenciamento de variáveis de ambiente |

### Frontend — CRM

| Tecnologia | Finalidade |
|---|---|
| HTML5 Semântico | Estrutura da SPA |
| CSS3 (5.400+ linhas) | Design system completo com variáveis, temas e modo escuro |
| JavaScript ES6+ (~4.000 linhas) | Lógica reativa sem frameworks |
| Socket.IO Client 4.7.5 | Atualizações em tempo real |
| SVG Nativo | 11 tipos de gráficos renderizados sem bibliotecas externas |
| Google Fonts | DM Serif Display + DM Sans / Inter |

### Frontend — Portal de Agendamento

| Tecnologia | Versão | Finalidade |
|---|---|---|
| React | 19.2 | Biblioteca de UI |
| Vite | 8.0 | Build tool e dev server |
| Tailwind CSS | 4.2 | Framework de estilização utilitária |
| Socket.IO Client | 4.8.3 | Comunicação em tempo real com o CRM |
| ESLint | 10.2 | Linting e qualidade de código |

### Banco de Dados

| Tecnologia | Versão | Finalidade |
|---|---|---|
| PostgreSQL | 16 | Banco relacional (via Docker ou cloud) |

### DevOps & Infraestrutura

| Tecnologia | Finalidade |
|---|---|
| Docker | Conteinerização dos serviços |
| Docker Compose | Orquestração (PostgreSQL + CRM + Agendamento) |
| Nginx | Reverse proxy e servidor estático (produção) |
| n8n | Automação de workflows via webhooks |

---

## 🏢 1. CRM BeautyFlow

> `Aplicativos/CRM BeautyFlow/` — **Porta 3001**

Painel completo de gestão para o profissional. O backend Flask serve tanto a API REST quanto o frontend SPA em HTML/CSS/JS puro — sem necessidade de build.

### Módulos e Funcionalidades

#### 📊 Dashboard
- Cards de métricas: Receita Hoje, Atendimentos, Clientes Ativos, Ticket Médio
- Gráfico de barras semanal de faturamento
- Ranking Top 5 serviços realizados
- Barra de progresso da meta mensal
- Mapa de Calor (Heatmap) 6 dias × 10 horários — visualiza horários de pico
- Lista de agendamentos do dia em tempo real
- Pagamentos recentes
- Alertas de clientes inativos com potencial de receita
- Seletor de período (7, 30, 90, 365 dias)

#### 📅 Agenda Interativa
- 4 modos de visualização: **Dia** (slots 30min), **Semana** (3/5/7 dias), **Mês**, **Ano**
- Navegação temporal (anterior/próximo/hoje)
- Clique direto em horário livre para agendar
- Validação automática de horários de funcionamento e conflitos
- Status de pagamento (Pago / Não Pago) direto na agenda
- Bloqueio visual de dias de folga
- Sincronização bidirecional com Google Calendar
- Atualizações em tempo real via WebSocket

#### 👥 Gestão de Clientes
- Busca em tempo real por nome ou telefone (com normalização de acentos)
- Filtros: Todos, Frequentes, Novos, Inativos (30+ dias), Regulares, Inadimplentes
- Ficha detalhada: avatar, total de visitas, total gasto, ticket médio, última visita
- Histórico cronológico completo de agendamentos
- Serviços mais consumidos por cliente
- Ações: cadastrar, editar, excluir, marcar como inadimplente

#### 💇 Gestão de Serviços
- CRUD completo: nome, duração (min), buffer/intervalo, preço (R$), cor hexadecimal
- Cor do serviço refletida nos cards da agenda

#### 💰 Módulo Financeiro
- KPIs: Receita Mensal, Despesas, Lucro Líquido, Margem %
- Gráfico diário comparativo Receitas × Despesas
- Gráfico Donut SVG de receita por serviço
- Lançamentos manuais com método de pagamento (Pix, Dinheiro, Cartão Crédito/Débito)
- **Snapshot imutável de receita** — ao marcar agendamento como pago, grava transação com nome persistente do cliente (não se perde se o cliente for excluído)
- Extrato completo de transações

#### 📉 Controle de Despesas
- Métricas: Total, Maior Despesa, Categoria mais custosa, Média
- Gráfico horizontal por categoria (Aluguel, Produtos, Energia, Marketing, Salários, Outros)
- Categorias de despesa customizáveis
- Lista completa com exclusão e novo lançamento

#### 📈 Relatórios e Exportação PDF
- Gráfico de tendência de receita SVG com gradiente e comparativo com período anterior
- Ranking Top 5 clientes
- Serviços mais rentáveis
- Mapa de calor completo de horários
- **Exportação em PDF** profissional com cabeçalho oficial (Razão Social, CNPJ, Telefone, Endereço)
- Seletor de período (7, 30, 90 dias, Ano)

#### 🎯 Metas
- Meta mensal customizável (padrão R$ 7.000)
- Barra de progresso em tempo real
- Notificação automática ao atingir a meta

#### 👤 Gestão de Usuários
- CRUD de operadores/administradores
- Login por e-mail/senha com hash PBKDF2/SHA-256
- Auto-criação de admin padrão se o banco estiver vazio
- Troca de senha

#### 🔔 Central de Notificações e Automações
- Sino com badge de não lidas no topbar
- Notificações de: novos agendamentos online, cancelamentos, meta atingida
- Automações configuráveis:
  - Confirmação automática de agendamento
  - Lembrete 24h e 1h antes
  - Confirmação de Pix
  - Felicitações de aniversário

#### 🔗 Central de Integrações
- **n8n**: URL de webhook, eventos (create/update/delete), headers customizados, botão de teste
- **Google Calendar**: OAuth 2.0, sincronização bidirecional automática
- **Webhooks genéricos**: Cadastro com toggle ativo/inativo

#### ⚙️ Configurações e Customização
- **Perfil**: dados e troca de senha
- **Horários de funcionamento**: Seg–Dom com abertura/fechamento ou fechado
- **Aparência**:
  - 5 Temas: Azul (padrão), Esmeralda, Rosa, Púrpura, Luz do Sol
  - Modo Claro / Escuro
  - Tamanho de fonte: Pequeno, Médio, Grande
  - Layout: Sidebar vertical ou Topbar horizontal
- **Dados da empresa**: Razão Social, CNPJ, endereço (usado nos PDFs)

### Rotas da API (~50 endpoints)

<details>
<summary>Clique para ver todas as rotas</summary>

#### Clientes
| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/api/clients/` | Listar clientes (`?search=&status=`) |
| `GET` | `/api/clients/:id` | Detalhes do cliente com histórico |
| `POST` | `/api/clients/` | Criar cliente |
| `PUT` | `/api/clients/:id` | Atualizar cliente |
| `DELETE` | `/api/clients/:id` | Excluir cliente |

#### Agendamentos
| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/api/appointments/` | Listar (`?date=&date_from=&date_to=&client_id=&status=`) |
| `GET` | `/api/appointments/:id` | Detalhes |
| `POST` | `/api/appointments/` | Criar (valida horário, notifica n8n/Google/WebSocket) |
| `PUT` | `/api/appointments/:id` | Atualizar (sync financeiro ao concluir) |
| `DELETE` | `/api/appointments/:id` | Excluir |

#### Serviços
| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/api/services/` | Listar serviços |
| `POST` | `/api/services/` | Criar serviço |
| `PUT` | `/api/services/:id` | Atualizar |
| `DELETE` | `/api/services/:id` | Excluir |

#### Transações Financeiras
| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/api/transactions/` | Listar (`?date_from=&date_to=&type=`) |
| `GET` | `/api/transactions/:id` | Detalhes |
| `POST` | `/api/transactions/` | Criar lançamento |
| `PUT` | `/api/transactions/:id` | Atualizar |
| `DELETE` | `/api/transactions/:id` | Excluir |

#### Usuários e Autenticação
| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/api/users/` | Listar usuários |
| `GET` | `/api/users/exists` | Verifica se há usuários cadastrados |
| `POST` | `/api/users/` | Criar usuário |
| `POST` | `/api/users/login` | Login (email + senha) |
| `PUT` | `/api/users/:id` | Atualizar |
| `PUT` | `/api/users/:id/password` | Trocar senha |
| `DELETE` | `/api/users/:id` | Excluir |

#### Estatísticas e Horários
| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/api/stats` | Dashboard completo (`?period=N`) |
| `GET` | `/api/available-slots` | Horários livres (`?date=&duration=&buffer=`) |
| `GET` | `/api/business-hours` | Horários de funcionamento |
| `PUT` | `/api/business-hours` | Atualizar horários |

#### Notificações
| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/api/notifications/` | Listar |
| `GET` | `/api/notifications/unread-count` | Contagem de não lidas |
| `POST` | `/api/notifications/read/:id` | Marcar como lida |
| `POST` | `/api/notifications/read-all` | Marcar todas |

#### Integrações
| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/api/integrations/` | Listar integrações |
| `POST` | `/api/integrations/` | Criar integração |
| `PUT` | `/api/integrations/:id` | Atualizar |
| `DELETE` | `/api/integrations/:id` | Excluir |

#### n8n
| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/api/n8n/config` | Configuração do webhook |
| `PUT` | `/api/n8n/config` | Atualizar configuração |
| `POST` | `/api/n8n/test` | Disparo de teste |
| `POST` | `/api/n8n/sync-calendar` | Sincronizar agendamentos |
| `GET` | `/api/n8n/status` | Status de conectividade |

#### Google Calendar
| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/api/google/config` | Configuração OAuth |
| `PUT` | `/api/google/config` | Salvar Client ID/Secret |
| `GET` | `/api/google/auth` | URL de consentimento OAuth 2.0 |
| `GET` | `/api/google/callback` | Callback OAuth |
| `GET` | `/api/google/status` | Status da conexão |
| `POST` | `/api/google/disconnect` | Desconectar |
| `POST` | `/api/google/sync` | Sincronizar evento |

#### Configurações e Despesas
| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/api/settings/` | Configurações globais |
| `PUT` | `/api/settings/` | Atualizar configurações |
| `GET` | `/api/expense-categories` | Categorias de despesa |
| `POST` | `/api/expense-categories` | Criar categoria |

</details>

### Eventos WebSocket (Socket.IO)

O backend emite eventos em tempo real para todas as operações críticas:

```
appointment:created | appointment:updated | appointment:deleted
client:created      | client:updated      | client:deleted
service:changed
transaction:created | transaction:updated | transaction:deleted
data:changed        (evento genérico com tipo e ação)
```

### Estrutura de Diretórios

```
CRM BeautyFlow/
├── backend/
│   ├── run.py                  # Inicialização dev (porta 3001)
│   ├── server.py               # App Flask + todas as rotas
│   ├── wsgi.py                 # Entrada para Gunicorn
│   ├── ws.py                   # Instância Socket.IO
│   ├── requirements.txt        # Dependências Python
│   ├── .env                    # Variáveis de ambiente
│   ├── db/
│   │   ├── connection.py       # Pool de conexões PostgreSQL
│   │   ├── database.py         # Queries e operações de banco
│   │   ├── repository.py       # Camada de repositório
│   │   ├── schema.sql          # Schema principal
│   │   ├── supabase_schema.sql # Schema alternativo (Supabase)
│   │   └── migrations/         # 11 migrations ordenadas
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
│       └── validation.py       # Validação de horários
├── src/
│   ├── index.html              # SPA completa
│   ├── js/app.js               # Lógica frontend (~4.000 linhas)
│   └── css/style.css           # Design system (~5.400 linhas)
└── docs/
    └── ux(Mirian Original).html
```

### Como Iniciar (Desenvolvimento)

```bash
cd "Aplicativos/CRM BeautyFlow/backend"
pip install -r requirements.txt
python run.py
# → http://localhost:3001
```

---

## 📱 2. Portal de Agendamento Online

> `Aplicativos/agendamento Vinicius/` — **Porta 5173**

Interface de agendamento para o cliente final com fluxo conversacional tipo assistente virtual. O cliente escolhe o serviço, data e horário — tudo é refletido em tempo real no CRM do profissional.

### Fluxo em 3 Etapas

1. **Identificação** — Nome completo e telefone/WhatsApp
2. **Preferências** — Opt-in para lembretes e notificações (24h antes, ofertas)
3. **Agendamento** — Seleção de serviço (carrossel), data (calendário) e horário (slots disponíveis calculados pela API)

### Funcionalidades

- Catálogo de serviços dinâmico (vindo da API do CRM)
- Calendário com bloqueio de datas passadas
- Consulta inteligente de horários vagos respeitando duração + buffer + colisões
- Card de resumo com serviço, valor, data por extenso, horário e duração
- Modal de confirmação de sucesso
- Cadastro/vinculação automática de cliente na base do CRM
- Disparo de WebSocket para o CRM em tempo real
- Design responsivo com paleta elegante (tons de rosa, borgonha, dourado)
- Animações de entrada nos balões de chat

### Estrutura de Diretórios

```
agendamento Vinicius/
├── index.html              # HTML5 de entrada
├── vite.config.js          # Config Vite (host: 0.0.0.0, porta 5173)
├── package.json            # Dependências npm
├── eslint.config.js        # ESLint Flat Config
├── .env                    # VITE_API_URL
├── src/
│   ├── main.jsx            # Entrada React 19 (StrictMode)
│   ├── App.jsx             # Componente principal + subcomponentes
│   ├── App.css             # (migrado para index.css)
│   ├── index.css           # Design system completo + animações
│   └── assets/
│       └── hero.png
└── public/
    ├── favicon.svg
    └── icons.svg
```

### Componentes

| Componente | Descrição |
|---|---|
| `StudioHeader` | Cabeçalho com logotipo e indicador de progresso (3 etapas) |
| `AssistantBubble` | Balão de mensagem da assistente virtual com avatar 🌸 |
| `UserBubble` | Balão de resposta do usuário |
| `ServiceCard` | Card de seleção de serviço com selo Premium |
| `SuccessModal` | Modal de confirmação com gradiente e resumo |

### Como Iniciar (Desenvolvimento)

```bash
cd "Aplicativos/agendamento Vinicius"
npm install
npm run dev
# → http://localhost:5173
```

---

## 🗄 Banco de Dados

PostgreSQL 16 com 9 tabelas, 3 views e triggers automáticos.

### Tabelas

| Tabela | Finalidade |
|---|---|
| `clients` | Clientes (nome, telefone, email, CPF, status, notas) |
| `appointments` | Agendamentos (data, hora, status, pagamento, duração, Google Event ID) |
| `services` | Serviços (nome, duração, buffer, preço, cor) |
| `transactions` | Lançamentos financeiros (receita/despesa, método, categoria, snapshot) |
| `business_hours` | Horários de funcionamento por dia da semana |
| `settings` | Configurações chave/valor (meta, empresa, credenciais, automações) |
| `notifications` | Notificações do sistema (tipo, título, mensagem, lida) |
| `integrations` | Integrações cadastradas (webhook, n8n, Google) com config JSONB |
| `users` | Usuários do sistema (email, senha hash, role) |

### Views

| View | Finalidade |
|---|---|
| `v_clients` | Total de visitas, gasto acumulado e última visita por cliente |
| `v_month_stats` | Faturamento mensal, despesas, agendamentos e clientes únicos |
| `v_daily_stats` | Agrupamento diário de métricas |

### Triggers

- `trigger_set_updated_at` — Atualiza automaticamente o campo `updated_at` antes de qualquer UPDATE nas tabelas principais.

---

## 🚀 Instalação

> `Aplicativos/instalacao/`

### Opção 1 — Docker (Recomendado)

O projeto possui um instalador interativo que detecta seu SO e configura tudo automaticamente:

```bash
cd "Aplicativos/instalacao"
chmod +x install.sh
./install.sh
```

O script `install.sh`:
- Detecta a distribuição Linux (Ubuntu, Debian, Pop!_OS, Mint, Arch, Manjaro, Fedora, RHEL, openSUSE) ou macOS
- Instala Docker e Docker Compose se necessário
- Detecta o IP da rede local para acesso por celulares e outros dispositivos
- Gera os arquivos `.env` automaticamente
- Sobe os 3 contêineres com healthcheck

#### Contêineres Docker Compose

| Serviço | Imagem Base | Porta |
|---|---|---|
| `beautyflow-postgres` | `postgres:16-alpine` | `5432` |
| `crm-backend` | `python:3.11-slim` | `3001` |
| `agendamento-app` | `node:20-alpine` → `nginx:alpine` | `5173:80` |

### Opção 2 — Windows

```cmd
cd Aplicativos\instalacao
install.bat
```

### Opção 3 — Manual (Desenvolvimento)

**Pré-requisitos:**
- Python 3.11+
- Node.js 20+
- npm
- PostgreSQL 16 (local ou cloud)

```bash
# 1. Banco de dados
psql -U postgres -c "CREATE DATABASE beautyflow;"
psql -U postgres -d beautyflow -f "Aplicativos/CRM BeautyFlow/backend/db/schema.sql"

# 2. Backend CRM
cd "Aplicativos/CRM BeautyFlow/backend"
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python run.py

# 3. Portal de Agendamento (novo terminal)
cd "Aplicativos/agendamento Vinicius"
npm install
npm run dev
```

### Scripts Disponíveis

| Script | Plataforma | Finalidade |
|---|---|---|
| `install.sh` | Linux / macOS | Instalador interativo completo |
| `install.bat` | Windows | Launcher Docker Desktop |
| `start.sh` | Linux / macOS | Inicia contêineres já construídos |
| `docker-compose.yml` | Todos | Orquestração dos 3 serviços |

---

## 🏗 Arquitetura de Produção

```
                        Internet
                           │
                      ┌────▼────┐
                      │  Nginx  │  porta 80/443 (SSL)
                      │  Proxy  │
                      └────┬────┘
                           │
                ┌──────────┴──────────┐
                │                     │
           ┌────▼─────┐        ┌─────▼───────┐
           │   CRM    │        │ Agendamento │
           │  :3001   │        │  :80/5173   │
           │ (Flask)  │        │(React/Nginx)│
           └────┬─────┘        └─────▲───────┘
                │                     │
                │   ┌─── WebSocket ───┘
                │   │   (Socket.IO)
                │   │
           ┌────▼───▼─────────────────────┐
           │   PostgreSQL 16              │
           │   Docker ou Cloud            │
           └──────────────────────────────┘
                │               │
           ┌────▼────┐    ┌────▼──────────┐
           │  n8n    │    │ Google        │
           │Webhooks │    │ Calendar API  │
           └─────────┘    └───────────────┘
```

---

## 🔐 Variáveis de Ambiente

### CRM Backend (`Aplicativos/CRM BeautyFlow/backend/.env`)

```env
DATABASE_URL=postgresql://beautyflow:CRMbeauty@localhost:5432/beautyflow?sslmode=disable
POSTGRES_PASSWORD=CRMbeauty
N8N_WEBHOOK_URL=https://seu-n8n.com/webhook/calendar-webhook
```

### Portal de Agendamento (`Aplicativos/agendamento Vinicius/.env`)

```env
VITE_API_URL=http://localhost:3001/api
```

### Docker Compose (`Aplicativos/instalacao/.env`)

```env
VITE_API_URL=http://<IP_DA_MÁQUINA>:3001/api
```

---

## 📚 Documentação

| Arquivo | Descrição |
|---|---|
| `FERRAMENTAS_E_FUNCIONALIDADES.txt` | Documento mestre com mapeamento exaustivo de todo o ecossistema |
| `docs/resumo_tecnico.md` | Arquitetura técnica detalhada, endpoints, fórmulas financeiras, gráficos SVG |
| `docs/ux(Mirian Original).html` | Protótipo HTML/CSS original da interface de referência |
| `Aplicativos/instalacao/tutorial.md` | Guia completo de deploy em servidor Ubuntu (Nginx, SSL, systemd, firewall, backup) |
| `diagrama_beautyflow.svg` | Diagrama vetorial da arquitetura geral |

---

## 📄 Licença

Projeto de extensão universitária — SENAI. Uso educacional.
