# BeautyFlow Platform — Hub de Gestao, Instalacao e Manutencao

O instalador e hub de gestao do BeautyFlow e uma interface de terminal (TUI) interativa e completa, desenvolvida para gerenciar com seguranca todos os aspectos da plataforma no Linux, macOS e Windows.

---

## Pre-requisitos

1. Docker instalado e em execucao (Docker Desktop no Windows/macOS ou Docker Engine no Linux).
2. Docker Compose habilitado.

---

## Como Executar o Hub Interativo

### No Linux / macOS:
```bash
cd "Aplicativos/instalacao"
./install.sh
```

### No Windows:
De dois cliques no arquivo `install.bat` ou abra o Prompt de Comando (CMD) na pasta `Aplicativos/instalacao` e digite:
```cmd
install.bat
```

---

## Funcionalidades do Hub (Menu Principal)

```
    ┌────────────────────────────────────────────────────────────┐
    │  BEAUTYFLOW PLATFORM  —  Hub de Gestao e Instalacao        │
    │  CRM BeautyFlow  +  Portal Agendamento  +  PostgreSQL      │
    ├────────────────────────────────────────────────────────────┤
    │  Status dos Servicos:                                      │
    │    PostgreSQL (5432):     [ ONLINE  ]                      │
    │    CRM Backend (3001):    [ ONLINE  ]                      │
    │    Agendamento (5173):    [ ONLINE  ]                      │
    └────────────────────────────────────────────────────────────┘
```

1. **[1] Instalar / Inicializar Plataforma**:
   - Detecta e valida Docker e Docker Compose.
   - Analisa conflitos de porta no sistema (5432, 3001, 5173).
   - Detecta o IP de rede para acesso via celular/tablet.
   - Inicializa os contêineres e o banco de dados com os dados padrao.

2. **[2] Iniciar Servicos**:
   - Sobe todos os contêineres em background.

3. **[3] Parar Servicos**:
   - Pausa os serviços sem risco de perda de dados.

4. **[4] Reiniciar Servicos**:
   - Reinicia contêineres e verifica os testes de saude.

5. **[5] Atualizar Plataforma**:
   - Atualiza o repositorio via Git (opcional) e recompila as imagens Docker mantendo intacto o volume do banco PostgreSQL.

6. **[6] Gerenciar Banco de Dados (Submenu)**:
   - **Criar Backup Completo**: Gera dump `.sql` com carimbo de data/hora na pasta `backups/`.
   - **Restaurar Backup**: Importa arquivo `.sql` existente para o PostgreSQL.
   - **Listar Backups**: Exibe histórico de backups e tamanhos de arquivo.
   - **Verificar Registros**: Mostra a contagem de clientes, agendamentos, serviços e usuários.
   - **Resetar Banco**: Recria o banco limpo aplicando as migrações e sementes iniciais.

7. **[7] Configurar IP de Rede & URL da API**:
   - Ajusta o IP para que clientes em smartphones conectados ao Wi-Fi consigam agendar e sincronizar com o CRM.

8. **[8] Ver Logs em Tempo Real**:
   - Exibe logs em streaming de todos os serviços ou de contêineres específicos.

9. **[9] Redefinir Senha do Administrador**:
   - Altera a senha do usuário `admin` diretamente no banco sem precisar acessar o terminal SQL.

10. **[10] Desinstalar / Limpar Ambiente Completo**:
    - Remove contêineres, redes e volumes após confirmação de segurança.

---

## Scripts Rapidos (Acoes com 1 clique)

Para operacoes diarias sem entrar no menu interativo:

* **Iniciar**:
  * Linux/macOS: `./start.sh`
  * Windows: de dois cliques em `start.bat`
* **Parar**:
  * Linux/macOS: `./stop.sh`
  * Windows: de dois cliques em `stop.bat`

---

## Acesso aos Servicos

* Painel CRM BeautyFlow (Gestao): http://localhost:3001
  * Usuario padrao: `admin`
  * Senha padrao: `admin`
* Portal de Agendamento (Clientes): http://localhost:5173
* Banco de Dados PostgreSQL: `localhost:5432` (DB: `beautyflow`, Usuario: `postgres`)
