#!/usr/bin/env bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRM_BACKEND="$PROJECT_ROOT/Aplicativos/CRM BeautyFlow/backend"
AGENDAMENTO="$PROJECT_ROOT/Aplicativos/Beatriz Gomes Studio"

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

# 2. Configurar encerramento limpo com Ctrl+C
cleanup() {
    echo ""
    echo "🛑 Encerrando servidores de desenvolvimento..."
    kill $(jobs -p) 2>/dev/null || true
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# 3. Iniciar Backend CRM BeautyFlow (porta 3001)
echo "💅 Iniciando CRM BeautyFlow Backend (porta 3001)..."
cd "$CRM_BACKEND"
export DATABASE_URL="${DATABASE_URL:-postgresql://postgres:beautyflow_pass@localhost:5432/beautyflow}"
"$CRM_BACKEND/.venv/bin/python" run.py &

# 4. Iniciar Portal de Agendamento Vite (porta 5173)
echo "🌸 Iniciando Portal de Agendamento Vite (porta 5173)..."
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
echo ""
echo "Qualquer alteração nos códigos do CRM ou do Agendamento atualizará dinamicamente!"
echo "Pressione Ctrl+C a qualquer momento para parar."

wait
