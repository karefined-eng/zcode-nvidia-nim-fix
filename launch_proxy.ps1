param(
    [string]$BaseUrl = "http://127.0.0.1:18787",
    [string]$TestModel = "z-ai/glm-5.3",
    [int]$StartupTimeoutSeconds = 60,
    [int]$TestTimeoutSeconds = 90,
    [int]$HealthTimeoutSeconds = 5,
    [switch]$NoSelfTest,
    [switch]$NoNotification,
    [switch]$NoDashboard,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:WasWedged = $false
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvFile = Join-Path $RepoRoot ".env"
$Launcher = Join-Path $RepoRoot "run_proxy.ps1"
$LogDir = Join-Path $env:LOCALAPPDATA "zcode-nvidia-nim-fix"
$LogPath = Join-Path $LogDir "proxy.log"

function Get-LocalClientKey {
    if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) {
        return $null
    }
    foreach ($Line in Get-Content -LiteralPath $EnvFile) {
        $TrimmedLine = $Line.Trim()
        if ($TrimmedLine -match "^NIM_PROXY_CLIENT_KEY\s*=\s*(.+)$") {
            $Value = $Matches[1].Trim()
            if ($Value.Length -ge 2 -and $Value.StartsWith('"') -and $Value.EndsWith('"')) {
                $Value = $Value.Substring(1, $Value.Length - 2)
            }
            return $Value
        }
    }
    return $null
}

function Test-ProxyHealth {
    try {
        return Invoke-RestMethod -Uri "$BaseUrl/health" -TimeoutSec $HealthTimeoutSeconds
    } catch {
        return $null
    }
}

function Get-ProxyProcesses {
    return Get-CimInstance Win32_Process -Filter "Name = 'python.exe' OR Name = 'powershell.exe'" |
        Where-Object {
            $_.CommandLine -and (
                $_.CommandLine -like "*nvidia_nim_proxy.server*" -or
                $_.CommandLine -like "*run_proxy.ps1*ApiKeyMode*"
            )
        }
}

function Stop-ProxyProcesses {
    $processes = Get-ProxyProcesses
    if (-not $processes) {
        return
    }
    foreach ($process in $processes) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
    $leftover = Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*nvidia_nim_proxy.server*" }
    foreach ($process in $leftover) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1
}

function Start-ProxyHeadless {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    if ((Test-Path -LiteralPath $LogPath) -and (Get-Item -LiteralPath $LogPath).Length -gt 2MB) {
        Move-Item -LiteralPath $LogPath -Destination "$LogPath.1" -Force
    }
    $proxyArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$Launcher`" -ApiKeyMode Pool -UpstreamTimeoutSeconds 600"
    if ($NoDashboard.IsPresent) {
        $proxyArgs += " -NoDashboard"
    }
    Start-Process -FilePath "powershell.exe" -ArgumentList $proxyArgs -WorkingDirectory $RepoRoot -WindowStyle Hidden -RedirectStandardOutput "$LogPath.out.log" -RedirectStandardError $LogPath | Out-Null
}

function Show-Header {
    param([string]$Line1)
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " $Line1"
    Write-Host "============================================================"
}

function Wait-ForKey {
    if (-not $NoPause) {
        Write-Host ""
        Write-Host "Press any key to close this window (the proxy keeps running)."
        try { [void][System.Console]::ReadKey($true) } catch { }
    }
}

function Show-Notification {
    param(
        [string]$Title,
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Kind = "Info",
        [int]$DisplaySeconds = 6
    )
    if ($NoNotification) {
        return
    }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $balloon = New-Object System.Windows.Forms.NotifyIcon
        $balloon.Icon = switch ($Kind) {
            "Error" { [System.Drawing.SystemIcons]::Error }
            "Warning" { [System.Drawing.SystemIcons]::Warning }
            default { [System.Drawing.SystemIcons]::Information }
        }
        $balloon.BalloonTipTitle = $Title
        $balloon.BalloonTipText = $Message
        $balloon.Visible = $true
        $balloon.ShowBalloonTip($DisplaySeconds * 1000)
        Start-Sleep -Seconds $DisplaySeconds
        $balloon.Dispose()
    } catch {
        # Notifications are best-effort; never fail a launch because one could not be shown.
    }
}

Show-Header "ZCode NVIDIA NIM proxy"

if (-not (Test-Path -LiteralPath $Launcher -PathType Leaf)) {
    Show-Header "FAIL: launcher not found"
    Write-Host "Missing: $Launcher" -ForegroundColor Red
    Show-Notification -Title "ZCode NIM proxy FAILED to start" -Message "Launcher not found: $Launcher" -Kind Error -DisplaySeconds 60
    exit 1
}

$health = Test-ProxyHealth
if ($health) {
    Write-Host "Proxy already running on $BaseUrl" -ForegroundColor Cyan
} else {
    $existing = Get-ProxyProcesses
    if ($existing) {
        Write-Host "Proxy process exists but is not responding (wedged). Restarting it..." -ForegroundColor Yellow
        Stop-ProxyProcesses
        $script:WasWedged = $true
    } else {
        Write-Host "Starting proxy (headless, logging to $LogPath)..."
    }
    Start-ProxyHeadless
    $deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
    $health = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $health = Test-ProxyHealth
        if ($health) {
            break
        }
    }
    if (-not $health) {
        Show-Header "FAIL: proxy did not start within $StartupTimeoutSeconds seconds"
        Write-Host "Check the log for the real error:" -ForegroundColor Red
        Write-Host "  $LogPath"
        Write-Host "Common cause: bad or missing keys in .env (duplicate keys are rejected)."
        Show-Notification -Title "ZCode NIM proxy FAILED to start" -Message "No response after $StartupTimeoutSeconds s. Check $LogPath - usually .env keys." -Kind Error -DisplaySeconds 60
        Wait-ForKey
        exit 1
    }
    Write-Host "Proxy is up." -ForegroundColor Green
}

if ($NoSelfTest) {
    Show-Header "PROXY READY (live test skipped)"
    Write-Host "  Base URL  $BaseUrl/v1"
    if (-not $NoDashboard.IsPresent) {
        Write-Host "  Dashboard $BaseUrl/dashboard"
    }
    Write-Host "  Log       $LogPath"
    Show-Notification -Title "ZCode NIM proxy ready" -Message "Running on $BaseUrl/v1 (live test skipped)" -Kind Info -DisplaySeconds 6
    Wait-ForKey
    exit 0
}

$localKey = Get-LocalClientKey
if (-not $localKey) {
    Show-Header "FAIL: no NIM_PROXY_CLIENT_KEY found in .env"
    Show-Notification -Title "ZCode NIM proxy FAILED to start" -Message "No NIM_PROXY_CLIENT_KEY in .env" -Kind Error -DisplaySeconds 60
    Wait-ForKey
    exit 1
}

$body = @{
    model    = $TestModel
    messages = @(@{ role = 'user'; content = 'Reply with the single word: ready' })
    max_tokens = 16
    stream   = $false
} | ConvertTo-Json -Depth 10

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$response = $null
$failure = $null
try {
    $response = Invoke-RestMethod -Method Post -Uri "$BaseUrl/v1/chat/completions" -Headers @{ Authorization = "Bearer $localKey" } -ContentType 'application/json' -Body $body -TimeoutSec $TestTimeoutSeconds
} catch {
    $failure = $_.Exception.Message
}
$stopwatch.Stop()

if ($failure -or -not $response) {
    Show-Header "PROXY IS UP, BUT THE LIVE TEST FAILED"
    Write-Host "  Reason: $failure" -ForegroundColor Red
    Write-Host ""
    Write-Host "The proxy itself is running; NVIDIA did not answer for '$TestModel'."
    Write-Host "This model may be temporarily unavailable - retry, or use another"
    Write-Host "chat model from the README (e.g. moonshotai/kimi-k3)."
    Write-Host "Log: $LogPath"
    Show-Notification -Title "ZCode NIM proxy: live test failed" -Message "Proxy is up but '$TestModel' did not answer. Try -Restart or another model." -Kind Warning -DisplaySeconds 30
    Wait-ForKey
    exit 2
}

$latency = [int]$stopwatch.Elapsed.TotalMilliseconds
$pool = "$($health.key_pool.available)/$($health.key_pool.total) available"
$catalog = "$($health.model_catalog.status) ($($health.model_catalog.count) models)"

Show-Header "PROXY READY - everything works"
Write-Host "  Base URL          $BaseUrl/v1" -ForegroundColor Green
if (-not $NoDashboard.IsPresent) {
    Write-Host "  Dashboard         $BaseUrl/dashboard" -ForegroundColor Green
}
Write-Host "  Live test         $TestModel OK (${latency} ms)" -ForegroundColor Green
Write-Host "  Key pool          $pool"
Write-Host "  Model catalog     $catalog"
Write-Host "  Log               $LogPath"
Write-Host ""
Write-Host "  ZCode provider settings:"
Write-Host "    Base URL   $BaseUrl/v1"
Write-Host "    Endpoint   /chat/completions"
Write-Host "    API key    local NIM_PROXY_CLIENT_KEY (from .env)"
Write-Host "    Model      $TestModel"
if ($script:WasWedged) {
    Show-Notification -Title "ZCode NIM proxy: was wedged, restarted" -Message "Proxy recovered and GLM 5.3 verified OK (${latency} ms)." -Kind Warning -DisplaySeconds 20
} else {
    Show-Notification -Title "ZCode NIM proxy ready" -Message "GLM 5.3 verified OK (${latency} ms) - $BaseUrl/v1" -Kind Info -DisplaySeconds 6
}
Wait-ForKey
exit 0
