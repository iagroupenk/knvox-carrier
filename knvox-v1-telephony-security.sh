#!/bin/bash
set -euo pipefail

echo "================================================"
echo " KNVOX Carrier Platform - V1.2.0 SIP Security"
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

mkdir -p docs configs/kamailio scripts

echo "[1/6] Arrêt Kamailio..."
./scripts/compose.sh stop kamailio || true

echo "[2/6] Nouvelle configuration Kamailio sécurisée..."

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

# Anti-flood SIP
modparam("pike", "sampling_time_unit", 2)
modparam("pike", "reqs_density_per_unit", 20)
modparam("pike", "remove_latency", 60)

request_route {
    force_rport();

    xlog("L_INFO", "KNVOX SIP \$rm \$ru from \$si:\$sp ua=\$ua\\n");

    # Protection boucle SIP
    if (!mf_process_maxfwd_header("10")) {
        xlog("L_WARN", "KNVOX SECURITY too many hops from \$si\\n");
        sl_send_reply("483", "Too Many Hops");
        exit;
    }

    # Anti-flood IP
    if (!pike_check_req()) {
        xlog("L_WARN", "KNVOX SECURITY flood detected from \$si ua=\$ua\\n");
        sl_send_reply("403", "Rate Limit");
        exit;
    }

    # Blocage scanners SIP connus
    if (\$ua =~ "friendly-scanner|sipvicious|VaxSIPUserAgent|pplsip|sipcli|sipsak|iWar|sip-scan|SIPVicious|scanner|bot|Bria Push Service") {
        xlog("L_WARN", "KNVOX SECURITY scanner blocked from \$si ua=\$ua\\n");
        sl_send_reply("403", "Forbidden");
        exit;
    }

    # Méthodes autorisées uniquement
    if (!is_method("REGISTER|INVITE|ACK|BYE|CANCEL|OPTIONS|INFO|UPDATE")) {
        xlog("L_WARN", "KNVOX SECURITY method blocked \$rm from \$si\\n");
        sl_send_reply("405", "Method Not Allowed");
        exit;
    }

    # Réponse monitoring
    if (is_method("OPTIONS")) {
        sl_send_reply("200", "KNVOX Kamailio OK");
        exit;
    }

    # Anti open-relay : seules les destinations internes de test sont autorisées
    if (is_method("INVITE")) {
        if (!(\$rU =~ "^(9996|10[0-1][0-9])$")) {
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

cp storage/telephony/kamailio/kamailio.cfg configs/kamailio/kamailio.security.template.cfg

echo "[3/6] Test configuration Kamailio..."

docker run --rm \
  --network host \
  -v "$(pwd)/storage/telephony/kamailio/kamailio.cfg:/etc/kamailio/kamailio.cfg:ro" \
  knvox/kamailio:1.1.0 \
  kamailio -c -f /etc/kamailio/kamailio.cfg

echo "[4/6] Scripts sécurité téléphonie..."

cat > scripts/sip-security-test.sh <<'TEST'
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
TEST

cat > scripts/sip-security-logs.sh <<'SECLOGS'
#!/bin/bash
set -e

cd "$(dirname "$0")/.."

./scripts/compose.sh logs --tail=300 -f kamailio | egrep "KNVOX SIP|KNVOX SECURITY|flood|scanner|blocked|403|405" || true
SECLOGS

chmod +x scripts/*.sh

echo "[5/6] Documentation..."

cat > docs/SIP_SECURITY.md <<'DOC'
# KNVOX V1.2.0 - SIP Security Layer

## Objectif

Cette version empêche le serveur SIP de fonctionner comme relais ouvert.

## Destinations autorisées en V1.2.0

Uniquement :

- 1000 à 1019
- 9996 echo test

Tout autre numéro est bloqué par Kamailio avec :

403 Destination Blocked

## Protections actives

- limitation des méthodes SIP
- anti-scan User-Agent
- rate limit IP avec Pike
- blocage des destinations externes
- logs sécurité Kamailio
- FreeSWITCH non exposé directement

## Important

Ne pas connecter de trunk fournisseur avant la mise en place de :

- comptes clients
- ACL IP clients
- billing temps réel
- limite d'appels simultanés
- limite CPS
- blocage pays sensibles
- alertes solde
DOC

echo "[6/6] Mise à jour Makefile..."

cat > Makefile <<'MAKEFILE'
.RECIPEPREFIX := >
.PHONY: start stop restart status health logs backup pull update firewall telephony telephony-status fs sip-users firewall-telephony sip-security-test sip-security-logs

start:
>./scripts/compose.sh up -d

stop:
>./scripts/compose.sh down

restart:
>./scripts/compose.sh restart

status:
>./scripts/status.sh

health:
>./scripts/healthcheck.sh

logs:
>./scripts/logs.sh

backup:
>./scripts/backup.sh

pull:
>./scripts/compose.sh pull

update:
>./scripts/compose.sh pull
>./scripts/compose.sh up -d

firewall:
>./scripts/firewall.sh

telephony:
>./scripts/compose.sh up -d --build freeswitch rtpengine kamailio

telephony-status:
>./scripts/telephony-status.sh

fs:
>./scripts/fs_cli.sh

sip-users:
>./scripts/show-sip-users.sh

firewall-telephony:
>./scripts/firewall-telephony.sh

sip-security-test:
>./scripts/sip-security-test.sh

sip-security-logs:
>./scripts/sip-security-logs.sh
MAKEFILE

echo ""
echo "Redémarrage Kamailio..."
./scripts/compose.sh up -d kamailio

sleep 10

./scripts/compose.sh ps kamailio

echo ""
echo "V1.2.0 SIP Security installée."
