#!/bin/bash
# Smoke test for AWS ECS deployment (via public ALB)
# Only tests publicly accessible endpoints: /products/* and /cart/*
# Internal services (KV, CCA, warehouse, RabbitMQ) are tested indirectly through cart checkout.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "${1:-}" ]]; then
  BASE="$1"
else
  ALB_DNS=$(cd "$PROJECT_ROOT/terraform" && terraform output -raw alb_dns_name 2>/dev/null || true)
  if [[ -z "$ALB_DNS" ]]; then
    echo "ERROR: Could not read ALB DNS from terraform output. Pass URL as argument."
    exit 1
  fi
  BASE="http://${ALB_DNS}"
fi
PASS=0
FAIL=0

green() { printf "\033[32m%s\033[0m\n" "$1"; }
red()   { printf "\033[31m%s\033[0m\n" "$1"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$1"; }

check() {
  local name="$1" expected_code="$2" actual_code="$3" body="$4"
  if [ "$actual_code" = "$expected_code" ]; then
    green "✓ $name (HTTP $actual_code)"
    PASS=$((PASS + 1))
  else
    red "✗ $name — expected $expected_code, got $actual_code"
    echo "  Response: $body"
    FAIL=$((FAIL + 1))
  fi
}

check_any() {
  local name="$1" expected="$2" actual_code="$3" body="$4"
  if echo "$expected" | tr '|' '\n' | grep -qx "$actual_code"; then
    green "✓ $name (HTTP $actual_code)"
    PASS=$((PASS + 1))
  else
    red "✗ $name — expected $expected, got $actual_code"
    echo "  Response: $body"
    FAIL=$((FAIL + 1))
  fi
}

echo "═══════════════════════════════════════════"
echo " AWS Smoke Test"
echo " ALB: $BASE"
echo "═══════════════════════════════════════════"
echo

# ── 1. Health Endpoints ────────────────────────────────────────────────────
echo "── Health (via ALB) ──"

RESP=$(curl -s -w "\n%{http_code}" "$BASE/products/health-check-dummy" 2>&1 || true)
# Just check ALB itself is reachable
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/health" || true)
echo "ALB default route: HTTP $RESP (expected 404 — means ALB is up)"
echo

# ── 2. Product Service ─────────────────────────────────────────────────────
echo "── Product Service ──"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/product" \
  -H 'Content-Type: application/json' \
  -d '{"sku":"SMOKE-AWS-001","manufacturer":"Acme","category_id":1,"weight":500,"some_other_id":1}')
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "POST /products (create)" 201 "$CODE" "$BODY"

PRODUCT_ID=$(echo "$BODY" | grep -o '"product_id":[0-9]*' | head -1 | cut -d: -f2)
if [ -z "$PRODUCT_ID" ]; then
  red "  Could not parse product_id, using 1"
  PRODUCT_ID=1
fi

RESP=$(curl -s -w "\n%{http_code}" "$BASE/products/$PRODUCT_ID")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "GET /products/$PRODUCT_ID" 200 "$CODE" "$BODY"

RESP=$(curl -s -w "\n%{http_code}" "$BASE/products/999999")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "GET /products/999999 (not found)" 404 "$CODE" "$BODY"

echo

# ── 3. Shopping Cart — Full Flow ───────────────────────────────────────────
# This indirectly tests KV (cart storage), CCA (authorization), Warehouse (reserve),
# and RabbitMQ (ship order) — all through the shopping cart's checkout flow.
echo "── Shopping Cart (full flow) ──"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/shopping-carts/addItem" \
  -H 'Content-Type: application/json' \
  -d "{\"customer_id\":42,\"product_id\":$PRODUCT_ID,\"quantity\":1}")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "POST /shopping-carts/addItem" 200 "$CODE" "$BODY"

CART_ID=$(echo "$BODY" | grep -o '"shopping_cart_id":[0-9]*' | head -1 | cut -d: -f2)
if [ -z "$CART_ID" ]; then
  red "  Could not parse shopping_cart_id, skipping remaining cart tests"
else
  # Checkout (tests CCA + warehouse + RabbitMQ + KV internally)
  RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/shopping-carts/$CART_ID/checkout" \
    -H 'Content-Type: application/json' \
    -d '{"credit_card_number":"1234-5678-9012-3456"}')
  CODE=$(echo "$RESP" | tail -1)
  BODY=$(echo "$RESP" | sed '$d')
  check_any "POST /cart/$CART_ID/checkout" "200|402" "$CODE" "$BODY"

  if [ "$CODE" = "200" ]; then
    green "  → Checkout succeeded! All internal services (KV, CCA, Warehouse, RabbitMQ) working."
  else
    yellow "  → Checkout declined (402) — CCA rejected, but pipeline is working."
  fi
fi

echo

# ── 4. Edge Cases ──────────────────────────────────────────────────────────
echo "── Edge Cases ──"

# Empty cart checkout
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/shopping-cart" \
  -H 'Content-Type: application/json' \
  -d '{"customer_id":99}')
BODY=$(echo "$RESP" | sed '$d')
EMPTY_CART_ID=$(echo "$BODY" | grep -o '"shopping_cart_id":[0-9]*' | head -1 | cut -d: -f2)

if [ -n "$EMPTY_CART_ID" ]; then
  RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/shopping-carts/$EMPTY_CART_ID/checkout" \
    -H 'Content-Type: application/json' \
    -d '{"credit_card_number":"1234-5678-9012-3456"}')
  CODE=$(echo "$RESP" | tail -1)
  BODY=$(echo "$RESP" | sed '$d')
  check_any "Checkout empty cart (should fail)" "400|404|409" "$CODE" "$BODY"
fi

# Non-existent cart
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/shopping-carts/999999999/checkout" \
  -H 'Content-Type: application/json' \
  -d '{"credit_card_number":"1234-5678-9012-3456"}')
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "Checkout non-existent cart" 404 "$CODE" "$BODY"

echo
echo "═══════════════════════════════════════════"
echo " Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
