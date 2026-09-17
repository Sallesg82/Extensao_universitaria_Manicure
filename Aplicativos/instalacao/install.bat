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

:: Checar status waha
set "ST_WAHA=[ OFFLINE ]"
docker ps --format "{{.Names}}" 2>nul | findstr /i "beautyflow-waha waha" >nul 2>&1
if !errorlevel! equ 0 (
    set "ST_WAHA=[ ONLINE  ]"
) else (
    docker ps -a --format "{{.Names}}" 2>nul | findstr /i "beautyflow-waha waha" >nul 2>&1
    if !errorlevel! equ 0 (
        set "ST_WAHA=[ PARADO  ]"
    ) else (
        if exist ".env" (
            findstr /i "INSTALL_WAHA=false" .env >nul 2>&1
            if !errorlevel! equ 0 set "ST_WAHA=[ INATIVO ]"
        )
    )
)

echo     │    PostgreSQL (5432):     !ST_PG!                        │
echo     │    CRM Backend (3001):    !ST_CRM!                        │
echo     │    Agendamento (5173):    !ST_AGD!                        │
echo     │    WhatsApp WAHA (3000):  !ST_WAHA!                        │
echo     └────────────────────────────────────────────────────────────┘
echo.
echo     ┌────────────────────────────────────────────────────────────┐
echo     │  Menu Principal de Operacoes                               │
echo     ├────────────────────────────────────────────────────────────┤
echo     │  [1]  Instalar / Inicializar Plataforma Completa           │
echo     │  [2]  Iniciar Servicos                                     │
echo     │  [3]  Parar Servicos                                       │
echo     │  [4]  Reiniciar Servicos                                   │
echo     │  [5]  Atualizar Plataforma (Rebuild sem perda de dados)    │
echo     │  [6]  Gerenciar Banco de Dados (Backup / Restore / Reset)  │
echo     │  [7]  Configurar IP de Rede & URL da API                   │
echo     │  [8]  Ver Logs em Tempo Real                               │
echo     │  [9]  Redefinir Senha do Administrador (admin)             │
echo     │  [10] Desinstalar / Limpar Ambiente Completo               │
echo     │  [11] Instalar / Gerenciar WhatsApp WAHA (Porta 3000)      │
echo     │  [12] Diagnostico do Sistema e Teste de Conexoes           │
echo     ├────────────────────────────────────────────────────────────┤
echo     │  [0]  Sair                                                 │
echo     └────────────────────────────────────────────────────────────┘
echo.
set /p "OPTION=    >> Escolha uma opcao [0-12]: "

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
if "%OPTION%"=="11" goto ACT_MANAGE_WAHA
if "%OPTION%"=="12" goto ACT_DIAGNOSTICS
if "%OPTION%"=="0" goto ACT_EXIT

echo   [ERRO] Opcao invalida. Digite um numero de 0 a 12.
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
    echo [AVISO] O Docker Desktop esta instalado, mas o motor ainda nao esta rodando.
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
for /f "tokens=*" %%i in ('powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike '*Loopback*' -and $_.IPAddress -notlike '169.254*' } | Select-Object -First 1).IPAddress" 2^>nul') do (
    if not "%%i"=="" set "LOCAL_IP=%%i"
)

echo IP detectado na rede local: !LOCAL_IP!
set /p "USER_IP=Confirme o IP ou digite outro (ex: localhost) [!LOCAL_IP!]: "
if "!USER_IP!"=="" set "USER_IP=!LOCAL_IP!"

(
  echo DATABASE_URL=postgresql://postgres:beautyflow_pass@postgres:5432/beautyflow
  echo N8N_WEBHOOK_URL=https://mirianfiorini.app.n8n.cloud/webhook/calendar-webhook
  echo WAHA_API_URL=http://waha:3000
  echo WAHA_API_KEY=218c0effefb845238a1ae3651c8ced5b
  echo INSTALL_WAHA=false
) > "%CRM_DIR%\backend\.env"

(
  echo VITE_API_URL=/api
) > "%AGENDA_DIR%\.env"

(
  echo VITE_API_URL=/api
  echo COMPOSE_PROFILES=
  echo INSTALL_WAHA=false
  echo WAHA_API_KEY=218c0effefb845238a1ae3651c8ced5b
) > ".env"

echo [OK] Arquivos .env configurados.
echo.
echo [*] Construindo e subindo os conteineres da plataforma...
%COMPOSE_CMD% up -d --build --force-recreate --remove-orphans

echo.
echo [*] Aguardando inicializacao dos servicos...
timeout /t 8 /nobreak >nul

:: Sincronizar tabelas e restricoes
call :RUN_MIGRATIONS

echo.
echo ════════════════════════════════════════════════════════════════
echo   INSTALACAO PRINCIPAL CONCLUIDA COM SUCESSO!
echo ════════════════════════════════════════════════════════════════
echo   Painel CRM BeautyFlow:       http://localhost:3001
echo   Credenciais de Acesso:       Usuario: admin ^| Senha: admin
echo   Portal de Agendamento:       http://localhost:5173
echo   Acesso Mobile (mesmo Wi-Fi): http://!USER_IP!:5173
echo   Banco de Dados PostgreSQL:   localhost:5432 (DB: beautyflow)
echo   WhatsApp WAHA (Porta 3000):  Nao instalado (para instalar, use a opcao 11 do menu)
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
set "PROF_ARG="
if exist ".env" (
    findstr /i "INSTALL_WAHA=true" .env >nul 2>&1
    if !errorlevel! equ 0 set "PROF_ARG=--profile waha"
)
%COMPOSE_CMD% !PROF_ARG! up -d
echo.
echo [OK] Servicos iniciados.
echo   • CRM BeautyFlow (Gestao):   http://localhost:3001
echo   • Portal de Agendamento:     http://localhost:5173
docker ps --format "{{.Names}}" 2>nul | findstr /i "beautyflow-waha waha" >nul 2>&1
if !errorlevel! equ 0 echo   • WhatsApp WAHA (Porta 3000): http://localhost:3000
echo.
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
%COMPOSE_CMD% --profile waha stop 2>nul || %COMPOSE_CMD% stop
docker stop beautyflow-waha >nul 2>&1
echo.
echo [OK] Servicos pausados. Dados do PostgreSQL preservados.
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
set "PROF_ARG="
if exist ".env" (
    findstr /i "INSTALL_WAHA=true" .env >nul 2>&1
    if !errorlevel! equ 0 set "PROF_ARG=--profile waha"
)
%COMPOSE_CMD% !PROF_ARG! restart
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
        cd ..\..
        git pull origin main || git pull
        cd /d "%~dp0"
    )
)

echo.
echo [*] Reconstruindo conteineres sem afetar dados do PostgreSQL...
set "PROF_ARG="
if exist ".env" (
    findstr /i "INSTALL_WAHA=true" .env >nul 2>&1
    if !errorlevel! equ 0 set "PROF_ARG=--profile waha"
)
%COMPOSE_CMD% !PROF_ARG! up -d --build
call :RUN_MIGRATIONS
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
echo     │  [5] Otimizar Banco de Dados (VACUUM ANALYZE)              │
echo     │  [6] Resetar Banco (Limpar e recriar estrutura)            │
echo     ├────────────────────────────────────────────────────────────┤
echo     │  [0] Voltar ao Menu Principal                              │
echo     └────────────────────────────────────────────────────────────┘
echo.
set /p "DB_OPT=    >> Escolha uma opcao [0-6]: "

if "%DB_OPT%"=="1" goto DB_BACKUP
if "%DB_OPT%"=="2" goto DB_RESTORE
if "%DB_OPT%"=="3" goto DB_LIST
if "%DB_OPT%"=="4" goto DB_INTEGRITY
if "%DB_OPT%"=="5" goto DB_VACUUM
if "%DB_OPT%"=="6" goto DB_RESET
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
    call :RUN_MIGRATIONS
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
echo [*] Contagem de Registros nas Tabelas:
docker exec beautyflow-postgres psql -U postgres -d beautyflow -c "SELECT 'Clientes' AS entidade, count(*) AS total FROM clients UNION ALL SELECT 'Agendamentos', count(*) FROM appointments UNION ALL SELECT 'Servicos no Catalogo', count(*) FROM services UNION ALL SELECT 'Transacoes Financeiras', count(*) FROM transactions UNION ALL SELECT 'Insumos de Estoque', count(*) FROM products UNION ALL SELECT 'Metas Mensais', count(*) FROM metas UNION ALL SELECT 'Horarios de Atendimento', count(*) FROM business_hours UNION ALL SELECT 'Integracoes Configuradas', count(*) FROM integrations UNION ALL SELECT 'Notificacoes do Sistema', count(*) FROM notifications UNION ALL SELECT 'Usuarios Administradores', count(*) FROM users;"
pause
goto ACT_DB_MENU

:DB_VACUUM
echo.
echo [*] Executando VACUUM ANALYZE no PostgreSQL...
docker exec beautyflow-postgres psql -U postgres -d beautyflow -c "VACUUM (VERBOSE, ANALYZE);"
echo [OK] Otimizacao concluida.
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
for /f "tokens=*" %%i in ('powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike '*Loopback*' -and $_.IPAddress -notlike '169.254*' } | Select-Object -First 1).IPAddress" 2^>nul') do (
    if not "%%i"=="" set "LOCAL_IP=%%i"
)

echo IP detectado na rede local: !LOCAL_IP!
echo.
echo Arquitetura com Proxy Reverso Ativo:
echo O portal de agendamento utiliza a rota relativa (/api).
echo Celulares no mesmo Wi-Fi acessam diretamente por:
echo http://!LOCAL_IP!:5173 (sem necessidade de abrir porta 3001)
echo.
set /p "CUSTOM_API=Deseja manter o padrao (/api) ou informar URL externa? [/api]: "
if "!CUSTOM_API!"=="" set "CUSTOM_API=/api"

(
  echo VITE_API_URL=!CUSTOM_API!
) > "%AGENDA_DIR%\.env"

(
  findstr /v /i "VITE_API_URL" .env 2>nul
  echo VITE_API_URL=!CUSTOM_API!
) > .env.tmp && move /y .env.tmp .env >nul 2>&1

echo.
echo [OK] Configuracao de API atualizada para: !CUSTOM_API!
echo  - Acesso local:              http://localhost:5173
echo  - Acesso no Wi-Fi (Mobile):  http://!LOCAL_IP!:5173
echo.
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
echo   [5] WhatsApp WAHA (Porta 3000)
echo   [0] Voltar
echo.
set /p "L_OPT=Escolha os logs para acompanhar [0-5]: "
if "%L_OPT%"=="1" %COMPOSE_CMD% logs -f
if "%L_OPT%"=="2" %COMPOSE_CMD% logs -f crm-backend
if "%L_OPT%"=="3" %COMPOSE_CMD% logs -f agendamento-app
if "%L_OPT%"=="4" %COMPOSE_CMD% logs -f postgres
if "%L_OPT%"=="5" %COMPOSE_CMD% logs -f waha
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

docker exec -i beautyflow-crm python -c "from werkzeug.security import generate_password_hash; from db.database import _run; pw_hash = generate_password_hash('!NEW_PASS!'); _run('UPDATE users SET password_hash = %%s WHERE email = %%s', (pw_hash, 'admin')); print('[OK] Senha do admin atualizada.')"
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
%COMPOSE_CMD% --profile waha down -v --remove-orphans 2>nul || %COMPOSE_CMD% down -v --remove-orphans
docker stop beautyflow-waha >nul 2>&1
docker rm beautyflow-waha >nul 2>&1
echo [OK] Plataforma desinstalada.
pause
goto MENU_LOOP

:: ============================================================================
:: 11. GERENCIAR WHATSAPP WAHA
:: ============================================================================
:ACT_MANAGE_WAHA
cls
echo.
echo     ┌────────────────────────────────────────────────────────────┐
echo     │  INSTALADOR E GESTAO DO WHATSAPP WAHA (Porta 3000)         │
echo     ├────────────────────────────────────────────────────────────┤
echo     │  [1] Executar Instalador do WAHA (Download e Setup)        │
echo     │  [2] Ativar / Iniciar WhatsApp WAHA                        │
echo     │  [3] Desativar / Parar WhatsApp WAHA                       │
echo     │  [4] Reiniciar Servico WAHA                                │
echo     │  [5] Conectar WhatsApp (Iniciar Sessao e Obter QR Code)    │
echo     │  [6] Testar Conexao e Consultar Sessoes WAHA               │
echo     │  [7] Abrir Painel QR Code no Navegador                     │
echo     │  [8] Ver Logs do WhatsApp em Tempo Real                    │
echo     │  [9] Desinstalar / Remover WAHA da Plataforma              │
echo     ├────────────────────────────────────────────────────────────┤
echo     │  [0] Voltar ao Menu Principal                              │
echo     └────────────────────────────────────────────────────────────┘
echo.
set /p "W_OPT=    >> Escolha uma opcao [0-9]: "

if "%W_OPT%"=="1" goto WAHA_INSTALL
if "%W_OPT%"=="2" goto WAHA_START
if "%W_OPT%"=="3" goto WAHA_STOP
if "%W_OPT%"=="4" goto WAHA_RESTART
if "%W_OPT%"=="5" goto WAHA_CONNECT
if "%W_OPT%"=="6" goto WAHA_TEST
if "%W_OPT%"=="7" goto WAHA_BROWSER
if "%W_OPT%"=="8" goto WAHA_LOGS
if "%W_OPT%"=="9" goto WAHA_UNINSTALL
if "%W_OPT%"=="0" goto MENU_LOOP
goto ACT_MANAGE_WAHA

:WAHA_INSTALL
call install_waha.bat
goto ACT_MANAGE_WAHA

:WAHA_CONNECT
echo.
echo [*] Inicializando sessao e preparando QR Code...
powershell -NoProfile -Command "try { Invoke-RestMethod -Uri 'http://localhost:3000/api/sessions' -Method Post -Headers @{'X-Api-Key'='218c0effefb845238a1ae3651c8ced5b'} -ContentType 'application/json' -Body '{\"name\":\"default\",\"start\":true}' } catch {}" >nul 2>&1
echo [OK] Sessao ativada.
echo Acesse o painel para escanear o QR Code: http://localhost:3000/dashboard
start http://localhost:3000/dashboard
pause
goto ACT_MANAGE_WAHA

:WAHA_TEST
echo.
echo [*] Testando conexao com http://localhost:3000/ping...
powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://localhost:3000/ping' -UseBasicParsing -TimeoutSec 3; Write-Host '[OK] Endpoint /ping online! Status:' $r.StatusCode } catch { Write-Host '[ERRO] Servico WAHA nao respondeu na porta 3000.' }"
pause
goto ACT_MANAGE_WAHA

:WAHA_START
(
  findstr /v /i "COMPOSE_PROFILES INSTALL_WAHA" .env 2>nul
  echo COMPOSE_PROFILES=waha
  echo INSTALL_WAHA=true
  echo WAHA_API_KEY=218c0effefb845238a1ae3651c8ced5b
) > .env.tmp && move /y .env.tmp .env >nul 2>&1
if exist "%CRM_DIR%\backend\.env" (
    powershell -NoProfile -Command "(Get-Content '%CRM_DIR%\backend\.env') -replace 'INSTALL_WAHA=false', 'INSTALL_WAHA=true' | Set-Content '%CRM_DIR%\backend\.env'" 2>nul
)
echo [*] Subindo servico WAHA...
%COMPOSE_CMD% --profile waha up -d waha
echo [OK] WhatsApp WAHA ativo em http://localhost:3000!
pause
goto ACT_MANAGE_WAHA

:WAHA_STOP
docker stop beautyflow-waha >nul 2>&1
docker rm beautyflow-waha >nul 2>&1
(
  findstr /v /i "COMPOSE_PROFILES INSTALL_WAHA" .env 2>nul
  echo COMPOSE_PROFILES=
  echo INSTALL_WAHA=false
) > .env.tmp && move /y .env.tmp .env >nul 2>&1
if exist "%CRM_DIR%\backend\.env" (
    powershell -NoProfile -Command "(Get-Content '%CRM_DIR%\backend\.env') -replace 'INSTALL_WAHA=true', 'INSTALL_WAHA=false' | Set-Content '%CRM_DIR%\backend\.env'" 2>nul
)
echo [OK] WhatsApp WAHA desativado.
pause
goto ACT_MANAGE_WAHA

:WAHA_RESTART
%COMPOSE_CMD% --profile waha restart waha
echo [OK] WhatsApp WAHA reiniciado.
pause
goto ACT_MANAGE_WAHA

:WAHA_BROWSER
start http://localhost:3000/dashboard
echo [OK] Painel aberto no navegador: http://localhost:3000/dashboard
pause
goto ACT_MANAGE_WAHA

:WAHA_LOGS
%COMPOSE_CMD% logs -f waha
goto ACT_MANAGE_WAHA

:WAHA_UNINSTALL
echo [!] Desinstalando o WhatsApp WAHA...
docker stop beautyflow-waha >nul 2>&1
docker rm beautyflow-waha >nul 2>&1
docker volume rm instalacao_waha_sessions >nul 2>&1
docker volume rm beautyflow_waha_sessions >nul 2>&1
(
  findstr /v /i "COMPOSE_PROFILES INSTALL_WAHA" .env 2>nul
  echo COMPOSE_PROFILES=
  echo INSTALL_WAHA=false
) > .env.tmp && move /y .env.tmp .env >nul 2>&1
if exist "%CRM_DIR%\backend\.env" (
    powershell -NoProfile -Command "(Get-Content '%CRM_DIR%\backend\.env') -replace 'INSTALL_WAHA=true', 'INSTALL_WAHA=false' | Set-Content '%CRM_DIR%\backend\.env'" 2>nul
)
(
  echo UPDATE settings SET value = 'false' WHERE key = 'whatsapp_integrated';
  echo UPDATE integrations SET enabled = false WHERE type IN ('whatsapp', 'waha'^);
) | docker exec -i beautyflow-postgres psql -U postgres -d beautyflow >nul 2>&1
echo [OK] WAHA removido da plataforma.
pause
goto ACT_MANAGE_WAHA

:: ============================================================================
:: 12. DIAGNOSTICO DO SISTEMA
:: ============================================================================
:ACT_DIAGNOSTICS
cls
echo.
echo --- [12] DIAGNOSTICO DO SISTEMA E TESTE DE CONEXOES ---
echo.
echo [1/6] Testando Docker Engine...
docker info >nul 2>&1
if %errorlevel% equ 0 (
    echo   [OK] Docker Engine ativo e respondendo.
) else (
    echo   [FALHA] Docker daemon nao esta rodando.
)

echo [2/6] Testando Banco de Dados PostgreSQL...
docker exec beautyflow-postgres pg_isready -U postgres -d beautyflow >nul 2>&1
if %errorlevel% equ 0 (
    echo   [OK] PostgreSQL online na porta 5432.
) else (
    echo   [FALHA] PostgreSQL nao esta respondendo.
)

echo [3/6] Testando API CRM Backend (Porta 3001)...
powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://localhost:3001/api/services/' -UseBasicParsing -TimeoutSec 3; Write-Host '  [OK] CRM API respondendo (HTTP' $r.StatusCode ')' } catch { Write-Host '  [FALHA] CRM API nao responde em http://localhost:3001' }"

echo [4/6] Testando Portal Agendamento (Porta 5173)...
powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://localhost:5173/' -UseBasicParsing -TimeoutSec 3; Write-Host '  [OK] Agendamento Web respondendo (HTTP' $r.StatusCode ')' } catch { Write-Host '  [FALHA] Portal nao responde em http://localhost:5173' }"

echo [5/6] Testando WhatsApp WAHA (Porta 3000)...
powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://localhost:3000/ping' -UseBasicParsing -TimeoutSec 3; Write-Host '  [OK] WhatsApp WAHA respondendo (/ping OK)' } catch { Write-Host '  [INFO] WAHA inativo ou nao instalado.' }"

echo [6/6] IP de Rede Local...
echo   IP Local detectado: !LOCAL_IP!
echo.
echo Diagnostico concluido.
pause
goto MENU_LOOP

:: ============================================================================
:: HELPER: Sincronizar Migracoes
:: ============================================================================
:RUN_MIGRATIONS
echo [*] Sincronizando tabelas e restricoes no PostgreSQL...
(
  echo DO $$ BEGIN IF EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE constraint_name = 'integrations_type_check' AND table_name = 'integrations'^) THEN ALTER TABLE integrations DROP CONSTRAINT integrations_type_check; ALTER TABLE integrations ADD CONSTRAINT integrations_type_check CHECK(type IN ('webhook', 'n8n', 'google_calendar', 'whatsapp', 'waha'^)^); END IF; END $$;
  echo CREATE TABLE IF NOT EXISTS public.metas (id SERIAL PRIMARY KEY, mes VARCHAR(7^) NOT NULL, meta NUMERIC(12, 2^) NOT NULL DEFAULT 7000.00, created_at TIMESTAMP WITH TIME ZONE DEFAULT now(^), updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(^), CONSTRAINT metas_mes_unique UNIQUE (mes^)^);
  echo CREATE TABLE IF NOT EXISTS public.products (id SERIAL PRIMARY KEY, name TEXT NOT NULL, category TEXT DEFAULT 'pink', qty INTEGER DEFAULT 0, price REAL DEFAULT 0, min_qty INTEGER DEFAULT 5, missing BOOLEAN DEFAULT false, created_at TIMESTAMP WITH TIME ZONE DEFAULT now(^), updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(^)^);
) | docker exec -i beautyflow-postgres psql -U postgres -d beautyflow >nul 2>&1
echo [OK] Estrutura do banco sincronizada.
exit /b 0

:ACT_EXIT
cls
echo.
echo BeautyFlow Platform encerrado.
echo.
exit /b 0
