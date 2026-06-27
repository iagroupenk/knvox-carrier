#!/bin/bash
set -e

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX TELEPHONY STATUS"
echo "===================================="
echo ""

./scripts/compose.sh ps freeswitch rtpengine kamailio || true

echo ""
echo "Ports SIP/RTP écoutés :"
ss -lntup | egrep ':(5060|5070|5080|8021|2223)\b' || true

echo ""
echo "FreeSWITCH status :"
docker exec knvox-freeswitch fs_cli -H 127.0.0.1 -P 8021 -p "$FS_EVENT_SOCKET_PASSWORD" -x status || true

echo ""
echo "Kamailio version :"
docker exec knvox-kamailio kamailio -v | head -n 3 || true

echo ""
echo "RTPEngine process :"
docker exec knvox-rtpengine pgrep -a rtpengine || true

echo ""
echo "SIP public : ${SIP_DOMAIN}:${KAMAILIO_SIP_PORT}"
echo "Echo test  : 9996"
