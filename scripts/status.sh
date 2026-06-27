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
