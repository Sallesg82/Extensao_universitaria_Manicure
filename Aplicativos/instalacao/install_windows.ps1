<#
╔══════════════════════════════════════════════╗
║   BeautyFlow — Instalador Unificado Windows ║
╚══════════════════════════════════════════════╝
#>

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

  # ── Opção 1: CRM ──
  $btnCrm = New-Object System.Windows.Forms.Button
  $btnCrm.Text = "  BeautyFlow CRM`n  Gestao do salao (clientes, agenda, financeiro)"
  $btnCrm.Font = $fonts.body; $btnCrm.Size = New-Object System.Drawing.Size(500, 55)
  $btnCrm.Location = New-Object System.Drawing.Point(80, $y)
  $btnCrm.BackColor = HexColor $colors.card; $btnCrm.ForeColor = HexColor $colors.white
  $btnCrm.FlatStyle = "Flat"
  $btnCrm.FlatAppearance.BorderSize = 1; $btnCrm.FlatAppearance.BorderColor = HexColor $colors.primary
  $btnCrm.TextAlign = "MiddleLeft"
  $btnCrm.Add_Click({ Show-MethodMenu "crm" })
  $panelMain.Controls.Add($btnCrm); $y += 65

  # ── Opção 2: Agendamento ──
  $btnAgenda = New-Object System.Windows.Forms.Button
  $btnAgenda.Text = "  BeautyFlow Agendamento`n  Painel do cliente (agendar servicos)"
  $btnAgenda.Font = $fonts.body; $btnAgenda.Size = New-Object System.Drawing.Size(500, 55)
  $btnAgenda.Location = New-Object System.Drawing.Point(80, $y)
  $btnAgenda.BackColor = HexColor $colors.card; $btnAgenda.ForeColor = HexColor $colors.white
  $btnAgenda.FlatStyle = "Flat"
  $btnAgenda.FlatAppearance.BorderSize = 1; $btnAgenda.FlatAppearance.BorderColor = HexColor $colors.sub
  $btnAgenda.TextAlign = "MiddleLeft"
  $btnAgenda.Add_Click({ Show-MethodMenu "agenda" })
  $panelMain.Controls.Add($btnAgenda); $y += 65

  # ── Opção 3: Ambos ──
  $btnAmbos = New-Object System.Windows.Forms.Button
  $btnAmbos.Text = "  Instalar AMBOS (Recomendado)`n  CRM + Agendamento integrados"
  $btnAmbos.Font = $fonts.body; $btnAmbos.Size = New-Object System.Drawing.Size(500, 55)
  $btnAmbos.Location = New-Object System.Drawing.Point(80, $y)
  $btnAmbos.BackColor = HexColor $colors.success; $btnAmbos.ForeColor = "White"
  $btnAmbos.FlatStyle = "Flat"
  $btnAmbos.TextAlign = "MiddleLeft"
  $btnAmbos.Add_Click({ Show-MethodMenu "ambos" })
  $panelMain.Controls.Add($btnAmbos)
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
  $btnDocker.Add_Click({ Start-Install $selection "docker" })
  $panelMain.Controls.Add($btnDocker); $y += 75

  $btnNative = New-Object System.Windows.Forms.Button
  $btnNative.Text = "  Instalacao Nativa`n  Python (CRM) / Node.js (Agendamento) direto"
  $btnNative.Font = $fonts.body; $btnNative.Size = New-Object System.Drawing.Size(500, 60)
  $btnNative.Location = New-Object System.Drawing.Point(80, $y)
  $btnNative.BackColor = HexColor $colors.card; $btnNative.ForeColor = HexColor $colors.white
  $btnNative.FlatStyle = "Flat"
  $btnNative.FlatAppearance.BorderSize = 1; $btnNative.FlatAppearance.BorderColor = HexColor $colors.sub
  $btnNative.TextAlign = "MiddleLeft"
  $btnNative.Add_Click({ Start-Install $selection "native" })
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
  $stepClone.Set("OK repositorio pronto", $colors.success)
  $form.Refresh()

  # ── Banco de Dados ──
  $stepDb.Set("Criando banco SQLite...", $colors.warning)
  $form.Refresh()
  if (-not (Test-Path $DB_DIR)) { New-Item -ItemType Directory -Path $DB_DIR -Force | Out-Null }
  if (-not (Test-Path $DB_PATH)) {
    $sqlScript = "$INST_DIR\init_db.sql"
    if (Test-Path $sqlScript) {
      $sql = Get-Content $sqlScript -Raw
      # Usar ADO.NET para criar o banco
      $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$DB_PATH")
      # Se SQLite não estiver disponível, tentar via PowerShell
      try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $sql
        $cmd.ExecuteNonQuery() | Out-Null
        $conn.Close()
      } catch {
        # Fallback: criar via sqlite3 se disponível
        $sqliteOk = Get-Command "sqlite3" -ErrorAction SilentlyContinue
        if ($sqliteOk) {
          sqlite3 $DB_PATH < $sqlScript 2>$null
        } else {
          # Criar via Python
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
      $stepFinal.Set("Docker Desktop nao encontrado!", "#c05050")
      Add-Spacer
      $l = New-Object System.Windows.Forms.Label
      $l.Text = "Instale Docker Desktop e tente novamente."
      $l.Font = $fonts.body; $l.ForeColor = HexColor $colors.white
      $l.Size = New-Object System.Drawing.Size(560, 22)
      $l.Location = New-Object System.Drawing.Point(60, 350)
      $panelMain.Controls.Add($l)
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
        $stepCrm.Set("Python nao encontrado!", "#c05050")
        Add-Spacer
        $l = New-Object System.Windows.Forms.Label
        $l.Text = "Instale Python 3.10+ em: https://python.org"
        $l.Font = $fonts.body; $l.ForeColor = HexColor $colors.white
        $l.Size = New-Object System.Drawing.Size(560, 22)
        $l.Location = New-Object System.Drawing.Point(60, 350)
        $panelMain.Controls.Add($l)
        return
      }
      $stepCrm.Set("Instalando dependencias Python...", $colors.warning); $form.Refresh()

      # Criar venv
      $venvDir = "$CRM_DIR\backend\.venv"
      if (-not (Test-Path $venvDir)) {
        python -m venv $venvDir 2>$null
      }
      # Instalar dependências
      & "$venvDir\Scripts\pip" install --quiet --upgrade pip 2>$null
      & "$venvDir\Scripts\pip" install --quiet flask flask-cors 2>$null
      $stepCrm.Set("OK CRM instalado", $colors.success)
      $form.Refresh()

      # Iniciar CRM
      $env:BEAUTYFLOW_DB_PATH = $DB_PATH
      $env:BEAUTYFLOW_NO_SEED = "true"
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
      $stepAgenda.Set("Verificando Node.js...", $colors.warning); $form.Refresh()
      $nodeOk = Get-Command "node" -ErrorAction SilentlyContinue
      if (-not $nodeOk) {
        $stepAgenda.Set("Node.js nao encontrado!", "#c05050")
        Add-Spacer
        $l = New-Object System.Windows.Forms.Label
        $l.Text = "Instale Node.js LTS em: https://nodejs.org"
        $l.Font = $fonts.body; $l.ForeColor = HexColor $colors.white
        $l.Size = New-Object System.Drawing.Size(560, 22)
        $l.Location = New-Object System.Drawing.Point(60, 350)
        $panelMain.Controls.Add($l)
        return
      }
      $stepAgenda.Set("Instalando dependencias npm...", $colors.warning); $form.Refresh()
      Push-Location $APP_DIR
      npm install --silent 2>$null
      Pop-Location
      $stepAgenda.Set("OK Agendamento instalado", $colors.success)
      $form.Refresh()

      # Iniciar Agendamento
      $psi2 = New-Object System.Diagnostics.ProcessStartInfo
      $psi2.FileName = "cmd.exe"
      $psi2.Arguments = "/c cd /d $APP_DIR && npm run dev"
      $psi2.UseShellExecute = $false
      $psi2.CreateNoWindow = $true
      [System.Diagnostics.Process]::Start($psi2) | Out-Null
    }
  }

  $stepFinal.Set("Concluido!", $colors.success)
  $form.Refresh()
  Start-Sleep -Milliseconds 500

  $urls = @()
  if ($selection -eq "crm" -or $selection -eq "ambos") { $urls += "CRM: http://localhost:3001" }
  if ($selection -eq "agenda" -or $selection -eq "ambos") { $urls += "Agendamento: http://localhost:5173" }
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

  Add-Spacer

  $l = New-Object System.Windows.Forms.Label
  $l.Text = "Acesse os aplicativos:"
  $l.Font = $fonts.body; $l.ForeColor = HexColor $colors.sub
  $l.Size = New-Object System.Drawing.Size(560, 22)
  $l.Location = New-Object System.Drawing.Point(60, ($panelMain.Controls | % { $_.Location.Y + $_.Size.Height } | Measure -Max | % { $_.Maximum + 10 }))
  $l.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($l)

  $y = $l.Location.Y + 35
  foreach ($url in $urls) {
    $parts = $url -split ": "
    $appName = $parts[0]
    $appUrl = $parts[1]

    $u = New-Object System.Windows.Forms.Label
    $u.Text = "$appName:"
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
    $script:targetUrl = $appUrl
    $btnOpen.Add_Click({ [System.Diagnostics.Process]::Start($script:targetUrl) })
    $panelMain.Controls.Add($btnOpen)

    $y += 38
  }

  Add-Spacer
  $endY = ($panelMain.Controls | % { $_.Location.Y + $_.Size.Height } | Measure -Max | % { $_.Maximum + 10 })

  $l2 = New-Object System.Windows.Forms.Label
  $l2.Text = "Pressione Sair para fechar."
  $l2.Font = $fonts.small; $l2.ForeColor = HexColor $colors.sub
  $l2.Size = New-Object System.Drawing.Size(560, 20)
  $l2.Location = New-Object System.Drawing.Point(60, $endY)
  $l2.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($l2)
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
  $top = 0
  if ($panelMain.Controls.Count -gt 0) {
    $top = ($panelMain.Controls | % { $_.Location.Y + $_.Size.Height } | Measure -Max | % { $_.Maximum })
  }
  $l = New-Object System.Windows.Forms.Label
  $l.Text = ""; $l.Size = New-Object System.Drawing.Size(10, 10)
  $l.Location = New-Object System.Drawing.Point(40, $top)
  $panelMain.Controls.Add($l)
}

function Add-Step($text) {
  $top = 0
  if ($panelMain.Controls.Count -gt 0) {
    $top = ($panelMain.Controls | % { $_.Location.Y + $_.Size.Height } | Measure -Max | % { $_.Maximum + 8 })
  }
  $box = New-Object System.Windows.Forms.Panel
  $box.Size = New-Object System.Drawing.Size(540, 38)
  $box.Location = New-Object System.Drawing.Point(50, $top)
  $box.BackColor = HexColor $colors.card
  $panelMain.Controls.Add($box)

  $dot = New-Object System.Windows.Forms.Label
  $dot.Name = "dot"; $dot.Text = "○"
  $dot.Font = $fonts.body; $dot.ForeColor = HexColor $colors.sub
  $dot.Size = New-Object System.Drawing.Size(20, 38)
  $dot.Location = New-Object System.Drawing.Point(10, 0)
  $dot.TextAlign = "MiddleLeft"
  $box.Controls.Add($dot)

  $label = New-Object System.Windows.Forms.Label
  $label.Name = "label"; $label.Text = $text
  $label.Font = $fonts.body; $label.ForeColor = HexColor $colors.white
  $label.Size = New-Object System.Drawing.Size(500, 38)
  $label.Location = New-Object System.Drawing.Point(30, 0)
  $label.TextAlign = "MiddleLeft"
  $box.Controls.Add($label)

  return New-Object PSObject -Property @{
    Box = $box; Dot = $dot; Label = $label
    Set = { param($newText, $color)
      $this.Label.Text = $newText
      $this.Dot.Text = "●"
      $this.Dot.ForeColor = HexColor $color
      $this.Box.Refresh()
    }.GetNewClosure()
  }
}

# ════════════════════════════════════════════
#  JANELA PRINCIPAL
# ════════════════════════════════════════════

$form = New-Object System.Windows.Forms.Form
$form.Text = "BeautyFlow - Instalador Unificado Windows"
$form.Size = New-Object System.Drawing.Size(680, 600)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = HexColor $colors.bg

$panelMain = New-Object System.Windows.Forms.Panel
$panelMain.Size = New-Object System.Drawing.Size(680, 560)
$panelMain.Location = New-Object System.Drawing.Point(0, 0)
$panelMain.BackColor = HexColor $colors.bg
$form.Controls.Add($panelMain)

$winVer = (Get-CimInstance Win32_OperatingSystem).Caption
$footer = New-Object System.Windows.Forms.Label
$footer.Text = "$winVer  |  BeautyFlow v1.0"
$footer.Font = $fonts.small; $footer.ForeColor = HexColor $colors.sub
$footer.Size = New-Object System.Drawing.Size(660, 20)
$footer.Location = New-Object System.Drawing.Point(10, 565)
$form.Controls.Add($footer)

Show-Menu
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
