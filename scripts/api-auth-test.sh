#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

auth_call() {
  CUSTOMER="$1"
  SRC="$2"
  DST="$3"
  CALLID="$4"

  echo ""
  echo "Test authorize: customer=${CUSTOMER} src=${SRC} dst=${DST}"

  curl -fsS \
    -X POST \
    "http://127.0.0.1:${BILLING_API_PORT}/api/v1/authorize-call" \
    -H "Content-Type: application/json" \
    -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
    -d "{\"customer_code\":\"${CUSTOMER}\",\"src\":\"${SRC}\",\"dst\":\"${DST}\",\"call_id\":\"${CALLID}\"}" | jq .
}

echo "===================================="
echo " KNVOX CALL AUTH API TEST"
echo "===================================="

auth_call "TEST1000" "1000" "9996" "api-test-9996-$(date +%s)"
auth_call "TEST1000" "1000" "33612345678" "api-test-france-$(date +%s)"
auth_call "TEST1000" "1000" "882123456" "api-test-blocked-$(date +%s)"

echo ""
echo "Test API terminé."
