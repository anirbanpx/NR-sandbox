# Design: Infrastructure & Process Monitoring

## Host Architecture (EC2 t2.micro, Amazon Linux 2023)

```
┌─────────────────────────────────────────────────────┐
│  EC2 t2.micro                                       │
│                                                     │
│  nginx (port 80)          ← reverse proxy           │
│  uvicorn / FastAPI (8000) ← main service            │
│  python worker.py         ← background processor   │
│  redis-server             ← cache                  │
│  sshd, systemd, cron      ← OS processes            │
│                                                     │
│  locust (cron, */5 min)   ← traffic simulation      │
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
│   └── requirements.txt
├── loadgen/
│   └── locustfile.py        # Realistic HTTP traffic simulation
├── collector/
│   ├── otel-collector.yaml  # Path A: hostmetrics + process scraper + OTLP recv
│   └── prometheus.yml       # Prometheus scrape config
├── infra/
│   ├── setup-ec2.sh         # EC2 bootstrap script
│   └── nginx.conf           # Reverse proxy config
└── prototype/
    └── queries.md           # PromQL and NRQL reference queries
```

## Design Decisions

**t2.micro with cloud-hosted backends (Grafana Cloud + New Relic cloud)**
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
