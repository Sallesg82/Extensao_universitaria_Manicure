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
        pg_ctl -D "$HOME/.pg_local/data" -l "$HOME/.pg_local/logfile" start
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
"$CRM_BACKEND/.venv/bin/python" run.py &

# 4. Iniciar Portal de Agendamento Vite (porta 5173)
echo "🌸 Iniciando Portal de Agendamento Vite (porta 5173)..."
cd "$AGENDAMENTO"
npm run dev &

echo ""
echo "✅ Aplicações rodando com recarregamento dinâmico:"
echo "   📊 CRM BeautyFlow:        http://localhost:3001  (Login: admin / Senha: admin)"
echo "   🌸 Portal de Agendamento:  http://localhost:5173"
echo "   🗄️  PostgreSQL:            localhost:5432 (Banco: beautyflow)"
echo ""
echo "Qualquer alteração nos códigos do CRM ou do Agendamento atualizará dinamicamente!"
echo "Pressione Ctrl+C a qualquer momento para parar."

wait
