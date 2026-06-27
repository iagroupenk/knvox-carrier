#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX PORTAL PUBLIC STATUS"
echo "===================================="
echo ""

echo "URL      : https://${PORTAL_DOMAIN}"
echo "User     : ${PORTAL_BASIC_USER}"
echo "Password : ${PORTAL_BASIC_PASSWORD}"
echo ""

echo "DNS:"
getent hosts "${PORTAL_DOMAIN}" || true

echo ""
echo "Docker:"
./scripts/compose.sh ps customer-portal traefik || true

echo ""
echo "Local portal:"
curl -fsS "http://127.0.0.1:${PORTAL_PORT}/health" | jq . || true

echo ""
echo "Public HTTPS headers:"
curl -k -I "https://${PORTAL_DOMAIN}" || true

echo ""
echo "Public API through auth:"
curl -k -fsS \
  -u "${PORTAL_BASIC_USER}:${PORTAL_BASIC_PASSWORD}" \
  "https://${PORTAL_DOMAIN}/api/v1/status" | jq . || true

echo ""
echo "Logs customer-portal:"
./scripts/compose.sh logs --tail=60 customer-portal || true

echo ""
echo "Logs traefik:"
./scripts/compose.sh logs --tail=80 traefik || true
