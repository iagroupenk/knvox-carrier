#!/bin/bash
set -euo pipefail

echo "================================================"
echo " KNVOX Carrier Platform - V1.1.0 Telephony"
echo "================================================"

cd /opt/knvox-carrier

if [ ! -f .env ]; then
  echo "ERROR: .env introuvable. Lance d'abord la V1.0.1."
  exit 1
fi

mkdir -p docker/kamailio docker/rtpengine
mkdir -p compose/telephony
mkdir -p storage/telephony/freeswitch/{conf,sounds,logs,db,recordings}
mkdir -p storage/telephony/kamailio
mkdir -p storage/telephony/rtpengine
mkdir -p docs scripts

env_get() {
  grep -E "^$1=" .env | tail -n1 | cut -d= -f2- || true
}

env_set() {
  KEY="$1"
  VALUE="$2"
  if grep -q "^${KEY}=" .env; then
    sed -i "s#^${KEY}=.*#${KEY}=${VALUE}#" .env
  else
    echo "${KEY}=${VALUE}" >> .env
  fi
}

env_set_if_missing() {
  KEY="$1"
  VALUE="$2"
  CURRENT="$(env_get "$KEY")"
  if [ -z "$CURRENT" ]; then
    env_set "$KEY" "$VALUE"
  fi
}

detect_public_ip() {
  curl -4 -fsS https://api.ipify.org 2>/dev/null || curl -4 -fsS https://ifconfig.me 2>/dev/null || true
}

detect_local_ip() {
  ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}'
}

PUBLIC_IP_DETECTED="$(detect_public_ip)"
LOCAL_IP_DETECTED="$(detect_local_ip)"

if [ -z "$PUBLIC_IP_DETECTED" ]; then
  echo "ERROR: impossible de détecter l'IP publique."
  echo "Ajoute PUBLIC_IP=TON_IP dans .env puis relance."
  exit 1
fi

if [ -z "$LOCAL_IP_DETECTED" ]; then
  echo "ERROR: impossible de détecter l'IP locale."
  exit 1
fi

DOMAIN_VALUE="$(env_get DOMAIN)"
if [ -z "$DOMAIN_VALUE" ]; then
  DOMAIN_VALUE="knvox.enaes.net"
  env_set DOMAIN "$DOMAIN_VALUE"
fi

env_set_if_missing PUBLIC_IP "$PUBLIC_IP_DETECTED"
env_set_if_missing LOCAL_IP "$LOCAL_IP_DETECTED"
env_set_if_missing SIP_DOMAIN "$DOMAIN_VALUE"

env_set_if_missing KAMAILIO_SIP_PORT "5060"
env_set_if_missing FS_INTERNAL_SIP_PORT "5070"
env_set_if_missing FS_RTP_START "10000"
env_set_if_missing FS_RTP_END "20000"

env_set_if_missing RTPENGINE_NG_PORT "2223"
env_set_if_missing RTPENGINE_RTP_START "30000"
env_set_if_missing RTPENGINE_RTP_END "40000"

env_set_if_missing FS_DEFAULT_PASSWORD "$(openssl rand -hex 12)"
env_set_if_missing FS_EVENT_SOCKET_PASSWORD "$(openssl rand -hex 16)"

chmod 600 .env

set -a
source .env
set +a

echo "[1/10] Génération Dockerfile Kamailio..."

cat > docker/kamailio/Dockerfile <<'KAMDOCKER'
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    ca-certificates \
    kamailio \
    kamailio-extra-modules \
    kamailio-utils-modules \
    kamailio-tls-modules \
    sngrep \
    tcpdump \
    iproute2 \
    dnsutils \
    netcat-openbsd \
    procps \
    && rm -rf /var/lib/apt/lists/*

CMD ["kamailio", "-DD", "-E", "-f", "/etc/kamailio/kamailio.cfg"]
KAMDOCKER

echo "[2/10] Génération Dockerfile RTPEngine..."

cat > docker/rtpengine/Dockerfile <<'RTPDOCKER'
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    ca-certificates \
    rtpengine-daemon \
    rtpengine-utils \
    iproute2 \
    netcat-openbsd \
    tcpdump \
    procps \
    && rm -rf /var/lib/apt/lists/*

CMD ["rtpengine", "--help"]
RTPDOCKER

echo "[3/10] Initialisation configuration FreeSWITCH..."

if [ ! -f storage/telephony/freeswitch/conf/freeswitch.xml ]; then
  docker pull safarov/freeswitch:1.10.12
  docker rm -f knvox-freeswitch-init >/dev/null 2>&1 || true
  docker run -d --name knvox-freeswitch-init safarov/freeswitch:1.10.12 >/dev/null
  sleep 5
  docker cp knvox-freeswitch-init:/etc/freeswitch/. storage/telephony/freeswitch/conf/
  docker rm -f knvox-freeswitch-init >/dev/null 2>&1 || true
fi

VARS_FILE="storage/telephony/freeswitch/conf/vars.xml"

upsert_fs_var() {
  NAME="$1"
  VALUE="$2"
  if grep -q "data=\"${NAME}=" "$VARS_FILE"; then
    sed -i -E "s#data=\"${NAME}=[^\"]*\"#data=\"${NAME}=${VALUE}\"#g" "$VARS_FILE"
  else
    sed -i "/<\/include>/i \ \ <X-PRE-PROCESS cmd=\"set\" data=\"${NAME}=${VALUE}\"/>" "$VARS_FILE"
  fi
}

upsert_fs_var "default_password" "$FS_DEFAULT_PASSWORD"
upsert_fs_var "domain" "$SIP_DOMAIN"
upsert_fs_var "internal_sip_port" "$FS_INTERNAL_SIP_PORT"
upsert_fs_var "external_sip_port" "5090"
upsert_fs_var "external_sip_ip" "$PUBLIC_IP"
upsert_fs_var "external_rtp_ip" "$PUBLIC_IP"

SWITCH_FILE="storage/telephony/freeswitch/conf/autoload_configs/switch.conf.xml"

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

set_xml_param "$SWITCH_FILE" "rtp-start-port" "$FS_RTP_START"
set_xml_param "$SWITCH_FILE" "rtp-end-port" "$FS_RTP_END"

EVENT_FILE="storage/telephony/freeswitch/conf/autoload_configs/event_socket.conf.xml"
set_xml_param "$EVENT_FILE" "listen-ip" "127.0.0.1"
set_xml_param "$EVENT_FILE" "listen-port" "8021"
set_xml_param "$EVENT_FILE" "password" "$FS_EVENT_SOCKET_PASSWORD"

INTERNAL_PROFILE="storage/telephony/freeswitch/conf/sip_profiles/internal.xml"

set_xml_param "$INTERNAL_PROFILE" "sip-ip" "127.0.0.1"
set_xml_param "$INTERNAL_PROFILE" "rtp-ip" "$LOCAL_IP"
set_xml_param "$INTERNAL_PROFILE" "ext-sip-ip" "$PUBLIC_IP"
set_xml_param "$INTERNAL_PROFILE" "ext-rtp-ip" "$PUBLIC_IP"
set_xml_param "$INTERNAL_PROFILE" "sip-port" "$FS_INTERNAL_SIP_PORT"

if [ -f storage/telephony/freeswitch/conf/sip_profiles/external.xml ]; then
  mv storage/telephony/freeswitch/conf/sip_profiles/external.xml storage/telephony/freeswitch/conf/sip_profiles/external.xml.disabled
fi

if [ -f storage/telephony/freeswitch/conf/sip_profiles/external-ipv6.xml ]; then
  mv storage/telephony/freeswitch/conf/sip_profiles/external-ipv6.xml storage/telephony/freeswitch/conf/sip_profiles/external-ipv6.xml.disabled
fi

echo "[4/10] Configuration Kamailio..."

cat > storage/telephony/kamailio/kamailio.cfg <<'KAMCFG'
#!KAMAILIO

debug=2
log_stderror=yes
fork=yes
children=4
udp_children=4
auto_aliases=no

alias="__SIP_DOMAIN__"

listen=udp:0.0.0.0:__KAMAILIO_SIP_PORT__ advertise __PUBLIC_IP__:__KAMAILIO_SIP_PORT__
listen=tcp:0.0.0.0:__KAMAILIO_SIP_PORT__ advertise __PUBLIC_IP__:__KAMAILIO_SIP_PORT__

mpath="/usr/lib/x86_64-linux-gnu/kamailio/modules/"

loadmodule "sl.so"
loadmodule "tm.so"
loadmodule "rr.so"
loadmodule "pv.so"
loadmodule "xlog.so"
loadmodule "maxfwd.so"
loadmodule "textops.so"
loadmodule "siputils.so"
loadmodule "nathelper.so"
loadmodule "rtpengine.so"

modparam("rr", "enable_full_lr", 1)
modparam("rtpengine", "rtpengine_sock", "udp:127.0.0.1:__RTPENGINE_NG_PORT__")

request_route {
    force_rport();

    xlog("L_INFO", "KNVOX SIP $rm $ru from $si:$sp\n");

    if (!mf_process_maxfwd_header("10")) {
        sl_send_reply("483", "Too Many Hops");
        exit;
    }

    if (is_method("OPTIONS") && ($rU == $null || $rU == "")) {
        sl_send_reply("200", "KNVOX Kamailio OK");
        exit;
    }

    if (nat_uac_test("19")) {
        if (is_method("REGISTER")) {
            fix_nated_register();
        } else {
            fix_nated_contact();
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

    route(RELAY_TO_FREESWITCH);
}

route[RELAY_TO_FREESWITCH] {
    $du = "sip:127.0.0.1:__FS_INTERNAL_SIP_PORT__";
    t_on_reply("MANAGE_REPLY");

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

sed -i "s#__PUBLIC_IP__#${PUBLIC_IP}#g" storage/telephony/kamailio/kamailio.cfg
sed -i "s#__SIP_DOMAIN__#${SIP_DOMAIN}#g" storage/telephony/kamailio/kamailio.cfg
sed -i "s#__KAMAILIO_SIP_PORT__#${KAMAILIO_SIP_PORT}#g" storage/telephony/kamailio/kamailio.cfg
sed -i "s#__FS_INTERNAL_SIP_PORT__#${FS_INTERNAL_SIP_PORT}#g" storage/telephony/kamailio/kamailio.cfg
sed -i "s#__RTPENGINE_NG_PORT__#${RTPENGINE_NG_PORT}#g" storage/telephony/kamailio/kamailio.cfg

echo "[5/10] Docker Compose Téléphonie..."

cat > compose/telephony/docker-compose.yml <<'TELCOMPOSE'
services:

  freeswitch:
    image: safarov/freeswitch:1.10.12
    container_name: knvox-freeswitch
    restart: unless-stopped
    network_mode: host
    environment:
      SOUND_RATES: "8000:16000"
      SOUND_TYPES: "music:en-us-callie"
      DUMPCAP: "false"
    volumes:
      - ./storage/telephony/freeswitch/conf:/etc/freeswitch
      - ./storage/telephony/freeswitch/sounds:/usr/share/freeswitch/sounds
      - ./storage/telephony/freeswitch/logs:/var/log/freeswitch
      - ./storage/telephony/freeswitch/db:/var/lib/freeswitch/db
      - ./storage/telephony/freeswitch/recordings:/var/lib/freeswitch/recordings
    healthcheck:
      test: ["CMD-SHELL", "fs_cli -H 127.0.0.1 -P 8021 -p ${FS_EVENT_SOCKET_PASSWORD} -x status >/dev/null 2>&1 || exit 1"]
      interval: 20s
      timeout: 5s
      retries: 10

  rtpengine:
    build:
      context: ./docker/rtpengine
    image: knvox/rtpengine:1.1.0
    container_name: knvox-rtpengine
    restart: unless-stopped
    network_mode: host
    command:
      - rtpengine
      - --foreground
      - --log-stderr
      - --listen-ng=127.0.0.1:${RTPENGINE_NG_PORT}
      - --interface=${LOCAL_IP}!${PUBLIC_IP}
      - --port-min=${RTPENGINE_RTP_START}
      - --port-max=${RTPENGINE_RTP_END}
      - --tos=184
    healthcheck:
      test: ["CMD-SHELL", "pgrep rtpengine >/dev/null 2>&1 || exit 1"]
      interval: 20s
      timeout: 5s
      retries: 5

  kamailio:
    build:
      context: ./docker/kamailio
    image: knvox/kamailio:1.1.0
    container_name: knvox-kamailio
    restart: unless-stopped
    network_mode: host
    depends_on:
      - freeswitch
      - rtpengine
    volumes:
      - ./storage/telephony/kamailio/kamailio.cfg:/etc/kamailio/kamailio.cfg:ro
    healthcheck:
      test: ["CMD-SHELL", "kamailio -c -f /etc/kamailio/kamailio.cfg >/dev/null 2>&1 || exit 1"]
      interval: 20s
      timeout: 5s
      retries: 5
TELCOMPOSE

echo "[6/10] Helper Docker Compose..."

cat > scripts/compose.sh <<'COMPOSESH'
#!/bin/bash
set -e

cd "$(dirname "$0")/.."

FILES=(-f docker-compose.yml)

if [ -f compose/telephony/docker-compose.yml ]; then
  FILES+=(-f compose/telephony/docker-compose.yml)
fi

exec docker compose "${FILES[@]}" "$@"
COMPOSESH

chmod +x scripts/compose.sh

echo "[7/10] Scripts téléphonie..."

cat > scripts/fs_cli.sh <<'FSCLI'
#!/bin/bash
set -e

cd "$(dirname "$0")/.."

set -a
source .env
set +a

docker exec -it knvox-freeswitch fs_cli -H 127.0.0.1 -P 8021 -p "$FS_EVENT_SOCKET_PASSWORD" "$@"
FSCLI

cat > scripts/show-sip-users.sh <<'SIPUSERS'
#!/bin/bash
set -e

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX SIP TEST USERS"
echo "===================================="
echo ""
echo "SIP Server : ${SIP_DOMAIN}"
echo "SIP Port   : ${KAMAILIO_SIP_PORT}"
echo "Transport  : UDP ou TCP"
echo ""
echo "Utilisateurs de test FreeSWITCH :"
echo "1000 à 1019"
echo ""
echo "Mot de passe SIP :"
echo "${FS_DEFAULT_PASSWORD}"
echo ""
echo "Test echo : appeler 9996"
echo ""
echo "Important : ne connecte pas encore de fournisseur minutes/PSTN."
SIPUSERS

cat > scripts/telephony-status.sh <<'TELSTATUS'
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
TELSTATUS

cat > scripts/firewall-telephony.sh <<'FWTELE'
#!/bin/bash
set -e

cd "$(dirname "$0")/.."

set -a
source .env
set +a

apt-get update
apt-get install -y ufw

ufw allow ${KAMAILIO_SIP_PORT}/udp
ufw allow ${KAMAILIO_SIP_PORT}/tcp
ufw allow ${RTPENGINE_RTP_START}:${RTPENGINE_RTP_END}/udp

ufw status numbered
FWTELE

chmod +x scripts/*.sh

echo "[8/10] Mise à jour scripts existants..."

cat > scripts/start.sh <<'START'
#!/bin/bash
set -e
cd "$(dirname "$0")/.."
./scripts/compose.sh up -d
START

cat > scripts/stop.sh <<'STOP'
#!/bin/bash
set -e
cd "$(dirname "$0")/.."
./scripts/compose.sh down
STOP

cat > scripts/restart.sh <<'RESTART'
#!/bin/bash
set -e
cd "$(dirname "$0")/.."
./scripts/compose.sh restart
RESTART

cat > scripts/logs.sh <<'LOGS'
#!/bin/bash
set -e

cd "$(dirname "$0")/.."

SERVICE="${1:-}"

if [ -z "$SERVICE" ]; then
  ./scripts/compose.sh logs --tail=150 -f
else
  ./scripts/compose.sh logs --tail=150 -f "$SERVICE"
fi
LOGS

cat > scripts/status.sh <<'STATUS'
#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX PLATFORM STATUS"
echo "===================================="
echo ""

echo "Docker:"
systemctl is-active docker || true
echo ""

echo "Containers:"
./scripts/compose.sh ps
echo ""

echo "URLs:"
if [ -f .env ]; then
  DOMAIN=$(grep '^DOMAIN=' .env | cut -d= -f2)
  echo "Portainer : https://portainer.${DOMAIN}"
  echo "Grafana   : https://grafana.${DOMAIN}"
  echo "MinIO     : https://minio.${DOMAIN}"
  echo "RabbitMQ  : https://rabbitmq.${DOMAIN}"
  echo "Status    : https://status.${DOMAIN}"
fi

echo ""
echo "Telephony:"
if [ -f .env ]; then
  SIP_DOMAIN=$(grep '^SIP_DOMAIN=' .env | cut -d= -f2)
  KAMAILIO_SIP_PORT=$(grep '^KAMAILIO_SIP_PORT=' .env | cut -d= -f2)
  echo "SIP       : ${SIP_DOMAIN}:${KAMAILIO_SIP_PORT}"
fi
STATUS

cat > scripts/healthcheck.sh <<'HEALTH'
#!/bin/bash
set -e

cd "$(dirname "$0")/.."

FAIL=0

echo "===================================="
echo " KNVOX HEALTHCHECK"
echo "===================================="
echo ""

if ! systemctl is-active --quiet docker; then
  echo "ERROR: Docker is not running"
  FAIL=1
else
  echo "OK: Docker is running"
fi

echo ""

for svc in $(./scripts/compose.sh ps --services); do
  CID=$(./scripts/compose.sh ps -q "$svc" || true)

  if [ -z "$CID" ]; then
    echo "ERROR: $svc has no container"
    FAIL=1
    continue
  fi

  STATUS=$(docker inspect -f '{{.State.Status}}' "$CID")
  HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CID")

  if [ "$STATUS" != "running" ]; then
    echo "ERROR: $svc status=$STATUS health=$HEALTH"
    FAIL=1
  elif [ "$HEALTH" = "unhealthy" ]; then
    echo "ERROR: $svc status=$STATUS health=$HEALTH"
    FAIL=1
  else
    echo "OK: $svc status=$STATUS health=$HEALTH"
  fi
done

echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "GLOBAL STATUS: OK"
  exit 0
else
  echo "GLOBAL STATUS: ERROR"
  exit 1
fi
HEALTH

chmod +x scripts/*.sh

echo "[9/10] Documentation et Makefile..."

cat > docs/TELEPHONY.md <<'TELDOC'
# KNVOX V1.1.0 Telephony Foundation

## Services

- Kamailio : SIP Proxy / SBC
- RTPEngine : RTP media proxy
- FreeSWITCH : softswitch / media server

## Ports publics V1.1

- 5060/udp + 5060/tcp : Kamailio SIP
- 30000-40000/udp : RTP via RTPEngine

## FreeSWITCH

FreeSWITCH écoute localement sur 127.0.0.1:5070.
Il ne doit pas être exposé directement aux clients.

## Test SIP

Utilisateurs de test : 1000 à 1019.

Le mot de passe est dans le fichier .env, variable FS_DEFAULT_PASSWORD.

Numéro de test echo : 9996.

## Important

Ne pas connecter de fournisseur PSTN/minutes tant que la sécurité antifraude et le billing ne sont pas en place.
TELDOC

cat > Makefile <<'MAKEFILE'
.RECIPEPREFIX := >
.PHONY: start stop restart status health logs backup pull update firewall telephony telephony-status fs sip-users firewall-telephony

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
MAKEFILE

echo "[10/10] Validation Compose..."

./scripts/compose.sh config >/dev/null

echo ""
echo "================================================"
echo " V1.1.0 Telephony générée avec succès."
echo "================================================"
echo ""
echo "IP publique : ${PUBLIC_IP}"
echo "IP locale   : ${LOCAL_IP}"
echo "SIP domaine : ${SIP_DOMAIN}"
echo ""
echo "Prochaine commande :"
echo "make telephony"
echo ""
