#!/bin/bash
set -e

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX SIP SECURITY TEST"
echo "===================================="
echo ""

echo "[1/4] Test Kamailio config..."
docker exec knvox-kamailio kamailio -c -f /etc/kamailio/kamailio.cfg

echo ""
echo "[2/4] Test OPTIONS local..."
MSG="OPTIONS sip:${SIP_DOMAIN} SIP/2.0\r
Via: SIP/2.0/UDP 127.0.0.1:5099;branch=z9hG4bK-knvox-test\r
From: <sip:health@${SIP_DOMAIN}>;tag=knvox\r
To: <sip:${SIP_DOMAIN}>\r
Call-ID: knvox-security-test\r
CSeq: 1 OPTIONS\r
Max-Forwards: 70\r
Content-Length: 0\r
\r
"

printf "$MSG" | nc -u -w2 127.0.0.1 "${KAMAILIO_SIP_PORT}" || true

echo ""
echo "[3/4] Derniers logs sécurité Kamailio..."
./scripts/compose.sh logs --tail=80 kamailio | egrep "KNVOX SIP|KNVOX SECURITY" || true

echo ""
echo "[4/4] Ports SIP/RTP..."
ss -lntup | egrep ':(5060|5070|8021|2223)\b' || true
ss -lunp | egrep ':(5060|5070|2223)\b' || true

echo ""
echo "Test terminé."
