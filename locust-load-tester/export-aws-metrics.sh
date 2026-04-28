#!/bin/bash
# Export all AWS metrics for load test analysis.
# Run this AFTER all locust tests complete.
# Usage:
#   ./export-aws-metrics.sh
#   ./export-aws-metrics.sh metrics-after
#   OUTDIR=metrics-before ./export-aws-metrics.sh
set -uo pipefail

cd "$(dirname "$0")"
OUTDIT="${1:-${METRICS_OUTDIR:-metrics-r5}}"
mkdir -p "$OUTDIT"

CLUSTER="ecommerce-cluster"
REGION="us-west-2"
SERVICES=("ecommerce-product" "ecommerce-shopping-cart" "ecommerce-cca" "ecommerce-warehouse")

# Time range: last 2 hours (adjust if tests ran longer)
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
START_TIME=$(date -u -v-2H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
  || date -u -d "2 hours ago" +"%Y-%m-%dT%H:%M:%SZ")

echo "Exporting metrics from $START_TIME to $END_TIME"

# ── 1. Per-service CPU & Memory metrics (1-minute granularity) ───────────────
for svc in "${SERVICES[@]}"; do
  echo "  → $svc CPU"
  aws cloudwatch get-metric-statistics \
    --namespace AWS/ECS \
    --metric-name CPUUtilization \
    --dimensions Name=ClusterName,Value=$CLUSTER Name=ServiceName,Value=$svc \
    --start-time "$START_TIME" --end-time "$END_TIME" \
    --period 60 --statistics Average Maximum \
    --region $REGION --no-cli-pager \
    --output json > "$OUTDIT/metrics-${svc}-cpu.json"

  echo "  → $svc Memory"
  aws cloudwatch get-metric-statistics \
    --namespace AWS/ECS \
    --metric-name MemoryUtilization \
    --dimensions Name=ClusterName,Value=$CLUSTER Name=ServiceName,Value=$svc \
    --start-time "$START_TIME" --end-time "$END_TIME" \
    --period 60 --statistics Average Maximum \
    --region $REGION --no-cli-pager \
    --output json > "$OUTDIT/metrics-${svc}-memory.json"

  echo "  → $svc Task Count"
  aws cloudwatch get-metric-statistics \
    --namespace ECS/ContainerInsights \
    --metric-name RunningTaskCount \
    --dimensions Name=ClusterName,Value=$CLUSTER Name=ServiceName,Value=$svc \
    --start-time "$START_TIME" --end-time "$END_TIME" \
    --period 60 --statistics Average \
    --region $REGION --no-cli-pager \
    --output json > "$OUTDIT/metrics-${svc}-tasks.json"
done

# ── 2. Scaling activities ────────────────────────────────────────────────────
echo "  → Scaling activities"
aws application-autoscaling describe-scaling-activities \
  --service-namespace ecs \
  --region $REGION --no-cli-pager \
  --output json > $OUTDIT/scaling-activities.json

# ── 3. CloudWatch alarm history ──────────────────────────────────────────────
echo "  → Alarm history"
aws cloudwatch describe-alarms \
  --region $REGION --no-cli-pager \
  --output json > $OUTDIT/alarm-history.json

# ── 4. Current service status ────────────────────────────────────────────────
echo "  → Current ECS service status"
aws ecs describe-services \
  --cluster $CLUSTER \
  --services "${SERVICES[@]}" \
  --region $REGION --no-cli-pager \
  --query 'services[].{name:serviceName,desired:desiredCount,running:runningCount}' \
  --output json > $OUTDIT/ecs-service-status.json

echo ""
echo "Done. Files in $OUTDIT/:"
ls -la $OUTDIT/*.json
