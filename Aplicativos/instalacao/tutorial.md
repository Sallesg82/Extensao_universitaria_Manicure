# BeautyFlow Platform — Hub de Gestão, Instalação e Manutenção

O instalador e hub de gestão do BeautyFlow é uma interface de terminal interativa (TUI) completa, desenvolvida para gerenciar com segurança, alta disponibilidade e facilidade todos os aspectos da plataforma no Linux, macOS e Windows.

---

## 1. Arquitetura da Plataforma

A plataforma opera em arquitetura conteinerizada isolada com Docker Compose:

* **CRM BeautyFlow (Backend & Painel do Gestor)**: Executado em Python 3.11 / Flask com WebSockets Socket.IO na porta **3001**.
* **Beatriz Gomes Studio (Portal de Agendamento)**: Single Page Application React 19 compilada com Vite e servida por Nginx Alpine na porta **5173**.
* **Banco de Dados PostgreSQL 16**: Banco relacional robusto com pool de conexões ativo na porta **5432**.
* **WhatsApp WAHA (WhatsApp HTTP API)**: Microserviço dedicado para automação e envio de notificações via WhatsApp (WebJS) na porta **3000**.

---

## 2. Pré-requisitos

1. **Docker e Docker Compose**:
   * **Linux**: Docker Engine ou Docker Desktop (o instalador detecta e oferece instalação automática para distribuições Debian, Ubuntu, Arch, Fedora, openSUSE).
   * **Windows / macOS**: Docker Desktop com WSL2 (Windows) ou Docker Desktop (macOS).
2. **Portas Livres**:
   * `5432` (PostgreSQL)
   * `3001` (CRM BeautyFlow)
   * `5173` (Portal de Agendamento Web)
   * `3000` (WhatsApp WAHA — opcional/habilitável)

---

## 3. Como Executar o Instalador / Hub Interativo

### No Linux / macOS:
No diretório raiz do projeto ou na pasta `Aplicativos/instalacao`:
```bash
./install.sh
```
*(ou `cd Aplicativos/instalacao && ./install.sh`)*

### No Windows:
Dê dois cliques no arquivo `install.bat` na raiz ou em `Aplicativos\instalacao\install.bat`, ou abra o Prompt de Comando (CMD) e digite:
```cmd
install.bat
```

---

## 4. Funcionalidades do Hub (Menu Principal)

```
    ┌────────────────────────────────────────────────────────────┐
    │  BEAUTYFLOW PLATFORM  —  Hub de Gestao e Instalacao        │
    │  CRM BeautyFlow  +  Portal Agendamento  +  PostgreSQL      │
    ├────────────────────────────────────────────────────────────┤
    │  Status dos Servicos:                                      │
    │    PostgreSQL (5432):     [ ONLINE  ]                      │
    │    CRM Backend (3001):    [ ONLINE  ]                      │
    │    Agendamento (5173):    [ ONLINE  ]                      │
    │    WhatsApp WAHA (3000):  [ ONLINE  ]                      │
    │  Rede Local: 192.168.1.15                                  │
    └────────────────────────────────────────────────────────────┘
```

### [1] Instalar / Inicializar Plataforma Completa
* Verifica preventivamente o uso das portas (5432, 3001 e 5173) e sugere liberação em caso de conflito.
* Detecta o endereço IP local na interface de rede para acesso de smartphones via Wi-Fi.
* Instala o núcleo da plataforma (PostgreSQL, CRM BeautyFlow e Portal de Agendamento). O WhatsApp WAHA é um módulo opcional gerenciado e instalado exclusivamente na opção **[11]**.
* Gera e sincroniza automaticamente os arquivos `.env` do CRM, Agendamento e instalador.
* Constrói e inicializa os contêineres Docker com checagem de integridade (*healthcheck*).
* Sincroniza tabelas (incluindo estoque de produtos e metas) e restrições de integridade no PostgreSQL.
* Apresenta resumo de URLs e credenciais padrão de acesso.

### [2] Iniciar Serviços
* Sobe todos os contêineres em background.
* Respeita o perfil do WhatsApp WAHA se estiver ativo.
* Aguarda o healthcheck de prontidão de cada serviço.

### [3] Parar Serviços
* Pausa todos os serviços com encerramento gracioso (*graceful shutdown*).
* **Zero perda de dados**: todos os cadastros, agendamentos e transações permanecem seguros no volume persistente do PostgreSQL.

### [4] Reiniciar Serviços
* Reinicia os contêineres da plataforma e aguarda a estabilização.

### [5] Atualizar Plataforma (Rebuild sem perda de dados)
* Permite sincronizar alterações do repositório Git (`git pull`).
* Reconstrói as imagens Docker com os arquivos e modificações mais recentes.
* Aplica automaticamente migrações de banco sem apagar registros existentes.

### [6] Gerenciar Banco de Dados (Submenu do PostgreSQL)
* **[1] Criar Backup Completo (pg_dump)**: Gera dump `.sql` com carimbo de data/hora na pasta `Aplicativos/instalacao/backups/`.
* **[2] Restaurar Banco a partir de Backup**: Lista os arquivos `.sql` disponíveis ou permite informar um caminho customizado, com confirmação de segurança.
* **[3] Listar Backups Existentes**: Exibe nome, tamanho e data de modificação de cada backup.
* **[4] Verificar Integridade das Tabelas e Registros**: Exibe a contagem em tempo real de clientes, agendamentos, catálogo de serviços, transações financeiras, produtos de estoque, metas mensais, horários, integrações, notificações e usuários.
* **[5] Otimizar Banco de Dados (VACUUM ANALYZE)**: Limpa espaços ociosos e recalcula as estatísticas do otimizador de consultas do PostgreSQL.
* **[6] Resetar Banco (Limpar e recriar estrutura)**: Exige digitação da palavra `RESET` e recria o banco limpo com dados padrão e catálogo inicial.

### [7] Configurar IP de Rede & URL da API
* Permite alterar o endereço de rede acessível por clientes externos ou dispositivos na mesma rede Wi-Fi.
* Atualiza os arquivos de configuração e oferece recompilação imediata do frontend de agendamento.

### [8] Ver Logs em Tempo Real
* Streaming contínuo de logs:
  1. Todos os serviços juntos
  2. CRM Backend (Flask / Python)
  3. Portal de Agendamento (Nginx)
  4. PostgreSQL
  5. WhatsApp WAHA (porta 3000)
* Encerramento fácil pressionando `Ctrl+C`.

### [9] Redefinir Senha do Administrador (admin)
* Permite redefinir a senha do usuário `admin` diretamente pelo banco com criptografia segura (hash PBKDF2/SHA-256), sem necessitar de acesso SQL manual.

### [10] Desinstalar / Limpar Ambiente Completo
* Exige digitação da palavra `EXCLUIR` para segurança contra operações acidentais.
* Remove os contêineres, redes e volumes Docker.

### [11] Instalar / Gerenciar WhatsApp WAHA (Porta 3000)
Submenu dedicado para instalação guiada e gerenciamento do WhatsApp:
* **[1] Instalar / Reconfigurar WhatsApp WAHA (Setup Guiado)**: Assistente passo a passo que checa portas, configura chave de API e sessão, baixa a imagem oficial `devlikeapro/waha:latest`, sobe o contêiner e inicializa a sessão automaticamente.
* **[2] Iniciar / Ativar Serviço WAHA**: Habilita o perfil `waha` e sobe o contêiner na porta 3000.
* **[3] Parar / Desativar Serviço WAHA**: Pausa e remove o contêiner WAHA, desabilitando o perfil.
* **[4] Reiniciar Serviço WAHA**: Reinicia o contêiner do WhatsApp.
* **[5] Conectar WhatsApp (Iniciar Sessão e Obter QR Code)**: Dispara a inicialização da sessão e abre a tela para escanear o QR Code.
* **[6] Testar Conexão**: Faz requisição ao endpoint `/ping` e consulta as sessões ativas via API.
* **[7] Abrir Painel QR Code no Navegador**: Abre diretamente `http://localhost:3000/dashboard` para escanear o QR Code no celular.
* **[8] Ver Logs do WhatsApp**: Acompanha a inicialização do navegador headless e eventos de mensagem.
* **[9] Desinstalar / Remover WAHA**: Remove o contêiner e dados do WAHA da plataforma de forma limpa.

> [!TIP]
> Você também pode executar o instalador direto pelo terminal a qualquer momento com:
> `bash install_waha.sh` (Linux/macOS) ou `install_waha.bat` (Windows).

### [12] Diagnóstico do Sistema e Teste de Conexões
Executa um *self-test* completo:
1. Docker Engine e daemon de execução.
2. PostgreSQL (porta 5432) e consulta de integridade.
3. API do CRM Backend (porta 3001).
4. Portal de Agendamento Web (porta 5173).
5. WhatsApp WAHA (porta 3000).
6. Endereço IP da rede local.
Apresenta relatório visual com diagnósticos em verde `[OK]`, amarelo `[AVISO]` ou vermelho `[FALHA]`.

---

## 5. Integração com WhatsApp WAHA

O microserviço WAHA (WhatsApp HTTP API) roda no contêiner `beautyflow-waha` na porta **3000**.

### Como Parear seu WhatsApp:
1. Inicie a plataforma (ou selecione a opção **[11] > [2]** para ativar o WAHA).
2. Abra no navegador: **http://localhost:3000/dashboard** (ou opção **[11] > [5]**).
3. Na sessão padrão (`default`), clique em **Start** e escaneie o **QR Code** apontando a câmera do WhatsApp do seu celular (*Aparelhos Conectados > Conectar um aparelho*).
4. Assim que o status mudar para **WORKING**, o BeautyFlow estará pronto para enviar mensagens automaticamente!

### Notificações Automáticas Suportadas:
* **Novo Agendamento**: Envia mensagem com nome do cliente, serviço, data, horário e valor.
* **Cancelamento**: Envia aviso empático de cancelamento para o cliente.
* **Lembrete de Horário**: Notificação de lembrete com antecedência.
* **Pós-Atendimento e Retorno**: Mensagens de agradecimento e incentivo a retorno.

### Variáveis Disponíveis nos Modelos de Mensagem:
* `{nome}`: Nome completo do cliente
* `{primeiro_nome}`: Primeiro nome do cliente
* `{servico}`: Nome do procedimento
* `{data}`: Data formatada (DD/MM/AAAA)
* `{horario}`: Horário do atendimento (HH:MM)
* `{valor}`: Valor formatado (ex: 45,00)
* `{empresa}`: Nome do salão/estúdio

---

## 6. Scripts Rápidos (1 Clique)

Para o dia a dia sem entrar no menu interativo, execute diretamente na raiz ou em `Aplicativos/instalacao`:

| Ação | Linux / macOS | Windows |
|---|---|---|
| **Hub Completo** | `./install.sh` | `install.bat` |
| **Iniciar Tudo** | `./start.sh` | `start.bat` |
| **Parar Tudo** | `./stop.sh` | `stop.bat` |

---

## 7. URLs de Acesso Padrão

* **Painel CRM BeautyFlow**: [http://localhost:3001](http://localhost:3001)
  * Usuário padrão: `admin`
  * Senha padrão: `admin`
* **Portal de Agendamento do Cliente**: [http://localhost:5173](http://localhost:5173)
* **Acesso Mobile (mesmo Wi-Fi)**: `http://<SEU_IP_LOCAL>:5173`
* **WhatsApp WAHA Dashboard**: [http://localhost:3000/dashboard](http://localhost:3000/dashboard)
* **Banco de Dados PostgreSQL**: `localhost:5432` (Banco: `beautyflow`, Usuário: `postgres`, Senha: `beautyflow_pass`)
