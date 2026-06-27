#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX PORTAL PUBLIC TEST"
echo "===================================="
echo ""

echo "[1/5] DNS"
if getent hosts "${PORTAL_DOMAIN}"; then
  echo "OK DNS"
else
  echo "ERREUR DNS : ${PORTAL_DOMAIN} ne résout pas encore."
  echo "Créer un A record : ${PORTAL_DOMAIN} -> 51.222.115.82"
  exit 1
fi

echo ""
echo "[2/5] Local portal"
curl -fsS "http://127.0.0.1:${PORTAL_PORT}/health" | jq .

echo ""
echo "[3/5] Public HTTPS sans auth, attendu: 401 ou 302/301 vers HTTPS"
curl -k -I "https://${PORTAL_DOMAIN}" | head -n 12 || true

echo ""
echo "[4/5] Public HTTPS avec auth"
curl -k -fsS \
  -u "${PORTAL_BASIC_USER}:${PORTAL_BASIC_PASSWORD}" \
  "https://${PORTAL_DOMAIN}/api/v1/status" | jq .

echo ""
echo "[5/5] Health global"
make health

echo ""
echo "Test portail public terminé."
echo "Ouvrir : https://${PORTAL_DOMAIN}"
echo "Login  : ${PORTAL_BASIC_USER}"
echo "Pass   : ${PORTAL_BASIC_PASSWORD}"
