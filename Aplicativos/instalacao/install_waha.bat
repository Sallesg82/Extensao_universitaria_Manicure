@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

set "CRM_DIR=%SCRIPT_DIR%..\CRM BeautyFlow"

echo ==================================================================
echo   INSTALADOR DO WHATSAPP WAHA - BeautyFlow Platform
echo   WhatsApp HTTP API Engine + Dashboard (Porta 3000)
echo ==================================================================
echo.

set "COMPOSE_CMD="
docker compose version >nul 2>&1
if !errorlevel! equ 0 (
    set "COMPOSE_CMD=docker compose"
) else (
    docker-compose version >nul 2>&1
    if !errorlevel! equ 0 set "COMPOSE_CMD=docker-compose"
)

if "%COMPOSE_CMD%"=="" (
    echo [ERRO] Docker Compose nao foi encontrado.
    pause
    exit /b 1
)

echo [*] [1/5] Verificando Docker Engine...
docker info >nul 2>&1
if !errorlevel! neq 0 (
    echo [ERRO] O Docker nao esta em execucao. Inicie o Docker Desktop.
    pause
    exit /b 1
)
echo [OK] Docker em execucao.

echo.
echo [*] [2/5] Configuracoes de Seguranca do WAHA
set "DEFAULT_KEY=218c0effefb845238a1ae3651c8ced5b"
set "USER_KEY=%DEFAULT_KEY%"
set /p "USER_KEY=Chave de API do WAHA [%DEFAULT_KEY%]: "
if "%USER_KEY%"=="" set "USER_KEY=%DEFAULT_KEY%"

set "USER_SESS=default"
set /p "USER_SESS=Nome da Sessao do WhatsApp [default]: "
if "%USER_SESS%"=="" set "USER_SESS=default"

echo.
echo [*] [3/5] Gravando variaveis de ambiente (.env)...
(
  findstr /v /i "COMPOSE_PROFILES INSTALL_WAHA WAHA_API_KEY WAHA_SESSION" .env 2>nul
  echo COMPOSE_PROFILES=waha
  echo INSTALL_WAHA=true
  echo WAHA_API_KEY=%USER_KEY%
  echo WAHA_SESSION=%USER_SESS%
) > .env.tmp && move /y .env.tmp .env >nul 2>&1

if exist "%CRM_DIR%\backend" (
  (
    findstr /v /i "INSTALL_WAHA WAHA_API_KEY WAHA_API_URL WAHA_SESSION" "%CRM_DIR%\backend\.env" 2>nul
    echo INSTALL_WAHA=true
    echo WAHA_API_KEY=%USER_KEY%
    echo WAHA_API_URL=http://waha:3000
    echo WAHA_SESSION=%USER_SESS%
  ) > "%CRM_DIR%\backend\.env.tmp" && move /y "%CRM_DIR%\backend\.env.tmp" "%CRM_DIR%\backend\.env" >nul 2>&1
)

docker ps --format "{{.Names}}" 2>nul | findstr /i "beautyflow-postgres" >nul 2>&1
if !errorlevel! equ 0 (
  (
    echo INSERT INTO settings (key, value^) VALUES ('whatsapp_integrated', 'true'^), ('waha_api_key', '%USER_KEY%'^), ('waha_session_name', '%USER_SESS%'^), ('waha_api_url', 'http://waha:3000'^) ON CONFLICT (key^) DO UPDATE SET value = EXCLUDED.value;
    echo INSERT INTO integrations (name, type, enabled, config^) SELECT 'WhatsApp WAHA', 'whatsapp', true, '{\"session\":\"%USER_SESS%\",\"notify_on_create\":true,\"notify_on_reminder\":true}'::jsonb WHERE NOT EXISTS (SELECT 1 FROM integrations WHERE type IN ('whatsapp', 'waha'^)^);
    echo UPDATE integrations SET enabled = true WHERE type IN ('whatsapp', 'waha'^);
  ^) | docker exec -i beautyflow-postgres psql -U postgres -d beautyflow >nul 2>&1
)

echo.
echo [*] [4/5] Baixando e iniciando o servico WAHA...
%COMPOSE_CMD% --profile waha up -d waha

echo.
echo [*] [5/5] Aguardando inicializacao do WAHA...
set "WAHA_READY=0"
for /l %%i in (1,1,30) do (
    powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://localhost:3000/ping' -UseBasicParsing -TimeoutSec 1; if ($r.StatusCode -eq 200) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
    if !errorlevel! equ 0 (
        set "WAHA_READY=1"
        goto WAHA_READY_OK
    )
    timeout /t 1 /nobreak >nul
)

:WAHA_READY_OK
if "%WAHA_READY%"=="1" (
    echo [OK] WAHA online! Inicializando sessao '%USER_SESS%'...
    powershell -NoProfile -Command "try { Invoke-RestMethod -Uri 'http://localhost:3000/api/sessions' -Method Post -Headers @{'X-Api-Key'='%USER_KEY%'} -ContentType 'application/json' -Body '{\"name\":\"%USER_SESS%\",\"start\":true}' } catch {}" >nul 2>&1
    echo [*] Inicializando banco de dados dedicado de mensagens (whatsapp_chat.db)...
    python -c "import sys; sys.path.insert(0, '%CRM_DIR%\backend'); from db.whatsapp_chat_db import init_chat_db; init_chat_db()" >nul 2>&1
    powershell -NoProfile -Command "try { Invoke-RestMethod -Uri 'http://localhost:3000/api/sessions/%USER_SESS%' -Method Put -Headers @{'X-Api-Key'='%USER_KEY%'} -ContentType 'application/json' -Body '{\"config\":{\"webhooks\":[{\"url\":\"http://beautyflow-crm:3001/api/whatsapp/webhook\",\"events\":[\"message\",\"message.any\",\"message.ack\"]}]}}' } catch {}" >nul 2>&1
    echo.
    echo ==================================================================
    echo  [OK] WhatsApp WAHA instalado e configurado com sucesso!
    echo ==================================================================
    echo   • URL da API WAHA:       http://localhost:3000
    echo   • Painel / QR Code:      http://localhost:3000/dashboard
    echo   • Sessao Ativa:          %USER_SESS%
    echo   • Chave de API:          %USER_KEY%
    echo   • Gerenciador de Chat:   Ativo com Banco Dedicado (whatsapp_chat.db)
    echo ==================================================================
    echo.
    echo   Para conectar seu WhatsApp:
    echo   1. Abra o WhatsApp no celular: Configuracoes > Aparelhos Conectados.
    echo   2. Acesse http://localhost:3000/dashboard e escaneie o QR Code!
    echo.
    start http://localhost:3000/dashboard
) else (
    echo [AVISO] O servico WAHA esta inicializando.
    echo Acesse em instantes: http://localhost:3000/dashboard
)

echo.
pause
