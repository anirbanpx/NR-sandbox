#!/usr/bin/env bash
# EC2 bootstrap — Amazon Linux 2023, t2.micro
#
# NR_LICENSE_KEY and GRAFANA_* are optional at first deploy.
# Re-run the script after adding them to .env to wire up observability.
#
# Run as ec2-user with sudo access:
#   chmod +x setup-ec2.sh && sudo bash setup-ec2.sh

set -euo pipefail

APP_DIR=/opt/nr-sandbox
OTEL_VERSION=0.103.0

# Load .env if present
ENV_FILE="${APP_DIR}/.env"
if [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE"; set +a
fi

NR_LICENSE_KEY=${NR_LICENSE_KEY:-}
GRAFANA_OTLP_ENDPOINT=${GRAFANA_OTLP_ENDPOINT:-}
GRAFANA_OTLP_AUTH=${GRAFANA_OTLP_AUTH:-}

echo "==> system update"
dnf update -y -q

echo "==> installing base packages"
dnf install -y -q python3.11 python3.11-pip python3-pip nginx redis6 git rsync

echo "==> configuring redis"
systemctl enable --now redis6

echo "==> installing app"
mkdir -p "$APP_DIR"
if [ -d /home/ec2-user/NR-sandbox ]; then
    rsync -a /home/ec2-user/NR-sandbox/. "$APP_DIR/"
fi

pip3.11 install -r "$APP_DIR/app/requirements.txt" -q
pip3.11 install locust -q

echo "==> configuring nginx"
cp "$APP_DIR/infra/nginx.conf" /etc/nginx/nginx.conf
systemctl enable --now nginx

# ── OTel Collector (skipped if Grafana credentials not yet set) ───────────────
if [ -n "$GRAFANA_OTLP_ENDPOINT" ] && [ -n "$GRAFANA_OTLP_AUTH" ]; then
    echo "==> installing OTel Collector contrib"
    curl -fsSL -o /tmp/otelcol.tar.gz \
        "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/otelcol-contrib_${OTEL_VERSION}_linux_amd64.tar.gz"
    tar -xzf /tmp/otelcol.tar.gz -C /usr/local/bin otelcol-contrib
    chmod +x /usr/local/bin/otelcol-contrib

    mkdir -p /etc/otelcol
    cp "$APP_DIR/collector/otel-collector.yaml" /etc/otelcol/config.yaml
    grep -E 'GRAFANA_' "$ENV_FILE" | tee /etc/otelcol/otelcol.env > /dev/null

    cat > /etc/systemd/system/otelcol.service <<'EOF'
[Unit]
Description=OpenTelemetry Collector
After=network.target

[Service]
EnvironmentFile=/etc/otelcol/otelcol.env
ExecStart=/usr/local/bin/otelcol-contrib --config /etc/otelcol/config.yaml
Restart=on-failure
RestartSec=5s
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now otelcol
    echo "    OTel Collector running"
else
    echo "    GRAFANA_* not set — skipping OTel Collector (add credentials and re-run to enable)"
fi

# ── New Relic Infrastructure agent (skipped if license key not yet set) ───────
if [ -n "$NR_LICENSE_KEY" ]; then
    echo "==> installing New Relic Infrastructure agent"
    echo "license_key: ${NR_LICENSE_KEY}" > /etc/newrelic-infra.yml
    curl -fsSL -o /etc/yum.repos.d/newrelic-infra.repo \
        https://download.newrelic.com/infrastructure_agent/linux/yum/el/9/x86_64/newrelic-infra.repo
    dnf install -y -q newrelic-infra
    systemctl enable --now newrelic-infra
    echo "    New Relic Infrastructure agent running"
else
    echo "    NR_LICENSE_KEY not set — skipping New Relic agent (add key and re-run to enable)"
fi

# ── Systemd services ──────────────────────────────────────────────────────────

# Use newrelic.admin wrapper only if NR key is present
if [ -n "$NR_LICENSE_KEY" ]; then
    APP_EXEC="/usr/bin/python3.11 -m newrelic.admin run-program uvicorn app.main:app --host 127.0.0.1 --port 8000"
else
    APP_EXEC="/usr/bin/python3.11 -m uvicorn app.main:app --host 127.0.0.1 --port 8000"
fi

echo "==> starting FastAPI app"
cat > /etc/systemd/system/nr-sandbox.service <<EOF
[Unit]
Description=NR Sandbox FastAPI App
After=redis6.service

[Service]
WorkingDirectory=${APP_DIR}
EnvironmentFile=${ENV_FILE}
Environment=OTEL_SDK_DISABLED=true
ExecStart=${APP_EXEC}
Restart=on-failure
RestartSec=5s
User=ec2-user

[Install]
WantedBy=multi-user.target
EOF

echo "==> starting background worker"
cat > /etc/systemd/system/nr-sandbox-worker.service <<EOF
[Unit]
Description=NR Sandbox Background Worker
After=redis6.service

[Service]
WorkingDirectory=${APP_DIR}
EnvironmentFile=${ENV_FILE}
Environment=OTEL_SDK_DISABLED=true
ExecStart=/usr/bin/python3.11 -m app.worker
Restart=on-failure
RestartSec=5s
User=ec2-user

[Install]
WantedBy=multi-user.target
EOF

# Remove OTEL_SDK_DISABLED once OTel Collector is running
if [ -n "$GRAFANA_OTLP_ENDPOINT" ]; then
    sed -i '/OTEL_SDK_DISABLED/d' /etc/systemd/system/nr-sandbox.service
    sed -i '/OTEL_SDK_DISABLED/d' /etc/systemd/system/nr-sandbox-worker.service
fi

systemctl daemon-reload
systemctl enable --now nr-sandbox
systemctl enable --now nr-sandbox-worker

echo ""
echo "==> setup complete"
echo "    curl http://localhost/health"
echo "    systemctl status nr-sandbox nr-sandbox-worker"
echo ""
echo "TEARDOWN (after capturing the demo):"
echo "    bash infra/teardown-ec2.sh"
