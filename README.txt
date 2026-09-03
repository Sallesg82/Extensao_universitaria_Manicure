================================================================================
BEAUTYFLOW — SISTEMA DE GESTÃO PARA SALÕES DE BELEZA
================================================================================

Projeto de Extensão Universitária — SENAI

Sistema completo de gestão para salões de beleza composto por dois aplicativos
integrados: um CRM de gestão para o profissional e um portal de agendamento
online para os clientes, conectados em tempo real via WebSockets.

================================================================================
VISÃO GERAL
================================================================================

  CRM BeautyFlow         -> Painel completo de gestão (porta 3001)
  Portal de Agendamento  -> Interface conversacional para clientes (porta 5173)

Ambos se comunicam em tempo real — quando um cliente agenda pelo portal,
o profissional recebe a notificação instantaneamente no CRM.

================================================================================
TECNOLOGIAS UTILIZADAS
================================================================================

[ Backend ]
  Python 3.11+                -> Linguagem principal do servidor
  Flask 3.0.3                 -> Framework web (API REST + frontend SPA)
  Flask-SocketIO 5.3.6        -> WebSockets para tempo real
  Flask-CORS 4.0.1            -> Requisições cross-origin
  Psycopg 3 (3.1.18)          -> Driver nativo PostgreSQL com connection pool
  Werkzeug                    -> Hash de senhas (PBKDF2/SHA-256)
  Google API Client 2.133.0   -> Integração OAuth 2.0 + Google Calendar API v3
  Requests 2.32.3             -> Webhooks HTTP (n8n e integrações externas)
  Python-Dotenv 1.0.1         -> Gerenciamento de variáveis de ambiente

[ Frontend — CRM ]
  HTML5 Semântico             -> Estrutura da SPA
  CSS3 (5.400+ linhas)        -> Design system com variáveis, temas e modo escuro
  JavaScript ES6+ (~4.000 linhas) -> Lógica reativa sem frameworks
  Socket.IO Client 4.7.5      -> Atualizações em tempo real
  SVG Nativo                  -> 11 tipos de gráficos sem bibliotecas externas
  Google Fonts                -> DM Serif Display + DM Sans / Inter

[ Frontend — Portal de Agendamento ]
  React 19.2                  -> Biblioteca de UI
  Vite 8.0                    -> Build tool e dev server
  Tailwind CSS 4.2            -> Framework de estilização utilitária
  Socket.IO Client 4.8.3      -> Comunicação em tempo real com o CRM
  ESLint 10.2                 -> Linting e qualidade de código

[ Banco de Dados ]
  PostgreSQL 16               -> Banco relacional (via Docker ou cloud)

[ DevOps e Infraestrutura ]
  Docker                      -> Conteinerização dos serviços
  Docker Compose              -> Orquestração (PostgreSQL + CRM + Agendamento)
  Nginx                       -> Reverse proxy e servidor estático (produção)
  n8n                         -> Automação de workflows via webhooks

================================================================================
1. CRM BEAUTYFLOW
================================================================================

Localização: Aplicativos/CRM BeautyFlow/ (Porta 3001)

Painel completo de gestão para o profissional. O backend Flask serve tanto a
API REST quanto o frontend SPA em HTML/CSS/JS puro — sem necessidade de build.

--- MÓDULOS E FUNCIONALIDADES ---

[Dashboard]
  - Cards: Receita Hoje, Atendimentos, Clientes Ativos, Ticket Médio
  - Gráfico de barras semanal de faturamento
  - Ranking Top 5 serviços realizados
  - Barra de progresso da meta mensal
  - Mapa de Calor (Heatmap) 6 dias x 10 horários (horários de pico)
  - Lista de agendamentos do dia em tempo real
  - Pagamentos recentes
  - Alertas de clientes inativos com potencial de receita
  - Seletor de período (7, 30, 90, 365 dias)

[Agenda Interativa]
  - 4 modos: Dia (slots 30min), Semana (3/5/7 dias), Mês, Ano
  - Navegação temporal (anterior/próximo/hoje)
  - Clique direto em horário livre para agendar
  - Validação automática de horários e conflitos
  - Status de pagamento (Pago / Não Pago) na agenda
  - Bloqueio visual de dias de folga
  - Sincronização bidirecional com Google Calendar
  - Atualizações em tempo real via WebSocket

[Gestão de Clientes]
  - Busca em tempo real por nome ou telefone
  - Filtros: Todos, Frequentes, Novos, Inativos (30+ dias), Regulares, Inadimplentes
  - Ficha: avatar, total visitas, total gasto, ticket médio, última visita
  - Histórico cronológico completo de agendamentos
  - Serviços mais consumidos por cliente
  - Ações: cadastrar, editar, excluir, marcar como inadimplente

[Gestão de Serviços]
  - CRUD: nome, duração (min), buffer/intervalo, preço (R$), cor hexadecimal
  - Cor do serviço refletida nos cards da agenda

[Módulo Financeiro]
  - KPIs: Receita Mensal, Despesas, Lucro Líquido, Margem %
  - Gráfico diário comparativo Receitas x Despesas
  - Gráfico Donut SVG de receita por serviço
  - Lançamentos manuais (Pix, Dinheiro, Cartão Crédito/Débito)
  - Snapshot imutável de receita (nome do cliente preservado se excluído)
  - Extrato completo de transações

[Controle de Despesas]
  - Métricas: Total, Maior Despesa, Categoria mais custosa, Média
  - Gráfico horizontal por categoria (Aluguel, Produtos, Energia, Marketing, Salários, Outros)
  - Categorias de despesa customizáveis

[Relatórios e Exportação PDF]
  - Gráfico SVG de tendência de receita com comparativo
  - Ranking Top 5 clientes e serviços mais rentáveis
  - Mapa de calor de horários
  - Exportação em PDF profissional com cabeçalho oficial (Razão Social, CNPJ)
  - Seletor de período (7, 30, 90 dias, Ano)

[Metas]
  - Meta mensal customizável (padrão R$ 7.000)
  - Barra de progresso em tempo real
  - Notificação automática ao atingir

[Gestão de Usuários]
  - CRUD de operadores/administradores
  - Login por e-mail/senha com hash PBKDF2/SHA-256
  - Auto-criação de admin padrão se banco vazio
  - Troca de senha

[Central de Notificações e Automações]
  - Sino com badge de não lidas
  - Novos agendamentos, cancelamentos, meta atingida
  - Automações: confirmação automática, lembrete 24h/1h, confirmação Pix, aniversário

[Central de Integrações]
  - n8n: webhook URL, eventos (create/update/delete), headers, teste
  - Google Calendar: OAuth 2.0, sincronia bidirecional
  - Webhooks genéricos: cadastro com toggle ativo/inativo

[Configurações e Customização]
  - Perfil e troca de senha
  - Horários de funcionamento: Seg-Dom
  - 5 Temas: Azul, Esmeralda, Rosa, Púrpura, Luz do Sol
  - Modo Claro / Escuro
  - Tamanho de fonte: Pequeno, Médio, Grande
  - Layout: Sidebar vertical ou Topbar horizontal
  - Dados da empresa (CNPJ, Razão Social para PDFs)

--- EVENTOS WEBSOCKET ---

  appointment:created | appointment:updated | appointment:deleted
  client:created      | client:updated      | client:deleted
  service:changed
  transaction:created | transaction:updated | transaction:deleted
  data:changed        (evento genérico com tipo e ação)

--- ESTRUTURA ---

  CRM BeautyFlow/
  ├── backend/
  │   ├── run.py                  # Inicialização dev (porta 3001)
  │   ├── server.py               # App Flask + todas as rotas
  │   ├── wsgi.py                 # Entrada Gunicorn
  │   ├── ws.py                   # Instância Socket.IO
  │   ├── requirements.txt        # Dependências Python
  │   ├── .env                    # Variáveis de ambiente
  │   ├── db/
  │   │   ├── connection.py       # Pool de conexões PostgreSQL
  │   │   ├── database.py         # Queries e operações
  │   │   ├── repository.py       # Camada de repositório
  │   │   ├── schema.sql          # Schema principal
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

--- COMO INICIAR (DESENVOLVIMENTO) ---

  cd "Aplicativos/CRM BeautyFlow/backend"
  pip install -r requirements.txt
  python run.py
  # Acesso: http://localhost:3001

================================================================================
2. PORTAL DE AGENDAMENTO ONLINE
================================================================================

Localização: Aplicativos/Beatriz Gomes Studio/ (Porta 5173)

Interface para o cliente final com fluxo conversacional tipo assistente virtual.
O cliente escolhe serviço, data e horário — tudo refletido em tempo real no CRM.

--- FLUXO EM 3 ETAPAS ---

  1. Identificação   -> Nome completo e telefone/WhatsApp
  2. Preferências     -> Opt-in para lembretes e notificações
  3. Agendamento      -> Seleção de serviço, data e horário disponível

--- FUNCIONALIDADES ---

  - Catálogo de serviços dinâmico (vindo da API do CRM)
  - Calendário com bloqueio de datas passadas
  - Consulta inteligente de horários vagos (duração + buffer + colisões)
  - Card de resumo com serviço, valor, data por extenso, horário e duração
  - Modal de confirmação de sucesso
  - Cadastro/vinculação automática de cliente na base do CRM
  - Disparo de WebSocket para o CRM em tempo real
  - Design responsivo (tons de rosa, borgonha, dourado)
  - Animações de entrada nos balões de chat

--- COMPONENTES ---

  StudioHeader    -> Cabeçalho com logotipo e indicador de progresso
  AssistantBubble -> Balão da assistente virtual com avatar
  UserBubble      -> Balão de resposta do usuário
  ServiceCard     -> Card de seleção de serviço com selo Premium
  SuccessModal    -> Modal de confirmação com gradiente e resumo

--- ESTRUTURA ---

  Beatriz Gomes Studio/
  ├── index.html              # HTML5 de entrada
  ├── vite.config.js          # Config Vite (host: 0.0.0.0, porta 5173)
  ├── package.json            # Dependências npm
  ├── eslint.config.js        # ESLint Flat Config
  ├── .env                    # VITE_API_URL
  ├── src/
  │   ├── main.jsx            # Entrada React 19 (StrictMode)
  │   ├── App.jsx             # Componente principal + subcomponentes
  │   ├── index.css           # Design system completo + animações
  │   └── assets/hero.png
  └── public/
      ├── favicon.svg
      └── icons.svg

--- COMO INICIAR (DESENVOLVIMENTO) ---

  cd "Aplicativos/Beatriz Gomes Studio"
  npm install
  npm run dev
  # Acesso: http://localhost:5173

================================================================================
BANCO DE DADOS
================================================================================

PostgreSQL 16/18 com 9 tabelas, 3 views, 28 índices e triggers automáticos.
Carga automática de sementes (6 serviços, horários Seg-Dom, meta e admin).

--- TABELAS ---

  clients          -> Clientes (nome, telefone, email, CPF, status, notas)
  appointments     -> Agendamentos (data, hora, status, pagamento, duração)
  services         -> Serviços (nome, duração, buffer, preço, cor)
  transactions     -> Lançamentos financeiros (receita/despesa, método, snapshot)
  business_hours   -> Horários de funcionamento por dia da semana
  settings         -> Configurações chave/valor (meta, empresa, credenciais)
  notifications    -> Notificações (tipo, título, mensagem, lida)
  integrations     -> Integrações cadastradas (webhook, n8n, Google) config JSONB
  users            -> Usuários do sistema (email, senha hash, role)

--- VIEWS ---

  v_clients        -> Total visitas, gasto acumulado (paid), última visita
  v_month_stats    -> Faturamento mensal, despesas, agendamentos, clientes únicos
  v_daily_stats    -> Agrupamento diário de métricas

--- TRIGGERS ---

  trigger_set_updated_at -> Atualiza updated_at antes de qualquer UPDATE

================================================================================
INSTALAÇÃO E HUB DE GESTÃO (TUI)
================================================================================

Localização: Aplicativos/instalacao/

Hub interativo em terminal sem emojis com 10 opções principais e submenu
completo de banco de dados (backup, restore, verificação, reset).

--- OPÇÃO 1: LINUX / MACOS (HUB INTERATIVO) ---

  cd "Aplicativos/instalacao"
  chmod +x install.sh
  ./install.sh

--- OPÇÃO 2: WINDOWS (HUB INTERATIVO) ---

  cd Aplicativos\instalacao
  install.bat

--- SCRIPTS RÁPIDOS DE 1 CLIQUE (DIA A DIA) ---

  Iniciar: ./start.sh  (Linux/macOS)  ou  start.bat  (Windows)
  Parar:   ./stop.sh   (Linux/macOS)  ou  stop.bat   (Windows)

--- CONTÊINERES DOCKER COMPOSE ---

  PostgreSQL:     beautyflow-postgres     -> postgres:16-alpine (porta 5432)
  CRM Backend:    beautyflow-crm          -> python:3.11-slim   (porta 3001)
  Agendamento:    beautyflow-agendamento  -> nginx:alpine       (porta 5173:80)

--- OPÇÃO 3: MANUAL (DESENVOLVIMENTO) ---

  Pré-requisitos: Python 3.11+, Node.js 20+, npm, PostgreSQL 16/18

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
  cd "Aplicativos/Beatriz Gomes Studio"
  npm install
  npm run dev

--- SCRIPTS DISPONÍVEIS ---

  install.sh          -> Linux / macOS — Hub TUI completo de gestão e manutenção
  install.bat         -> Windows — Hub TUI completo de gestão e manutenção
  start.sh / start.bat -> Inicializador rápido de 1 clique
  stop.sh / stop.bat   -> Parada rápida de 1 clique sem perda de dados
  docker-compose.yml  -> Orquestração dos 3 serviços com healthchecks

================================================================================
ARQUITETURA DE PRODUÇÃO
================================================================================

                        Internet
                           |
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
           │   PostgreSQL 16 / 18         │
           │   Docker ou Cloud            │
           └──────────────────────────────┘
                │               │
           ┌────▼────┐    ┌────▼──────────┐
           │  n8n    │    │ Google        │
           │Webhooks │    │ Calendar API  │
           └─────────┘    └───────────────┘

================================================================================
VARIÁVEIS DE AMBIENTE
================================================================================

--- CRM Backend (Aplicativos/CRM BeautyFlow/backend/.env) ---

  DATABASE_URL=postgresql://postgres:beautyflow_pass@postgres:5432/beautyflow
  N8N_WEBHOOK_URL=https://mirianfiorini.app.n8n.cloud/webhook/calendar-webhook

--- Portal de Agendamento (Aplicativos/Beatriz Gomes Studio/.env) ---

  VITE_API_URL=http://localhost:3001/api

--- Docker Compose (Aplicativos/instalacao/.env) ---

  VITE_API_URL=http://<IP_OU_HOST>:3001/api

--- CREDENCIAIS PADRÃO DO SISTEMA ---
  Usuário: admin
  Senha:   admin

================================================================================
DOCUMENTAÇÃO
================================================================================

  FERRAMENTAS_E_FUNCIONALIDADES.txt -> Documento mestre do ecossistema
  docs/resumo_tecnico.md            -> Arquitetura técnica, endpoints, fórmulas
  docs/ux(Mirian Original).html     -> Protótipo HTML/CSS da interface
  Aplicativos/instalacao/tutorial.md -> Guia e documentação do hub e deploy
  diagrama_beautyflow.svg           -> Diagrama vetorial da arquitetura

================================================================================
LICENÇA
================================================================================

Projeto de extensão universitária — SENAI. Uso educacional.

