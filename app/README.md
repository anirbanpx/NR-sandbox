# app

FastAPI application and background worker — the workload being monitored by both
observability stacks.

## Components

### `main.py` — API server

Seven endpoints (full CRUD + observability signals):

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Liveness check |
| GET | `/items` | Read all items from Redis |
| POST | `/items` | Create an item in Redis |
| PUT | `/items/{name}` | Update an item's value (404 if not found) |
| DELETE | `/items/{name}` | Delete an item (404 if not found) |
| GET | `/items/slow` | Sleeps 1.5–3s — drives latency signal |
| GET | `/items/error` | Returns HTTP 500 — drives error rate signal |

`GET /` redirects to the demo UI at `/static/index.html`.

Auto-instrumented via `FastAPIInstrumentor` — all requests produce OTel spans when
the collector is running.

### `static/index.html` — demo UI

Single-page browser UI served by FastAPI. Lets you exercise all five endpoints
without curl: check app status, list/create items, trigger a slow request, and
trigger an error — useful for live demos.

### `worker.py` — background worker

Polls a Redis queue (`jobs:pending`) and processes jobs. Deliberately not
auto-instrumented by either observability stack out of the box. Killing it mid-run
is the central demo moment: the process disappears from the host process list but
neither stack fires an alert by default.

### `telemetry.py` — OTel SDK setup

Configures traces, metrics, and logs exporters pointing at
`OTEL_EXPORTER_OTLP_ENDPOINT` (defaults to `http://localhost:4317`).
Set `OTEL_SDK_DISABLED=true` to disable all telemetry (used in tests and local dev).

## Running locally

```bash
pip install -r app/requirements.txt

# Redis required
docker run -d -p 6379:6379 redis:7

# API server (port 8000, telemetry off)
OTEL_SDK_DISABLED=true uvicorn app.main:app --reload
# demo UI at http://localhost:8000

# Background worker (separate terminal)
OTEL_SDK_DISABLED=true python -m app.worker
```

## Running with telemetry

Requires the OTel Collector to be running and reachable at `localhost:4317`.

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
OTEL_SERVICE_NAME=nr-sandbox \
uvicorn app.main:app
```

## Tests

```bash
pip install -r tests/requirements-test.txt
pytest tests/ -v
```

Six integration tests cover all endpoints. Tests run against the real app with a
real Redis connection — no mocks.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `REDIS_URL` | `redis://localhost:6379` | Redis connection URL |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4317` | OTel Collector OTLP endpoint |
| `OTEL_SERVICE_NAME` | `nr-sandbox` | Service name in traces and metrics |
| `OTEL_SDK_DISABLED` | `false` | Set to `true` to disable all telemetry |
| `WORKER_POLL_INTERVAL` | `2` | Redis poll interval in seconds |
