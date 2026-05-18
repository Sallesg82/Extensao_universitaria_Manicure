# Tutorial Completo — BeautyFlow CRM + Agendamento no Ubuntu Server

Guia de instalação e configuração do **BeautyFlow CRM** (gestão de salão) e **BeautyFlow Agendamento** (painel do cliente) em um servidor **Ubuntu Server**, com Supabase (self-hosted ou cloud), Nginx, SSL e systemd.

---

## Índice

1. [Visão geral da arquitetura](#1-visão-geral-da-arquitetura)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Preparação do servidor Ubuntu](#3-preparação-do-servidor-ubuntu)
4. [Opções de banco de dados (Supabase)](#4-opções-de-banco-de-dados-supabase)
   - [4.1 Supabase Cloud (recomendado para iniciantes)](#41-supabase-cloud-recomendado-para-iniciantes)
   - [4.2 Supabase self-hosted no servidor (Docker)](#42-supabase-self-hosted-no-servidor-docker)
5. [Clone do repositório](#5-clone-do-repositório)
6. [CRM — Backend Flask](#6-crm--backend-flask)
7. [Agendamento — Frontend React](#7-agendamento--frontend-react)
8. [Proxy reverso com Nginx + SSL](#8-proxy-reverso-com-nginx--ssl)
9. [Serviços systemd (auto-start)](#9-serviços-systemd-auto-start)
10. [Firewall UFW](#10-firewall-ufw)
11. [Acesso e primeiro uso](#11-acesso-e-primeiro-uso)
12. [Integração n8n](#12-integração-n8n)
13. [Manutenção e atualização](#13-manutenção-e-atualização)
14. [Resumo dos comandos](#14-resumo-dos-comandos)

---

## 1. Visão geral da arquitetura

```
                    Internet
                       │
                  ┌────▼────┐
                  │ Nginx   │  porta 80/443 (SSL)
                  │ Proxy   │
                  └────┬────┘
                       │
            ┌──────────┴──────────┐
            │                     │
       ┌────▼─────┐        ┌─────▼──────┐
       │  CRM     │        │ Agendamento │
       │ :3001    │        │ :5173       │
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

| Componente | Porta | Tecnologia |
|------------|-------|------------|
| CRM (backend) | 3001 | Python / Flask |
| CRM (frontend) | 3001 (servido pelo Flask) | HTML / CSS / JS |
| Agendamento | 5173 | React / Vite |
| Supabase | 5432 (PostgreSQL) + 8000 (API) | PostgreSQL + Go TrueAuth |
| Nginx | 80 / 443 | Proxy reverso + SSL |

---

## 2. Pré-requisitos

### Hardware mínimo recomendado

| Recurso | Cloud Supabase | Supabase self-hosted |
|---------|---------------|---------------------|
| CPU | 1 vCPU | 2 vCPUs |
| RAM | 1 GB | 4 GB |
| Disco | 10 GB | 20 GB |
| SO | Ubuntu 22.04+ | Ubuntu 22.04+ |

### Software necessário

```bash
# Ubuntu Server (tudo via apt)
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl python3 python3-venv python3-pip \
    nodejs npm nginx certbot python3-certbot-nginx ufw
```

### Versões mínimas

| Programa | Versão |
|----------|--------|
| Ubuntu | 22.04 LTS |
| Python | 3.10+ |
| Node.js | 18+ |
| Nginx | 1.18+ |
| Docker (opcional) | 24+ |

---

## 3. Preparação do servidor Ubuntu

### 3.1 Nome do servidor (hostname)

```bash
sudo hostnamectl set-hostname beautyflow
```

### 3.2 Fuso horário

```bash
sudo timedatectl set-timezone America/Sao_Paulo
```

### 3.3 Criar usuário deploy (recomendado)

```bash
sudo adduser deploy
sudo usermod -aG sudo deploy
su - deploy
```

> Todos os comandos abaixo assumem que você está logado como `deploy`.

---

## 4. Opções de banco de dados (Supabase)

### 4.1 Supabase Cloud (recomendado para iniciantes)

Mais simples — não consome recursos do servidor.

#### 4.1.1 Criar conta

1. Acesse https://supabase.com
2. Crie uma conta (GitHub ou email)
3. Crie um **novo projeto**:
   - **Name:** `beautyflow`
   - **Database Password:** anote em local seguro
   - **Region:** South America (São Paulo) — `southamerica-east1`
   - **Pricing Plan:** Free tier já funciona

#### 4.1.2 Obter credenciais

No dashboard do projeto, vá em **Project Settings → API**:

```
Project URL:     https://xxxxx.supabase.co      ← SUPABASE_URL
anon public:     eyJhbGciOiJIUzI1NiIs...        ← SUPABASE_ANON_KEY
service_role:    eyJhbGciOiJIUzI1NiIs...        ← SUPABASE_KEY
```

#### 4.1.3 Executar o schema SQL

1. No dashboard, vá em **SQL Editor**
2. Clique em **New Query**
3. Copie o conteúdo do arquivo:
   ```
   ~/Extensao_universitaria_Manicure/Aplicativos/CRM BeautyFlow/backend/db/supabase_schema.sql
   ```
4. Cole e execute (botão **Run** ou Ctrl+Enter)

---

### 4.2 Supabase self-hosted no servidor (Docker)

Para quem quer tudo no próprio servidor (maior controle, sem depender de nuvem).

#### 4.2.1 Instalar Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
# Faça logout e login para o grupo ter efeito
```

#### 4.2.2 Instalar Supabase via CLI

```bash
# Baixar Supabase CLI
wget https://github.com/supabase/cli/releases/download/v2.20.0/supabase_2.20.0_linux_amd64.deb
sudo dpkg -i supabase_2.20.0_linux_amd64.deb

# Iniciar serviços Supabase
cd ~
mkdir supabase-beautyflow && cd supabase-beautyflow
supabase init
supabase start
```

Na primeira execução, o Supabase baixa as imagens Docker. Anote a saída:

```
Started supabase local development setup.

         API URL: http://localhost:54321
          DB URL: postgresql://postgres:postgres@localhost:54322/postgres
      Studio URL: http://localhost:54323
    Inbucket URL: http://localhost:54324
      anon key: eyJhbGciOiJIUzI1NiIs...
service_role key: eyJhbGciOiJIUzI1NiIs...
```

#### 4.2.3 Alternativa: Supabase com docker-compose manual

Crie `~/supabase-docker/docker-compose.yml`:

```yaml
services:
  supabase-db:
    image: supabase/postgres:15.6.1.41
    environment:
      POSTGRES_PASSWORD: supabase
    ports:
      - "5432:5432"
    volumes:
      - ./data:/var/lib/postgresql/data
    restart: unless-stopped

  supabase-kong:
    image: kong:2.8.1
    ports:
      - "8000:8000"
      - "8443:8443"
    restart: unless-stopped
```

> ⚠️ **Recomendação:** Para produção, use o Supabase Cloud. O self-hosted requer manutenção e consome ~2 GB de RAM.

---

## 5. Clone do repositório

```bash
cd ~
git clone https://github.com/Sallesg82/Extensao_universitaria_Manicure.git
cd Extensao_universitaria_Manicure
```

---

## 6. CRM — Backend Flask

### 6.1 Ambiente virtual e dependências

```bash
cd "Aplicativos/CRM BeautyFlow/backend"

# Criar venv
python3 -m venv .venv

# Ativar e instalar
source .venv/bin/activate
pip install --upgrade pip
pip install flask flask-cors supabase httpx gunicorn
```

### 6.2 Configurar credenciais Supabase

Crie o arquivo `.env`:

```bash
nano .env
```

Conteúdo (ajuste com suas credenciais):

```env
SUPABASE_URL=https://seu-projeto.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIs...
SUPABASE_KEY=eyJhbGciOiJIUzI1NiIs...
```

> **Supabase self-hosted:**
> ```
> SUPABASE_URL=http://localhost:54321
> SUPABASE_KEY=eyJhbGciOiJIUzI1NiIs...  (service_role key do supabase start)
> ```

### 6.3 Executar schema SQL

Se escolheu **Supabase Cloud**, execute o schema pelo SQL Editor do dashboard.

Se escolheu **Supabase self-hosted**:

```bash
# Conectar direto no PostgreSQL
psql postgresql://postgres:postgres@localhost:54322/postgres \
  -f ~/Extensao_universitaria_Manicure/Aplicativos/CRM\ BeautyFlow/backend/db/supabase_schema.sql
```

Ou pelo Studio (http://localhost:54323), vá em **SQL Editor** e cole o conteúdo do arquivo.

### 6.4 Testar o CRM

```bash
cd ~/Extensao_universitaria_Manicure/Aplicativos/CRM\ BeautyFlow/backend
source .venv/bin/activate

# Desenvolvimento (Flask dev server)
python run.py

# Produção (Gunicorn — mais robusto)
.venv/bin/gunicorn -w 4 -b 0.0.0.0:3001 server:app
```

Acesse: `http://SEU_IP:3001`

---

## 7. Agendamento — Frontend React

### 7.1 Instalar dependências

```bash
cd ~/Extensao_universitaria_Manicure/Aplicativos/agendamento\ Vinicius
npm install
```

### 7.2 Configurar URL da API

Edite o arquivo `src/App.jsx` e altere a URL da API:

```js
const API = "http://SEU_IP:3001/api";
```

Para produção com Nginx (recomendado), use o caminho relativo:

```js
const API = "/api";  // Nginx fará o proxy
```

### 7.3 Testar o Agendamento

```bash
cd ~/Extensao_universitaria_Manicure/Aplicativos/agendamento\ Vinicius
npm run dev
```

Acesse: `http://SEU_IP:5173`

> ⚠️ O Agendamento depende do CRM rodando. Ambos devem estar ativos.

---

## 8. Proxy reverso com Nginx + SSL

### 8.1 Configurar Nginx

```bash
sudo nano /etc/nginx/sites-available/beautyflow
```

```nginx
server {
    listen 80;
    server_name seu-dominio.com;

    # CRM (Flask)
    location / {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_cache_bypass $http_upgrade;
    }

    # Agendamento (React/Vite)
    location /agendamento/ {
        proxy_pass http://127.0.0.1:5173/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
```

Ativar o site:

```bash
sudo ln -s /etc/nginx/sites-available/beautyflow /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 8.2 Configurar SSL com Let's Encrypt

```bash
sudo certbot --nginx -d seu-dominio.com
```

Renovação automática já vem configurada. Teste:

```bash
sudo certbot renew --dry-run
```

### 8.3 Acesso via domínio

| Serviço | URL |
|---------|-----|
| CRM | https://seu-dominio.com |
| Agendamento | https://seu-dominio.com/agendamento/ |

---

## 9. Serviços systemd (auto-start)

Para que os serviços iniciem automaticamente com o servidor e reiniciem se caírem.

### 9.1 Serviço do CRM

```bash
sudo nano /etc/systemd/system/beautyflow-crm.service
```

```ini
[Unit]
Description=BeautyFlow CRM
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/home/deploy/Extensao_universitaria_Manicure/Aplicativos/CRM BeautyFlow/backend
EnvironmentFile=/home/deploy/Extensao_universitaria_Manicure/Aplicativos/CRM BeautyFlow/backend/.env
ExecStart=/home/deploy/Extensao_universitaria_Manicure/Aplicativos/CRM BeautyFlow/backend/.venv/bin/gunicorn -w 4 -b 0.0.0.0:3001 server:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 9.2 Serviço do Agendamento

```bash
sudo nano /etc/systemd/system/beautyflow-agenda.service
```

```ini
[Unit]
Description=BeautyFlow Agendamento
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/home/deploy/Extensao_universitaria_Manicure/Aplicativos/agendamento Vinicius
ExecStart=/usr/bin/npm run dev
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 9.3 Ativar e iniciar

```bash
sudo systemctl daemon-reload
sudo systemctl enable beautyflow-crm beautyflow-agenda
sudo systemctl start beautyflow-crm beautyflow-agenda

# Verificar status
sudo systemctl status beautyflow-crm
sudo systemctl status beautyflow-agenda

# Ver logs
sudo journalctl -u beautyflow-crm -f
sudo journalctl -u beautyflow-agenda -f
```

---

## 10. Firewall UFW

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh                # porta 22
sudo ufw allow 'Nginx Full'       # portas 80 e 443
sudo ufw --force enable
sudo ufw status
```

Para desenvolvimento (acesso direto às portas):

```bash
sudo ufw allow 3001  # CRM
sudo ufw allow 5173  # Agendamento
```

> ⚠️ Em produção, libere apenas as portas 22 (SSH), 80 e 443 (Nginx).

---

## 11. Acesso e primeiro uso

1. Acesse `http://SEU_IP:3001` (ou o domínio configurado)
2. Crie sua conta na tela de registro
3. Pronto — o CRM BeautyFlow está operacional

**Agendamento:** acesse `http://SEU_IP:5173` (ou `/agendamento/` se configurou Nginx)

---

## 12. Integração n8n

### 12.1 Configurar webhook

No CRM, vá em **Configurações → Integrações**:

1. Clique em **+ Nova Integração**
2. Escolha o tipo:
   - **Webhook:** URL HTTP qualquer
   - **n8n:** URL do webhook do n8n
3. Cole a URL de destino
4. Clique em **Testar** para verificar a conexão
5. Salve

### 12.2 Selecionar eventos

Escolha quais ações disparam o webhook:

| Evento | Descrição |
|--------|-----------|
| create | Agendamento criado |
| update | Agendamento alterado |
| delete | Agendamento cancelado/excluído |

### 12.3 Exemplo de payload enviado

```json
{
  "action": "create",
  "appointment_id": 42,
  "client_name": "Ana Paula Silva",
  "client_phone": "(11) 98765-4321",
  "service": "Manicure + Pedicure",
  "price": 70.0,
  "status": "pending",
  "start_datetime": "2026-05-18T09:00:00-03:00",
  "end_datetime": "2026-05-18T10:20:00-03:00",
  "google_event_id": ""
}
```

---

## 13. Manutenção e atualização

### Atualizar repositório

```bash
cd ~/Extensao_universitaria_Manicure
git pull
```

### Atualizar dependências do CRM

```bash
cd "Aplicativos/CRM BeautyFlow/backend"
source .venv/bin/activate
pip install --upgrade -r requirements.txt
sudo systemctl restart beautyflow-crm
```

### Atualizar dependências do Agendamento

```bash
cd "Aplicativos/agendamento Vinicius"
npm update
sudo systemctl restart beautyflow-agenda
```

### Backup do Supabase Cloud

No dashboard do Supabase:
1. Vá em **Database → Backups**
2. Clique em **Trigger a backup** ou agende backups automáticos no plano Pro

### Backup do Supabase self-hosted

```bash
pg_dump postgresql://postgres:postgres@localhost:54322/postgres > backup_$(date +%Y%m%d).sql
```

---

## 14. Resumo dos comandos

### Instalação inicial (Ubuntu server limpo)

```bash
# 1. System packages
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl python3 python3-venv nginx certbot ufw

# 2. Node.js (se não veio com apt)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

# 3. Clone
git clone https://github.com/Sallesg82/Extensao_universitaria_Manicure.git
cd Extensao_universitaria_Manicure

# 4. CRM
cd "Aplicativos/CRM BeautyFlow/backend"
python3 -m venv .venv
source .venv/bin/activate
pip install flask flask-cors supabase httpx gunicorn
# Edite .env com credenciais Supabase
nano .env

# 5. Agendamento
cd ../../
cd "Aplicativos/agendamento Vinicius"
npm install

# 6. Iniciar
cd ../../instalacao
bash start.sh ambos
```

### Iniciar/parar serviços (sem systemd)

```bash
# Parar instalação
cd ~/Extensao_universitaria_Manicure/Aplicativos/instalacao
bash start.sh ambos       # Inicia CRM + Agendamento
bash start.sh crm         # Só CRM
bash start.sh agenda      # Só Agendamento
```

### Iniciar/parar serviços (com systemd)

```bash
sudo systemctl start beautyflow-crm
sudo systemctl stop beautyflow-crm
sudo systemctl restart beautyflow-crm
sudo systemctl status beautyflow-crm

sudo systemctl start beautyflow-agenda
sudo systemctl stop beautyflow-agenda
sudo systemctl restart beautyflow-agenda
sudo systemctl status beautyflow-agenda
```

### URLs de acesso

| Serviço | Local | Com Nginx |
|---------|-------|-----------|
| CRM | http://IP:3001 | https://dominio.com |
| Agendamento | http://IP:5173 | https://dominio.com/agendamento/ |
| API do CRM | http://IP:3001/api | https://dominio.com/api |

---

> **Dica:** A melhor opção para servidor é a instalação **nativa com systemd + Nginx + SSL**.
> O Supabase **Cloud** é recomendado para evitar complexidade e consumo de RAM no servidor.
