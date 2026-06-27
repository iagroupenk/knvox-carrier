#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX SIP REGISTRATION TOOLKIT TEST"
echo "===================================="

echo ""
echo "[1/7] Création client demo"
./scripts/customer-create.sh CC-DEMO-001 "Demo Call Center 001" 25.00 1 2 >/dev/null
echo "OK client demo"

echo ""
echo "[2/7] Création compte SIP 1002"
./scripts/sip-account-create.sh CC-DEMO-001 1002 "CC-DEMO-001 SIP 1002" >/tmp/knvox_sip_1002.json
cat /tmp/knvox_sip_1002.json | jq .
echo "OK compte SIP 1002"

echo ""
echo "[3/7] Sync FreeSWITCH"
./scripts/freeswitch-sync-sip-accounts.sh

echo ""
echo "[4/7] Fiche softphone"
./scripts/sip-provisioning-card.sh 1002

echo ""
echo "[5/7] Résolution call-control"
./scripts/call-control-resolve.sh 1002 127.0.0.1

echo ""
echo "[6/7] Test autorisation interne 1002 -> 9996"

set -a
source .env
set +a

CALLID="sip-reg-toolkit-1002-$(date +%s)"

./scripts/kamailio-authorize-call.sh 1002 1002 9996 "${CALLID}" 127.0.0.1

curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/end-call" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"call_id\":\"${CALLID}\",\"reason\":\"sip-registration-toolkit-test-end\"}" | jq .

echo ""
echo "[7/7] Status SIP + health"
./scripts/sip-registration-status.sh
make health

echo ""
echo "Test SIP Registration Toolkit terminé."
