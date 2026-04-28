#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== Tearing down existing containers ==="
docker compose --profile init down 2>/dev/null || true
docker compose down 2>/dev/null || true
docker network prune -f

echo "=== Starting all services ==="
docker compose up -d --build --force-recreate

echo "=== Loading product data ==="
docker compose --profile init up data-loader

echo "=== Smoke Test ==="
cd ../scripts
smoke-test-local.sh

#echo "=== Starting Locust ==="
#echo "Open http://localhost:8089 in your browser"
#cd ../locust-load-tester
#source .venv/bin/activate 2>/dev/null || (python3 -m venv .venv && source .venv/bin/activate && pip install -e .)
#locust -f locustfile.py -H http://localhost:8080 --processes 4
