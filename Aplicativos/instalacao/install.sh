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
    PERGUNTAR_INSTALACAO "${MISSING[*]}" "${MISSING[@]}"
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
    echo "  ✓ Banco criado vazio em:"
    echo "    $DB_PATH"
    echo "  ✓ Tabelas criadas (sem dados)"
  fi
}

# ────────── Gerenciador de pacotes ──────────
PERGUNTAR_INSTALACAO() {
  local nome="$1"
  shift
  echo "  ⚠ $nome não encontrado"
  if [ "$OS" = "macos" ]; then
    if command -v brew >/dev/null 2>&1; then
      read -r -p "  Instalar $nome com brew? [s/N] " R
      [ "$R" != "s" ] && [ "$R" != "S" ] && { echo "  Cancelado"; exit 1; }
      brew install "$@"
      return 0
    fi
    echo "  Instale $nome manualmente"; exit 1
  fi
  if command -v apt >/dev/null 2>&1; then
    read -r -p "  Instalar $nome com sudo apt? [s/N] " R
    [ "$R" != "s" ] && [ "$R" != "S" ] && { echo "  Cancelado"; exit 1; }
    sudo apt install -y "$@"
  elif command -v dnf >/dev/null 2>&1; then
    read -r -p "  Instalar $nome com sudo dnf? [s/N] " R
    [ "$R" != "s" ] && [ "$R" != "S" ] && { echo "  Cancelado"; exit 1; }
    sudo dnf install -y "$@"
  elif command -v pacman >/dev/null 2>&1; then
    read -r -p "  Instalar $nome com sudo pacman? [s/N] " R
    [ "$R" != "s" ] && [ "$R" != "S" ] && { echo "  Cancelado"; exit 1; }
    sudo pacman -S --noconfirm "$@"
  else
    echo "  Instale $nome manualmente"; exit 1
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
    PERGUNTAR_INSTALACAO "python3" python3 python3-venv
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
    if [ "$OS" = "linux" ]; then
      echo "  ⚠ Node.js não encontrado"
      if command -v apt >/dev/null 2>&1; then
        read -r -p "  Instalar Node.js via nodesource? [s/N] " R
        [ "$R" != "s" ] && [ "$R" != "S" ] && { echo "  Cancelado"; exit 1; }
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
        sudo apt install -y nodejs
      elif command -v dnf >/dev/null 2>&1; then
        read -r -p "  Instalar Node.js com sudo dnf? [s/N] " R
        [ "$R" != "s" ] && [ "$R" != "S" ] && { echo "  Cancelado"; exit 1; }
        sudo dnf module install -y nodejs:22
      elif command -v pacman >/dev/null 2>&1; then
        read -r -p "  Instalar Node.js com sudo pacman? [s/N] " R
        [ "$R" != "s" ] && [ "$R" != "S" ] && { echo "  Cancelado"; exit 1; }
        sudo pacman -S --noconfirm nodejs npm
      else
        echo "  Instale Node.js manualmente: https://nodejs.org"; exit 1
      fi
    elif [ "$OS" = "macos" ]; then
      PERGUNTAR_INSTALACAO "Node.js" node
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
    echo "  ✓ docker $($SUDO docker --version | cut -d' ' -f3 | tr -d ',')"
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
  if ! $SUDO docker compose version >/dev/null 2>&1; then
    echo "  ⚠ docker compose v2+ não encontrado."
    echo "  Atualize o Docker para a versão mais recente."
    exit 1
  fi
  echo "  ✓ docker compose $($SUDO docker compose version | awk '{print $4}' | tr -d ',')"
}

# Detecta se precisamos de sudo para Docker
SUDO=""
if command -v docker >/dev/null 2>&1; then
  if ! docker ps >/dev/null 2>&1; then
    if sudo docker ps >/dev/null 2>&1; then
      SUDO="sudo"
      echo "  ⚠ Docker requer sudo — usando 'sudo docker'"
    fi
  fi
fi

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
  $SUDO docker compose down 2>/dev/null || true

  local UP=""
  if [ "$1" = "crm" ] || [ "$1" = "ambos" ]; then
    echo ""
    echo "  Build CRM..."
    $SUDO docker compose build crm
    UP+="crm "
  fi
  if [ "$1" = "agenda" ] || [ "$1" = "ambos" ]; then
    echo ""
    echo "  Build Agendamento..."
    $SUDO docker compose build agenda
    UP+="agenda "
  fi

  echo ""
  echo "  Iniciando containers: $UP"
  $SUDO docker compose up -d $UP
  echo "  ✓ Containers rodando"
}

# ══════════════════════════════════════════
#  DETECTAR INSTALAÇÃO EXISTENTE
# ══════════════════════════════════════════

detectar_instalacao() {
  local CRM_DIR="$BASE/CRM-Mirian (protótipo)"
  local APP_DIR="$BASE/agendamento Vinicius"
  local VENV_DIR="$CRM_DIR/backend/.venv"

  local CRM_INST=false
  local AGENDA_INST=false
  local DOCKER_INST=false

  [ -d "$VENV_DIR" ] && CRM_INST=true
  [ -d "$APP_DIR/node_modules" ] && AGENDA_INST=true
  command -v docker >/dev/null 2>&1 && $SUDO docker ps -a --filter "name=beautyflow" --format "{{.Names}}" 2>/dev/null | grep -q . && DOCKER_INST=true

  echo ""
  echo "── Instalações Detectadas ──"
  echo "  Nativo:"
  echo "    CRM:        $([ "$CRM_INST" = true ] && echo '✓ instalado' || echo '— não instalado')"
  echo "    Agendamento: $([ "$AGENDA_INST" = true ] && echo '✓ instalado' || echo '— não instalado')"
  echo "  Docker:      $([ "$DOCKER_INST" = true ] && echo '✓ containers encontrados' || echo '— não instalado')"
  echo ""

  # Retorna flags para quem chamou
  echo "$CRM_INST:$AGENDA_INST:$DOCKER_INST"
}

atualizar_repositorio() {
  echo ""
  echo "── Atualizando repositório ──"
  if [ "$INSIDE_REPO" = true ]; then
    git pull --ff-only
    echo "  ✓ Repositório atualizado"
  else
    echo "  Repositório clonado recentemente, já está atualizado"
  fi
}

reinstalar_nativo() {
  local target="$1"  # crm, agenda, ambos
  local CRM_DIR="$BASE/CRM-Mirian (protótipo)"
  local APP_DIR="$BASE/agendamento Vinicius"
  local VENV_DIR="$CRM_DIR/backend/.venv"

  echo ""
  echo "── Reinstalando (limpo) ──"

  if [ "$target" = "crm" ] || [ "$target" = "ambos" ]; then
    echo "  Removendo CRM..."
    rm -rf "$VENV_DIR"
    instalar_crm
  fi
  if [ "$target" = "agenda" ] || [ "$target" = "ambos" ]; then
    echo "  Removendo Agendamento..."
    rm -rf "$APP_DIR/node_modules"
    instalar_agendamento
  fi
  echo "  ✓ Reinstalação concluída"
}

reinstalar_docker() {
  echo ""
  echo "── Reinstalando Docker (limpo) ──"
  if command -v docker >/dev/null 2>&1; then
    $SUDO docker compose down 2>/dev/null || true
    $SUDO docker rmi -f instalacao-crm instalacao-agenda 2>/dev/null || true
    echo "  ✓ Containers e imagens removidos"
  fi
  modo_docker "ambos"
}

atualizar_dependencias_nativo() {
  local target="$1"
  local CRM_DIR="$BASE/CRM-Mirian (protótipo)"
  local APP_DIR="$BASE/agendamento Vinicius"
  local VENV_DIR="$CRM_DIR/backend/.venv"

  echo ""
  echo "── Atualizando dependências ──"

  if [ "$target" = "crm" ] || [ "$target" = "ambos" ]; then
    if [ -d "$VENV_DIR" ]; then
      echo "  Atualizando dependências Python do CRM..."
      "$VENV_DIR/bin/pip" install --quiet --upgrade pip flask flask-cors
      echo "  ✓ CRM atualizado"
    else
      echo "  ⚠ CRM não instalado. Instalando..."
      instalar_crm
    fi
  fi
  if [ "$target" = "agenda" ] || [ "$target" = "ambos" ]; then
    if [ -d "$APP_DIR/node_modules" ]; then
      echo "  Atualizando dependências npm do Agendamento..."
      cd "$APP_DIR" && npm update --silent && cd "$DIR"
      echo "  ✓ Agendamento atualizado"
    else
      echo "  ⚠ Agendamento não instalado. Instalando..."
      instalar_agendamento
    fi
  fi
}

atualizar_docker() {
  echo ""
  echo "── Atualizando Docker ──"
  if command -v docker >/dev/null 2>&1; then
    $SUDO docker compose pull 2>/dev/null || true
    $SUDO docker compose build --no-cache 2>/dev/null || true
    $SUDO docker compose up -d
    echo "  ✓ Containers atualizados e reiniciados"
  else
    echo "  ⚠ Docker não disponível"
  fi
}

gestor_atualizacao() {
  local target="$1"   # nativo-crm, nativo-agenda, nativo-ambos, docker
  local nome=""
  local CRM_DIR="$BASE/CRM-Mirian (protótipo)"
  local APP_DIR="$BASE/agendamento Vinicius"
  local VENV_DIR="$CRM_DIR/backend/.venv"

  case "$target" in
    nativo-crm)    nome="CRM (nativo)" ;;
    nativo-agenda) nome="Agendamento (nativo)" ;;
    nativo-ambos)  nome="CRM + Agendamento (nativo)" ;;
    docker)        nome="Docker (Ambos)" ;;
  esac

  echo ""
  echo "═══ Gerenciar: $nome ═══"
  echo ""
  echo "  1) Reinstalar (deletar tudo + instalar do zero)"
  echo "  2) Atualizar (git pull + atualizar dependências)"
  echo "  3) Desinstalar (remover completamente)"
  echo "  4) Cancelar"
  echo ""
  read -r -p "Escolha [1-4] (padrão 4): " R
  R="${R:-4}"

  case "$R" in
    1)
      case "$target" in
        nativo-crm)    reinstalar_nativo "crm" ;;
        nativo-agenda) reinstalar_nativo "agenda" ;;
        nativo-ambos)  reinstalar_nativo "ambos" ;;
        docker)        reinstalar_docker ;;
      esac
      ;;
    2)
      atualizar_repositorio
      case "$target" in
        nativo-crm)    atualizar_dependencias_nativo "crm" ;;
        nativo-agenda) atualizar_dependencias_nativo "agenda" ;;
        nativo-ambos)  atualizar_dependencias_nativo "ambos" ;;
        docker)        atualizar_docker ;;
      esac
      echo ""
      echo "╔══════════════════════════════════════════════╗"
      echo "║  Atualização concluída!                      ║"
      if [ "$target" = "docker" ]; then
        echo "║                                              ║"
        echo "║  CRM:        http://localhost:3001            ║"
        echo "║  Agendamento: http://localhost:5173           ║"
      else
        echo "║                                              ║"
        echo "║  Use start.sh para iniciar:                  ║"
        echo "║    bash \"$DIR/start.sh\" $([ "$target" = "nativo-crm" ] && echo "crm" || { [ "$target" = "nativo-agenda" ] && echo "agenda"; } || echo "ambos")  ║"
      fi
      echo "╚══════════════════════════════════════════════╝"
      ;;
    3)
      echo ""
      echo "── Desinstalando ──"

      # Perguntar sobre o banco de dados
      local DEL_DB=false
      if [ -f "$DB_PATH" ]; then
        echo "  Banco existente em: $DB_PATH"
        read -r -p "  Remover também o banco de dados? [s/N] " R
        [ "$R" = "s" ] || [ "$R" = "S" ] && DEL_DB=true
      fi

      case "$target" in
        nativo-crm)
          pkill -f "backend/server.py" 2>/dev/null || true
          rm -rf "$VENV_DIR"
          echo "  ✓ CRM desinstalado (processo encerrado, venv removido)"
          ;;
        nativo-agenda)
          pkill -f "npm run dev" 2>/dev/null || true
          pkill -f "vite" 2>/dev/null || true
          rm -rf "$APP_DIR/node_modules"
          echo "  ✓ Agendamento desinstalado (processo encerrado, node_modules removido)"
          ;;
        nativo-ambos)
          pkill -f "backend/server.py" 2>/dev/null || true
          pkill -f "npm run dev" 2>/dev/null || true
          pkill -f "vite" 2>/dev/null || true
          rm -rf "$VENV_DIR" "$APP_DIR/node_modules"
          echo "  ✓ CRM e Agendamento desinstalados (processos encerrados)"
          ;;
        docker)
          if command -v docker >/dev/null 2>&1; then
            $SUDO docker compose down 2>/dev/null || true
            $SUDO docker rmi -f instalacao-crm instalacao-agenda 2>/dev/null || true
            echo "  ✓ Containers e imagens Docker removidos"
          fi
          ;;
      esac

      if [ "$DEL_DB" = true ]; then
        rm -f "$DB_PATH"
        echo "  ✓ Banco de dados removido"
      fi
      echo "  ✓ Desinstalação concluída"
      ;;
    4|*)
      echo "  Cancelado"
      ;;
  esac
}

perguntar_iniciar() {
  local modo="$1"
  echo ""
  read -r -p "  Iniciar agora? [s/N] " R
  if [ "$R" = "s" ] || [ "$R" = "S" ]; then
    echo ""
    bash "$DIR/start.sh" "$modo"
  fi
}

# ══════════════════════════════════════════
#  MENU INTERATIVO
# ══════════════════════════════════════════

if [ "$MODE" = "menu" ]; then
  echo "Escolha o que deseja fazer:"
  echo ""
  echo "  1) Ambos (CRM + Agendamento) ← RECOMENDADO"
  echo "  2) BeautyFlow CRM (gestão do salão)"
  echo "  3) BeautyFlow Agendamento (painel do cliente)"
  echo "  4) Docker — Ambos (container)"
  echo "  5) Gerenciar instalação (reinstalar / atualizar)"
  echo ""
  read -r -p "Digite o número [1-5] (padrão 1): " ESCOLHA
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
    perguntar_iniciar "ambos"
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
    perguntar_iniciar "crm"
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
    perguntar_iniciar "agenda"
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
  5|gerenciar)
    echo "═══ Gerenciar Instalação ═══"
    echo ""
    echo "Escolha o que deseja gerenciar:"
    echo ""
    echo "  1) Instalação Nativa — Ambos (CRM + Agendamento)"
    echo "  2) Instalação Nativa — CRM"
    echo "  3) Instalação Nativa — Agendamento"
    echo "  4) Instalação Docker — Ambos"
    echo "  5) Voltar"
    echo ""
    read -r -p "Escolha [1-5] (padrão 5): " SUB
    SUB="${SUB:-5}"
    echo ""
    case "$SUB" in
      1) gestor_atualizacao "nativo-ambos" ;;
      2) gestor_atualizacao "nativo-crm" ;;
      3) gestor_atualizacao "nativo-agenda" ;;
      4) gestor_atualizacao "docker" ;;
      5|*) echo "  Cancelado" ;;
    esac
    ;;
  *)
    echo "  Opção inválida: $ESCOLHA"; exit 1
    ;;
esac
