# proxy_gui.ps1 — native Windows Forms GUI for managing the NVIDIA/Gemini proxy
# Right-click → Run with PowerShell  |  or: powershell -File .\proxy_gui.ps1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ─── Config ──────────────────────────────────────────────────────────────
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvFiles = @{
    'NVIDIA' = Join-Path $RepoRoot '.env'
    'Gemini' = Join-Path $RepoRoot '.env.gemini'
}
$LaunchScript  = Join-Path $RepoRoot 'run_proxy.ps1'
$CheckerScript = Join-Path $RepoRoot 'check_proxy.ps1'
$LogDir = Join-Path $env:LOCALAPPDATA 'zcode-nvidia-nim-fix'
$LogPath = Join-Path $LogDir 'proxy.log'
$LogonTaskName  = 'ZCode NVIDIA NIM Proxy'
$WatchdogTaskName = 'ZCode NVIDIA NIM Proxy Watchdog'

$DefaultProvider = 'Gemini'  # switch default if you prefer NVIDIA
$RefreshMs = 3000

# ─── Helpers ─────────────────────────────────────────────────────────────
function Get-ProviderConfig($provider) {
    $envPath = $EnvFiles[$provider]
    if (-not (Test-Path -LiteralPath $envPath)) { return $null }
    $cfg = @{ Provider = $provider; EnvFile = $envPath }
    foreach ($Line in Get-Content -LiteralPath $envPath) {
        $Trimmed = $Line.Trim()
        if ($Trimmed -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') {
            $cfg[$Matches[1]] = $Matches[2].Trim()
        }
    }
    return $cfg
}

function Get-ProxyProcesses {
    Get-CimInstance Win32_Process -Filter "Name = 'python.exe' OR Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -and ($_.CommandLine -like "*nvidia_nim_proxy.server*" -or $_.CommandLine -like "*run_proxy.ps1*ApiKeyMode*") }
}

function Stop-ProxyProcesses {
    Get-ProxyProcesses | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
    Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*nvidia_nim_proxy.server*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
}

function Start-Proxy($provider) {
    $cfg = Get-ProviderConfig $provider
    if (-not $cfg) { return "Env file not found: $($EnvFiles[$provider])" }
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$LaunchScript`" -ApiKeyMode Pool -UpstreamTimeoutSeconds 600 -EnvFile `"$($cfg.EnvFile)`""
    if (-not $cfg.NIM_PROXY_UPSTREAM_BASE_URL) { return "Missing NIM_PROXY_UPSTREAM_BASE_URL in $($cfg.EnvFile)" }
    $env:ENV_FILE = $cfg.EnvFile
    Start-Process -FilePath "powershell.exe" -ArgumentList $args -WorkingDirectory $RepoRoot -WindowStyle Hidden -RedirectStandardOutput "$LogDir\proxy.out.log" -RedirectStandardError "$LogDir\proxy.err.log" | Out-Null
    return $null
}

function Test-Health($baseUrl = 'http://127.0.0.1:18787') {
    try { return Invoke-RestMethod -Uri "$baseUrl/health" -TimeoutSec 5 }
    catch { return $null }
}

function Get-AutoStartState {
    $logon = Get-ScheduledTask -TaskName $LogonTaskName -ErrorAction SilentlyContinue
    $watch = Get-ScheduledTask -TaskName $WatchdogTaskName -ErrorAction SilentlyContinue
    return @{ Logon = $null -ne $logon; Watchdog = $null -ne $watch }
}

function Set-AutoStart($enable) {
    if ($enable) {
        if (-not (Get-ScheduledTask -TaskName $LogonTaskName -ErrorAction SilentlyContinue)) {
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$LaunchScript`" -NoPause"
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"; $trigger.Delay = "PT30S"
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
            Register-ScheduledTask -TaskName $LogonTaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
        }
        if (-not (Get-ScheduledTask -TaskName $WatchdogTaskName -ErrorAction SilentlyContinue)) {
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$CheckerScript`" -AutoFix -HealthTimeoutSeconds 8"
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
            Register-ScheduledTask -TaskName $WatchdogTaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
        }
    } else {
        if (Get-ScheduledTask -TaskName $LogonTaskName -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $LogonTaskName -Confirm:$false }
        if (Get-ScheduledTask -TaskName $WatchdogTaskName -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $WatchdogTaskName -Confirm:$false }
    }
}

# ─── UI ──────────────────────────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text = 'ZCode NIM Proxy Manager'
$form.Size = New-Object System.Drawing.Size([int]520, 560)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(0x0F,0x11,0x15)
$form.ForeColor = [System.Drawing.Color]::FromArgb(0xE6,0xE9,0xEF)
$font = New-Object System.Drawing.Font('Segoe UI', 9)

$mutedBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(0x8B,0x93,0xA7))
$okBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(0x3F,0xB9,0x50))
$warnBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(0xD2,0x99,0x22))
$badBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(0xF8,0x51,0x49))

# Top: Provider selector
$lblProvider = New-Object System.Windows.Forms.Label
$lblProvider.Text = 'Provider'
$lblProvider.Location = New-Object System.Drawing.Point([int]16, [int] 16)
$lblProvider.AutoSize = $true
$lblProvider.Font = $font
$lblProvider.ForeColor = [System.Drawing.Color]::FromArgb(0x8B,0x93,0xA7)

$cmbProvider = New-Object System.Windows.Forms.ComboBox
$cmbProvider.Location = New-Object System.Drawing.Point([int]16, [int] 38)
$cmbProvider.Size = New-Object System.Drawing.Size([int]140, 24)
$cmbProvider.DropDownStyle = 'DropDownList'
$cmbProvider.Items.AddRange(@('Gemini','NVIDIA'))
$cmbProvider.SelectedItem = $DefaultProvider
$cmbProvider.Font = $font

# Status header
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point([int]180, 16)
$lblStatus.Size = New-Object System.Drawing.Size([int]300, 46)
$lblStatus.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$lblStatus.Text = 'Status: checking…'

# Info grid
$script:gridY = 76
function AddInfoRow($label, $y, $varName) {
    $script:gridY
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $label
    $l.Location = New-Object System.Drawing.Point([int]16, [int] $y)
    $l.Size = New-Object System.Drawing.Size([int]110, 22)
    $l.Font = $font
    $l.ForeColor = $mutedBrush.Color
    $form.Controls.Add($l)
    $v = New-Object System.Windows.Forms.Label
    $v.Name = $varName
    $v.Text = '-'
    $v.Location = New-Object System.Drawing.Point([int]136, $y)
    $v.Size = New-Object System.Drawing.Size([int]360, 22)
    $v.Font = New-Object System.Drawing.Font('Cascadia Code', 9)
    $form.Controls.Add($v)
    $gridY += 24
}

AddInfoRow 'Mode:' $gridY 'lblMode'
AddInfoRow 'Upstream:' $gridY 'lblUpstream'
AddInfoRow 'Key Pool:' $gridY 'lblPool'
AddInfoRow 'Queue:' $gridY 'lblQueue'
AddInfoRow 'Models:' $gridY 'lblModels'
AddInfoRow 'Last update:' $gridY 'lblUpdated'

# Buttons
$btnY = $gridY + 16
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = 'Start'
$btnStart.Location = New-Object System.Drawing.Point([int]16, [int] $btnY)
$btnStart.Size = New-Object System.Drawing.Size([int]96, 32)
$btnStart.BackColor = [System.Drawing.Color]::FromArgb(0x17,0x1A,0x21)
$btnStart.FlatStyle = 'Flat'
$btnStart.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0x3F,0xB9,0x50)
$btnStart.ForeColor = [System.Drawing.Color]::FromArgb(0x3F,0xB9,0x50)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = 'Stop'
$btnStop.Location = New-Object System.Drawing.Point([int]120, $btnY)
$btnStop.Size = New-Object System.Drawing.Size([int]96, 32)
$btnStop.BackColor = [System.Drawing.Color]::FromArgb(0x17,0x1A,0x21)
$btnStop.FlatStyle = 'Flat'
$btnStop.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0xF8,0x51,0x49)
$btnStop.ForeColor = [System.Drawing.Color]::FromArgb(0xF8,0x51,0x49)

$btnRestart = New-Object System.Windows.Forms.Button
$btnRestart.Text = 'Restart'
$btnRestart.Location = New-Object System.Drawing.Point([int]224, $btnY)
$btnRestart.Size = New-Object System.Drawing.Size([int]96, 32)
$btnRestart.BackColor = [System.Drawing.Color]::FromArgb(0x17,0x1A,0x21)
$btnRestart.FlatStyle = 'Flat'
$btnRestart.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0xD2,0x99,0x22)
$btnRestart.ForeColor = [System.Drawing.Color]::FromArgb(0xD2,0x99,0x22)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Refresh Now'
$btnRefresh.Location = New-Object System.Drawing.Point([int][int]328, [int]$btnY)
$btnRefresh.Size = New-Object System.Drawing.Size([int][int]160, [int]32)
$btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(0x17,0x1A,0x21)
$btnRefresh.FlatStyle = 'Flat'
$btnRefresh.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0x26,0x2B,0x36)
$btnRefresh.ForeColor = [System.Drawing.Color]::FromArgb(0xE6,0xE9,0xEF)

# Auto-start toggle
$chkAuto = New-Object System.Windows.Forms.CheckBox
$chkAuto.Text = 'Auto-start at logon (scheduled task + watchdog)'
$chkAuto.Location = New-Object System.Drawing.Point([int][int]16, [int]($btnY + 42))
$chkAuto.Size = New-Object System.Drawing.Size([int][int]400, [int]24)
$chkAuto.Font = $font
$chkAuto.ForeColor = [System.Drawing.Color]::FromArgb(0xE6,0xE9,0xEF)

# Log tail
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = 'Log (tail)'
$lblLog.Location = New-Object System.Drawing.Point([int]16, [int] $btnY + 72)
$lblLog.AutoSize = $true
$lblLog.Font = $font
$lblLog.ForeColor = $mutedBrush.Color

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point([int]16, [int] $btnY + 98)
$txtLog.Size = New-Object System.Drawing.Size([int]472, 350)
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font('Cascadia Code', 8)
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(0x08,0x0A,0x0D)
$txtLog.ForeColor = [System.Drawing.Color]::FromArgb(0xE6,0xE9,0xEF)
$txtLog.BorderStyle = 'FixedSingle'

# Add all controls
$form.Controls.AddRange(@($lblProvider,$cmbProvider,$lblStatus,
    $btnStart,$btnStop,$btnRestart,$btnRefresh,
    $chkAuto,$lblLog,$txtLog))

# ─── Logic ──────────────────────────────────────────────────────────────
$currentProvider = $DefaultProvider
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $RefreshMs

$autoState = Get-AutoStartState
$chkAuto.Checked = $autoState.Logon -or $autoState.Watchdog

function UpdateStatus {
    $health = Test-Health
    if ($health) {
        $lblStatus.Text = 'Status: UP'
        $lblStatus.ForeColor = $okBrush.Color
        $lblMode.Text = $health.mode
        $lblUpstream.Text = $health.upstream
        if ($health.key_pool) {
            $pool = $health.key_pool
            $lblPool.Text = "$($pool.available)/$($pool.total) avail  •  $($pool.cooling_down) cooling  •  $($pool.quarantined) quarantined"
            $lblQueue.Text = "$($health.queue.active) active  •  $($health.queue.queued) waiting"
        } else {
            $lblPool.Text = 'Single-key mode'
            $lblQueue.Text = '-'
        }
        $cat = $health.model_catalog
        $lblModels.Text = "$($cat.status)  ($($cat.count) models)"
        $lblUpdated.Text = (Get-Date).ToString('HH:mm:ss')
    } else {
        $procs = Get-ProxyProcesses
        if ($procs) {
            $lblStatus.Text = 'Status: WEDGED (process alive, no /health response)'
            $lblStatus.ForeColor = $warnBrush.Color
        } else {
            $lblStatus.Text = 'Status: DOWN'
            $lblStatus.ForeColor = $badBrush.Color
        }
        $lblMode.Text = $lblUpstream.Text = $lblPool.Text = $lblQueue.Text = $lblModels.Text = '-'
        $lblUpdated.Text = (Get-Date).ToString('HH:mm:ss')
    }
}

function UpdateLogTail {
    if (Test-Path -LiteralPath $LogPath) {
        $lines = Get-Content -LiteralPath $LogPath -Tail 120
        $txtLog.Lines = $lines
        $txtLog.SelectionStart = $txtLog.Text.Length
        $txtLog.ScrollToCaret()
    }
}

function SetBusy($busy) {
    $btnStart.Enabled = -not $busy
    $btnStop.Enabled = -not $busy
    $btnRestart.Enabled = -not $busy
    $btnRefresh.Enabled = -not $busy
    $cmbProvider.Enabled = -not $busy
}

$btnStart.Add_Click({
    SetBusy $true
    $err = Start-Proxy $currentProvider
    if ($err) {
        [System.Windows.Forms.MessageBox]::Show($err, 'Start failed', 'OK', 'Error')
    } else {
        Start-Sleep -Seconds 2
        UpdateStatus
    }
    SetBusy $false
    UpdateLogTail
})

$btnStop.Add_Click({
    SetBusy $true
    Stop-ProxyProcesses
    UpdateStatus
    SetBusy $false
    UpdateLogTail
})

$btnRestart.Add_Click({
    SetBusy $true
    Stop-ProxyProcesses
    Start-Sleep -Seconds 1
    $err = Start-Proxy $currentProvider
    if ($err) { [System.Windows.Forms.MessageBox]::Show($err, 'Restart failed', 'OK', 'Error') }
    else { Start-Sleep -Seconds 2; UpdateStatus }
    SetBusy $false
    UpdateLogTail
})

$btnRefresh.Add_Click({ UpdateStatus; UpdateLogTail })

$cmbProvider.Add_SelectedIndexChanged({ $currentProvider = $cmbProvider.SelectedItem; UpdateStatus })

$chkAuto.Add_CheckedChanged({ Set-AutoStart $chkAuto.Checked })

$timer.Add_Tick({ UpdateStatus; UpdateLogTail })

# Initial load
UpdateStatus
UpdateLogTail
$timer.Start()

$form.Add_FormClosing({ $timer.Stop() })
$form.ShowDialog()