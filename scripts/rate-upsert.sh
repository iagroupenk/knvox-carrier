#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

PREFIX="${1:-44}"
DEST="${2:-United Kingdom Test}"
RATE="${3:-0.020000}"

curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/rates" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"prefix\":\"${PREFIX}\",\"destination\":\"${DEST}\",\"rate_per_min\":${RATE},\"setup_fee\":0,\"minimum_sec\":1,\"increment_sec\":1,\"enabled\":true}" | jq .
