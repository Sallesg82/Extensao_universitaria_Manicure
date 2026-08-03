@echo off
chcp 65001 > NUL
setlocal enabledelayedexpansion

echo ==================================================================
echo         BeautyFlow CRM + Agendamento — Instalador Docker
echo ==================================================================
echo.

echo [1/4] Verificando Docker...
docker --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERRO] Docker nao instalado ou nao esta rodando. Por favor, inicie o Docker Desktop.
    pause
    exit /b 1
)

echo [2/4] Gerando configuracoes .env...
(
  echo DATABASE_URL=postgresql://postgres:beautyflow_pass@postgres:5432/beautyflow
  echo N8N_WEBHOOK_URL=https://mirianfiorini.app.n8n.cloud/webhook/calendar-webhook
) > "..\CRM BeautyFlow\backend\.env"

(
  echo VITE_API_URL=http://localhost:3001/api
) > "..\agendamento Vinicius\.env"

(
  echo VITE_API_URL=http://localhost:3001/api
) > ".env"

echo [3/4] Subindo conteineres com Docker Compose...
docker compose up -d --build

echo.
echo ==================================================================
echo INSTALACAO CONCLUIDA COM SUCESSO!
echo ==================================================================
echo CRM BeautyFlow:        http://localhost:3001
echo Portal de Agendamento: http://localhost:5173
echo PostgreSQL DB:         localhost:5432 (beautyflow)
echo ==================================================================
pause
