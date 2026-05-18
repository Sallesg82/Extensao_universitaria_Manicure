#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/Sallesg82/Extensao_universitaria_Manicure.git"

echo "============================================"
echo "  BeautyFlow CRM — Instalação"
echo "============================================"
echo ""

# ────────── Detectar SO ──────────
OS="$(uname -s)"
case "$OS" in
  Linux)  OS="linux"  ;;
  Darwin) OS="macos"  ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "  Windows detectado. Use WSL (Ubuntu) ou Docker."
    echo "  Docker: bash install.sh docker"
    echo "  WSL:   rode este script dentro do WSL."
    exit 1
    ;;
  *)
    echo "  SO não suportado: $OS"
    exit 1
    ;;
esac
echo "  SO: $OS"

# ────────── Detectar se está dentro do repositório ──────────
INSIDE_REPO=false
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  BASENAME="$(basename "$(git rev-parse --show-toplevel)")"
  if [ "$BASENAME" = "Extensao_universitaria_Manicure" ]; then
    INSIDE_REPO=true
  fi
fi

MODE="${1:-native}"

# ────────── Modo Docker ──────────
if [ "$MODE" = "docker" ]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "  ERRO: docker não encontrado."
    echo "  Instale: https://docs.docker.com/engine/install/"
    exit 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    echo "  ERRO: docker compose não encontrado (versão 2+)."
    exit 1
  fi
  echo "  ✓ docker $(docker --version | cut -d' ' -f3 | tr -d ',')"
  echo "  ✓ docker compose $(docker compose version | awk '{print $4}' | tr -d ',')"

  if [ "$INSIDE_REPO" = false ]; then
    echo ""
    echo "  Clonando repositório..."
    git clone "$REPO_URL" /tmp/Extensao_universitaria_Manicure
    cd "/tmp/Extensao_universitaria_Manicure/Aplicativos/CRM-Mirian (protótipo)/instalacao"
  else
    cd "$(dirname "$0")"
  fi

  # Diretório backend (para o .env)
  if [ "$INSIDE_REPO" = false ]; then
    ENV_DIR="/tmp/Extensao_universitaria_Manicure/Aplicativos/CRM-Mirian (protótipo)/backend"
  else
    ENV_DIR="$(cd "$(dirname "$0")/../backend" && pwd)"
  fi
  ENV_FILE="$ENV_DIR/.env"

  # Credenciais Supabase
  echo ""
  echo "── Configuração do Supabase ──"
  echo "  Crie um projeto em https://supabase.com"
  echo "  E copie as 4 credenciais (Project Settings > API)"
  echo ""
  read -r -p "  SUPABASE_URL (ex: https://xxxxx.supabase.co): " SUPABASE_URL
  read -r -p "  SUPABASE_ANON_KEY (anon public): " SUPABASE_ANON_KEY
  read -r -p "  SUPABASE_KEY (service_role secret): " SUPABASE_KEY
  read -r -p "  SUPABASE_JWT_SECRET (JWT Secret): " SUPABASE_JWT_SECRET
  cat > "$ENV_FILE" <<EOF
SUPABASE_URL=$SUPABASE_URL
SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
SUPABASE_KEY=$SUPABASE_KEY
SUPABASE_JWT_SECRET=$SUPABASE_JWT_SECRET
EOF
  echo "  ✓ .env salvo em $ENV_FILE"
  echo "  ⚠ Execute o script SQL em backend/db/supabase_schema.sql no SQL Editor do Supabase"
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
  echo "  Acessar: http://localhost:3001"
  echo ""
  echo "  Para parar: docker compose down"
  echo "  Para ver logs: docker compose logs -f"
  echo ""
  exit 0
fi

# ══════════════════════════════════════════
#  Instalação Nativa
# ══════════════════════════════════════════

# ────────── Verificar / Instalar dependências do sistema ──────────
echo "[1/6] Verificando dependências do sistema..."

MISSING=()
NEED_VENV=false

if ! command -v python3 >/dev/null 2>&1; then
  MISSING+=("python3")
fi

if ! python3 -c "import venv" >/dev/null 2>&1; then
  NEED_VENV=true
  if [ "$OS" = "linux" ]; then
    MISSING+=("python3-venv")
  fi
fi

if ! command -v git >/dev/null 2>&1; then
  MISSING+=("git")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
  echo ""
  echo "  ⚠ Faltam os seguintes pacotes: ${MISSING[*]}"

  if [ "$OS" = "linux" ]; then
    # Detectar gerenciador de pacotes
    if command -v apt >/dev/null 2>&1; then
      PKG_MGR="apt"
      INSTALL_CMD="sudo apt install -y ${MISSING[*]}"
    elif command -v dnf >/dev/null 2>&1; then
      PKG_MGR="dnf"
      INSTALL_CMD="sudo dnf install -y ${MISSING[*]}"
    elif command -v pacman >/dev/null 2>&1; then
      PKG_MGR="pacman"
      INSTALL_CMD="sudo pacman -S --noconfirm ${MISSING[*]}"
    else
      echo "  Nenhum gerenciador de pacotes conhecido (apt/dnf/pacman)."
      echo "  Instale manualmente: ${MISSING[*]}"
      exit 1
    fi
    echo "  Gerenciador detectado: $PKG_MGR"

    read -r -p "  Deseja instalar com '$INSTALL_CMD'? [s/N] " RESP
    if [ "$RESP" != "s" ] && [ "$RESP" != "S" ]; then
      echo "  Instalação cancelada pelo usuário."
      exit 1
    fi
    eval "$INSTALL_CMD"
    echo "  ✓ Pacotes instalados"

    # Garantir que python3-venv funcionou
    if $NEED_VENV && ! python3 -c "import venv" >/dev/null 2>&1; then
      echo "  ERRO: python3-venv não disponível mesmo após instalação."
      echo "  Tente: sudo apt install python3-venv  (ou equivalente)"
      exit 1
    fi

  elif [ "$OS" = "macos" ]; then
    if ! command -v brew >/dev/null 2>&1; then
      echo "  Homebrew não encontrado. Instale em: https://brew.sh"
      echo "  Ou instale manualmente: ${MISSING[*]}"
      exit 1
    fi
    BREW_PKGS=()
    for pkg in "${MISSING[@]}"; do
      [ "$pkg" = "python3-venv" ] && pkg="python"
      BREW_PKGS+=("$pkg")
    done
    INSTALL_CMD="brew install ${BREW_PKGS[*]}"
    echo "  Comando: $INSTALL_CMD"

    read -r -p "  Deseja executar? [s/N] " RESP
    if [ "$RESP" != "s" ] && [ "$RESP" != "S" ]; then
      echo "  Instalação cancelada pelo usuário."
      exit 1
    fi
    eval "$INSTALL_CMD"
    echo "  ✓ Pacotes instalados"
  fi
else
  echo "  ✓ python3 $(python3 --version | cut -d' ' -f2)"
  echo "  ✓ python3-venv disponível"
  command -v git >/dev/null 2>&1 && echo "  ✓ git $(git --version | cut -d' ' -f3)"
fi
echo ""

# ────────── Clonar se necessário ──────────
if [ "$INSIDE_REPO" = false ]; then
  echo "  Repositório não encontrado. Clonando..."
  TARGET="/tmp/Extensao_universitaria_Manicure"
  if [ -d "$TARGET" ]; then
    echo "  Diretório $TARGET já existe. Atualizando..."
    cd "$TARGET" && git pull
  else
    git clone "$REPO_URL" "$TARGET"
  fi
  CRM_DIR="$TARGET/Aplicativos/CRM-Mirian (protótipo)"
  cd "$CRM_DIR/instalacao"
  DIR="$CRM_DIR"
  VENV_DIR="$DIR/backend/.venv"
  echo "  ✓ Repositório clonado em $TARGET"
  echo ""
else
  DIR="$(cd "$(dirname "$0")/.." && pwd)"
  VENV_DIR="$DIR/backend/.venv"
fi

# ────────── Ambiente virtual ──────────
echo "[2/6] Criando ambiente virtual..."
if [ -d "$VENV_DIR" ]; then
  echo "  ✓ Ambiente virtual já existe em $VENV_DIR"
else
  python3 -m venv "$VENV_DIR"
  echo "  ✓ Ambiente criado em $VENV_DIR"
fi
echo ""

# ────────── Dependências Python ──────────
echo "[3/6] Instalando dependências Python..."
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet flask flask-cors requests supabase werkzeug google-auth google-auth-oauthlib google-api-python-client python-dateutil postgrest
echo "  ✓ Dependências Python instaladas (Flask, Supabase, Google API, etc.)"
echo ""

# ────────── Credenciais Supabase ──────────
echo "[4/6] Configurando credenciais do Supabase..."
ENV_FILE="$DIR/backend/.env"
DO_SETUP=true
if [ -f "$ENV_FILE" ]; then
  echo "  ✓ .env já existe em $ENV_FILE"
  read -r -p "  Deseja sobrescrever? [s/N] " RESP
  [ "$RESP" != "s" ] && [ "$RESP" != "S" ] && DO_SETUP=false
fi

if [ "$DO_SETUP" = true ]; then
  echo ""
  echo "── Configuração do Supabase (banco de dados) ──"
  echo "  Crie um projeto em https://supabase.com"
  echo "  E copie as credenciais em Project Settings → API"
  echo ""
  echo "  São 4 credenciais:"
  echo "    1. Project URL"
  echo "    2. anon public key"
  echo "    3. service_role key (secret)"
  echo "    4. JWT Secret"
  echo ""
  read -r -p "  SUPABASE_URL (ex: https://xxxxx.supabase.co): " SUPABASE_URL
  read -r -p "  SUPABASE_ANON_KEY (anon public): " SUPABASE_ANON_KEY
  read -r -p "  SUPABASE_KEY (service_role secret): " SUPABASE_KEY
  read -r -p "  SUPABASE_JWT_SECRET (JWT Secret): " SUPABASE_JWT_SECRET

  cat > "$ENV_FILE" <<EOF
SUPABASE_URL=$SUPABASE_URL
SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
SUPABASE_KEY=$SUPABASE_KEY
SUPABASE_JWT_SECRET=$SUPABASE_JWT_SECRET
EOF
  echo "  ✓ .env salvo em $ENV_FILE"
  echo "  ⚠ Lembre-se de executar o script SQL em:"
  echo "    $DIR/backend/db/supabase_schema.sql"
  echo "    no SQL Editor do seu projeto Supabase"
  echo ""
fi

# ────────── Verificar Supabase ──────────
echo "[5/6] Verificando conexão com Supabase..."
set -a
[ -f "$ENV_FILE" ] && source "$ENV_FILE"
set +a
"$VENV_DIR/bin/python" -c "
import sys, os
sys.path.insert(0, '$DIR/backend')
from db.database import get_db
db = get_db()
print('  ✓ Conexão com Supabase OK')
" 2>&1 || echo "  ⚠ Não foi possível conectar ao Supabase. Verifique as credenciais."
echo ""

# ────────── Resumo final ──────────
echo "[6/6] Concluído!"
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
