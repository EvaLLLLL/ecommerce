#!/bin/bash
# Load products into the Product Service using the data-loader JAR.
# Usage:
#   ./scripts/load-products.sh                        # local (default 1000 products)
#   ./scripts/load-products.sh --aws                  # AWS ALB
#   ./scripts/load-products.sh --aws --count 1000     # AWS ALB, 1000 products
#   PRODUCT_SERVICE_URL=http://... ./scripts/load-products.sh --count 500
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAR="$PROJECT_ROOT/data-loader/target/data-loader-1.0-SNAPSHOT.jar"

# ── Defaults ─────────────────────────────────────────────────────────────────
COUNT="${PRODUCT_COUNT:-1000}"
URL="${PRODUCT_SERVICE_URL:-ecommerce-alb-1556515951.us-west-2.elb.amazonaws.com}"

# ── Parse args ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --aws)
      ALB_DNS=$(cd "$PROJECT_ROOT/terraform" && terraform output -raw alb_dns_name 2>/dev/null || true)
      if [[ -z "$ALB_DNS" ]]; then
        echo "ERROR: Could not read ALB DNS from terraform output."
        echo "       Make sure you've run 'terraform apply' in terraform/"
        exit 1
      fi
      URL="http://${ALB_DNS}"
      shift ;;
    --count)
      COUNT="$2"; shift 2 ;;
    *)
      echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Build JAR if missing ────────────────────────────────────────────────────
if [[ ! -f "$JAR" ]]; then
  echo "Building data-loader JAR..."
  mvn -f "$PROJECT_ROOT/data-loader/pom.xml" package -DskipTests -q
fi

# ── Run ──────────────────────────────────────────────────────────────────────
echo "Loading $COUNT products into $URL"
PRODUCT_SERVICE_URL="$URL" PRODUCT_COUNT="$COUNT" java -jar "$JAR"
