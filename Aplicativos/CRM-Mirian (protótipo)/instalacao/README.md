# BeautyFlow CRM

CRM para salão de beleza — gestão de clientes, agendamentos, financeiro e relatórios.

---

## Índice

1. [Pré-requisitos](#1-pré-requisitos)
2. [Instalação](#2-instalação)
    - [2.1. Native (Python direto)](#21-native-python-direto)
    - [2.2. Windows (Instalador Gráfico)](#22-windows-instalador-gráfico)
    - [2.3. Docker](#23-docker)
3. [Execução](#3-execução)
   - [3.1. Native](#31-native)
   - [3.2. Docker](#32-docker)
4. [Integrações via Docker](#4-integrações-via-docker)
5. [Estrutura do Projeto](#5-estrutura-do-projeto)
6. [API REST](#6-api-rest)
7. [Funcionalidades](#7-funcionalidades)
8. [Personalização](#8-personalização)
9. [Manutenção do Manual](#9-manutenção-do-manual)
10. [Solução de Problemas](#10-solução-de-problemas)

---

## 1. Pré-requisitos

| Recurso      | Versão Mínima | Obrigatório        |
|-------------|---------------|--------------------|
| Git         | Qualquer      | Sempre             |
| Python      | 3.10+         | Instalação Native  |
| Docker      | 24+           | Instalação Docker  |
| docker compose | 2.0+       | Instalação Docker  |

Sistema operacional: Linux, macOS ou Windows.

Verifique sua instalação:

```bash
python3 --version       # Native
git --version
docker --version        # Docker
docker compose version  # Docker
```

---

## 2. Instalação

### 2.1. Native (Python direto)

#### 2.1.1. Clonar o repositório

```bash
git clone https://github.com/Sallesg82/Extensao_universitaria_Manicure.git
cd "Extensao_universitaria_Manicure/CRM-Mirian (protótipo)/instalacao"
```

#### 2.1.2. Executar o instalador

```bash
bash install.sh
```

O script `install.sh` faz automaticamente:

1. **Verifica** se Python 3 está instalado
2. **Cria** um ambiente virtual Python em `backend/.venv/`
3. **Instala** as dependências (Flask, Flask-CORS)
4. **Inicializa** o banco SQLite com dados de demonstração (9 clientes, 16 agendamentos, 8 serviços, transações financeiras)

> O banco de dados fica em `backend/db/beautyflow.db`. Para usar o banco compartilhado com o app de agendamento, defina a variável de ambiente `BEAUTYFLOW_DB_PATH` antes de iniciar.

#### 2.1.3. Instalação manual passo a passo

Caso prefira instalar manualmente (da raiz do projeto):

```bash
# 1. Criar ambiente virtual
python3 -m venv backend/.venv

# 2. Ativar o ambiente
source backend/.venv/bin/activate

# 3. Instalar dependências
pip install flask flask-cors

# 4. Inicializar o banco
python -c "
import sys; sys.path.insert(0, 'backend')
from db.database import get_db
get_db().close()
"
```

> **Windows (PowerShell, sem WSL):**
> ```powershell
> python -m venv backend\.venv
> backend\.venv\Scripts\pip install flask flask-cors
> backend\.venv\Scripts\python -c "import sys; sys.path.insert(0, 'backend'); from db.database import get_db; get_db().close()"
> backend\.venv\Scripts\python backend\server.py
> ```

---

### 2.2. Windows (Instalador Gráfico)

No Windows 10/11, basta executar o instalador com interface gráfica:

1. Abra a pasta `instalacao/` no Explorer
2. Dê um **duplo clique** em `install.bat`
3. Escolha o método de instalação:
   - **Docker** (recomendado) — container isolado, sem poluir o sistema
   - **WSL + Python** — usa o Windows Subsystem for Linux
4. O instalador verifica as dependências e orienta o download se necessário
5. Ao final, mostra o endereço **http://localhost:3001** e oferece "Abrir no navegador"

> **Pré-requisitos:** Windows 10/11 com PowerShell 5.1+.  
> Para o método Docker, instale [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/).  
> Para o método WSL, siga as instruções em https://learn.microsoft.com/pt-br/windows/wsl/install.

---

### 2.3. Docker

A instalação via Docker empacota o CRM em um container isolado. Além disso, o
`docker-compose.yml` já inclui (comentados) serviços de integração como n8n
(WhatsApp), PostgreSQL e Redis — basta descomentar para ativar.

#### 2.2.1. Clonar o repositório

```bash
git clone https://github.com/Sallesg82/Extensao_universitaria_Manicure.git
cd "Extensao_universitaria_Manicure/CRM-Mirian (protótipo)/instalacao"
```

#### 2.2.2. Build da imagem

```bash
docker compose build
```

#### 2.2.3. Iniciar o container

```bash
docker compose up -d
```

O servidor estará disponível em **http://localhost:3001**.

Para acompanhar os logs:

```bash
docker compose logs -f
```

#### 2.2.4. Parar o container

```bash
docker compose down
```

Para parar **e remover o volume** com o banco de dados:

```bash
docker compose down -v
```

#### 2.2.5. Resetar os dados

```bash
docker compose down -v
docker compose up -d   # recria o banco com seed automático
```

---

## 3. Execução

### 3.1. Native

```bash
# Na pasta instalacao/
bash start.sh
```

O servidor será iniciado em **http://localhost:3001**.

Pressione `Ctrl+C` para parar.

### 3.2. Docker

```bash
# Na pasta instalacao/
docker compose up -d
```

Para parar:

```bash
docker compose down
```

### 3.3. Acessar a plataforma

Abra o navegador em **[http://localhost:3001](http://localhost:3001)**.

A plataforma carregará automaticamente:
- Dashboard com métricas do dia (receita, atendimentos, clientes ativos)
- Lista de clientes carregada da API
- Agenda semanal com agendamentos do banco de dados
- Temas, modo escuro e layout salvos no navegador

---

## 4. Integrações via Docker

O `docker-compose.yml` foi projetado para ser o ponto de partida de todas as
integrações do CRM. Os serviços ficam todos na mesma rede Docker
(`beautyflow_net`), podendo se comunicar livremente.

### 4.1. Serviços disponíveis (comentados)

| Serviço     | Imagem               | Porta  | Finalidade                              |
|-------------|----------------------|--------|-----------------------------------------|
| **n8n**     | `n8nio/n8n`          | 5678   | Automação WhatsApp, lembretes, notificações |
| **PostgreSQL** | `postgres:17`     | 5432   | Banco relacional para produção (substitui SQLite) |
| **Redis**   | `redis:7-alpine`     | 6379   | Cache e fila de processamento assíncrono |
| **ngrok**   | `ngrok/ngrok`        | 4040   | Tunnel HTTP para testar webhooks localmente |

### 4.2. Como ativar uma integração

Edite o `docker-compose.yml`, remova os comentários (`#`) do serviço desejado
e recrie os containers:

```bash
# 1. Editar docker-compose.yml (descomentar o serviço)
# 2. Recriar os containers
docker compose up -d
```

### 4.3. Exemplo: WhatsApp + n8n

O n8n permite criar fluxos de automação visual (como Zapier) para enviar
mensagens WhatsApp automaticamente:

| Fluxo                      | Gatilho                                  |
|----------------------------|------------------------------------------|
| Confirmação de agendamento | Webhook chamado pela API do CRM          |
| Lembrete 24h antes         | Agendamento no n8n + consulta à API      |
| Aniversário de cliente     | Consulta agendada à API `/api/clients/`  |

Para conectar o n8n ao CRM:

1. Descomente o serviço `n8n` no `docker-compose.yml`
2. Execute `docker compose up -d`
3. Acesse `http://localhost:5678` para configurar o n8n
4. Crie um webhook apontando para `http://app:3001/api/appointments/`

> **Nota:** dentro da rede Docker, o CRM é acessível pelo nome do serviço `app`
> (porta 3001). O ngrok pode expor o CRM para a internet se necessário.

### 4.4. Exemplo: Google Agenda

A sincronização com Google Agenda pode ser feita via:

1. Um webhook no n8n que escuta novos agendamentos na API
2. O n8n chama a API do Google Agenda para criar o evento
3. O webhook do Google Agenda (push notifications) atualiza o CRM

### 4.5. Diagrama de rede Docker

```
┌─────────────────────────────────────────┐
│           beautyflow_net                │
│                                         │
│  ┌──────────┐                           │
│  │   app    │  ← CRM Flask              │
│  │ :3001    │                           │
│  └────┬─────┘                           │
│       │ conexão interna                 │
│  ┌────▼─────┐  ┌──────────┐  ┌────────┐ │
│  │   n8n   │  │ postgres │  │ redis  │ │
│  │ :5678   │  │ :5432    │  │ :6379  │ │
│  └─────────┘  └──────────┘  └────────┘ │
│       │                                 │
│  ┌────▼─────┐                           │
│  │  ngrok   │  ──► internet             │
│  └──────────┘                           │
└─────────────────────────────────────────┘
```

```
CRM-Mirian (protótipo)/
├── src/                    # Front-end (SPA preview)
│   ├── index.html          # Página principal
│   ├── css/
│   │   └── style.css       # Todos os estilos + temas + dark mode
│   └── js/
│       └── app.js          # Lógica do front-end (SPA, fetch da API)
│
├── backend/                # API REST
│   ├── server.py           # Servidor Flask (API + arquivos estáticos)
│   ├── run.py              # Entry point alternativo
│   ├── db/
│   │   ├── database.py     # Conexão SQLite, schema, seed data
│   │   └── beautyflow.db   # Banco de dados (criado na 1ª execução)
│   ├── routes/
│   │   ├── clients.py      # CRUD de clientes
│   │   ├── appointments.py # CRUD de agendamentos
│   │   └── services.py     # CRUD de serviços
│   └── middleware/
│       └── validation.py   # Validação de dados de entrada
│
├── instalacao/             # Deploy e documentação
│   ├── install.sh          # Script de instalação nativa
│   ├── start.sh            # Script para iniciar nativamente
│   ├── Dockerfile          # Imagem Docker do CRM
│   ├── docker-compose.yml  # Orquestração + integrações
│   ├── .dockerignore
│   └── README.md           # Este manual
│
└── docs/
    └── ux(Mirian Original).html  # Protótipo original do UI/UX
```

### 5.1. Fluxo de dados

```
Navegador (index.html)
    ↓  fetch()  ↑  JSON
Servidor Flask (server.py)
    ↓              ↑
SQLite (backend/db/beautyflow.db)
```

O front-end faz requisições `fetch()` para a API REST. O servidor processa e retorna JSON. O banco SQLite é acessado diretamente pelo servidor.

---

## 6. API REST

A API roda em `http://localhost:3001/api/`.

### 6.1. Clientes

| Método | Rota                | Descrição                     |
|--------|---------------------|-------------------------------|
| GET    | `/api/clients/`     | Lista todos os clientes       |
| GET    | `/api/clients/<id>` | Detalhes + agendamentos       |
| POST   | `/api/clients/`     | Criar novo cliente            |
| PUT    | `/api/clients/<id>` | Atualizar cliente             |
| DELETE | `/api/clients/<id>` | Remover cliente               |

**POST /api/clients/** — corpo:

```json
{
  "name": "Maria Silva",
  "phone": "(11) 98765-4321",
  "email": "maria@email.com",
  "status": "regular"
}
```

### 6.2. Agendamentos

| Método | Rota                      | Descrição                          |
|--------|---------------------------|------------------------------------|
| GET    | `/api/appointments/`      | Lista (aceita filtros)             |
| GET    | `/api/appointments/<id>`  | Detalhes do agendamento            |
| POST   | `/api/appointments/`      | Criar novo agendamento             |
| PUT    | `/api/appointments/<id>`  | Atualizar agendamento              |
| DELETE | `/api/appointments/<id>`  | Remover agendamento                |

**Filtros da listagem** (query params):

| Parâmetro    | Exemplo                | Descrição                     |
|--------------|------------------------|-------------------------------|
| `date`       | `?date=2026-05-01`     | Agendamentos de uma data      |
| `date_from`  | `?date_from=2026-04-28`| A partir de uma data          |
| `date_to`    | `?date_to=2026-05-04`  | Até uma data                  |
| `client_id`  | `?client_id=1`         | Agendamentos de um cliente    |
| `status`     | `?status=confirmed`    | Filtrar por status            |

**POST /api/appointments/** — corpo:

```json
{
  "client_id": 1,
  "service": "Manicure Simples",
  "appointment_date": "2026-05-10",
  "appointment_time": "14:00",
  "price": 35,
  "status": "confirmed",
  "duration": 40
}
```

### 6.3. Serviços

| Método | Rota                | Descrição                     |
|--------|---------------------|-------------------------------|
| GET    | `/api/services/`    | Lista todos os serviços       |
| POST   | `/api/services/`    | Criar novo serviço            |
| PUT    | `/api/services/<id>`| Atualizar serviço             |
| DELETE | `/api/services/<id>`| Remover serviço               |

### 6.4. Estatísticas (Dashboard)

| Método | Rota          | Descrição                         |
|--------|---------------|-----------------------------------|
| GET    | `/api/stats`  | Métricas, top clientes, agendamentos de hoje |

Resposta:

```json
{
  "today_revenue": 410.0,
  "today_count": 7,
  "active_clients": 84,
  "avg_ticket": 58.0,
  "month_revenue": 6840.0,
  "month_expenses": 1340.0,
  "top_clients": [ ... ],
  "today_appointments": [ ... ]
}
```

---

## 7. Funcionalidades

### 7.1. Front-end (SPA)

- **Dashboard:** métricas em tempo real, agendamentos do dia, fluxo de caixa
- **Agenda:** visualização semanal, eventos dinâmicos por horário
- **Clientes:** listagem com busca, detalhes com histórico de atendimentos
- **Financeiro:** receitas vs despesas, gráficos, lançamentos recentes
- **Relatórios:** tendência de receita, top clientes, serviços populares
- **Configurações:** perfil, horários, serviços, notificações, aparência

### 7.2. Personalização

- **5 temas:** Azul (padrão), Esmeralda, Rosa, Púrpura, Luz do Sol
- **Modo escuro:** independente por tema, cores harmoniosas (não cinza genérico)
- **Tamanho da fonte:** pequeno, médio, grande
- **Layout:** vertical (sidebar) ou horizontal (topbar)
- **Sidebar:** expansível/colapsável

As preferências ficam salvas no `localStorage` do navegador.

### 7.3. Dados de demonstração

Na primeira execução, o banco é populado com:

- **9 clientes** com históricos de atendimento
- **16 agendamentos** em múltiplas datas
- **8 serviços** (Manicure, Pedicure, Gel, Alongamento, etc.)
- **5 transações** financeiras

---

## 8. Personalização

### 8.1. Adicionar novo tema

Edite `css/style.css` e adicione no bloco de temas:

```css
[data-theme="meu-tema"] {
  --primary-500: #<cor>;
  --primary-600: #<cor>;
  --dark-bg-body: #<cor>;
  /* demais variáveis... */
}
```

Depois adicione a opção no HTML em `index.html` (seção de temas em Configurações).

### 8.2. Adicionar novo serviço

Via API:

```bash
curl -X POST http://localhost:3001/api/services/ \
  -H 'Content-Type: application/json' \
  -d '{"name":"Novo Serviço","duration":60,"price":50,"color":"#ff6600"}'
```

Ou edite o seed em `backend/db/database.py` e recrie o banco.

### 8.3. Adicionar nova integração no Docker

1. Adicione o serviço no `docker-compose.yml` seguindo o padrão dos existentes
2. Atualize o [diagrama de rede](#45-diagrama-de-rede-docker) se necessário
3. Adicione instruções nesta seção
4. Recrie os containers: `docker compose up -d`

---

## 9. Manutenção do Manual

> **Regra:** sempre que uma alteração significativa for feita no projeto (nova rota, novo
> arquivo, mudança de dependência, alteração na estrutura, novo comando), este manual
> deve ser atualizado na mesma pull request/commit.

### O que atualizar:

| Alteração | Seção do Manual |
|-----------|-----------------|
| Nova rota na API | [6. API REST](#6-api-rest) |
| Novo arquivo/pasta | [5. Estrutura do Projeto](#5-estrutura-do-projeto) |
| Nova dependência | [2.1.3. Instalação manual](#213-instalação-manual-passo-a-passo) e `install.sh` |
| Mudança no fluxo de dados | [5.1. Fluxo de dados](#51-fluxo-de-dados) |
| Nova funcionalidade | [7. Funcionalidades](#7-funcionalidades) |
| Mudança nos pré-requisitos | [1. Pré-requisitos](#1-pré-requisitos) |
| Novo script/comando | [3. Execução](#3-execução) |
| Problema conhecido | [10. Solução de Problemas](#10-solução-de-problemas) |
| Mudança no front-end | [7.1. Front-end (SPA)](#71-front-end-spa) |
| Nova opção de tema/config | [7.2. Personalização](#72-personalização) e [8. Personalização](#8-personalização) |
| Nova integração no Docker | [4. Integrações via Docker](#4-integrações-via-docker) e `docker-compose.yml` |

### Como atualizar:

1. Faça as alterações no código
2. Edite o `README.md` refletindo as mudanças
3. Se necessário, atualize o `install.sh` e/ou `docker-compose.yml`
4. Inclua as alterações do manual no mesmo commit das mudanças no código

---

## 10. Solução de Problemas

### 10.1. Porta 3001 já em uso

```bash
# Native
lsof -i :3001
kill <PID>

# Docker
docker compose down
```

### 10.2. Banco corrompido ou resetar dados

**Native:**

```bash
rm backend/db/beautyflow.db
bash start.sh   # recria automaticamente com seed
```

> O banco fica em `backend/db/beautyflow.db` (padrão) ou no caminho definido por `BEAUTYFLOW_DB_PATH`.

**Docker:**

```bash
docker compose down -v
docker compose up -d
```

### 10.3. Erro de permissão nos scripts

```bash
chmod +x install.sh start.sh
```

### 10.4. Ambiente virtual não encontrado (Native)

```bash
rm -rf backend/.venv
bash install.sh
```

### 10.5. Front-end não carrega dados

Abra o console do navegador (F12) e verifique:
- Erros de rede na aba "Network"
- Mensagens de erro em "Console"
- Se o servidor está rodando: `curl http://localhost:3001/api/stats`

### 10.6. Docker: permissão negada ao escrever no volume

No Linux, o container pode rodar como root e criar arquivos com permissão root.
Para resolver:

```bash
# Ajustar permissão da pasta do banco
sudo chown -R $USER:$USER backend/db/
```

Ou configure o `user:` no `docker-compose.yml`:

```yaml
services:
  app:
    user: "${UID:-1000}:${GID:-1000}"
```

---

Licença: MIT
