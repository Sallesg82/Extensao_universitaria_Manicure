@echo off
title BeautyFlow CRM - Instalador Windows

chcp 65001 >nul

echo.
echo ╔══════════════════════════════════════════════╗
echo ║   BeautyFlow CRM — Instalador para Windows  ║
echo ╚══════════════════════════════════════════════╝
echo.

REM Verificar se PowerShell esta disponivel
where powershell >nul 2>&1
if %errorlevel% neq 0 (
    echo ERRO: PowerShell nao encontrado.
    echo Este instalador requer o PowerShell 5.1+.
    pause
    exit /b 1
)

REM Verificar permissão de administrador
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  AVISO: Algumas funcionalidades (WSL, Docker) exigem
    echo  permissao de administrador.
    echo.
    echo  Recomenda-se executar como Administrador:
    echo    Clique com o botao direito ^> "Executar como administrador"
    echo.
    pause
)

echo.
echo  Iniciando instalador grafico...
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0install_windows.ps1"

if %errorlevel% neq 0 (
    echo.
    echo  Ocorreu um erro ao executar o instalador.
    echo  Tente executar como Administrador.
    pause
)
