@echo off
title BeautyFlow - Instalador Unificado Windows

chcp 65001 >nul

echo.
echo ╔══════════════════════════════════════════════╗
echo ║    BeautyFlow — Instalador Unificado Windows ║
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
    echo  AVISO: Algumas operacoes podem exigir
    echo  permissao de administrador (Docker, Python, Node).
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
