# 📚 Documentações do BeautyFlow CRM

Bem-vindo ao diretório central de documentações da plataforma **BeautyFlow CRM**.

Aqui estão reunidos todos os documentos técnicos, manuais de operação, referências de API e análises detalhadas sobre a nova arquitetura do sistema e a migração completa do backend para **Rust nativo**.

---

## 📑 Índice dos Documentos

### 1. [Migração Completa do Backend para Rust](MIGRACAO_BACKEND_RUST.md)
> **Leitura indispensável:** Entenda a transição do antigo backend em Python (Flask + Flask-SocketIO) para o novo backend em Rust (Axum + SQLx + Tokio + Socketioxide).
- Motivações técnicas da mudança.
- Comparativo detalhado de métricas (consumo de memória RAM reduzido em ~92%, latência de 0.5ms, boot em 48ms).
- Qualidades e diferenciais do novo sistema (sem GC pauses, concorrência real sem o GIL do Python, segurança de memória e tipos estáticos).

### 2. [Arquitetura do Sistema em Rust](ARQUITETURA_DO_SISTEMA_RUST.md)
> **Para desenvolvedores:** Guia completo sobre como o código está estruturado e como os módulos interagem.
- Estrutura de diretórios e arquivos em `backend/src/`.
- Gerenciamento de estado global compartilhado (`AppState`).
- Arquitetura de notificações em tempo real com `PgListener` e `socketioxide`.
- Módulo de persistência do chat WhatsApp em SQLite (`chat_db.rs`).
- Criptografia e compatibilidade de senhas (`auth.rs`).

### 3. [Guia de Desenvolvimento, Operação e Deploy](GUIA_DE_DESENVOLVIMENTO_E_DEPLOY.md)
> **Para operação e DevOps:** Como rodar, testar, compilar e implantar a aplicação.
- Inicialização local com `./dev.sh`, `cargo run` ou `run.py`.
- Subcomandos de linha de comando (`beautyflow-crm --healthcheck` e `--reset-admin <senha>`).
- Execução de testes unitários e de integração.
- Build multi-stage e deploy via Docker Compose.
- Variáveis de ambiente configuráveis no `.env`.

### 4. [Referência Completa de APIs e Rotas](REFERENCIA_DE_APIS_E_ROTAS.md)
> **Para integrações e frontend:** Especificação detalhada de todos os 30 endpoints REST e eventos WebSocket.
- Rotas de Usuários e Autenticação.
- Rotas de Estatísticas e Dashboard.
- Rotas de Clientes, Agendamentos, Serviços e Estoque.
- Rotas de WhatsApp WAHA, n8n e Google Calendar.
- Eventos em tempo real emitidos via WebSocket (`Socket.IO v4`).

---

## ⚡ Resumo dos Ganhos de Performance

```
Consumo de RAM:      180MB (Python) ──▶  16MB (Rust)      [-92%]
Tempo de Boot:       3.200ms        ──▶  48ms            [70x mais rápido]
Latência Média:      35ms           ──▶  0.8ms           [40x menor latência]
Tamanho da Imagem:   850MB          ──▶  85MB            [-90%]
```
