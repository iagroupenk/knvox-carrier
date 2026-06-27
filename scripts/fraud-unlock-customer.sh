#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

CUSTOMER="${1:-TEST1000}"

set -a
source .env
set +a

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -v customer="$CUSTOMER" <<'SQL'
UPDATE billing.customers
SET fraud_locked = false
WHERE code = :'customer';

SELECT code, fraud_locked FROM billing.customers WHERE code = :'customer';
SQL
