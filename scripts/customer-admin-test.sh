#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX CUSTOMER ADMIN TEST"
echo "===================================="

CUSTOMER="CC-DEMO-001"

echo ""
echo "[1/8] Création client demo"
./scripts/customer-create.sh "${CUSTOMER}" "Demo Call Center 001" 25.00 1 2

echo ""
echo "[2/8] Liste clients"
./scripts/customer-list.sh

echo ""
echo "[3/8] Détail client"
./scripts/customer-show.sh "${CUSTOMER}"

echo ""
echo "[4/8] Crédit client +15 EUR"
./scripts/customer-credit.sh "${CUSTOMER}" 15.00 "demo-credit-$(date +%s)"

echo ""
echo "[5/8] Modification limites"
./scripts/customer-limits.sh "${CUSTOMER}" 2 5 50.0 0.7

echo ""
echo "[6/8] Test route sandbox France sur client demo"
set -a
source .env
set +a

curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/provider-route-simulate" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"customer_code\":\"${CUSTOMER}\",\"src\":\"1000\",\"dst\":\"33612345678\",\"call_id\":\"customer-admin-route-$(date +%s)\"}" | jq .

echo ""
echo "[7/8] CDR client demo"
./scripts/customer-cdrs.sh "${CUSTOMER}"

echo ""
echo "[8/8] Health"
make health

echo ""
echo "Test Customer Admin terminé."
