#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

route_test() {
  DST="$1"
  CALLID="provider-route-${DST}-$(date +%s)"

  echo ""
  echo "ROUTE TEST dst=${DST}"

  curl -fsS \
    -X POST \
    "http://127.0.0.1:${BILLING_API_PORT}/api/v1/provider-route-simulate" \
    -H "Content-Type: application/json" \
    -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
    -d "{\"customer_code\":\"TEST1000\",\"src\":\"1000\",\"dst\":\"${DST}\",\"call_id\":\"${CALLID}\"}" | jq .
}

echo "===================================="
echo " KNVOX PROVIDER ROUTING SANDBOX TEST"
echo "===================================="

echo ""
echo "[1/5] Routes fournisseurs sandbox"
./scripts/provider-routes.sh

echo ""
echo "[2/5] Interne 9996 : aucun fournisseur nécessaire"
route_test "9996"

echo ""
echo "[3/5] France 33612345678 : route trouvée mais PSTN désactivé"
route_test "33612345678"

echo ""
echo "[4/5] Préfixe bloqué 882 : refus immédiat"
route_test "882123456"

echo ""
echo "[5/5] Dernières décisions routing"
./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
SELECT
  created_at,
  customer_code,
  src,
  dst,
  normalized_dst,
  selected_provider_code,
  route_allowed,
  route_reason,
  destination,
  sell_rate_per_min,
  buy_rate_per_min,
  margin_per_min,
  estimated_margin,
  pstn_enabled
FROM billing.routing_decisions
ORDER BY created_at DESC
LIMIT 10;
SQL

echo ""
echo "Test Provider Routing Sandbox terminé."
