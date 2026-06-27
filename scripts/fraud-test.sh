#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

api_start() {
  CUSTOMER="$1"
  SRC="$2"
  DST="$3"
  CALLID="$4"

  echo ""
  echo "START customer=${CUSTOMER} src=${SRC} dst=${DST} callid=${CALLID}"

  curl -sS \
    -X POST \
    "http://127.0.0.1:${BILLING_API_PORT}/api/v1/start-call" \
    -H "Content-Type: application/json" \
    -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
    -d "{\"customer_code\":\"${CUSTOMER}\",\"src\":\"${SRC}\",\"dst\":\"${DST}\",\"call_id\":\"${CALLID}\"}" | jq .
}

api_end() {
  CALLID="$1"
  REASON="${2:-fraud_test_end}"

  echo ""
  echo "END callid=${CALLID}"

  curl -sS \
    -X POST \
    "http://127.0.0.1:${BILLING_API_PORT}/api/v1/end-call" \
    -H "Content-Type: application/json" \
    -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
    -d "{\"call_id\":\"${CALLID}\",\"reason\":\"${REASON}\"}" | jq .
}

echo "===================================="
echo " KNVOX FRAUD GUARD TEST"
echo "===================================="

TS="$(date +%s)"

echo ""
echo "[0/5] Nettoyage anciens appels test"
./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
DELETE FROM billing.active_calls WHERE call_id LIKE 'fraud-test-%';
SQL

sleep 2

echo ""
echo "[1/5] Appel interne normal 9996 : doit être autorisé"
CALL1="fraud-test-internal-${TS}"
api_start "TEST1000" "1000" "9996" "${CALL1}"
sleep 2
api_end "${CALL1}" "fraud_test_internal_end"

sleep 2

echo ""
echo "[2/5] Préfixe haut tarif 979 : doit être bloqué par max_rate_per_min"
api_start "TEST1000" "1000" "979123456" "fraud-test-highrate-${TS}"

sleep 2

echo ""
echo "[3/5] Test CPS : premier appel OK, deuxième appel immédiat bloqué par cps_limit"
CALLA="fraud-test-cps-a-${TS}"
CALLB="fraud-test-cps-b-${TS}"

api_start "TEST1000" "1000" "9996" "${CALLA}"
api_start "TEST1000" "1000" "9996" "${CALLB}"
sleep 1
api_end "${CALLA}" "fraud_test_cps_end"

echo ""
echo "[4/5] Statut fraude"
./scripts/fraud-status.sh

echo ""
echo "[5/5] Health"
make health

echo ""
echo "Test Fraud Guard terminé."
