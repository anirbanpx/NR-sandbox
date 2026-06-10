#!/usr/bin/env bash
# Copy repo to EC2 and run the bootstrap script.
# Requires infra/.ec2-state (written by provision-ec2.sh) and infra/.env.
#
# Usage: bash infra/deploy.sh

set -euo pipefail

STATE_FILE="infra/.ec2-state"
ENV_FILE="infra/.env"

if [ ! -f "$STATE_FILE" ]; then
    echo "error: $STATE_FILE not found — run provision-ec2.sh first" >&2
    exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "==> no infra/.env found — creating minimal one (NR + Grafana keys can be added later)"
    cat > "$ENV_FILE" <<'ENVEOF'
REDIS_URL=redis://localhost:6379
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
OTEL_SERVICE_NAME=nr-sandbox
OTEL_SDK_DISABLED=true
ENVEOF
fi

source "$STATE_FILE"

SSH="ssh -o StrictHostKeyChecking=no -i ${KEY_FILE} ec2-user@${PUBLIC_IP}"
SCP="scp -o StrictHostKeyChecking=no -i ${KEY_FILE}"

echo "==> syncing repo to ec2-user@${PUBLIC_IP}:/home/ec2-user/NR-sandbox"
$SSH "mkdir -p /home/ec2-user/NR-sandbox"
tar --exclude='.git' --exclude='infra/.ec2-state' --exclude='infra/*.pem' \
    -czf - . | $SSH "tar -xzf - -C /home/ec2-user/NR-sandbox/"

echo "==> copying .env"
$SCP "$ENV_FILE" "ec2-user@${PUBLIC_IP}:/home/ec2-user/NR-sandbox/.env"

echo "==> running setup-ec2.sh"
$SSH "sudo bash /home/ec2-user/NR-sandbox/infra/setup-ec2.sh"

echo ""
echo "==> deploy complete"
echo "    curl http://${PUBLIC_IP}/health"
echo "    ssh -i ${KEY_FILE} ec2-user@${PUBLIC_IP}"
