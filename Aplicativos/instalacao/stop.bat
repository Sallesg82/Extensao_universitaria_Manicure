@echo off
chcp 65001 > NUL
setlocal enabledelayedexpansion

cd /d "%~dp0"

echo [*] Parando conteineres da plataforma BeautyFlow...

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

%COMPOSE_CMD% --profile waha stop 2>nul || %COMPOSE_CMD% stop
docker stop beautyflow-waha >nul 2>&1

echo.
echo ==================================================================
echo [OK] Todos os conteineres foram parados com sucesso.
echo      (Seus dados no PostgreSQL continuam preservados no volume)
echo ==================================================================
pause
