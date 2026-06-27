#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

CUSTOMER="${1:-TEST1000}"

set -a
source .env
set +a

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -v customer="$CUSTOMER" <<'SQL'
SELECT
  c.code,
  c.name,
  c.status,
  c.currency,
  c.prepaid_balance,
  COALESCE(SUM(x.cost), 0)::numeric(14,6) AS rated_usage,
  (c.prepaid_balance - COALESCE(SUM(x.cost), 0))::numeric(14,6) AS theoretical_remaining_balance,
  c.max_concurrent_calls,
  c.cps_limit
FROM billing.customers c
LEFT JOIN billing.cdrs x ON x.customer_code = c.code
WHERE c.code = :'customer'
GROUP BY c.code, c.name, c.status, c.currency, c.prepaid_balance, c.max_concurrent_calls, c.cps_limit;
SQL
