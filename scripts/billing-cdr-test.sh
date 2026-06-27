#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

CALL_ID="knvox-test-$(date +%Y%m%d%H%M%S)"

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<SQL
WITH rate AS (
  SELECT *
  FROM billing.rate_prefixes
  WHERE enabled = true
    AND '33612345678' LIKE prefix || '%'
  ORDER BY length(prefix) DESC
  LIMIT 1
),
calc AS (
  SELECT
    '${CALL_ID}'::text AS call_id,
    'TEST1000'::text AS customer_code,
    '1000'::text AS src,
    '33612345678'::text AS dst,
    destination,
    60::integer AS duration_sec,
    rate_per_min,
    (
      setup_fee +
      (
        CEIL(GREATEST(60, minimum_sec)::numeric / increment_sec::numeric)
        * increment_sec::numeric
        / 60::numeric
        * rate_per_min
      )
    )::numeric(14,6) AS cost
  FROM rate
)
INSERT INTO billing.cdrs(call_id, customer_code, src, dst, destination, duration_sec, rate_per_min, cost, currency, status)
SELECT call_id, customer_code, src, dst, destination, duration_sec, rate_per_min, cost, '${BILLING_CURRENCY}', 'rated'
FROM calc
ON CONFLICT (call_id) DO NOTHING;

SELECT call_id, customer_code, src, dst, destination, duration_sec, rate_per_min, cost, currency, status
FROM billing.cdrs
WHERE call_id='${CALL_ID}';

SELECT
  c.code,
  c.name,
  c.prepaid_balance,
  COALESCE(SUM(x.cost),0) AS rated_usage,
  c.prepaid_balance - COALESCE(SUM(x.cost),0) AS remaining_balance
FROM billing.customers c
LEFT JOIN billing.cdrs x ON x.customer_code = c.code
WHERE c.code='TEST1000'
GROUP BY c.code, c.name, c.prepaid_balance;
SQL
