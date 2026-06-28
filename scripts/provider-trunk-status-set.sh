#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

PROVIDER="${1:-SIM-FR-1}"
ENABLED="${2:-false}"

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -v provider="$PROVIDER" \
  -v enabled="$ENABLED" <<'SQL'
SELECT *
FROM billing.set_provider_trunk_status(:'provider', :'enabled'::BOOLEAN);
SQL
