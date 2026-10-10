# AGENTS.md — Operational Manual (Central Nervous System)

> **Read this file on initialization before taking any action.**
> All project documentation is centralized in `docs/`: see [origin.md](origin.md), [handoff/](handoff/), [research/](research/).

## What this project is

`zcode-nvidia-nim-fix` is a local OpenAI-compatible **Chat Completions** proxy for NVIDIA NIM. It strips unsupported request fields (notably ZCode's literal `extra_body`, which NVIDIA rejects with `400`), preserves messages and structured tool calls, forwards JSON/SSE streams, rotates a private API-key pool, runs bounded FIFO queues, caches the public model catalog, and can optionally sync models into OpenCode's config. Package/repo names retain the original ZCode origin; the proxy works with any compatible client.

Full user-facing documentation: [README.md](../README.md) at the repo root.

## Quick Facts

| Item | Value |
| --- | --- |
| Local base URL | `http://127.0.0.1:18787/v1` |
| Chat endpoint | `POST /v1/chat/completions` |
| Cached model list | `GET /v1/models` |
| Health | `GET /health` |
| NVIDIA upstream | `https://integrate.api.nvidia.com/v1` |
| Launcher | `run_proxy.ps1` (Windows, parses `.env` for pool mode) |
| Runtime deps | **None** — stdlib only (Python 3.10+) |
| Tests | 303 passing (`pytest`) |
| Python in use | 3.12.10 (`.venv` created 2026-10-09) |

## Environment Setup (completed 2026-10-09)

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip pytest ruff mypy
```

Installed: `pip 26.2.1`, `pytest 9.1.1`, `ruff 0.16.10`, `mypy 2.4.0`.
`.env` exists (git-ignored) with a generated local `NIM_PROXY_CLIENT_KEY` and 5 distinct real `NVIDIA_API_KEY_1..5` values. Never commit `.env`.

## Verification Commands

```powershell
.\.venv\Scripts\python.exe -m pytest
.\.venv\Scripts\python.exe -m ruff check .
.\.venv\Scripts\python.exe -m mypy nvidia_nim_proxy tests
.\.venv\Scripts\python.exe -m pip wheel --no-deps --wheel-dir dist .
```

## Running the Proxy (One-Click)

The daily flow needs **no flags and no log reading**:

| Action | Command |
| --- | --- |
| Start + self-test (double-click) | `launch_proxy.bat` |
| Start from a terminal, no pause | `powershell -File launch_proxy.ps1 -NoPause` |
| Glanceable status anytime | `powershell -File check_proxy.ps1` |
| **Recover from a wedge** | `powershell -File check_proxy.ps1 -Restart` |
| Stop the proxy | `powershell -File check_proxy.ps1 -Stop` |
| Auto-start at login + watchdog | `.\install_autostart.ps1` (undo: `-Remove`) |

Auto-start uses two **Scheduled Tasks** (registered by `install_autostart.ps1`, not a Startup shortcut):

- `ZCode NVIDIA NIM Proxy` — AtLogOn trigger with a **30-second delay**, `powershell -File launch_proxy.ps1 -NoPause`, restart on failure (3x, 1 min apart), 10-minute execution limit.
- `ZCode NVIDIA NIM Proxy Watchdog` — every 5 minutes runs `check_proxy.ps1 -AutoFix` (8s health timeout). `-AutoFix` restarts the proxy **only when WEDGED** (health timeout); a connection-refused (deliberately stopped) proxy is left stopped, so manual control keeps working.

Verify a task ran: `Get-ScheduledTaskInfo -TaskName "ZCode NVIDIA NIM Proxy"` (`LastTaskResult` 0 = success). Run one manually: `Start-ScheduledTask -TaskName "ZCode NVIDIA NIM Proxy"`.

`launch_proxy.ps1` starts the proxy **headless** (Pool mode, 600s timeout) with stdout/stderr redirected to `%LOCALAPPDATA%\zcode-nvidia-nim-fix\proxy.log` (rotated at 2MB to `.1`), waits for `/health`, runs a **live GLM 5.3 request**, and prints a `PROXY READY` banner with the ZCode provider settings. Exit codes: `0` ready, `1` not started, `2` up but live test failed. If a proxy process exists but health times out (wedged), the launcher **kills and restarts it automatically**.

`check_proxy.ps1` distinguishes three states: **RUNNING** (exit 0), **NOT RUNNING** (connection refused, exit 1), and **WEDGED** (process alive but health times out, exit 2 — fix with `-Restart`). `-Stop` kills the launcher shell and the python server by matching their command lines (`nvidia_nim_proxy.server`, `run_proxy.ps1 -ApiKeyMode`).

**Never launch raw python for pool mode** — a bare `python -m nvidia_nim_proxy.server` will not see `.env` (see Traps). The equivalent manual launch is:

```powershell
powershell -NoProfile -Command ". .\run_proxy.ps1 -ApiKeyMode Pool -UpstreamTimeoutSeconds 600"
```

- Health: `Invoke-RestMethod http://127.0.0.1:18787/health`
- Stop: `Ctrl+C` in its terminal, or `Stop-Process -Id <pid>`
- Only **one** proxy on port `18787` at a time. Stop before switching modes.

## Architecture Map

| Path | Role |
| --- | --- |
| `nvidia_nim_proxy/server.py` | HTTP server (stdlib), endpoints, failover wiring, version string |
| `nvidia_nim_proxy/sanitizer.py` | Strips unsupported request fields (`extra_body`, `reasoning`, `thinking`, ...); preserves tool calls |
| `nvidia_nim_proxy/credentials.py` | Key validation; **rejects duplicate NVIDIA keys** (`ValueError: duplicate NVIDIA API key detected at ...`) |
| `nvidia_nim_proxy/key_pool.py` | Round-robin key rotation, cooldown (408/429), quarantine (401/403) |
| `nvidia_nim_proxy/scheduler.py` | FIFO queues per key; emits the `Queue event=...` log lines |
| `nvidia_nim_proxy/model_catalog.py` | Background `/v1/models` refresh (6h), cache at `%LOCALAPPDATA%\zcode-nvidia-nim-fix\models.json` |
| `nvidia_nim_proxy/model_profiles.py` | Reasoning-effort mapping per model (body / chat_template / provider_default) |
| `nvidia_nim_proxy/model_limits.py` | Context/output limit registry (`MODEL_CONTEXT_LIMITS`, 12 IDs) |
| `nvidia_nim_proxy/opencode_sync.py` | Opt-in OpenCode JSON sync; only syncs the 12 documented chat models |
| `run_proxy.ps1` | Launcher: activates venv, parses `.env`, sets env vars, restores them on exit |
| `tests/` | 16 test files; `test_integration.py` holds the GLM 5.2 `extra_body` regression |
| `.github/workflows/ci.yml` | CI: pytest, ruff, mypy, wheel build, launcher checks |

## Search / Grep Strategies

- Error strings are the fastest anchors: `grep -rn "duplicate NVIDIA API key"` → `credentials.py:68`.
- Model IDs are the join key across registries: `grep -rn "glm-5"` hits `model_limits.py`, `model_profiles.py`, `opencode_sync.py`, README.
- The proxy logs every lifecycle event with `model='...'` and `api_key_fingerprint=...` — grep the launcher output, not the code, to trace a single request.
- Catalog cache for quick model lists: `C:\Users\asamoah\AppData\Local\zcode-nvidia-nim-fix\models.json` (80 entries; 12 are documented chat models).

## Model Compatibility — Verified Live 2026-10-09

9 of 12 documented chat models respond; failures are **NVIDIA-side**, not proxy bugs.

| Model | Verdict | Notes |
| --- | --- | --- |
| `z-ai/glm-5.3` | ✅ Always 200 | 14 requests, zero failures; ~3–6s; 1M ctx / 16,384 out; native `max` default |
| `moonshotai/kimi-k3` | ✅ 200 | 1M ctx; only model with controllable effort (`low`/`high`/`max`); proxy strips top_p/penalties |
| `nvidia/nemotron-3-ultra-550b-a55b` | ✅ 200 | 1M ctx |
| `nvidia/nemotron-3-super-120b-a12b` | ✅ 200 | 1M ctx |
| `nvidia/nemotron-3.5-lightning-30b-a3b` | ✅ 200 | 1M ctx; at low `max_tokens` its chain-of-thought leaked into `content` |
| `poolside/laguna-xs-2.1` | ✅ 200 (one 503, auto-failover to next key → 200) | Pool rotation verified live |
| `meta/muse-glimmer-30b` | ✅ 200 | 131K ctx |
| `openai/gpt-oss-20b` | ✅ 200 | 131K ctx; NVIDIA caps output at **4,096** |
| `deepseek-ai/deepseek-v4.1-flash` | ⚠️ Flaky | 504 at 300s first tries, 200 at `max_tokens=512` |
| `z-ai/glm-5.3-flash` | ❌ NVIDIA 504 | ~302s gateway timeout on every attempt |
| `google/gemma-4-31b-it` | ❌ NVIDIA 504 | ~302s gateway timeout repeatedly |
| `moonshotai/kimi-k2.6` | ❌ 404 | Not deployed for this key/endpoint |

Selection rationale (GLM 5.3 daily driver, Kimi K3 alternate): [research/model-selection.md](research/model-selection.md). Untested: structured `tool_calls` per model — that is the open question before locking a daily driver.

## Tool Quirks & Environment Traps (Friction Log)

Logged so the next agent does not rediscover them.

1. **pip installs get killed by the default 120s command timeout.** Symptom: shell tool aborts mid-`pip install`. Fix: pass `timeout: 300000` (or more) on every `pip install` on this machine.
2. **Corrupted pip installs in `.venv\Lib\site-packages`.** Symptom: `WARNING: Ignoring invalid distribution ~ip`. Fix: `Remove-Item -LiteralPath ".venv\Lib\site-packages\~ip" -Recurse -Force` (and any `~ip-*.dist-info`), then `python -m pip install --upgrade pip`.
3. **`background_process` `ready` must be an object**, e.g. `{"pattern": "listening"}`, not a bare string — a string is rejected with an argument-schema error.
4. **Background processes do not inherit `run_proxy.ps1`'s `.env` parsing.** Launching `.venv\Scripts\python.exe -m nvidia_nim_proxy.server --api-key-mode pool` directly fails with `NIM_PROXY_CLIENT_KEY is required in pool mode`. Fix: launch through the launcher: `powershell -NoProfile -Command ". .\run_proxy.ps1 -ApiKeyMode Pool -UpstreamTimeoutSeconds 600"`.
5. **The proxy refuses duplicate NVIDIA key values.** All five `NVIDIA_API_KEY_n` placeholders were identical → `duplicate NVIDIA API key detected at NVIDIA_API_KEY_2`, process exits immediately. Every `NVIDIA_API_KEY_n` must be a distinct value; `NIM_PROXY_CLIENT_KEY` must differ from all of them.
6. **A connection-refused `/health` right after start does not mean the process is up.** The `ready` pattern matched the startup banner before listening, and the process had already exited (trap 5). Always read the process logs (`background_process` action `logs`) before diagnosing.
7. **`Select-String` returns MatchInfo objects** — piping into `Select-Object -ExpandProperty Line` fails (`Property "Line" cannot be found`), and piping formatted `Get-ChildItem` output into `Select-String` silently matches nothing. Fix: use `Get-Content -Raw` plus regex `-replace` on the whole string; for file lists use `Get-ChildItem -Recurse -File | Select-Object -ExpandProperty FullName`.
8. **Windows paths need backslashes.** Passing `nvidia_nim_proxy:model_limits.py` (colon) to the read tool fails with "File not found".
9. **Model IDs are case- and punctuation-sensitive.** `z-ai/glm-5-3-flash` (hyphens) and `deepseek-ai/deepseek-v4.1-flasH` (wrong case) returned **404**. Use exact IDs from the catalog/README.
10. **Reasoning models look "empty" at low `max_tokens`.** `moonshotai/kimi-k3`, `openai/gpt-oss-20b`, `meta/muse-glimmer-30b`, and `nvidia/nemotron-3-super-120b-a12b` put output in `reasoning_content` first; final `content` appears only with `max_tokens >= 256`. Do not misread as failure.
11. **`/health` version is stale.** `server.py` reports `nvidia_nim_proxy.__version__` = `0.2.1` while `pyproject.toml` = `0.3.0` (wheel builds as 0.3.0). Do not trust `/health` version for release info; fix by syncing `__init__.py` if a release is prepared.
12. **PowerShell: use `;` not `&&`** when chaining dependent commands; use `cmd1; if ($?) { cmd2 }`.
13. **Use `monitor`, not `start`, for one-shot checks** (health/test requests) — `monitor` runs the command and returns its output; `start` is for long-running servers.
14. **The proxy can wedge silently (discovered 2026-10-09).** Symptom: the process stays alive, `netstat` shows `LISTENING`, new connections are accepted and handler threads spawn (thread count rises), but **no endpoint ever responds** — `/health`, `/v1/models`, and chat all hang until the client times out. CPU stays at 0%. It was observed right after ZCode connected and streamed through the proxy; ZCode's abandoned connection sat in `CLOSE_WAIT`. Root cause not fully isolated (leading theory: blocking writes to the minimized console's stderr buffer); **the fix was architectural**: `launch_proxy.ps1` now starts the proxy **headless** (`-WindowStyle Hidden` with stderr redirected to `%LOCALAPPDATA%\zcode-nvidia-nim-fix\proxy.log`) instead of in a minimized console window. The headless version has served continuous ZCode streaming without wedging. Detection: `check_proxy.ps1` treats a health **timeout** as WEDGED (distinct from connection-refused = NOT RUNNING); recovery: `check_proxy.ps1 -Restart`, which `launch_proxy.ps1` also does automatically at startup.
15. **The harness kills bash-tool commands that spawn `Start-Process` children** (`ChildProcess.kill`), but detached children survive — a headless proxy started this way keeps running after the tool call is killed. Verify state with `check_proxy.ps1` rather than trusting the command's exit.
16. **The venv python re-execs the system python.** `.venv\Scripts\python.exe -m nvidia_nim_proxy.server` (parent) spawns `C:\Users\asamoah\AppData\Local\Programs\Python\Python312\python.exe -m nvidia_nim_proxy.server` (child, same args); the **child holds the listening port**. Stop routines must match both command lines (the `nvidia_nim_proxy.server` pattern does).
17. **PowerShell 5.1 rejects post-hoc repetition on scheduled triggers.** `$trigger.RepetitionInterval = ...` throws "property cannot be found on this object" on the `MSFT_TaskTimeTrigger` returned by `New-ScheduledTaskTrigger`. Fix: pass `-RepetitionInterval` directly to `New-ScheduledTaskTrigger -Once -At <time> -RepetitionInterval (New-TimeSpan -Minutes 5)`. Verified working on PowerShell 5.1 / Windows 11.
18. **Scheduled Tasks beat the Startup folder for this proxy.** The task trigger supports a logon **delay** (kills the startup race), `-ExecutionPolicy Bypass`, restart-on-failure, and an execution time limit; a Startup shortcut has none of these. Tasks register non-elevated for the current user (`-AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"`) — no admin prompt needed.

19. **Edit tool `oldString` matching picks the first occurrence.** When editing `server.py`, I targeted `_send_tool_call_text_diagnostic` but the match also caught the same `def` signature pattern inside `_send_json` logic, deleting the `response_body = json.dumps(...)` line → runtime `NameError`. Fix: make `oldString` unique by including more surrounding context (2-3 lines) or use `replaceAll` when intentionally changing multiple locations.

20. **Missing `import json` in new test file** caused `NameError: name 'json' is not defined` at mypy/runtime. Always include standard-library imports explicitly even when the test module already imports `json` elsewhere (module scope is per-file).

21. **Direct method assignment (`Class.method = func`) breaks mypy strict.** Assigning to `NIMProxyHandler._forward_to_nim` in a test produced `Incompatible types in assignment` — the signature is `def _forward_to_nim(self, ...)` vs the test's standalone `def forward(handler, ...)`. Fix: use `monkeypatch.setattr(NIMProxyHandler, "_forward_to_nim", forward)` — pytest's monkeypatch preserves type compatibility and auto-restores.

22. **`GET /dashboard` served by the existing proxy process** costs ~0 extra RAM. When adding an in-process status page, route it in `do_GET` before `/v1/models`, gate it with a `dashboard_enabled` config flag (default `is_loopback_host(host)`), and add `--no-dashboard` CLI override — no separate process, no upstream calls, no auth (reuses secret-free `/health` data). Restart required for running proxies to pick up new routes.
19. **The watchdog restarts only wedged proxies, never stopped ones.** `check_proxy.ps1 -AutoFix` treats a connection-refused response as "deliberately stopped" and exits 0 silently. This is intentional: it keeps `check_proxy.ps1 -Stop` usable for mode switching instead of the watchdog resurrecting the old mode.

## Conventions

- `.env`, `.venv/`, `dist/`, caches are git-ignored. Real keys live only in `.env`, process env, or IDE credential stores — never in commits, READMEs, examples, or logs.
- Proxy logs omit keys; only fingerprints (`api_key_fingerprint`) appear.
- Follow SemVer; changelog in [CHANGELOG.md](../CHANGELOG.md).
- Author of record: Levent Dogan (per `pyproject.toml`).
