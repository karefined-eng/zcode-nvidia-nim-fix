param(
    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$StartupFolder = [Environment]::GetFolderPath('Startup')
$ShortcutPath = Join-Path $StartupFolder "ZCode NVIDIA NIM Proxy.lnk"

if ($Remove) {
    if (Test-Path -LiteralPath $ShortcutPath) {
        Remove-Item -LiteralPath $ShortcutPath -Force
        Write-Host "Auto-start removed: $ShortcutPath" -ForegroundColor Yellow
    } else {
        Write-Host "Auto-start was not installed. Nothing to remove."
    }
    return
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = Join-Path $RepoRoot "launch_proxy.bat"
$shortcut.Arguments = "-NoPause"
$shortcut.WorkingDirectory = $RepoRoot
$shortcut.WindowStyle = 7
$shortcut.Description = "Start the ZCode NVIDIA NIM proxy and verify it before opening ZCode"
$shortcut.Save()

Write-Host "Auto-start installed:" -ForegroundColor Green
Write-Host "  $ShortcutPath"
Write-Host ""
Write-Host "The proxy now starts (minimized, with a self-test) at every login."
Write-Host "Open ZCode any time after login - requests to the local URL will work."
Write-Host ""
Write-Host "To undo:  .\install_autostart.ps1 -Remove"
