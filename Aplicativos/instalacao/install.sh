#!/usr/bin/env bash
# ==============================================================================
# BeautyFlow Platform — Hub de Gestao, Instalacao e Manutencao
# Suporte: Linux / macOS | Arquitetura: Docker Compose + PostgreSQL
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Recarregar sessao com o grupo docker caso o usuario ja faca parte do grupo
# mas a sessao atual do shell ainda nao tenha herdado as novas permissoes
if [ -z "${BF_GROUP_RELOADED:-}" ] && [ "$(id -u)" -ne 0 ]; then
    if ! id -Gn 2>/dev/null | grep -qw docker && getent group docker 2>/dev/null | grep -qw "$USER"; then
        export BF_GROUP_RELOADED=1
        exec newgrp docker -c "exec bash \"$SCRIPT_DIR/install.sh\" \"$@\""
    fi
fi

CRM_DIR="$(cd "$SCRIPT_DIR/../CRM BeautyFlow" && pwd)"
AGENDA_DIR="$(cd "$SCRIPT_DIR/../Beatriz Gomes Studio" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
mkdir -p "$BACKUP_DIR"

# ------------------------------------------------------------------------------
# Paleta de Cores TUI (Sem emojis, foco em elegancia tipografica)
# ------------------------------------------------------------------------------
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_MAGENTA='\033[0;35m'
C_CYAN='\033[0;36m'
C_WHITE='\033[1;37m'
C_GRAY='\033[0;90m'
C_B_MAGENTA='\033[1;35m'
C_B_CYAN='\033[1;36m'
C_B_GREEN='\033[1;32m'
C_B_RED='\033[1;31m'
C_B_YELLOW='\033[1;33m'

# ------------------------------------------------------------------------------
# Deteccao de Comando Docker Compose
# ------------------------------------------------------------------------------
detect_compose() {
    if docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        COMPOSE_CMD=""
    fi
}
detect_compose

# ------------------------------------------------------------------------------
# Verificador de Status do Servico
# ------------------------------------------------------------------------------
svc_status() {
    local svc="$1"
    if [ -z "${COMPOSE_CMD:-}" ]; then
        echo -e "${C_GRAY}[ INATIVO ]${C_RESET}"
        return
    fi
    local state
    state=$($COMPOSE_CMD ps --format '{{.Service}}={{.State}}' 2>/dev/null | grep "^$svc=" | head -n1 | cut -d'=' -f2 || true)
    if [ "$state" = "running" ]; then
        echo -e "${C_B_GREEN}[ ONLINE  ]${C_RESET}"
    elif [ -n "$state" ]; then
        echo -e "${C_YELLOW}[ $state ]${C_RESET}"
    else
        echo -e "${C_GRAY}[ OFFLINE ]${C_RESET}"
    fi
}

# ------------------------------------------------------------------------------
# Cabecalho TUI Principal
# ------------------------------------------------------------------------------
show_header() {
    clear 2>/dev/null || true
    local st_pg st_crm st_agd
    st_pg=$(svc_status "postgres")
    st_crm=$(svc_status "crm-backend")
    st_agd=$(svc_status "agendamento-app")

    echo -e "${C_B_MAGENTA}"
    echo "    ┌────────────────────────────────────────────────────────────┐"
    echo -e "    │  ${C_WHITE}${C_BOLD}BEAUTYFLOW PLATFORM${C_RESET}${C_B_MAGENTA}  —  Hub de Gestao e Instalacao       │"
    echo -e "    │  ${C_DIM}CRM BeautyFlow  +  Portal Agendamento  +  PostgreSQL${C_RESET}${C_B_MAGENTA}     │"
    echo "    ├────────────────────────────────────────────────────────────┤"
    echo -e "    │  Status dos Servicos:                                      │"
    echo -e "    │    PostgreSQL (5432):     ${st_pg}${C_B_MAGENTA}                        │"
    echo -e "    │    CRM Backend (3001):    ${st_crm}${C_B_MAGENTA}                        │"
    echo -e "    │    Agendamento (5173):    ${st_agd}${C_B_MAGENTA}                        │"
    echo "    └────────────────────────────────────────────────────────────┘"
    echo -e "${C_RESET}"
}

# ------------------------------------------------------------------------------
# Verificacao e Instalacao de Dependencias
# ------------------------------------------------------------------------------
check_dependencies() {
    echo -e "${C_B_CYAN}[*] Verificando dependencias do sistema...${C_RESET}"
    
    if ! command -v docker &>/dev/null || [ -z "$COMPOSE_CMD" ]; then
        echo -e "${C_YELLOW}[AVISO] Docker ou Docker Compose ausente no sistema.${C_RESET}"
        read -rp "Deseja instalar as dependencias automaticamente? [S/n]: " RESP
        RESP=${RESP:-S}
        if [[ "$RESP" =~ ^[Ss]$ ]]; then
            install_docker_distro
            detect_compose
        else
            echo -e "${C_RED}[ERRO] O Docker e obrigatorio para executar a plataforma.${C_RESET}"
            return 1
        fi
    fi

    local DOCKER_OUT
    DOCKER_OUT=$(docker info 2>&1 || true)
    if echo "$DOCKER_OUT" | grep -qi "permission denied"; then
        echo -e "${C_YELLOW}[AVISO] Permissao negada ao acessar o Docker (${USER} nao esta com o grupo ativo).${C_RESET}"
        if ! getent group docker 2>/dev/null | grep -qw "$USER"; then
            echo -e "${C_CYAN}[*] Adicionando o usuario '$USER' ao grupo 'docker'...${C_RESET}"
            sudo usermod -aG docker "$USER"
        fi
        if [ -z "${BF_GROUP_RELOADED:-}" ]; then
            echo -e "${C_B_CYAN}[*] Atualizando credenciais da sessao com 'newgrp docker'...${C_RESET}"
            export BF_GROUP_RELOADED=1
            exec newgrp docker -c "exec bash \"$SCRIPT_DIR/install.sh\" \"$@\""
        fi
        echo -e "${C_RED}[ERRO] O usuario '$USER' esta no grupo docker, mas a sessao do terminal precisa ser atualizada.${C_RESET}"
        echo -e "      Execute o comando abaixo no terminal antes de reabrir o script:"
        echo -e "        ${C_WHITE}${C_BOLD}newgrp docker${C_RESET}"
        echo -e "      (Ou faca logout/login no sistema para aplicar as permissoes globalmente)."
        return 1
    elif ! docker info &>/dev/null; then
        echo -e "${C_YELLOW}[AVISO] O servico do Docker nao esta ativo. Tentando iniciar...${C_RESET}"
        if command -v systemctl &>/dev/null; then
            sudo systemctl start docker || true
            sleep 2
        fi
        if ! docker info &>/dev/null; then
            echo -e "${C_RED}[ERRO] Nao foi possivel comunicar com o Docker.${C_RESET}"
            echo -e "      Certifique-se de que o servico esteja rodando ou use: sudo systemctl start docker"
            return 1
        fi
    fi
    echo -e "${C_B_GREEN}[OK] Docker e Docker Compose operacionais.${C_RESET}"
    return 0
}

install_docker_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        local FAMILIA="${ID:-linux}"
        local ID_LIKE="${ID_LIKE:-}"
        if [[ "$ID_LIKE" == *"arch"* ]]; then FAMILIA="arch"; fi
        if [[ "$ID_LIKE" == *"debian"* ]] || [[ "$ID_LIKE" == *"ubuntu"* ]]; then FAMILIA="ubuntu"; fi
        if [[ "$ID_LIKE" == *"fedora"* ]] || [[ "$ID_LIKE" == *"rhel"* ]]; then FAMILIA="fedora"; fi
        if [[ "$ID_LIKE" == *"suse"* ]]; then FAMILIA="opensuse"; fi

        echo -e "${C_CYAN}[*] Instalando pacotes para: $NAME...${C_RESET}"
        case "$FAMILIA" in
            arch|manjaro|endeavouros)
                sudo pacman -Sy --noconfirm docker docker-compose
                ;;
            ubuntu|debian|pop|mint)
                sudo apt-get update -qq
                sudo apt-get install -y -qq docker.io docker-compose-plugin || sudo apt-get install -y -qq docker.io docker-compose
                ;;
            fedora|rhel|centos|rocky|almalinux)
                sudo dnf install -y -q docker docker-compose || sudo dnf install -y -q docker
                ;;
            opensuse*|sles)
                sudo zypper in -y docker docker-compose
                ;;
            *)
                echo -e "${C_RED}[ERRO] Distribuicao nao mapeada automaticamente. Instale o Docker manualmente.${C_RESET}"
                return 1
                ;;
        esac
        sudo systemctl enable --now docker || true
        sudo usermod -aG docker "$USER" 2>/dev/null || true
        if [ -z "${BF_GROUP_RELOADED:-}" ]; then
            export BF_GROUP_RELOADED=1
            exec newgrp docker -c "exec bash \"$SCRIPT_DIR/install.sh\" \"$@\""
        fi
    elif [ "$(uname)" == "Darwin" ]; then
        if command -v brew &>/dev/null; then
            brew install --cask docker
        else
            echo -e "${C_RED}[ERRO] Instale o Docker Desktop para macOS: https://www.docker.com/products/docker-desktop/${C_RESET}"
            return 1
        fi
    fi
}

# ------------------------------------------------------------------------------
# Deteccao de IP da Maquina na Rede Local
# ------------------------------------------------------------------------------
detect_local_ip() {
    local ip=""
    if [ "$(uname)" == "Darwin" ]; then
        ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
    elif command -v hostname &>/dev/null; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [ -z "$ip" ] && command -v ip &>/dev/null; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}')
    fi
    if [ -z "$ip" ]; then
        ip="localhost"
    fi
    echo "$ip"
}

# ------------------------------------------------------------------------------
# Verificacao Preventiva de Conflitos de Porta
# ------------------------------------------------------------------------------
check_port() {
    local port="$1"
    local desc="$2"
    local in_use=0

    if command -v ss &>/dev/null; then
        if ss -tlpn 2>/dev/null | grep -qE ":$port[[:space:]]"; then in_use=1; fi
    elif command -v lsof &>/dev/null; then
        if lsof -i ":$port" -sTCP:LISTEN &>/dev/null; then in_use=1; fi
    elif command -v netstat &>/dev/null; then
        if netstat -tuln 2>/dev/null | grep -qE ":$port[[:space:]]"; then in_use=1; fi
    fi

    if [ "$in_use" -eq 1 ]; then
        if ! docker ps --format '{{.Ports}}' 2>/dev/null | grep -qE ":$port->"; then
            echo -e "${C_YELLOW}[AVISO] A porta $port ($desc) ja esta em uso por outro servico local.${C_RESET}"
            if [ "$port" -eq 5432 ]; then
                read -rp "        Deseja tentar pausar o PostgreSQL local agora? (S/n): " STOP_PG
                STOP_PG=${STOP_PG:-S}
                if [[ "$STOP_PG" =~ ^[Ss]$ ]]; then
                    if [ -d "$HOME/.pg_local/data" ] && command -v pg_ctl &>/dev/null; then
                        pg_ctl -D "$HOME/.pg_local/data" stop 2>/dev/null || true
                    elif [ -x "$HOME/.pg_bin/usr/bin/pg_ctl" ]; then
                        "$HOME/.pg_bin/usr/bin/pg_ctl" -D "$HOME/.pg_local/data" stop 2>/dev/null || true
                    fi
                    sudo systemctl stop postgresql 2>/dev/null || true
                    sleep 2
                fi
            else
                read -rp "        Deseja encerrar o processo local na porta $port ($desc)? (S/n): " STOP_PROC
                STOP_PROC=${STOP_PROC:-S}
                if [[ "$STOP_PROC" =~ ^[Ss]$ ]]; then
                    if command -v fuser &>/dev/null; then
                        fuser -k -n tcp "$port" 2>/dev/null || true
                    elif command -v lsof &>/dev/null; then
                        lsof -ti :"$port" -sTCP:LISTEN 2>/dev/null | xargs -r kill -9 2>/dev/null || true
                    fi
                    sleep 1
                fi
            fi
        fi
    fi
}

# ------------------------------------------------------------------------------
# Loop de Aguardo e Monitoramento de Saude dos Conteineres
# ------------------------------------------------------------------------------
wait_for_health() {
    local tries=30
    echo -e "${C_CYAN}[*] Aguardando servicos inicializarem e passarem no healthcheck...${C_RESET}"
    for i in $(seq 1 "$tries"); do
        local all_ok=1
        local dead_found=0
        while IFS='=' read -r svc state health; do
            if [ -z "$svc" ]; then continue; fi
            if [ "$state" = "exited" ] || [ "$state" = "dead" ]; then
                echo -e "${C_RED}[ERRO] O servico '$svc' encerrou inesperadamente (status: $state).${C_RESET}"
                dead_found=1
            fi
            if [ "$state" != "running" ] || [ "$health" = "unhealthy" ] || [ "$health" = "starting" ]; then
                all_ok=0
            fi
        done < <($COMPOSE_CMD ps --format '{{.Service}}={{.State}}={{.Health}}' 2>/dev/null)

        if [ "$dead_found" -eq 1 ]; then
            echo ""
            echo -e "${C_YELLOW}[DIAGNOSTICO] Exibindo ultimas linhas de log:${C_RESET}"
            $COMPOSE_CMD logs --tail=30
            return 1
        fi

        if [ "$all_ok" -eq 1 ]; then
            echo -e "${C_B_GREEN}[OK] Todos os servicos estao ativos e saudaveis!${C_RESET}"
            return 0
        fi
        sleep 3
    done
    echo -e "${C_YELLOW}[AVISO] Tempo limite de espera atingido. Verifique com: docker compose logs -f${C_RESET}"
    return 0
}

# ------------------------------------------------------------------------------
# 1. Instalar / Inicializar Plataforma
# ------------------------------------------------------------------------------
action_install() {
    show_header
    echo -e "${C_BOLD}${C_MAGENTA}--- [1] INSTALACAO E INICIALIZACAO COMPLETA ---${C_RESET}
"
    
    if ! check_dependencies; then return; fi

    echo ""
    echo -e "${C_B_CYAN}[*] Verificando portas do sistema...${C_RESET}"
    check_port 5432 "PostgreSQL"
    check_port 3001 "CRM BeautyFlow"
    check_port 5173 "Portal Agendamento"

    echo ""
    echo -e "${C_B_CYAN}[*] Configuracao de Rede & Enderecamento da API${C_RESET}"
    local DETECTED_IP
    DETECTED_IP=$(detect_local_ip)
    echo -e "    O endereco IP permite que smartphones na rede Wi-Fi acessem o agendamento."
    echo -e "    IP detectado: ${C_WHITE}${C_BOLD}$DETECTED_IP${C_RESET}"
    read -rp "    Confirme o IP ou digite outro (ex: localhost) [$DETECTED_IP]: " USER_IP
    USER_IP=${USER_IP:-$DETECTED_IP}

    cat <<ENV_CRM > "$CRM_DIR/backend/.env"
DATABASE_URL=postgresql://postgres:beautyflow_pass@postgres:5432/beautyflow
N8N_WEBHOOK_URL=https://mirianfiorini.app.n8n.cloud/webhook/calendar-webhook
ENV_CRM

    cat <<ENV_AGD > "$AGENDA_DIR/.env"
VITE_API_URL=http://$USER_IP:3001/api
ENV_AGD

    cat <<ENV_ROOT > "$SCRIPT_DIR/.env"
VITE_API_URL=http://$USER_IP:3001/api
ENV_ROOT
    echo -e "${C_B_GREEN}[OK] Arquivos .env configurados com sucesso.${C_RESET}
"

    echo -e "${C_B_CYAN}[*] Construindo e iniciando os conteineres Docker...${C_RESET}"
    $COMPOSE_CMD up -d --build --force-recreate --remove-orphans

    echo ""
    wait_for_health

    echo ""
    echo -e "${C_B_MAGENTA}════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "  ${C_WHITE}${C_BOLD}INSTALACAO CONCLUIDA COM SUCESSO!${C_RESET}"
    echo -e "${C_B_MAGENTA}════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "  Painel CRM BeautyFlow:    ${C_B_CYAN}http://localhost:3001${C_RESET}"
    echo -e "  Credenciais de Acesso:    Usuario: ${C_YELLOW}admin${C_RESET} | Senha: ${C_YELLOW}admin${C_RESET}"
    echo -e "  Portal de Agendamento:    ${C_B_CYAN}http://localhost:5173${C_RESET}"
    echo -e "  Acesso Mobile (mesmo Wi-Fi): ${C_B_CYAN}http://$USER_IP:5173${C_RESET}"
    echo -e "  Banco de Dados Postgres:  ${C_WHITE}localhost:5432 (DB: beautyflow)${C_RESET}"
    echo -e "${C_B_MAGENTA}════════════════════════════════════════════════════════════════${C_RESET}"
}

# ------------------------------------------------------------------------------
# 2. Iniciar Servicos
# ------------------------------------------------------------------------------
action_start() {
    show_header
    echo -e "${C_BOLD}${C_MAGENTA}--- [2] INICIAR SERVICOS ---${C_RESET}
"
    if ! check_dependencies; then return; fi
    echo -e "${C_CYAN}[*] Subindo conteineres...${C_RESET}"
    $COMPOSE_CMD up -d
    wait_for_health
}

# ------------------------------------------------------------------------------
# 3. Parar Servicos
# ------------------------------------------------------------------------------
action_stop() {
    show_header
    echo -e "${C_BOLD}${C_MAGENTA}--- [3] PARAR SERVICOS ---${C_RESET}
"
    if [ -z "$COMPOSE_CMD" ]; then echo -e "${C_RED}[ERRO] Compose nao disponivel.${C_RESET}"; return; fi
    echo -e "${C_CYAN}[*] Pausando conteineres da plataforma...${C_RESET}"
    $COMPOSE_CMD stop
    echo -e "${C_B_GREEN}[OK] Plataforma pausada. Dados do PostgreSQL preservados.${C_RESET}"
}

# ------------------------------------------------------------------------------
# 4. Reiniciar Servicos
# ------------------------------------------------------------------------------
action_restart() {
    show_header
    echo -e "${C_BOLD}${C_MAGENTA}--- [4] REINICIAR SERVICOS ---${C_RESET}
"
    if [ -z "$COMPOSE_CMD" ]; then echo -e "${C_RED}[ERRO] Compose nao disponivel.${C_RESET}"; return; fi
    echo -e "${C_CYAN}[*] Reiniciando conteineres...${C_RESET}"
    $COMPOSE_CMD restart
    wait_for_health
}

# ------------------------------------------------------------------------------
# 5. Atualizar Plataforma
# ------------------------------------------------------------------------------
action_update() {
    show_header
    echo -e "${C_BOLD}${C_MAGENTA}--- [5] ATUALIZAR PLATAFORMA ---${C_RESET}
"
    if ! check_dependencies; then return; fi

    if [ -d "$SCRIPT_DIR/../../.git" ]; then
        echo -e "${C_CYAN}[*] Repositorio Git detectado.${C_RESET}"
        read -rp "Deseja buscar as ultimas atualizacoes via git pull? [S/n]: " PULL_ANS
        PULL_ANS=${PULL_ANS:-S}
        if [[ "$PULL_ANS" =~ ^[Ss]$ ]]; then
            (cd "$SCRIPT_DIR/../.." && git pull origin main || git pull || true)
        fi
    fi

    echo ""
    echo -e "${C_CYAN}[*] Reconstruindo imagens Docker com as alteracoes mais recentes...${C_RESET}"
    echo -e "    (O volume do PostgreSQL NAO sera afetado; seus dados permanecem intactos)"
    $COMPOSE_CMD up -d --build
    wait_for_health
    echo -e "
${C_B_GREEN}[OK] Plataforma atualizada com sucesso!${C_RESET}"
}

# ------------------------------------------------------------------------------
# 6. Gerenciamento de Banco de Dados (Submenu)
# ------------------------------------------------------------------------------
db_backup() {
    echo -e "
${C_BOLD}${C_CYAN}[*] Criando Backup do PostgreSQL...${C_RESET}"
    local TS
    TS=$(date +%Y%m%d_%H%M%S)
    local FILE="$BACKUP_DIR/backup_beautyflow_${TS}.sql"

    if ! docker ps --format '{{.Names}}' | grep -q 'beautyflow-postgres'; then
        echo -e "${C_RED}[ERRO] O conteiner 'beautyflow-postgres' nao esta rodando.${C_RESET}"
        echo -e "       Inicie a plataforma primeiro (Opcao 2)."
        return
    fi

    if docker exec beautyflow-postgres pg_dump -U postgres -d beautyflow > "$FILE"; then
        local SIZE
        SIZE=$(du -h "$FILE" | cut -f1)
        echo -e "${C_B_GREEN}[OK] Backup criado com sucesso!${C_RESET}"
        echo -e "     Arquivo: ${C_WHITE}$FILE${C_RESET}"
        echo -e "     Tamanho: ${C_YELLOW}$SIZE${C_RESET}"
    else
        echo -e "${C_RED}[ERRO] Falha ao executar pg_dump.${C_RESET}"
        rm -f "$FILE"
    fi
}

db_restore() {
    echo -e "
${C_BOLD}${C_CYAN}[*] Restaurar Banco de Dados...${C_RESET}"
    if ! docker ps --format '{{.Names}}' | grep -q 'beautyflow-postgres'; then
        echo -e "${C_RED}[ERRO] O conteiner 'beautyflow-postgres' precisa estar ativo.${C_RESET}"
        return
    fi

    echo -e "Backups disponiveis em '$BACKUP_DIR':"
    local files=("$BACKUP_DIR"/*.sql)
    local TARGET_SQL=""
    if [ ! -e "${files[0]}" ]; then
        echo -e "  ${C_YELLOW}(Nenhum backup encontrado na pasta backups)${C_RESET}"
        echo ""
        read -rp "Digite o caminho completo de outro arquivo .sql: " CUSTOM_SQL
        if [ ! -f "$CUSTOM_SQL" ]; then
            echo -e "${C_RED}[ERRO] Arquivo nao encontrado.${C_RESET}"
            return
        fi
        TARGET_SQL="$CUSTOM_SQL"
    else
        local idx=1
        for f in "${files[@]}"; do
            echo -e "  [${C_WHITE}$idx${C_RESET}] $(basename "$f") (${C_YELLOW}$(du -h "$f" | cut -f1)${C_RESET})"
            idx=$((idx + 1))
        done
        read -rp "Selecione o numero do backup ou digite o caminho de outro: " CHOICE
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#files[@]}" ]; then
            TARGET_SQL="${files[$((CHOICE - 1))]}"
        elif [ -f "$CHOICE" ]; then
            TARGET_SQL="$CHOICE"
        else
            echo -e "${C_RED}[ERRO] Selecao invalida.${C_RESET}"
            return
        fi
    fi

    echo -e "${C_B_RED}[ATENCAO] Esta operacao ira sobrescrever as tabelas existentes no banco 'beautyflow'!${C_RESET}"
    read -rp "Tem certeza que deseja prosseguir com a restauracao? [s/N]: " CONF
    if [[ ! "$CONF" =~ ^[Ss]$ ]]; then
        echo -e "${C_GRAY}Restauracao cancelada.${C_RESET}"
        return
    fi

    echo -e "${C_CYAN}[*] Importando dados de '$(basename "$TARGET_SQL")'...${C_RESET}"
    if docker exec -i beautyflow-postgres psql -U postgres -d beautyflow < "$TARGET_SQL"; then
        echo -e "${C_B_GREEN}[OK] Banco de dados restaurado com sucesso!${C_RESET}"
    else
        echo -e "${C_RED}[ERRO] Falha durante a importacao do script SQL.${C_RESET}"
    fi
}

db_list_backups() {
    echo -e "
${C_BOLD}${C_CYAN}[*] Backups Armazenados:${C_RESET}"
    local files=("$BACKUP_DIR"/*.sql)
    if [ ! -e "${files[0]}" ]; then
        echo -e "  ${C_GRAY}Nenhum arquivo de backup encontrado em: $BACKUP_DIR${C_RESET}"
    else
        printf "  %-36s %-10s %-20s
" "ARQUIVO" "TAMANHO" "DATA DE MODIFICACAO"
        echo "  ----------------------------------------------------------------------"
        for f in "${files[@]}"; do
            local sz mod
            sz=$(du -h "$f" | cut -f1)
            mod=$(date -r "$f" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || stat -c "%y" "$f" 2>/dev/null | cut -d'.' -f1 || echo "-")
            printf "  %-36s %-10s %-20s
" "$(basename "$f")" "$sz" "$mod"
        done
    fi
}

db_check_integrity() {
    echo -e "
${C_BOLD}${C_CYAN}[*] Verificando Integridade das Tabelas e Registros...${C_RESET}"
    if ! docker ps --format '{{.Names}}' | grep -q 'beautyflow-postgres'; then
        echo -e "${C_RED}[ERRO] PostgreSQL nao esta rodando.${C_RESET}"
        return
    fi

    docker exec beautyflow-postgres psql -U postgres -d beautyflow -c "
        SELECT 'Clientes' AS entidade, count(*) AS total FROM clients
        UNION ALL
        SELECT 'Agendamentos', count(*) FROM appointments
        UNION ALL
        SELECT 'Servicos', count(*) FROM services
        UNION ALL
        SELECT 'Transacoes', count(*) FROM transactions
        UNION ALL
        SELECT 'Horarios Cadastrados', count(*) FROM business_hours
        UNION ALL
        SELECT 'Usuarios Admin', count(*) FROM users;
    "
}

db_reset() {
    echo -e "
${C_BOLD}${C_RED}[ALERTA DE SEGURANCA] ZERAR E RECRIAR BANCO DE DADOS${C_RESET}"
    echo -e "Esta operacao ira apagar todas as tabelas e dados do banco 'beautyflow'"
    echo -e "e reinicializar a estrutura limpa com os servicos e horarios padrao."
    read -rp "Para confirmar, digite exatamente 'RESET': " CONF
    if [ "$CONF" != "RESET" ]; then
        echo -e "${C_GRAY}Operacao abortada.${C_RESET}"
        return
    fi

    echo -e "${C_CYAN}[*] Resetando banco de dados...${C_RESET}"
    docker exec beautyflow-postgres psql -U postgres -c "DROP DATABASE IF EXISTS beautyflow;"
    docker exec beautyflow-postgres psql -U postgres -c "CREATE DATABASE beautyflow;"
    docker exec -i beautyflow-postgres psql -U postgres -d beautyflow < "$CRM_DIR/backend/db/schema.sql"
    $COMPOSE_CMD restart crm-backend
    echo -e "${C_B_GREEN}[OK] Banco de dados recriado limpo com schema e sementes iniciais!${C_RESET}"
}

action_database_menu() {
    while true; do
        show_header
        echo -e "    ${C_B_MAGENTA}┌────────────────────────────────────────────────────────────┐${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_WHITE}${C_BOLD}GERENCIAMENTO DE BANCO DE DADOS (PostgreSQL)${C_RESET}               ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}├────────────────────────────────────────────────────────────┤${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_B_GREEN}[1]${C_RESET} Criar Backup Completo (pg_dump)                     ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_YELLOW}[2]${C_RESET} Restaurar Banco a partir de Backup (.sql)            ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_CYAN}[3]${C_RESET} Listar Backups Existentes                            ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_BLUE}[4]${C_RESET} Verificar Contagem de Registros nas Tabelas         ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_RED}[5]${C_RESET} Resetar Banco (Limpar e recriar estrutura)           ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}├────────────────────────────────────────────────────────────┤${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_DIM}[0]${C_RESET} Voltar ao Menu Principal                             ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}└────────────────────────────────────────────────────────────┘${C_RESET}"
        echo ""
        read -rp "    >> Escolha uma opcao [0-5]: " D_OPT
        case $D_OPT in
            1) db_backup ;;
            2) db_restore ;;
            3) db_list_backups ;;
            4) db_check_integrity ;;
            5) db_reset ;;
            0) break ;;
            *) echo -e "    ${C_RED}Opcao invalida.${C_RESET}" ;;
        esac
        echo ""
        read -rp "Pressione [ENTER] para continuar..."
    done
}

# ------------------------------------------------------------------------------
# 7. Configuracoes de Rede & IP
# ------------------------------------------------------------------------------
action_network_config() {
    show_header
    echo -e "${C_BOLD}${C_MAGENTA}--- [7] CONFIGURACAO DE REDE & IP DE ACESSO ---${C_RESET}
"
    
    local CURRENT_API="localhost"
    if [ -f "$SCRIPT_DIR/.env" ]; then
        CURRENT_API=$(grep VITE_API_URL "$SCRIPT_DIR/.env" | cut -d'=' -f2 || echo "http://localhost:3001/api")
    fi
    echo -e "URL da API configurada atualmente: ${C_B_CYAN}$CURRENT_API${C_RESET}"
    
    local DETECTED_IP
    DETECTED_IP=$(detect_local_ip)
    echo -e "IP detectado na rede local:        ${C_WHITE}${C_BOLD}$DETECTED_IP${C_RESET}"
    echo ""
    read -rp "Digite o novo IP ou Dominio (ou ENTER para manter [$DETECTED_IP]): " NEW_IP
    NEW_IP=${NEW_IP:-$DETECTED_IP}

    cat <<ENV_AGD > "$AGENDA_DIR/.env"
VITE_API_URL=http://$NEW_IP:3001/api
ENV_AGD
    cat <<ENV_ROOT > "$SCRIPT_DIR/.env"
VITE_API_URL=http://$NEW_IP:3001/api
ENV_ROOT

    echo -e "
${C_B_GREEN}[OK] Configuracoes de rede atualizadas para: http://$NEW_IP:3001/api${C_RESET}"
    read -rp "Deseja recompilar o portal de agendamento agora para aplicar o novo endereco? [S/n]: " REC
    REC=${REC:-S}
    if [[ "$REC" =~ ^[Ss]$ ]]; then
        $COMPOSE_CMD up -d --build agendamento-app
        echo -e "${C_B_GREEN}[OK] Portal de agendamento atualizado.${C_RESET}"
    fi
}

# ------------------------------------------------------------------------------
# 8. Visualizacao de Logs em Tempo Real
# ------------------------------------------------------------------------------
action_logs() {
    show_header
    echo -e "${C_BOLD}${C_MAGENTA}--- [8] LOGS EM TEMPO REAL ---${C_RESET}
"
    echo -e "  [1] Todos os servicos"
    echo -e "  [2] CRM Backend (Flask)"
    echo -e "  [3] Portal de Agendamento (Nginx/React)"
    echo -e "  [4] PostgreSQL"
    echo -e "  [0] Voltar"
    echo ""
    read -rp "Selecione quais logs deseja acompanhar [0-4]: " LOG_OPT
    case $LOG_OPT in
        1) echo -e "${C_DIM}(Pressione Ctrl+C para sair dos logs)${C_RESET}"; sleep 1; $COMPOSE_CMD logs -f ;;
        2) echo -e "${C_DIM}(Pressione Ctrl+C para sair dos logs)${C_RESET}"; sleep 1; $COMPOSE_CMD logs -f crm-backend ;;
        3) echo -e "${C_DIM}(Pressione Ctrl+C para sair dos logs)${C_RESET}"; sleep 1; $COMPOSE_CMD logs -f agendamento-app ;;
        4) echo -e "${C_DIM}(Pressione Ctrl+C para sair dos logs)${C_RESET}"; sleep 1; $COMPOSE_CMD logs -f postgres ;;
        0) return ;;
        *) echo -e "${C_RED}Opcao invalida.${C_RESET}" ;;
    esac
}

# ------------------------------------------------------------------------------
# 9. Redefinir Senha do Administrador
# ------------------------------------------------------------------------------
action_reset_password() {
    show_header
    echo -e "${C_BOLD}${C_MAGENTA}--- [9] REDEFINIR SENHA DO ADMINISTRADOR (admin) ---${C_RESET}
"
    if ! docker ps --format '{{.Names}}' | grep -q 'beautyflow-crm'; then
        echo -e "${C_RED}[ERRO] O conteiner 'beautyflow-crm' precisa estar rodando.${C_RESET}"
        return
    fi

    read -rp "Digite a nova senha para o usuario 'admin' [padrao: admin]: " NEW_PASS
    NEW_PASS=${NEW_PASS:-admin}

    docker exec -i beautyflow-crm python -c "
from werkzeug.security import generate_password_hash
from db.connection import get_pool
pw_hash = generate_password_hash('$NEW_PASS')
pool = get_pool()
with pool.connection() as conn:
    with conn.cursor() as cur:
        cur.execute('UPDATE users SET password_hash = %s WHERE email = %s', (pw_hash, 'admin'))
    conn.commit()
print('[OK] Senha do usuario admin atualizada.')
"
    echo -e "${C_B_GREEN}[OK] Senha alterada com sucesso! Agora voce pode logar com a nova senha.${C_RESET}"
}

# ------------------------------------------------------------------------------
# 10. Desinstalar / Limpar Ambiente
# ------------------------------------------------------------------------------
action_uninstall() {
    show_header
    echo -e "${C_BOLD}${C_B_RED}--- [10] DESINSTALAR E LIMPAR AMBIENTE ---${C_RESET}
"
    echo -e "${C_RED}ALERTA CRITICO: Esta acao ira parar todos os conteineres e APAGAR o volume${C_RESET}"
    echo -e "${C_RED}de dados do PostgreSQL (clientes, agendamentos, transacoes).${C_RESET}"
    echo -e "Recomendado: Faca um backup antes (Opcao 6) se quiser guardar os dados."
    echo ""
    read -rp "Se tem certeza absoluta, digite a palavra 'EXCLUIR': " CONF
    if [ "$CONF" = "EXCLUIR" ]; then
        echo -e "${C_CYAN}[*] Removendo conteineres, redes e volumes Docker...${C_RESET}"
        $COMPOSE_CMD down -v --remove-orphans || true
        echo -e "${C_B_GREEN}[OK] Ambiente BeautyFlow removido com sucesso.${C_RESET}"
    else
        echo -e "${C_GRAY}Acao cancelada.${C_RESET}"
    fi
}

# ------------------------------------------------------------------------------
# Loop Principal do Menu TUI
# ------------------------------------------------------------------------------
main_menu() {
    while true; do
        show_header
        echo -e "    ${C_B_MAGENTA}┌────────────────────────────────────────────────────────────┐${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_WHITE}${C_BOLD}Menu Principal de Operacoes${C_RESET}                               ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}├────────────────────────────────────────────────────────────┤${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_B_GREEN}[1]${C_RESET}  Instalar / Inicializar Plataforma                    ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_CYAN}[2]${C_RESET}  Iniciar Servicos                                     ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_YELLOW}[3]${C_RESET}  Parar Servicos                                       ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_BLUE}[4]${C_RESET}  Reiniciar Servicos                                   ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_B_CYAN}[5]${C_RESET}  Atualizar Plataforma (Rebuild sem perda de dados)    ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_MAGENTA}[6]${C_RESET}  Gerenciar Banco de Dados (Backup / Restore / Reset)  ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_WHITE}[7]${C_RESET}  Configurar IP de Rede & URL da API                   ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_GRAY}[8]${C_RESET}  Ver Logs em Tempo Real                               ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_B_YELLOW}[9]${C_RESET}  Redefinir Senha do Administrador (admin)             ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_B_RED}[10]${C_RESET} Desinstalar / Limpar Ambiente Completo              ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}├────────────────────────────────────────────────────────────┤${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_DIM}[0]${C_RESET}  Sair                                                 ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}└────────────────────────────────────────────────────────────┘${C_RESET}"
        echo ""
        read -rp "    >> Escolha uma opcao [0-10]: " OPTION

        case $OPTION in
            1) action_install ;;
            2) action_start ;;
            3) action_stop ;;
            4) action_restart ;;
            5) action_update ;;
            6) action_database_menu ;;
            7) action_network_config ;;
            8) action_logs ;;
            9) action_reset_password ;;
            10) action_uninstall ;;
            0)
                echo -e "
  ${C_B_MAGENTA}BeautyFlow Platform encerrado.${C_RESET}
"
                exit 0
                ;;
            *)
                echo -e "  ${C_RED}Opcao invalida. Escolha entre 0 e 10.${C_RESET}"
                ;;
        esac
        echo ""
        read -rp "Pressione [ENTER] para voltar ao menu..."
    done
}

main_menu
