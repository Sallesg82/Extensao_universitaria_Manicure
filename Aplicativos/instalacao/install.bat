@echo off
chcp 65001 > NUL
setlocal enabledelayedexpansion

:: Garante que o diretorio de execucao seja a pasta deste script
cd /d "%~dp0"

set "CRM_DIR=..\CRM BeautyFlow"
set "AGENDA_DIR=..\Beatriz Gomes Studio"
set "BACKUP_DIR=backups"
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"

:: Detectar comando do Compose
set "COMPOSE_CMD=docker compose"
docker compose version >nul 2>&1
if %errorlevel% neq 0 (
    where docker-compose >nul 2>&1
    if %errorlevel% equ 0 (
        set "COMPOSE_CMD=docker-compose"
    ) else (
        set "COMPOSE_CMD="
    )
)

:MENU_LOOP
cls
echo.
echo     ┌────────────────────────────────────────────────────────────┐
echo     │  BEAUTYFLOW PLATFORM  —  Hub de Gestao e Instalacao        │
echo     │  CRM BeautyFlow  +  Portal Agendamento  +  PostgreSQL      │
echo     │  Edicao Windows                                            │
echo     ├────────────────────────────────────────────────────────────┤
echo     │  Status dos Servicos Docker:                               │

:: Checar status postgres
set "ST_PG=[ OFFLINE ]"
docker ps --format "{{.Names}}" 2>nul | findstr /i "beautyflow-postgres" >nul 2>&1
if !errorlevel! equ 0 set "ST_PG=[ ONLINE  ]"

:: Checar status crm
set "ST_CRM=[ OFFLINE ]"
docker ps --format "{{.Names}}" 2>nul | findstr /i "beautyflow-crm" >nul 2>&1
if !errorlevel! equ 0 set "ST_CRM=[ ONLINE  ]"

:: Checar status agendamento
set "ST_AGD=[ OFFLINE ]"
docker ps --format "{{.Names}}" 2>nul | findstr /i "beautyflow-agendamento" >nul 2>&1
if !errorlevel! equ 0 set "ST_AGD=[ ONLINE  ]"

echo     │    PostgreSQL (5432):     !ST_PG!                        │
echo     │    CRM Backend (3001):    !ST_CRM!                        │
echo     │    Agendamento (5173):    !ST_AGD!                        │
echo     └────────────────────────────────────────────────────────────┘
echo.
echo     ┌────────────────────────────────────────────────────────────┐
echo     │  Menu Principal de Operacoes                               │
echo     ├────────────────────────────────────────────────────────────┤
echo     │  [1]  Instalar / Inicializar Plataforma                    │
echo     │  [2]  Iniciar Servicos                                     │
echo     │  [3]  Parar Servicos                                       │
echo     │  [4]  Reiniciar Servicos                                   │
echo     │  [5]  Atualizar Plataforma (Rebuild sem perda de dados)    │
echo     │  [6]  Gerenciar Banco de Dados (Backup / Restore / Reset)  │
echo     │  [7]  Configurar IP de Rede & URL da API                   │
echo     │  [8]  Ver Logs em Tempo Real                               │
echo     │  [9]  Redefinir Senha do Administrador (admin)             │
echo     │  [10] Desinstalar / Limpar Ambiente Completo               │
echo     ├────────────────────────────────────────────────────────────┤
echo     │  [0]  Sair                                                 │
echo     └────────────────────────────────────────────────────────────┘
echo.
set /p "OPTION=    >> Escolha uma opcao [0-10]: "

if "%OPTION%"=="1" goto ACT_INSTALL
if "%OPTION%"=="2" goto ACT_START
if "%OPTION%"=="3" goto ACT_STOP
if "%OPTION%"=="4" goto ACT_RESTART
if "%OPTION%"=="5" goto ACT_UPDATE
if "%OPTION%"=="6" goto ACT_DB_MENU
if "%OPTION%"=="7" goto ACT_NETWORK
if "%OPTION%"=="8" goto ACT_LOGS
if "%OPTION%"=="9" goto ACT_RESETPW
if "%OPTION%"=="10" goto ACT_UNINSTALL
if "%OPTION%"=="0" goto ACT_EXIT

echo   [ERRO] Opcao invalida. Digite um numero de 0 a 10.
timeout /t 2 >nul
goto MENU_LOOP

:: ============================================================================
:: 1. INSTALAR / INICIALIZAR
:: ============================================================================
:ACT_INSTALL
cls
echo.
echo --- [1] INSTALACAO E INICIALIZACAO COMPLETA ---
echo.

where docker >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERRO] O Docker nao foi encontrado neste computador.
    echo Por favor, instale o Docker Desktop para Windows:
    echo https://www.docker.com/products/docker-desktop/
    pause
    goto MENU_LOOP
)

docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo [AVISO] O Docker Desktop esta instalado, mas o motor (daemon) ainda nao esta rodando.
    echo Abra o aplicativo Docker Desktop e aguarde o status 'Engine running'.
    pause
    docker info >nul 2>&1
    if !errorlevel! neq 0 (
        echo [ERRO] O Docker Desktop ainda nao respondeu.
        pause
        goto MENU_LOOP
    )
)

if "%COMPOSE_CMD%"=="" (
    echo [ERRO] Docker Compose nao disponivel. Atualize o Docker Desktop.
    pause
    goto MENU_LOOP
)

echo [*] Verificando portas no Windows (5432, 3001, 5173)...
netstat -ano | findstr ":5432 " | findstr "LISTENING" >nul 2>&1
if %errorlevel% equ 0 (
    docker ps --format "{{.Ports}}" 2>nul | findstr ":5432->" >nul 2>&1
    if !errorlevel! neq 0 (
        echo [AVISO] A porta 5432 ja esta em uso no Windows (ex: servico PostgreSQL local).
        echo Recomendado pausar o servico local do PostgreSQL antes de continuar.
    )
)

echo.
echo [*] Detectando endereco IP para acesso via Wi-Fi...
set "LOCAL_IP=localhost"
for /f "tokens=*" %%i in ('powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 ^| Where-Object { $_.InterfaceAlias -notlike '*Loopback*' -and $_.IPAddress -notlike '169.254*' } ^| Select-Object -First 1).IPAddress" 2^>nul') do (
    if not "%%i"=="" set "LOCAL_IP=%%i"
)

echo IP detectado na rede local: !LOCAL_IP!
set /p "USER_IP=Confirme o IP ou digite outro (ex: localhost) [!LOCAL_IP!]: "
if "!USER_IP!"=="" set "USER_IP=!LOCAL_IP!"

(
  echo DATABASE_URL=postgresql://postgres:beautyflow_pass@postgres:5432/beautyflow
  echo N8N_WEBHOOK_URL=https://mirianfiorini.app.n8n.cloud/webhook/calendar-webhook
) > "%CRM_DIR%\backend\.env"

(
  echo VITE_API_URL=http://!USER_IP!:3001/api
) > "%AGENDA_DIR%\.env"

(
  echo VITE_API_URL=http://!USER_IP!:3001/api
) > ".env"

echo [OK] Arquivos .env configurados.
echo.
echo [*] Construindo e subindo os conteineres Docker...
%COMPOSE_CMD% up -d --build --force-recreate --remove-orphans

echo.
echo [*] Aguardando inicializacao dos servicos...
timeout /t 8 /nobreak >nul

echo.
echo ════════════════════════════════════════════════════════════════
echo   INSTALACAO CONCLUIDA COM SUCESSO!
echo ════════════════════════════════════════════════════════════════
echo   Painel CRM BeautyFlow:    http://localhost:3001
echo   Credenciais de Acesso:    Usuario: admin ^| Senha: admin
echo   Portal de Agendamento:    http://localhost:5173
echo   Acesso Mobile (mesmo Wi-Fi): http://!USER_IP!:5173
echo   Banco de Dados Postgres:  localhost:5432 (DB: beautyflow)
echo ════════════════════════════════════════════════════════════════
pause
goto MENU_LOOP

:: ============================================================================
:: 2. INICIAR SERVICOS
:: ============================================================================
:ACT_START
cls
echo.
echo --- [2] INICIAR SERVICOS ---
echo.
%COMPOSE_CMD% up -d
echo.
echo [OK] Servicos iniciados.
timeout /t 4 /nobreak >nul
pause
goto MENU_LOOP

:: ============================================================================
:: 3. PARAR SERVICOS
:: ============================================================================
:ACT_STOP
cls
echo.
echo --- [3] PARAR SERVICOS ---
echo.
%COMPOSE_CMD% stop
echo.
echo [OK] Servicos pausados. Dados preservados.
pause
goto MENU_LOOP

:: ============================================================================
:: 4. REINICIAR SERVICOS
:: ============================================================================
:ACT_RESTART
cls
echo.
echo --- [4] REINICIAR SERVICOS ---
echo.
%COMPOSE_CMD% restart
echo.
echo [OK] Servicos reiniciados.
pause
goto MENU_LOOP

:: ============================================================================
:: 5. ATUALIZAR PLATAFORMA
:: ============================================================================
:ACT_UPDATE
cls
echo.
echo --- [5] ATUALIZAR PLATAFORMA ---
echo.
if exist "..\..\.git" (
    echo [*] Repositorio Git detectado.
    set /p "PULL_GIT=Deseja buscar atualizacoes via git pull? [S/n]: "
    if "!PULL_GIT!"=="" set "PULL_GIT=S"
    if /i "!PULL_GIT!"=="S" (
        git pull origin main || git pull
    )
)

echo.
echo [*] Reconstruindo conteineres sem afetar dados do PostgreSQL...
%COMPOSE_CMD% up -d --build
echo.
echo [OK] Plataforma atualizada com sucesso!
pause
goto MENU_LOOP

:: ============================================================================
:: 6. SUBMENU BANCO DE DADOS
:: ============================================================================
:ACT_DB_MENU
cls
echo.
echo     ┌────────────────────────────────────────────────────────────┐
echo     │  GERENCIAMENTO DE BANCO DE DADOS (PostgreSQL)              │
echo     ├────────────────────────────────────────────────────────────┤
echo     │  [1] Criar Backup Completo (pg_dump)                       │
echo     │  [2] Restaurar Banco a partir de Backup (.sql)             │
echo     │  [3] Listar Backups Existentes                             │
echo     │  [4] Verificar Contagem de Registros nas Tabelas           │
echo     │  [5] Resetar Banco (Limpar e recriar estrutura)            │
echo     ├────────────────────────────────────────────────────────────┤
echo     │  [0] Voltar ao Menu Principal                              │
echo     └────────────────────────────────────────────────────────────┘
echo.
set /p "DB_OPT=    >> Escolha uma opcao [0-5]: "

if "%DB_OPT%"=="1" goto DB_BACKUP
if "%DB_OPT%"=="2" goto DB_RESTORE
if "%DB_OPT%"=="3" goto DB_LIST
if "%DB_OPT%"=="4" goto DB_INTEGRITY
if "%DB_OPT%"=="5" goto DB_RESET
if "%DB_OPT%"=="0" goto MENU_LOOP
goto ACT_DB_MENU

:DB_BACKUP
echo.
echo [*] Criando backup do PostgreSQL...
for /f "tokens=*" %%t in ('powershell -NoProfile -Command "Get-Date -Format 'yyyyMMdd_HHmmss'"') do set "TS=%%t"
set "BKP_FILE=%BACKUP_DIR%\backup_beautyflow_%TS%.sql"

docker ps --format "{{.Names}}" | findstr /i "beautyflow-postgres" >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERRO] O conteiner 'beautyflow-postgres' nao esta rodando.
    pause
    goto ACT_DB_MENU
)

docker exec beautyflow-postgres pg_dump -U postgres -d beautyflow > "%BKP_FILE%"
if %errorlevel% equ 0 (
    echo [OK] Backup criado com sucesso em: %BKP_FILE%
) else (
    echo [ERRO] Falha ao gerar backup.
    if exist "%BKP_FILE%" del "%BKP_FILE%"
)
pause
goto ACT_DB_MENU

:DB_RESTORE
echo.
echo [*] Restaurar Banco de Dados...
echo Arquivos disponiveis em %BACKUP_DIR%:
dir /b "%BACKUP_DIR%\*.sql" 2>nul
echo.
set /p "R_FILE=Digite o nome do arquivo .sql (ou caminho completo): "
if not exist "%R_FILE%" (
    if exist "%BACKUP_DIR%\%R_FILE%" (
        set "R_FILE=%BACKUP_DIR%\%R_FILE%"
    ) else (
        echo [ERRO] Arquivo nao encontrado.
        pause
        goto ACT_DB_MENU
    )
)

echo [ATENCAO] Esta acao ira sobrescrever os dados atuais do banco 'beautyflow'!
set /p "CONF_R=Deseja prosseguir? [s/N]: "
if /i not "%CONF_R%"=="S" (
    echo Operacao cancelada.
    pause
    goto ACT_DB_MENU
)

echo Importando %R_FILE%...
type "%R_FILE%" | docker exec -i beautyflow-postgres psql -U postgres -d beautyflow
if %errorlevel% equ 0 (
    echo [OK] Banco de dados restaurado com sucesso!
) else (
    echo [ERRO] Falha na importacao do script SQL.
)
pause
goto ACT_DB_MENU

:DB_LIST
echo.
echo [*] Backups Armazenados:
dir "%BACKUP_DIR%\*.sql"
pause
goto ACT_DB_MENU

:DB_INTEGRITY
echo.
echo [*] Contagem de Registros:
docker exec beautyflow-postgres psql -U postgres -d beautyflow -c "SELECT 'Clientes' AS entidade, count(*) AS total FROM clients UNION ALL SELECT 'Agendamentos', count(*) FROM appointments UNION ALL SELECT 'Servicos', count(*) FROM services UNION ALL SELECT 'Transacoes', count(*) FROM transactions UNION ALL SELECT 'Horarios Cadastrados', count(*) FROM business_hours UNION ALL SELECT 'Usuarios Admin', count(*) FROM users;"
pause
goto ACT_DB_MENU

:DB_RESET
echo.
echo [ALERTA DE SEGURANCA] ZERAR E RECRIAR BANCO DE DADOS
echo Esta operacao apagara todos os dados atuais e reinicializara o catalogo padrao.
set /p "CONF_DEL=Para confirmar, digite exatamente 'RESET': "
if not "%CONF_DEL%"=="RESET" (
    echo Operacao cancelada.
    pause
    goto ACT_DB_MENU
)
echo [*] Resetando banco de dados...
docker exec beautyflow-postgres psql -U postgres -c "DROP DATABASE IF EXISTS beautyflow;"
docker exec beautyflow-postgres psql -U postgres -c "CREATE DATABASE beautyflow;"
type "%CRM_DIR%\backend\db\schema.sql" | docker exec -i beautyflow-postgres psql -U postgres -d beautyflow
%COMPOSE_CMD% restart crm-backend
echo [OK] Banco de dados reinicializado com estrutura e sementes padrao.
pause
goto ACT_DB_MENU

:: ============================================================================
:: 7. CONFIGURACAO DE REDE
:: ============================================================================
:ACT_NETWORK
cls
echo.
echo --- [7] CONFIGURACAO DE REDE ^& IP ---
echo.
set "LOCAL_IP=localhost"
for /f "tokens=*" %%i in ('powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 ^| Where-Object { $_.InterfaceAlias -notlike '*Loopback*' -and $_.IPAddress -notlike '169.254*' } ^| Select-Object -First 1).IPAddress" 2^>nul') do (
    if not "%%i"=="" set "LOCAL_IP=%%i"
)

echo IP detectado na rede local: !LOCAL_IP!
set /p "NEW_IP=Digite o novo endereco IP ou Dominio [!LOCAL_IP!]: "
if "!NEW_IP!"=="" set "NEW_IP=!LOCAL_IP!"

(
  echo VITE_API_URL=http://!NEW_IP!:3001/api
) > "%AGENDA_DIR%\.env"

(
  echo VITE_API_URL=http://!NEW_IP!:3001/api
) > ".env"

echo.
echo [OK] Endereco atualizado para http://!NEW_IP!:3001/api
set /p "REBLD=Deseja reconstruir o portal de agendamento agora? [S/n]: "
if "!REBLD!"=="" set "REBLD=S"
if /i "!REBLD!"=="S" (
    %COMPOSE_CMD% up -d --build agendamento-app
    echo [OK] Portal de agendamento recompilado com novo endereco!
)
pause
goto MENU_LOOP

:: ============================================================================
:: 8. LOGS EM TEMPO REAL
:: ============================================================================
:ACT_LOGS
cls
echo.
echo --- [8] LOGS EM TEMPO REAL ---
echo   [1] Todos os servicos
echo   [2] CRM Backend
echo   [3] Portal Agendamento
echo   [4] PostgreSQL
echo   [0] Voltar
echo.
set /p "L_OPT=Escolha os logs para acompanhar [0-4]: "
if "%L_OPT%"=="1" %COMPOSE_CMD% logs -f
if "%L_OPT%"=="2" %COMPOSE_CMD% logs -f crm-backend
if "%L_OPT%"=="3" %COMPOSE_CMD% logs -f agendamento-app
if "%L_OPT%"=="4" %COMPOSE_CMD% logs -f postgres
goto MENU_LOOP

:: ============================================================================
:: 9. REDEFINIR SENHA ADMIN
:: ============================================================================
:ACT_RESETPW
cls
echo.
echo --- [9] REDEFINIR SENHA DO ADMINISTRADOR ---
echo.
docker ps --format "{{.Names}}" | findstr /i "beautyflow-crm" >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERRO] O conteiner 'beautyflow-crm' precisa estar rodando.
    pause
    goto MENU_LOOP
)

set /p "NEW_PASS=Digite a nova senha para o admin [padrao: admin]: "
if "!NEW_PASS!"=="" set "NEW_PASS=admin"

docker exec -i beautyflow-crm python -c "from werkzeug.security import generate_password_hash; from db.connection import get_pool; pw_hash = generate_password_hash('!NEW_PASS!'); pool = get_pool(); conn = pool.getconn(); cur = conn.cursor(); cur.execute('UPDATE users SET password_hash = %%s WHERE email = %%s', (pw_hash, 'admin')); conn.commit(); pool.putconn(conn); print('[OK] Senha do admin atualizada.')"
echo.
echo [OK] Senha alterada com sucesso!
pause
goto MENU_LOOP

:: ============================================================================
:: 10. DESINSTALAR / LIMPAR
:: ============================================================================
:ACT_UNINSTALL
cls
echo.
echo --- [10] DESINSTALAR E LIMPAR AMBIENTE ---
echo.
echo [ALERTA] Esta operacao ira excluir os conteineres e TODOS os dados do PostgreSQL.
set /p "CONF_UN=Para confirmar, digite exatamente 'EXCLUIR': "
if not "%CONF_UN%"=="EXCLUIR" (
    echo Acao cancelada.
    pause
    goto MENU_LOOP
)
%COMPOSE_CMD% down -v --remove-orphans
echo.
echo [OK] Plataforma e volumes de dados removidos com sucesso.
pause
goto MENU_LOOP

:ACT_EXIT
cls
echo.
echo BeautyFlow Platform encerrado.
echo.
exit /b 0
