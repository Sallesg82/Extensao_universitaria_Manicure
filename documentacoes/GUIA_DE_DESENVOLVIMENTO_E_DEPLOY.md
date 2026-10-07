# Guia de Desenvolvimento, Operação e Deploy

Este guia detalha como executar, testar, compilar e realizar o deploy do novo backend em **Rust** da plataforma **BeautyFlow CRM**.

---

## 1. Requisitos do Sistema

- **Compilação Local:**
  - Rust 1.80+ (com `cargo` e `rustc`)
  - Biblioteca OpenSSL / C compiler (`pkg-config`, `libssl-dev`, `build-essential`)
- **Execução em Produção (Sem compilar localmente):**
  - Docker e Docker Compose (o processo de compilação ocorre automaticamente dentro da imagem multi-stage).

---

## 2. Executando Localmente no Ambiente de Desenvolvimento

### Opção 1: Via Script Unificado (`dev.sh`) — Recomendado
O script principal da raiz do projeto já está integrado para inicializar o PostgreSQL, o WAHA e o backend Rust:

```bash
./dev.sh
```
O script verifica a existência do binário compilado em `Aplicativos/CRM BeautyFlow/backend/target/release/beautyflow-crm` e o executa em segundo plano na porta `3001`.

---

### Opção 2: Via Cargo Diretamente
Para desenvolver no backend com recarregamento ou depuração detalhada:

```bash
cd "Aplicativos/CRM BeautyFlow/backend"

# Executar em modo debug:
cargo run

# Ou compilar e executar com todas as otimizações de produção:
cargo run --release
```

Por padrão, o servidor escutará na porta definida na variável de ambiente `PORT` (padrão: `3001` ou `5005`).

---

### Opção 3: Via `run.py` (Delegação Transparente)
Para garantir que scripts ou rotinas que anteriormente invocavam `python run.py` não quebrem, o arquivo `run.py` detecta a presença do binário Rust compilado e substitui o processo:

```bash
cd "Aplicativos/CRM BeautyFlow/backend"
./run.py
```

---

## 3. Subcomandos de Linha de Comando (CLI Integrado)

O executável `beautyflow-crm` possui utilitários administrativos embutidos:

### 3.1. Verificação de Saúde (`--healthcheck`)
Testa a conectividade com os bancos PostgreSQL e SQLite e retorna código de saída `0` se tudo estiver operacional:

```bash
./target/release/beautyflow-crm --healthcheck
```
*Saída esperada:*
```
HEALTHCHECK_OK
```

### 3.2. Redefinição de Senha do Administrador (`--reset-admin`)
Permite redefinir a senha do usuário `admin` diretamente no banco de dados sem precisar entrar no console SQL:

```bash
./target/release/beautyflow-crm --reset-admin "sua_nova_senha"
```
*Saída esperada:*
```
Senha de admin atualizada com sucesso (1 registros afetados)
```

---

## 4. Testes Automatizados

O backend conta com testes unitários em Rust e scripts de teste de integração de ponta a ponta:

### Executar Testes Unitários de Criptografia e Autenticação
```bash
cd "Aplicativos/CRM BeautyFlow/backend"
cargo test
```

### Executar Bateria Completa de Endpoints da API
Com o servidor rodando em qualquer porta (ex: 3001 ou 5005), você pode rodar a suite automatizada que valida todos os 30 endpoints:

```bash
python3 - << 'EOF'
import urllib.request, json
# ... faz requisições em todos os 30 endpoints ...
EOF
```

---

## 5. Deploy com Docker e Docker Compose

O deploy do CRM é totalmente containerizado utilizando uma imagem multi-stage super leve:

### 5.1. Como Funciona o `Dockerfile.crm`
1. **Stage 1 (`builder`):** Utiliza imagem oficial `rust:1.85-slim-bookworm` para compilar o código em modo `--release`.
2. **Stage 2 (`runner`):** Copia somente o binário executável final para uma imagem `debian:bookworm-slim` limpa (apenas bibliotecas dinâmicas básicas e certificados CA). O resultado é uma imagem final de aproximadamente **85 MB**, contra os mais de 850 MB da imagem anterior com Python.

### 5.2. Comandos para Construir e Subir os Contêineres

Na pasta `Aplicativos/instalacao/`:

```bash
cd Aplicativos/instalacao

# Construir as imagens atualizadas:
docker compose build crm-backend

# Iniciar todos os serviços:
docker compose up -d

# Visualizar logs em tempo real:
docker compose logs -f crm-backend
```

### 5.3. Monitoramento e Healthcheck no Docker
O container `beautyflow-crm` utiliza o próprio subcomando nativo para auto-diagnóstico:

```yaml
healthcheck:
  test: ["CMD", "/app/beautyflow-crm", "--healthcheck"]
  interval: 5s
  timeout: 5s
  retries: 6
  start_period: 5s
```
Se o PostgreSQL reiniciar ou ficar inacessível temporariamente, o Docker sinaliza o estado do container de maneira transparente.

---

## 6. Variáveis de Ambiente (`.env`)

| Variável | Valor Padrão / Exemplo | Descrição |
| :--- | :--- | :--- |
| `PORT` | `3001` | Porta HTTP do servidor Axum |
| `DATABASE_URL` | `postgresql://postgres:beautyflow_pass@localhost:5432/beautyflow` | String de conexão com o PostgreSQL |
| `STATIC_DIR` | Auto-detectado (`../src`) | Diretório contendo os arquivos da interface SPA |
| `N8N_WEBHOOK_URL`| URL de webhook n8n | Endpoint para sincronização de calendário |
| `WAHA_API_URL` | `http://localhost:3000` | URL do servidor WhatsApp WAHA |
| `WAHA_API_KEY` | Chave de API configurada | Chave de autenticação no WAHA |
| `WAHA_SESSION` | `default` ou `beauty` | Nome da sessão ativa no WAHA |
| `RUST_LOG` | `info` | Nível de detalhamento dos logs (`error`, `warn`, `info`, `debug`, `trace`) |
