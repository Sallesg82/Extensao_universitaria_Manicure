<#
   BeautyFlow - Instalador Unificado Windows
#>

$ErrorActionPreference = "Stop"
$startErr = $null
try {

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$REPO_URL = "https://github.com/Sallesg82/Extensao_universitaria_Manicure.git"
$REPO_DIR = "$env:TEMP\Extensao_universitaria_Manicure"
$BASE     = "$REPO_DIR\Aplicativos"
$DB_DIR   = "$BASE\DB"
$DB_PATH  = "$DB_DIR\beautyflow.db"
$CRM_DIR  = "$BASE\CRM-Mirian (protótipo)"
$APP_DIR  = "$BASE\agendamento Vinicius"
$INST_DIR = "$BASE\instalacao"

$form      = $null
$panelMain = $null

$fonts = @{
  title  = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
  header = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
  body   = New-Object System.Drawing.Font("Segoe UI", 11)
  small  = New-Object System.Drawing.Font("Segoe UI", 9)
  mono   = New-Object System.Drawing.Font("Consolas", 10)
}

$colors = @{
  bg      = "#0a1628"
  card    = "#14203a"
  primary = "#4a90d9"
  success = "#4e8f6a"
  warning = "#c9894a"
  white   = "#b8d4f0"
  sub     = "#8aaccb"
}

function HexColor($hex) {
  return [System.Drawing.Color]::FromArgb([int]("0x$($hex.Substring(1))"))
}

function Get-NextY {
  if ($panelMain.Controls.Count -eq 0) { return 10 }
  return ($panelMain.Controls | % { $_.Location.Y + $_.Size.Height } | Measure -Max | % { $_.Maximum + 10 })
}

# ════════════════════════════════════════════
#  TELA PRINCIPAL — Menu de escolha
# ════════════════════════════════════════════

function Show-Menu {
  $panelMain.Controls.Clear()

  $logo = New-Object System.Windows.Forms.Label
  $logo.Text = "BeautyFlow"
  $logo.Font = $fonts.title; $logo.ForeColor = HexColor $colors.primary
  $logo.Size = New-Object System.Drawing.Size(600, 45)
  $logo.Location = New-Object System.Drawing.Point(40, 20)
  $logo.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($logo)

  $sub = New-Object System.Windows.Forms.Label
  $sub.Text = "Instalador Unificado para Windows"
  $sub.Font = $fonts.small; $sub.ForeColor = HexColor $colors.sub
  $sub.Size = New-Object System.Drawing.Size(600, 22)
  $sub.Location = New-Object System.Drawing.Point(40, 65)
  $sub.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($sub)

  $infoLines = @(
    "Escolha qual(is) aplicativo(s) deseja instalar:",
    "O banco de dados SQLite sera criado automaticamente"
  )
  $y = 110
  foreach ($line in $infoLines) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $line; $l.Font = $fonts.body; $l.ForeColor = HexColor $colors.white
    $l.Size = New-Object System.Drawing.Size(560, 22)
    $l.Location = New-Object System.Drawing.Point(60, $y)
    $panelMain.Controls.Add($l); $y += 24
  }
  $y += 15

  $btnAmbos = New-Object System.Windows.Forms.Button
  $btnAmbos.Text = "  Instalar AMBOS (Recomendado)`n  CRM + Agendamento integrados"
  $btnAmbos.Font = $fonts.body; $btnAmbos.Size = New-Object System.Drawing.Size(500, 55)
  $btnAmbos.Location = New-Object System.Drawing.Point(80, $y)
  $btnAmbos.BackColor = HexColor $colors.success; $btnAmbos.ForeColor = "White"
  $btnAmbos.FlatStyle = "Flat"
  $btnAmbos.TextAlign = "MiddleLeft"
  $btnAmbos.Tag = "ambos"
  $btnAmbos.Add_Click({ Show-MethodMenu $this.Tag })
  $panelMain.Controls.Add($btnAmbos); $y += 65

  $btnCrm = New-Object System.Windows.Forms.Button
  $btnCrm.Text = "  BeautyFlow CRM`n  Gestao do salao (clientes, agenda, financeiro)"
  $btnCrm.Font = $fonts.body; $btnCrm.Size = New-Object System.Drawing.Size(500, 55)
  $btnCrm.Location = New-Object System.Drawing.Point(80, $y)
  $btnCrm.BackColor = HexColor $colors.card; $btnCrm.ForeColor = HexColor $colors.white
  $btnCrm.FlatStyle = "Flat"
  $btnCrm.FlatAppearance.BorderSize = 1; $btnCrm.FlatAppearance.BorderColor = HexColor $colors.primary
  $btnCrm.TextAlign = "MiddleLeft"
  $btnCrm.Tag = "crm"
  $btnCrm.Add_Click({ Show-MethodMenu $this.Tag })
  $panelMain.Controls.Add($btnCrm); $y += 65

  $btnAgenda = New-Object System.Windows.Forms.Button
  $btnAgenda.Text = "  BeautyFlow Agendamento`n  Painel do cliente (agendar servicos)"
  $btnAgenda.Font = $fonts.body; $btnAgenda.Size = New-Object System.Drawing.Size(500, 55)
  $btnAgenda.Location = New-Object System.Drawing.Point(80, $y)
  $btnAgenda.BackColor = HexColor $colors.card; $btnAgenda.ForeColor = HexColor $colors.white
  $btnAgenda.FlatStyle = "Flat"
  $btnAgenda.FlatAppearance.BorderSize = 1; $btnAgenda.FlatAppearance.BorderColor = HexColor $colors.sub
  $btnAgenda.TextAlign = "MiddleLeft"
  $btnAgenda.Tag = "agenda"
  $btnAgenda.Add_Click({ Show-MethodMenu $this.Tag })
  $panelMain.Controls.Add($btnAgenda); $y += 75

  $btnGerenciar = New-Object System.Windows.Forms.Button
  $btnGerenciar.Text = "  Gerenciar instalacao`n  Reinstalar ou atualizar aplicativos ja instalados"
  $btnGerenciar.Font = $fonts.body; $btnGerenciar.Size = New-Object System.Drawing.Size(500, 55)
  $btnGerenciar.Location = New-Object System.Drawing.Point(80, $y)
  $btnGerenciar.BackColor = HexColor $colors.card; $btnGerenciar.ForeColor = HexColor $colors.warning
  $btnGerenciar.FlatStyle = "Flat"
  $btnGerenciar.FlatAppearance.BorderSize = 1; $btnGerenciar.FlatAppearance.BorderColor = HexColor $colors.warning
  $btnGerenciar.TextAlign = "MiddleLeft"
  $btnGerenciar.Add_Click({ Show-ManageMenu })
  $panelMain.Controls.Add($btnGerenciar)
}

# ════════════════════════════════════════════
#  TELA DE GERENCIAR
# ════════════════════════════════════════════

function Show-ManageMenu {
  $panelMain.Controls.Clear()

  $title = New-Object System.Windows.Forms.Label
  $title.Text = "Gerenciar Instalacao"
  $title.Font = $fonts.header; $title.ForeColor = HexColor $colors.white
  $title.Size = New-Object System.Drawing.Size(600, 30)
  $title.Location = New-Object System.Drawing.Point(40, 20)
  $panelMain.Controls.Add($title)

  $sub = New-Object System.Windows.Forms.Label
  $sub.Text = "Escolha o que deseja gerenciar:"
  $sub.Font = $fonts.body; $sub.ForeColor = HexColor $colors.sub
  $sub.Size = New-Object System.Drawing.Size(560, 22)
  $sub.Location = New-Object System.Drawing.Point(60, 65)
  $panelMain.Controls.Add($sub)

  $y = 110
  $btnData = @(
    @("  Instalacao Nativa - Ambos (CRM + Agendamento)", "nativo-ambos", $colors.primary),
    @("  Instalacao Nativa - CRM", "nativo-crm", $colors.primary),
    @("  Instalacao Nativa - Agendamento", "nativo-agenda", $colors.primary),
    @("  Instalacao Docker - Ambos", "docker", $colors.warning)
  )
  foreach ($item in $btnData) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $item[0]
    $b.Font = $fonts.body; $b.Size = New-Object System.Drawing.Size(500, 45)
    $b.Location = New-Object System.Drawing.Point(80, $y)
    $b.BackColor = HexColor $colors.card; $b.ForeColor = HexColor $item[2]
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 1; $b.FlatAppearance.BorderColor = HexColor $item[2]
    $b.TextAlign = "MiddleLeft"
    $b.Tag = $item[1]
    $b.Add_Click({ Show-ManageAction $this.Tag })
    $panelMain.Controls.Add($b); $y += 55
  }

  $y += 10
  $btnBack = New-Object System.Windows.Forms.Button
  $btnBack.Text = "  Voltar"
  $btnBack.Font = $fonts.body; $btnBack.Size = New-Object System.Drawing.Size(200, 40)
  $btnBack.Location = New-Object System.Drawing.Point(80, $y)
  $btnBack.BackColor = HexColor $colors.card; $btnBack.ForeColor = HexColor $colors.sub
  $btnBack.FlatStyle = "Flat"
  $btnBack.Add_Click({ Show-Menu })
  $panelMain.Controls.Add($btnBack)
}

function Show-ManageAction($target) {
  $panelMain.Controls.Clear()

  $names = @{
    "nativo-ambos"  = "CRM + Agendamento (Nativo)"
    "nativo-crm"    = "CRM (Nativo)"
    "nativo-agenda" = "Agendamento (Nativo)"
    "docker"        = "Docker (Ambos)"
  }

  Add-Title "Gerenciar: $($names[$target])"
  Add-Spacer

  $l = New-Object System.Windows.Forms.Label
  $l.Text = "Escolha uma acao:"
  $l.Font = $fonts.body; $l.ForeColor = HexColor $colors.sub
  $l.Size = New-Object System.Drawing.Size(560, 22)
  $l.Location = New-Object System.Drawing.Point(60, 70)
  $panelMain.Controls.Add($l)

  $y = 110
  $actions = @(
    @("  Reinstalar (deletar tudo + instalar do zero)", "reinstall", "#c05050"),
    @("  Atualizar (git pull + atualizar dependencias)", "update", $colors.success),
    @("  Desinstalar (remover completamente)", "uninstall", "#c05050")
  )
  foreach ($item in $actions) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $item[0]
    $b.Font = $fonts.body; $b.Size = New-Object System.Drawing.Size(500, 50)
    $b.Location = New-Object System.Drawing.Point(80, $y)
    $b.BackColor = HexColor $colors.card; $b.ForeColor = HexColor $item[2]
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 1; $b.FlatAppearance.BorderColor = HexColor $item[2]
    $b.TextAlign = "MiddleLeft"
    $b.Tag = @($target, $item[1])
    $b.Add_Click({ $tag = $this.Tag; Start-Manage $tag[0] $tag[1] })
    $panelMain.Controls.Add($b); $y += 60
  }

  $btnCancel = New-Object System.Windows.Forms.Button
  $btnCancel.Text = "  Cancelar"
  $btnCancel.Font = $fonts.body; $btnCancel.Size = New-Object System.Drawing.Size(200, 40)
  $btnCancel.Location = New-Object System.Drawing.Point(80, $y)
  $btnCancel.BackColor = HexColor $colors.card; $btnCancel.ForeColor = HexColor $colors.sub
  $btnCancel.FlatStyle = "Flat"
  $btnCancel.Add_Click({ Show-ManageMenu })
  $panelMain.Controls.Add($btnCancel)
}

function Start-Manage($target, $action) {
  $panelMain.Controls.Clear()
  Add-Title "Executando..."
  Add-Spacer

  $stepGit  = Add-Step "Atualizando repositorio..."
  $stepAct  = Add-Step "Executando acao..."
  $stepFin  = Add-Step "Finalizando..."
  Add-Spacer

  if ($action -eq "reinstall") {
    $msg = "Tem certeza? Isso vai deletar tudo e reinstalar do zero.`n`nContinuar?"
    $resp = [System.Windows.Forms.MessageBox]::Show($msg, "Confirmar reinstalacao", "YesNo", "Warning")
    if ($resp -ne "Yes") { Show-ManageMenu; return }
  }
  if ($action -eq "uninstall") {
    $msg = "Tem certeza? Isso vai remover completamente a instalacao.`n`nContinuar?"
    $resp = [System.Windows.Forms.MessageBox]::Show($msg, "Confirmar desinstalacao", "YesNo", "Warning")
    if ($resp -ne "Yes") { Show-ManageMenu; return }
  }

  if ($action -ne "uninstall") {
    $stepGit.Set("Atualizando repositorio...", $colors.warning)
    $form.Refresh()
    if (Test-Path "$REPO_DIR\.git") {
      Push-Location $REPO_DIR
      git pull --ff-only 2>&1 | Out-Null
      Pop-Location
    }
    $stepGit.Set("OK repositorio atualizado", $colors.success)
    $form.Refresh()
  }

  if ($target -eq "docker") {
    if ($action -eq "reinstall") {
      $stepAct.Set("Removendo containers e imagens...", $colors.warning)
      $form.Refresh()
      Push-Location $INST_DIR
      docker compose down 2>&1 | Out-Null
      docker rmi -f instalacao-crm instalacao-agenda 2>&1 | Out-Null
      Pop-Location
      $stepAct.Set("OK limpo", $colors.success)
      $form.Refresh()
      Start-Install "ambos" "docker"
      return
    } elseif ($action -eq "uninstall") {
      $stepAct.Set("Removendo containers e imagens...", $colors.warning)
      $form.Refresh()
      Push-Location $INST_DIR
      docker compose down 2>&1 | Out-Null
      docker rmi -f instalacao-crm instalacao-agenda 2>&1 | Out-Null
      Pop-Location
      $stepAct.Set("OK Docker desinstalado", $colors.success)
      $form.Refresh()
    } else {
      $stepAct.Set("Rebuildando e reiniciando containers...", $colors.warning)
      $form.Refresh()
      Push-Location $INST_DIR
      docker compose build --no-cache 2>&1 | Out-Null
      docker compose up -d 2>&1 | Out-Null
      Pop-Location
      $stepAct.Set("OK containers atualizados", $colors.success)
      $form.Refresh()
    }
  } else {
    $isAmbos = $target -eq "nativo-ambos"
    $isCrm = $target -eq "nativo-crm" -or $isAmbos
    $isAgenda = $target -eq "nativo-agenda" -or $isAmbos

    if ($action -eq "reinstall") {
      if ($isCrm) {
        $stepAct.Set("Removendo e reinstalando CRM...", $colors.warning)
        $form.Refresh()
        $venvDir = "$CRM_DIR\backend\.venv"
        if (Test-Path $venvDir) { Remove-Item -Recurse -Force $venvDir -ErrorAction SilentlyContinue }
        python -m venv $venvDir 2>$null
        & "$venvDir\Scripts\pip" install --quiet --upgrade pip 2>$null
        & "$venvDir\Scripts\pip" install --quiet flask flask-cors 2>$null
        $stepAct.Set("OK CRM reinstalado", $colors.success)
        $form.Refresh()
      }
      if ($isAgenda) {
        $stepAct.Set("Removendo e reinstalando Agendamento...", $colors.warning)
        $form.Refresh()
        $nmDir = "$APP_DIR\node_modules"
        if (Test-Path $nmDir) { Remove-Item -Recurse -Force $nmDir -ErrorAction SilentlyContinue }
        Push-Location $APP_DIR
        npm install --silent 2>$null
        Pop-Location
        $stepAct.Set("OK Agendamento reinstalado", $colors.success)
        $form.Refresh()
      }
    } elseif ($action -eq "uninstall") {
      if ($isCrm) {
        $stepAct.Set("Removendo CRM...", $colors.warning)
        $form.Refresh()
        Get-CimInstance Win32_Process -Filter "Name LIKE 'python%' AND CommandLine LIKE '%server.py%'" | Invoke-CimMethod -MethodName Terminate -ErrorAction SilentlyContinue
        $venvDir = "$CRM_DIR\backend\.venv"
        if (Test-Path $venvDir) { Remove-Item -Recurse -Force $venvDir -ErrorAction SilentlyContinue }
        $stepAct.Set("OK CRM desinstalado", $colors.success)
        $form.Refresh()
      }
      if ($isAgenda) {
        $stepAct.Set("Removendo Agendamento...", $colors.warning)
        $form.Refresh()
        Get-CimInstance Win32_Process -Filter "Name LIKE 'node%' AND (CommandLine LIKE '%vite%' OR CommandLine LIKE '%npm%')" | Invoke-CimMethod -MethodName Terminate -ErrorAction SilentlyContinue
        $nmDir = "$APP_DIR\node_modules"
        if (Test-Path $nmDir) { Remove-Item -Recurse -Force $nmDir -ErrorAction SilentlyContinue }
        $stepAct.Set("OK Agendamento desinstalado", $colors.success)
        $form.Refresh()
      }
      if (Test-Path $DB_PATH) {
        $msg = "Remover tambem o banco de dados?`n`n$DB_PATH"
        $resp = [System.Windows.Forms.MessageBox]::Show($msg, "Banco de dados", "YesNo", "Question")
        if ($resp -eq "Yes") {
          Remove-Item -Force $DB_PATH -ErrorAction SilentlyContinue
          $stepAct.Set("OK banco de dados removido", $colors.success)
          $form.Refresh()
        }
      }
    } else {
      if ($isCrm) {
        $venvDir = "$CRM_DIR\backend\.venv"
        if (Test-Path $venvDir) {
          $stepAct.Set("Atualizando dependencias Python do CRM...", $colors.warning)
          $form.Refresh()
          & "$venvDir\Scripts\pip" install --quiet --upgrade pip flask flask-cors 2>$null
        }
      }
      if ($isAgenda) {
        $nmDir = "$APP_DIR\node_modules"
        if (Test-Path $nmDir) {
          $stepAct.Set("Atualizando dependencias npm do Agendamento...", $colors.warning)
          $form.Refresh()
          Push-Location $APP_DIR
          npm update --silent 2>$null
          Pop-Location
        }
      }
      $stepAct.Set("OK dependencias atualizadas", $colors.success)
      $form.Refresh()
    }
  }

  $stepFin.Set("Concluido!", $colors.success)
  $form.Refresh()
  Start-Sleep -Milliseconds 500

  if ($target -eq "docker") {
    Show-Final @("CRM: http://localhost:3001", "Agendamento: http://localhost:5173")
  } else {
    Show-Final @("Use o start.sh para iniciar os aplicativos")
  }
}

# ════════════════════════════════════════════
#  TELA DE MÉTODO (Docker vs Nativo)
# ════════════════════════════════════════════

function Show-MethodMenu($selection) {
  $panelMain.Controls.Clear()

  $labelMap = @{ crm="BeautyFlow CRM"; agenda="BeautyFlow Agendamento"; ambos="AMBOS" }

  $title = New-Object System.Windows.Forms.Label
  $title.Text = "Instalar: $($labelMap[$selection])"
  $title.Font = $fonts.header; $title.ForeColor = HexColor $colors.white
  $title.Size = New-Object System.Drawing.Size(600, 30)
  $title.Location = New-Object System.Drawing.Point(40, 30)
  $panelMain.Controls.Add($title)

  $l = New-Object System.Windows.Forms.Label
  $l.Text = "Escolha o metodo de instalacao:"
  $l.Font = $fonts.body; $l.ForeColor = HexColor $colors.sub
  $l.Size = New-Object System.Drawing.Size(560, 22)
  $l.Location = New-Object System.Drawing.Point(60, 80)
  $panelMain.Controls.Add($l)

  $y = 130
  $btnDocker = New-Object System.Windows.Forms.Button
  $btnDocker.Text = "  Docker (Recomendado)`n  Container isolado, sem poluir o sistema"
  $btnDocker.Font = $fonts.body; $btnDocker.Size = New-Object System.Drawing.Size(500, 60)
  $btnDocker.Location = New-Object System.Drawing.Point(80, $y)
  $btnDocker.BackColor = HexColor $colors.card; $btnDocker.ForeColor = HexColor $colors.white
  $btnDocker.FlatStyle = "Flat"
  $btnDocker.FlatAppearance.BorderSize = 1; $btnDocker.FlatAppearance.BorderColor = HexColor $colors.primary
  $btnDocker.TextAlign = "MiddleLeft"
  $btnDocker.Tag = $selection
  $btnDocker.Add_Click({ Start-Install $this.Tag "docker" })
  $panelMain.Controls.Add($btnDocker); $y += 75

  $btnNative = New-Object System.Windows.Forms.Button
  $btnNative.Text = "  Instalacao Nativa`n  Python (CRM) / Node.js (Agendamento) direto"
  $btnNative.Font = $fonts.body; $btnNative.Size = New-Object System.Drawing.Size(500, 60)
  $btnNative.Location = New-Object System.Drawing.Point(80, $y)
  $btnNative.BackColor = HexColor $colors.card; $btnNative.ForeColor = HexColor $colors.white
  $btnNative.FlatStyle = "Flat"
  $btnNative.FlatAppearance.BorderSize = 1; $btnNative.FlatAppearance.BorderColor = HexColor $colors.sub
  $btnNative.TextAlign = "MiddleLeft"
  $btnNative.Tag = $selection
  $btnNative.Add_Click({ Start-Install $this.Tag "native" })
  $panelMain.Controls.Add($btnNative); $y += 75

  $btnBack = New-Object System.Windows.Forms.Button
  $btnBack.Text = "  Voltar"
  $btnBack.Font = $fonts.body; $btnBack.Size = New-Object System.Drawing.Size(200, 40)
  $btnBack.Location = New-Object System.Drawing.Point(80, $y)
  $btnBack.BackColor = HexColor $colors.card; $btnBack.ForeColor = HexColor $colors.sub
  $btnBack.FlatStyle = "Flat"
  $btnBack.Add_Click({ Show-Menu })
  $panelMain.Controls.Add($btnBack)
}

# ════════════════════════════════════════════
#  BOTÃO VOLTAR (exibe erro + volta)
# ════════════════════════════════════════════

function Add-ErrorAndBack($text, $backAction) {
  $nextY = Get-NextY
  $l = New-Object System.Windows.Forms.Label
  $l.Text = $text
  $l.Font = $fonts.body; $l.ForeColor = HexColor $colors.white
  $l.Size = New-Object System.Drawing.Size(560, 22)
  $l.Location = New-Object System.Drawing.Point(60, $nextY)
  $panelMain.Controls.Add($l)

  $btnBack = New-Object System.Windows.Forms.Button
  $btnBack.Text = "  Voltar"
  $btnBack.Font = $fonts.body; $btnBack.Size = New-Object System.Drawing.Size(200, 40)
  $btnBack.Location = New-Object System.Drawing.Point(80, $nextY + 35)
  $btnBack.BackColor = HexColor $colors.card; $btnBack.ForeColor = HexColor $colors.sub
  $btnBack.FlatStyle = "Flat"
  $btnBack.Add_Click($backAction)
  $panelMain.Controls.Add($btnBack)
}

# ════════════════════════════════════════════
#  INSTALAÇÃO
# ════════════════════════════════════════════

function Start-Install($selection, $method) {
  $panelMain.Controls.Clear()
  Add-Title "Instalando..."
  Add-Spacer

  $stepClone  = Add-Step "Preparando repositorio..."
  $stepDb     = Add-Step "Configurando banco de dados..."
  $stepCrm    = $null
  $stepAgenda = $null

  if ($selection -eq "crm" -or $selection -eq "ambos") {
    $stepCrm = Add-Step "Instalando BeautyFlow CRM..."
  }
  if ($selection -eq "agenda" -or $selection -eq "ambos") {
    $stepAgenda = Add-Step "Instalando BeautyFlow Agendamento..."
  }
  $stepFinal  = Add-Step "Finalizando..."
  Add-Spacer

  # ── Clonar ──
  $stepClone.Set("Clonando repositorio...", $colors.warning)
  $form.Refresh()
  if (Test-Path $REPO_DIR) { Remove-Item -Recurse -Force $REPO_DIR -ErrorAction SilentlyContinue }
  git clone $REPO_URL $REPO_DIR 2>&1 | Out-Null
  if (-not (Test-Path $REPO_DIR)) {
    Add-ErrorAndBack "Erro ao clonar repositorio. Verifique se o git esta instalado." { Show-MethodMenu $selection }
    return
  }
  $stepClone.Set("OK repositorio pronto", $colors.success)
  $form.Refresh()

  # ── Banco de Dados ──
  $stepDb.Set("Verificando banco de dados...", $colors.warning)
  $form.Refresh()
  if (-not (Test-Path $DB_DIR)) { New-Item -ItemType Directory -Path $DB_DIR -Force | Out-Null }

  if (Test-Path $DB_PATH) {
    $msg = "Banco de dados ja existe.`n`nLimpar (remover dados existentes)?"
    $resp = [System.Windows.Forms.MessageBox]::Show($msg, "Banco de dados", "YesNo", "Question")
    if ($resp -eq "Yes") {
      Remove-Item -Force $DB_PATH -ErrorAction SilentlyContinue
    }
  }

  if (-not (Test-Path $DB_PATH)) {
    $sqlScript = "$INST_DIR\init_db.sql"
    if (Test-Path $sqlScript) {
      try {
        Add-Type -AssemblyName System.Data.SQLite -ErrorAction Stop
        $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$DB_PATH")
        $conn.Open()
        $sql = Get-Content $sqlScript -Raw
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $sql
        $cmd.ExecuteNonQuery() | Out-Null
        $conn.Close()
      } catch {
        $sqliteOk = Get-Command "sqlite3" -ErrorAction SilentlyContinue
        if ($sqliteOk) {
          & (Get-Command sqlite3).Source $DB_PATH ".read '$sqlScript'" 2>$null
        } else {
          python -c @"
import sqlite3, os
os.makedirs(os.path.dirname('$DB_PATH'), exist_ok=True)
conn = sqlite3.connect('$DB_PATH')
conn.executescript(open('$sqlScript', encoding='utf-8').read())
conn.commit()
conn.close()
"@ 2>$null
        }
      }
    }
  }
  $stepDb.Set("OK banco criado (tabelas prontas)", $colors.success)
  $form.Refresh()

  if ($method -eq "docker") {
    # ═══════ DOCKER ═══════
    $dockerOk = (Get-Command "docker" -ErrorAction SilentlyContinue) -ne $null
    if (-not $dockerOk) {
      $stepFinal.Set("Docker Desktop nao encontrado!", $colors.warning)
      $form.Refresh()
      $msg = "Docker Desktop nao esta instalado.`n`nDeseja baixar o instalador do Docker Desktop?"
      $resp = [System.Windows.Forms.MessageBox]::Show($msg, "Docker nao encontrado", "YesNo", "Question")
      if ($resp -eq "Yes") {
        Start-Process "https://docs.docker.com/desktop/setup/install/windows-install/"
      }
      Add-ErrorAndBack "Instale o Docker Desktop e tente novamente." { Show-MethodMenu $selection }
      return
    }

    Push-Location $INST_DIR
    if ($selection -eq "crm" -or $selection -eq "ambos") {
      $stepCrm.Set("Build CRM...", $colors.warning); $form.Refresh()
      docker compose build crm 2>&1 | Out-Null
      $stepCrm.Set("OK CRM pronto", $colors.success); $form.Refresh()
    }
    if ($selection -eq "agenda" -or $selection -eq "ambos") {
      $stepAgenda.Set("Build Agendamento...", $colors.warning); $form.Refresh()
      docker compose build agenda 2>&1 | Out-Null
      $stepAgenda.Set("OK Agendamento pronto", $colors.success); $form.Refresh()
    }
    docker compose up -d 2>&1 | Out-Null
    Pop-Location

  } else {
    # ═══════ NATIVO ═══════
    if ($selection -eq "crm" -or $selection -eq "ambos") {
      $stepCrm.Set("Verificando Python...", $colors.warning); $form.Refresh()
      $pythonOk = Get-Command "python" -ErrorAction SilentlyContinue
      if (-not $pythonOk) {
        $stepCrm.Set("Python nao encontrado!", $colors.warning)
        $form.Refresh()
        $msg = "Python 3.10+ nao foi encontrado.`n`nDeseja baixar o instalador do Python?`n(Instale com a opcao 'Add Python to PATH' marcada.)"
        $resp = [System.Windows.Forms.MessageBox]::Show($msg, "Python nao encontrado", "YesNo", "Question")
        if ($resp -eq "Yes") {
          Start-Process "https://www.python.org/downloads/"
        }
        Add-ErrorAndBack "Instale Python 3.10+ e tente novamente." { Show-MethodMenu $selection }
        return
      }
      $stepCrm.Set("Instalando dependencias Python...", $colors.warning); $form.Refresh()

      $venvDir = "$CRM_DIR\backend\.venv"
      if (-not (Test-Path $venvDir)) {
        python -m venv $venvDir 2>$null
      }
      & "$venvDir\Scripts\pip" install --quiet --upgrade pip 2>$null
      & "$venvDir\Scripts\pip" install --quiet flask flask-cors 2>$null
      $stepCrm.Set("OK CRM instalado", $colors.success)
      $form.Refresh()
    }

    if ($selection -eq "agenda" -or $selection -eq "ambos") {
      $stepAgenda.Set("Verificando Node.js...", $colors.warning); $form.Refresh()
      $nodeOk = Get-Command "node" -ErrorAction SilentlyContinue
      if (-not $nodeOk) {
        $stepAgenda.Set("Node.js nao encontrado!", $colors.warning)
        $form.Refresh()
        $msg = "Node.js LTS nao foi encontrado.`n`nDeseja baixar o instalador do Node.js?"
        $resp = [System.Windows.Forms.MessageBox]::Show($msg, "Node.js nao encontrado", "YesNo", "Question")
        if ($resp -eq "Yes") {
          Start-Process "https://nodejs.org/"
        }
        Add-ErrorAndBack "Instale Node.js LTS e tente novamente." { Show-MethodMenu $selection }
        return
      }
      $stepAgenda.Set("Instalando dependencias npm...", $colors.warning); $form.Refresh()
      Push-Location $APP_DIR
      npm install --silent 2>$null
      Pop-Location
      $stepAgenda.Set("OK Agendamento instalado", $colors.success)
      $form.Refresh()
    }
  }

  $urls = @()
  if ($selection -eq "crm" -or $selection -eq "ambos") { $urls += "CRM: http://localhost:3001" }
  if ($selection -eq "agenda" -or $selection -eq "ambos") { $urls += "Agendamento: http://localhost:5173" }

  if ($method -eq "native") {
    $msg = "Instalacao concluida!`n`nDeseja iniciar os aplicativos agora?"
    $resp = [System.Windows.Forms.MessageBox]::Show($msg, "Iniciar agora?", "YesNo", "Question")
    if ($resp -eq "Yes") {
      $stepFinal.Set("Iniciando...", $colors.warning)
      $form.Refresh()

      if ($selection -eq "crm" -or $selection -eq "ambos") {
        $venvDir = "$CRM_DIR\backend\.venv"
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "$venvDir\Scripts\python.exe"
        $psi.Arguments = "$CRM_DIR\backend\server.py"
        $psi.EnvironmentVariables["BEAUTYFLOW_DB_PATH"] = $DB_PATH
        $psi.EnvironmentVariables["BEAUTYFLOW_NO_SEED"] = "true"
        $psi.WorkingDirectory = "$CRM_DIR\backend"
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        [System.Diagnostics.Process]::Start($psi) | Out-Null
      }
      if ($selection -eq "agenda" -or $selection -eq "ambos") {
        $psi2 = New-Object System.Diagnostics.ProcessStartInfo
        $psi2.FileName = "cmd.exe"
        $psi2.Arguments = "/c cd /d $APP_DIR && npm run dev"
        $psi2.UseShellExecute = $false
        $psi2.CreateNoWindow = $true
        [System.Diagnostics.Process]::Start($psi2) | Out-Null
      }
    }
  }

  $stepFinal.Set("Concluido!", $colors.success)
  $form.Refresh()

  Show-Final $urls
}

# ════════════════════════════════════════════
#  TELA FINAL
# ════════════════════════════════════════════

function Show-Final($urls) {
  $panelMain.Controls.Clear()

  $check = New-Object System.Windows.Forms.Label
  $check.Text = "OK"
  $check.Font = New-Object System.Drawing.Font("Segoe UI", 42, [System.Drawing.FontStyle]::Bold)
  $check.ForeColor = HexColor $colors.success
  $check.Size = New-Object System.Drawing.Size(600, 60)
  $check.Location = New-Object System.Drawing.Point(40, 20)
  $check.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($check)

  $title = New-Object System.Windows.Forms.Label
  $title.Text = "Instalacao concluida!"
  $title.Font = $fonts.header; $title.ForeColor = HexColor $colors.white
  $title.Size = New-Object System.Drawing.Size(600, 30)
  $title.Location = New-Object System.Drawing.Point(40, 85)
  $title.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($title)

  $y = 130

  $l = New-Object System.Windows.Forms.Label
  $l.Text = "Acesse os aplicativos:"
  $l.Font = $fonts.body; $l.ForeColor = HexColor $colors.sub
  $l.Size = New-Object System.Drawing.Size(560, 22)
  $l.Location = New-Object System.Drawing.Point(60, $y)
  $l.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($l)

  $y += 35
  foreach ($url in $urls) {
    $parts = $url -split ": "
    $appName = $parts[0]
    $appUrl = $parts[1]

    $u = New-Object System.Windows.Forms.Label
    $u.Text = "$($appName):"
    $u.Font = $fonts.body; $u.ForeColor = HexColor $colors.white
    $u.Size = New-Object System.Drawing.Size(130, 28)
    $u.Location = New-Object System.Drawing.Point(120, $y)
    $u.TextAlign = "MiddleRight"
    $panelMain.Controls.Add($u)

    $box = New-Object System.Windows.Forms.TextBox
    $box.Text = $appUrl
    $box.Font = $fonts.mono; $box.ForeColor = HexColor $colors.primary
    $box.BackColor = HexColor $colors.card
    $box.Size = New-Object System.Drawing.Size(280, 28)
    $box.Location = New-Object System.Drawing.Point(260, $y)
    $box.ReadOnly = $true; $box.BorderStyle = "FixedSingle"
    $panelMain.Controls.Add($box)

    $btnOpen = New-Object System.Windows.Forms.Button
    $btnOpen.Text = "Abrir"
    $btnOpen.Font = $fonts.small; $btnOpen.Size = New-Object System.Drawing.Size(65, 28)
    $btnOpen.Location = New-Object System.Drawing.Point(550, $y)
    $btnOpen.BackColor = HexColor $colors.success; $btnOpen.ForeColor = "White"
    $btnOpen.FlatStyle = "Flat"
    $btnOpen.Tag = $appUrl
    $btnOpen.Add_Click({ [System.Diagnostics.Process]::Start($this.Tag) })
    $panelMain.Controls.Add($btnOpen)

    $y += 38
  }

  $y += 20
  $l2 = New-Object System.Windows.Forms.Label
  $l2.Text = "Pressione Sair para fechar."
  $l2.Font = $fonts.small; $l2.ForeColor = HexColor $colors.sub
  $l2.Size = New-Object System.Drawing.Size(560, 20)
  $l2.Location = New-Object System.Drawing.Point(60, $y)
  $l2.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($l2)

  $y += 30
  $btnSair = New-Object System.Windows.Forms.Button
  $btnSair.Text = "  Sair"
  $btnSair.Font = $fonts.body; $btnSair.Size = New-Object System.Drawing.Size(200, 40)
  $btnSair.Location = New-Object System.Drawing.Point(240, $y)
  $btnSair.BackColor = HexColor $colors.primary; $btnSair.ForeColor = "White"
  $btnSair.FlatStyle = "Flat"
  $btnSair.Add_Click({ $form.Close() })
  $panelMain.Controls.Add($btnSair)
}

# ════════════════════════════════════════════
#  COMPONENTES AUXILIARES
# ════════════════════════════════════════════

function Add-Title($text) {
  $l = New-Object System.Windows.Forms.Label
  $l.Text = $text; $l.Font = $fonts.header; $l.ForeColor = HexColor $colors.white
  $l.Size = New-Object System.Drawing.Size(600, 30)
  $l.Location = New-Object System.Drawing.Point(40, 25)
  $panelMain.Controls.Add($l)
}

function Add-Spacer {
  $top = Get-NextY
  $l = New-Object System.Windows.Forms.Label
  $l.Text = ""; $l.Size = New-Object System.Drawing.Size(10, 5)
  $l.Location = New-Object System.Drawing.Point(40, $top)
  $panelMain.Controls.Add($l)
}

function Add-Step($text) {
  $top = Get-NextY
  $box = New-Object System.Windows.Forms.Panel
  $box.Size = New-Object System.Drawing.Size(540, 38)
  $box.Location = New-Object System.Drawing.Point(50, $top)
  $box.BackColor = HexColor $colors.card
  $panelMain.Controls.Add($box)

  $dot = New-Object System.Windows.Forms.Label
  $dot.Text = "o"
  $dot.Font = $fonts.body; $dot.ForeColor = HexColor $colors.sub
  $dot.Size = New-Object System.Drawing.Size(20, 38)
  $dot.Location = New-Object System.Drawing.Point(10, 0)
  $dot.TextAlign = "MiddleLeft"
  $box.Controls.Add($dot)

  $label = New-Object System.Windows.Forms.Label
  $label.Text = $text
  $label.Font = $fonts.body; $label.ForeColor = HexColor $colors.white
  $label.Size = New-Object System.Drawing.Size(500, 38)
  $label.Location = New-Object System.Drawing.Point(30, 0)
  $label.TextAlign = "MiddleLeft"
  $box.Controls.Add($label)

  $obj = New-Object PSObject
  $obj | Add-Member -MemberType NoteProperty -Name "Box" -Value $box
  $obj | Add-Member -MemberType NoteProperty -Name "Dot" -Value $dot
  $obj | Add-Member -MemberType NoteProperty -Name "Label" -Value $label
  $obj | Add-Member -MemberType ScriptMethod -Name "Set" -Value {
    param($newText, $color)
    $this.Label.Text = $newText
    $this.Dot.Text = "*"
    $this.Dot.ForeColor = HexColor $color
    $this.Box.Refresh()
  }
  return $obj
}

# ════════════════════════════════════════════
#  JANELA PRINCIPAL
# ════════════════════════════════════════════

$form = New-Object System.Windows.Forms.Form
$form.Text = "BeautyFlow - Instalador Unificado Windows"
$form.Size = New-Object System.Drawing.Size(680, 640)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = HexColor $colors.bg

$panelMain = New-Object System.Windows.Forms.Panel
$panelMain.Size = New-Object System.Drawing.Size(680, 620)
$panelMain.Location = New-Object System.Drawing.Point(0, 0)
$panelMain.BackColor = HexColor $colors.bg
$panelMain.AutoScroll = $true
$form.Controls.Add($panelMain)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = "BeautyFlow v1.0"
$footer.Font = $fonts.small; $footer.ForeColor = HexColor $colors.sub
$footer.Size = New-Object System.Drawing.Size(660, 20)
$footer.Location = New-Object System.Drawing.Point(10, 620)
$form.Controls.Add($footer)

Show-Menu
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()

} catch {
  $startErr = $_.Exception.Message
  try {
    [System.Windows.Forms.MessageBox]::Show("Erro ao iniciar o instalador:`n$startErr", "Erro", "OK", "Error")
  } catch {
    Write-Host "ERRO: $startErr"
    Write-Host "Pressione qualquer tecla para sair."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
  }
}