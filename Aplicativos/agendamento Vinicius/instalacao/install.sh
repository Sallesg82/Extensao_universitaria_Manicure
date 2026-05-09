#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/Sallesg82/Extensao_universitaria_Manicure.git"

echo "============================================"
echo "  BeautyFlow Agendamento — Instalação"
echo "============================================"
echo ""

# ────────── Detectar SO ──────────
OS="$(uname -s)"
case "$OS" in
  Linux)  OS="linux"  ;;
  Darwin) OS="macos"  ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "  Windows detectado. Use:"
    echo "    Docker: bash install.sh docker"
    echo "    WSL:   rode dentro do WSL"
    echo "    Nativo: instale Node.js manualmente e execute:"
    echo "      npm install && npm run dev"
    exit 1
    ;;
  *)
    echo "  SO não suportado: $OS"
    exit 1
    ;;
esac
echo "  SO: $OS"
echo ""

# ────────── Detectar se está dentro do repositório ──────────
INSIDE_REPO=false
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  BASENAME="$(basename "$(git rev-parse --show-toplevel)")"
  [ "$BASENAME" = "Extensao_universitaria_Manicure" ] && INSIDE_REPO=true
fi

MODE="${1:-native}"

# ══════════════════════════════════════════
#  Modo Docker
# ══════════════════════════════════════════
if [ "$MODE" = "docker" ]; then
  echo "[1/3] Verificando Docker..."
  command -v docker >/dev/null 2>&1 || { echo "  ERRO: docker não encontrado."; exit 1; }
  docker compose version >/dev/null 2>&1 || { echo "  ERRO: docker compose v2+ não encontrado."; exit 1; }
  echo "  ✓ docker $(docker --version | cut -d' ' -f3 | tr -d ',')"
  echo "  ✓ docker compose $(docker compose version | awk '{print $4}' | tr -d ',')"

  if [ "$INSIDE_REPO" = false ]; then
    echo ""
    echo "  Clonando repositório..."
    TARGET="/tmp/Extensao_universitaria_Manicure"
    [ -d "$TARGET" ] && rm -rf "$TARGET"
    git clone "$REPO_URL" "$TARGET"
    cd "$TARGET/Aplicativos/agendamento Vinicius/instalacao"
  else
    cd "$(dirname "$0")"
  fi

  echo ""
  echo "  Build da imagem..."
  docker compose build
  echo "  ✓ Imagem criada"

  echo ""
  echo "  Iniciando container..."
  docker compose up -d
  echo "  ✓ Container rodando"

  echo ""
  echo "============================================"
  echo "  Instalação Docker concluída!"
  echo "============================================"
  echo ""
  echo "  Acessar: http://localhost:5173"
  echo "  (O CRM deve estar rodando em http://localhost:3001)"
  echo ""
  echo "  Para parar: docker compose down"
  echo ""
  exit 0
fi

# ══════════════════════════════════════════
#  Instalação Nativa
# ══════════════════════════════════════════

# ────────── Verificar / Instalar Node.js ──────────
echo "[1/4] Verificando dependências..."

MISSING=()

if ! command -v node >/dev/null 2>&1; then
  MISSING+=("nodejs")
elif ! command -v npm >/dev/null 2>&1; then
  MISSING+=("npm")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "  ⚠ Faltam: ${MISSING[*]}"
  echo ""

  if [ "$OS" = "linux" ]; then
    if command -v apt >/dev/null 2>&1; then
      echo "  Detectedo apt. Instalando Node.js via NodeSource..."
      read -r -p "  Deseja instalar Node.js? [s/N] " RESP
      if [ "$RESP" != "s" ] && [ "$RESP" != "S" ]; then
        echo "  Instalação cancelada."
        exit 1
      fi
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
      sudo apt install -y nodejs
      echo "  ✓ Node.js $(node --version) instalado"
    elif command -v dnf >/dev/null 2>&1; then
      echo "  Para instalar Node.js no Fedora:"
      echo "    sudo dnf install nodejs"
      exit 1
    elif command -v pacman >/dev/null 2>&1; then
      echo "  Para instalar Node.js no Arch:"
      echo "    sudo pacman -S nodejs npm"
      exit 1
    else
      echo "  Instale Node.js manualmente: https://nodejs.org"
      exit 1
    fi
  elif [ "$OS" = "macos" ]; then
    echo "  Recomendado instalar via Homebrew:"
    echo "    brew install node"
    exit 1
  fi
else
  echo "  ✓ node $(node --version)"
  echo "  ✓ npm $(npm --version)"
fi
echo ""

# ────────── Verificar clonagem ──────────
if [ "$INSIDE_REPO" = false ]; then
  echo "  Repositório não encontrado. Clonando..."
  TARGET="/tmp/Extensao_universitaria_Manicure"
  [ -d "$TARGET" ] && rm -rf "$TARGET"
  git clone "$REPO_URL" "$TARGET"
  APP_DIR="$TARGET/Aplicativos/agendamento Vinicius"
  cd "$APP_DIR"
  echo "  ✓ Repositório clonado"
  echo ""
else
  APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
  cd "$APP_DIR"
fi

# ────────── npm install ──────────
echo "[2/4] Instalando dependências npm..."
npm install --silent
echo "  ✓ Dependências instaladas"
echo ""

# ────────── Build (opcional) ──────────
echo "[3/4] Build de produção..."
npx vite build --silent 2>/dev/null
echo "  ✓ Build concluído (dist/)"
echo ""

# ────────── Resumo ──────────
echo "[4/4] Concluído!"
echo ""
echo "============================================"
echo "  Instalação concluída!"
echo "============================================"
echo ""
echo "  Para iniciar o servidor de desenvolvimento:"
echo "    cd \"$APP_DIR\" && npm run dev"
echo ""
echo "  Modo preview (após build):"
echo "    cd \"$APP_DIR\" && npm run preview"
echo ""
echo "  Acessar: http://localhost:5173"
echo ""
echo "  ⚠ ATENÇÃO: O CRM deve estar rodando em http://localhost:3001"
echo "    para o agendamento funcionar corretamente."
echo ""
echo "  Via Docker:"
echo "    cd \"$(dirname "$0")\" && bash install.sh docker"
echo ""
