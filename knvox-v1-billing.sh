#!/bin/bash
set -euo pipefail

echo "================================================"
echo " KNVOX Carrier Platform - V1.3.0 Billing Core"
echo "================================================"

cd /opt/knvox-carrier

if [ ! -f .env ]; then
  echo "ERROR: .env introuvable"
  exit 1
fi

set -a
source .env
set +a

env_get() {
  grep -E "^$1=" .env | tail -n1 | cut -d= -f2- || true
}

env_set_if_missing() {
  KEY="$1"
  VALUE="$2"
  CURRENT="$(env_get "$KEY")"
  if [ -z "$CURRENT" ]; then
    echo "${KEY}=${VALUE}" >> .env
  fi
}

env_set_if_missing CGRATES_ENGINE_IMAGE "dkr.cgrates.org/master/cgr-engine:latest"
env_set_if_missing CGRATES_CONSOLE_IMAGE "dkr.cgrates.org/master/cgr-console:latest"
env_set_if_missing CGRATES_LOADER_IMAGE "dkr.cgrates.org/master/cgr-loader:latest"
env_set_if_missing CGRATES_JSONRPC_PORT "2012"
env_set_if_missing CGRATES_HTTP_PORT "2080"
env_set_if_missing BILLING_CURRENCY "EUR"
env_set_if_missing BILLING_DEFAULT_CUSTOMER "TEST1000"

chmod 600 .env

set -a
source .env
set +a

mkdir -p compose/billing
mkdir -p configs/cgrates
mkdir -p storage/billing/{cgrates,cdr,incoming,processed,failed,exports}
mkdir -p database/schemas
mkdir -p scripts
mkdir -p docs

echo "[1/8] Pull images CGRateS..."
docker pull "${CGRATES_ENGINE_IMAGE}"
docker pull "${CGRATES_CONSOLE_IMAGE}"
docker pull "${CGRATES_LOADER_IMAGE}"

echo "[2/8] Extraction configuration CGRateS par défaut si absente..."

if [ ! -f configs/cgrates/cgrates.json ]; then
  docker rm -f knvox-cgrates-init >/dev/null 2>&1 || true
  CID=$(docker create --name knvox-cgrates-init "${CGRATES_ENGINE_IMAGE}")
  docker cp "${CID}:/etc/cgrates/." configs/cgrates/ || true
  docker rm -f knvox-cgrates-init >/dev/null 2>&1 || true
fi

echo "[3/8] Compose billing..."

cat > compose/billing/docker-compose.yml <<'BILLCOMPOSE'
services:

  cgr-engine:
    image: ${CGRATES_ENGINE_IMAGE}
    container_name: knvox-cgr-engine
    restart: unless-stopped
    command:
      - -config_path=/etc/cgrates
      - -logger=*stdout
    environment:
      DOCKER_IP: 127.0.0.1
      REDIS_HOST: redis
      REDIS_PORT: "6379"
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      CGRATES_JSONRPC_PORT: ${CGRATES_JSONRPC_PORT}
      CGRATES_HTTP_PORT: ${CGRATES_HTTP_PORT}
      TZ: ${TIMEZONE}
    volumes:
      - ./configs/cgrates:/etc/cgrates
      - ./storage/billing/cgrates:/var/lib/cgrates
      - ./storage/billing/cdr:/var/spool/cgrates/cdr
    ports:
      - "127.0.0.1:${CGRATES_JSONRPC_PORT}:2012"
      - "127.0.0.1:${CGRATES_HTTP_PORT}:2080"
    networks:
      - backend
      - database
BILLCOMPOSE

echo "[4/8] Mise à jour compose helper..."

cat > scripts/compose.sh <<'COMPOSESH'
#!/bin/bash
set -e

cd "$(dirname "$0")/.."

FILES=(-f docker-compose.yml)

if [ -f compose/telephony/docker-compose.yml ]; then
  FILES+=(-f compose/telephony/docker-compose.yml)
fi

if [ -f compose/billing/docker-compose.yml ]; then
  FILES+=(-f compose/billing/docker-compose.yml)
fi

exec docker compose "${FILES[@]}" "$@"
COMPOSESH

chmod +x scripts/compose.sh

echo "[5/8] Schéma PostgreSQL billing KNVOX..."

cat > database/schemas/billing_v1.sql <<'SQL'
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS billing;

CREATE TABLE IF NOT EXISTS billing.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    currency TEXT NOT NULL DEFAULT 'EUR',
    prepaid_balance NUMERIC(14,6) NOT NULL DEFAULT 0,
    credit_limit NUMERIC(14,6) NOT NULL DEFAULT 0,
    max_concurrent_calls INTEGER NOT NULL DEFAULT 2,
    cps_limit INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS billing.providers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'inactive',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS billing.rate_decks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    currency TEXT NOT NULL DEFAULT 'EUR',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS billing.rate_prefixes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deck_code TEXT NOT NULL REFERENCES billing.rate_decks(code) ON DELETE CASCADE,
    prefix TEXT NOT NULL,
    destination TEXT NOT NULL,
    rate_per_min NUMERIC(14,6) NOT NULL,
    setup_fee NUMERIC(14,6) NOT NULL DEFAULT 0,
    minimum_sec INTEGER NOT NULL DEFAULT 1,
    increment_sec INTEGER NOT NULL DEFAULT 1,
    enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(deck_code, prefix)
);

CREATE TABLE IF NOT EXISTS billing.blocked_prefixes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prefix TEXT UNIQUE NOT NULL,
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS billing.cdrs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_id TEXT UNIQUE NOT NULL,
    customer_code TEXT REFERENCES billing.customers(code),
    src TEXT,
    dst TEXT NOT NULL,
    destination TEXT,
    duration_sec INTEGER NOT NULL DEFAULT 0,
    rate_per_min NUMERIC(14,6) NOT NULL DEFAULT 0,
    cost NUMERIC(14,6) NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'EUR',
    status TEXT NOT NULL DEFAULT 'rated',
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS billing.wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_code TEXT NOT NULL REFERENCES billing.customers(code),
    amount NUMERIC(14,6) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'EUR',
    type TEXT NOT NULL,
    reference TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_billing_cdrs_customer ON billing.cdrs(customer_code);
CREATE INDEX IF NOT EXISTS idx_billing_cdrs_started_at ON billing.cdrs(started_at);
CREATE INDEX IF NOT EXISTS idx_billing_rate_prefixes_prefix ON billing.rate_prefixes(prefix);
SQL

echo "[6/8] Scripts billing..."

cat > scripts/billing-db-init.sh <<'INITDB'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < database/schemas/billing_v1.sql

echo "Billing schema installé dans PostgreSQL."
INITDB

cat > scripts/billing-sample-data.sh <<'SAMPLEDATA'
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
SAMPLEDATA

cat > scripts/billing-cdr-test.sh <<'CDRTEST'
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
CDRTEST

cat > scripts/billing-status.sh <<'BILLSTATUS'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX BILLING STATUS"
echo "===================================="
echo ""

./scripts/compose.sh ps cgr-engine || true

echo ""
echo "CGRateS logs:"
./scripts/compose.sh logs --tail=80 cgr-engine || true

echo ""
echo "PostgreSQL billing tables:"
./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt billing.*" || true

echo ""
echo "CGRateS console status:"
docker run --rm --network host "${CGRATES_CONSOLE_IMAGE}" status || true
BILLSTATUS

cat > scripts/cgr-console.sh <<'CGRCONSOLE'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

docker run --rm --network host "${CGRATES_CONSOLE_IMAGE}" "$@"
CGRCONSOLE

chmod +x scripts/*.sh

echo "[7/8] Documentation..."

cat > docs/BILLING.md <<'DOC'
# KNVOX V1.3.0 - Billing Core

## Objectif

Cette version installe la base billing KNVOX :

- CGRateS engine
- PostgreSQL schema billing
- clients
- fournisseurs
- rate decks
- préfixes tarifaires
- CDRs
- wallet transactions
- prefixes bloqués

## Ports

CGRateS est exposé uniquement localement :

- 127.0.0.1:2012 JSON-RPC
- 127.0.0.1:2080 HTTP API si activée

Aucun port billing n'est exposé publiquement.

## Important

Aucun fournisseur PSTN n'est encore connecté.

Les appels externes restent bloqués par Kamailio jusqu'à la mise en place complète :

- contrôle solde
- autorisation d'appel
- limite CPS
- limite appels simultanés
- LCR
- anti-fraude destination
DOC

echo "[8/8] Makefile..."

cat > Makefile <<'MAKEFILE'
.RECIPEPREFIX := >
.PHONY: start stop restart status health logs backup pull update firewall telephony telephony-status fs sip-users firewall-telephony sip-security-test sip-security-logs billing billing-status billing-db-init billing-sample-data billing-cdr-test cgr-console

start:
>./scripts/compose.sh up -d

stop:
>./scripts/compose.sh down

restart:
>./scripts/compose.sh restart

status:
>./scripts/status.sh

health:
>./scripts/healthcheck.sh

logs:
>./scripts/logs.sh

backup:
>./scripts/backup.sh

pull:
>./scripts/compose.sh pull

update:
>./scripts/compose.sh pull
>./scripts/compose.sh up -d

firewall:
>./scripts/firewall.sh

telephony:
>./scripts/compose.sh up -d --build freeswitch rtpengine kamailio

telephony-status:
>./scripts/telephony-status.sh

fs:
>./scripts/fs_cli.sh

sip-users:
>./scripts/show-sip-users.sh

firewall-telephony:
>./scripts/firewall-telephony.sh

sip-security-test:
>./scripts/sip-security-test.sh

sip-security-logs:
>./scripts/sip-security-logs.sh

billing:
>./scripts/compose.sh up -d cgr-engine

billing-status:
>./scripts/billing-status.sh

billing-db-init:
>./scripts/billing-db-init.sh

billing-sample-data:
>./scripts/billing-sample-data.sh

billing-cdr-test:
>./scripts/billing-cdr-test.sh

cgr-console:
>./scripts/cgr-console.sh status
MAKEFILE

./scripts/compose.sh config >/dev/null

echo ""
echo "V1.3.0 Billing Core générée."
echo ""
echo "Prochaines commandes :"
echo "make billing"
echo "make billing-db-init"
echo "make billing-sample-data"
echo "make billing-cdr-test"
echo "make billing-status"
