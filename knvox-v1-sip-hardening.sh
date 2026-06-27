#!/bin/bash
set -euo pipefail

echo "================================================"
echo " KNVOX Carrier Platform - V1.2.1 SIP Hardening"
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

echo "[1/5] Backup configuration Kamailio actuelle..."
cp storage/telephony/kamailio/kamailio.cfg "storage/telephony/kamailio/kamailio.cfg.bak.$(date +%Y%m%d-%H%M%S)"

echo "[2/5] Arrêt Kamailio..."
./scripts/compose.sh stop kamailio || true

echo "[3/5] Configuration Kamailio V1.2.1 renforcée..."

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
loadmodule "pike.so"

modparam("rr", "enable_full_lr", 1)
modparam("rtpengine", "rtpengine_sock", "udp:127.0.0.1:${RTPENGINE_NG_PORT}")

modparam("pike", "sampling_time_unit", 2)
modparam("pike", "reqs_density_per_unit", 12)
modparam("pike", "remove_latency", 120)

request_route {
    force_rport();

    xlog("L_INFO", "KNVOX SIP \$rm \$ru from \$si:\$sp ua=\$ua\\n");

    if (!mf_process_maxfwd_header("10")) {
        xlog("L_WARN", "KNVOX SECURITY too many hops from \$si\\n");
        sl_send_reply("483", "Too Many Hops");
        exit;
    }

    if (!pike_check_req()) {
        xlog("L_WARN", "KNVOX SECURITY flood blocked from \$si ua=\$ua\\n");
        sl_send_reply("403", "Rate Limit");
        exit;
    }

    if (\$ua =~ "friendly-scanner|sipvicious|VaxSIPUserAgent|pplsip|sipcli|sipsak|iWar|sip-scan|SIPVicious|scanner|bot|Vicidial") {
        xlog("L_WARN", "KNVOX SECURITY scanner UA blocked from \$si ua=\$ua\\n");
        sl_send_reply("403", "Forbidden");
        exit;
    }

    if (!is_method("REGISTER|INVITE|ACK|BYE|CANCEL|OPTIONS|INFO|UPDATE")) {
        xlog("L_WARN", "KNVOX SECURITY method blocked \$rm from \$si\\n");
        sl_send_reply("405", "Method Not Allowed");
        exit;
    }

    if (is_method("OPTIONS")) {
        sl_send_reply("200", "KNVOX Kamailio OK");
        exit;
    }

    if (is_method("REGISTER")) {
        if (!(\$tU =~ "^(100[0-9]|101[0-9])$" || \$fU =~ "^(100[0-9]|101[0-9])$")) {
            xlog("L_WARN", "KNVOX SECURITY register blocked user fU=\$fU tU=\$tU from \$si ua=\$ua\\n");
            sl_send_reply("403", "Register Blocked");
            exit;
        }
    }

    if (is_method("INVITE")) {
        if (!(\$rU =~ "^(9996|100[0-9]|101[0-9])$")) {
            xlog("L_WARN", "KNVOX SECURITY destination blocked rU=\$rU from \$si ua=\$ua\\n");
            sl_send_reply("403", "Destination Blocked");
            exit;
        }
    }

    if (is_method("BYE|CANCEL")) {
        rtpengine_delete();
    }

    if (is_method("INVITE|UPDATE") && has_body("application/sdp")) {
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

cp storage/telephony/kamailio/kamailio.cfg configs/kamailio/kamailio.v1.2.1.cfg

echo "[4/5] Test configuration..."
docker run --rm \
  --network host \
  -v "$(pwd)/storage/telephony/kamailio/kamailio.cfg:/etc/kamailio/kamailio.cfg:ro" \
  knvox/kamailio:1.1.0 \
  kamailio -c -f /etc/kamailio/kamailio.cfg

echo "[5/5] Redémarrage Kamailio..."
./scripts/compose.sh up -d kamailio

sleep 10

./scripts/compose.sh ps kamailio
./scripts/compose.sh logs --tail=80 kamailio

echo ""
echo "V1.2.1 SIP Hardening installé."
