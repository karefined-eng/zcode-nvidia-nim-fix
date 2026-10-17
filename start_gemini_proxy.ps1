# Script to start the proxy with Gemini upstream URL
$url = 'https://generativelanguage.googleapis.com/v1beta/openai'
# Set in the CURRENT process so the child run_proxy.ps1 → python inherits it.
# User-scope-only assignment is invisible to processes started from this shell.
$env:NIM_PROXY_UPSTREAM_BASE_URL = $url
Write-Host "NIM_PROXY_UPSTREAM_BASE_URL set to: $env:NIM_PROXY_UPSTREAM_BASE_URL"

# Start the proxy in Pool mode
& 'C:\Users\asamoah\zcode-nvidia-nim-fix\run_proxy.ps1' -ApiKeyMode Pool -UpstreamTimeoutSeconds 600 -DebugMode