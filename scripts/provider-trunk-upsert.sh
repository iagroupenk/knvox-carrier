#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

PROVIDER="${1:-SIM-FR-1}"
NAME="${2:-Sandbox Provider}"
HOST="${3:-sandbox.invalid}"
PORT="${4:-5060}"
TRANSPORT="${5:-udp}"
ENABLED="${6:-false}"

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -v provider="$PROVIDER" \
  -v name="$NAME" \
  -v host="$HOST" \
  -v port="$PORT" \
  -v transport="$TRANSPORT" \
  -v enabled="$ENABLED" <<'SQL'
SELECT *
FROM billing.upsert_provider_trunk(
  :'provider',
  :'name',
  :'host',
  :'port'::INTEGER,
  :'transport',
  NULL,
  NULL,
  :'host',
  false,
  :'enabled'::BOOLEAN,
  true,
  1,
  2,
  'Created by CLI sandbox'
);
SQL
