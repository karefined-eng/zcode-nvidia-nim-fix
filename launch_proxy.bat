@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch_proxy.ps1" %*

exit /b %ERRORLEVEL%
