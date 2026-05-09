# BeautyFlow Agendamento

Painel de agendamento online para clientes do salão. Conecta ao **BeautyFlow CRM** (porta 3001).

---

## Índice

1. [Pré-requisitos](#1-pré-requisitos)
2. [Instalação](#2-instalação)
   - [2.1. Native (Node.js direto)](#21-native-nodejs-direto)
   - [2.2. Windows (Instalador Gráfico)](#22-windows-instalador-gráfico)
   - [2.3. Docker](#23-docker)
3. [Execução](#3-execução)
   - [3.1. Native](#31-native)
   - [3.2. Docker](#32-docker)
4. [API](#4-api)
5. [Estrutura](#5-estrutura)

---

## 1. Pré-requisitos

| Recurso   | Versão Mínima | Obrigatório       |
|-----------|---------------|-------------------|
| Git       | Qualquer      | Sempre            |
| Node.js   | 20+           | Instalação Native |
| npm       | 9+            | Instalação Native |
| Docker    | 24+           | Instalação Docker |

Sistema operacional: Linux, macOS ou Windows.

> **IMPORTANTE:** O [BeautyFlow CRM](https://github.com/Sallesg82/Extensao_universitaria_Manicure) precisa estar rodando em **http://localhost:3001** para o agendamento funcionar.

---

## 2. Instalação

### 2.1. Native (Node.js direto)

#### 2.1.1. Clonar o repositório

```bash
git clone https://github.com/Sallesg82/Extensao_universitaria_Manicure.git
cd "Extensao_universitaria_Manicure/Aplicativos/agendamento Vinicius/instalacao"
```

#### 2.1.2. Executar o instalador

```bash
bash install.sh
```

O script faz automaticamente:

1. **Verifica** se Node.js e npm estão instalados
2. **Instala** via apt (Linux) caso necessário (pergunta antes)
3. **Clona** o repositório se não estiver dentro dele
4. Executa `npm install`
5. Executa `npx vite build`

#### 2.1.3. Instalação manual passo a passo

```bash
# Na raiz do projeto
npm install
npm run dev
```

---

### 2.2. Windows (Instalador Gráfico)

1. Abra a pasta `instalacao/` no Explorer
2. Dê **duplo clique** em `install.bat`
3. Escolha o método:
   - **Docker** — container nginx para produção
   - **Node.js** — dev server com Vite
4. Ao final, mostra **http://localhost:5173** com botão "Abrir no navegador"

---

### 2.3. Docker

```bash
cd "Extensao_universitaria_Manicure/Aplicativos/agendamento Vinicius/instalacao"
docker compose build
docker compose up -d
```

Acessar: **http://localhost:5173**

Para rodar junto com o CRM, descomente o serviço `crm` no `docker-compose.yml`.

---

## 3. Execução

### 3.1. Native

```bash
# Servidor de desenvolvimento
npm run dev

# Preview do build
npm run preview
```

O servidor será iniciado em **http://localhost:5173**.

### 3.2. Docker

```bash
docker compose up -d        # Iniciar
docker compose logs -f      # Logs
docker compose down         # Parar
```

---

## 4. API

O agendamento consome a API do CRM em `http://localhost:3001/api`.

| Método | Rota                    | Descrição                  |
|--------|-------------------------|----------------------------|
| GET    | `/api/clients/`         | Listar clientes            |
| POST   | `/api/clients/`         | Criar cliente              |
| GET    | `/api/services/`        | Listar serviços            |
| POST   | `/api/services/`        | Criar serviço              |
| GET    | `/api/appointments/`    | Listar agendamentos        |
| POST   | `/api/appointments/`    | Criar agendamento          |

---

## 5. Estrutura

```
agendamento Vinicius/
├── src/                  # Código-fonte React
│   ├── App.jsx           # Componente principal (fluxo de agendamento)
│   ├── main.jsx          # Entry point
│   └── App.css           # Estilos
├── index.html
├── package.json
├── vite.config.js
└── instalacao/           # Instaladores
    ├── install.sh        # Linux/macOS
    ├── start.sh          # Iniciar servidor
    ├── install.bat       # Launcher Windows
    ├── install_windows.ps1  # Instalador gráfico Windows
    ├── Dockerfile        # Build Docker (nginx)
    ├── docker-compose.yml
    └── README.md         # Este manual
```
