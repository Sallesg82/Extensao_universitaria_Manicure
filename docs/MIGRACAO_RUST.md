# Documentações da Plataforma BeautyFlow CRM

As documentações técnicas completas sobre a plataforma e sobre a migração de todo o backend de Python/Flask para **Rust nativo** foram organizadas no diretório dedicado [`/documentacoes`](file:///home/sallez/Documentos/projetos/Extensao_universitaria_Manicure/documentacoes):

1. [**Relatório de Migração de Backend para Rust**](file:///home/sallez/Documentos/projetos/Extensao_universitaria_Manicure/documentacoes/MIGRACAO_BACKEND_RUST.md):
   - Comparativo de métricas (consumo de memória RAM reduzido de ~200MB para ~16MB, boot em 48ms, latência sub-milissegundo).
   - Eliminação do GIL do Python e ganhos em concorrência real assíncrona com Tokio.
   - Qualidades técnicas e garantia de estabilidade.

2. [**Arquitetura do Backend em Rust**](file:///home/sallez/Documentos/projetos/Extensao_universitaria_Manicure/documentacoes/ARQUITETURA_DO_SISTEMA_RUST.md):
   - Estrutura de módulos (`main.rs`, `config.rs`, `db/`, `services/`, `routes/`).
   - Sincronização em tempo real via PostgreSQL `pgevents` e WebSocket `socketioxide`.
   - Gerenciamento de conversas do WhatsApp em SQLite (`chat_db.rs`).

3. [**Guia de Desenvolvimento, Operação e Deploy**](file:///home/sallez/Documentos/projetos/Extensao_universitaria_Manicure/documentacoes/GUIA_DE_DESENVOLVIMENTO_E_DEPLOY.md):
   - Inicialização local com `./dev.sh` ou `cargo run`.
   - Subcomandos integrados `--healthcheck` e `--reset-admin <senha>`.
   - Build multi-stage e Docker Compose.

4. [**Referência Completa de APIs e Rotas**](file:///home/sallez/Documentos/projetos/Extensao_universitaria_Manicure/documentacoes/REFERENCIA_DE_APIS_E_ROTAS.md):
   - Especificação técnica dos 30 endpoints REST e eventos WebSocket.
