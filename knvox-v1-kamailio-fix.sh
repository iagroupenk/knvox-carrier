#!/bin/bash
set -euo pipefail

echo "================================================"
echo " KNVOX Carrier Platform - V1.1.1 Kamailio Fix"
echo "================================================"

cd /opt/knvox-carrier

set -a
source .env
set +a

KAMAILIO_SIP_PORT="${KAMAILIO_SIP_PORT:-5060}"
FS_INTERNAL_SIP_PORT="${FS_INTERNAL_SIP_PORT:-5070}"
RTPENGINE_NG_PORT="${RTPENGINE_NG_PORT:-2223}"
SIP_DOMAIN="${SIP_DOMAIN:-knvox.enaes.net}"
PUBLIC_IP="${PUBLIC_IP:-51.222.115.82}"
LOCAL_IP="${LOCAL_IP:-51.222.115.82}"

echo "[1/8] Logs Kamailio avant correction..."
./scripts/compose.sh logs --tail=80 kamailio || true

echo "[2/8] Arrêt Kamailio..."
./scripts/compose.sh stop kamailio || true

echo "[3/8] Sécurisation FreeSWITCH : désactivation profils non utilisés..."

FS_CONF="storage/telephony/freeswitch/conf"

for f in \
  "${FS_CONF}/sip_profiles/external.xml" \
  "${FS_CONF}/sip_profiles/external-ipv6.xml" \
  "${FS_CONF}/sip_profiles/internal-ipv6.xml"
do
  if [ -f "$f" ]; then
    mv "$f" "${f}.disabled"
  fi
done

set_xml_param() {
  FILE="$1"
  NAME="$2"
  VALUE="$3"

  if [ ! -f "$FILE" ]; then
    return
  fi

  if grep -q "<param name=\"${NAME}\"" "$FILE"; then
    sed -i -E "s#(<param name=\"${NAME}\" value=\")[^\"]*(\"/>)#\1${VALUE}\2#g" "$FILE"
  else
    sed -i "/<\/settings>/i \ \ \ \ <param name=\"${NAME}\" value=\"${VALUE}\"/>" "$FILE"
  fi
}

INTERNAL_PROFILE="${FS_CONF}/sip_profiles/internal.xml"

set_xml_param "$INTERNAL_PROFILE" "sip-ip" "127.0.0.1"
set_xml_param "$INTERNAL_PROFILE" "rtp-ip" "$LOCAL_IP"
set_xml_param "$INTERNAL_PROFILE" "ext-sip-ip" "$PUBLIC_IP"
set_xml_param "$INTERNAL_PROFILE" "ext-rtp-ip" "$PUBLIC_IP"
set_xml_param "$INTERNAL_PROFILE" "sip-port" "$FS_INTERNAL_SIP_PORT"

echo "[4/8] Réécriture configuration Kamailio propre..."

cat > storage/telephony/kamailio/kamailio.cfg <<KAMCFG
#!KAMAILIO

debug=2
log_stderror=yes
fork=no
children=1
auto_aliases=no

alias="${SIP_DOMAIN}"

listen=udp:0.0.0.0:${KAMAILIO_SIP_PORT} advertise ${PUBLIC_IP}:${KAMAILIO_SIP_PORT}

mpath="/usr/lib/x86_64-linux-gnu/kamailio/modules/"

loadmodule "sl.so"
loadmodule "tm.so"
loadmodule "rr.so"
loadmodule "pv.so"
loadmodule "xlog.so"
loadmodule "maxfwd.so"
loadmodule "textops.so"
loadmodule "siputils.so"
loadmodule "rtpengine.so"

modparam("rr", "enable_full_lr", 1)
modparam("rtpengine", "rtpengine_sock", "udp:127.0.0.1:${RTPENGINE_NG_PORT}")

request_route {
    force_rport();

    xlog("L_INFO", "KNVOX SIP \$rm \$ru from \$si:\$sp\\n");

    if (!mf_process_maxfwd_header("10")) {
        sl_send_reply("483", "Too Many Hops");
        exit;
    }

    if (is_method("OPTIONS")) {
        sl_send_reply("200", "KNVOX Kamailio OK");
        exit;
    }

    if (is_method("BYE|CANCEL")) {
        rtpengine_delete();
    }

    if (is_method("INVITE") && has_body("application/sdp")) {
        rtpengine_offer("replace-origin replace-session-connection ICE=remove");
    }

    if (is_method("INVITE|SUBSCRIBE|UPDATE")) {
        record_route();
    }

    t_on_reply("MANAGE_REPLY");

    \$du = "sip:127.0.0.1:${FS_INTERNAL_SIP_PORT}";

    if (!t_relay()) {
        sl_reply_error();
    }

    exit;
}

onreply_route[MANAGE_REPLY] {
    if (has_body("application/sdp")) {
        rtpengine_answer("replace-origin replace-session-connection ICE=remove");
    }
}
KAMCFG

echo "[5/8] Reconstruction image Kamailio..."
./scripts/compose.sh build kamailio

echo "[6/8] Test configuration Kamailio..."
docker run --rm \
  --network host \
  -v "$(pwd)/storage/telephony/kamailio/kamailio.cfg:/etc/kamailio/kamailio.cfg:ro" \
  knvox/kamailio:1.1.0 \
  kamailio -c -f /etc/kamailio/kamailio.cfg

echo "[7/8] Redémarrage FreeSWITCH + RTPEngine..."
./scripts/compose.sh up -d freeswitch rtpengine

sleep 15

echo "Ports utilisés avant Kamailio :"
ss -lntup | egrep ':(5060|5070|8021|2223)\b' || true
ss -lunp | egrep ':(5060|5070|2223)\b' || true

echo "[8/8] Démarrage Kamailio..."
./scripts/compose.sh up -d kamailio

sleep 10

echo ""
echo "Etat Kamailio :"
./scripts/compose.sh ps kamailio

echo ""
echo "Logs Kamailio :"
./scripts/compose.sh logs --tail=120 kamailio || true

echo ""
echo "Correction V1.1.1 terminée."
