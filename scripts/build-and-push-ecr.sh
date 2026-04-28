#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────────
AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_PREFIX="ecommerce"
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "AWS Account: ${AWS_ACCOUNT_ID}"

# service-dir:ecr-repo-suffix
SERVICES=(
  "product-service:product-service"
  "shopping-cart-service:shopping-cart-service"
  "credit-card-authorizer-service:credit-card-authorizer-service"
  "warehouse-service:warehouse-service"
  "kv-database:kv-database"
)

# ── ECR Login ───────────────────────────────────────────────────────────────
echo "==> Logging in to ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${REGISTRY}"

# ── Build & Push Java services ──────────────────────────────────────────────
for ENTRY in "${SERVICES[@]}"; do
  SERVICE_DIR="${ENTRY%%:*}"
  REPO_SUFFIX="${ENTRY##*:}"
  REPO="${ECR_PREFIX}-${REPO_SUFFIX}"
  IMAGE="${REGISTRY}/${REPO}:latest"

  echo ""
  echo "==> Building ${SERVICE_DIR}..."
  docker build \
    --platform linux/amd64 \
    -t "${IMAGE}" \
    -f "${PROJECT_ROOT}/${SERVICE_DIR}/Dockerfile" \
    "${PROJECT_ROOT}"

  echo "==> Pushing ${IMAGE}..."
  docker push "${IMAGE}"
done

# ── RabbitMQ (pull from Docker Hub, tag, push) ──────────────────────────────
RABBITMQ_IMAGE="${REGISTRY}/${ECR_PREFIX}-rabbitmq:latest"
echo ""
echo "==> Building RabbitMQ amd64 image..."
docker build --platform linux/amd64 -t "${RABBITMQ_IMAGE}" - <<'DOCKERFILE'
FROM --platform=linux/amd64 rabbitmq:4-management
DOCKERFILE

echo "==> Pushing RabbitMQ..."
docker push "${RABBITMQ_IMAGE}"

# ── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "=== All images pushed to ECR ==="
echo ""
echo "Wait for ECS services to become healthy, then test:"
echo "  curl http://$(cd "${PROJECT_ROOT}/terraform" && terraform output -raw alb_dns_name)/health"
