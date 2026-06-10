# Implementation Plan

## Phase 1 — Application & Instrumentation

Build the FastAPI app with OTel instrumentation and the background worker.

- `app/main.py` — 5 endpoints: `/health`, `/items` (GET/POST), `/items/slow`, `/items/error`
- `app/worker.py` — long-running background process (queue consumer / polling loop)
- `app/telemetry.py` — OTel SDK: TracerProvider + MeterProvider + LoggingHandler → OTLP :4317
- `app/requirements.txt` — fastapi, uvicorn, opentelemetry-sdk + instrumentation packages

## Phase 2 — Collector & Load Generator

Configure the OTel Collector and traffic simulation.

- `collector/otel-collector.yaml` — receivers: `hostmetrics` (process scraper) + `otlp`;
  exporters: Grafana Cloud OTLP endpoint
- `collector/prometheus.yml` — scrape config for local metrics endpoints
- `loadgen/locustfile.py` — mixed load: 80% GET /items, 15% POST /items, 5% /slow + /error

## Phase 3 — EC2 Deployment

Provision the EC2 instance and run both instrumentation paths simultaneously.

- `infra/setup-ec2.sh` — installs Python 3.11, nginx, redis, locust; registers OTel
  Collector and New Relic Infrastructure agent as systemd services; starts all app processes
- `infra/nginx.conf` — routes port 80 → uvicorn :8000
- EC2 IAM: no AWS-specific permissions needed (all telemetry goes to external clouds)
- Security group: inbound port 22 (SSH, your IP only), port 80 (HTTP)

## Phase 4 — Prototype & Comparison

Build the observability prototype and document findings.

- Grafana dashboard (exported as `prototype/dashboard.json`) — process visibility view
  using data from the OTel hostmetrics process scraper
- `prototype/queries.md` — key PromQL queries (Path A) alongside equivalent NRQL
  queries (Path B) for direct comparison

## Verification Checklist

- [ ] `curl <ec2-ip>/health` returns 200
- [ ] OTel Collector forwarding data — visible in Grafana Cloud within 60s of startup
- [ ] New Relic Infrastructure UI shows EC2 host with all processes listed
- [ ] New Relic APM shows FastAPI service with distributed traces
- [ ] Locust traffic generating visible request rate and error rate signals
- [ ] `/items/slow` endpoint produces latency spikes observable in both stacks
