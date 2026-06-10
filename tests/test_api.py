"""
API integration tests — run without any live infra.

Telemetry is disabled via OTEL_SDK_DISABLED; Redis is replaced with a MagicMock
via FastAPI's dependency_overrides so no redis server is required.

Run:
    pip install -r tests/requirements-test.txt
    pytest tests/ -v
"""
import os

os.environ["OTEL_SDK_DISABLED"] = "true"

from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient

from app.main import app, get_redis


@pytest.fixture(autouse=True)
def mock_redis():
    r = MagicMock()
    r.keys.return_value = []
    r.get.return_value = None
    app.dependency_overrides[get_redis] = lambda: r
    yield r
    app.dependency_overrides.clear()


client = TestClient(app)


def test_health():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_list_items_empty(mock_redis):
    mock_redis.keys.return_value = []
    resp = client.get("/items")
    assert resp.status_code == 200
    assert resp.json() == {}


def test_list_items_populated(mock_redis):
    mock_redis.keys.return_value = ["item:foo", "item:bar"]
    mock_redis.get.side_effect = lambda k: {"item:foo": "1", "item:bar": "2"}[k]
    resp = client.get("/items")
    assert resp.status_code == 200
    assert resp.json() == {"foo": "1", "bar": "2"}


def test_create_item(mock_redis):
    resp = client.post("/items", json={"name": "widget", "value": "blue"})
    assert resp.status_code == 201
    assert resp.json() == {"name": "widget", "value": "blue"}
    mock_redis.set.assert_called_once_with("item:widget", "blue")


def test_slow_endpoint():
    resp = client.get("/items/slow")
    assert resp.status_code == 200
    body = resp.json()
    assert "latency_ms" in body
    assert body["latency_ms"] >= 1500


def test_error_endpoint():
    resp = client.get("/items/error")
    assert resp.status_code == 500
    assert resp.json()["detail"] == "intentional error"
