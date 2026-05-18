# BeautyFlow — Instalador Unificado

Instala o **BeautyFlow CRM** (gestão do salão) e/ou o **BeautyFlow Agendamento** (painel do cliente) com banco de dados Supabase.

---

## Índice

1. [Pré-requisitos](#1-pré-requisitos)
2. [Como usar](#2-como-usar)
   - [Linux / macOS](#21-linux--macos)
   - [Windows](#22-windows)
   - [Docker](#23-docker)
3. [O que é instalado](#3-o-que-é-instalado)
4. [Estrutura](#4-estrutura)

---

## 1. Pré-requisitos

| Recurso     | Native Linux/macOS | Native Windows | Docker |
|-------------|-------------------|----------------|--------|
| Git         | ✓ obrigatório     | ✓ obrigatório  | ✓      |
| Python 3.10+| ✓ (CRM)           | ✓ (CRM)        | —      |
| Node.js 20+ | ✓ (Agendamento)  | ✓ (Agendamento)| —      |
| Docker 24+  | —                 | —              | ✓      |
| Conta Supabase | ✓ obrigatório | ✓ obrigatório  | ✓      |

---

## 2. Como usar

### 2.1. Linux / macOS

```bash
# Clonar
git clone https://github.com/Sallesg82/Extensao_universitaria_Manicure.git
cd Extensao_universitaria_Manicure/Aplicativos/instalacao

# Executar instalador
bash install.sh
```

O menu pergunta qual app instalar:
- **1** — CRM (Python/Flask, porta 3001)
- **2** — Agendamento (React/Vite, porta 5173)
- **3** — Ambos (recomendado)
- **4** — Docker (ambos em container)

O instalador:
1. Configura as credenciais do Supabase (banco de dados na nuvem)
2. Instala as dependências do sistema (git, python3, node)
3. Configura o(s) app(s) escolhido(s)
4. Ao final, mostra os endereços para acessar

```bash
# Iniciar após instalação
bash start.sh         # inicia ambos
bash start.sh crm     # só CRM
bash start.sh agenda  # só agendamento
```

### 2.2. Windows

1. Abra a pasta `instalacao/` no Explorer
2. Dê **duplo clique** em `install.bat`
3. Escolha qual app instalar: **CRM**, **Agendamento** ou **Ambos**
4. Escolha o método: **Docker** ou **Nativo**
5. O instalador verifica dependências e orienta o download se necessário
6. Ao final, mostra os endereços com botões "Abrir"

### 2.3. Docker

```bash
cd Extensao_universitaria_Manicure/Aplicativos/instalacao
docker compose build
docker compose up -d
```

> O Supabase é usado como banco de dados. Para resetar os dados, acesse o SQL Editor do Supabase e recrie as tabelas.

---

## 3. O que é instalado

### Banco de Dados
- **Supabase** — tabelas: `clients`, `appointments`, `services`, `transactions`, `settings`, `users`
- Schema disponível em `backend/db/supabase_schema.sql`

### BeautyFlow CRM (se escolhido)
- **Backend:** Flask (Python) na porta `3001`
- **Frontend:** HTML/CSS/JS com dashboard, agenda, clientes, financeiro, relatórios
- **API REST:** `/api/clients/`, `/api/appointments/`, `/api/services/`, `/api/stats`
- **Banco:** Supabase (nuvem)

### BeautyFlow Agendamento (se escolhido)
- **Frontend:** React + Vite na porta `5173`
- **Consome** a API do CRM em `localhost:3001`
- **Serviços:** fluxo de agendamento para o cliente final

---

## 4. Estrutura

```
Aplicativos/
├── instalacao/               ← Instalador unificado
│   ├── install.sh            Linux/macOS
│   ├── start.sh              Iniciar servidores
│   ├── install.bat           Launcher Windows
│   ├── install_windows.ps1   GUI Windows
│   ├── docker-compose.yml    Docker (CRM + Agendamento)
│   └── README.md
│
├── CRM BeautyFlow/   ← Aplicativo CRM
│   ├── backend/
│   │   └── db/
│   │       └── supabase_schema.sql  ← Schema do banco
│   └── instalacao/           (instalador individual)
│
└── agendamento Vinicius/     ← Aplicativo Agendamento
    └── instalacao/           (instalador individual)
```
