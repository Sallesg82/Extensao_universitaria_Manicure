#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$DIR/.." && pwd)"
DB_PATH="$BASE/DB/beautyflow.db"
CRM_DIR="$BASE/CRM-Mirian (protótipo)"
APP_DIR="$BASE/agendamento Vinicius"

MODO="${1:-ambos}"

kill_port() {
  local port=$1
  if command -v fuser >/dev/null 2>&1; then
    fuser -k "${port}/tcp" 2>/dev/null || true
  elif command -v lsof >/dev/null 2>&1; then
    local pids
    pids=$(lsof -t -i :"$port" 2>/dev/null) || true
    [ -n "$pids" ] && kill $pids 2>/dev/null || true
  fi
  sleep 0.5
}

echo "╔══════════════════════════════════════════════╗"
echo "║        BeautyFlow — Iniciar                  ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

if [ ! -f "$DB_PATH" ]; then
  echo "  Banco não encontrado. Execute install.sh primeiro."
  exit 1
fi
echo "  Banco: $DB_PATH"
echo ""

iniciar_crm() {
  if [ ! -d "$CRM_DIR/backend/.venv" ]; then
    echo "  CRM não instalado. Execute install.sh"
    exit 1
  fi
  echo "  Parando instância anterior do CRM..."
  kill_port 3001
  echo "  Iniciando CRM (http://localhost:3001)..."
  export BEAUTYFLOW_DB_PATH="$DB_PATH"
  export BEAUTYFLOW_NO_SEED="true"
  rm -f /tmp/beautyflow_crm.log
  cd "$CRM_DIR"
  nohup backend/.venv/bin/python backend/server.py > /tmp/beautyflow_crm.log 2>&1 &
  echo "  ✓ CRM rodando (PID $!)"
  cd "$DIR"
}

iniciar_agenda() {
  if [ ! -d "$APP_DIR/node_modules" ]; then
    echo "  Agendamento não instalado. Execute install.sh"
    exit 1
  fi
  echo "  Parando instância anterior do Agendamento..."
  kill_port 5173
  echo "  Iniciando Agendamento (http://localhost:5173)..."
  rm -f /tmp/beautyflow_agenda.log
  cd "$APP_DIR"
  nohup npm run dev > /tmp/beautyflow_agenda.log 2>&1 &
  echo "  ✓ Agendamento rodando (PID $!)"
  cd "$DIR"
}

case "$MODO" in
  crm)
    iniciar_crm
    ;;
  agenda)
    iniciar_agenda
    echo "  ⚠ Certifique-se de que o CRM está rodando em :3001"
    ;;
  ambos|*)
    iniciar_crm
    iniciar_agenda
    echo ""
    echo "  CRM:        http://localhost:3001"
    echo "  Agendamento: http://localhost:5173"
    ;;
esac
