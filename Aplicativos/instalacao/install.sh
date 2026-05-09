#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/Sallesg82/Extensao_universitaria_Manicure.git"
DIR="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$DIR/.." && pwd)"
DB_DIR="$BASE/DB"
DB_PATH="$DB_DIR/beautyflow.db"

echo "╔══════════════════════════════════════════════╗"
echo "║         BeautyFlow — Instalador Unificado    ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ────────── SO ──────────
OS="$(uname -s)"
case "$OS" in
  Linux)  OS="linux"  ;;
  Darwin) OS="macos"  ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "  Windows detectado. Execute install.bat"
    exit 1
    ;;
  *)
    echo "  SO não suportado: $OS"; exit 1
    ;;
esac
echo "  SO: $OS"
echo ""

# ────────── Detectar repo ──────────
INSIDE_REPO=false
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  [ "$(basename "$(git rev-parse --show-toplevel)")" = "Extensao_universitaria_Manicure" ] && INSIDE_REPO=true
fi

if [ "$INSIDE_REPO" = false ]; then
  echo "  Clonando repositório..."
  TARGET="/tmp/Extensao_universitaria_Manicure"
  [ -d "$TARGET" ] && rm -rf "$TARGET"
  git clone "$REPO_URL" "$TARGET"
  DIR="$TARGET/Aplicativos/instalacao"
  BASE="$TARGET/Aplicativos"
  DB_DIR="$TARGET/Aplicativos/DB"
  DB_PATH="$DB_DIR/beautyflow.db"
  cd "$DIR"
  echo "  ✓ Repositório clonado"
  echo ""
fi

MODE="${1:-menu}"

# ══════════════════════════════════════════
#  FUNÇÕES
# ══════════════════════════════════════════

instalar_dependencias_base() {
  echo ""
  echo "── Verificando dependências base ──"

  local MISSING=()
  command -v git >/dev/null 2>&1 || MISSING+=("git")
  command -v sqlite3 >/dev/null 2>&1 || MISSING+=("sqlite3")

  if [ ${#MISSING[@]} -gt 0 ]; then
    echo "  ⚠ Faltam: ${MISSING[*]}"
    if command -v apt >/dev/null 2>&1; then
      read -r -p "  Instalar com sudo apt? [s/N] " RESP
      [ "$RESP" != "s" ] && [ "$RESP" != "S" ] && { echo "  Cancelado"; exit 1; }
      sudo apt install -y "${MISSING[@]}"
    elif command -v dnf >/dev/null 2>&1; then
      read -r -p "  Instalar com sudo dnf? [s/N] " RESP
      [ "$RESP" != "s" ] && [ "$RESP" != "S" ] && { echo "  Cancelado"; exit 1; }
      sudo dnf install -y "${MISSING[@]}"
    elif command -v pacman >/dev/null 2>&1; then
      read -r -p "  Instalar com sudo pacman? [s/N] " RESP
      [ "$RESP" != "s" ] && [ "$RESP" != "S" ] && { echo "  Cancelado"; exit 1; }
      sudo pacman -S --noconfirm "${MISSING[@]}"
    else
      echo "  Instale manualmente: ${MISSING[*]}"; exit 1
    fi
    echo "  ✓ Instalados"
  else
    echo "  ✓ git"; echo "  ✓ sqlite3"
  fi
}

criar_banco() {
  echo ""
  echo "── Banco de Dados ──"
  mkdir -p "$DB_DIR"
  if [ -f "$DB_PATH" ]; then
    echo "  ✓ Banco já existe em:"
    echo "    $DB_PATH"
  else
    sqlite3 "$DB_PATH" < "$DIR/init_db.sql"
    echo "  ✓ Banco criado em:"
    echo "    $DB_PATH"
    echo "  ✓ Tabelas criadas (sem dados)"
  fi
}

instalar_crm() {
  echo ""
  echo "── Instalando BeautyFlow CRM ──"
  local CRM_DIR="$BASE/CRM-Mirian (protótipo)"
  local VENV_DIR="$CRM_DIR/backend/.venv"
  local INST_DIR="$CRM_DIR/instalacao"

  # Python
  if ! command -v python3 >/dev/null 2>&1; then
    echo "  ⚠ python3 não encontrado"
    if command -v apt >/dev/null 2>&1; then
      read -r -p "  Instalar python3? [s/N] " R
      [ "$R" != "s" ] && [ "$R" != "S" ] && { echo "  Cancelado"; exit 1; }
      sudo apt install -y python3 python3-venv
    else
      echo "  Instale python3 manualmente"; exit 1
    fi
  fi

  # venv
  if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
    echo "  ✓ venv criado"
  fi

  # pip
  "$VENV_DIR/bin/pip" install --quiet --upgrade pip
  "$VENV_DIR/bin/pip" install --quiet flask flask-cors
  echo "  ✓ Dependências Python instaladas"

  echo "  ✓ CRM pronto (use start.sh para iniciar)"
}

instalar_agendamento() {
  echo ""
  echo "── Instalando BeautyFlow Agendamento ──"
  local APP_DIR="$BASE/agendamento Vinicius"

  if ! command -v node >/dev/null 2>&1; then
    echo "  ⚠ Node.js não encontrado"
    if command -v apt >/dev/null 2>&1; then
      read -r -p "  Instalar Node.js? [s/N] " R
      [ "$R" != "s" ] && [ "$R" != "S" ] && { echo "  Cancelado"; exit 1; }
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
      sudo apt install -y nodejs
    else
      echo "  Instale Node.js manualmente: https://nodejs.org"; exit 1
    fi
  fi
  echo "  ✓ node $(node --version)"

  cd "$APP_DIR"
  npm install --silent
  echo "  ✓ Dependências npm instaladas"
  cd "$DIR"
}

iniciar_crm() {
  local CRM_DIR="$BASE/CRM-Mirian (protótipo)"
  local VENV_DIR="$CRM_DIR/backend/.venv"

  echo ""
  echo "  Iniciando CRM em http://localhost:3001 ..."
  export BEAUTYFLOW_DB_PATH="$DB_PATH"
  export BEAUTYFLOW_NO_SEED="true"
  nohup "$VENV_DIR/bin/python" "$CRM_DIR/backend/server.py" > /tmp/beautyflow_crm.log 2>&1 &
  sleep 2
  echo "  ✓ CRM rodando (PID $!)"
}

iniciar_agendamento() {
  local APP_DIR="$BASE/agendamento Vinicius"

  echo ""
  echo "  Iniciando Agendamento em http://localhost:5173 ..."
  cd "$APP_DIR"
  nohup npm run dev > /tmp/beautyflow_agenda.log 2>&1 &
  sleep 2
  echo "  ✓ Agendamento rodando (PID $!)"
  cd "$DIR"
}

instalar_docker() {
  echo ""
  echo "── Docker ──"
  if command -v docker >/dev/null 2>&1; then
    echo "  ✓ docker $(docker --version | cut -d' ' -f3 | tr -d ',')"
    return 0
  fi

  echo "  ⚠ Docker não encontrado."

  if [ "$OS" = "linux" ]; then
    if command -v apt >/dev/null 2>&1; then
      echo "  O Docker será instalado via script oficial (get.docker.com)."
      read -r -p "  Deseja instalar o Docker? [s/N] " R
      [ "$R" != "s" ] && [ "$R" != "S" ] && { echo "  Cancelado"; exit 1; }
      curl -fsSL https://get.docker.com | sudo sh
      sudo usermod -aG docker "$USER"
      echo "  ✓ Docker instalado! Faça logout/login para usar sem sudo."
      command -v docker >/dev/null 2>&1 || { echo "  ERRO: falha ao instalar Docker"; exit 1; }
    elif command -v dnf >/dev/null 2>&1; then
      read -r -p "  Instalar docker com sudo dnf? [s/N] " R
      [ "$R" != "s" ] && [ "$R" != "S" ] && { echo "  Cancelado"; exit 1; }
      sudo dnf install -y docker docker-compose
      sudo systemctl enable --now docker
      echo "  ✓ Docker instalado"
    elif command -v pacman >/dev/null 2>&1; then
      read -r -p "  Instalar docker com sudo pacman? [s/N] " R
      [ "$R" != "s" ] && [ "$R" != "S" ] && { echo "  Cancelado"; exit 1; }
      sudo pacman -S --noconfirm docker docker-compose
      sudo systemctl enable --now docker
      echo "  ✓ Docker instalado"
    else
      echo "  Instale manualmente: https://docs.docker.com/engine/install/"
      exit 1
    fi
  elif [ "$OS" = "macos" ]; then
    echo "  Baixe o Docker Desktop em: https://docs.docker.com/desktop/setup/install/mac-install/"
    read -r -p "  Deseja abrir o site? [s/N] " R
    [ "$R" = "s" ] || [ "$R" = "S" ] && open "https://docs.docker.com/desktop/setup/install/mac-install/"
    exit 1
  fi
}

verificar_docker_compose() {
  if ! docker compose version >/dev/null 2>&1; then
    echo "  ⚠ docker compose v2+ não encontrado."
    echo "  Atualize o Docker para a versão mais recente."
    exit 1
  fi
  echo "  ✓ docker compose $(docker compose version | awk '{print $4}' | tr -d ',')"
}

modo_docker() {
  instalar_docker
  verificar_docker_compose

  # Docker mode: se o banco já existe, pergunta se quer limpar
  echo ""
  echo "── Banco de Dados ──"
  mkdir -p "$DB_DIR"
  if [ -f "$DB_PATH" ]; then
    echo "  Banco existente: $DB_PATH"
    read -r -p "  Limpar banco (remover dados existentes)? [s/N] " R
    if [ "$R" = "s" ] || [ "$R" = "S" ]; then
      rm -f "$DB_PATH"
      sqlite3 "$DB_PATH" < "$DIR/init_db.sql"
      echo "  ✓ Banco limpo e recriado vazio"
    else
      echo "  ✓ Banco mantido"
    fi
  else
    sqlite3 "$DB_PATH" < "$DIR/init_db.sql"
    echo "  ✓ Banco criado vazio em: $DB_PATH"
  fi

  # Remove containers antigos para aplicar nova config
  docker compose down 2>/dev/null || true

  local UP=""
  if [ "$1" = "crm" ] || [ "$1" = "ambos" ]; then
    echo ""
    echo "  Build CRM..."
    docker compose build crm
    UP+="crm "
  fi
  if [ "$1" = "agenda" ] || [ "$1" = "ambos" ]; then
    echo ""
    echo "  Build Agendamento..."
    docker compose build agenda
    UP+="agenda "
  fi

  echo ""
  echo "  Iniciando containers: $UP"
  docker compose up -d $UP
  echo "  ✓ Containers rodando"
}

# ══════════════════════════════════════════
#  MENU INTERATIVO
# ══════════════════════════════════════════

if [ "$MODE" = "menu" ]; then
  echo "Escolha o que deseja instalar:"
  echo ""
  echo "  1) Ambos (CRM + Agendamento) ← RECOMENDADO"
  echo "  2) BeautyFlow CRM (gestão do salão)"
  echo "  3) BeautyFlow Agendamento (painel do cliente)"
  echo "  4) Docker — Ambos (container)"
  echo ""
  read -r -p "Digite o número [1-4] (padrão 1): " ESCOLHA
  ESCOLHA="${ESCOLHA:-1}"
  echo ""
fi

# ────────── Execução ──────────

case "${ESCOLHA:-$MODE}" in
  1|ambos)
    instalar_dependencias_base
    criar_banco
    instalar_crm
    instalar_agendamento
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║  Instalação concluída!                       ║"
    echo "║                                              ║"
    echo "║  Para iniciar:                               ║"
    echo "║    bash \"$DIR/start.sh\" ambos            ║"
    echo "║                                              ║"
    echo "║  CRM:        http://localhost:3001            ║"
    echo "║  Agendamento: http://localhost:5173           ║"
    echo "╚══════════════════════════════════════════════╝"
    ;;
  2|crm)
    instalar_dependencias_base
    criar_banco
    instalar_crm
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║  Instalação concluída!                       ║"
    echo "║                                              ║"
    echo "║  Para iniciar o CRM:                         ║"
    echo "║    bash \"$DIR/start.sh\" crm              ║"
    echo "║                                              ║"
    echo "║  Acessar: http://localhost:3001              ║"
    echo "╚══════════════════════════════════════════════╝"
    ;;
  3|agenda)
    instalar_dependencias_base
    criar_banco
    instalar_agendamento
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║  Instalação concluída!                       ║"
    echo "║                                              ║"
    echo "║  Para iniciar o Agendamento:                 ║"
    echo "║    bash \"$DIR/start.sh\" agenda           ║"
    echo "║                                              ║"
    echo "║  Acessar: http://localhost:5173              ║"
    echo "║  (CRM deve estar rodando em :3001)           ║"
    echo "╚══════════════════════════════════════════════╝"
    ;;
  4|docker)
    instalar_dependencias_base
    modo_docker "ambos"
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║  Docker concluído!                           ║"
    echo "║                                              ║"
    echo "║  CRM:        http://localhost:3001            ║"
    echo "║  Agendamento: http://localhost:5173           ║"
    echo "╚══════════════════════════════════════════════╝"
    ;;
  *)
    echo "  Opção inválida: $ESCOLHA"; exit 1
    ;;
esac
