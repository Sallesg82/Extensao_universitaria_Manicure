@echo off
title BeautyFlow Agendamento - Instalador Windows

chcp 65001 >nul

echo.
echo ╔══════════════════════════════════════════════╗
echo ║ BeautyFlow Agendamento — Instalador Windows ║
echo ╚══════════════════════════════════════════════╝
echo.

where powershell >nul 2>&1
if %errorlevel% neq 0 (
    echo ERRO: PowerShell nao encontrado.
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  AVISO: Algumas operacoes (Docker, Node.js)
    echo  podem exigir permissao de administrador.
    echo.
    pause
)

echo.
echo  Iniciando instalador grafico...
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0install_windows.ps1"

if %errorlevel% neq 0 (
    echo.
    echo  Ocorreu um erro. Tente executar como Administrador.
    pause
)
