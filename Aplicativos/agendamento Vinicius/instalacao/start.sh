#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-dev}"

DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$MODE" = "docker" ]; then
  cd "$(dirname "$0")"
  exec docker compose up
fi

cd "$DIR"

if [ ! -d "node_modules" ]; then
  echo "  node_modules não encontrado. Executando npm install..."
  npm install
  echo ""
fi

if [ "$MODE" = "preview" ]; then
  echo "============================================"
  echo "  BeautyFlow Agendamento — Preview"
  echo "============================================"
  echo ""
  exec npm run preview
fi

echo "============================================"
echo "  BeautyFlow Agendamento — Dev Server"
echo "============================================"
echo ""
echo "  Servidor: http://localhost:5173"
echo "  Pressione Ctrl+C para parar"
echo ""

exec npm run dev
