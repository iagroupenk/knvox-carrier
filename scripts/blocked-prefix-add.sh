#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

PREFIX="${1:-44870}"
REASON="${2:-Test blocked prefix}"

curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/blocked-prefixes" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"prefix\":\"${PREFIX}\",\"reason\":\"${REASON}\"}" | jq .
