#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "Reset active calls + call attempts CC-DEMO-001 / 1002..."

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
DELETE FROM billing.active_calls
WHERE src = '1002'
   OR customer_code = 'CC-DEMO-001'
   OR call_id LIKE '%1002%';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema='billing'
          AND table_name='call_attempts'
    ) THEN
        DELETE FROM billing.call_attempts
        WHERE customer_code = 'CC-DEMO-001'
          AND created_at > now() - interval '30 minutes';
    END IF;
END $$;

SELECT count(*) AS active_calls_after_reset FROM billing.active_calls;
SQL

rm -f /tmp/knvox-authorized-callids.cache 2>/dev/null || true
./scripts/compose.sh exec -T kamailio sh -lc 'rm -f /tmp/knvox-authorized-callids.cache || true'
