#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX API STATUS"
echo "===================================="
echo ""

./scripts/compose.sh ps billing-api || true

echo ""
echo "Health local:"
curl -fsS "http://127.0.0.1:${BILLING_API_PORT}/health" | jq . || true

echo ""
echo "API status:"
curl -fsS \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/status" | jq . || true

echo ""
echo "Logs:"
./scripts/compose.sh logs --tail=80 billing-api || true
