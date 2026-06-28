#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX EXTERNAL CALL DRY-RUN TEST"
echo "===================================="

echo ""
echo "[1/5] Force PSTN OFF"
make pstn-force-off

echo ""
echo "[2/5] Dry-run France sandbox"
./scripts/external-call-dry-run.sh 33612345678

echo ""
echo "[3/5] Dry-run préfixe bloqué 882"
./scripts/external-call-dry-run.sh 882123456 || true

echo ""
echo "[4/5] Derniers dry-runs API"
./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
SELECT
  created_at,
  customer_code,
  src,
  dst,
  selected_provider_code,
  route_allowed,
  route_reason,
  pstn_enabled
FROM billing.external_call_dry_run_events
ORDER BY created_at DESC
LIMIT 10;
SQL

echo ""
echo "[5/5] Safety + health"
make pstn-safety-audit
make health

echo ""
echo "Test V1.6.5 terminé. Aucun appel réel placé."
