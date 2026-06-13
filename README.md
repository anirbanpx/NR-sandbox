# NR Sandbox

A minimal process-monitoring prototype built to compare two observability stacks —
**New Relic Infrastructure** and **Grafana Cloud via OpenTelemetry** — on a single EC2 host.

The core question: how quickly does each stack surface per-process visibility out of the box,
and what does it take to get there?

---

## What's running

```
                        ┌─────────────────────────────────────┐
                        │            EC2 t3.micro             │
                        │                                     │
  HTTP traffic          │  nginx (reverse proxy, :80)         │
  ──────────────────►   │    └─► FastAPI app (:8000)          │
                        │          └─► Redis (jobs queue)     │
                        │    └─► Background worker            │
                        │                                     │
                        │  OTel Collector                     │
                        │    ├─ hostmetrics (CPU/mem/disk/net)│
                        │    ├─ process scraper (per-PID)     │
                        │    └─► Grafana Cloud (OTLP)         │
                        │                                     │
                        │  NR Infrastructure agent            │
                        │    └─► New Relic (EU)               │
                        └─────────────────────────────────────┘
```

**FastAPI app** — five endpoints: read items, write items, an intentionally slow endpoint
(1.5–3s latency), and an intentional 500 error. Backed by Redis for state. Ships a
bare-bone browser UI at `/` for live demos (no curl needed).

**Background worker** — polls a Redis queue and processes jobs. Intentionally not
auto-instrumented by either stack — killing it mid-run is the central demo moment.

**OTel Collector** — collects host metrics and per-process metrics, exports to Grafana Cloud.

**NR Infrastructure agent** — ships host-level metrics to New Relic.

---

## Repository layout

```
app/            FastAPI application + background worker
  main.py       API endpoints
  worker.py     Redis queue consumer
  telemetry.py  OTel SDK setup (traces, metrics, logs)
  static/       Demo UI (single-page HTML, served at /)

collector/
  otel-collector.yaml   OTel Collector config (hostmetrics + OTLP export)
  prometheus.yml        Prometheus scrape config (reference)

infra/
  provision-ec2.sh  One-time EC2 setup (key pair, security group, instance)
  deploy.sh         Sync repo + run setup-ec2.sh
  setup-ec2.sh      Idempotent bootstrap: installs app, NR agent, OTel Collector
  teardown-ec2.sh   Terminate instance and clean up AWS resources
  nginx.conf        Reverse proxy config
  .env.example      Required environment variables

loadgen/
  locustfile.py     Locust load generator (30 users, realistic traffic mix)

tests/
  test_api.py       Integration tests (6 tests, no mocks)

spec/
  requirements.md   Problem statement and goals
  design.md         Architecture decisions + demo narrative
  implementation.md Deployment steps + verification checklist
```

---

## Quick start

### Local development

```bash
# install dependencies
pip install -r app/requirements.txt

# start Redis (Docker)
docker run -d -p 6379:6379 redis:7

# run the app (telemetry disabled locally)
OTEL_SDK_DISABLED=true uvicorn app.main:app --reload
# demo UI available at http://localhost:8000

# run the worker (separate terminal)
OTEL_SDK_DISABLED=true python -m app.worker

# run tests
pip install -r tests/requirements-test.txt
pytest tests/
```

### EC2 deployment

See [`infra/README.md`](infra/README.md) for the full deployment walkthrough.

Short version:
```bash
# 1. provision (one-time)
bash infra/provision-ec2.sh

# 2. add credentials
cp infra/.env.example infra/.env
# edit .env — add NR_LICENSE_KEY and GRAFANA_* values

# 3. deploy
bash infra/deploy.sh

# 4. verify
curl http://<public-ip>/health
```

---

## Observability stacks

| | New Relic | Grafana Cloud |
|---|---|---|
| Agent | NR Infrastructure agent | OTel Collector contrib |
| Transport | Proprietary (NR ingest) | OTLP/HTTP |
| Host metrics | Yes (built-in) | Yes (hostmetrics receiver) |
| Per-process metrics | Yes (built-in) | Yes (process scraper) |
| App traces | NR APM agent (separate) | OTel SDK → Collector |
| EU region | `eu0*` key prefix + `collector_url` | endpoint URL contains region |

---

## Load generator

```bash
# headless, 30 users, runs on EC2 against localhost
locust -f loadgen/locustfile.py --host http://localhost \
  --headless -u 30 -r 3 --run-time 30m

# with UI (local, against EC2)
locust -f loadgen/locustfile.py --host http://<ec2-ip>
```

Traffic mix: 80% GET /items · 15% POST /items · 4% GET /items/slow · 1% GET /items/error
