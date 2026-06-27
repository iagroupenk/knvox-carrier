#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX BILLING SAFETY TEST"
echo "===================================="
echo ""

echo "[1/5] Solde client TEST1000"
./scripts/billing-balance.sh TEST1000

echo ""
echo "[2/5] Autorisation interne echo 9996"
./scripts/billing-authorize.sh TEST1000 1000 9996

echo ""
echo "[3/5] Test France 33612345678"
./scripts/billing-rate-check.sh 33612345678
./scripts/billing-authorize.sh TEST1000 1000 33612345678

echo ""
echo "[4/5] Test préfixe bloqué 882123456"
./scripts/billing-rate-check.sh 882123456
./scripts/billing-authorize.sh TEST1000 1000 882123456

echo ""
echo "[5/5] Dernières autorisations"
set -a
source .env
set +a

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
SELECT
  created_at,
  customer_code,
  src,
  dst,
  normalized_dst,
  allowed,
  reason,
  rate_per_min,
  estimated_min_cost,
  balance
FROM billing.call_authorizations
ORDER BY created_at DESC
LIMIT 10;
SQL

echo ""
echo "Test Billing Safety terminé."
