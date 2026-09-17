#!/usr/bin/env bash
# ==============================================================================
# BeautyFlow Platform — Instalador e Configurador do WhatsApp WAHA
# Suporte: Linux / macOS | Contêiner: devlikeapro/waha:latest (Porta 3000)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CRM_DIR="$(cd "$SCRIPT_DIR/../CRM BeautyFlow" && pwd)"

# Recarregar sessao com o grupo docker caso necessario
if [ -z "${BF_GROUP_RELOADED:-}" ] && [ "$(id -u)" -ne 0 ]; then
    if ! id -Gn 2>/dev/null | grep -qw docker && getent group docker 2>/dev/null | grep -qw "$USER"; then
        export BF_GROUP_RELOADED=1
        exec newgrp docker -c "exec bash \"$SCRIPT_DIR/install_waha.sh\" \"$@\""
    fi
fi

# Paleta de Cores TUI
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

# Deteccao de Docker Compose
COMPOSE_CMD=""
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo -e "${C_B_RED}[ERRO] Docker Compose nao foi encontrado no sistema.${C_RESET}"
    exit 1
fi

echo -e "${C_B_MAGENTA}"
echo "    ┌────────────────────────────────────────────────────────────┐"
echo -e "    │  ${C_WHITE}${C_BOLD}INSTALADOR DO WHATSAPP WAHA — BeautyFlow Platform${C_RESET}${C_B_MAGENTA}         │"
echo -e "    │  ${C_DIM}WhatsApp HTTP API Engine + Dashboard + Integracao CRM${C_RESET}${C_B_MAGENTA}     │"
echo "    └────────────────────────────────────────────────────────────┘"
echo -e "${C_RESET}"

# 1. Checar Docker Engine
echo -e "${C_B_CYAN}[1/6] Verificando Docker Engine...${C_RESET}"
if ! docker info >/dev/null 2>&1; then
    echo -e "${C_RED}[ERRO] O daemon do Docker nao esta em execucao.${C_RESET}"
    echo -e "       Inicie o servico do Docker e execute o instalador novamente."
    exit 1
fi
echo -e "      ${C_B_GREEN}[OK] Docker operando normalmente.${C_RESET}"

# 2. Checar e liberar porta 3000 se em conflito
echo ""
echo -e "${C_B_CYAN}[2/6] Verificando disponibilidade da porta 3000...${C_RESET}"
if ss -tlpn 2>/dev/null | grep -qE ":3000[[:space:]]"; then
    if ! docker ps --format '{{.Ports}}' 2>/dev/null | grep -qE ":3000->"; then
        echo -e "      ${C_YELLOW}[AVISO] A porta 3000 esta em uso por um servico local fora do Docker.${C_RESET}"
        read -rp "      Deseja tentar encerrar o processo local na porta 3000? (S/n): " STOP_P
        STOP_P=${STOP_P:-S}
        if [[ "$STOP_P" =~ ^[Ss]$ ]]; then
            if command -v fuser &>/dev/null; then
                fuser -k -n tcp 3000 2>/dev/null || true
            elif command -v lsof &>/dev/null; then
                lsof -ti :3000 -sTCP:LISTEN 2>/dev/null | xargs -r kill -9 2>/dev/null || true
            fi
            sleep 1
        fi
    else
        echo -e "      ${C_GRAY}A porta 3000 ja esta atribuida a um conteiner Docker.${C_RESET}"
    fi
else
    echo -e "      ${C_B_GREEN}[OK] Porta 3000 livre.${C_RESET}"
fi

# 3. Configuracao da API WAHA
echo ""
echo -e "${C_B_CYAN}[3/6] Configuracao de Seguranca & Sessao${C_RESET}"
DEFAULT_KEY="218c0effefb845238a1ae3651c8ced5b"
CUR_KEY="$DEFAULT_KEY"
if [ -f "$SCRIPT_DIR/.env" ] && grep -q "WAHA_API_KEY=" "$SCRIPT_DIR/.env"; then
    val=$(grep "WAHA_API_KEY=" "$SCRIPT_DIR/.env" | head -n1 | cut -d'=' -f2- | tr -d '\r')
    if [ -n "$val" ]; then CUR_KEY="$val"; fi
fi

echo -e "      Chave de seguranca para integracao entre o CRM BeautyFlow e o WAHA."
read -rp "      Chave de API do WAHA [$CUR_KEY]: " USER_KEY
USER_KEY=${USER_KEY:-$CUR_KEY}

read -rp "      Nome da Sessao do WhatsApp [default]: " USER_SESS
USER_SESS=${USER_SESS:-default}

# 4. Gravar configuracoes no .env
echo ""
echo -e "${C_B_CYAN}[4/6] Persistindo variaveis de ambiente e ativando perfil 'waha'...${C_RESET}"
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

# Se o banco PostgreSQL ja estiver rodando no Docker, atualiza a tabela settings e integrations
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

# 5. Baixar e subir imagem Docker
echo ""
echo -e "${C_B_CYAN}[5/6] Baixando e iniciando o servico WAHA (devlikeapro/waha:latest)...${C_RESET}"
$COMPOSE_CMD --profile waha up -d waha

# 6. Aguardar healthcheck e criar sessao
echo ""
echo -e "${C_B_CYAN}[6/6] Aguardando o WAHA responder em http://localhost:3000/ping...${C_RESET}"
waha_ready=0
for i in $(seq 1 35); do
    if curl -s -f http://localhost:3000/ping >/dev/null 2>&1; then
        waha_ready=1
        break
    fi
    echo -n "."
    sleep 1
done
echo ""

if [ "$waha_ready" -eq 1 ]; then
    echo -e "      ${C_B_GREEN}[OK] Endpoint do WAHA online!${C_RESET}"
    echo -e "      Inicializando sessao '$USER_SESS'..."
    curl -s -X POST "http://localhost:3000/api/sessions" \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $USER_KEY" \
        -d "{\"name\":\"$USER_SESS\",\"start\":true}" >/dev/null 2>&1 || true

    echo -e "      Inicializando banco de dados dedicado de mensagens do WhatsApp..."
    if command -v python3 &>/dev/null; then
        python3 -c "import sys; sys.path.insert(0, '$CRM_DIR/backend'); from db.whatsapp_chat_db import init_chat_db; init_chat_db()" >/dev/null 2>&1 || true
    elif command -v python &>/dev/null; then
        python -c "import sys; sys.path.insert(0, '$CRM_DIR/backend'); from db.whatsapp_chat_db import init_chat_db; init_chat_db()" >/dev/null 2>&1 || true
    fi
    echo -e "      ${C_B_GREEN}[OK] Banco de dados do Chat WhatsApp configurado (db/whatsapp_chat.db).${C_RESET}"

    echo -e "      Configurando sincronizacao de mensagens em tempo real no WAHA..."
    curl -s -X PUT "http://localhost:3000/api/sessions/$USER_SESS" \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $USER_KEY" \
        -d "{\"config\":{\"webhooks\":[{\"url\":\"http://beautyflow-crm:3001/api/whatsapp/webhook\",\"events\":[\"message\",\"message.any\",\"message.ack\"]}]}}" >/dev/null 2>&1 || true

    echo ""
    echo -e "${C_B_GREEN}==================================================================${C_RESET}"
    echo -e "  ${C_BOLD}${C_WHITE}✔ INSTALACAO DO WHATSAPP WAHA CONCLUIDA COM SUCESSO!${C_RESET}"
    echo -e "${C_B_GREEN}==================================================================${C_RESET}"
    echo -e "  • URL da API WAHA:       ${C_B_CYAN}http://localhost:3000${C_RESET}"
    echo -e "  • Painel QR Code:         ${C_B_CYAN}http://localhost:3000/dashboard${C_RESET}"
    echo -e "  • Sessao Ativa:           ${C_WHITE}$USER_SESS${C_RESET}"
    echo -e "  • Chave de API:           ${C_WHITE}$USER_KEY${C_RESET}"
    echo -e "  • Gerenciador de Chat:    ${C_B_GREEN}Ativo com Banco Dedicado (whatsapp_chat.db)${C_RESET}"
    echo -e "${C_B_GREEN}==================================================================${C_RESET}"
    echo ""
    echo -e "${C_BOLD}📲 Como conectar seu WhatsApp:${C_RESET}"
    echo -e "   1. Abra o WhatsApp no seu smartphone."
    echo -e "   2. Va em: ${C_WHITE}Configuracoes (ou menu 3 pontos) > Aparelhos Conectados${C_RESET}."
    echo -e "   3. Toque em ${C_WHITE}Conectar um Aparelho${C_RESET}."
    echo -e "   4. Acesse ${C_B_CYAN}http://localhost:3000/dashboard${C_RESET} e escaneie o QR Code exibido!"
    echo ""

    read -rp "Deseja abrir o Dashboard agora no navegador? [S/n]: " OPEN_BROWSER
    OPEN_BROWSER=${OPEN_BROWSER:-S}
    if [[ "$OPEN_BROWSER" =~ ^[Ss]$ ]]; then
        if command -v xdg-open &>/dev/null; then
            xdg-open "http://localhost:3000/dashboard" 2>/dev/null || true
        elif command -v open &>/dev/null; then
            open "http://localhost:3000/dashboard" 2>/dev/null || true
        fi
    fi
else
    echo -e "${C_YELLOW}[AVISO] O contêiner WAHA esta iniciando em segundo plano.${C_RESET}"
    echo -e "        Acesse em alguns instantes: ${C_B_CYAN}http://localhost:3000/dashboard${C_RESET}"
fi

echo ""
