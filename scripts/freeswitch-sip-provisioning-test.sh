#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX FREESWITCH SIP PROVISIONING TEST"
echo "===================================="

echo ""
echo "[1/6] Création client demo"
./scripts/customer-create.sh CC-DEMO-001 "Demo Call Center 001" 25.00 1 2 >/dev/null
echo "OK client demo"

echo ""
echo "[2/6] Création compte SIP 1001 lié à CC-DEMO-001"
./scripts/sip-account-create.sh CC-DEMO-001 1001 "CC-DEMO-001 SIP 1001" >/tmp/knvox_sip_1001.json
cat /tmp/knvox_sip_1001.json | jq .
echo "OK compte SIP 1001"

echo ""
echo "[3/6] Sync FreeSWITCH"
./scripts/freeswitch-sync-sip-accounts.sh

echo ""
echo "[4/6] Résolution call-control 1001"
./scripts/call-control-resolve.sh 1001 127.0.0.1

echo ""
echo "[5/6] Test autorisation appel interne 1001 -> 9996"
set -a
source .env
set +a

CALLID="fs-provision-1001-$(date +%s)"

./scripts/kamailio-authorize-call.sh 1001 1001 9996 "${CALLID}" 127.0.0.1

curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/end-call" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"call_id\":\"${CALLID}\",\"reason\":\"fs-provision-test-end\"}" | jq .

echo ""
echo "[6/6] Status provisioning + health"
./scripts/freeswitch-sip-provisioning-status.sh
make health

echo ""
echo "Test FreeSWITCH SIP Provisioning terminé."
echo ""
echo "Pour configurer un softphone test:"
echo "Serveur SIP : 51.222.115.82"
echo "Port        : 5060 UDP"
echo "Username    : 1001"
echo "Password    : voir sortie JSON ci-dessus ou dernier CSV dans exports/sip/"
echo "Test appel  : 9996"
