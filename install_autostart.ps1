param(
    [switch]$ScheduledTask,
    [switch]$Watchdog,
    [switch]$StartupFolder,
    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LauncherScript = Join-Path $RepoRoot "launch_proxy.ps1"
$CheckerScript = Join-Path $RepoRoot "check_proxy.ps1"
$StartupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) "ZCode NVIDIA NIM Proxy.lnk"

$LogonTaskName = "ZCode NVIDIA NIM Proxy"
$WatchdogTaskName = "ZCode NVIDIA NIM Proxy Watchdog"

$PowerShellArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$LauncherScript`" -NoPause"
$WatchdogArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$CheckerScript`" -AutoFix -HealthTimeoutSeconds 8"

function Remove-AllStartupEntries {
    $removed = $false
    if (Test-Path -LiteralPath $StartupShortcut) {
        Remove-Item -LiteralPath $StartupShortcut -Force
        Write-Host "Removed Startup shortcut: $StartupShortcut" -ForegroundColor Yellow
        $removed = $true
    }
    foreach ($name in @($LogonTaskName, $WatchdogTaskName)) {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
            Write-Host "Removed scheduled task: $name" -ForegroundColor Yellow
            $removed = $true
        }
    }
    if (-not $removed) {
        Write-Host "Nothing to remove."
    }
}

function Install-LogonTask {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $PowerShellArguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $trigger.Delay = "PT30S"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskName $LogonTaskName -Action $action -Trigger $trigger -Settings $settings -Description "Starts the ZCode NVIDIA NIM proxy at logon (30s delay) with a live self-test and logs to LOCALAPPDATA" -Force | Out-Null
    Write-Host "Registered scheduled task: $LogonTaskName" -ForegroundColor Green
    Write-Host "  Runs at logon after a 30-second delay; retries 3 times on failure."
}

function Install-WatchdogTask {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $WatchdogArguments
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName $WatchdogTaskName -Action $action -Trigger $trigger -Settings $settings -Description "Checks the local proxy every 5 minutes and restarts it only if it becomes wedged (a deliberately stopped proxy is not restarted)" -Force | Out-Null
    Write-Host "Registered scheduled task: $WatchdogTaskName" -ForegroundColor Green
    Write-Host "  Checks every 5 minutes; restarts the proxy only if it wedges."
}

function Install-StartupShortcut {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($StartupShortcut)
    $shortcut.TargetPath = Join-Path $RepoRoot "launch_proxy.bat"
    $shortcut.Arguments = "-NoPause"
    $shortcut.WorkingDirectory = $RepoRoot
    $shortcut.WindowStyle = 7
    $shortcut.Description = "Start the ZCode NVIDIA NIM proxy and verify it before opening ZCode"
    $shortcut.Save()
    Write-Host "Installed Startup shortcut: $StartupShortcut" -ForegroundColor Green
}

if ($Remove) {
    Remove-AllStartupEntries
    return
}

$selectedAny = $false
if ($ScheduledTask) { Install-LogonTask; $selectedAny = $true }
if ($Watchdog) { Install-WatchdogTask; $selectedAny = $true }
if ($StartupFolder) { Install-StartupShortcut; $selectedAny = $true }

if (-not $selectedAny) {
    Install-LogonTask
    Install-WatchdogTask
}

Write-Host ""
Write-Host "Check status anytime:  .\check_proxy.ps1"
Write-Host "Remove all of this:    .\install_autostart.ps1 -Remove"
