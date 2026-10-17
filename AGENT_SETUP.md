# One-Click Setup Prompt

Paste this into your agentic coding tool (Cursor/Copilot/Cline/OpenCode):

```
Clone https://github.com/karefined-eng/zcode-nvidia-nim-fix into a local folder. Then:
1. Create a Python venv and install nothing (no deps needed).
2. Copy .env.example to .env.
3. Ask me for my NVIDIA API key from https://build.nvidia.com (free tier) and put it in .env as NVIDIA_API_KEY_1.
4. Run .\run_proxy.ps1 -ApiKeyMode Pool -UpstreamTimeoutSeconds 600.
5. Tell me to set my IDE base URL to http://127.0.0.1:18787/v1 and model to z-ai/glm-5.3.
6. Run check_proxy.ps1 to verify.
Only ask me for the API key; do everything else automatically.
```
