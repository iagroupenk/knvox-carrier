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
