#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
SELECT
  created_at,
  provider_code,
  event_type,
  details
FROM billing.provider_trunk_events
ORDER BY created_at DESC
LIMIT 50;
SQL
