param(
    [string]$BaseUrl = "http://127.0.0.1:18787",
    [int]$HealthTimeoutSeconds = 5,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AutoFix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogPath = Join-Path $env:LOCALAPPDATA "zcode-nvidia-nim-fix\proxy.log"

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
        return $false
    }
    foreach ($process in $processes) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "Stopped $($process.Name) (PID $($process.ProcessId))" -ForegroundColor Yellow
    }
    Start-Sleep -Seconds 2
    $leftover = Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*nvidia_nim_proxy.server*" }
    foreach ($process in $leftover) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "Force stopped python.exe (PID $($process.ProcessId))" -ForegroundColor Yellow
    }
    Start-Sleep -Seconds 1
    return $true
}

if ($Stop) {
    if (Stop-ProxyProcesses) {
        Write-Host "Proxy stopped."
    } else {
        Write-Host "No proxy processes found."
    }
    return
}

if ($Restart) {
    Write-Host "Restarting the proxy..."
    Stop-ProxyProcesses | Out-Null
    $launcher = Join-Path $RepoRoot "launch_proxy.ps1"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -NoPause
    exit $LASTEXITCODE
}

if ($AutoFix) {
    try {
        $health = Invoke-RestMethod -Uri "$BaseUrl/health" -TimeoutSec $HealthTimeoutSeconds
        exit 0
    } catch [System.Net.WebException] {
        if ($_.Exception.Status -ne [System.Net.WebExceptionStatus]::Timeout) {
            exit 0
        }
    } catch {
        exit 0
    }
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Proxy wedged on $BaseUrl; restarting" -ForegroundColor Yellow
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "check_proxy.ps1") -Restart
    exit $LASTEXITCODE
}

$health = $null
$state = "down"
try {
    $health = Invoke-RestMethod -Uri "$BaseUrl/health" -TimeoutSec $HealthTimeoutSeconds
    $state = "up"
} catch [System.Net.WebException] {
    if ($_.Exception.Status -eq [System.Net.WebExceptionStatus]::Timeout) {
        $state = "wedged"
    }
} catch {
    $state = "down"
}

if ($state -eq "up") {
    Write-Host ""
    Write-Host "Proxy RUNNING on $BaseUrl" -ForegroundColor Green
    Write-Host "  status         $($health.status)"
    Write-Host "  key pool       $($health.key_pool.available)/$($health.key_pool.total) available ($($health.key_pool.cooling_down) cooling, $($health.key_pool.quarantined) quarantined)"
    Write-Host "  queue          $($health.queue.active) active, $($health.queue.queued) queued"
    Write-Host "  model catalog  $($health.model_catalog.status) ($($health.model_catalog.count) models)"
    try {
        $null = Invoke-WebRequest -Uri "$BaseUrl/dashboard" -TimeoutSec $HealthTimeoutSeconds -UseBasicParsing
        Write-Host "  dashboard      $BaseUrl/dashboard"
    } catch {
    }
    Write-Host ""
    exit 0
}

if ($state -eq "wedged") {
    Write-Host ""
    Write-Host "Proxy WEDGED on $BaseUrl - process is alive but not answering" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This can happen after the IDE disconnects mid-stream. Fix it with:"
    Write-Host "  .\check_proxy.ps1 -Restart"
    Write-Host "Last log lines: $LogPath"
    Write-Host ""
    exit 2
}

Write-Host ""
Write-Host "Proxy NOT running on $BaseUrl" -ForegroundColor Red
Write-Host ""
Write-Host "Start it with:  launch_proxy.bat"
Write-Host ""
exit 1
