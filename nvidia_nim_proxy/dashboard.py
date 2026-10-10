"""Read-only local status page served by the proxy."""

from __future__ import annotations

DASHBOARD_PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>NVIDIA NIM Proxy</title>
<style>
:root {
  color-scheme: dark;
  --bg: #0f1115;
  --card: #171a21;
  --line: #262b36;
  --text: #e6e9ef;
  --muted: #8b93a7;
  --ok: #3fb950;
  --warn: #d29922;
  --bad: #f85149;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  padding: 24px;
  background: var(--bg);
  color: var(--text);
  font: 14px/1.5 "Segoe UI", system-ui, sans-serif;
}
h1 { font-size: 18px; margin: 0 0 4px; }
.sub { color: var(--muted); margin: 0 0 20px; }
.grid {
  display: grid;
  gap: 12px;
  grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
  max-width: 920px;
}
.card {
  background: var(--card);
  border: 1px solid var(--line);
  border-radius: 10px;
  padding: 14px 16px;
}
.card h2 {
  margin: 0 0 10px;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: .08em;
  text-transform: uppercase;
  color: var(--muted);
}
.pill {
  display: inline-block;
  padding: 2px 10px;
  border-radius: 999px;
  font-size: 12px;
  font-weight: 600;
}
.pill.ok { background: rgba(63, 185, 80, .15); color: var(--ok); }
.pill.warn { background: rgba(210, 153, 34, .15); color: var(--warn); }
.pill.bad { background: rgba(248, 81, 73, .15); color: var(--bad); }
.value { font-size: 22px; font-variant-numeric: tabular-nums; margin-bottom: 4px; }
.row { display: flex; justify-content: space-between; gap: 12px; padding: 3px 0; }
.row span:last-child { font-variant-numeric: tabular-nums; }
.mono { font-family: ui-monospace, "Cascadia Code", Consolas, monospace; font-size: 12px; word-break: break-all; }
.foot { color: var(--muted); margin-top: 16px; font-size: 12px; }
</style>
</head>
<body>
<h1>NVIDIA NIM Proxy</h1>
<p class="sub">Local read-only status. Refreshes every 2 seconds from <span class="mono">GET /health</span>; no credentials are shown.</p>
<div class="grid">
  <div class="card">
    <h2>Proxy</h2>
    <div id="state" class="pill warn">checking</div>
    <div class="row"><span>Mode</span><span id="mode">-</span></div>
    <div class="row"><span>Version</span><span id="version">-</span></div>
  </div>
  <div class="card">
    <h2>Queue</h2>
    <div id="queue" class="value">-</div>
    <div class="row"><span>Active</span><span id="active">-</span></div>
    <div class="row"><span>Waiting</span><span id="queued">-</span></div>
  </div>
  <div class="card">
    <h2>Key pool</h2>
    <div id="pool">-</div>
  </div>
  <div class="card">
    <h2>Model catalog</h2>
    <div id="catalog">-</div>
  </div>
  <div class="card">
    <h2>Upstream</h2>
    <div id="upstream" class="mono">-</div>
  </div>
</div>
<p class="foot">Last update: <span id="stamp">-</span></p>
<script>
function setText(id, value) {
  document.getElementById(id).textContent = String(value);
}
function setPill(id, level, label) {
  const pill = document.getElementById(id);
  pill.className = "pill " + level;
  pill.textContent = label;
}
function row(name, value) {
  return '<div class="row"><span>' + name + '</span><span>' + value + '</span></div>';
}
function resetCards() {
  setText("mode", "-");
  setText("version", "-");
  setText("upstream", "-");
  setText("active", "-");
  setText("queued", "-");
  document.getElementById("queue").textContent = "-";
  document.getElementById("pool").textContent = "-";
  document.getElementById("catalog").textContent = "-";
}
function render(health) {
  setPill("state", "ok", health.status || "ok");
  setText("mode", health.mode);
  setText("version", health.version);
  setText("upstream", health.upstream);
  const queue = health.queue || {};
  setText("active", queue.active || 0);
  setText("queued", queue.queued || 0);
  document.getElementById("queue").textContent = (queue.active || 0) + " running / " + (queue.queued || 0) + " waiting";
  const pool = health.key_pool;
  if (pool) {
    const level = pool.quarantined > 0 ? "warn" : "ok";
    document.getElementById("pool").innerHTML = row("Available", pool.available + " / " + pool.total) +
      row("Cooling down", '<span style="color: var(--warn)">' + pool.cooling_down + "</span>") +
      row("Quarantined", '<span style="color: var(--bad)">' + pool.quarantined + "</span>") +
      row("Active", pool.active);
    setPill("state", level, pool.quarantined > 0 ? "key quarantined" : (health.status || "ok"));
  } else {
    document.getElementById("pool").textContent = "No pool (single-key mode)";
  }
  const catalog = health.model_catalog || {};
  const status = catalog.status || "unknown";
  const level = status === "ready" ? "ok" : (status === "disabled" ? "warn" : "bad");
  document.getElementById("catalog").innerHTML =
    row("Status", '<span class="pill ' + level + '">' + status + "</span>") +
    row("Models", catalog.count === undefined ? "-" : catalog.count);
}
async function refresh() {
  try {
    const response = await fetch("/health", { cache: "no-store" });
    if (!response.ok) {
      throw new Error("HTTP " + response.status);
    }
    render(await response.json());
  } catch (error) {
    resetCards();
    setPill("state", "bad", "unreachable");
  }
  setText("stamp", new Date().toLocaleTimeString());
}
refresh();
setInterval(refresh, 2000);
</script>
</body>
</html>
"""

__all__ = ["DASHBOARD_PAGE"]
