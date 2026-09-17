#!/usr/bin/env bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRM_BACKEND="$PROJECT_ROOT/Aplicativos/CRM BeautyFlow/backend"
AGENDAMENTO="$PROJECT_ROOT/Aplicativos/Beatriz Gomes Studio"
INSTALACAO_DIR="$PROJECT_ROOT/Aplicativos/instalacao"
COMPOSE_FILE="$INSTALACAO_DIR/docker-compose.yml"

show_help() {
    echo "Uso: ./dev.sh [opções]"
    echo ""
    echo "Opções:"
    echo "  -w, --waha, --with-waha   Inicia o ambiente com suporte ao WhatsApp WAHA (porta 3000)"
    echo "  -i, --install-waha        Executa a instalação e configuração guiada do WhatsApp WAHA"
    echo "  --no-waha, --without-waha Inicia o ambiente sem o WhatsApp WAHA"
    echo "  -h, --help                Exibe esta mensagem de ajuda"
    echo ""
    echo "Exemplos:"
    echo "  ./dev.sh               Inicia o ambiente (usa .env ou pergunta se interativo)"
    echo "  ./dev.sh --waha        Inicia com WAHA ativo"
    echo "  ./dev.sh --install-waha Configura e inicia o WAHA interativamente"
    exit 0
}

ENABLE_WAHA=""
DO_INSTALL_WAHA=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w|--waha|--with-waha)
            ENABLE_WAHA=1
            shift
            ;;
        -i|--install-waha)
            ENABLE_WAHA=1
            DO_INSTALL_WAHA=1
            shift
            ;;
        --no-waha|--without-waha)
            ENABLE_WAHA=0
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Opção desconhecida: $1"
            echo "Execute './dev.sh --help' para ver as opções disponíveis."
            exit 1
            ;;
    esac
done

echo "=================================================="
echo "🚀 Iniciando BeautyFlow em Modo de Desenvolvimento"
echo "=================================================="

# 1. Garantir que o PostgreSQL local está rodando
if command -v pg_ctl >/dev/null 2>&1; then
    if ! pg_ctl -D "$HOME/.pg_local/data" status >/dev/null 2>&1; then
        echo "🗄️  Iniciando PostgreSQL local..."
        if ! pg_ctl -D "$HOME/.pg_local/data" -l "$HOME/.pg_local/logfile" start; then
            echo ""
            echo "❌ Erro ao iniciar o PostgreSQL local!"
            if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}} ({{.Ports}})' | grep -q '5432'; then
                echo "⚠️  Detectado contêiner Docker ocupando a porta 5432:"
                docker ps --filter "publish=5432" --format "   - {{.Names}} ({{.Image}})"
                echo "💡 Para parar o contêiner em conflito, execute:"
                echo "   docker stop \$(docker ps -q --filter \"publish=5432\")"
            fi
            echo ""
            echo "📄 Últimas linhas do log ($HOME/.pg_local/logfile):"
            tail -n 10 "$HOME/.pg_local/logfile" 2>/dev/null || true
            exit 1
        fi
    else
        echo "🗄️  PostgreSQL já está em execução."
    fi
fi

# 2. Configurar WhatsApp WAHA (instalação e integração)
export DATABASE_URL="${DATABASE_URL:-postgresql://postgres:beautyflow_pass@localhost:5432/beautyflow}"

COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
fi

DEFAULT_WAHA_KEY="218c0effefb845238a1ae3651c8ced5b"
DEFAULT_WAHA_SESS="Beautyflow"

CUR_WAHA_KEY="$DEFAULT_WAHA_KEY"
CUR_WAHA_SESS="$DEFAULT_WAHA_SESS"
ENV_INSTALL_WAHA=""

if [ -f "$CRM_BACKEND/.env" ]; then
    k_val=$(grep -E "^WAHA_API_KEY=" "$CRM_BACKEND/.env" 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d '\r' || true)
    if [ -n "$k_val" ]; then CUR_WAHA_KEY="$k_val"; fi
    s_val=$(grep -E "^WAHA_SESSION=" "$CRM_BACKEND/.env" 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d '\r' || true)
    if [ -n "$s_val" ]; then CUR_WAHA_SESS="$s_val"; fi
    i_val=$(grep -E "^INSTALL_WAHA=" "$CRM_BACKEND/.env" 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d '\r' || true)
    if [ -n "$i_val" ]; then ENV_INSTALL_WAHA="$i_val"; fi
fi

if [ -z "$ENV_INSTALL_WAHA" ] && [ -f "$INSTALACAO_DIR/.env" ]; then
    i_val=$(grep -E "^INSTALL_WAHA=" "$INSTALACAO_DIR/.env" 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d '\r' || true)
    if [ -n "$i_val" ]; then ENV_INSTALL_WAHA="$i_val"; fi
fi

if [ -z "$ENABLE_WAHA" ]; then
    if [ "$ENV_INSTALL_WAHA" = "true" ]; then
        ENABLE_WAHA=1
    elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^(beautyflow-waha|waha)$'; then
        ENABLE_WAHA=1
    elif [ -t 0 ]; then
        echo ""
        read -rp "📱 Deseja habilitar e iniciar a integração com WhatsApp WAHA (porta 3000)? [s/N]: " RESP_W
        RESP_W=${RESP_W:-N}
        if [[ "$RESP_W" =~ ^[Ss]$ ]]; then
            ENABLE_WAHA=1
            if [ "$ENV_INSTALL_WAHA" != "true" ]; then
                DO_INSTALL_WAHA=1
            fi
        else
            ENABLE_WAHA=0
        fi
    else
        ENABLE_WAHA=0
    fi
fi

WAHA_STARTED_BY_DEV=0

if [ "$ENABLE_WAHA" -eq 1 ]; then
    echo ""
    echo "📱 Preparando integração com WhatsApp WAHA..."

    if ! command -v docker >/dev/null 2>&1; then
        echo "❌ Docker não encontrado no sistema. O WAHA necessita do Docker para executar."
        echo "   Para continuar sem o WAHA, execute: ./dev.sh --no-waha"
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "❌ O daemon do Docker não está ativo. Inicie o serviço Docker e tente novamente."
        echo "   Para continuar sem o WAHA, execute: ./dev.sh --no-waha"
        exit 1
    fi

    if [ "$DO_INSTALL_WAHA" -eq 1 ] && [ -t 0 ]; then
        echo "--- Configuração do WhatsApp WAHA ---"
        read -rp "   Chave de API do WAHA [$CUR_WAHA_KEY]: " INPUT_KEY
        CUR_WAHA_KEY=${INPUT_KEY:-$CUR_WAHA_KEY}

        read -rp "   Nome da Sessão do WhatsApp [$CUR_WAHA_SESS]: " INPUT_SESS
        CUR_WAHA_SESS=${INPUT_SESS:-$CUR_WAHA_SESS}
    fi

    touch "$CRM_BACKEND/.env"
    sed -i '/INSTALL_WAHA/d' "$CRM_BACKEND/.env" 2>/dev/null || true
    sed -i '/WAHA_API_KEY/d' "$CRM_BACKEND/.env" 2>/dev/null || true
    sed -i '/WAHA_API_URL/d' "$CRM_BACKEND/.env" 2>/dev/null || true
    sed -i '/WAHA_SESSION/d' "$CRM_BACKEND/.env" 2>/dev/null || true
    echo "INSTALL_WAHA=true" >> "$CRM_BACKEND/.env"
    echo "WAHA_API_KEY=$CUR_WAHA_KEY" >> "$CRM_BACKEND/.env"
    echo "WAHA_API_URL=http://localhost:3000" >> "$CRM_BACKEND/.env"
    echo "WAHA_SESSION=$CUR_WAHA_SESS" >> "$CRM_BACKEND/.env"

    if [ -d "$INSTALACAO_DIR" ]; then
        touch "$INSTALACAO_DIR/.env"
        sed -i '/COMPOSE_PROFILES/d' "$INSTALACAO_DIR/.env" 2>/dev/null || true
        sed -i '/INSTALL_WAHA/d' "$INSTALACAO_DIR/.env" 2>/dev/null || true
        sed -i '/WAHA_API_KEY/d' "$INSTALACAO_DIR/.env" 2>/dev/null || true
        sed -i '/WAHA_SESSION/d' "$INSTALACAO_DIR/.env" 2>/dev/null || true
        echo "COMPOSE_PROFILES=waha" >> "$INSTALACAO_DIR/.env"
        echo "INSTALL_WAHA=true" >> "$INSTALACAO_DIR/.env"
        echo "WAHA_API_KEY=$CUR_WAHA_KEY" >> "$INSTALACAO_DIR/.env"
        echo "WAHA_SESSION=$CUR_WAHA_SESS" >> "$INSTALACAO_DIR/.env"
    fi

    if ss -tlpn 2>/dev/null | grep -qE ":3000[[:space:]]"; then
        if ! docker ps --format '{{.Ports}}' 2>/dev/null | grep -qE ":3000->"; then
            echo "⚠️  Porta 3000 em uso por processo local fora do Docker."
            if [ -t 0 ]; then
                read -rp "   Deseja encerrar o processo local na porta 3000? [S/n]: " STOP_P
                STOP_P=${STOP_P:-S}
                if [[ "$STOP_P" =~ ^[Ss]$ ]]; then
                    if command -v fuser >/dev/null 2>&1; then
                        fuser -k -n tcp 3000 2>/dev/null || true
                    elif command -v lsof >/dev/null 2>&1; then
                        lsof -ti :3000 -sTCP:LISTEN 2>/dev/null | xargs -r kill -9 2>/dev/null || true
                    fi
                    sleep 1
                fi
            fi
        fi
    fi

    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^(beautyflow-waha|waha)$'; then
        echo "🐳 Iniciando contêiner beautyflow-waha..."
        if [ -n "$COMPOSE_CMD" ] && [ -f "$COMPOSE_FILE" ]; then
            $COMPOSE_CMD -f "$COMPOSE_FILE" --profile waha up -d waha
        else
            docker run -d \
                --name beautyflow-waha \
                --restart unless-stopped \
                -p 3000:3000 \
                -e WAHA_LOG_LEVEL=info \
                -e WAHA_PRINT_QR=False \
                -e WAHA_DASHBOARD_ENABLED=True \
                -e WHATSAPP_DEFAULT_ENGINE=WEBJS \
                -e WAHA_BASE_URL=http://localhost:3000 \
                -e WAHA_API_KEY="$CUR_WAHA_KEY" \
                -v waha_sessions:/app/.sessions \
                devlikeapro/waha:latest
        fi
        WAHA_STARTED_BY_DEV=1
    else
        echo "🐳 Contêiner WAHA já está em execução."
    fi

    echo "⏳ Aguardando serviço WAHA responder em http://localhost:3000/ping..."
    waha_ready=0
    for i in $(seq 1 25); do
        if curl -s -f http://localhost:3000/ping >/dev/null 2>&1; then
            waha_ready=1
            break
        fi
        sleep 1
    done

    if [ "$waha_ready" -eq 1 ]; then
        echo "✅ Endpoint WAHA online!"
        curl -s -X POST "http://localhost:3000/api/sessions" \
            -H "Content-Type: application/json" \
            -H "X-Api-Key: $CUR_WAHA_KEY" \
            -d "{\"name\":\"$CUR_WAHA_SESS\",\"start\":true}" >/dev/null 2>&1 || true
    else
        echo "⚠️  WAHA ainda está inicializando em segundo plano."
    fi

    echo "🔄 Sincronizando integração do WhatsApp no banco de dados..."
    "$CRM_BACKEND/.venv/bin/python" -c "
import os, sys
sys.path.insert(0, '$CRM_BACKEND')
os.environ['DATABASE_URL'] = '$DATABASE_URL'
from db.database import _run, update_setting
try:
    update_setting('whatsapp_integrated', 'true')
    update_setting('waha_api_key', '$CUR_WAHA_KEY')
    update_setting('waha_session_name', '$CUR_WAHA_SESS')
    update_setting('waha_api_url', 'http://localhost:3000')
    _run('''
        INSERT INTO integrations (name, type, enabled, config)
        SELECT 'WhatsApp WAHA', 'whatsapp', true, %s::jsonb
        WHERE NOT EXISTS (SELECT 1 FROM integrations WHERE type IN ('whatsapp', 'waha'));
    ''', ('{\"session\":\"$CUR_WAHA_SESS\",\"notify_on_create\":true,\"notify_on_reminder\":true}',))
    _run(\"UPDATE integrations SET enabled = true WHERE type IN ('whatsapp', 'waha');\")
except Exception as e:
    print(f'Aviso na sincronização do DB: {e}', file=sys.stderr)
" 2>/dev/null || true

    export INSTALL_WAHA="true"
    export WAHA_API_KEY="$CUR_WAHA_KEY"
    export WAHA_API_URL="http://localhost:3000"
    export WAHA_SESSION="$CUR_WAHA_SESS"
else
    export INSTALL_WAHA="false"
fi

# 3. Configurar encerramento limpo com Ctrl+C
cleanup() {
    echo ""
    echo "🛑 Encerrando servidores de desenvolvimento..."
    kill $(jobs -p) 2>/dev/null || true
    if [ "${WAHA_STARTED_BY_DEV:-0}" -eq 1 ]; then
        echo "📱 Parando contêiner WhatsApp WAHA..."
        if [ -n "$COMPOSE_CMD" ] && [ -f "$COMPOSE_FILE" ]; then
            $COMPOSE_CMD -f "$COMPOSE_FILE" --profile waha stop waha >/dev/null 2>&1 || docker stop beautyflow-waha >/dev/null 2>&1 || true
        else
            docker stop beautyflow-waha >/dev/null 2>&1 || true
        fi
    fi
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# 4. Iniciar Backend CRM BeautyFlow (porta 3001)
echo "💅 Iniciando CRM BeautyFlow Backend (porta 3001)..."
if ss -tlpn 2>/dev/null | grep -qE ":3001[[:space:]]"; then
    if ! docker ps --format '{{.Ports}}' 2>/dev/null | grep -qE ":3001->"; then
        echo "   Liberando porta 3001 ocupada por instância anterior..."
        fuser -k -n tcp 3001 >/dev/null 2>&1 || true
        sleep 1
    fi
fi
cd "$CRM_BACKEND"
"$CRM_BACKEND/.venv/bin/python" run.py &

# 5. Iniciar Portal de Agendamento Vite (porta 5173)
echo "🌸 Iniciando Portal de Agendamento Vite (porta 5173)..."
if ss -tlpn 2>/dev/null | grep -qE ":5173[[:space:]]"; then
    if ! docker ps --format '{{.Ports}}' 2>/dev/null | grep -qE ":5173->"; then
        echo "   Liberando porta 5173 ocupada por instância anterior..."
        fuser -k -n tcp 5173 >/dev/null 2>&1 || true
        sleep 1
    fi
fi
cd "$AGENDAMENTO"
export PATH="$AGENDAMENTO/node_modules/.bin:$PATH"
NODE_BIN="$(command -v node || echo "node")"
if [ -f "$AGENDAMENTO/node_modules/vite/bin/vite.js" ]; then
    "$NODE_BIN" "$AGENDAMENTO/node_modules/vite/bin/vite.js" --host 0.0.0.0 --port 5173 &
elif command -v npx >/dev/null 2>&1; then
    npx vite --host 0.0.0.0 --port 5173 &
else
    npm run dev &
fi

echo ""
echo "✅ Aplicações rodando com recarregamento dinâmico:"
echo "   📊 CRM BeautyFlow:        http://localhost:3001  (Login: admin / Senha: admin)"
echo "   🌸 Portal de Agendamento:  http://localhost:5173"
echo "   🗄️  PostgreSQL:            localhost:5432 (Banco: beautyflow)"
if [ "$ENABLE_WAHA" -eq 1 ]; then
    echo "   📱 WhatsApp WAHA:         http://localhost:3000  (QR Code: http://localhost:3000/dashboard)"
    echo "      • Sessão: $CUR_WAHA_SESS | API Key: $CUR_WAHA_KEY"
fi
echo ""
echo "Qualquer alteração nos códigos do CRM ou do Agendamento atualizará dinamicamente!"
echo "Pressione Ctrl+C a qualquer momento para parar."

wait
