#!/bin/bash
# Restart all KV database containers on EC2 to clear in-memory data.
# Usage: ./scripts/reset-kv-data.sh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$PROJECT_ROOT/terraform"

KEY_PATH="${KV_KEY_PATH:-$HOME/.ssh/vockey.pem}"

# Fetch all KV EC2 public IPs from terraform output (JSON map)
IPS_JSON=$(cd "$TF_DIR" && terraform output -json kv_ec2_public_ips)

ALL_IPS=$(echo "$IPS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for ips in data.values():
    for ip in ips:
        print(ip)
")

if [[ -z "$ALL_IPS" ]]; then
  echo "ERROR: No KV EC2 IPs found. Is terraform applied?"
  exit 1
fi

echo "Restarting KV containers on all EC2 nodes..."
for ip in $ALL_IPS; do
  echo "  → $ip"
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$KEY_PATH" ec2-user@"$ip" \
    "sudo docker restart kv-node" 2>/dev/null &
done

wait
echo "KV containers restarted."

# Also restart ECS Product Service to reset its in-memory ID counter
ECS_CLUSTER=$(cd "$TF_DIR" && terraform output -raw ecs_cluster_name 2>/dev/null || echo "ecommerce")
REGION="${AWS_REGION:-us-west-2}"

echo "Restarting ECS services to reset in-memory state..."
for svc in product-service shopping-cart; do
  echo "  → $svc"
  aws ecs update-service --cluster "$ECS_CLUSTER" --service "$svc" \
    --force-new-deployment --region "$REGION" --no-cli-pager > /dev/null 2>&1 &
done

wait
echo "Done. Wait ~60s for ECS tasks to restart before loading products."
