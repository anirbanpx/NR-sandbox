# loadgen

Locust-based load generator. Simulates realistic API traffic to produce CPU, memory,
latency, and error rate signals visible in both observability stacks.

## Traffic mix

| Weight | Endpoint | Purpose |
|---|---|---|
| 80% | GET `/items` | Baseline read throughput |
| 15% | POST `/items` | Write traffic with unique payloads |
| 4% | GET `/items/slow` | Latency spike signal (p95/p99) |
| 1% | GET `/items/error` | Error rate signal |

## Running

### Headless (on EC2, against localhost)

```bash
locust -f loadgen/locustfile.py --host http://localhost \
  --headless -u 30 -r 3 --run-time 30m
```

`-u 30` — 30 concurrent users  
`-r 3` — ramp up 3 users/second  
`--run-time 30m` — stop after 30 minutes

### With web UI (local, against EC2)

```bash
pip install locust
locust -f loadgen/locustfile.py --host http://<ec2-ip>
# open http://localhost:8089
```

### Background on EC2 (nohup)

```bash
nohup locust -f loadgen/locustfile.py --host http://localhost \
  --headless -u 30 -r 3 --run-time 30m > /tmp/locust.log 2>&1 &

# follow output
tail -f /tmp/locust.log

# stop early
pkill -f locust
```

## Reading the output

Locust prints a stats table every few seconds:

```
Type    Name              Reqs  Fails  Avg  Min   Max  RPS
GET     /items [GET]      2400  0      12   2     45   19.1
POST    /items [POST]      450  0      18   5     60    3.6
GET     /items/slow        120  0    2266  1533  2992   0.9
GET     /items/error        30  0       2   1      4    0.0
```

The `/items/slow` p95 latency (1.5–3s range) and `/items/error` 500s are intentional —
they produce the latency and error signals used in the observability demo.
