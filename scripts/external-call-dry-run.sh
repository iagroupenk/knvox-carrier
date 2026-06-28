#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

DST="${1:-33612345678}"
CUSTOMER="${CUSTOMER_CODE:-TEST1000}"
SRC="${SRC:-1000}"

API_URL="${BILLING_API_URL:-http://127.0.0.1:${BILLING_API_PORT:-8088}}"

DATA="$(jq -n \
  --arg customer_code "$CUSTOMER" \
  --arg src "$SRC" \
  --arg dst "$DST" \
  '{customer_code:$customer_code, src:$src, dst:$dst}')"

curl -fsS \
  -X POST \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "$DATA" \
  "${API_URL}/api/v1/external-call/dry-run" | jq .
