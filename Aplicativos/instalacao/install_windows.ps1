<#
   BeautyFlow - Instalador Unificado Windows (Terminal)
#>

$REPO_URL = "https://github.com/Sallesg82/Extensao_universitaria_Manicure.git"
$DIR     = Split-Path -Parent $MyInvocation.MyCommand.Path
$BASE    = Split-Path -Parent $DIR
$CRM_DIR = "$BASE\CRM-Mirian (protótipo)"
$APP_DIR = "$BASE\agendamento Vinicius"

$INSIDE_REPO = (git rev-parse --show-toplevel 2>$null | Split-Path -Leaf) -eq "Extensao_universitaria_Manicure"

function Banner {
  Write-Host ""
  Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
  Write-Host "║         BeautyFlow - Instalador Unificado    ║" -ForegroundColor Cyan
  Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
  Write-Host ""
}

function Ok  { Write-Host "  [OK] $($args[0])" -ForegroundColor Green }
function Aviso { Write-Host "  [!] $($args[0])" -ForegroundColor Yellow }
function Erro { Write-Host "  [ERRO] $($args[0])" -ForegroundColor Red }

function Confirmar($msg) {
  $r = Read-Host "$msg [s/N]"
  return ($r -eq "s" -or $r -eq "S")
}

function MenuOpcoes($titulo, $opcoes) {
  Write-Host "$titulo" -ForegroundColor White
  Write-Host ""
  foreach ($o in $opcoes) {
    Write-Host "  $($o[0])) $($o[1])" -ForegroundColor $o[2]
  }
  Write-Host ""
  $r = Read-Host "Escolha (padrao $($opcoes[0][0]))"
  if ([string]::IsNullOrWhiteSpace($r)) { $r = $opcoes[0][0] }
  return $r
}

# ══════════════════════════════════════════
#  Dependencias
# ══════════════════════════════════════════

function InstalarGit {
  if (Get-Command git -ErrorAction SilentlyContinue) { Ok "git encontrado"; return }
  Aviso "Git nao encontrado"
  if (Confirmar "Deseja baixar o instalador do Git?") {
    Start-Process "https://git-scm.com/download/win"
  }
  Erro "Instale o Git manualmente e tente novamente"
  exit 1
}

function InstalarPython {
    Ok "python $(python --version 2>&1)"
    return
  }
  Aviso "Python 3.10+ nao encontrado"
  if (Confirmar "Deseja baixar o instalador do Python? (marque 'Add Python to PATH')") {
    Start-Process "https://www.python.org/downloads/"
  }
  Erro "Instale Python 3.10+ e tente novamente"
  exit 1
}

function InstalarNode {
  if (Get-Command node -ErrorAction SilentlyContinue) {
    Ok "node $(node --version)"
    return
  }
  Aviso "Node.js nao encontrado"
  if (Confirmar "Deseja baixar o instalador do Node.js LTS?") {
    Start-Process "https://nodejs.org/"
  }
  Erro "Instale Node.js LTS e tente novamente"
  exit 1
}

# ══════════════════════════════════════════
#  Repositorio
# ══════════════════════════════════════════

function ClonarRepo {
  if ($INSIDE_REPO) { Ok "Repositorio ja esta clonado"; return }
  Write-Host ""
  Write-Host "── Clonando repositorio ──" -ForegroundColor White
  $target = "$env:TEMP\Extensao_universitaria_Manicure"
  if (Test-Path $target) { Remove-Item -Recurse -Force $target -ErrorAction SilentlyContinue }
  git clone $REPO_URL $target 2>&1 | Out-Null
  if (-not (Test-Path $target)) { Erro "Falha ao clonar repositorio"; exit 1 }
  Set-Variable -Name DIR -Value "$target\Aplicativos\instalacao" -Scope Script
  Set-Variable -Name BASE -Value "$target\Aplicativos" -Scope Script
  Set-Variable -Name CRM_DIR -Value "$BASE\CRM-Mirian (protótipo)" -Scope Script
  Set-Variable -Name APP_DIR -Value "$BASE\agendamento Vinicius" -Scope Script
  Set-Variable -Name INSIDE_REPO -Value $false -Scope Script
  Ok "Repositorio clonado"
}

function AtualizarRepo {
  Write-Host ""
  Write-Host "── Atualizando repositorio ──" -ForegroundColor White
  if ($INSIDE_REPO) {
    Push-Location $BASE
    git pull --ff-only 2>&1 | Out-Null
    Pop-Location
    Ok "Repositorio atualizado"
  } else {
    Ok "Repositorio clonado recentemente, ja esta atualizado"
  }
}

# ══════════════════════════════════════════
#  Instalacao Nativa
# ══════════════════════════════════════════

function ConfigurarSupabase {
  $envFile = "$CRM_DIR\backend\.env"
  if (Test-Path $envFile) {
    Ok "Supabase ja configurado (.env encontrado)"
    return
  }
  Write-Host ""
  Write-Host "── Configuracao do Supabase (banco de dados) ──" -ForegroundColor White
  Write-Host "  Precisa de uma conta em https://supabase.com" -ForegroundColor Yellow
  Write-Host "  Crie um projeto e copie as credenciais em" -ForegroundColor Yellow
  Write-Host "  Project Settings -> API" -ForegroundColor Yellow
  Write-Host ""
  $url      = Read-Host "  SUPABASE_URL (ex: https://xxxxx.supabase.co)"
  $anonKey  = Read-Host "  SUPABASE_ANON_KEY (anon public)"
  $svcKey   = Read-Host "  SUPABASE_KEY (service_role secret)"
  if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($anonKey) -or [string]::IsNullOrWhiteSpace($svcKey)) {
    Aviso "Credenciais vazias — pode editar manualmente em:"
    Aviso "  $envFile"
  }
  New-Item -ItemType Directory -Force -Path "$CRM_DIR\backend" -ErrorAction SilentlyContinue | Out-Null
  @"
SUPABASE_URL=$url
SUPABASE_ANON_KEY=$anonKey
SUPABASE_KEY=$svcKey
"@ | Set-Content -Path $envFile
  Ok ".env criado em $envFile"
  Aviso "Lembre-se de executar o script SQL em:"
  Aviso "  $CRM_DIR\backend\db\supabase_schema.sql"
  Aviso "  no SQL Editor do seu projeto Supabase"
}

function InstalarCrm {
  Write-Host ""
  Write-Host "── Instalando BeautyFlow CRM ──" -ForegroundColor White
  $venvDir = "$CRM_DIR\backend\.venv"
  InstalarPython
  if (-not (Test-Path $venvDir)) {
    python -m venv $venvDir 2>$null
    Ok "venv criado"
  }
  & "$venvDir\Scripts\pip" install --quiet --upgrade pip 2>$null
  & "$venvDir\Scripts\pip" install --quiet flask flask-cors supabase httpx 2>$null
  Ok "Dependencias Python instaladas"
  ConfigurarSupabase
}

function InstalarAgendamento {
  Write-Host ""
  Write-Host "── Instalando BeautyFlow Agendamento ──" -ForegroundColor White
  InstalarNode
  Push-Location $APP_DIR
  npm install 2>$null
  Pop-Location
  Ok "Dependencias npm instaladas"
}

# ══════════════════════════════════════════
#  Docker
# ══════════════════════════════════════════

function InstalarDocker {
  if (Get-Command docker -ErrorAction SilentlyContinue) {
    Ok "docker $(docker --version 2>&1)"
    return
  }
  Aviso "Docker nao encontrado"
  if (Confirmar "Deseja baixar o Docker Desktop?") {
    Start-Process "https://docs.docker.com/desktop/setup/install/windows-install/"
  }
  Erro "Instale o Docker Desktop e tente novamente"
  exit 1
}

function ModoDocker($selection) {
  InstalarDocker
  Push-Location $DIR
  docker compose down 2>$null
  if ($selection -eq "crm" -or $selection -eq "ambos") {
    Write-Host ""
    Write-Host "  Build CRM..." -ForegroundColor Yellow
    docker compose build crm 2>&1 | Out-Null
    Ok "CRM pronto"
  }
  if ($selection -eq "agenda" -or $selection -eq "ambos") {
    Write-Host ""
    Write-Host "  Build Agendamento..." -ForegroundColor Yellow
    docker compose build agenda 2>&1 | Out-Null
    Ok "Agendamento pronto"
  }
  docker compose up -d 2>&1 | Out-Null
  Pop-Location
  Ok "Containers rodando"
}

# ══════════════════════════════════════════
#  Iniciar Apps
# ══════════════════════════════════════════

function IniciarCrm {
  $venvDir = "$CRM_DIR\backend\.venv"
  $pythonExe = "$venvDir\Scripts\python.exe"
  if (-not (Test-Path $pythonExe)) { Aviso "CRM nao instalado (venv nao encontrado)"; return }
  Ok "Iniciando CRM (backend Python)..."
  try {
    $p = Start-Process -FilePath $pythonExe -ArgumentList "$CRM_DIR\backend\server.py" -WorkingDirectory "$CRM_DIR\backend" -NoNewWindow -PassThru
    Start-Sleep -Seconds 3
    if ($p.HasExited) {
      Aviso "CRM parece ter fechado. Verifique se ha erros acima."
    } else {
      Ok "CRM rodando (PID $($p.Id)) em http://localhost:3001"
    }
  } catch {
    Aviso "Falha ao iniciar CRM: $_"
    Aviso "Tente manualmente: cd '$CRM_DIR\backend' && .venv\Scripts\python server.py"
  }
}

function IniciarAgendamento {
  $nmDir = "$APP_DIR\node_modules"
  if (-not (Test-Path $nmDir)) { Aviso "Agendamento nao instalado (node_modules nao encontrado)"; return }
  Ok "Iniciando Agendamento (Vite)..."
  try {
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c cd /d $APP_DIR && npm run dev" -NoNewWindow -PassThru
    Start-Sleep -Seconds 3
    if ($p.HasExited) {
      Aviso "Agendamento parece ter fechado. Verifique se ha erros acima."
    } else {
      Ok "Agendamento rodando (PID $($p.Id)) em http://localhost:5173"
    }
  } catch {
    Aviso "Falha ao iniciar Agendamento: $_"
    Aviso "Tente manualmente: cd '$APP_DIR' && npm run dev"
  }
}

# ══════════════════════════════════════════
#  Gerenciar
# ══════════════════════════════════════════

function GerenciarInstalacao {
  while ($true) {
    $sub = MenuOpcoes "═══ Gerenciar Instalacao ═══" @(
      @("1", "Instalacao Nativa - Ambos (CRM + Agendamento)", "White"),
      @("2", "Instalacao Nativa - CRM", "White"),
      @("3", "Instalacao Nativa - Agendamento", "White"),
      @("4", "Instalacao Docker - Ambos", "Yellow"),
      @("5", "Voltar", "Gray")
    )
    switch ($sub) {
      "1" { GestorAtualizacao "nativo-ambos" }
      "2" { GestorAtualizacao "nativo-crm" }
      "3" { GestorAtualizacao "nativo-agenda" }
      "4" { GestorAtualizacao "docker" }
      "5" { break }
    }
  }
}

function GestorAtualizacao($target) {
  $nomeMap = @{ "nativo-ambos"="CRM + Agendamento (Nativo)"; "nativo-crm"="CRM (Nativo)"; "nativo-agenda"="Agendamento (Nativo)"; "docker"="Docker (Ambos)" }
  while ($true) {
    $acao = MenuOpcoes "Gerenciar: $($nomeMap[$target])" @(
      @("1", "Reinstalar (deletar tudo + instalar do zero)", "Red"),
      @("2", "Atualizar (git pull + atualizar dependencias)", "Green"),
      @("3", "Desinstalar (remover completamente)", "Red"),
      @("4", "Cancelar", "Gray")
    )
    switch ($acao) {
      "1" {
        if (-not (Confirmar "Tem certeza? Isso vai deletar tudo e reinstalar do zero. Continuar?")) { return }
        GestorReinstall $target
      }
      "2" {
        AtualizarRepo
        GestorUpdate $target
      }
      "3" {
        if (-not (Confirmar "Tem certeza? Isso vai remover completamente a instalacao. Continuar?")) { return }
        GestorUninstall $target
      }
      "4" { return }
    }
    Write-Host ""
    Write-Host "Operacao concluida!" -ForegroundColor Green
    pause
    break
  }
}

function GestorReinstall($target) {
  Write-Host ""
  Write-Host "── Reinstalando ──" -ForegroundColor White
  if ($target -eq "nativo-crm" -or $target -eq "nativo-ambos") {
    Write-Host "  Removendo CRM..." -ForegroundColor Yellow
    $venvDir = "$CRM_DIR\backend\.venv"
    if (Test-Path $venvDir) { Remove-Item -Recurse -Force $venvDir -ErrorAction SilentlyContinue }
    InstalarCrm
  }
  if ($target -eq "nativo-agenda" -or $target -eq "nativo-ambos") {
    Write-Host "  Removendo Agendamento..." -ForegroundColor Yellow
    $nmDir = "$APP_DIR\node_modules"
    if (Test-Path $nmDir) { Remove-Item -Recurse -Force $nmDir -ErrorAction SilentlyContinue }
    InstalarAgendamento
  }
  if ($target -eq "docker") {
    Write-Host "  Removendo containers..." -ForegroundColor Yellow
    Push-Location $DIR
    docker compose down 2>$null
    docker rmi -f instalacao-crm instalacao-agenda 2>$null
    Pop-Location
    ModoDocker "ambos"
  }
  Ok "Reinstalacao concluida"
}

function GestorUpdate($target) {
  Write-Host ""
  Write-Host "── Atualizando dependencias ──" -ForegroundColor White
  if ($target -eq "nativo-crm" -or $target -eq "nativo-ambos") {
    $venvDir = "$CRM_DIR\backend\.venv"
    if (Test-Path $venvDir) {
      & "$venvDir\Scripts\pip" install --quiet --upgrade pip flask flask-cors supabase httpx 2>$null
      Ok "CRM atualizado"
    } else {
      InstalarCrm
    }
  }
  if ($target -eq "nativo-agenda" -or $target -eq "nativo-ambos") {
    $nmDir = "$APP_DIR\node_modules"
    if (Test-Path $nmDir) {
      Push-Location $APP_DIR
      npm update 2>$null
      Pop-Location
      Ok "Agendamento atualizado"
    } else {
      InstalarAgendamento
    }
  }
  if ($target -eq "docker") {
    Push-Location $DIR
    docker compose down 2>$null
    docker compose build --no-cache 2>$null
    docker compose up -d 2>$null
    Pop-Location
    Ok "Containers atualizados e reiniciados"
  }
}

function GestorUninstall($target) {
  Write-Host ""
  Write-Host "── Desinstalando ──" -ForegroundColor White
  if ($target -eq "nativo-crm" -or $target -eq "nativo-ambos") {
    $venvDir = "$CRM_DIR\backend\.venv"
    Get-CimInstance Win32_Process -Filter "Name LIKE 'python%' AND CommandLine LIKE '%server.py%'" -ErrorAction SilentlyContinue |
      Invoke-CimMethod -MethodName Terminate -ErrorAction SilentlyContinue
    if (Test-Path $venvDir) { Remove-Item -Recurse -Force $venvDir -ErrorAction SilentlyContinue }
    Ok "CRM desinstalado"
  }
  if ($target -eq "nativo-agenda" -or $target -eq "nativo-ambos") {
    $nmDir = "$APP_DIR\node_modules"
    Get-CimInstance Win32_Process -Filter "Name LIKE 'node%' AND (CommandLine LIKE '%vite%' OR CommandLine LIKE '%npm%')" -ErrorAction SilentlyContinue |
      Invoke-CimMethod -MethodName Terminate -ErrorAction SilentlyContinue
    if (Test-Path $nmDir) { Remove-Item -Recurse -Force $nmDir -ErrorAction SilentlyContinue }
    Ok "Agendamento desinstalado"
  }
  if ($target -eq "docker") {
    Push-Location $DIR
    docker compose down 2>$null
    docker rmi -f instalacao-crm instalacao-agenda 2>$null
    Pop-Location
    Ok "Docker desinstalado"
  }
}

# ══════════════════════════════════════════
#  Menu Principal
# ══════════════════════════════════════════

function ShowMenu {
  Banner
  $escolha = MenuOpcoes "Escolha o que deseja fazer:" @(
    @("1", "Ambos (CRM + Agendamento) - RECOMENDADO", "Green"),
    @("2", "BeautyFlow CRM (gestao do salao)", "White"),
    @("3", "BeautyFlow Agendamento (painel do cliente)", "White"),
    @("4", "Docker - Ambos (container)", "Yellow"),
    @("5", "Gerenciar instalacao (reinstalar / atualizar)", "Cyan")
  )
  return $escolha
}

# ══════════════════════════════════════════
#  Instalacao
# ══════════════════════════════════════════

function Instalar($selection, $method) {
  ClonarRepo
  if ($method -eq "native") {
    InstalarGit
    if ($selection -eq "crm" -or $selection -eq "ambos") { InstalarCrm }
    if ($selection -eq "agenda" -or $selection -eq "ambos") { InstalarAgendamento }
  } else {
    InstalarGit
    ModoDocker $selection
  }
}

function MostrarFinal($selection) {
  Write-Host ""
  Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
  Write-Host "║  Instalacao concluida!                       ║" -ForegroundColor Cyan
  Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
  if ($selection -eq "crm" -or $selection -eq "ambos") {
    Write-Host "  CRM:        http://localhost:3001" -ForegroundColor Green
  }
  if ($selection -eq "agenda" -or $selection -eq "ambos") {
    Write-Host "  Agendamento: http://localhost:5173" -ForegroundColor Green
  }
  Write-Host ""
}

function PerguntarIniciar {
  param($selection)
  if (-not (Confirmar "Deseja iniciar os aplicativos agora?")) { return }
  if ($selection -eq "crm" -or $selection -eq "ambos") { IniciarCrm }
  if ($selection -eq "agenda" -or $selection -eq "ambos") { IniciarAgendamento }
  Write-Host ""
  Write-Host "  Para testar manualmente:" -ForegroundColor Cyan
  Write-Host "    CRM:        .venv\Scripts\python server.py" -ForegroundColor Gray
  Write-Host "    Agendamento: npm run dev" -ForegroundColor Gray
}

# ══════════════════════════════════════════
#  Main
# ══════════════════════════════════════════

$escolha = ShowMenu

switch ($escolha) {
  "1" {
    Instalar "ambos" "native"
    MostrarFinal "ambos"
    PerguntarIniciar "ambos"
  }
  "2" {
    Instalar "crm" "native"
    MostrarFinal "crm"
    PerguntarIniciar "crm"
  }
  "3" {
    Instalar "agenda" "native"
    MostrarFinal "agenda"
    PerguntarIniciar "agenda"
  }
  "4" {
    Instalar "ambos" "docker"
    MostrarFinal "ambos"
  }
  "5" {
    GerenciarInstalacao
  }
}

Write-Host ""
Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor Gray
try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch {}