#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX FRAUD GUARD STATUS"
echo "===================================="
echo ""

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
SELECT
  code,
  status,
  prepaid_balance,
  cps_limit,
  max_concurrent_calls,
  fraud_locked,
  daily_spend_limit,
  max_rate_per_min,
  max_call_duration_sec
FROM billing.customers
ORDER BY code;

SELECT
  event_type,
  severity,
  count(*) AS events
FROM billing.fraud_events
WHERE created_at >= now() - interval '24 hours'
GROUP BY event_type, severity
ORDER BY events DESC, event_type;

SELECT
  created_at,
  customer_code,
  event_type,
  severity,
  src,
  dst,
  call_id,
  details
FROM billing.fraud_events
ORDER BY created_at DESC
LIMIT 10;

SELECT
  created_at,
  customer_code,
  src,
  dst,
  allowed,
  reason,
  call_id
FROM billing.call_attempts
ORDER BY created_at DESC
LIMIT 10;
SQL
