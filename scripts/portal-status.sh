#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX CUSTOMER PORTAL STATUS"
echo "===================================="
echo ""

./scripts/compose.sh ps customer-portal || true

echo ""
echo "Portal health local:"
curl -fsS "http://127.0.0.1:${PORTAL_PORT}/health" | jq . || true

echo ""
echo "Portal API status through proxy:"
curl -fsS "http://127.0.0.1:${PORTAL_PORT}/api/v1/status" | jq . || true

echo ""
echo "Portal URL local:"
echo "http://127.0.0.1:${PORTAL_PORT}"

echo ""
echo "Logs:"
./scripts/compose.sh logs --tail=80 customer-portal || true
