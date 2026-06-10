#!/usr/bin/env bash
# Provision EC2 t2.micro for the NR-sandbox prototype.
#
# Prerequisites:
#   aws cli v2 installed and configured (aws configure, or env vars / IAM role)
#   jq installed (brew install jq / sudo dnf install jq / choco install jq)
#
# Usage:
#   chmod +x infra/provision-ec2.sh
#   bash infra/provision-ec2.sh              # us-east-1 (default)
#   AWS_REGION=eu-west-1 bash infra/provision-ec2.sh
#
# Outputs: infra/.ec2-state  (instance-id, public IP, key path — used by teardown)

set -euo pipefail

REGION=${AWS_REGION:-$(aws configure get region 2>/dev/null || echo "ap-south-2")}
PROJECT=nr-sandbox
KEY_NAME="${PROJECT}-key"
KEY_FILE="infra/${KEY_NAME}.pem"
SG_NAME="${PROJECT}-sg"
STATE_FILE="infra/.ec2-state"

echo "==> region: $REGION"

# ── 1. Key pair ───────────────────────────────────────────────────────────────
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" \
       --query 'KeyPairs[0].KeyName' --output text 2>/dev/null | grep -q "$KEY_NAME"; then
    echo "==> key pair '$KEY_NAME' already exists — skipping creation"
else
    echo "==> creating key pair '$KEY_NAME'"
    # remove existing file (may be read-only from a prior run)
    [ -f "$KEY_FILE" ] && chmod 600 "$KEY_FILE" && rm -f "$KEY_FILE"
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --region "$REGION" \
        --query 'KeyMaterial' \
        --output text > "$KEY_FILE"
    chmod 400 "$KEY_FILE"
    echo "    saved to $KEY_FILE"
fi

# ── 2. Security group ─────────────────────────────────────────────────────────
MY_IP=$(curl -sf https://checkip.amazonaws.com)
echo "==> your public IP: $MY_IP"

SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" \
    --region "$REGION" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || true)

if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
    echo "==> creating security group '$SG_NAME'"
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SG_NAME" \
        --description "NR-sandbox prototype" \
        --region "$REGION" \
        --query 'GroupId' \
        --output text)

    # SSH from your IP only
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp --port 22 \
        --cidr "${MY_IP}/32" \
        --region "$REGION"

    # HTTP from anywhere (Locust needs to hit port 80)
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp --port 80 \
        --cidr "0.0.0.0/0" \
        --region "$REGION"

    echo "    security group: $SG_ID"
else
    echo "==> security group '$SG_NAME' already exists: $SG_ID"
fi

# ── 3. Latest Amazon Linux 2023 AMI ──────────────────────────────────────────
echo "==> resolving latest Amazon Linux 2023 AMI"
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023*-kernel-*-x86_64" \
              "Name=state,Values=available" \
    --region "$REGION" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)
echo "    AMI: $AMI_ID"

# ── 4. Launch instance ────────────────────────────────────────────────────────
echo "==> launching t2.micro"
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type t3.micro \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --region "$REGION" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$PROJECT},{Key=Project,Value=$PROJECT}]" \
    --query 'Instances[0].InstanceId' \
    --output text)
echo "    instance: $INSTANCE_ID"

# ── 5. Wait for running state ─────────────────────────────────────────────────
echo "==> waiting for instance to reach running state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)
echo "    public IP: $PUBLIC_IP"

# ── 6. Save state for teardown ────────────────────────────────────────────────
cat > "$STATE_FILE" <<EOF
INSTANCE_ID=$INSTANCE_ID
PUBLIC_IP=$PUBLIC_IP
REGION=$REGION
KEY_FILE=$KEY_FILE
SG_ID=$SG_ID
EOF
echo "==> state saved to $STATE_FILE"

# ── 7. Wait for SSH to be ready ───────────────────────────────────────────────
echo "==> waiting for SSH to come up (this takes ~30s)..."
for i in $(seq 1 18); do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
           -i "$KEY_FILE" "ec2-user@${PUBLIC_IP}" "echo ok" 2>/dev/null; then
        echo "    SSH ready"
        break
    fi
    echo "    attempt $i/18 — retrying in 10s"
    sleep 10
done

# ── 8. Copy repo and deploy ───────────────────────────────────────────────────
echo ""
echo "==> instance is ready. next steps:"
echo ""
echo "  1. create infra/.env with your credentials (see infra/.env.example)"
echo ""
echo "  2. deploy:"
echo "     bash infra/deploy.sh"
echo ""
echo "  3. verify:"
echo "     curl http://${PUBLIC_IP}/health"
echo ""
echo "  SSH: ssh -i ${KEY_FILE} ec2-user@${PUBLIC_IP}"
