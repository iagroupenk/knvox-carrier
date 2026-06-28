#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX PROVIDER TRUNK SANDBOX TEST"
echo "===================================="

echo ""
echo "[1/6] Liste trunks sandbox"
./scripts/provider-trunk-list.sh

echo ""
echo "[2/6] Génération XML FreeSWITCH désactivé"
./scripts/provider-trunk-generate-freeswitch.sh

echo ""
echo "[3/6] Vérification PSTN désactivé"
./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
SELECT key, value
FROM billing.system_settings
WHERE key IN ('pstn_enabled', 'require_balance', 'min_call_balance')
ORDER BY key;
SQL

echo ""
echo "[4/6] Simulation route fournisseur existante si disponible"
if [ -x ./scripts/provider-route-test.sh ]; then
  ./scripts/provider-route-test.sh || true
else
  echo "provider-route-test.sh absent, simulation ignorée."
fi

echo ""
echo "[5/6] Events trunks"
./scripts/provider-trunk-events.sh

echo ""
echo "[6/6] Health"
make health

echo ""
echo "Test V1.6.0 terminé."
echo "Aucun trunk réel connecté."
