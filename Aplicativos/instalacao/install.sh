#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║          BeautyFlow CRM + Agendamento — Instalador Docker        ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# 1. Identificação do Sistema Operacional e Distribuição
echo "🔍 [1/5] Identificando o Sistema Operacional e Distribuição..."

OS="Unknown"
DISTRO="Unknown"
DISTRO_NAME="Desconhecida"
ID_LIKE=""

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS="Linux"
    DISTRO="${ID:-linux}"
    DISTRO_NAME="${NAME:-Linux}"
    ID_LIKE="${ID_LIKE:-}"
elif [ "$(uname)" == "Darwin" ]; then
    OS="macOS"
    DISTRO="macOS"
    DISTRO_NAME="macOS"
fi

echo "  ✓ Sistema identificado: $OS ($DISTRO_NAME)"

# Função para instalar Docker de acordo com a distribuição
install_docker() {
    echo ""
    echo "📦 Instalando o Docker para a distribuição $DISTRO_NAME..."
    
    FAMILIA="$DISTRO"
    if [[ "$ID_LIKE" == *"arch"* ]]; then FAMILIA="arch"; fi
    if [[ "$ID_LIKE" == *"debian"* ]] || [[ "$ID_LIKE" == *"ubuntu"* ]]; then FAMILIA="ubuntu"; fi
    if [[ "$ID_LIKE" == *"fedora"* ]] || [[ "$ID_LIKE" == *"rhel"* ]]; then FAMILIA="fedora"; fi
    if [[ "$ID_LIKE" == *"suse"* ]]; then FAMILIA="opensuse"; fi

    case "$FAMILIA" in
        arch|manjaro|endeavouros)
            echo "-> Executando: sudo pacman -Sy --noconfirm docker docker-compose"
            sudo pacman -Sy --noconfirm docker docker-compose
            echo "-> Ativando serviço do Docker..."
            sudo systemctl enable --now docker || true
            sudo usermod -aG docker "$USER" 2>/dev/null || true
            ;;
        ubuntu|debian|pop|mint)
            echo "-> Executando: sudo apt-get update && sudo apt-get install -y docker.io docker-compose-v2"
            sudo apt-get update
            sudo apt-get install -y docker.io docker-compose-v2 || sudo apt-get install -y docker.io docker-compose
            echo "-> Ativando serviço do Docker..."
            sudo systemctl enable --now docker || true
            sudo usermod -aG docker "$USER" 2>/dev/null || true
            ;;
        fedora|rhel|centos|rocky|almalinux)
            echo "-> Executando: sudo dnf install -y docker docker-compose"
            sudo dnf install -y docker docker-compose || sudo dnf install -y docker
            echo "-> Ativando serviço do Docker..."
            sudo systemctl enable --now docker || true
            sudo usermod -aG docker "$USER" 2>/dev/null || true
            ;;
        opensuse*|sles)
            echo "-> Executando: sudo zypper in -y docker docker-compose"
            sudo zypper in -y docker docker-compose
            echo "-> Ativando serviço do Docker..."
            sudo systemctl enable --now docker || true
            sudo usermod -aG docker "$USER" 2>/dev/null || true
            ;;
        macOS)
            if command -v brew &>/dev/null; then
                echo "-> Executando: brew install --cask docker"
                brew install --cask docker
            else
                echo "❌ Por favor instale o Docker Desktop para macOS em https://www.docker.com/products/docker-desktop/"
                exit 1
            fi
            ;;
        *)
            echo "⚠️  Distribuição $DISTRO_NAME não possui instalador automático mapeado."
            echo "Por favor, instale o Docker manualmente com o gerenciador de pacotes do seu sistema."
            exit 1
            ;;
    esac
}

# 2. Verificar dependências
echo "🔍 [2/5] Verificando se o Docker está instalado..."

if ! command -v docker &> /dev/null; then
    echo "⚠️  Docker não foi encontrado no sistema ($DISTRO_NAME)."
    read -p "Deseja instalar o Docker e Docker Compose automaticamente agora? (s/N): " resp
    if [[ "$resp" =~ ^[Ss]$ ]]; then
        install_docker
    else
        echo "❌ Instalação interrompida. O Docker é necessário para rodar o projeto."
        exit 1
    fi
fi

# Verificar se o serviço do Docker está rodando
if ! docker info &> /dev/null; then
    echo "⚠️  O serviço do Docker não está ativo."
    if command -v systemctl &> /dev/null; then
        echo "-> Tentando iniciar o serviço do Docker (sudo systemctl start docker)..."
        sudo systemctl start docker || true
    fi
fi

COMPOSE_CMD=""
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo "⚠️  Docker Compose não foi encontrado."
    read -p "Deseja instalar o Docker Compose agora? (s/N): " resp
    if [[ "$resp" =~ ^[Ss]$ ]]; then
        install_docker
        if docker compose version &> /dev/null; then
            COMPOSE_CMD="docker compose"
        elif command -v docker-compose &> /dev/null; then
            COMPOSE_CMD="docker-compose"
        else
            echo "❌ Não foi possível configurar o Docker Compose."
            exit 1
        fi
    else
        echo "❌ Docker Compose é necessário para executar a plataforma."
        exit 1
    fi
fi

echo "  ✓ Docker e Docker Compose prontos!"

# 3. Configurar arquivos de ambiente (.env)
echo "⚙️  [3/5] Configurando variáveis de ambiente..."

CRM_DIR="$(cd "$SCRIPT_DIR/../CRM BeautyFlow" && pwd)"
AGENDA_DIR="$(cd "$SCRIPT_DIR/../agendamento Vinicius" && pwd)"

cat <<EOF > "$CRM_DIR/backend/.env"
DATABASE_URL=postgresql://postgres:beautyflow_pass@postgres:5432/beautyflow
N8N_WEBHOOK_URL=https://mirianfiorini.app.n8n.cloud/webhook/calendar-webhook
EOF

cat <<EOF > "$AGENDA_DIR/.env"
VITE_API_URL=http://localhost:3001/api
EOF

# .env do docker-compose (controla o build-arg do app de agendamento)
cat <<EOF > "$SCRIPT_DIR/.env"
VITE_API_URL=http://localhost:3001/api
EOF

echo "  ✓ Arquivos .env gerados com sucesso."

# 4. Construir e subir os contêineres
echo "🚀 [4/5] Subindo contêineres no Docker (PostgreSQL, CRM, Agendamento)..."
$COMPOSE_CMD up -d --build --force-recreate --remove-orphans

# 5. Aguardar inicialização e verificar saúde dos serviços
echo "⏳ [5/5] Aguardando banco de dados e aplicações inicializarem..."

wait_for_health() {
    local tries=30
    for i in $(seq 1 "$tries"); do
        local all_ok=1
        local unhealthy=""
        while IFS='=' read -r svc state health; do
            if [ -z "$svc" ]; then continue; fi
            if [ "$state" != "running" ] || [ "$health" = "unhealthy" ] || [ "$health" = "starting" ]; then
                all_ok=0
                if [ "$health" = "unhealthy" ]; then unhealthy="$unhealthy $svc"; fi
            fi
        done < <($COMPOSE_CMD ps --format '{{.Service}}={{.State}}={{.Health}}' 2>/dev/null)
        if [ -n "$unhealthy" ]; then
            echo "❌ Serviço(s) com problema:${unhealthy}"
            echo ""
            echo "🔎 Diagnóstico — execute:"
            echo "  docker compose logs --tail=100 <servico>"
            return 1
        fi
        if [ "$all_ok" -eq 1 ]; then
            echo "  ✓ Todos os serviços estão saudáveis."
            return 0
        fi
        sleep 3
    done
    echo "⚠️  Tempo de espera esgotado. Verifique os logs com: $COMPOSE_CMD logs -f"
    return 1
}

if ! wait_for_health; then
    echo "❌ A inicialização apresentou problemas. Verifique os logs acima."
    exit 1
fi

echo ""
echo "══════════════════════════════════════════════════════════════════"
echo "🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
echo "══════════════════════════════════════════════════════════════════"
echo " Os seguintes serviços estão ativos:"
echo "  • CRM BeautyFlow (Painel):   http://localhost:3001"
echo "  • Portal de Agendamento:     http://localhost:5173"
echo "  • Banco de Dados PostgreSQL: localhost:5432 (DB: beautyflow)"
echo "══════════════════════════════════════════════════════════════════"
echo " Comandos úteis:"
echo "  • Ver logs:           cd Aplicativos/instalacao && $COMPOSE_CMD logs -f"
echo "  • Parar serviços:     cd Aplicativos/instalacao && $COMPOSE_CMD down"
echo "  • Iniciar serviços:   cd Aplicativos/instalacao && $COMPOSE_CMD up -d"
echo "══════════════════════════════════════════════════════════════════"
