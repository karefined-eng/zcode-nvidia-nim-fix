## Target Location

- Workspace: docs/AGENTS.md  (section: "Tool Quirks & Environment Traps", append after existing item 18)

## Classification & Rationale

**Item 1 — Edit tool `oldString` matches first occurrence**
- Kind: rule — a single do/don't covers it.
- Scope: workspace — applies to all future edits in this repository where the edit tool is used.
- Evidence: at turn 8, targeting `_send_tool_call_text_diagnostic` in server.py deleted the `response_body = json.dumps(...)` line from `_send_json` because both share the signature `def _send_...`. Runtime `NameError: name 'response_body' is not defined` surfaced in pytest.

**Item 2 — Missing `import json` in test files**
- Kind: rule — a single do/don't ("always include stdlib imports per-file") states it fully.
- Scope: workspace — this project uses mypy strict; stdlib imports are not implicitly available across modules.
- Evidence: at turn 9, test_dashboard.py used `json.dumps` without `import json`; mypy reported `NameError: name 'json' is not defined`.

**Item 3 — Direct method assignment breaks mypy strict**
- Kind: rule — a single do/don't ("use `monkeypatch.setattr` for method replacement in tests") states it fully.
- Scope: workspace — this project enforces mypy strict; monkey-patching by assignment produces `Incompatible types in assignment`.
- Evidence: at turn 9, `NIMProxyHandler._forward_to_nim = forward` in test_dashboard.py failed mypy; switching to `monkeypatch.setattr(NIMProxyHandler, "_forward_to_nim", forward)` passed.

**Item 4 — In-process dashboard pattern for zero-RAM status page**
- Kind: skill — the pattern involves ordered steps: add module constant, route in `do_GET` before `/v1/models`, gate with `dashboard_enabled` config defaulting to `is_loopback_host(host)`, add `--no-dashboard` CLI flag, reuse secret-free `/health` data, log URL at startup, restart running proxies.
- Scope: workspace — specific to this proxy's architecture (stdlib HTTP server, no external deps, secret-free health endpoint).
- Evidence: at turns 6–10, the dashboard was implemented as a 5.3 KB inline HTML page served from the existing process; validation: 313 tests pass, ruff clean, mypy strict clean, live smoke test returned 200 with 5281 bytes.

## Scope

All four items apply to this repository's development workflow and codebase conventions. They do not apply globally to other projects unless those projects share the same toolchain (Kilo edit tool, mypy strict, stdlib-only Python server).

## Proposed Additions

anchor:
```
18. **Scheduled Tasks beat the Startup folder for this proxy.** The task trigger supports a logon **delay** (kills the startup race), `-ExecutionPolicy Bypass`, restart-on-failure, and an execution time limit; a Startup shortcut has none of these. Tasks register non-elevated for the current user (`-AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"`) — no admin prompt needed.
```

text to insert after that anchor:

```
19. **Edit tool `oldString` matches first occurrence.** When editing `server.py`, I targeted `_send_tool_call_text_diagnostic` but the match also caught the same `def` signature pattern inside `_send_json` logic, deleting the `response_body = json.dumps(...)` line → runtime `NameError`. Fix: make `oldString` unique by including more surrounding context (2-3 lines) or use `replaceAll` when intentionally changing multiple locations.

20. **Missing `import json` in new test file** caused `NameError: name 'json' is not defined` at mypy/runtime. Always include standard-library imports explicitly even when the test module already imports `json` elsewhere (module scope is per-file).

21. **Direct method assignment (`Class.method = func`) breaks mypy strict.** Assigning to `NIMProxyHandler._forward_to_nim` in a test produced `Incompatible types in assignment` — the signature is `def _forward_to_nim(self, ...)` vs the test's standalone `def forward(handler, ...)`. Fix: use `monkeypatch.setattr(NIMProxyHandler, "_forward_to_nim", forward)` — pytest's monkeypatch preserves type compatibility and auto-restores.

22. **`GET /dashboard` served by the existing proxy process** costs ~0 extra RAM. When adding an in-process status page, route it in `do_GET` before `/v1/models`, gate it with a `dashboard_enabled` config flag (default `is_loopback_host(host)`), and add `--no-dashboard` CLI override — no separate process, no upstream calls, no auth (reuses secret-free `/health` data). Restart required for running proxies to pick up new routes.
```

## Conflicts and Alternatives

- The four items were already appended to AGENTS.md during the session (as items 19–22) per the project's mandatory friction-logging rule. This proposal formalizes them through the learn skill's approval gate. No existing rules are contradicted.
- Update-not-create was taken: AGENTS.md already owns "Tool Quirks & Environment Traps". Creating a separate file would fragment the trap log.
- Item 4 (dashboard pattern) could alternatively be extracted to a skill `skills/in-process-dashboard/SKILL.md` for reuse across projects. This proposal keeps it as a rule in AGENTS.md because the pattern is tightly coupled to this proxy's specific architecture (stdlib server, secret-free `/health`, loopback-only binding). If another project adopts the same stack, a skill can be created then.

## Verification Plan

1. Re-read `docs/AGENTS.md` after edit and confirm items 19–22 appear verbatim under "Tool Quirks & Environment Traps".
2. Run the project's verification commands:
   - `.\.venv\Scripts\python.exe -m pytest` — expect 313 passed
   - `.\.venv\Scripts\python.exe -m ruff check .` — expect "All checks passed!"
   - `.\.venv\Scripts\python.exe -m mypy nvidia_nim_proxy tests` — expect "Success: no issues found"
3. Smoke test the dashboard: start proxy on an alternate port with `--api-key-mode client --no-model-discovery`, fetch `/dashboard`, verify 200 and HTML body contains "NVIDIA NIM Proxy".

## Outcome

**Approved** at 2026-10-10T10:11:53Z by user.

### Verification Results

| Check | Result |
|-------|--------|
| AGENTS.md items 19–22 present | ✅ Confirmed verbatim at lines 147–153 |
| pytest (313 tests) | ✅ 313 passed in 30.42s |
| ruff check | ✅ All checks passed! |
| mypy strict (25 files) | ✅ Success: no issues found |
| Dashboard smoke test | ✅ 200 OK, 5281 bytes, title present |

All four learnings are now durably recorded in `docs/AGENTS.md` under "Tool Quirks & Environment Traps".