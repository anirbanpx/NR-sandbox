# NR Sandbox — Process Monitoring: A Teardown and Prototype

This repository contains the hands-on component of a product exercise examining **why process
monitoring is foundational yet under-adopted** — and what can be done about it. Rather than
relying on a documentation review, I deployed a real workload on AWS, instrumented it with **two
stacks in parallel** (New Relic and OpenTelemetry/Grafana), deliberately introduced failures, and
documented every point at which a practitioner loses confidence between *installation* and *trust*.
I then designed a remedy and built it as a clickable prototype.

The central question throughout: how quickly does each stack surface trustworthy per-process
visibility out of the box, and what is required to get there?

---

## Reviewer's Guide

| Deliverable | Description | Open it |
|---|---|---|
| **Interactive prototype** | The proposed "Process Coverage" view — a clickable four-screen fix with a built-in guided walkthrough | **[Launch the prototype](https://anirbanpx.github.io/NR-sandbox/prototype/)** |
| **Friction log** | The core findings: a step-by-step teardown of the practitioner journey, evidenced with screenshots | **[docs/friction-log.md](docs/friction-log.md)** |
| **Grafana live dashboard** | OTel hostmetrics on the live EC2 instance — CPU, memory, 133 named processes, load average (publicly accessible, no authentication required) | **[Open dashboard](https://cyanpiano2691.grafana.net/public-dashboards/1b74cf98134b47ba84ed1bf32f369a7a)** |
| **New Relic live view** | New Relic Infrastructure agent on the same host — named process list, APM, host metrics | **[Open New Relic](https://onenr.io/0ERPxbDZPRW)** |
| **Evidence** | The raw screenshots behind every finding | **[docs/images/](docs/images/)** |
| **The build** | The dual-instrumented workload deployed for this exercise — real traffic, real host | [Architecture ↓](#observability-architecture) · [app/](app/) · [infra/](infra/) |
| **Mock source** | Prototype source and a static panel export | [prototype/](prototype/) · [docs/mocks/](docs/mocks/) |
| **Demo video** | Approximately 1.5-minute walkthrough: AWS console, live web application, Grafana and New Relic side by side | **[Watch on YouTube](https://youtu.be/TQgK1YVJlbc)** |

> **First time here?** Begin with the **prototype** — it tells the story in roughly a minute —
> then read the **friction log** for the supporting evidence. The remainder of this document
> describes the build that produced both.

---

## Components

**FastAPI application** — full CRUD operations on items (`GET`/`POST`/`PUT`/`DELETE`), an
intentionally slow endpoint (1.5–3 second latency), and an intentional 500 error. Backed by
Redis. Includes a minimal browser UI at `/` for live demonstrations, requiring no command-line
tools.

**Background worker** — polls a Redis queue and processes jobs. Deliberately left
uninstrumented by either stack; terminating it mid-run is the central demonstration moment.

**OTel Collector** — collects host metrics and per-process metrics, and exports them to
Grafana Cloud.

**New Relic Infrastructure agent** — transmits host-level metrics to New Relic.

---

## Observability Architecture

```
  HTTP traffic        ┌──────────────────── EC2 t3.micro ──────────────────────────┐
  ─────────────────►  │                                                              │
                      │  nginx :80 ──► FastAPI :8000 ──────────► Redis :6379        │
                      │                    │    │                        ▲           │
                      │            OTel    │    │  NR APM           worker.py        │
                      │            SDK ①   │    │  agent ②         (background)     │
                      │                    ▼    │                                    │
                      │  ┌───────────────────────────────────────┐                  │
                      │  │  OTel Collector                       │◄── all procs ③  │
                      │  │  · OTLP recv :4317  ◄── app ①        │                  │
                      │  │  · hostmetrics      ◄── host ③        │                  │
                      │  └───────────────────────────────────────┘                  │
                      │  ┌───────────────────────────────────────┐                  │
                      │  │  NR Infrastructure Agent              │◄── all procs ③  │
                      │  │  · host metrics + process list        │                  │
                      │  └───────────────────────────────────────┘                  │
                      └──────────────┬──────────────────────────────┬───────────────┘
                                     │                              │
                                     ▼                              ▼
                        ┌─────────────────────────┐   ┌──────────────────────────┐
                        │      Grafana Cloud       │   │      New Relic (EU)      │
                        │  Prometheus — metrics    │   │  Infrastructure — hosts  │
                        │  Tempo      — traces     │   │  APM            — svcs   │
                        │  Loki       — logs       │   │  Logs                    │
                        └─────────────────────────┘   └──────────────────────────┘
                               Path A (OSS)                   Path B (New Relic)

  ① OTel SDK — traces, metrics, logs exported from the app via OTLP
  ② New Relic APM agent — in-process, ships app telemetry directly to New Relic
  ③ host + per-process metrics — CPU, memory, per-PID stats for all running processes
```

Both stacks observe the same host and processes (③). The central demonstration: terminate
`worker.py` and observe how quickly, or slowly, each stack surfaces the missing process.

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
  setup-ec2.sh      Idempotent bootstrap: installs app, New Relic agent, NRDOT collector, OTel Collector
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

docs/             Committee-facing deliverables
  friction-log.md The product teardown — findings + screenshots
  images/         Screenshot evidence behind the findings
  mocks/          Static mock export (process-coverage panel)

prototype/        The clickable "Process Coverage" prototype (hosted on GitHub Pages)
  index.html      Self-contained 4-screen interactive mock
  fonts/          Self-hosted Inter (no external dependency)
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

Refer to [`infra/README.md`](infra/README.md) for the complete deployment walkthrough.

Summary:
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
| Agent | New Relic Infrastructure agent + NRDOT v1.16.0¹ | OTel Collector contrib |
| Transport | Proprietary (New Relic ingest) | OTLP/HTTP |
| Host metrics | Yes (built-in) | Yes (hostmetrics receiver) |
| Per-process metrics | Yes (built-in) | Yes (process scraper) |
| App traces | New Relic APM agent (separate) | OTel SDK → Collector |
| EU region | `eu0*` key prefix + `collector_url` | endpoint URL contains region |

¹ NRDOT (`nrdot-collector`) is New Relic's production-grade OTel distribution, installed alongside the
infra agent to cross-check default process-metrics behaviour on the OTel path. Both ship to New
Relic; the infra agent is the primary collector.

---

## Load generator

```bash
# headless, 30 users, runs on EC2 against localhost
locust -f loadgen/locustfile.py --host http://localhost \
  --headless -u 30 -r 3 --run-time 30m

# with UI (local, against EC2)
locust -f loadgen/locustfile.py --host http://<ec2-ip>
```

Traffic mix: 74% GET /items · 13% POST /items · 7% PUT /items/{name} · 4% GET /items/slow · 1% DELETE /items/{name} · 1% GET /items/error
