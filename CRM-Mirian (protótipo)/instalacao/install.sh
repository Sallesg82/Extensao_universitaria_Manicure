#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV_DIR="$DIR/backend/.venv"

echo "============================================"
echo "  BeautyFlow CRM — Instalação"
echo "============================================"
echo ""

# ---------- Modo: Docker ou Native ----------
MODE="${1:-native}"

if [ "$MODE" = "docker" ]; then
  echo "[1/3] Verificando Docker..."
  command -v docker >/dev/null 2>&1 || { echo "ERRO: docker não encontrado."; exit 1; }
  echo "  ✓ docker $(docker --version | cut -d' ' -f3 | tr -d ',')"

  echo "[2/3] Build da imagem..."
  cd "$(dirname "$0")"
  docker compose build
  echo "  ✓ Imagem criada"

  echo "[3/3] Iniciando container..."
  docker compose up -d
  echo "  ✓ Container rodando"

  echo ""
  echo "============================================"
  echo "  Instalação Docker concluída!"
  echo "============================================"
  echo ""
  echo "  Acessar: http://localhost:3001"
  echo ""
  echo "  Para parar: docker compose down"
  echo "  Para ver logs: docker compose logs -f"
  echo ""
  exit 0
fi

# ────────── Instalação Native ──────────

echo "[1/4] Verificando pré-requisitos..."
command -v python3 >/dev/null 2>&1 || { echo "ERRO: python3 não encontrado. Instale Python 3.14+."; exit 1; }
echo "  ✓ python3 $(python3 --version | cut -d' ' -f2)"

command -v git >/dev/null 2>&1 || echo "  ⚠ git não encontrado (apenas para clonar)"

echo ""

echo "[2/4] Criando ambiente virtual..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
echo "  ✓ Ambiente criado em $VENV_DIR"

echo "[3/4] Instalando dependências..."
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet flask flask-cors
echo "  ✓ Dependências instaladas (Flask, Flask-CORS)"

echo "[4/4] Inicializando banco de dados..."
"$VENV_DIR/bin/python" -c "
import sys
sys.path.insert(0, '$DIR/backend')
from db.database import get_db
conn = get_db()
conn.close()
print('  ✓ Banco criado e populado com dados de demonstração')
"
echo ""

echo "============================================"
echo "  Instalação concluída!"
echo "============================================"
echo ""
echo "  Para iniciar o servidor:"
echo "    cd \"$DIR/instalacao\" && bash start.sh"
echo ""
echo "  Alternativa via Docker:"
echo "    cd \"$DIR/instalacao\" && bash install.sh docker"
echo ""
echo "  Acessar: http://localhost:3001"
echo ""
