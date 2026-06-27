#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

send_invite() {
  DST="$1"
  CALLID="knvox-call-control-${DST}-$(date +%s)"

  echo ""
  echo "SIP INVITE test vers ${DST}"

  MSG="INVITE sip:${DST}@${SIP_DOMAIN} SIP/2.0\r
Via: SIP/2.0/UDP 127.0.0.1:5099;branch=z9hG4bK-${CALLID}\r
From: <sip:1000@${SIP_DOMAIN}>;tag=knvox\r
To: <sip:${DST}@${SIP_DOMAIN}>\r
Call-ID: ${CALLID}\r
CSeq: 1 INVITE\r
Max-Forwards: 70\r
Contact: <sip:1000@127.0.0.1:5099>\r
Content-Length: 0\r
\r
"

  printf "$MSG" | nc -u -w2 127.0.0.1 "${KAMAILIO_SIP_PORT}" || true
}

echo "===================================="
echo " KNVOX CALL CONTROL TEST"
echo "===================================="

echo ""
echo "[1/4] Test API direct"
./scripts/api-auth-test.sh

echo ""
echo "[2/4] Test SIP externe France, doit être bloqué par Billing API"
send_invite "33612345678"

echo ""
echo "[3/4] Test SIP préfixe risqué, doit être bloqué"
send_invite "882123456"

echo ""
echo "[4/4] Logs autorisation Kamailio"
tail -n 30 logs/kamailio-auth/auth.log 2>/dev/null || true

echo ""
echo "Logs Kamailio récents:"
./scripts/compose.sh logs --tail=80 kamailio | egrep "KNVOX AUTH|Billing Authorization|KNVOX SECURITY" || true

echo ""
echo "Test Call Control terminé."
