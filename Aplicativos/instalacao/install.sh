#!/usr/bin/env bash
# ==============================================================================
# BeautyFlow Platform — Hub de Gestao, Instalacao e Manutencao
# Suporte: Linux / macOS | Arquitetura: Docker Compose + PostgreSQL + WAHA
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
# Paleta de Cores TUI (Elegancia visual e alta legibilidade)
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
# Deteccao de IP da Maquina na Rede Local
# ------------------------------------------------------------------------------
detect_local_ip() {
    local ip=""
    if [ "$(uname)" == "Darwin" ]; then
        ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
    elif command -v ip &>/dev/null; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' || true)
        if [ -z "$ip" ]; then
            ip=$(ip -4 addr show scope global 2>/dev/null | grep -vE '(docker|br-|veth)' | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || true)
        fi
    fi
    if [ -z "$ip" ] && command -v hostname &>/dev/null; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
    fi
    if [ -z "$ip" ]; then
        ip="localhost"
    fi
    echo "$ip"
}

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
        local p=""
        case "$svc" in
            "postgres") p="5432" ;;
            "crm-backend") p="3001" ;;
            "agendamento-app") p="5173" ;;
        esac
        if [ -n "$p" ] && ss -tlpn 2>/dev/null | grep -qE ":$p[[:space:]]"; then
            echo -e "${C_YELLOW}[ LOCAL   ]${C_RESET}"
        else
            echo -e "${C_GRAY}[ OFFLINE ]${C_RESET}"
        fi
    fi
}

waha_status() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^(beautyflow-waha|waha)$'; then
        echo -e "${C_B_GREEN}[ ONLINE  ]${C_RESET}"
    elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qE '^(beautyflow-waha|waha)$'; then
        echo -e "${C_B_YELLOW}[ PARADO  ]${C_RESET}"
    elif ss -tlpn 2>/dev/null | grep -qE ":3000[[:space:]]"; then
        echo -e "${C_YELLOW}[ LOCAL   ]${C_RESET}"
    elif [ -f "$SCRIPT_DIR/.env" ] && grep -q "INSTALL_WAHA=true" "$SCRIPT_DIR/.env"; then
        echo -e "${C_RED}[ OFFLINE ]${C_RESET}"
    else
        echo -e "${C_GRAY}[ INATIVO ]${C_RESET}"
    fi
}

# ------------------------------------------------------------------------------
# Cabecalho TUI Principal
# ------------------------------------------------------------------------------
show_header() {
    clear 2>/dev/null || true
    local st_pg st_crm st_agd st_waha cur_ip
    st_pg=$(svc_status "postgres")
    st_crm=$(svc_status "crm-backend")
    st_agd=$(svc_status "agendamento-app")
    st_waha=$(waha_status)
    cur_ip=$(detect_local_ip)

    echo -e "${C_B_MAGENTA}"
    echo "    ┌────────────────────────────────────────────────────────────┐"
    echo -e "    │  ${C_WHITE}${C_BOLD}BEAUTYFLOW PLATFORM${C_RESET}${C_B_MAGENTA}  —  Hub de Gestao e Instalacao       │"
    echo -e "    │  ${C_DIM}CRM BeautyFlow  +  Portal Agendamento  +  PostgreSQL${C_RESET}${C_B_MAGENTA}     │"
    echo "    ├────────────────────────────────────────────────────────────┤"
    echo -e "    │  Status dos Servicos:                                      │"
    echo -e "    │    PostgreSQL (5432):     ${st_pg}${C_B_MAGENTA}                        │"
    echo -e "    │    CRM Backend (3001):    ${st_crm}${C_B_MAGENTA}                        │"
    echo -e "    │    Agendamento (5173):    ${st_agd}${C_B_MAGENTA}                        │"
    echo -e "    │    WhatsApp WAHA (3000):  ${st_waha}${C_B_MAGENTA}                        │"
    echo -e "    │  Rede Local: ${C_WHITE}${cur_ip}${C_B_MAGENTA}                                      │"
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
                    if [ -x "$HOME/.local/bin/pg_ctl" ]; then
                        "$HOME/.local/bin/pg_ctl" -D "$HOME/.pg_local/data" stop 2>/dev/null || true
                    elif [ -x "$HOME/.pg_bin/usr/bin/pg_ctl" ]; then
                        "$HOME/.pg_bin/usr/bin/pg_ctl" -D "$HOME/.pg_local/data" stop 2>/dev/null || true
                    elif [ -d "$HOME/.pg_local/data" ] && command -v pg_ctl &>/dev/null; then
                        pg_ctl -D "$HOME/.pg_local/data" stop 2>/dev/null || true
                    fi
                    sudo systemctl stop postgresql 2>/dev/null || true
                    sleep 2
                    if ss -tlpn 2>/dev/null | grep -qE ":5432[[:space:]]"; then
                        if command -v fuser &>/dev/null; then
                            fuser -k -n tcp 5432 2>/dev/null || true
                        elif command -v lsof &>/dev/null; then
                            lsof -ti :5432 -sTCP:LISTEN 2>/dev/null | xargs -r kill -9 2>/dev/null || true
                        fi
                    fi
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
    local tries=35
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
    echo -e "${C_YELLOW}[AVISO] Tempo limite de espera atingido. Os servicos continuam iniciando em background.${C_RESET}"
    return 0
}

# ------------------------------------------------------------------------------
# Sincronizacao de Migracoes e Tabelas no Banco de Dados
# ------------------------------------------------------------------------------
run_schema_migrations() {
    echo -e "${C_CYAN}[*] Sincronizando tabelas e restricoes no PostgreSQL...${C_RESET}"
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'beautyflow-postgres'; then
        return 0
    fi
    docker exec -i beautyflow-postgres psql -U postgres -d beautyflow >/dev/null 2>&1 << 'SQL_MIGRATE'
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'integrations_type_check' AND table_name = 'integrations'
  ) THEN
    ALTER TABLE integrations DROP CONSTRAINT integrations_type_check;
    ALTER TABLE integrations ADD CONSTRAINT integrations_type_check CHECK(type IN ('webhook', 'n8n', 'google_calendar', 'whatsapp', 'waha'));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.metas (
    id SERIAL PRIMARY KEY,
    mes VARCHAR(7) NOT NULL,
    meta NUMERIC(12, 2) NOT NULL DEFAULT 7000.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    CONSTRAINT metas_mes_unique UNIQUE (mes)
);

CREATE TABLE IF NOT EXISTS public.products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    category TEXT DEFAULT 'pink',
    qty INTEGER DEFAULT 0,
    price REAL DEFAULT 0,
    min_qty INTEGER DEFAULT 5,
    missing BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

INSERT INTO public.products (name, category, qty, price, min_qty, missing) VALUES
    ('Esmalte OPI', 'pink', 12, 8.0, 5, false),
    ('Óleo de Cutícula', 'amber', 2, 15.0, 5, false),
    ('Luvas Descartáveis (cx)', 'blue', 3, 25.0, 2, false),
    ('Algodão', 'pink', 0, 4.0, 8, true),
    ('Removedor de Esmalte', 'purple', 5, 12.0, 3, false),
    ('Cera Depilatória', 'amber', 0, 45.0, 2, true),
    ('Henna para Sobrancelha', 'amber', 2, 20.0, 4, false),
    ('Toalhas Descartáveis', 'blue', 8, 18.0, 4, false),
    ('Álcool 70%', 'purple', 6, 10.0, 3, false),
    ('Palito de Laranjeira', 'pink', 15, 3.0, 6, false)
ON CONFLICT DO NOTHING;
SQL_MIGRATE
    echo -e "${C_B_GREEN}[OK] Estrutura e tabelas adicionais sincronizadas.${C_RESET}"
}

# ------------------------------------------------------------------------------
# 1. Instalar / Inicializar Plataforma
# ------------------------------------------------------------------------------
action_install() {
    show_header
    echo -e "${C_BOLD}${C_MAGENTA}--- [1] INSTALACAO E INICIALIZACAO COMPLETA ---${C_RESET}\n"
    
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
WAHA_API_URL=http://waha:3000
WAHA_API_KEY=218c0effefb845238a1ae3651c8ced5b
INSTALL_WAHA=false
ENV_CRM

    cat <<ENV_AGD > "$AGENDA_DIR/.env"
VITE_API_URL=/api
ENV_AGD

    cat <<ENV_ROOT > "$SCRIPT_DIR/.env"
VITE_API_URL=/api
COMPOSE_PROFILES=
INSTALL_WAHA=false
WAHA_API_KEY=218c0effefb845238a1ae3651c8ced5b
ENV_ROOT
    echo -e "${C_B_GREEN}[OK] Arquivos .env configurados com sucesso.${C_RESET}\n"

    echo -e "${C_B_CYAN}[*] Construindo e iniciando os conteineres da plataforma...${C_RESET}"
    $COMPOSE_CMD up -d --build --force-recreate --remove-orphans

    echo ""
    wait_for_health
    run_schema_migrations

    echo ""
    echo -e "${C_B_MAGENTA}════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "  ${C_WHITE}${C_BOLD}INSTALACAO PRINCIPAL CONCLUIDA COM SUCESSO!${C_RESET}"
    echo -e "${C_B_MAGENTA}════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "  Painel CRM BeautyFlow:       ${C_B_CYAN}http://localhost:3001${C_RESET}"
    echo -e "  Credenciais de Acesso:       Usuario: ${C_YELLOW}admin${C_RESET} | Senha: ${C_YELLOW}admin${C_RESET}"
    echo -e "  Portal de Agendamento:       ${C_B_CYAN}http://localhost:5173${C_RESET}"
    echo -e "  Acesso Mobile (mesmo Wi-Fi): ${C_B_CYAN}http://$USER_IP:5173${C_RESET}"
    echo -e "  Banco de Dados PostgreSQL:   ${C_WHITE}localhost:5432 (DB: beautyflow)${C_RESET}"
    echo -e "  WhatsApp WAHA (Porta 3000):  ${C_GRAY}Nao instalado (para instalar, utilize a opcao 11 do menu)${C_RESET}"
    echo -e "${C_B_MAGENTA}════════════════════════════════════════════════════════════════${C_RESET}"
}

# ------------------------------------------------------------------------------
# 2. Iniciar Servicos
# ------------------------------------------------------------------------------
action_start() {
    show_header
    echo -e "${C_BOLD}${C_MAGENTA}--- [2] INICIAR SERVICOS ---${C_RESET}\n"
    if ! check_dependencies; then return; fi

    echo -e "${C_B_CYAN}[*] Verificando disponibilidade das portas...${C_RESET}"
    check_port 5432 "PostgreSQL"
    check_port 3001 "CRM BeautyFlow"
    check_port 5173 "Portal Agendamento"
    if [ -f "$SCRIPT_DIR/.env" ] && grep -q "INSTALL_WAHA=true" "$SCRIPT_DIR/.env"; then
        check_port 3000 "WhatsApp WAHA"
    fi

    echo -e "${C_CYAN}[*] Subindo conteineres...${C_RESET}"
    
    local prof_arg=""
    if [ -f "$SCRIPT_DIR/.env" ] && grep -q "INSTALL_WAHA=true" "$SCRIPT_DIR/.env"; then
        prof_arg="--profile waha"
    fi
    
    $COMPOSE_CMD $prof_arg up -d
    wait_for_health

    echo ""
    echo -e "${C_B_GREEN}[OK] Plataforma iniciada!${C_RESET}"
    echo -e "  • CRM BeautyFlow (Gestao):   ${C_B_CYAN}http://localhost:3001${C_RESET}"
    echo -e "  • Portal de Agendamento:     ${C_B_CYAN}http://localhost:5173${C_RESET}"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^(beautyflow-waha|waha)$'; then
        echo -e "  • WhatsApp WAHA (Porta 3000): ${C_B_GREEN}http://localhost:3000${C_RESET}"
    fi
}

# ------------------------------------------------------------------------------
# 3. Parar Servicos
# ------------------------------------------------------------------------------
action_stop() {
    show_header
    echo -e "${C_BOLD}${C_MAGENTA}--- [3] PARAR SERVICOS ---${C_RESET}\n"
    if [ -z "$COMPOSE_CMD" ]; then echo -e "${C_RED}[ERRO] Compose nao disponivel.${C_RESET}"; return; fi
    echo -e "${C_CYAN}[*] Pausando conteineres da plataforma...${C_RESET}"
    $COMPOSE_CMD --profile waha stop 2>/dev/null || $COMPOSE_CMD stop
    docker stop beautyflow-waha 2>/dev/null || true
    echo -e "${C_B_GREEN}[OK] Plataforma pausada. Dados do PostgreSQL preservados.${C_RESET}"
}

# ------------------------------------------------------------------------------
# 4. Reiniciar Servicos
# ------------------------------------------------------------------------------
action_restart() {
    show_header
    echo -e "${C_BOLD}${C_MAGENTA}--- [4] REINICIAR SERVICOS ---${C_RESET}\n"
    if [ -z "$COMPOSE_CMD" ]; then echo -e "${C_RED}[ERRO] Compose nao disponivel.${C_RESET}"; return; fi

    echo -e "${C_B_CYAN}[*] Verificando disponibilidade das portas...${C_RESET}"
    check_port 5432 "PostgreSQL"
    check_port 3001 "CRM BeautyFlow"
    check_port 5173 "Portal Agendamento"
    if [ -f "$SCRIPT_DIR/.env" ] && grep -q "INSTALL_WAHA=true" "$SCRIPT_DIR/.env"; then
        check_port 3000 "WhatsApp WAHA"
    fi

    echo -e "${C_CYAN}[*] Reiniciando conteineres...${C_RESET}"
    local prof_arg=""
    if [ -f "$SCRIPT_DIR/.env" ] && grep -q "INSTALL_WAHA=true" "$SCRIPT_DIR/.env"; then
        prof_arg="--profile waha"
    fi
    $COMPOSE_CMD $prof_arg restart
    wait_for_health
}

# ------------------------------------------------------------------------------
# 5. Atualizar Plataforma
# ------------------------------------------------------------------------------
action_update() {
    show_header
    echo -e "${C_BOLD}${C_MAGENTA}--- [5] ATUALIZAR PLATAFORMA ---${C_RESET}\n"
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
    local prof_arg=""
    if [ -f "$SCRIPT_DIR/.env" ] && grep -q "INSTALL_WAHA=true" "$SCRIPT_DIR/.env"; then
        prof_arg="--profile waha"
    fi
    $COMPOSE_CMD $prof_arg up -d --build
    wait_for_health
    run_schema_migrations
    echo -e "\n${C_B_GREEN}[OK] Plataforma atualizada com sucesso!${C_RESET}"
}

# ------------------------------------------------------------------------------
# 6. Gerenciamento de Banco de Dados (Submenu)
# ------------------------------------------------------------------------------
db_backup() {
    echo -e "\n${C_BOLD}${C_CYAN}[*] Criando Backup do PostgreSQL...${C_RESET}"
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
    echo -e "\n${C_BOLD}${C_CYAN}[*] Restaurar Banco de Dados...${C_RESET}"
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
        run_schema_migrations
    else
        echo -e "${C_RED}[ERRO] Falha durante a importacao do script SQL.${C_RESET}"
    fi
}

db_list_backups() {
    echo -e "\n${C_BOLD}${C_CYAN}[*] Backups Armazenados:${C_RESET}"
    local files=("$BACKUP_DIR"/*.sql)
    if [ ! -e "${files[0]}" ]; then
        echo -e "  ${C_GRAY}Nenhum arquivo de backup encontrado em: $BACKUP_DIR${C_RESET}"
    else
        printf "  %-36s %-10s %-20s\n" "ARQUIVO" "TAMANHO" "DATA DE MODIFICACAO"
        echo "  ----------------------------------------------------------------------"
        for f in "${files[@]}"; do
            local sz mod
            sz=$(du -h "$f" | cut -f1)
            mod=$(date -r "$f" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || stat -c "%y" "$f" 2>/dev/null | cut -d'.' -f1 || echo "-")
            printf "  %-36s %-10s %-20s\n" "$(basename "$f")" "$sz" "$mod"
        done
    fi
}

db_check_integrity() {
    echo -e "\n${C_BOLD}${C_CYAN}[*] Verificando Integridade das Tabelas e Registros...${C_RESET}"
    if ! docker ps --format '{{.Names}}' | grep -q 'beautyflow-postgres'; then
        echo -e "${C_RED}[ERRO] PostgreSQL nao esta rodando.${C_RESET}"
        return
    fi

    docker exec beautyflow-postgres psql -U postgres -d beautyflow -c "
        SELECT 'Clientes' AS entidade, count(*) AS total FROM clients
        UNION ALL
        SELECT 'Agendamentos', count(*) FROM appointments
        UNION ALL
        SELECT 'Servicos no Catalogo', count(*) FROM services
        UNION ALL
        SELECT 'Transacoes Financeiras', count(*) FROM transactions
        UNION ALL
        SELECT 'Insumos de Estoque', count(*) FROM products
        UNION ALL
        SELECT 'Metas Mensais', count(*) FROM metas
        UNION ALL
        SELECT 'Horarios de Atendimento', count(*) FROM business_hours
        UNION ALL
        SELECT 'Integracoes Configuradas', count(*) FROM integrations
        UNION ALL
        SELECT 'Notificacoes do Sistema', count(*) FROM notifications
        UNION ALL
        SELECT 'Usuarios Administradores', count(*) FROM users;
    "
}

db_vacuum() {
    echo -e "\n${C_BOLD}${C_CYAN}[*] Otimizando Banco de Dados (VACUUM ANALYZE)...${C_RESET}"
    if ! docker ps --format '{{.Names}}' | grep -q 'beautyflow-postgres'; then
        echo -e "${C_RED}[ERRO] PostgreSQL nao esta rodando.${C_RESET}"
        return
    fi
    docker exec beautyflow-postgres psql -U postgres -d beautyflow -c "VACUUM (VERBOSE, ANALYZE);"
    echo -e "${C_B_GREEN}[OK] Otimizacao e recalculo de estatisticas concluidos!${C_RESET}"
}

db_reset() {
    echo -e "\n${C_BOLD}${C_RED}[ALERTA DE SEGURANCA] ZERAR E RECRIAR BANCO DE DADOS${C_RESET}"
    echo -e "Esta operacao ira apagar todas as tabelas e dados do banco 'beautyflow'"
    echo -e "e reinicializar a estrutura limpa com os servicos, estoque e horarios padrao."
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
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_WHITE}[5]${C_RESET} Otimizar Banco (VACUUM ANALYZE)                      ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_RED}[6]${C_RESET} Resetar Banco (Limpar e recriar estrutura)           ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}├────────────────────────────────────────────────────────────┤${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_DIM}[0]${C_RESET} Voltar ao Menu Principal                             ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}└────────────────────────────────────────────────────────────┘${C_RESET}"
        echo ""
        read -rp "    >> Escolha uma opcao [0-6]: " D_OPT
        case $D_OPT in
            1) db_backup ;;
            2) db_restore ;;
            3) db_list_backups ;;
            4) db_check_integrity ;;
            5) db_vacuum ;;
            6) db_reset ;;
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
    echo -e "${C_BOLD}${C_MAGENTA}--- [7] CONFIGURACAO DE REDE & IP DE ACESSO ---${C_RESET}\n"
    
    local CURRENT_API="/api"
    if [ -f "$SCRIPT_DIR/.env" ]; then
        CURRENT_API=$(grep VITE_API_URL "$SCRIPT_DIR/.env" | cut -d'=' -f2 || echo "/api")
    fi
    echo -e "Configuracao de API atual:         ${C_B_CYAN}$CURRENT_API${C_RESET}"
    
    local DETECTED_IP
    DETECTED_IP=$(detect_local_ip)
    echo -e "IP detectado na rede local:        ${C_WHITE}${C_BOLD}$DETECTED_IP${C_RESET}"
    echo ""
    echo -e "  ${C_B_GREEN}ℹ️ Arquitetura com Proxy Reverso Ativo:${C_RESET}"
    echo -e "  O portal de agendamento se comunica via rota relativa (/api)."
    echo -e "  Smartphones no mesmo Wi-Fi acessam diretamente por:"
    echo -e "  ${C_B_CYAN}http://$DETECTED_IP:5173${C_RESET} (sem necessidade de abrir a porta 3001)\n"

    read -rp "Deseja manter o padrao recomendado (/api) ou informar URL externa? [/api]: " NEW_API
    NEW_API=${NEW_API:-/api}

    cat <<ENV_AGD > "$AGENDA_DIR/.env"
VITE_API_URL=$NEW_API
ENV_AGD
    sed -i '/VITE_API_URL/d' "$SCRIPT_DIR/.env" 2>/dev/null || true
    echo "VITE_API_URL=$NEW_API" >> "$SCRIPT_DIR/.env"

    echo -e "\n${C_B_GREEN}[OK] Configuracoes salvas: VITE_API_URL=$NEW_API${C_RESET}"
    echo -e "  • Acesso local:              http://localhost:5173"
    echo -e "  • Acesso no Wi-Fi (Mobile):  http://$DETECTED_IP:5173"
    echo ""
    read -rp "Deseja recompilar o portal de agendamento agora para garantir aplicacao? [S/n]: " REC
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
    echo -e "${C_BOLD}${C_MAGENTA}--- [8] LOGS EM TEMPO REAL ---${C_RESET}\n"
    echo -e "  [1] Todos os servicos"
    echo -e "  [2] CRM Backend (Flask / Python)"
    echo -e "  [3] Portal de Agendamento (Nginx / React)"
    echo -e "  [4] PostgreSQL"
    echo -e "  [5] WhatsApp WAHA (Porta 3000)"
    echo -e "  [0] Voltar"
    echo ""
    read -rp "Selecione quais logs deseja acompanhar [0-5]: " LOG_OPT
    case $LOG_OPT in
        1) echo -e "${C_DIM}(Pressione Ctrl+C para sair dos logs)${C_RESET}"; sleep 1; $COMPOSE_CMD logs -f ;;
        2) echo -e "${C_DIM}(Pressione Ctrl+C para sair dos logs)${C_RESET}"; sleep 1; $COMPOSE_CMD logs -f crm-backend ;;
        3) echo -e "${C_DIM}(Pressione Ctrl+C para sair dos logs)${C_RESET}"; sleep 1; $COMPOSE_CMD logs -f agendamento-app ;;
        4) echo -e "${C_DIM}(Pressione Ctrl+C para sair dos logs)${C_RESET}"; sleep 1; $COMPOSE_CMD logs -f postgres ;;
        5) echo -e "${C_DIM}(Pressione Ctrl+C para sair dos logs)${C_RESET}"; sleep 1; $COMPOSE_CMD logs -f waha ;;
        0) return ;;
        *) echo -e "${C_RED}Opcao invalida.${C_RESET}" ;;
    esac
}

# ------------------------------------------------------------------------------
# 9. Redefinir Senha do Administrador
# ------------------------------------------------------------------------------
action_reset_password() {
    show_header
    echo -e "${C_BOLD}${C_MAGENTA}--- [9] REDEFINIR SENHA DO ADMINISTRADOR (admin) ---${C_RESET}\n"
    if ! docker ps --format '{{.Names}}' | grep -q 'beautyflow-crm'; then
        echo -e "${C_RED}[ERRO] O conteiner 'beautyflow-crm' precisa estar rodando.${C_RESET}"
        return
    fi

    read -rp "Digite a nova senha para o usuario 'admin' [padrao: admin]: " NEW_PASS
    NEW_PASS=${NEW_PASS:-admin}

    docker exec -i beautyflow-crm python -c "
from werkzeug.security import generate_password_hash
from db.database import _run
pw_hash = generate_password_hash('$NEW_PASS')
_run('UPDATE users SET password_hash = %s WHERE email = %s', (pw_hash, 'admin'))
print('[OK] Senha do usuario admin atualizada.')
"
    echo -e "${C_B_GREEN}[OK] Senha alterada com sucesso! Agora voce pode logar com a nova senha.${C_RESET}"
}

# ------------------------------------------------------------------------------
# 10. Desinstalar / Limpar Ambiente
# ------------------------------------------------------------------------------
action_uninstall() {
    show_header
    echo -e "${C_BOLD}${C_B_RED}--- [10] DESINSTALAR E LIMPAR AMBIENTE ---${C_RESET}\n"
    echo -e "${C_RED}ALERTA CRITICO: Esta acao ira parar todos os conteineres e APAGAR o volume${C_RESET}"
    echo -e "${C_RED}de dados do PostgreSQL (clientes, agendamentos, estoque, transacoes).${C_RESET}"
    echo -e "Recomendado: Faca um backup antes (Opcao 6) se quiser guardar os dados."
    echo ""
    read -rp "Se tem certeza absoluta, digite a palavra 'EXCLUIR': " CONF
    if [ "$CONF" = "EXCLUIR" ]; then
        echo -e "${C_CYAN}[*] Removendo conteineres, redes e volumes Docker...${C_RESET}"
        $COMPOSE_CMD --profile waha down -v --remove-orphans || $COMPOSE_CMD down -v --remove-orphans || true
        docker stop beautyflow-waha 2>/dev/null || true
        docker rm beautyflow-waha 2>/dev/null || true
        echo -e "${C_B_GREEN}[OK] Ambiente BeautyFlow removido com sucesso.${C_RESET}"
    else
        echo -e "${C_GRAY}Acao cancelada.${C_RESET}"
    fi
}

# ------------------------------------------------------------------------------
# 11. Instalador e Gestao do WhatsApp WAHA (Porta 3000)
# ------------------------------------------------------------------------------
action_install_waha() {
    show_header
    echo -e "${C_BOLD}${C_MAGENTA}--- INSTALADOR DO WHATSAPP WAHA (PORTA 3000) ---${C_RESET}\n"
    echo -e "O WAHA (WhatsApp HTTP API) permite automatizar o envio de confirmacoes,"
    echo -e "lembretes de agendamentos e integracoes com n8n diretamente pelo WhatsApp.\n"

    if ! check_dependencies; then return; fi

    echo -e "${C_B_CYAN}[1/6] Verificando disponibilidade da porta 3000...${C_RESET}"
    check_port 3000 "WhatsApp WAHA"

    echo ""
    echo -e "${C_B_CYAN}[2/6] Configuracao da API WAHA${C_RESET}"
    local DEFAULT_KEY="218c0effefb845238a1ae3651c8ced5b"
    local CUR_KEY="$DEFAULT_KEY"
    if [ -f "$SCRIPT_DIR/.env" ] && grep -q "WAHA_API_KEY=" "$SCRIPT_DIR/.env"; then
        local val
        val=$(grep "WAHA_API_KEY=" "$SCRIPT_DIR/.env" | head -n1 | cut -d'=' -f2- | tr -d '\r')
        if [ -n "$val" ]; then CUR_KEY="$val"; fi
    fi

    echo -e "      Chave de seguranca da API (utilizada para autenticacao entre o CRM e o WAHA)."
    read -rp "      Chave de API do WAHA [$CUR_KEY]: " USER_KEY
    USER_KEY=${USER_KEY:-$CUR_KEY}

    read -rp "      Nome da sessao do WhatsApp [default]: " USER_SESS
    USER_SESS=${USER_SESS:-default}

    echo ""
    echo -e "${C_B_CYAN}[3/6] Gravando variaveis de ambiente e integracoes...${C_RESET}"
    touch "$SCRIPT_DIR/.env"
    sed -i '/COMPOSE_PROFILES/d' "$SCRIPT_DIR/.env" 2>/dev/null || true
    sed -i '/INSTALL_WAHA/d' "$SCRIPT_DIR/.env" 2>/dev/null || true
    sed -i '/WAHA_API_KEY/d' "$SCRIPT_DIR/.env" 2>/dev/null || true
    sed -i '/WAHA_SESSION/d' "$SCRIPT_DIR/.env" 2>/dev/null || true
    echo "COMPOSE_PROFILES=waha" >> "$SCRIPT_DIR/.env"
    echo "INSTALL_WAHA=true" >> "$SCRIPT_DIR/.env"
    echo "WAHA_API_KEY=$USER_KEY" >> "$SCRIPT_DIR/.env"
    echo "WAHA_SESSION=$USER_SESS" >> "$SCRIPT_DIR/.env"

    if [ -d "$CRM_DIR/backend" ]; then
        touch "$CRM_DIR/backend/.env"
        sed -i '/INSTALL_WAHA/d' "$CRM_DIR/backend/.env" 2>/dev/null || true
        sed -i '/WAHA_API_KEY/d' "$CRM_DIR/backend/.env" 2>/dev/null || true
        sed -i '/WAHA_API_URL/d' "$CRM_DIR/backend/.env" 2>/dev/null || true
        sed -i '/WAHA_SESSION/d' "$CRM_DIR/backend/.env" 2>/dev/null || true
        echo "INSTALL_WAHA=true" >> "$CRM_DIR/backend/.env"
        echo "WAHA_API_KEY=$USER_KEY" >> "$CRM_DIR/backend/.env"
        echo "WAHA_API_URL=http://waha:3000" >> "$CRM_DIR/backend/.env"
        echo "WAHA_SESSION=$USER_SESS" >> "$CRM_DIR/backend/.env"
    fi

    # Atualiza banco de dados do CRM se PostgreSQL estiver acessivel
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'beautyflow-postgres'; then
        docker exec -i beautyflow-postgres psql -U postgres -d beautyflow -c "
            INSERT INTO settings (key, value) VALUES
                ('whatsapp_integrated', 'true'),
                ('waha_api_key', '$USER_KEY'),
                ('waha_session_name', '$USER_SESS'),
                ('waha_api_url', 'http://waha:3000')
            ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

            INSERT INTO integrations (name, type, enabled, config)
            SELECT 'WhatsApp WAHA', 'whatsapp', true, ('{\"session\":\"' || '$USER_SESS' || '\",\"notify_on_create\":true,\"notify_on_reminder\":true}')::jsonb
            WHERE NOT EXISTS (SELECT 1 FROM integrations WHERE type IN ('whatsapp', 'waha'));
            UPDATE integrations SET enabled = true WHERE type IN ('whatsapp', 'waha');
        " >/dev/null 2>&1 || true
    fi
    echo -e "      ${C_B_GREEN}[OK] Configuracoes gravadas com sucesso.${C_RESET}"

    echo ""
    echo -e "${C_B_CYAN}[4/6] Baixando imagem Docker do WAHA (devlikeapro/waha:latest)...${C_RESET}"
    docker pull devlikeapro/waha:latest

    echo ""
    echo -e "${C_B_CYAN}[5/6] Iniciando conteiner beautyflow-waha...${C_RESET}"
    $COMPOSE_CMD --profile waha up -d waha

    echo ""
    echo -e "${C_B_CYAN}[6/6] Aguardando o WAHA responder em http://localhost:3000/ping...${C_RESET}"
    local waha_online=0
    for i in $(seq 1 35); do
        if curl -s -f http://localhost:3000/ping >/dev/null 2>&1; then
            waha_online=1
            break
        fi
        echo -n "."
        sleep 1
    done
    echo ""

    if [ "$waha_online" -eq 1 ]; then
        echo -e "      ${C_B_GREEN}[OK] Endpoint do WAHA online!${C_RESET}"
        echo -e "      Inicializando sessao '$USER_SESS'..."
        curl -s -X POST "http://localhost:3000/api/sessions" \
            -H "Content-Type: application/json" \
            -H "X-Api-Key: $USER_KEY" \
            -d "{\"name\":\"$USER_SESS\",\"start\":true}" >/dev/null 2>&1 || true

        echo ""
        echo -e "${C_B_GREEN}==================================================================${C_RESET}"
        echo -e "  ${C_BOLD}${C_WHITE}✔ INSTALACAO DO WHATSAPP WAHA CONCLUIDA COM SUCESSO!${C_RESET}"
        echo -e "${C_B_GREEN}==================================================================${C_RESET}"
        echo -e "  • Servico API WAHA:       ${C_B_CYAN}http://localhost:3000${C_RESET}"
        echo -e "  • Painel QR Code:         ${C_B_CYAN}http://localhost:3000/dashboard${C_RESET}"
        echo -e "  • Sessao Ativa:           ${C_WHITE}$USER_SESS${C_RESET}"
        echo -e "  • Chave de API:           ${C_WHITE}$USER_KEY${C_RESET}"
        echo -e "${C_B_GREEN}==================================================================${C_RESET}"
        echo ""
        echo -e "${C_BOLD}📲 Como conectar seu WhatsApp:${C_RESET}"
        echo -e "   1. Abra o WhatsApp no seu smartphone."
        echo -e "   2. Toque em ${C_WHITE}Configuracoes (ou menu 3 pontos) > Aparelhos Conectados${C_RESET}."
        echo -e "   3. Toque em ${C_WHITE}Conectar um Aparelho${C_RESET}."
        echo -e "   4. Acesse ${C_B_CYAN}http://localhost:3000/dashboard${C_RESET} e escaneie o QR Code exibido!"
        echo ""
        read -rp "Deseja abrir o Dashboard agora no navegador? [S/n]: " OPEN_NAV
        OPEN_NAV=${OPEN_NAV:-S}
        if [[ "$OPEN_NAV" =~ ^[Ss]$ ]]; then
            if command -v xdg-open &>/dev/null; then
                xdg-open "http://localhost:3000/dashboard" 2>/dev/null || true
            elif command -v open &>/dev/null; then
                open "http://localhost:3000/dashboard" 2>/dev/null || true
            fi
        fi
    else
        echo -e "${C_YELLOW}[AVISO] O conteiner WAHA foi iniciado, mas ainda esta inicializando.${C_RESET}"
        echo -e "        Acesse em instantes: ${C_B_CYAN}http://localhost:3000/dashboard${C_RESET}"
    fi
}

action_manage_waha() {
    while true; do
        show_header
        echo -e "    ${C_B_MAGENTA}┌────────────────────────────────────────────────────────────┐${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_WHITE}${C_BOLD}INSTALADOR E GESTAO DO WHATSAPP WAHA (Porta 3000)${C_RESET}         ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}├────────────────────────────────────────────────────────────┤${C_RESET}"
        local cur_st
        cur_st=$(waha_status)
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  Status do Servico:  ${cur_st}${C_B_MAGENTA}                                │${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  Dashboard / QR:     ${C_B_CYAN}http://localhost:3000/dashboard${C_RESET}           ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}├────────────────────────────────────────────────────────────┤${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_B_GREEN}[1]${C_RESET} Instalar / Reconfigurar WhatsApp WAHA (Setup Guiado)${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_CYAN}[2]${C_RESET} Iniciar / Ativar Servico WAHA                       ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_YELLOW}[3]${C_RESET} Parar / Desativar Servico WAHA                      ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_BLUE}[4]${C_RESET} Reiniciar Servico WAHA                              ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_B_CYAN}[5]${C_RESET} Conectar WhatsApp (Iniciar Sessao e Obter QR Code)  ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_WHITE}[6]${C_RESET} Testar Conexao e Consultar Sessao WhatsApp          ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_MAGENTA}[7]${C_RESET} Abrir Painel QR Code no Navegador                   ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_GRAY}[8]${C_RESET} Ver Logs do WhatsApp em Tempo Real                  ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_B_RED}[9]${C_RESET} Desinstalar / Remover WAHA da Plataforma            ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}├────────────────────────────────────────────────────────────┤${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_DIM}[0]${C_RESET} Voltar ao Menu Principal                             ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}└────────────────────────────────────────────────────────────┘${C_RESET}"
        echo ""
        read -rp "    >> Escolha uma opcao [0-9]: " W_OPT

        case $W_OPT in
            1)
                action_install_waha
                ;;
            2)
                check_port 3000 "WhatsApp WAHA"
                sed -i '/COMPOSE_PROFILES/d' "$SCRIPT_DIR/.env" 2>/dev/null || true
                sed -i '/INSTALL_WAHA/d' "$SCRIPT_DIR/.env" 2>/dev/null || true
                echo "COMPOSE_PROFILES=waha" >> "$SCRIPT_DIR/.env"
                echo "INSTALL_WAHA=true" >> "$SCRIPT_DIR/.env"
                if [ -f "$CRM_DIR/backend/.env" ]; then
                    sed -i 's/INSTALL_WAHA=false/INSTALL_WAHA=true/g' "$CRM_DIR/backend/.env" 2>/dev/null || true
                fi
                echo -e "${C_CYAN}[*] Subindo conteiner WAHA...${C_RESET}"
                $COMPOSE_CMD --profile waha up -d waha
                echo -e "${C_B_GREEN}[OK] WhatsApp WAHA iniciado em http://localhost:3000!${C_RESET}"
                ;;
            3)
                echo -e "${C_YELLOW}[*] Parando servico WAHA...${C_RESET}"
                docker stop beautyflow-waha 2>/dev/null || true
                docker rm beautyflow-waha 2>/dev/null || true
                sed -i '/COMPOSE_PROFILES/d' "$SCRIPT_DIR/.env" 2>/dev/null || true
                sed -i '/INSTALL_WAHA/d' "$SCRIPT_DIR/.env" 2>/dev/null || true
                echo "COMPOSE_PROFILES=" >> "$SCRIPT_DIR/.env"
                echo "INSTALL_WAHA=false" >> "$SCRIPT_DIR/.env"
                if [ -f "$CRM_DIR/backend/.env" ]; then
                    sed -i 's/INSTALL_WAHA=true/INSTALL_WAHA=false/g' "$CRM_DIR/backend/.env" 2>/dev/null || true
                fi
                echo -e "${C_B_GREEN}[OK] WhatsApp WAHA desativado.${C_RESET}"
                ;;
            4)
                echo -e "${C_CYAN}[*] Reiniciando conteiner WAHA...${C_RESET}"
                $COMPOSE_CMD --profile waha restart waha
                echo -e "${C_B_GREEN}[OK] WhatsApp WAHA reiniciado.${C_RESET}"
                ;;
            5)
                echo -e "\n${C_CYAN}[*] Inicializando sessao e obtendo status da conexao WhatsApp...${C_RESET}"
                local k="218c0effefb845238a1ae3651c8ced5b"
                if [ -f "$SCRIPT_DIR/.env" ] && grep -q "WAHA_API_KEY=" "$SCRIPT_DIR/.env"; then
                    k=$(grep "WAHA_API_KEY=" "$SCRIPT_DIR/.env" | head -n1 | cut -d'=' -f2- | tr -d '\r')
                fi
                local s="default"
                if [ -f "$SCRIPT_DIR/.env" ] && grep -q "WAHA_SESSION=" "$SCRIPT_DIR/.env"; then
                    s=$(grep "WAHA_SESSION=" "$SCRIPT_DIR/.env" | head -n1 | cut -d'=' -f2- | tr -d '\r')
                fi
                curl -s -X POST "http://localhost:3000/api/sessions" \
                    -H "Content-Type: application/json" \
                    -H "X-Api-Key: $k" \
                    -d "{\"name\":\"$s\",\"start\":true}" >/dev/null 2>&1 || true
                echo -e "${C_B_GREEN}[OK] Sessao ativada.${C_RESET}"
                echo -e "Acesse o painel para escanear o QR Code: ${C_B_CYAN}http://localhost:3000/dashboard${C_RESET}"
                if command -v xdg-open &>/dev/null; then
                    xdg-open "http://localhost:3000/dashboard" 2>/dev/null || true
                elif command -v open &>/dev/null; then
                    open "http://localhost:3000/dashboard" 2>/dev/null || true
                fi
                ;;
            6)
                echo -e "\n${C_CYAN}[*] Testando endpoint WAHA em http://localhost:3000/ping...${C_RESET}"
                if curl -s -f http://localhost:3000/ping >/dev/null 2>&1; then
                    echo -e "${C_B_GREEN}[OK] Endpoint /ping respondendo com sucesso!${C_RESET}"
                    echo -e "${C_CYAN}[*] Consultando sessoes ativas...${C_RESET}"
                    local k="218c0effefb845238a1ae3651c8ced5b"
                    if [ -f "$SCRIPT_DIR/.env" ] && grep -q "WAHA_API_KEY=" "$SCRIPT_DIR/.env"; then
                        k=$(grep "WAHA_API_KEY=" "$SCRIPT_DIR/.env" | head -n1 | cut -d'=' -f2- | tr -d '\r')
                    fi
                    local sess_json
                    sess_json=$(curl -s -H "X-Api-Key: $k" http://localhost:3000/api/sessions 2>/dev/null || echo "[]")
                    echo -e "    Resposta da API: ${C_WHITE}$sess_json${C_RESET}"
                else
                    echo -e "${C_RED}[ERRO] Nao foi possivel conectar ao WAHA na porta 3000.${C_RESET}"
                    echo -e "       Instale ou inicie o servico pela opcao [1] ou [2]."
                fi
                ;;
            7)
                echo -e "${C_CYAN}[*] Abrindo painel do WAHA...${C_RESET}"
                if command -v xdg-open &>/dev/null; then
                    xdg-open "http://localhost:3000/dashboard" 2>/dev/null || true
                elif command -v open &>/dev/null; then
                    open "http://localhost:3000/dashboard" 2>/dev/null || true
                fi
                echo -e "    Acesse: ${C_B_CYAN}http://localhost:3000/dashboard${C_RESET}"
                ;;
            8)
                echo -e "${C_DIM}(Pressione Ctrl+C para sair dos logs)${C_RESET}"
                sleep 1
                $COMPOSE_CMD logs -f waha
                ;;
            9)
                echo -e "${C_B_RED}[!] Desinstalacao do WhatsApp WAHA${C_RESET}"
                read -rp "    Tem certeza que deseja remover o WAHA e suas sessoes? [s/N]: " CONF_RM
                if [[ "$CONF_RM" =~ ^[Ss]$ ]]; then
                    docker stop beautyflow-waha 2>/dev/null || true
                    docker rm beautyflow-waha 2>/dev/null || true
                    docker volume rm instalacao_waha_sessions beautyflow_waha_sessions 2>/dev/null || true
                    sed -i '/COMPOSE_PROFILES/d' "$SCRIPT_DIR/.env" 2>/dev/null || true
                    sed -i '/INSTALL_WAHA/d' "$SCRIPT_DIR/.env" 2>/dev/null || true
                    echo "COMPOSE_PROFILES=" >> "$SCRIPT_DIR/.env"
                    echo "INSTALL_WAHA=false" >> "$SCRIPT_DIR/.env"
                    if [ -f "$CRM_DIR/backend/.env" ]; then
                        sed -i 's/INSTALL_WAHA=true/INSTALL_WAHA=false/g' "$CRM_DIR/backend/.env" 2>/dev/null || true
                    fi
                    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'beautyflow-postgres'; then
                        docker exec -i beautyflow-postgres psql -U postgres -d beautyflow -c "
                            UPDATE settings SET value = 'false' WHERE key = 'whatsapp_integrated';
                            UPDATE integrations SET enabled = false WHERE type IN ('whatsapp', 'waha');
                        " >/dev/null 2>&1 || true
                    fi
                    echo -e "${C_B_GREEN}[OK] WhatsApp WAHA desinstalado da plataforma.${C_RESET}"
                fi
                ;;
            0) break ;;
            *) echo -e "    ${C_RED}Opcao invalida.${C_RESET}" ;;
        esac
        echo ""
        read -rp "Pressione [ENTER] para continuar..."
    done
}

# ------------------------------------------------------------------------------
# 12. Diagnostico do Sistema e Teste de Conexoes
# ------------------------------------------------------------------------------
action_diagnostics() {
    show_header
    echo -e "${C_BOLD}${C_MAGENTA}--- [12] DIAGNOSTICO DO SISTEMA E TESTE DE CONEXOES ---${C_RESET}\n"
    echo -e "Executando testes automatizados na infraestrutura do BeautyFlow...\n"

    # 1. Docker
    echo -n "  [1/6] Docker Engine: "
    if docker info >/dev/null 2>&1; then
        local d_ver
        d_ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "OK")
        echo -e "${C_B_GREEN}[OK] Ativo (Versao $d_ver)${C_RESET}"
    else
        echo -e "${C_B_RED}[FALHA] Docker daemon nao esta respondendo${C_RESET}"
    fi

    # 2. PostgreSQL
    echo -n "  [2/6] Banco PostgreSQL (Porta 5432): "
    if docker exec beautyflow-postgres pg_isready -U postgres -d beautyflow >/dev/null 2>&1; then
        local count_clients
        count_clients=$(docker exec beautyflow-postgres psql -U postgres -d beautyflow -t -c "SELECT count(*) FROM clients;" 2>/dev/null | tr -d ' ' || echo "0")
        echo -e "${C_B_GREEN}[OK] Conectado e respondendo ($count_clients clientes na base)${C_RESET}"
    else
        echo -e "${C_B_RED}[FALHA] PostgreSQL offline ou inacessivel${C_RESET}"
    fi

    # 3. CRM Backend
    echo -n "  [3/6] API CRM Backend (Porta 3001): "
    local crm_code
    crm_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/api/services/ 2>/dev/null || echo "000")
    if [ "$crm_code" = "200" ]; then
        echo -e "${C_B_GREEN}[OK] Online (HTTP 200)${C_RESET}"
    elif [ "$crm_code" != "000" ]; then
        echo -e "${C_B_YELLOW}[AVISO] Respondendo com HTTP $crm_code${C_RESET}"
    else
        echo -e "${C_B_RED}[FALHA] Servico nao responde em http://localhost:3001${C_RESET}"
    fi

    # 4. Portal Agendamento
    echo -n "  [4/6] Portal de Agendamento (Porta 5173): "
    local agd_code
    agd_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5173/ 2>/dev/null || echo "000")
    if [ "$agd_code" = "200" ]; then
        echo -e "${C_B_GREEN}[OK] Online (HTTP 200 Nginx)${C_RESET}"
    elif [ "$agd_code" != "000" ]; then
        echo -e "${C_B_YELLOW}[AVISO] Respondendo com HTTP $agd_code${C_RESET}"
    else
        echo -e "${C_B_RED}[FALHA] Nao responde em http://localhost:5173${C_RESET}"
    fi

    # 5. WhatsApp WAHA
    echo -n "  [5/6] WhatsApp WAHA (Porta 3000): "
    local waha_code
    waha_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ping 2>/dev/null || echo "000")
    if [ "$waha_code" = "200" ]; then
        echo -e "${C_B_GREEN}[OK] Online (HTTP 200 - Pronto para envio)${C_RESET}"
    elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^(beautyflow-waha|waha)$'; then
        echo -e "${C_B_YELLOW}[AVISO] Conteiner ativo, aguardando resposta inicial${C_RESET}"
    elif [ -f "$SCRIPT_DIR/.env" ] && grep -q "INSTALL_WAHA=false" "$SCRIPT_DIR/.env"; then
        echo -e "${C_GRAY}[DESATIVADO] WAHA nao esta habilitado (Opcao 11 para ativar)${C_RESET}"
    else
        echo -e "${C_GRAY}[INATIVO] Servico parado${C_RESET}"
    fi

    # 6. Rede Local / Wi-Fi
    local cur_ip
    cur_ip=$(detect_local_ip)
    echo -n "  [6/6] Acesso Remoto / Wi-Fi: "
    if [ "$cur_ip" != "localhost" ]; then
        echo -e "${C_B_GREEN}[OK] IP $cur_ip detectado (Agendamento: http://$cur_ip:5173)${C_RESET}"
    else
        echo -e "${C_YELLOW}[LOCAL] Apenas localhost detectado${C_RESET}"
    fi

    echo ""
    echo -e "${C_B_MAGENTA}────────────────────────────────────────────────────────────────${C_RESET}"
    echo -e "  Diagnostico concluido."
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
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_B_GREEN}[1]${C_RESET}  Instalar / Inicializar Plataforma Completa           ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_CYAN}[2]${C_RESET}  Iniciar Servicos                                     ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_YELLOW}[3]${C_RESET}  Parar Servicos                                       ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_BLUE}[4]${C_RESET}  Reiniciar Servicos                                   ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_B_CYAN}[5]${C_RESET}  Atualizar Plataforma (Rebuild sem perda de dados)    ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_MAGENTA}[6]${C_RESET}  Gerenciar Banco de Dados (Backup / Restore / Reset)  ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_WHITE}[7]${C_RESET}  Configurar IP de Rede & URL da API                   ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_GRAY}[8]${C_RESET}  Ver Logs em Tempo Real                               ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_B_YELLOW}[9]${C_RESET}  Redefinir Senha do Administrador (admin)             ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_B_RED}[10]${C_RESET} Desinstalar / Limpar Ambiente Completo              ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_B_GREEN}[11]${C_RESET} Instalar / Gerenciar WhatsApp WAHA (Porta 3000)    ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_B_CYAN}[12]${C_RESET} Diagnostico do Sistema e Teste de Conexoes          ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}├────────────────────────────────────────────────────────────┤${C_RESET}"
        echo -e "    ${C_B_MAGENTA}│${C_RESET}  ${C_DIM}[0]${C_RESET}  Sair                                                 ${C_B_MAGENTA}│${C_RESET}"
        echo -e "    ${C_B_MAGENTA}└────────────────────────────────────────────────────────────┘${C_RESET}"
        echo ""
        read -rp "    >> Escolha uma opcao [0-12]: " OPTION

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
            11) action_manage_waha ;;
            12) action_diagnostics ;;
            0)
                echo -e "\n  ${C_B_MAGENTA}BeautyFlow Platform encerrado.${C_RESET}\n"
                exit 0
                ;;
            *)
                echo -e "  ${C_RED}Opcao invalida. Escolha entre 0 e 12.${C_RESET}"
                ;;
        esac
        echo ""
        read -rp "Pressione [ENTER] para voltar ao menu..."
    done
}

main_menu
