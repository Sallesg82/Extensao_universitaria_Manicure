<#
╔══════════════════════════════════════════════╗
║ BeautyFlow Agendamento — Instalador Windows ║
╚══════════════════════════════════════════════╝
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$REPO_URL  = "https://github.com/Sallesg82/Extensao_universitaria_Manicure.git"
$REPO_DIR  = "$env:TEMP\Extensao_universitaria_Manicure"
$APP_DIR   = "$REPO_DIR\Aplicativos\agendamento Vinicius"
$INST_DIR  = "$APP_DIR\instalacao"

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
#  FUNÇÕES DE TELA
# ════════════════════════════════════════════

function Show-Welcome {
  $panelMain.Controls.Clear()

  $logo = New-Object System.Windows.Forms.Label
  $logo.Text = "BeautyFlow Agendamento"
  $logo.Font = $fonts.title
  $logo.ForeColor = HexColor $colors.primary
  $logo.Size = New-Object System.Drawing.Size(600, 45)
  $logo.Location = New-Object System.Drawing.Point(40, 30)
  $logo.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($logo)

  $sub = New-Object System.Windows.Forms.Label
  $sub.Text = "Painel de agendamento para clientes — Instalador Windows"
  $sub.Font = $fonts.small
  $sub.ForeColor = HexColor $colors.sub
  $sub.Size = New-Object System.Drawing.Size(600, 22)
  $sub.Location = New-Object System.Drawing.Point(40, 80)
  $sub.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($sub)

  $infos = @(
    "Agendamento online para os clientes do seu sala",
    "Conecta ao BeautyFlow CRM (porta 3001)",
    "",
    "Escolha o metodo de instalacao:"
  )
  $y = 130
  foreach ($line in $infos) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $line
    $l.Font = $fonts.body
    $l.ForeColor = HexColor $colors.white
    $l.Size = New-Object System.Drawing.Size(560, 22)
    $l.Location = New-Object System.Drawing.Point(60, $y)
    $panelMain.Controls.Add($l)
    $y += 24
  }
  $y += 15

  $btnDocker = New-Object System.Windows.Forms.Button
  $btnDocker.Text = "  Docker (Recomendado)`n  Build + nginx em container"
  $btnDocker.Font = $fonts.body
  $btnDocker.Size = New-Object System.Drawing.Size(500, 60)
  $btnDocker.Location = New-Object System.Drawing.Point(80, $y)
  $btnDocker.BackColor = HexColor $colors.card
  $btnDocker.ForeColor = HexColor $colors.white
  $btnDocker.FlatStyle = "Flat"
  $btnDocker.FlatAppearance.BorderSize = 1
  $btnDocker.FlatAppearance.BorderColor = HexColor $colors.primary
  $btnDocker.TextAlign = "MiddleLeft"
  $btnDocker.Add_Click({ Show-DockerCheck })
  $panelMain.Controls.Add($btnDocker)

  $y += 75

  $btnNode = New-Object System.Windows.Forms.Button
  $btnNode.Text = "  Node.js Nativo`n  npm install + npm run dev"
  $btnNode.Font = $fonts.body
  $btnNode.Size = New-Object System.Drawing.Size(500, 60)
  $btnNode.Location = New-Object System.Drawing.Point(80, $y)
  $btnNode.BackColor = HexColor $colors.card
  $btnNode.ForeColor = HexColor $colors.white
  $btnNode.FlatStyle = "Flat"
  $btnNode.FlatAppearance.BorderSize = 1
  $btnNode.FlatAppearance.BorderColor = HexColor $colors.sub
  $btnNode.TextAlign = "MiddleLeft"
  $btnNode.Add_Click({ Show-NodeCheck })
  $panelMain.Controls.Add($btnNode)
}

function Show-DockerCheck {
  $panelMain.Controls.Clear()
  Add-Title "Docker — Verificando dependencias"
  Add-Spacer

  $step1 = Add-Step "Verificando Docker Desktop..."
  $step2 = Add-Step "Clonando repositorio..."
  $step3 = Add-Step "Build da imagem..."
  $step4 = Add-Step "Iniciando container..."

  $step1.Set("Verificando...", $colors.warning)

  $dockerOk = (Get-Command "docker" -ErrorAction SilentlyContinue) -ne $null
  if (-not $dockerOk) {
    $step1.Set("Docker Desktop nao encontrado", "#c05050")
    Add-Spacer
    $l = New-Object System.Windows.Forms.Label
    $l.Text = "Docker Desktop e necessario."
    $l.Font = $fonts.body; $l.ForeColor = HexColor $colors.white
    $l.Size = New-Object System.Drawing.Size(560, 22)
    $l.Location = New-Object System.Drawing.Point(60, ($panelMain.Controls | % { $_.Location.Y + $_.Size.Height } | Measure -Max | % { $_.Maximum + 10 }))
    $panelMain.Controls.Add($l)

    $link = New-Object System.Windows.Forms.LinkLabel
    $link.Text = "Clique aqui para baixar Docker Desktop"
    $link.Font = $fonts.body; $link.LinkColor = HexColor $colors.primary
    $link.Size = New-Object System.Drawing.Size(450, 22)
    $link.Location = New-Object System.Drawing.Point(60, $l.Location.Y + 28)
    $link.Add_Click({ [System.Diagnostics.Process]::Start("https://docs.docker.com/desktop/setup/install/windows-install/") })
    $panelMain.Controls.Add($link)

    $btnRetry = New-Object System.Windows.Forms.Button
    $btnRetry.Text = "  Ja instalei! Verificar"
    $btnRetry.Font = $fonts.body; $btnRetry.Size = New-Object System.Drawing.Size(250, 40)
    $btnRetry.Location = New-Object System.Drawing.Point(80, $link.Location.Y + 40)
    $btnRetry.BackColor = HexColor $colors.primary; $btnRetry.ForeColor = "White"
    $btnRetry.FlatStyle = "Flat"
    $btnRetry.Add_Click({ Show-DockerCheck })
    $panelMain.Controls.Add($btnRetry)
    return
  }
  $step1.Set("OK $(docker --version)", $colors.success)
  $form.Refresh()
  Start-Sleep -Milliseconds 200

  # Clonar
  $step2.Set("Clonando repositorio...", $colors.warning)
  $form.Refresh()
  if (Test-Path $REPO_DIR) { Remove-Item -Recurse -Force $REPO_DIR -ErrorAction SilentlyContinue }
  git clone $REPO_URL $REPO_DIR 2>&1 | Out-Null
  $step2.Set("OK repositorio clonado", $colors.success)
  $form.Refresh()

  # Build
  $step3.Set("Build da imagem...", $colors.warning)
  $form.Refresh()
  Push-Location $INST_DIR
  docker compose build 2>&1 | Out-Null
  Pop-Location
  $step3.Set("OK imagem criada", $colors.success)
  $form.Refresh()

  # Iniciar
  $step4.Set("Iniciando container...", $colors.warning)
  $form.Refresh()
  Push-Location $INST_DIR
  docker compose up -d 2>&1 | Out-Null
  Pop-Location
  $step4.Set("OK container rodando", $colors.success)

  Add-Spacer; Add-Spacer
  Show-Final "http://localhost:5173"
}

function Show-NodeCheck {
  $panelMain.Controls.Clear()
  Add-Title "Node.js — Verificando dependencias"
  Add-Spacer

  $step1 = Add-Step "Verificando Node.js..."
  $step2 = Add-Step "Clonando repositorio..."
  $step3 = Add-Step "Instalando dependencias npm..."
  $step4 = Add-Step "Build..."

  $step1.Set("Verificando...", $colors.warning)

  $nodeOk = (Get-Command "node" -ErrorAction SilentlyContinue) -ne $null
  if (-not $nodeOk) {
    $step1.Set("Node.js nao encontrado", "#c05050")
    Add-Spacer
    $l = New-Object System.Windows.Forms.Label
    $l.Text = "Node.js e necessario. Deseja baixar e instalar?"
    $l.Font = $fonts.body; $l.ForeColor = HexColor $colors.white
    $l.Size = New-Object System.Drawing.Size(560, 22)
    $l.Location = New-Object System.Drawing.Point(60, ($panelMain.Controls | % { $_.Location.Y + $_.Size.Height } | Measure -Max | % { $_.Maximum + 10 }))
    $panelMain.Controls.Add($l)

    $link = New-Object System.Windows.Forms.LinkLabel
    $link.Text = "Clique aqui para baixar Node.js LTS"
    $link.Font = $fonts.body; $link.LinkColor = HexColor $colors.primary
    $link.Size = New-Object System.Drawing.Size(400, 22)
    $link.Location = New-Object System.Drawing.Point(60, $l.Location.Y + 28)
    $link.Add_Click({ [System.Diagnostics.Process]::Start("https://nodejs.org") })
    $panelMain.Controls.Add($link)

    $btnRetry = New-Object System.Windows.Forms.Button
    $btnRetry.Text = "  Ja instalei! Verificar"
    $btnRetry.Font = $fonts.body; $btnRetry.Size = New-Object System.Drawing.Size(250, 40)
    $btnRetry.Location = New-Object System.Drawing.Point(80, $link.Location.Y + 40)
    $btnRetry.BackColor = HexColor $colors.primary; $btnRetry.ForeColor = "White"
    $btnRetry.FlatStyle = "Flat"
    $btnRetry.Add_Click({ Show-NodeCheck })
    $panelMain.Controls.Add($btnRetry)
    return
  }
  $step1.Set("OK Node.js $(node --version)", $colors.success)
  $form.Refresh()
  Start-Sleep -Milliseconds 200

  # Clonar
  $step2.Set("Clonando repositorio...", $colors.warning)
  $form.Refresh()
  if (Test-Path $REPO_DIR) { Remove-Item -Recurse -Force $REPO_DIR -ErrorAction SilentlyContinue }
  git clone $REPO_URL $REPO_DIR 2>&1 | Out-Null
  $step2.Set("OK repositorio clonado", $colors.success)
  $form.Refresh()

  # npm install
  $step3.Set("Instalando dependencias...", $colors.warning)
  $form.Refresh()
  Push-Location $APP_DIR
  npm install --silent 2>&1 | Out-Null
  Pop-Location
  $step3.Set("OK dependencias instaladas", $colors.success)
  $form.Refresh()

  # Build
  $step4.Set("Build de producao...", $colors.warning)
  $form.Refresh()
  Push-Location $APP_DIR
  npx vite build --silent 2>&1 | Out-Null
  Pop-Location
  $step4.Set("OK build concluido (dist/)", $colors.success)

  # Iniciar server
  Push-Location $APP_DIR
  Start-Process -NoNewWindow -FilePath "npm" -ArgumentList "run dev" 2>$null
  Pop-Location

  Add-Spacer; Add-Spacer
  Show-Final "http://localhost:5173"
}

function Show-Final($url) {
  $panelMain.Controls.Clear()

  $check = New-Object System.Windows.Forms.Label
  $check.Text = "OK"
  $check.Font = New-Object System.Drawing.Font("Segoe UI", 42, [System.Drawing.FontStyle]::Bold)
  $check.ForeColor = HexColor $colors.success
  $check.Size = New-Object System.Drawing.Size(600, 60)
  $check.Location = New-Object System.Drawing.Point(40, 30)
  $check.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($check)

  $title = New-Object System.Windows.Forms.Label
  $title.Text = "Instalacao concluida!"
  $title.Font = $fonts.header
  $title.ForeColor = HexColor $colors.white
  $title.Size = New-Object System.Drawing.Size(600, 30)
  $title.Location = New-Object System.Drawing.Point(40, 95)
  $title.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($title)

  Add-Spacer

  $l1 = New-Object System.Windows.Forms.Label
  $l1.Text = "Agendamento disponivel em:"
  $l1.Font = $fonts.body; $l1.ForeColor = HexColor $colors.sub
  $l1.Size = New-Object System.Drawing.Size(560, 22)
  $l1.Location = New-Object System.Drawing.Point(60, ($panelMain.Controls | % { $_.Location.Y + $_.Size.Height } | Measure -Max | % { $_.Maximum + 10 }))
  $l1.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($l1)

  $urlBox = New-Object System.Windows.Forms.TextBox
  $urlBox.Text = $url
  $urlBox.Font = $fonts.mono; $urlBox.ForeColor = HexColor $colors.primary
  $urlBox.BackColor = HexColor $colors.card
  $urlBox.Size = New-Object System.Drawing.Size(360, 30)
  $urlBox.Location = New-Object System.Drawing.Point(140, $l1.Location.Y + 35)
  $urlBox.TextAlign = "MiddleCenter"; $urlBox.ReadOnly = $true
  $urlBox.BorderStyle = "FixedSingle"
  $panelMain.Controls.Add($urlBox)

  $btnCopy = New-Object System.Windows.Forms.Button
  $btnCopy.Text = "Copiar"
  $btnCopy.Font = $fonts.small; $btnCopy.Size = New-Object System.Drawing.Size(70, 28)
  $btnCopy.Location = New-Object System.Drawing.Point(510, $l1.Location.Y + 35)
  $btnCopy.BackColor = HexColor $colors.primary; $btnCopy.ForeColor = "White"
  $btnCopy.FlatStyle = "Flat"
  $btnCopy.Add_Click({ [System.Windows.Forms.Clipboard]::SetText($url); $btnCopy.Text = "Copiado!"; Start-Sleep 1; $btnCopy.Text = "Copiar" })
  $panelMain.Controls.Add($btnCopy)

  $btnOpen = New-Object System.Windows.Forms.Button
  $btnOpen.Text = "  Abrir no navegador"
  $btnOpen.Font = $fonts.body; $btnOpen.Size = New-Object System.Drawing.Size(300, 45)
  $btnOpen.Location = New-Object System.Drawing.Point(150, $l1.Location.Y + 85)
  $btnOpen.BackColor = HexColor $colors.success; $btnOpen.ForeColor = "White"
  $btnOpen.FlatStyle = "Flat"
  $btnOpen.Add_Click({ [System.Diagnostics.Process]::Start($url) })
  $panelMain.Controls.Add($btnOpen)

  Add-Spacer

  $l2 = New-Object System.Windows.Forms.Label
  $l2.Text = "ATENCAO: O CRM (porta 3001) precisa estar rodando!"
  $l2.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
  $l2.ForeColor = HexColor $colors.warning
  $l2.Size = New-Object System.Drawing.Size(560, 22)
  $l2.Location = New-Object System.Drawing.Point(60, ($panelMain.Controls | % { $_.Location.Y + $_.Size.Height } | Measure -Max | % { $_.Maximum + 10 }))
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
$form.Text = "BeautyFlow Agendamento - Instalador Windows"
$form.Size = New-Object System.Drawing.Size(680, 540)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = HexColor $colors.bg

$panelMain = New-Object System.Windows.Forms.Panel
$panelMain.Size = New-Object System.Drawing.Size(680, 500)
$panelMain.Location = New-Object System.Drawing.Point(0, 0)
$panelMain.BackColor = HexColor $colors.bg
$form.Controls.Add($panelMain)

$winVer = (Get-CimInstance Win32_OperatingSystem).Caption
$footer = New-Object System.Windows.Forms.Label
$footer.Text = "$winVer  |  BeautyFlow Agendamento v1.0"
$footer.Font = $fonts.small; $footer.ForeColor = HexColor $colors.sub
$footer.Size = New-Object System.Drawing.Size(660, 20)
$footer.Location = New-Object System.Drawing.Point(10, 505)
$form.Controls.Add($footer)

Show-Welcome
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
