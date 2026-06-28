#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX PSTN STATUS"
echo "===================================="

echo ""
echo "[1/4] Settings"
./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
SELECT key, value
FROM billing.system_settings
WHERE key IN ('pstn_enabled', 'require_balance', 'min_call_balance')
ORDER BY key;
SQL

echo ""
echo "[2/4] Provider trunks"
./scripts/provider-trunk-list.sh || true

echo ""
echo "[3/4] Active calls"
./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
SELECT count(*) AS active_calls
FROM billing.active_calls;
SQL

echo ""
echo "[4/4] Dernières décisions routing"
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
FROM billing.routing_decisions
ORDER BY created_at DESC
LIMIT 10;
SQL
