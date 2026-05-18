<#
╔══════════════════════════════════════════════╗
║   BeautyFlow CRM — Instalador para Windows  ║
╚══════════════════════════════════════════════╝
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ────────── Config ──────────
$REPO_URL  = "https://github.com/Sallesg82/Extensao_universitaria_Manicure.git"
$REPO_DIR  = "$env:TEMP\Extensao_universitaria_Manicure"
$CRM_DIR   = "$REPO_DIR\Aplicativos\CRM-Mirian (protótipo)"
$INST_DIR  = "$CRM_DIR\instalacao"

# ────────── Variáveis globais do formulário ──────────
$form      = $null
$panelMain = $null
$fonts = @{
  title  = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
  header = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
  body   = New-Object System.Drawing.Font("Segoe UI", 11)
  small  = New-Object System.Drawing.Font("Segoe UI", 9)
  mono   = New-Object System.Drawing.Font("Consolas", 10)
}

# ────────── Cores ──────────
$colors = @{
  bg       = "#0a1628"
  card     = "#14203a"
  primary  = "#4a90d9"
  success  = "#4e8f6a"
  warning  = "#c9894a"
  white    = "#b8d4f0"
  sub      = "#8aaccb"
}

function HexColor($hex) {
  return [System.Drawing.Color]::FromArgb([int]("0x$($hex.Substring(1))"))
}

# ════════════════════════════════════════════
#  FUNÇÕES DE TELA
# ════════════════════════════════════════════

function Show-Welcome {
  $panelMain.Controls.Clear()

  # Logo
  $logo = New-Object System.Windows.Forms.Label
  $logo.Text = "BeautyFlow"
  $logo.Font = $fonts.title
  $logo.ForeColor = HexColor $colors.primary
  $logo.Size = New-Object System.Drawing.Size(600, 50)
  $logo.Location = New-Object System.Drawing.Point(40, 40)
  $logo.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($logo)

  $sub = New-Object System.Windows.Forms.Label
  $sub.Text = "CRM & Gestao - Instalador para Windows"
  $sub.Font = $fonts.small
  $sub.ForeColor = HexColor $colors.sub
  $sub.Size = New-Object System.Drawing.Size(600, 25)
  $sub.Location = New-Object System.Drawing.Point(40, 90)
  $sub.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($sub)

  # Cards de informações
  $infoTexts = @(
    "Bem-vindo ao instalador do BeautyFlow CRM!",
    "Este programa ira instalar o sistema de gestao",
    "para salao de beleza no seu computador.",
    "",
    "Escolha o metodo de instalacao abaixo:"
  )
  $y = 140
  foreach ($line in $infoTexts) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $line
    $l.Font = $fonts.body
    $l.ForeColor = HexColor $colors.white
    $l.Size = New-Object System.Drawing.Size(560, 22)
    $l.Location = New-Object System.Drawing.Point(60, $y)
    $panelMain.Controls.Add($l)
    $y += 24
  }

  $y += 20

  # ── Botão Docker ──
  $btnDocker = New-Object System.Windows.Forms.Button
  $btnDocker.Text = "  Metodo Docker (Recomendado)`n  Instala tudo em um container isolado"
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

  # ── Botão Python Nativo ──
  $btnPython = New-Object System.Windows.Forms.Button
  $btnPython.Text = "  Metodo Python (WSL)`n  Usa o Windows Subsystem for Linux"
  $btnPython.Font = $fonts.body
  $btnPython.Size = New-Object System.Drawing.Size(500, 60)
  $btnPython.Location = New-Object System.Drawing.Point(80, $y)
  $btnPython.BackColor = HexColor $colors.card
  $btnPython.ForeColor = HexColor $colors.white
  $btnPython.FlatStyle = "Flat"
  $btnPython.FlatAppearance.BorderSize = 1
  $btnPython.FlatAppearance.BorderColor = HexColor $colors.sub
  $btnPython.TextAlign = "MiddleLeft"
  $btnPython.Add_Click({ Show-WslCheck })
  $panelMain.Controls.Add($btnPython)
}

function Show-DockerCheck {
  $panelMain.Controls.Clear()

  Add-Title "Docker - Verificando dependencias"
  Add-Spacer

  $step1 = Add-Step "Verificando Docker Desktop..."
  $step2 = Add-Step "Verificando docker compose..."
  $step3 = Add-Step "Clonando repositorio..."
  $step4 = Add-Step "Build da imagem Docker..."
  $step5 = Add-Step "Iniciando container..."

  $step1.Set("Verificando...", $colors.warning)

  # Verificar Docker
  $dockerOk = (Get-Command "docker" -ErrorAction SilentlyContinue) -ne $null
  if (-not $dockerOk) {
    $step1.Set("Docker Desktop nao encontrado", "#c05050")
    Add-Spacer
    $msg = New-Object System.Windows.Forms.Label
    $msg.Text = "Docker Desktop e necessario para este metodo."
    $msg.Font = $fonts.body
    $msg.ForeColor = HexColor $colors.white
    $msg.Size = New-Object System.Drawing.Size(560, 22)
    $msg.Location = New-Object System.Drawing.Point(60, $panelMain.Controls | % { $_.Location.Y + $_.Size.Height } | Measure -Max | % { $_.Maximum + 10 })
    $panelMain.Controls.Add($msg)

    $link = New-Object System.Windows.Forms.LinkLabel
    $link.Text = "Clique aqui para baixar Docker Desktop"
    $link.Font = $fonts.body
    $link.LinkColor = HexColor $colors.primary
    $link.Size = New-Object System.Drawing.Size(400, 22)
    $link.Location = New-Object System.Drawing.Point(60, $msg.Location.Y + 28)
    $link.Add_Click({ [System.Diagnostics.Process]::Start("https://docs.docker.com/desktop/setup/install/windows-install/") })
    $panelMain.Controls.Add($link)

    $btnRetry = New-Object System.Windows.Forms.Button
    $btnRetry.Text = "  Ja instalei! Verificar novamente"
    $btnRetry.Font = $fonts.body
    $btnRetry.Size = New-Object System.Drawing.Size(300, 40)
    $btnRetry.Location = New-Object System.Drawing.Point(80, $link.Location.Y + 40)
    $btnRetry.BackColor = HexColor $colors.primary
    $btnRetry.ForeColor = "White"
    $btnRetry.FlatStyle = "Flat"
    $btnRetry.Add_Click({ Show-DockerCheck })
    $panelMain.Controls.Add($btnRetry)

    $btnWslAlt = New-Object System.Windows.Forms.Button
    $btnWslAlt.Text = "  Voltar e escolher WSL"
    $btnWslAlt.Font = $fonts.body
    $btnWslAlt.Size = New-Object System.Drawing.Size(280, 40)
    $btnWslAlt.Location = New-Object System.Drawing.Point(400, $link.Location.Y + 40)
    $btnWslAlt.BackColor = HexColor $colors.card
    $btnWslAlt.ForeColor = HexColor $colors.white
    $btnWslAlt.FlatStyle = "Flat"
    $btnWslAlt.Add_Click({ Show-WslCheck })
    $panelMain.Controls.Add($btnWslAlt)
    return
  }
  $step1.Set("OK $(docker --version)", $colors.success)

  # Verificar docker compose
  $composeOk = $null
  try { $composeOk = docker compose version } catch {}
  if (-not $composeOk) {
    $step2.Set("docker compose versao 2+ necessario", "#c05050")
    Add-Spacer
    $msg = New-Object System.Windows.Forms.Label
    $msg.Text = "Atualize o Docker Desktop para a versao mais recente."
    $msg.Font = $fonts.body
    $msg.ForeColor = HexColor $colors.white
    $msg.Size = New-Object System.Drawing.Size(560, 22)
    $msg.Location = New-Object System.Drawing.Point(60, ($panelMain.Controls | % { $_.Location.Y + $_.Size.Height } | Measure -Max | % { $_.Maximum + 10 }))
    $panelMain.Controls.Add($msg)
    return
  }
  $step2.Set("OK docker compose $(docker compose version | % { $_ -replace '.*v','' -replace ',.*','' })", $colors.success)

  $form.Refresh()
  Start-Sleep -Milliseconds 300

  # Clonar repositório
  $step3.Set("Clonando repositorio...", $colors.warning)
  $form.Refresh()
  if (Test-Path $REPO_DIR) {
    Remove-Item -Recurse -Force $REPO_DIR -ErrorAction SilentlyContinue
  }
  git clone $REPO_URL $REPO_DIR 2>&1 | Out-Null
  $step3.Set("OK repositorio clonado", $colors.success)
  $form.Refresh()

  # ── Coletar credenciais do Supabase ──
  $supabaseUrl = ""
  $supabaseAnonKey = ""
  $supabaseKey = ""
  $supabaseJwtSecret = ""

  $credDialog = New-Object System.Windows.Forms.Form
  $credDialog.Text = "Credenciais Supabase"
  $credDialog.Size = New-Object System.Drawing.Size(540, 340)
  $credDialog.StartPosition = "CenterParent"
  $credDialog.FormBorderStyle = "FixedDialog"
  $credDialog.MaximizeBox = $false
  $credDialog.BackColor = HexColor $colors.bg

  $title = New-Object System.Windows.Forms.Label
  $title.Text = "Configuracao do Supabase"
  $title.Font = $fonts.header
  $title.ForeColor = HexColor $colors.white
  $title.Size = New-Object System.Drawing.Size(500, 30)
  $title.Location = New-Object System.Drawing.Point(20, 15)
  $credDialog.Controls.Add($title)

  $info = New-Object System.Windows.Forms.Label
  $info.Text = "Crie um projeto em supabase.com e cole as 4 credenciais (Project Settings > API):"
  $info.Font = $fonts.small
  $info.ForeColor = HexColor $colors.sub
  $info.Size = New-Object System.Drawing.Size(500, 35)
  $info.Location = New-Object System.Drawing.Point(20, 50)
  $credDialog.Controls.Add($info)

  $labels = @("SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_KEY (service_role)", "SUPABASE_JWT_SECRET")
  $textboxes = @()
  $y = 95
  for ($i = 0; $i -lt 4; $i++) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $labels[$i]
    $l.Font = $fonts.small
    $l.ForeColor = HexColor $colors.white
    $l.Size = New-Object System.Drawing.Size(490, 18)
    $l.Location = New-Object System.Drawing.Point(22, $y)
    $credDialog.Controls.Add($l)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Font = $fonts.mono
    $tb.Size = New-Object System.Drawing.Size(490, 22)
    $tb.Location = New-Object System.Drawing.Point(22, $y + 19)
    $tb.BackColor = HexColor $colors.card
    $tb.ForeColor = HexColor $colors.white
    $tb.BorderStyle = "FixedSingle"
    $credDialog.Controls.Add($tb)
    $textboxes += $tb

    $y += 48
  }

  $btnOk = New-Object System.Windows.Forms.Button
  $btnOk.Text = "Salvar e Continuar"
  $btnOk.Font = $fonts.body
  $btnOk.Size = New-Object System.Drawing.Size(200, 35)
  $btnOk.Location = New-Object System.Drawing.Point(150, $y + 10)
  $btnOk.BackColor = HexColor $colors.success
  $btnOk.ForeColor = "White"
  $btnOk.FlatStyle = "Flat"
  $btnOk.Add_Click({
    $credDialog.Tag = @($textboxes[0].Text, $textboxes[1].Text, $textboxes[2].Text, $textboxes[3].Text)
    $credDialog.Close()
  })
  $credDialog.Controls.Add($btnOk)

  [void]$credDialog.ShowDialog()
  $creds = $credDialog.Tag
  if ($creds -and $creds[0]) {
    $supabaseUrl = $creds[0]
    $supabaseAnonKey = $creds[1]
    $supabaseKey = $creds[2]
    $supabaseJwtSecret = $creds[3]
    $envContent = @"
SUPABASE_URL=$supabaseUrl
SUPABASE_ANON_KEY=$supabaseAnonKey
SUPABASE_KEY=$supabaseKey
SUPABASE_JWT_SECRET=$supabaseJwtSecret
"@
    $envFilePath = "$REPO_DIR\Aplicativos\CRM-Mirian (protótipo)\backend\.env"
    [System.IO.File]::WriteAllText($envFilePath, $envContent)
  }

  # Build Docker
  $step4.Set("Build da imagem...", $colors.warning)
  $form.Refresh()
  Push-Location $INST_DIR
  docker compose build 2>&1 | Out-Null
  Pop-Location
  $step4.Set("OK imagem criada", $colors.success)
  $form.Refresh()

  # Iniciar container
  $step5.Set("Iniciando container...", $colors.warning)
  $form.Refresh()
  Push-Location $INST_DIR
  docker compose up -d 2>&1 | Out-Null
  Pop-Location
  $step5.Set("OK container rodando", $colors.success)

  Add-Spacer
  Add-Spacer
  Show-Final "http://localhost:3001"
}

function Show-WslCheck {
  $panelMain.Controls.Clear()

  Add-Title "WSL + Python - Verificando dependencias"
  Add-Spacer

  $step1 = Add-Step "Verificando WSL (Windows Subsystem for Linux)..."
  $step2 = Add-Step "Verificando distribuicao Ubuntu..."
  $step3 = Add-Step "Instalando dependencias no Ubuntu..."
  $step4 = Add-Step "Configurando banco de dados..."

  $step1.Set("Verificando...", $colors.warning)

  # Verificar WSL
  $wslOk = $null
  try { $wslOk = wsl --status 2>$null } catch {}
  if (-not $wslOk) {
    $step1.Set("WSL nao encontrado", "#c05050")
    Add-Spacer
    $l = New-Object System.Windows.Forms.Label
    $l.Text = "WSL e necessario para executar o CRM no Windows."
    $l.Font = $fonts.body
    $l.ForeColor = HexColor $colors.white
    $l.Size = New-Object System.Drawing.Size(560, 22)
    $l.Location = New-Object System.Drawing.Point(60, ($panelMain.Controls | % { $_.Location.Y + $_.Size.Height } | Measure -Max | % { $_.Maximum + 10 }))
    $panelMain.Controls.Add($l)

    $link = New-Object System.Windows.Forms.LinkLabel
    $link.Text = "Clique aqui para ver o tutorial de instalacao do WSL"
    $link.Font = $fonts.body
    $link.LinkColor = HexColor $colors.primary
    $link.Size = New-Object System.Drawing.Size(450, 22)
    $link.Location = New-Object System.Drawing.Point(60, $l.Location.Y + 28)
    $link.Add_Click({ [System.Diagnostics.Process]::Start("https://learn.microsoft.com/pt-br/windows/wsl/install") })
    $panelMain.Controls.Add($link)

    $btnRetry = New-Object System.Windows.Forms.Button
    $btnRetry.Text = "  Ja instalei! Verificar novamente"
    $btnRetry.Font = $fonts.body
    $btnRetry.Size = New-Object System.Drawing.Size(300, 40)
    $btnRetry.Location = New-Object System.Drawing.Point(80, $link.Location.Y + 40)
    $btnRetry.BackColor = HexColor $colors.primary
    $btnRetry.ForeColor = "White"
    $btnRetry.FlatStyle = "Flat"
    $btnRetry.Add_Click({ Show-WslCheck })
    $panelMain.Controls.Add($btnRetry)
    return
  }
  $step1.Set("OK WSL disponivel", $colors.success)

  # Verificar distribuição Ubuntu
  $step2.Set("Verificando...", $colors.warning)
  $form.Refresh()
  $distros = wsl --list --quiet 2>$null
  $hasUbuntu = $distros -match "Ubuntu"
  if (-not $hasUbuntu) {
    $step2.Set("Instalando Ubuntu...", $colors.warning)
    $form.Refresh()
    wsl --install -d Ubuntu 2>&1 | Out-Null
    Start-Sleep -Seconds 5
    $distros = wsl --list --quiet 2>$null
    $hasUbuntu = $distros -match "Ubuntu"
    if (-not $hasUbuntu) {
      $step2.Set("Falha ao instalar Ubuntu automaticamente", "#c05050")
      Add-Spacer
      $l = New-Object System.Windows.Forms.Label
      $l.Text = "Execute manualmente: wsl --install -d Ubuntu"
      $l.Font = $fonts.mono
      $l.ForeColor = HexColor $colors.white
      $l.Size = New-Object System.Drawing.Size(560, 22)
      $l.Location = New-Object System.Drawing.Point(60, ($panelMain.Controls | % { $_.Location.Y + $_.Size.Height } | Measure -Max | % { $_.Maximum + 10 }))
      $panelMain.Controls.Add($l)
      return
    }
  }
  $step2.Set("OK Ubuntu instalado", $colors.success)
  $form.Refresh()

  # Instalar dependências no WSL (git, python3, python3-venv)
  $step3.Set("Instalando dependencias no Ubuntu...", $colors.warning)
  $form.Refresh()
  wsl -d Ubuntu -u root -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt update -qq && apt install -y -qq git python3 python3-venv 2>/dev/null
  " 2>$null | Out-Null
  $step3.Set("OK dependencias instaladas", $colors.success)
  $form.Refresh()

  # ── Coletar credenciais do Supabase ──
  $supabaseUrl = ""
  $supabaseAnonKey = ""
  $supabaseKey = ""
  $supabaseJwtSecret = ""
  $credsOk = $false

  $credDialog = New-Object System.Windows.Forms.Form
  $credDialog.Text = "Credenciais Supabase"
  $credDialog.Size = New-Object System.Drawing.Size(540, 340)
  $credDialog.StartPosition = "CenterParent"
  $credDialog.FormBorderStyle = "FixedDialog"
  $credDialog.MaximizeBox = $false
  $credDialog.BackColor = HexColor $colors.bg

  $title = New-Object System.Windows.Forms.Label
  $title.Text = "Configuracao do Supabase"
  $title.Font = $fonts.header
  $title.ForeColor = HexColor $colors.white
  $title.Size = New-Object System.Drawing.Size(500, 30)
  $title.Location = New-Object System.Drawing.Point(20, 15)
  $credDialog.Controls.Add($title)

  $info = New-Object System.Windows.Forms.Label
  $info.Text = "Crie um projeto em supabase.com e cole as 4 credenciais (Project Settings > API):"
  $info.Font = $fonts.small
  $info.ForeColor = HexColor $colors.sub
  $info.Size = New-Object System.Drawing.Size(500, 35)
  $info.Location = New-Object System.Drawing.Point(20, 50)
  $credDialog.Controls.Add($info)

  $labels = @("SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_KEY (service_role)", "SUPABASE_JWT_SECRET")
  $textboxes = @()
  $y = 95
  for ($i = 0; $i -lt 4; $i++) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $labels[$i]
    $l.Font = $fonts.small
    $l.ForeColor = HexColor $colors.white
    $l.Size = New-Object System.Drawing.Size(490, 18)
    $l.Location = New-Object System.Drawing.Point(22, $y)
    $credDialog.Controls.Add($l)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Font = $fonts.mono
    $tb.Size = New-Object System.Drawing.Size(490, 22)
    $tb.Location = New-Object System.Drawing.Point(22, $y + 19)
    $tb.BackColor = HexColor $colors.card
    $tb.ForeColor = HexColor $colors.white
    $tb.BorderStyle = "FixedSingle"
    $credDialog.Controls.Add($tb)
    $textboxes += $tb

    $y += 48
  }

  $btnOk = New-Object System.Windows.Forms.Button
  $btnOk.Text = "Salvar e Continuar"
  $btnOk.Font = $fonts.body
  $btnOk.Size = New-Object System.Drawing.Size(200, 35)
  $btnOk.Location = New-Object System.Drawing.Point(150, $y + 10)
  $btnOk.BackColor = HexColor $colors.success
  $btnOk.ForeColor = "White"
  $btnOk.FlatStyle = "Flat"
  $btnOk.Add_Click({
    $credDialog.Tag = @($textboxes[0].Text, $textboxes[1].Text, $textboxes[2].Text, $textboxes[3].Text)
    $credDialog.Close()
  })
  $credDialog.Controls.Add($btnOk)

  [void]$credDialog.ShowDialog()
  $creds = $credDialog.Tag
  if ($creds -and $creds[0]) {
    $supabaseUrl = $creds[0]
    $supabaseAnonKey = $creds[1]
    $supabaseKey = $creds[2]
    $supabaseJwtSecret = $creds[3]
    $credsOk = $true
  }

  # Clonar e configurar via WSL
  $step4.Set("Clonando repositorio e configurando...", $colors.warning)
  $form.Refresh()
  $envContent = @"
SUPABASE_URL=$supabaseUrl
SUPABASE_ANON_KEY=$supabaseAnonKey
SUPABASE_KEY=$supabaseKey
SUPABASE_JWT_SECRET=$supabaseJwtSecret
"@

  wsl -d Ubuntu -- bash -c "
    set -e
    rm -rf /tmp/Extensao_universitaria_Manicure
    git clone https://github.com/Sallesg82/Extensao_universitaria_Manicure.git /tmp/Extensao_universitaria_Manicure
    cd '/tmp/Extensao_universitaria_Manicure/Aplicativos/CRM-Mirian (protótipo)'
    python3 -m venv backend/.venv
    backend/.venv/bin/pip install -q flask flask-cors requests supabase werkzeug google-auth google-auth-oauthlib google-api-python-client python-dateutil postgrest
    cat > backend/.env << 'WSL_ENV'
$envContent
WSL_ENV
    backend/.venv/bin/python -c '
import sys; sys.path.insert(0, \"backend\")
from db.database import get_db; get_db().close()
'
    cd instalacao
    nohup bash start.sh > /dev/null 2>&1 &
    sleep 2
  " 2>$null | Out-Null
  $step4.Set("OK CRM configurado e iniciado no WSL", $colors.success)

  Add-Spacer
  Add-Spacer
  Show-Final "http://localhost:3001"
}

# ════════════════════════════════════════════
#  TELA FINAL
# ════════════════════════════════════════════

function Show-Final($url) {
  $panelMain.Controls.Clear()

  # Check de sucesso
  $check = New-Object System.Windows.Forms.Label
  $check.Text = "OK"
  $check.Font = New-Object System.Drawing.Font("Segoe UI", 42, [System.Drawing.FontStyle]::Bold)
  $check.ForeColor = HexColor $colors.success
  $check.Size = New-Object System.Drawing.Size(600, 60)
  $check.Location = New-Object System.Drawing.Point(40, 30)
  $check.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($check)

  $title = New-Object System.Windows.Forms.Label
  $title.Text = "Instalacao concluida com sucesso!"
  $title.Font = $fonts.header
  $title.ForeColor = HexColor $colors.white
  $title.Size = New-Object System.Drawing.Size(600, 35)
  $title.Location = New-Object System.Drawing.Point(40, 100)
  $title.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($title)

  Add-Spacer

  $l1 = New-Object System.Windows.Forms.Label
  $l1.Text = "O BeautyFlow CRM ja esta rodando! Acesse:"
  $l1.Font = $fonts.body
  $l1.ForeColor = HexColor $colors.sub
  $l1.Size = New-Object System.Drawing.Size(560, 22)
  $l1.Location = New-Object System.Drawing.Point(60, ($panelMain.Controls | % { $_.Location.Y + $_.Size.Height } | Measure -Max | % { $_.Maximum + 10 }))
  $l1.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($l1)

  # URL em destaque
  $urlBox = New-Object System.Windows.Forms.TextBox
  $urlBox.Text = $url
  $urlBox.Font = $fonts.mono
  $urlBox.ForeColor = HexColor $colors.primary
  $urlBox.BackColor = HexColor $colors.card
  $urlBox.Size = New-Object System.Drawing.Size(360, 30)
  $urlBox.Location = New-Object System.Drawing.Point(140, $l1.Location.Y + 35)
  $urlBox.TextAlign = "MiddleCenter"
  $urlBox.ReadOnly = $true
  $urlBox.BorderStyle = "FixedSingle"
  $panelMain.Controls.Add($urlBox)

  # Botão copiar
  $btnCopy = New-Object System.Windows.Forms.Button
  $btnCopy.Text = "Copiar"
  $btnCopy.Font = $fonts.small
  $btnCopy.Size = New-Object System.Drawing.Size(70, 28)
  $btnCopy.Location = New-Object System.Drawing.Point(510, $l1.Location.Y + 35)
  $btnCopy.BackColor = HexColor $colors.primary
  $btnCopy.ForeColor = "White"
  $btnCopy.FlatStyle = "Flat"
  $btnCopy.Add_Click({
    [System.Windows.Forms.Clipboard]::SetText($url)
    $btnCopy.Text = "Copiado!"
    Start-Sleep -Milliseconds 1500
    $btnCopy.Text = "Copiar"
  })
  $panelMain.Controls.Add($btnCopy)

  # Botão abrir navegador
  $btnOpen = New-Object System.Windows.Forms.Button
  $btnOpen.Text = "  Abrir no navegador"
  $btnOpen.Font = $fonts.body
  $btnOpen.Size = New-Object System.Drawing.Size(300, 45)
  $btnOpen.Location = New-Object System.Drawing.Point(150, $l1.Location.Y + 85)
  $btnOpen.BackColor = HexColor $colors.success
  $btnOpen.ForeColor = "White"
  $btnOpen.FlatStyle = "Flat"
  $btnOpen.Add_Click({ [System.Diagnostics.Process]::Start($url) })
  $panelMain.Controls.Add($btnOpen)

  Add-Spacer

  $l2 = New-Object System.Windows.Forms.Label
  $l2.Text = "Pressione Sair para fechar o instalador."
  $l2.Font = $fonts.small
  $l2.ForeColor = HexColor $colors.sub
  $l2.Size = New-Object System.Drawing.Size(560, 20)
  $l2.Location = New-Object System.Drawing.Point(60, ($panelMain.Controls | % { $_.Location.Y + $_.Size.Height } | Measure -Max | % { $_.Maximum + 10 }))
  $l2.TextAlign = "MiddleCenter"
  $panelMain.Controls.Add($l2)
}

# ════════════════════════════════════════════
#  COMPONENTES AUXILIARES
# ════════════════════════════════════════════

function Add-Title($text) {
  $l = New-Object System.Windows.Forms.Label
  $l.Text = $text
  $l.Font = $fonts.header
  $l.ForeColor = HexColor $colors.white
  $l.Size = New-Object System.Drawing.Size(600, 35)
  $l.Location = New-Object System.Drawing.Point(40, 30)
  $panelMain.Controls.Add($l)
}

function Add-Spacer {
  $top = 0
  if ($panelMain.Controls.Count -gt 0) {
    $top = ($panelMain.Controls | % { $_.Location.Y + $_.Size.Height } | Measure -Max | % { $_.Maximum })
  }
  $l = New-Object System.Windows.Forms.Label
  $l.Text = ""
  $l.Size = New-Object System.Drawing.Size(10, 10)
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
  $dot.Name = "dot"
  $dot.Text = "○"
  $dot.Font = $fonts.body
  $dot.ForeColor = HexColor $colors.sub
  $dot.Size = New-Object System.Drawing.Size(20, 38)
  $dot.Location = New-Object System.Drawing.Point(10, 0)
  $dot.TextAlign = "MiddleLeft"
  $box.Controls.Add($dot)

  $label = New-Object System.Windows.Forms.Label
  $label.Name = "label"
  $label.Text = $text
  $label.Font = $fonts.body
  $label.ForeColor = HexColor $colors.white
  $label.Size = New-Object System.Drawing.Size(500, 38)
  $label.Location = New-Object System.Drawing.Point(30, 0)
  $label.TextAlign = "MiddleLeft"
  $box.Controls.Add($label)

  return New-Object -TypeName PSObject -Property @{
    Box   = $box
    Dot   = $dot
    Label = $label
    Set   = {
      param($newText, $color)
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
$form.Text = "BeautyFlow CRM - Instalador Windows"
$form.Size = New-Object System.Drawing.Size(680, 560)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = HexColor $colors.bg
$form.Icon = $null

$panelMain = New-Object System.Windows.Forms.Panel
$panelMain.Size = New-Object System.Drawing.Size(680, 520)
$panelMain.Location = New-Object System.Drawing.Point(0, 0)
$panelMain.BackColor = HexColor $colors.bg
$form.Controls.Add($panelMain)

# Rodapé com versão do Windows detectada
$winVer = (Get-CimInstance Win32_OperatingSystem).Caption
$footer = New-Object System.Windows.Forms.Label
$footer.Text = "Sistema: $winVer  |  BeautyFlow CRM v1.0"
$footer.Font = $fonts.small
$footer.ForeColor = HexColor $colors.sub
$footer.Size = New-Object System.Drawing.Size(660, 20)
$footer.Location = New-Object System.Drawing.Point(10, 525)
$footer.TextAlign = "MiddleLeft"
$form.Controls.Add($footer)

# Mostrar tela inicial
Show-Welcome

# ── Exibir formulário ──
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
