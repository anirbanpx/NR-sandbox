# Design: Infrastructure & Process Monitoring

## Host Architecture (EC2 t3.micro, Amazon Linux 2023, ap-south-2)

```
┌─────────────────────────────────────────────────────┐
│  EC2 t3.micro                                       │
│                                                     │
│  nginx (port 80)          ← reverse proxy           │
│  uvicorn / FastAPI (8000) ← main service            │
│  python worker.py         ← background processor   │
│  redis-server             ← cache                  │
│  sshd, systemd            ← OS processes            │
│                                                     │
│  locust (headless)        ← traffic simulation      │
└─────────────────────────────────────────────────────┘
```

## Instrumentation Paths

### Path A — OSS (OpenTelemetry + Grafana Cloud)

```
FastAPI app ──OTLP──► OTel Collector ──► Grafana Cloud (free tier)
                      (hostmetrics)       ├── Prometheus (metrics)
                      (process scraper)   ├── Loki (logs)
                      (OTLP receiver)     └── Tempo (traces)
```

The OTel Collector `hostmetrics` receiver with the `process` scraper enumerates all
running processes on the host — not only the ones explicitly configured for monitoring.

### Path B — New Relic

```
FastAPI app (NR APM agent) ──►
New Relic Infrastructure agent ──► New Relic cloud
(process auto-discovery)            ├── Infrastructure → Hosts
                                    ├── APM → Services
                                    └── Logs
```

## Project Structure

```
NR-sandbox/
├── spec/
│   ├── requirements.md
│   ├── design.md
│   └── implementation.md
├── app/
│   ├── main.py              # FastAPI: /health, /items CRUD, /slow, /error
│   ├── worker.py            # Background process
│   ├── telemetry.py         # OTel SDK setup (traces + metrics + logs)
│   ├── requirements.txt
│   └── static/
│       └── index.html       # Demo UI (vanilla JS, served at /)
├── loadgen/
│   └── locustfile.py        # Realistic HTTP traffic simulation
├── collector/
│   ├── otel-collector.yaml  # Path A: hostmetrics + process scraper + OTLP recv
│   └── prometheus.yml       # Prometheus scrape config
├── infra/
│   ├── provision-ec2.sh     # One-time EC2 provisioning
│   ├── deploy.sh            # Sync repo and run bootstrap
│   ├── setup-ec2.sh         # Idempotent EC2 bootstrap
│   ├── teardown-ec2.sh      # Terminate instance and clean up
│   ├── nginx.conf           # Reverse proxy config
│   └── .env.example         # Credential template
└── tests/
    └── test_api.py          # Integration tests (6 tests, no mocks)
```

## Design Decisions

**t3.micro with cloud-hosted backends (Grafana Cloud + New Relic cloud)**
Running Prometheus and Grafana on the EC2 instance would consume ~400 MB RAM, leaving
insufficient headroom for the application stack. Using cloud-hosted backends keeps the
EC2 footprint under 300 MB and makes the instrumentation architecture realistic —
collectors forward data out, agents are lightweight.

**Redis over RDS**
A managed RDS instance runs outside the EC2 host and adds no processes to observe.
Redis running on the same EC2 instance is a real host process, which is directly
relevant to the investigation. It also keeps the setup within free-tier limits.

**Credentials via `.env`, never committed**
All API keys (Grafana Cloud, New Relic license key) are injected via environment
variables at runtime. The `.env` file is gitignored.

## Demo Narrative

The endpoints and processes map to specific observable signals so the demo tells a story
rather than just emitting data:

- `/items/slow` — produces latency spikes (p95/p99 signal).
- `/items/error` — drives error rate.
- `worker.py` killed mid-run — the background worker is monitored by neither stack's
  default config. Killing it demonstrates the core pain: a process that is "invisible
  until it crashes." This is the central before/after moment of the prototype.
