"""Exercise the read-only local dashboard page without exposing credentials."""

from __future__ import annotations

import http.client
import json
import sys
from contextlib import contextmanager
from pathlib import Path
from threading import Thread
from typing import Any, Iterator

import pytest

import nvidia_nim_proxy.server as module
from nvidia_nim_proxy.dashboard import DASHBOARD_PAGE
from nvidia_nim_proxy.model_catalog import ModelCatalog
from nvidia_nim_proxy.server import NIMProxyHandler, ProxyConfig, build_server


@contextmanager
def running_server(config: ProxyConfig) -> Iterator[int]:
    proxy = build_server("127.0.0.1", 0, config)
    thread = Thread(target=proxy.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
    thread.start()
    try:
        yield proxy.server_port
    finally:
        proxy.shutdown()
        proxy.server_close()
        thread.join(timeout=2)


def get(port: int, path: str) -> tuple[int, str, bytes]:
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        connection.request("GET", path)
        response = connection.getresponse()
        return response.status, response.getheader("Content-Type") or "", response.read()
    finally:
        connection.close()


def pool_config(**overrides: Any) -> ProxyConfig:
    settings: dict[str, Any] = dict(
        upstream_base_url="https://integrate.api.nvidia.com/v1",
        api_key="upstream-secret",
        api_key_mode="pool",
        pool_keys=("upstream-secret",),
        local_client_key="local-secret",
    )
    settings.update(overrides)
    return ProxyConfig(**settings)


def test_dashboard_page_bundles_every_asset_with_no_external_requests() -> None:
    assert "http://" not in DASHBOARD_PAGE
    assert "https://" not in DASHBOARD_PAGE
    assert "src=" not in DASHBOARD_PAGE
    assert "href=" not in DASHBOARD_PAGE


@pytest.mark.parametrize("mode", ["env", "client", "pool"])
def test_dashboard_serves_health_only_without_credentials(mode: str) -> None:
    config = pool_config(api_key_mode=mode)
    with running_server(config) as port:
        for path in ("/dashboard", "/dashboard/"):
            status, content_type, body = get(port, path)
            assert status == 200
            assert content_type.startswith("text/html")
            assert body.decode("utf-8") == DASHBOARD_PAGE

        page = DASHBOARD_PAGE
        for secret in ("upstream-secret", "local-secret", "NVIDIA_API_KEY"):
            assert secret not in page
        assert "/health" in page


def test_dashboard_returns_not_found_when_disabled() -> None:
    with running_server(pool_config(dashboard_enabled=False)) as port:
        status, content_type, body = get(port, "/dashboard")
        assert status == 404
        assert content_type.startswith("application/json")
        assert body == b'{"error":"not_found"}'


def test_disabled_dashboard_keeps_health_and_chat_routes_available(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = pool_config(dashboard_enabled=False)
    forwarded: list[dict[str, Any]] = []

    def forward(
        handler: NIMProxyHandler, body: dict[str, Any], *, client_authorization: str | None
    ) -> None:
        forwarded.append(body)
        handler._send_json(200, {"ok": True})

    monkeypatch.setattr(NIMProxyHandler, "_forward_to_nim", forward)
    with running_server(config) as port:
        assert get(port, "/dashboard")[:1] == (404,)
        status, _, _ = get(port, "/health")
        assert status == 200
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        try:
            connection.request(
                "POST",
                "/v1/chat/completions",
                body=json.dumps({"model": "m", "messages": []}),
                headers={
                    "Authorization": "Bearer local-secret",
                    "Content-Type": "application/json",
                },
            )
            response = connection.getresponse()
            assert response.status == 200
        finally:
            connection.close()
    assert forwarded == [{"model": "m", "messages": []}]


@pytest.mark.parametrize(
    "extra_args,enabled",
    [
        ([], True),
        (["--no-dashboard"], False),
        (["--host", "0.0.0.0", "--allow-remote"], False),
    ],
)
def test_main_enables_dashboard_only_for_loopback_when_not_disabled(
    extra_args: list[str],
    enabled: bool,
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    monkeypatch.setattr(sys, "argv", ["proxy", "--api-key-mode", "client", *extra_args])
    configs: list[ProxyConfig] = []
    closed: list[bool] = []

    class FakeServer:
        def serve_forever(self) -> None:
            raise KeyboardInterrupt()

        def server_close(self) -> None:
            closed.append(True)

    def build(host: str, port: int, config: ProxyConfig) -> Any:
        configs.append(config)
        return FakeServer()

    monkeypatch.setattr(module, "build_server", build)
    monkeypatch.setattr(ModelCatalog, "start", lambda self: None)
    module.main()
    assert configs[0].dashboard_enabled is enabled
    assert closed == [True]
