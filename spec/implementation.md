# Implementation Plan

## [x] Phase 1 — Application & Instrumentation

Build the FastAPI app with OTel instrumentation and the background worker.

- `app/main.py` — full CRUD: `/health`, `/items` (GET/POST/PUT/DELETE), `/items/slow`, `/items/error`; `GET /` redirects to demo UI
- `app/worker.py` — long-running background process (queue consumer / polling loop)
- `app/telemetry.py` — OTel SDK: TracerProvider + MeterProvider + LoggingHandler → OTLP :4317
- `app/requirements.txt` — fastapi, uvicorn, opentelemetry-sdk + instrumentation packages
- `app/static/index.html` — single-page demo UI; exercises all endpoints from a browser without curl

## [x] Phase 2 — Collector & Load Generator

Configure the OTel Collector and traffic simulation.

- `collector/otel-collector.yaml` — receivers: `hostmetrics` (process scraper) + `otlp`;
  exporters: Grafana Cloud OTLP endpoint
- `collector/prometheus.yml` — scrape config for local metrics endpoints
- `loadgen/locustfile.py` — mixed load: 80% GET /items, 15% POST /items, 4% /slow, 1% /error

## [x] Phase 3 — EC2 Deployment

Provision the EC2 instance and run both instrumentation paths simultaneously.

- `infra/provision-ec2.sh` — creates key pair, security group, and t3.micro instance
- `infra/deploy.sh` — syncs repo to EC2 and invokes `setup-ec2.sh`
- `infra/setup-ec2.sh` — installs Python 3.11, nginx, redis6, locust; registers OTel
  Collector and New Relic Infrastructure agent as systemd services; starts all app processes
- `infra/nginx.conf` — routes port 80 → uvicorn :8000
- `infra/teardown-ec2.sh` — terminates instance and deletes security group
- EC2 IAM: no AWS-specific permissions needed (all telemetry goes to external clouds)
- Security group: inbound port 22 (SSH, your IP only), port 80 (HTTP)
- Region: ap-south-2 (Hyderabad); EU NR accounts need `collector_url` override in
  `newrelic-infra.yml` — handled automatically by `setup-ec2.sh` based on key prefix

## [ ] Phase 4 — Prototype & Comparison

Build the observability prototype and document findings.

- Grafana dashboard (exported as `prototype/dashboard.json`) — process visibility view
  using data from the OTel hostmetrics process scraper
- `prototype/queries.md` — key PromQL queries (Path A) alongside equivalent NRQL
  queries (Path B) for direct comparison

## Verification Checklist

- [x] `curl <ec2-ip>/health` returns 200
- [x] OTel Collector forwarding data — visible in Grafana Cloud within 60s of startup
- [x] New Relic Infrastructure UI shows EC2 host with all processes listed
- [ ] New Relic APM shows FastAPI service with distributed traces (requires NR Python APM agent)
- [x] Locust traffic generating visible request rate and error rate signals
- [x] `/items/slow` endpoint produces latency spikes observable in both stacks
- [ ] Killing `worker.py` demonstrates the process-visibility gap in each stack
- [ ] Process-visibility gap is clearly demonstrable across both stacks (not just data flowing)
