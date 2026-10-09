# Handoff — Setup, Proxy Launch, and Live Model Compatibility Testing

**Date:** 2026-10-09
**Session scope:** Environment setup → proxy launch → live verification of all 12 documented chat models → documentation scaffolding
**Status:** Complete. Proxy left running in Pool mode. No code changes were made.

## 1. Environment Setup

| Step | Result |
| --- | --- |
| Python | 3.12.10 (`C:\Users\asamoah\AppData\Local\Programs\Python\Python312\python.exe`) |
| venv | `.venv` created |
| Dev deps | `pip 26.2.1`, `pytest 9.1.1`, `ruff 0.16.10`, `mypy 2.4.0` |
| `.env` | Created from `.env.example`; local `NIM_PROXY_CLIENT_KEY` generated; user later supplied 5 distinct real NVIDIA keys |
| `pytest` | **303 passed** in ~32s |
| `ruff check .` | All checks passed |
| `mypy nvidia_nim_proxy tests` | Success, 23 source files |
| Wheel | `dist/zcode_nvidia_nim_fix-0.3.0-py3-none-any.whl` built |

**Blocker hit and resolved:** a corrupted `~ip` distribution in the fresh venv broke pip (`WARNING: Ignoring invalid distribution ~ip`). Fixed by removing `.venv\Lib\site-packages\~ip` and `~ip-25.0.1.dist-info`, then reinstalling pip. (Logged in AGENTS.md traps.)

## 2. Proxy Launch

First launch attempt failed: all five `NVIDIA_API_KEY_n` values in `.env` were identical placeholders → `duplicate NVIDIA API key detected at NVIDIA_API_KEY_2` → process exited before listening. User replaced them with five distinct keys.

Final launch (still running at session end, PID 20192):

```powershell
powershell -NoProfile -Command ". .\run_proxy.ps1 -ApiKeyMode Pool -UpstreamTimeoutSeconds 600"
```

- URL: `http://127.0.0.1:18787/v1`
- `/health`: `status: ok`, `mode: pool`, catalog `ready` with **80 models**, `5/5` keys available
- End-to-end test: `z-ai/glm-5.3` returned a normal completion (`finish_reason: stop`, 36 reasoning tokens) — proxy path proven working.

## 3. Live Model Compatibility Probe

All 12 documented chat models were probed through the running proxy. Full results table in [AGENTS.md](../AGENTS.md#model-compatibility--verified-live-2026-10-09). Summary:

- **9 models respond.** GLM 5.3 was the only model with a 100% success rate (14 requests, zero failures).
- **3 failures are NVIDIA-side, not proxy bugs:** GLM 5.3 Flash and Gemma 4 return `504 Gateway Timeout` after ~302s (NVIDIA's own gateway timeout — raising the proxy's 600s upstream timeout cannot help); Kimi K2.6 returns `404` (not deployed for this key).
- **DeepSeek V4.1 Flash is flaky:** 504 on short budgets, success at `max_tokens=512` — consistent with cold starts.
- **Pool failover verified live:** Laguna XS 2.1 returned `503` on key A and the proxy automatically retried on key B (`Queue event=failover ... attempt=2`) → `200`. Key rotation across fingerprints confirmed in logs.
- **Trap discovered:** reasoning models (Kimi K3, GPT-OSS 20B, Muse Glimmer, Nemotron Super) show empty `content` at low `max_tokens`; content appears at `>= 256`. Also observed Nemotron 3.5 Lightning leaking chain-of-thought into `content` at low budgets.

## 4. Discrepancies Found (README vs. live behavior)

| README claim | Live finding |
| --- | --- |
| "GLM 5.2 remains supported where NVIDIA offers it" | N/A this session (GLM 5.3 used) |
| Kimi K2.6 documented with a model card | **404 on this key** — matches README's "evidence boundary" caveat |
| GLM 5.3 Flash documented | **504 on every attempt** — README caveat held |
| Small validation requests "did not confirm the full window" for GLM/Kimi/DeepSeek | Confirmed: DeepSeek needed a larger budget to respond at all |
| `/health` version | Reports `0.2.1` while `pyproject.toml` is `0.3.0` — stale `__version__` in `nvidia_nim_proxy/__init__.py`. Not fixed (would touch a release constant without a release); flagged in AGENTS.md traps. |

## 5. Documentation Scaffolding Created

Per the standing documentation standards:

- `docs/AGENTS.md` — operational manual (architecture map, setup, run instructions, search strategies, **Tool Quirks & Environment Traps** friction log, live model findings, conventions)
- `docs/origin.md` — reconstructed origin story and standing constraints (flagged as reconstructed; needs founder review)
- `docs/handoff/2026-10-09-setup-and-model-compat-testing.md` — this file
- `docs/research/model-selection.md` — workflow reasoning behind the model recommendations

## 6. One-Click Operations Tooling (added 2026-10-09, same session)

User requirement: *"every time I open ZCode I know it works"* — no log reading, no flag memorization. Delivered:

| File | Purpose |
| --- | --- |
| `launch_proxy.bat` | Double-click: starts the proxy headless, waits for health, runs a live GLM 5.3 test, prints a `PROXY READY` banner with the ZCode provider settings. Exit 0/1/2. |
| `launch_proxy.ps1` | The engine behind the bat (also usable directly, `-NoPause` for terminals/autostart). Headless start, logs to `%LOCALAPPDATA%\zcode-nvidia-nim-fix\proxy.log` (2MB rotation), auto-kills a wedged proxy before starting. |
| `check_proxy.ps1` | Glanceable status: RUNNING / NOT RUNNING / **WEDGED**. `-Stop` kills processes cleanly; `-Restart` recovers a wedge in one command. |
| `install_autostart.ps1` | Login-time Startup shortcut (installed; undo with `-Remove`). |

## 7. The Silent-Wedge Bug (discovered and mitigated 2026-10-09)

**Symptom:** minutes after the first one-click launch, every endpoint hung — `/health`, `/v1/models`, chat — while the process stayed alive with `LISTENING` on 18787, 0% CPU, and handler threads spawning on connect but never responding. ZCode's abandoned connection sat in `CLOSE_WAIT`. Diagnosis path (see AGENTS.md traps 14–16): accept loop alive (thread count rises on connect), no CPU spin, all threads in wait states, tests use ephemeral ports so pytest was exonerated. Leading theory: blocking writes to the minimized console's stderr buffer; **root cause not fully isolated**.

**Mitigation (architectural, verified):** the launcher now starts the proxy **headless** (`-WindowStyle Hidden`, stderr → `proxy.log`) instead of a minimized console window. After the change, the proxy served **continuous ZCode streaming for 4+ minutes with zero failures** (log shows rotating pool fingerprints, all 200s). Recovery tooling added: WEDGED state detection in `check_proxy.ps1` (health timeout ≠ connection refused) and `-Restart`.

**Verified end-to-end (all states):**
1. `check_proxy.ps1` on a stopped proxy → NOT RUNNING, exit 1 ✓
2. `launch_proxy.ps1 -NoPause` → headless start, live test passes, banner, exit 0 ✓ (ZCode requests began flowing immediately — the user was actively chatting)
3. `check_proxy.ps1` → RUNNING with pool/queue/catalog ✓
4. `check_proxy.ps1 -Restart` → old processes killed, fresh processes started (log timestamps prove the cycle), ZCode requests resumed with 200s ✓

Note: the sandbox harness kills bash-tool commands that spawn `Start-Process` children (`ChildProcess.kill`), but detached headless children survive — verified by process inspection afterward. Double-clicking the .bat is unaffected.

Docs updated: README "One-Click Startup and Status" + AGENTS.md run section and traps 14–16. Proxy left running headless via the new launcher flow.

## 8. Open Items for the Next Agent

1. **Structured `tool_calls` are untested per model.** This is the deciding factor for agentic/coding use. Probe with a tool-call payload on GLM 5.3, Kimi K3, and the Nemotrons before locking a daily driver.
2. **Version sync** (`__init__.py` 0.2.1 vs pyproject 0.3.0) before the next release.
3. **Re-probe the 504 models later** — NVIDIA endpoint availability is transient; Gemma 4 / GLM 5.3 Flash may recover.
4. **Founder review of `docs/origin.md`** — it was reconstructed from README/code, not from direct founder testimony.
5. If the proxy is ever run in Client mode, `launch_proxy.ps1` currently hardcodes Pool mode — extend its params before using it for other modes.
6. **Watch for wedge recurrence.** If the headless design ever wedges again, capture `proxy.log` at wedge time and consider a Python-level fix (handler socket timeouts, stderr unbuffered writes) rather than another restart band-aid.
