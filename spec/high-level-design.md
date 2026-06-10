# High-Level Design: Infrastructure & Process Monitoring Prototype

## Problem Statement

Host and process monitoring within infrastructure monitoring suffers from poor adoption
despite being foundational to production reliability. Operators face:

- Hosts with dozens of running processes where only a handful are monitored — the rest
  are invisible until they crash.
- Process telemetry that exists in isolation, disconnected from the services it underpins
  or the hosts it runs on.

## Goal

Experience this pain firsthand across two monitoring stacks, then build a prototype that
meaningfully improves process monitoring adoption.

---

## Deliverables

1. A multi-process tech stack deployed on AWS EC2 (free tier)
2. Real traffic simulation against the deployed stack
3. Two instrumentation paths — OSS (OTel + Prometheus + Grafana) and New Relic
4. A prototype dashboard that surfaces the "dark processes" gap and measures adoption

---

## Architecture

### EC2 Host (t2.micro, Amazon Linux 2023)

```
┌─────────────────────────────────────────────────────┐
│  EC2 t2.micro                                       │
│                                                     │
│  nginx (port 80)          ← reverse proxy           │
│  uvicorn / FastAPI (8000) ← main service            │
│  python worker.py         ← dark process (initially)│
│  redis-server             ← dark process (initially)│
│  sshd, systemd, cron      ← OS processes            │
│                                                     │
│  locust (cron, */5 min)   ← traffic simulation      │
└─────────────────────────────────────────────────────┘
```

"Dark process" = running on the host but emitting no telemetry. This is the default
state for most real-world processes and the core problem to demonstrate.

---

## Instrumentation Paths

### Path A — OSS Stack

```
FastAPI app ──OTLP──► OTel Collector ──► Grafana Cloud (free tier)
                      (hostmetrics)       ├── Prometheus (metrics)
                      (process scraper)   ├── Loki (logs)
                      (OTLP receiver)     └── Tempo (traces)
```

Key: the `process` scraper in OTel hostmetrics receiver enumerates **all** running
processes on the host — not just the ones explicitly configured. This is what makes
the "dark vs monitored" view possible.

### Path B — New Relic

```
FastAPI app (NR APM agent) ──►
New Relic Infrastructure agent ──► New Relic cloud
(auto-discovers all processes)      ├── Infrastructure → Hosts → Processes
                                    ├── APM → Services
                                    └── Logs
```

New Relic infra agent requires zero process configuration — all processes appear
automatically in the Processes tab.

---

## Project Structure

```
NR-sandbox/
├── spec/                        ← spec-driven development lives here
│   └── high-level-design.md
├── app/
│   ├── main.py                  # FastAPI: /health, /items CRUD, /slow, /error
│   ├── worker.py                # Background process — dark initially
│   ├── telemetry.py             # OTel SDK (TracerProvider + MeterProvider + Logger)
│   └── requirements.txt
├── loadgen/
│   └── locustfile.py            # Mixed traffic: 80% GET, 15% POST, 5% error/slow
├── collector/
│   ├── otel-collector.yaml      # Path A: hostmetrics + process scraper + OTLP recv
│   └── prometheus.yml           # Prometheus scrape config
├── infra/
│   ├── setup-ec2.sh             # Bootstrap script for EC2 instance
│   └── nginx.conf               # Reverse proxy config
├── prototype/
│   ├── dashboard.json           # Grafana: Process Inventory + Adoption Score panels
│   └── queries.md               # PromQL vs NRQL side-by-side
└── docker-compose.yml           # Optional local validation stack
```

---

## The Prototype: Process Inventory Dashboard

The Grafana dashboard (Path A) directly addresses the adoption problem with 4 panels:

| Panel | What it shows |
|---|---|
| **Process Inventory Map** | Table of ALL host processes: name, CPU%, mem%, monitored (yes/no) |
| **Adoption Score** | `monitored / total * 100` — target > 80% |
| **Dark Process Alert** | Fires when a known process disappears (crash detection via `absent()`) |
| **Service → Process → Host** | Links FastAPI trace spans back to the uvicorn process on the host |

New Relic equivalent panels documented in `prototype/queries.md` for comparison.

---

## Comparison Axis

| Dimension | OSS (OTel + Grafana Cloud) | New Relic |
|---|---|---|
| Process discovery | Manual regex config in collector | Automatic, zero config |
| Setup time | ~2 hours | ~15 minutes |
| Dark process visibility | After collector config | Immediate, out of box |
| Process ↔ Service correlation | Manual dashboard joins | Built-in UI |
| Cost | Free (Grafana Cloud free tier) | Free (100 GB/month) |
| Adoption friction | High | Low |

This comparison **is** the prototype finding — it quantifies where the adoption gap comes from.

---

## Implementation Phases

| Phase | Scope |
|---|---|
| 1 | Build app/, collector/, loadgen/, infra/ |
| 2 | Deploy to EC2; both agents running; locust traffic live |
| 3 | Build Grafana Process Inventory dashboard; tune adoption score metric |
| 4 | Comparison writeup in prototype/queries.md; NRQL vs PromQL |

---

## Key Constraints

- **No RDS** — use in-memory storage for app data. Redis runs locally on EC2 as a
  deliberate dark process; lighting it up is the adoption improvement demo.
- **No local Docker validation phase** — go straight to EC2 for real host data.
- **Grafana Cloud + New Relic cloud** as backends — EC2 only runs agents/collectors,
  keeping RAM well within t2.micro limits (~250 MB total).
- **`.env` for all credentials** — never committed to git.
