@echo off
chcp 65001 > NUL
setlocal enabledelayedexpansion

cd /d "%~dp0"

echo [*] Iniciando plataforma BeautyFlow...

set "COMPOSE_CMD=docker compose"
docker compose version >nul 2>&1
if %errorlevel% neq 0 (
    where docker-compose >nul 2>&1
    if %errorlevel% equ 0 (
        set "COMPOSE_CMD=docker-compose"
    ) else (
        echo [ERRO] Docker Compose nao foi encontrado.
        pause
        exit /b 1
    )
)

set "PROF_ARG="
if exist ".env" (
    findstr /i "INSTALL_WAHA=true" .env >nul 2>&1
    if !errorlevel! equ 0 set "PROF_ARG=--profile waha"
)

%COMPOSE_CMD% !PROF_ARG! up -d

echo [*] Aguardando servicos inicializarem...
timeout /t 5 /nobreak >nul

echo.
echo ==================================================================
echo [OK] Plataforma BeautyFlow iniciada com sucesso!
echo ==================================================================
echo  • CRM BeautyFlow (Gestao):   http://localhost:3001
echo  • Portal de Agendamento:     http://localhost:5173
echo  • PostgreSQL DB:             localhost:5432
docker ps --format "{{.Names}}" 2>nul | findstr /i "beautyflow-waha waha" >nul 2>&1
if !errorlevel! equ 0 (
    echo  • WhatsApp WAHA (Porta 3000): http://localhost:3000
    echo  • Dashboard / QR Code:        http://localhost:3000/dashboard
)
echo ==================================================================
pause
