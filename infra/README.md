# infra

Scripts for provisioning, deploying, and tearing down the EC2 prototype.

## Prerequisites

- AWS CLI v2 configured (`aws configure`) with permissions for EC2
- An SSH key will be created automatically by `provision-ec2.sh`
- `jq` installed locally

## Lifecycle

### 1. Provision (one-time)

Creates a key pair, security group, and t3.micro instance in `ap-south-2`.

```bash
bash infra/provision-ec2.sh
```

Writes instance state to `infra/.ec2-state` (gitignored). SSH is locked to your
current public IP; HTTP (port 80) is open to `0.0.0.0/0` for the load generator.

### 2. Configure credentials

```bash
cp infra/.env.example infra/.env
# edit infra/.env — add NR_LICENSE_KEY and GRAFANA_* values
```

The deploy script skips any agent whose credentials are absent — you can deploy
without credentials first, then re-run after adding them.

**EU New Relic accounts** (license key starts with `eu0`): `setup-ec2.sh` automatically
sets `collector_url: https://infra-api.eu01.nr-data.net` in `newrelic-infra.yml`.

**Grafana Cloud auth**: `GRAFANA_OTLP_AUTH` must be the raw base64 value of
`<instance-id>:<api-token>`. The collector config prepends `Basic ` itself.

### 3. Deploy

Syncs the repo to the instance and runs `setup-ec2.sh`. Safe to re-run — the
script is idempotent and picks up new credentials on each run.

```bash
bash infra/deploy.sh
```

What `setup-ec2.sh` installs:
- Python 3.11, nginx, Redis 6, git
- App Python dependencies + Locust
- OTel Collector contrib (if `GRAFANA_*` set)
- New Relic Infrastructure agent (if `NR_LICENSE_KEY` set)
- systemd services: `nr-sandbox`, `nr-sandbox-worker`, `otelcol`, `newrelic-infra`

### 4. Verify

```bash
curl http://<public-ip>/health          # → {"status":"ok"}
ssh -i infra/nr-sandbox-key.pem ec2-user@<public-ip>
  sudo systemctl status nr-sandbox nr-sandbox-worker otelcol newrelic-infra
```

### 5. Run load generator

```bash
ssh -i infra/nr-sandbox-key.pem ec2-user@<public-ip>
  cd /opt/nr-sandbox
  nohup locust -f loadgen/locustfile.py --host http://localhost \
    --headless -u 30 -r 3 --run-time 30m > /tmp/locust.log 2>&1 &
```

### 6. Teardown

Terminates the instance and deletes the security group. Run after capturing the demo.

```bash
bash infra/teardown-ec2.sh
```

The key pair (`infra/nr-sandbox-key.pem`) is kept locally and in AWS in case you
re-provision. Delete it manually if no longer needed.

---

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `NR_LICENSE_KEY` | For NR | New Relic ingest license key |
| `GRAFANA_OTLP_ENDPOINT` | For Grafana | Full OTLP gateway URL |
| `GRAFANA_OTLP_AUTH` | For Grafana | `base64(<instance-id>:<api-token>)` |
| `REDIS_URL` | No | Defaults to `redis://localhost:6379` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | No | Defaults to `http://localhost:4317` (local collector) |
| `OTEL_SERVICE_NAME` | No | Defaults to `nr-sandbox` |

## Instance start/stop (cost saving)

The instance can be stopped between sessions without reprovisioning:

```bash
# stop
aws ec2 stop-instances --instance-ids <id> --region ap-south-2

# start + get new IP (public IP changes on each start)
aws ec2 start-instances --instance-ids <id> --region ap-south-2
aws ec2 describe-instances --instance-ids <id> --region ap-south-2 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text

# update infra/.ec2-state with new IP, then re-deploy
bash infra/deploy.sh
```
