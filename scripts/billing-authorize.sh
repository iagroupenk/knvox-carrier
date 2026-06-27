#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

CUSTOMER="${1:-TEST1000}"
SRC="${2:-1000}"
DST="${3:-9996}"
CALLID="${4:-knvox-auth-$(date +%Y%m%d%H%M%S)}"

set -a
source .env
set +a

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -v customer="$CUSTOMER" \
  -v src="$SRC" \
  -v dst="$DST" \
  -v callid="$CALLID" <<'SQL'
SELECT *
FROM billing.authorize_call(:'customer', :'src', :'dst', :'callid');
SQL
