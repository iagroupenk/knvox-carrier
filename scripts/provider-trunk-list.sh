#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
SELECT
  provider_code,
  trunk_name,
  sip_host,
  sip_port,
  transport,
  register,
  enabled,
  sandbox_only,
  max_cps,
  max_concurrent_calls,
  updated_at
FROM billing.provider_trunks
ORDER BY provider_code;
SQL
