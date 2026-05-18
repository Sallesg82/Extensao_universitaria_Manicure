#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-native}"

if [ "$MODE" = "docker" ]; then
  cd "$(dirname "$0")"
  exec docker compose up
fi

DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV_DIR="$DIR/backend/.venv"
ENV_FILE="$DIR/backend/.env"

if [ ! -d "$VENV_DIR" ]; then
  echo "Ambiente virtual não encontrado."
  echo "Execute: bash install.sh"
  echo "Ou via Docker: bash start.sh docker"
  exit 1
fi

# Carregar credenciais do Supabase
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

echo "Iniciando BeautyFlow CRM..."
echo "  Servidor: http://localhost:3001"
echo "  Pressione Ctrl+C para parar"
echo ""

exec "$VENV_DIR/bin/python" "$DIR/backend/server.py"
