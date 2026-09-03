#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -z "${BF_GROUP_RELOADED:-}" ] && [ "$(id -u)" -ne 0 ]; then
    if ! id -Gn 2>/dev/null | grep -qw docker && getent group docker 2>/dev/null | grep -qw "$USER"; then
        export BF_GROUP_RELOADED=1
        exec newgrp docker -c "exec bash \"$SCRIPT_DIR/start.sh\" \"$@\""
    fi
fi

COMPOSE_CMD=""
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo "[ERRO] Docker Compose nao foi encontrado."
    exit 1
fi

echo "[*] Iniciando plataforma BeautyFlow..."
$COMPOSE_CMD up -d

echo "[*] Aguardando servicos inicializarem..."
for i in $(seq 1 30); do
    all_ok=1
    unhealthy=""
    while IFS='=' read -r svc state health; do
        if [ -z "$svc" ]; then continue; fi
        if [ "$state" != "running" ] || [ "$health" = "unhealthy" ] || [ "$health" = "starting" ]; then
            all_ok=0
            if [ "$health" = "unhealthy" ]; then unhealthy="$unhealthy $svc"; fi
        fi
    done < <($COMPOSE_CMD ps --format '{{.Service}}={{.State}}={{.Health}}' 2>/dev/null)
    if [ -n "$unhealthy" ]; then
        echo "[ERRO] Servico(s) com problema:${unhealthy}"
        echo "Executar para diagnostico: $COMPOSE_CMD logs --tail=100 <servico>"
        exit 1
    fi
    if [ "$all_ok" -eq 1 ]; then
        break
    fi
    sleep 3
done

echo ""
echo "[OK] Servicos ativos:"
echo "  • CRM BeautyFlow (Painel):   http://localhost:3001 (admin / admin)"
echo "  • Portal de Agendamento:     http://localhost:5173"
echo "  • Banco de Dados PostgreSQL: localhost:5432"
