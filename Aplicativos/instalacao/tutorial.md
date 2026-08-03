# Guia de Instalação e Execução do BeautyFlow (CRM + Agendamento) via Docker

Este instalador simplificado configura toda a plataforma **BeautyFlow** de forma integrada usando **Docker** e **Docker Compose**, conectando o CRM BeautyFlow, o portal de agendamentos para clientes e o banco de dados PostgreSQL com motor REST API.

---

## 🛠️ Pré-requisitos

1. **Docker** instalado e em execução (Docker Desktop no Windows/macOS ou Docker Engine no Linux).
2. **Docker Compose** habilitado.

---

## 🚀 Como Instalar e Rodar (Passo a Passo)

### No Linux / macOS:
No terminal, acesse a pasta do instalador e execute:
```bash
cd "Aplicativos/instalacao"
./install.sh
```

### No Windows:
Clique duas vezes no arquivo `install.bat` ou abra o Terminal (CMD/PowerShell) na pasta `Aplicativos/instalacao` e rode:
```cmd
install.bat
```

---

## 🌐 Acesso às Aplicações

Após a conclusão da instalação, a plataforma estará online em:

* 📊 **Painel CRM BeautyFlow (Gestão)**: [http://localhost:3001](http://localhost:3001)
* 🌸 **Portal de Agendamento (Clientes)**: [http://localhost:5173](http://localhost:5173)
* 🗄️ **Banco de Dados PostgreSQL**: `localhost:5432` (Banco: `beautyflow`, Usuário: `postgres`, Senha: `beautyflow_pass`)

---

## 📦 Arquitetura dos Contêineres Docker

| Contêiner | Função | Porta |
|-----------|--------|-------|
| `beautyflow-postgres` | Banco de dados PostgreSQL 16 com schema completo inicializado | `5432` |
| `beautyflow-crm` | Backend Flask + Frontend SPA do CRM BeautyFlow (conecta direto ao PostgreSQL) | `3001` |
| `beautyflow-agendamento` | Frontend React + Vite do Portal de Agendamento do cliente | `5173` |

---

## 🛠️ Comandos Úteis

* **Iniciando a plataforma**:
  ```bash
  ./start.sh
  ```
* **Verificando logs dos contêineres**:
  ```bash
  docker compose logs -f
  ```
* **Parando os serviços**:
  ```bash
  docker compose down
  ```

---

## ⚙️ Configuração da URL da API (deploy remoto)

Por padrão, o portal de agendamento aponta para `http://localhost:3001/api` (funciona
apenas quando o navegador está na mesma máquina que o Docker). Para servir de um
servidor remoto, altere o arquivo `.env` dentro desta pasta (`Aplicativos/instalacao/.env`):

```env
VITE_API_URL=http://SEU_IP_OU_DOMINIO:3001/api
```

Depois, reconstrua o portal:

```bash
docker compose up -d --build agendamento-app
```

> Nota: a URL da API é embutida no bundle React em tempo de build — alterações no
> `.env` só têm efeito após reconstruir o contêiner `agendamento-app`.
