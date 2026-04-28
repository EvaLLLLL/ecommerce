#!/bin/bash
# Smoke test for all microservices running in docker-compose
set -euo pipefail

BASE="http://localhost"
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

# Accept multiple expected codes: check_any "name" "200|402" "$CODE" "$BODY"
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
echo " Smoke Test"
echo "═══════════════════════════════════════════"
echo

# ── 1. KV Database ──────────────────────────────────────────────────────────
echo "── KV Database ──"

RESP=$(curl -s -w "\n%{http_code}" -X PUT "$BASE:8084/kv" \
  -H 'Content-Type: application/json' \
  -d '{"key":"smoke-test","value":"hello"}')
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "PUT /kv" 201 "$CODE" "$BODY"

RESP=$(curl -s -w "\n%{http_code}" "$BASE:8084/kv?key=smoke-test")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "GET /kv (exists)" 200 "$CODE" "$BODY"

RESP=$(curl -s -w "\n%{http_code}" "$BASE:8084/kv?key=nonexistent")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "GET /kv (not found)" 404 "$CODE" "$BODY"

# Transaction lifecycle: begin → end
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE:8084/db/begin_transaction")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "POST /db/begin_transaction" 200 "$CODE" "$BODY"
TX_ID=$(echo "$BODY" | grep -o '"transaction_id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$TX_ID" ]; then
  RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE:8084/db/end_transaction" \
    -H 'Content-Type: application/json' \
    -d "{\"transaction_id\":\"$TX_ID\"}")
  CODE=$(echo "$RESP" | tail -1)
  BODY=$(echo "$RESP" | sed '$d')
  check "POST /db/end_transaction" 200 "$CODE" "$BODY"
fi

# Transaction lifecycle: begin → abort
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE:8084/db/begin_transaction")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
TX_ID2=$(echo "$BODY" | grep -o '"transaction_id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$TX_ID2" ]; then
  RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE:8084/db/abort_transaction" \
    -H 'Content-Type: application/json' \
    -d "{\"transaction_id\":\"$TX_ID2\"}")
  CODE=$(echo "$RESP" | tail -1)
  BODY=$(echo "$RESP" | sed '$d')
  check "POST /db/abort_transaction" 200 "$CODE" "$BODY"
fi

echo

# ── 2. Product Service ──────────────────────────────────────────────────────
echo "── Product Service ──"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE:8080/product" \
  -H 'Content-Type: application/json' \
  -d '{"sku":"SMOKE-TEST-001","manufacturer":"Acme","category_id":1,"weight":500,"some_other_id":1}')
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "POST /product (create)" 201 "$CODE" "$BODY"

PRODUCT_ID=$(echo "$BODY" | grep -o '"product_id":[0-9]*' | head -1 | cut -d: -f2)
if [ -z "$PRODUCT_ID" ]; then
  red "  Could not parse product_id, using 1"
  PRODUCT_ID=1
fi

RESP=$(curl -s -w "\n%{http_code}" "$BASE:8080/products/$PRODUCT_ID")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "GET /products/$PRODUCT_ID" 200 "$CODE" "$BODY"

RESP=$(curl -s -w "\n%{http_code}" "$BASE:8080/products/999999")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "GET /products/999999 (not found)" 404 "$CODE" "$BODY"

echo

# ── 3. Warehouse Service ────────────────────────────────────────────────────
echo "── Warehouse Service ──"

RESP=$(curl -s -w "\n%{http_code}" "$BASE:8083/warehouse/inventory/$PRODUCT_ID")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "GET /warehouse/inventory/$PRODUCT_ID" 200 "$CODE" "$BODY"
INITIAL_STOCK=$(echo "$BODY" | grep -o '"available_quantity":[0-9]*' | head -1 | cut -d: -f2)

RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE:8083/warehouse/reserve" \
  -H 'Content-Type: application/json' \
  -d "{\"product_id\":$PRODUCT_ID,\"quantity\":2}")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "POST /warehouse/reserve (qty=2)" 200 "$CODE" "$BODY"

# Verify stock decreased
RESP=$(curl -s -w "\n%{http_code}" "$BASE:8083/warehouse/inventory/$PRODUCT_ID")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
AFTER_RESERVE=$(echo "$BODY" | grep -o '"available_quantity":[0-9]*' | head -1 | cut -d: -f2)
if [ -n "$INITIAL_STOCK" ] && [ -n "$AFTER_RESERVE" ]; then
  EXPECTED=$((INITIAL_STOCK - 2))
  if [ "$AFTER_RESERVE" = "$EXPECTED" ]; then
    green "✓ Inventory decreased from $INITIAL_STOCK to $AFTER_RESERVE after reserve"
    PASS=$((PASS + 1))
  else
    red "✗ Inventory expected $EXPECTED, got $AFTER_RESERVE"
    FAIL=$((FAIL + 1))
  fi
fi

RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE:8083/warehouse/unreserve" \
  -H 'Content-Type: application/json' \
  -d "{\"product_id\":$PRODUCT_ID,\"quantity\":2}")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "POST /warehouse/unreserve (qty=2)" 200 "$CODE" "$BODY"

# Verify stock restored
RESP=$(curl -s -w "\n%{http_code}" "$BASE:8083/warehouse/inventory/$PRODUCT_ID")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
AFTER_UNRESERVE=$(echo "$BODY" | grep -o '"available_quantity":[0-9]*' | head -1 | cut -d: -f2)
if [ -n "$INITIAL_STOCK" ] && [ -n "$AFTER_UNRESERVE" ]; then
  if [ "$AFTER_UNRESERVE" = "$INITIAL_STOCK" ]; then
    green "✓ Inventory restored to $INITIAL_STOCK after unreserve"
    PASS=$((PASS + 1))
  else
    red "✗ Inventory expected $INITIAL_STOCK after unreserve, got $AFTER_UNRESERVE"
    FAIL=$((FAIL + 1))
  fi
fi

# Reserve more than available → expect 409
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE:8083/warehouse/reserve" \
  -H 'Content-Type: application/json' \
  -d "{\"product_id\":$PRODUCT_ID,\"quantity\":999999}")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "POST /warehouse/reserve (insufficient stock)" 409 "$CODE" "$BODY"

echo

# ── 4. Credit Card Authorizer ───────────────────────────────────────────────
echo "── Credit Card Authorizer ──"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE:8081/credit-card-authorizer/authorize" \
  -H 'Content-Type: application/json' \
  -d '{"credit_card_number":"1234-5678-9012-3456"}')
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
# 200 = approved, 402 = declined (10% chance)
check_any "POST /credit-card-authorizer/authorize" "200|402" "$CODE" "$BODY"

echo

# ── 5. Shopping Cart — Happy Path (direct addItem → checkout) ───────────────
echo "── Shopping Cart (happy path) ──"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE:8082/shopping-carts/addItem" \
  -H 'Content-Type: application/json' \
  -d "{\"customer_id\":42,\"product_id\":$PRODUCT_ID,\"quantity\":1}")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "POST /shopping-carts/addItem" 200 "$CODE" "$BODY"

CART_ID=$(echo "$BODY" | grep -o '"shopping_cart_id":[0-9]*' | head -1 | cut -d: -f2)
if [ -z "$CART_ID" ]; then
  red "  Could not parse shopping_cart_id, skipping remaining cart tests"
else
  # Record stock before checkout
  RESP=$(curl -s -w "\n%{http_code}" "$BASE:8083/warehouse/inventory/$PRODUCT_ID")
  STOCK_BEFORE=$(echo "$RESP" | sed '$d' | grep -o '"available_quantity":[0-9]*' | head -1 | cut -d: -f2)

  # Checkout
  RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE:8082/shopping-carts/$CART_ID/checkout" \
    -H 'Content-Type: application/json' \
    -d '{"credit_card_number":"1234-5678-9012-3456"}')
  CODE=$(echo "$RESP" | tail -1)
  BODY=$(echo "$RESP" | sed '$d')
  check_any "POST /shopping-carts/$CART_ID/checkout" "200|402" "$CODE" "$BODY"

  if [ "$CODE" = "200" ]; then
    ORDER_ID=$(echo "$BODY" | grep -o '"order_id":[0-9]*' | head -1 | cut -d: -f2)

    # Verify order saved in KV
    if [ -n "$ORDER_ID" ]; then
      RESP=$(curl -s -w "\n%{http_code}" "$BASE:8085/kv?key=order:$ORDER_ID")
      CODE=$(echo "$RESP" | tail -1)
      BODY=$(echo "$RESP" | sed '$d')
      check "KV has order:$ORDER_ID" 200 "$CODE" "$BODY"
    fi

    # Verify inventory decreased after checkout
    if [ -n "$STOCK_BEFORE" ]; then
      RESP=$(curl -s -w "\n%{http_code}" "$BASE:8083/warehouse/inventory/$PRODUCT_ID")
      STOCK_AFTER=$(echo "$RESP" | sed '$d' | grep -o '"available_quantity":[0-9]*' | head -1 | cut -d: -f2)
      if [ -n "$STOCK_AFTER" ]; then
        EXPECTED=$((STOCK_BEFORE - 1))
        if [ "$STOCK_AFTER" = "$EXPECTED" ]; then
          green "✓ Inventory decreased after checkout ($STOCK_BEFORE → $STOCK_AFTER)"
          PASS=$((PASS + 1))
        else
          red "✗ Inventory expected $EXPECTED after checkout, got $STOCK_AFTER"
          FAIL=$((FAIL + 1))
        fi
      fi
    fi
  else
    yellow "  Checkout declined (402) — skipping post-checkout verifications"
  fi
fi

echo

# ── 6. Shopping Cart — Checkout empty cart → should fail ────────────────────
echo "── Shopping Cart (edge cases) ──"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE:8082/shopping-cart" \
  -H 'Content-Type: application/json' \
  -d '{"customer_id":99}')
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
EMPTY_CART_ID=$(echo "$BODY" | grep -o '"shopping_cart_id":[0-9]*' | head -1 | cut -d: -f2)

if [ -n "$EMPTY_CART_ID" ]; then
  RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE:8082/shopping-carts/$EMPTY_CART_ID/checkout" \
    -H 'Content-Type: application/json' \
    -d '{"credit_card_number":"1234-5678-9012-3456"}')
  CODE=$(echo "$RESP" | tail -1)
  BODY=$(echo "$RESP" | sed '$d')
  check_any "Checkout empty cart (should fail)" "400|404|409" "$CODE" "$BODY"
fi

# Checkout non-existent cart → 404
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE:8082/shopping-carts/999999999/checkout" \
  -H 'Content-Type: application/json' \
  -d '{"credit_card_number":"1234-5678-9012-3456"}')
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
check "Checkout non-existent cart" 404 "$CODE" "$BODY"

echo

# ── 7. Health Endpoints ─────────────────────────────────────────────────────
echo "── Health Endpoints ──"

for svc in "8080:product" "8081:cca" "8082:cart" "8083:warehouse" "8084:kv-products" "8085:kv-carts"; do
  PORT=$(echo "$svc" | cut -d: -f1)
  NAME=$(echo "$svc" | cut -d: -f2)
  RESP=$(curl -s -w "\n%{http_code}" "$BASE:$PORT/health")
  CODE=$(echo "$RESP" | tail -1)
  BODY=$(echo "$RESP" | sed '$d')
  check "GET /health ($NAME)" 200 "$CODE" "$BODY"
done

echo
echo "═══════════════════════════════════════════"
echo " Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
