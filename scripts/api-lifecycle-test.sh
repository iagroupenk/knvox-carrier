#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

CALLID="api-lifecycle-9996-$(date +%s)"

echo "===================================="
echo " KNVOX API LIFECYCLE TEST"
echo "===================================="

echo ""
echo "[1/5] Start internal call 9996"
curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/start-call" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"customer_code\":\"TEST1000\",\"src\":\"1000\",\"dst\":\"9996\",\"call_id\":\"${CALLID}\"}" | jq .

echo ""
echo "[2/5] Active calls"
curl -fsS \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/active-calls" | jq .

sleep 2

echo ""
echo "[3/5] End internal call"
curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/end-call" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"call_id\":\"${CALLID}\",\"reason\":\"test_end\"}" | jq .

echo ""
echo "[4/5] Start external France, should be denied"
curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/start-call" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"customer_code\":\"TEST1000\",\"src\":\"1000\",\"dst\":\"33612345678\",\"call_id\":\"api-lifecycle-fr-$(date +%s)\"}" | jq .

echo ""
echo "[5/5] Billing status"
curl -fsS \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/status" | jq .

echo ""
echo "Test lifecycle terminé."
