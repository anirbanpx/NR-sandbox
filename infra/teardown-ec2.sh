#!/usr/bin/env bash
# Terminate the EC2 instance and clean up resources.
# Run after capturing the demo to stay within free-tier limits.
#
# Usage: bash infra/teardown-ec2.sh

set -euo pipefail

STATE_FILE="infra/.ec2-state"

if [ ! -f "$STATE_FILE" ]; then
    echo "error: $STATE_FILE not found — nothing to tear down" >&2
    exit 1
fi

source "$STATE_FILE"

echo "==> terminating instance $INSTANCE_ID in $REGION"
read -rp "    confirm? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "aborted"
    exit 0
fi

aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
    --query 'TerminatingInstances[0].CurrentState.Name' --output text

echo "==> waiting for termination..."
aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$REGION"
echo "    instance terminated"

echo "==> deleting security group $SG_ID"
aws ec2 delete-security-group --group-id "$SG_ID" --region "$REGION"
echo "    security group deleted"

echo "==> removing state file"
rm -f "$STATE_FILE"

echo ""
echo "==> teardown complete — no running EC2 resources remain"
echo "    key pair '${KEY_FILE}' and key in AWS are kept in case you re-provision."
echo "    To delete the key pair: aws ec2 delete-key-pair --key-name nr-sandbox-key --region $REGION"
