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

echo  Iniciando instalador grafico...
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0install_windows.ps1"

echo.
echo  Instalador finalizado. Pressione qualquer tecla para sair.
pause
