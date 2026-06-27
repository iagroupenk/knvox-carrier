#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX RATE ADMIN TEST"
echo "===================================="

echo ""
echo "[1/7] Ajout tarif de vente UK 44"
./scripts/rate-upsert.sh 44 "United Kingdom Test" 0.020000

echo ""
echo "[2/7] Ajout route fournisseur sandbox UK"
./scripts/provider-route-upsert.sh SIM-UK-1 44 "UK Sandbox" 0.010000

echo ""
echo "[3/7] Simulation route UK, PSTN doit rester désactivé"
set -a
source .env
set +a

curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/provider-route-simulate" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"customer_code\":\"TEST1000\",\"src\":\"1000\",\"dst\":\"447700900123\",\"call_id\":\"rate-admin-uk-$(date +%s)\"}" | jq .

echo ""
echo "[4/7] Ajout préfixe bloqué test 44870"
./scripts/blocked-prefix-add.sh 44870 "UK premium test block"

echo ""
echo "[5/7] Simulation préfixe bloqué"
curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/provider-route-simulate" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"customer_code\":\"TEST1000\",\"src\":\"1000\",\"dst\":\"44870123456\",\"call_id\":\"rate-admin-block-$(date +%s)\"}" | jq .

echo ""
echo "[6/7] Suppression préfixe bloqué test 44870"
./scripts/blocked-prefix-delete.sh 44870

echo ""
echo "[7/7] Liste tarifs et health"
./scripts/rate-list.sh
make health

echo ""
echo "Test Rate Admin terminé."
