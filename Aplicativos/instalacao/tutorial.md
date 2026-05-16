# Tutorial — Rodar o BeautyFlow (CRM + Agendamento)

> **Nota:** Este tutorial considera que o Supabase já está configurado com as credenciais
> embutidas no código. Para rodar, basta clonar e executar os comandos abaixo.

---

## 1. Pré-requisitos

| Programa | Versão mínima |
|----------|---------------|
| Git      | qualquer      |
| Python 3 | 3.10+         |
| Node.js  | 18+           |
| npm      | 9+            |

---

## 2. Clonar o repositório

```bash
git clone <url-do-repositorio>
cd Extensao_universitaria_Manicure
```

---

## 3. Backend — CRM

### 3.1 Criar ambiente virtual e instalar dependências

```bash
cd "Aplicativos/CRM-Mirian (protótipo)/backend"

python3 -m venv .venv
source .venv/bin/activate      # Linux/macOS
# .venv\Scripts\activate       # Windows (PowerShell)

pip install flask flask-cors supabase httpx
```

### 3.2 Verificar o Supabase

As credenciais já estão fixas no arquivo `db/database.py`.
Se for usar outro projeto Supabase, edite as variáveis `SUPABASE_URL` e `SUPABASE_KEY` lá dentro.

**Schema do banco:** as tabelas precisam existir no Supabase.
Abra o SQL Editor do seu projeto Supabase e execute o conteúdo do arquivo:

```
Aplicativos/CRM-Mirian (protótipo)/backend/db/supabase_schema.sql
```

Ou, com o CRM rodando, acesse `http://localhost:3001/api/migrate/sql` para copiar o SQL.

### 3.3 Iniciar o CRM

```bash
cd "Aplicativos/CRM-Mirian (protótipo)/backend"
source .venv/bin/activate
FLASK_DEBUG=0 python -c "import server; server.app.run(host='0.0.0.0', port=3001, debug=False, use_reloader=False)"
```

O CRM vai estar disponível em **http://localhost:3001**.

---

## 4. Frontend — Agendamento (React + Vite)

Abra **outro terminal**.

```bash
cd "Aplicativos/agendamento Vinicius"
npm install
npm run dev
```

O agendamento vai estar disponível em **http://localhost:5173**.

> ⚠️ O Agendamento depende do CRM rodando na porta 3001 para funcionar.
> As chamadas de API são feitas para `http://localhost:3001/api`.

---

## 5. Primeiro acesso

1. Abra http://localhost:3001
2. Crie uma conta na tela de registro (primeiro usuário)
3. Pronto — o CRM está operacional

---

## 6. Integração com n8n (opcional)

Na aba **Configurações > Integrações**:
1. Cole a URL do webhook do n8n
2. Clique em **Testar** para verificar
3. Clique em **Salvar**

A partir daí, todo agendamento criado no CRM dispara automaticamente um webhook para o n8n.

---

## 7. Resumo dos comandos

```bash
# Terminal 1 — CRM
cd "Aplicativos/CRM-Mirian (protótipo)/backend"
source .venv/bin/activate
FLASK_DEBUG=0 python -c "import server; server.app.run(host='0.0.0.0', port=3001, debug=False, use_reloader=False)"

# Terminal 2 — Agendamento
cd "Aplicativos/agendamento Vinicius"
npm install   # só na primeira vez
npm run dev
```

| Serviço        | URL                     |
|----------------|-------------------------|
| CRM            | http://localhost:3001   |
| Agendamento    | http://localhost:5173   |
| API do CRM     | http://localhost:3001/api |
