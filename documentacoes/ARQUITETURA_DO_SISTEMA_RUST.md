# Arquitetura Técnica do Backend em Rust

Este documento descreve a organização interna, o fluxo de dados e os módulos do novo backend do **BeautyFlow CRM**, desenvolvido em **Rust**.

---

## 1. Visão Geral da Estrutura de Arquivos

Todo o código-fonte do backend está concentrado em [`Aplicativos/CRM BeautyFlow/backend/`](file:///home/sallez/Documentos/projetos/Extensao_universitaria_Manicure/Aplicativos/CRM%20BeautyFlow/backend/):

```
backend/
├── Cargo.toml               # Dependências e perfil de compilação release otimizado
├── Cargo.lock               # Trava de versões exatas das dependências
├── run.py                   # Script launcher com auto-delegação para o binário Rust
├── .env                     # Variáveis de ambiente (PostgreSQL, WAHA, n8n, etc.)
├── db/                      # Arquivos de banco local
│   ├── schema.sql           # Schema DDL do PostgreSQL
│   └── whatsapp_chat.db     # Banco de dados SQLite do chat WhatsApp
├── target/release/
│   └── beautyflow-crm       # Binário executável nativo compilado (~26MB)
└── src/                     # Código-fonte Rust
    ├── main.rs              # Ponto de entrada, servidor Axum + Socket.IO, CLI
    ├── config.rs            # Configurações do ambiente e auto-detecção de diretórios
    ├── db/                  # Camada de banco de dados
    │   ├── mod.rs           # Estado global (AppState) e pools PgPool / SqlitePool
    │   ├── schema.rs        # DDL, triggers de realtime e reconciliação financeira
    │   ├── chat_db.rs       # Gerenciador de conversas e mensagens SQLite (WA)
    │   └── listener.rs      # PgListener assíncrono escutando notificações em tempo real
    ├── services/            # Serviços de integração e domínio
    │   ├── mod.rs           # Exportação dos serviços
    │   ├── auth.rs          # Hashing Werkzeug-compatível (scrypt & pbkdf2)
    │   ├── waha.rs          # Integração HTTP com a API do WhatsApp (WAHA)
    │   ├── n8n.rs           # Disparo de webhooks e sincronização com Google Calendar
    │   └── scheduler.rs     # Agendador em background de lembretes automáticos
    └── routes/              # Roteadores e handlers da API REST
        ├── mod.rs           # Montagem unificada do roteador /api
        ├── users.rs         # Login, autenticação e usuários
        ├── stats.rs         # Métricas financeiras, dashboards e KPIs
        ├── clients.rs       # CRUD de clientes e histórico de visitas
        ├── appointments.rs  # Agendamentos, validação de horários e conflitos
        ├── services.rs      # Catálogo de serviços
        ├── products.rs      # Inventário, controle de estoque e alertas
        ├── business_hours.rs# Horários de funcionamento e slots livres
        ├── settings.rs      # Configurações gerais e categorias de despesas
        ├── transactions.rs  # Entradas e saídas financeiras
        ├── metas.rs         # Metas mensais de faturamento
        ├── notifications.rs # Central de notificações do sistema
        ├── integrations.rs  # Configurações de serviços integrados
        ├── whatsapp.rs      # Endpoints de controle e webhook do WhatsApp
        ├── n8n.rs           # Endpoints de integração com n8n
        └── migrate.rs       # Exportação do schema SQL
```

---

## 2. Componentes Centrais

### 2.1. Ponto de Entrada (`main.rs`)
Responsável por orquestrar todo o ciclo de vida do servidor:
1. **Configuração de Tracing/Logs:** Formatação estruturada em stdout com níveis configuráveis via variável `RUST_LOG`.
2. **Subcomandos de Linha de Comando:**
   - `--healthcheck`: Testa a conectividade com os bancos de dados e responde com código `0` ou `1`.
   - `--reset-admin <nova_senha>`: Atualiza diretamente no banco de dados a senha do usuário administrador usando o algoritmo seguro scrypt.
3. **Socket.IO Layer:** Instancia a camada `SocketIo` (`socketioxide`), configurando salas e eventos de comunicação bidirecional com a interface.
4. **Serviço de Arquivos Estáticos:** Utiliza o middleware `ServeDir` do `tower-http` para entregar a SPA web (`index.html`, `js/`, `css/`) diretamente do binário na raiz `/`.
5. **Tarefas de Background (Spawn):** Inicia a escuta de eventos do PostgreSQL (`start_postgres_listener`) e o agendador de lembretes (`start_reminders_scheduler`).

---

### 2.2. Estado Compartilhado da Aplicação (`AppState`)
Gerenciado via `Arc<AppState>` e injetado em cada rota do Axum por meio de `State(state)`:

```rust
pub struct AppState {
    pub pg_pool: PgPool,            // Conexões assíncronas com PostgreSQL
    pub sqlite_pool: SqlitePool,    // Conexões assíncronas com SQLite (Chat WAHA)
    pub io: SocketIo,               // Instância do Socket.IO para broadcast em tempo real
    pub config: AppConfig,          // Configurações e caminhos do sistema
    pub http_client: reqwest::Client// Cliente HTTP assíncrono para WAHA e n8n
}
```

---

### 2.3. Arquitetura de Notificações em Tempo Real

A sincronização em tempo real entre o banco de dados e os navegadores dos operadores funciona através de uma esteira orientada a eventos:

```
[ Ação no Sistema ou API ]
           │
           ▼
[ Banco PostgreSQL ] ───▶ Executa Trigger: notify_pgevents()
                               │
                               ▼ Canal NOTIFY 'pgevents'
                    [ listener.rs: PgListener ]
                               │
                               ▼ Deserializa evento JSON
                    [ socketioxide: io.emit() ]
                               │
                               ▼ WebSocket / Polling
               [ Navegador do Usuário / Frontend SPA ]
          (Atualiza tabela, badges e gráficos instantaneamente)
```

**Tabelas Monitoradas em Tempo Real:**
- `appointments` ➔ Emite evento `appointment_updated` / `appointment_created`
- `transactions` ➔ Emite evento `transaction_created` / `transaction_updated`
- `clients` ➔ Emite evento `client_updated`
- `notifications` ➔ Emite evento `notification_created`
- `products` ➔ Emite evento `stock_updated`
- `users` ➔ Emite evento `user_updated`

---

### 2.4. Gestão de Mensagens do WhatsApp (`chat_db.rs`)

O banco SQLite [`db/whatsapp_chat.db`](file:///home/sallez/Documentos/projetos/Extensao_universitaria_Manicure/Aplicativos/CRM%20BeautyFlow/backend/db/whatsapp_chat.db) armazena as conversas do WhatsApp de forma isolada do PostgreSQL, evitando poluir o banco financeiro com tráfego de mensageria:

1. **Normalização de Telefones Brasileiros:** A função `clean_phone()` extrai somente números e a lógica de busca gera variações plausíveis do número com ou sem o dígito `9` adicional.
2. **Histórico Rápido:** Consulta indexada por timestamp permitindo que o frontend carregue rapidamente as últimas mensagens de qualquer conversa sem degradação de performance.
3. **Respostas Rápidas (Canned Responses):** Tabela nativa contendo atalhos rápidos (`/agendar`, `/confirmar`, `/lembrete`, etc.) para o atendimento.

---

### 2.5. Autenticação e Segurança (`auth.rs`)

O módulo de segurança foi desenvolvido para ser estritamente compatível com o gerador de senhas do Python Werkzeug:
- **Formato Suportado:** `scrypt:32768:8:1$<salt>$<hash>` (onde $N=32768, r=8, p=1$).
- **Fallback Suportado:** `pbkdf2:sha256:<iter>$<salt>$<hash>`.
- **Independência de Parâmetros:** A função `verify_password` analisa os argumentos para identificar automaticamente qual valor representa o hash salvo no banco e qual representa o texto plano digitado, prevenindo inversões de parâmetros acidentais.
- **Login Híbrido:** O endpoint `/api/users/login` aceita tanto o campo `email` quanto `username`, e realiza a busca indiferente a maiúsculas/minúsculas (`LOWER(email)` ou `LOWER(name)`).
