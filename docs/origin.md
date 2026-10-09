# Origin

> **Agents: read this file before proposing any major architectural change, UI redesign, or feature-scope change.** Do not deviate from the vision established here.

## The Origin Story

This project exists because of a single, stubborn error. ZCode — an AI coding IDE — sent chat requests to NVIDIA NIM's hosted OpenAI-compatible endpoint with a literal `extra_body` field in the JSON payload. NVIDIA's endpoint does not accept that field and rejects every request with:

```
400 Unsupported parameter(s): extra_body
```

The fix that could not be made in ZCode had to be made *between* ZCode and NVIDIA. Hence: a local proxy. It accepts whatever ZCode sends, strips the fields NVIDIA refuses, and forwards a clean request. That is the whole origin of `zcode-nvidia-nim-fix`.

## Core Reasoning

The vision that emerged from that first fix, in the founder's own framing:

1. **Intercept, don't patch.** The incompatibility lives in the client's request shape. A local translation layer is the only place it can be fixed without upstream cooperation.
2. **Trust nothing about the model contract.** A model card is not a hosted endpoint. The proxy maps only *verified* per-model behavior (reasoning effort, fixed sampling fields, context limits) and refuses to guess. Where NVIDIA's documentation is silent, the proxy sends nothing rather than inventing a wire field.
3. **The pool exists because rate limits are per-key.** Rotation and bounded queues spread load across keys — they cannot bypass NVIDIA's per-account or per-model limits, and the proxy never claims to.
4. **Zero runtime dependencies.** The proxy is stdlib-only so it can never break a user's environment. Tests and tooling may have dev dependencies; the shipped package may not.
5. **Secrets never leave the machine.** Keys live only in local `.env`, process environment, or the IDE credential store. Logs print fingerprints, not keys.

## Psychological Intent

The work is aimed at a developer who is *already frustrated*: they picked a model, they paid for a key, and the IDE rejected every message with a cryptic 400. The design answers that state with:

- **Immediate, honest diagnostics.** Errors say what happened and what to do (`401 from local Pool provider → use NIM_PROXY_CLIENT_KEY`), never a stack trace.
- **Conservative defaults that never surprise.** A failed model call fails with a real upstream status, not a masked one. The proxy does not silently retry what cannot be safely retried (a started SSE stream).
- **Documentation as product.** The README is not decoration; it is the interface for a tool whose value is measured in removed friction.

## Standing Constraints for Future Agents

- Do not add third-party runtime dependencies.
- Do not invent model-specific wire fields; verify against NVIDIA's hosted docs first.
- Do not weaken the duplicate-key, quarantine, or credential checks — they are deliberate safety properties, not bugs.
- Keep the proxy a *translation* layer. It is not a router, not a caching service, not a rate-limit bypass.
- The GLM 5.2 `extra_body` regression case in `tests/test_integration.py` is the founding test. It must keep passing.

## Provenance Note

This file was reconstructed on 2026-10-09 from the project README and codebase conventions (no prior origin document existed). The founder of record is Levent Dogan. If any framing above misstates the original intent, correct this file — future agents treat it as canonical.
