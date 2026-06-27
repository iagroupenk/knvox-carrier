#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX MULTI-CUSTOMER CALL CONTROL TEST"
echo "===================================="

echo ""
echo "[1/8] Création client demo CC-DEMO-001"
./scripts/customer-create.sh CC-DEMO-001 "Demo Call Center 001" 25.00 1 2 >/dev/null
echo "OK client demo"

echo ""
echo "[2/8] Création comptes SIP 1000 et 1001"
./scripts/sip-account-create.sh TEST1000 1000 "TEST1000 SIP 1000" >/dev/null
./scripts/sip-account-create.sh CC-DEMO-001 1001 "CC-DEMO-001 SIP 1001" >/dev/null
echo "OK comptes SIP"

echo ""
echo "[3/8] Mapping call-control"
./scripts/call-control-map.sh

echo ""
echo "[4/8] Résolution SIP 1000 -> TEST1000"
./scripts/call-control-resolve.sh 1000 127.0.0.1

sleep 2

CALLID1="multi-1000-$(date +%s)"
echo ""
echo "[5/8] Autorisation appel interne 1000 / TEST1000 vers 9996"
./scripts/kamailio-authorize-call.sh 1000 1000 9996 "${CALLID1}" 127.0.0.1
curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/end-call" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"call_id\":\"${CALLID1}\",\"reason\":\"multi-test-end\"}" | jq .
echo "OK appel 1000"

sleep 2

CALLID2="multi-1001-$(date +%s)"
echo ""
echo "[6/8] Autorisation appel interne 1001 / CC-DEMO-001 vers 9996"
./scripts/kamailio-authorize-call.sh 1001 1001 9996 "${CALLID2}" 127.0.0.1
curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/end-call" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"call_id\":\"${CALLID2}\",\"reason\":\"multi-test-end\"}" | jq .
echo "OK appel 1001"

echo ""
echo "[7/8] Test blocage compte SIP désactivé 2002"
./scripts/sip-account-create.sh TEST1000 2002 "Disabled SIP 2002" >/dev/null
./scripts/sip-account-status.sh 2002 false >/dev/null

if ./scripts/kamailio-authorize-call.sh 2002 2002 9996 "multi-disabled-$(date +%s)" 127.0.0.1; then
  echo "ERREUR: le compte désactivé a été autorisé"
  exit 1
else
  echo "OK compte désactivé bloqué"
fi

echo ""
echo "[8/8] API status + health"
make api-status
make health

echo ""
echo "Test Multi-Customer Call Control terminé."
