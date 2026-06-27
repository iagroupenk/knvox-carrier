#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX CUSTOMER PORTAL TEST"
echo "===================================="

echo ""
echo "[1/5] Homepage"
curl -fsS "http://127.0.0.1:${PORTAL_PORT}/" | grep -i "KNVOX Carrier Portal" >/dev/null
echo "OK homepage"

echo ""
echo "[2/5] Health proxy"
curl -fsS "http://127.0.0.1:${PORTAL_PORT}/health" | jq .

echo ""
echo "[3/5] API status via portal proxy"
curl -fsS "http://127.0.0.1:${PORTAL_PORT}/api/v1/status" | jq .

echo ""
echo "[4/5] Clients via portal proxy"
curl -fsS "http://127.0.0.1:${PORTAL_PORT}/api/v1/customers" | jq '.[0:3]'

echo ""
echo "[5/5] Health global"
make health

echo ""
echo "Test Customer Portal terminé."
