#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -z "${BF_GROUP_RELOADED:-}" ] && [ "$(id -u)" -ne 0 ]; then
    if ! id -Gn 2>/dev/null | grep -qw docker && getent group docker 2>/dev/null | grep -qw "$USER"; then
        export BF_GROUP_RELOADED=1
        exec newgrp docker -c "exec bash \"$SCRIPT_DIR/stop.sh\" \"$@\""
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

echo "[*] Parando conteineres da plataforma BeautyFlow..."
$COMPOSE_CMD stop

echo ""
echo "=================================================================="
echo "[OK] Todos os conteineres foram parados com sucesso."
echo "     (Seus dados no PostgreSQL continuam preservados no volume)"
echo "=================================================================="
