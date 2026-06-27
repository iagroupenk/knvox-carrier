#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<SQL
INSERT INTO billing.customers(code, name, currency, prepaid_balance, credit_limit, max_concurrent_calls, cps_limit)
VALUES ('TEST1000', 'KNVOX Test Customer 1000', '${BILLING_CURRENCY}', 10.000000, 0, 2, 1)
ON CONFLICT (code) DO UPDATE SET
  prepaid_balance = EXCLUDED.prepaid_balance,
  max_concurrent_calls = EXCLUDED.max_concurrent_calls,
  cps_limit = EXCLUDED.cps_limit;

INSERT INTO billing.providers(code, name, status)
VALUES ('NO_PROVIDER', 'No external PSTN provider connected', 'inactive')
ON CONFLICT (code) DO NOTHING;

INSERT INTO billing.rate_decks(code, name, currency)
VALUES ('KNVOX_TEST_EUR', 'KNVOX Test Retail EUR', '${BILLING_CURRENCY}')
ON CONFLICT (code) DO NOTHING;

INSERT INTO billing.rate_prefixes(deck_code, prefix, destination, rate_per_min, minimum_sec, increment_sec)
VALUES
('KNVOX_TEST_EUR', '33', 'France Test', 0.010000, 1, 1),
('KNVOX_TEST_EUR', '212', 'Morocco Test', 0.050000, 1, 1),
('KNVOX_TEST_EUR', '1', 'USA Canada Test', 0.008000, 1, 1)
ON CONFLICT (deck_code, prefix) DO UPDATE SET
  destination = EXCLUDED.destination,
  rate_per_min = EXCLUDED.rate_per_min,
  minimum_sec = EXCLUDED.minimum_sec,
  increment_sec = EXCLUDED.increment_sec;

INSERT INTO billing.blocked_prefixes(prefix, reason)
VALUES
('882', 'High risk satellite / international premium'),
('883', 'High risk global service'),
('979', 'Premium risk'),
('870', 'Inmarsat risk')
ON CONFLICT (prefix) DO NOTHING;
SQL

echo "Données billing de test installées."
