# Research — Model Selection for This Project's Workflow

**Date:** 2026-10-09
**Question:** Of the 12 documented chat models reachable through the proxy, which is best suited to the actual work this project involves?
**Method:** Live probing through the running proxy (12 models, repeated requests), correlated with the proxy's own registries (`model_profiles.py`, `model_limits.py`) and the README's evidence-boundary section.

## What "this work" actually is

The dominant tasks are: reading long proxy logs and correlating events across modules; cross-referencing README claims against live endpoint behavior; diagnosing status-code chains (504 → failover → 200); and writing precise, structured summaries. It is **diagnostic and correlative work**, not greenfield feature work. That shapes the selection criteria below.

## Criteria and why they matter (cognitive rationale)

| Criterion | Weight | Psychological / operational reason |
| --- | --- | --- |
| Reliability (consistent 200s) | Highest | Every failed call is a context switch. A 302s timeout destroys flow state far more than a slightly worse answer. |
| Iteration latency | High | Diagnostic loops are short-prompt/high-frequency; the user tolerates wait per call, not per minute. |
| Output budget | High | Multi-file edits and long analyses get truncated mid-thought at small budgets — the error surfaces as *silent wrongness*, the worst failure mode. |
| Context window | Medium | Log traces + code + README routinely exceed 100K tokens; matters, but rarely the binding constraint here. |
| Effort control | Medium | Being able to dial `max` for a hard correlation and `low` for a log skim prevents both over-thinking and under-thinking. |
| Raw model size | Low | All 12 clear the bar for this task class; size is not the bottleneck. |

## Findings that drove the ranking

1. **GLM 5.3 was the only 100%-reliable model** (14 requests, zero failures, ~3–6s). The 504 models (GLM 5.3 Flash, Gemma 4) fail *after* the full upstream timeout — the proxy's 600s setting cannot rescue an NVIDIA gateway that gives up at 302s.
2. **GPT-OSS 20B is disqualified for editing work by its 4,096-token output cap** — verified against NVIDIA's hosted schema. Truncation mid-edit is a silent-failure trap.
3. **Kimi K3 is the only model with controllable effort** (`low`/`high`/`max`, set in the request body). The proxy even strips sampling fields NVIDIA documents as fixed for it — evidence the profile is maintained and correct.
4. **Pool failover works as designed** (observed live: 503 → automatic retry on next key → 200), so single-key flakiness is survivable; *model-level* 504s are not, because every key hits the same dead deployment.
5. **Reasoning models hide output at low budgets** (content only in `reasoning_content` until `max_tokens >= 256`) — a usability trap when comparing models with short probes.

## Recommendation

- **Daily driver: `z-ai/glm-5.3`** — 1M context, 16,384 output budget, native `max` reasoning default, and the only model that never failed. Reliability + speed is the compound win for diagnostic loops.
- **Alternate: `moonshotai/kimi-k3`** — when a task benefits from explicit effort control, or as failover diversity against GLM outages.
- **Throughput: `nvidia/nemotron-3.5-lightning-30b-a3b`** — 1M context with only 30B active params (MoE) makes it the right pick for bulk log scanning if cost/latency at volume ever matters.
- **Avoid for now:** GPT-OSS 20B (4K cap), Muse Glimmer (131K, no profile), Laguna (262K, one 503), and the three failing models (Gemma 4, GLM 5.3 Flash, Kimi K2.6).

## Evidence boundary (honest limits)

- **Structured `tool_calls` were not tested.** If the workflow becomes agentic (file edits, multi-step tool use), this probe must be re-run with a tool-call payload before the choice is final.
- Latency figures are single-run observations under one load condition, not benchmarks.
- NVIDIA endpoint availability is transient; the 504/404 verdicts are as-of 2026-10-09 and worth re-probing.
