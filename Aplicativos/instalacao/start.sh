#!/usr/bin/env bash
# ==============================================================================
# BeautyFlow Platform — Inicializador Rapido (start.sh)
# ==============================================================================
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

# Liberar porta 5432 se ocupada por PostgreSQL local
if ss -tlpn 2>/dev/null | grep -qE ":5432[[:space:]]"; then
    if ! docker ps --format '{{.Ports}}' 2>/dev/null | grep -qE ":5432->"; then
        echo "[*] Detectado PostgreSQL local ocupando a porta 5432. Pausando servico local..."
        if [ -x "$HOME/.local/bin/pg_ctl" ]; then
            "$HOME/.local/bin/pg_ctl" -D "$HOME/.pg_local/data" stop 2>/dev/null || true
        elif [ -x "$HOME/.pg_bin/usr/bin/pg_ctl" ]; then
            "$HOME/.pg_bin/usr/bin/pg_ctl" -D "$HOME/.pg_local/data" stop 2>/dev/null || true
        elif [ -d "$HOME/.pg_local/data" ] && command -v pg_ctl &>/dev/null; then
            pg_ctl -D "$HOME/.pg_local/data" stop 2>/dev/null || true
        fi
        sudo systemctl stop postgresql 2>/dev/null || true
        sleep 1
    fi
fi

# Liberar porta 3001 se ocupada por processo local
if ss -tlpn 2>/dev/null | grep -qE ":3001[[:space:]]"; then
    if ! docker ps --format '{{.Ports}}' 2>/dev/null | grep -qE ":3001->"; then
        echo "[*] Detectado processo local ocupando a porta 3001. Encerrando processo..."
        if command -v fuser &>/dev/null; then
            fuser -k -n tcp 3001 2>/dev/null || true
        elif command -v lsof &>/dev/null; then
            lsof -ti :3001 -sTCP:LISTEN 2>/dev/null | xargs -r kill -9 2>/dev/null || true
        fi
        sleep 1
    fi
fi

echo "[*] Iniciando plataforma BeautyFlow..."
PROF_ARG=""
if [ -f "$SCRIPT_DIR/.env" ] && grep -q "INSTALL_WAHA=true" "$SCRIPT_DIR/.env"; then
    PROF_ARG="--profile waha"
fi

$COMPOSE_CMD $PROF_ARG up -d

echo "[*] Aguardando servicos inicializarem e passarem no healthcheck..."
for i in $(seq 1 35); do
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
        echo "Executar para diagnostico: $COMPOSE_CMD logs --tail=50"
        exit 1
    fi
    if [ "$all_ok" -eq 1 ]; then
        break
    fi
    sleep 2
done

echo ""
echo "=================================================================="
echo " [OK] Plataforma BeautyFlow iniciada com sucesso!"
echo "=================================================================="
echo "  • CRM BeautyFlow (Gestao):   http://localhost:3001 (admin / admin)"
echo "  • Portal de Agendamento:     http://localhost:5173"
LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || hostname -I 2>/dev/null | awk '{print $1}' || echo "")
if [ -n "$LOCAL_IP" ] && [ "$LOCAL_IP" != "127.0.0.1" ]; then
    echo "  • Acesso Mobile (mesmo Wi-Fi): http://$LOCAL_IP:5173"
fi
echo "  • Banco de Dados PostgreSQL: localhost:5432"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^(beautyflow-waha|waha)$'; then
    echo "  • WhatsApp WAHA (Porta 3000): http://localhost:3000"
    echo "  • Dashboard / QR Code:        http://localhost:3000/dashboard"
fi
echo "=================================================================="
