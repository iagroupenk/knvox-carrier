#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

PROVIDER="${1:-SIM-UK-1}"
PREFIX="${2:-44}"
DEST="${3:-UK Sandbox}"
BUYRATE="${4:-0.010000}"

curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/provider-routes" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"provider_code\":\"${PROVIDER}\",\"prefix\":\"${PREFIX}\",\"destination\":\"${DEST}\",\"buy_rate_per_min\":${BUYRATE},\"setup_fee\":0,\"minimum_sec\":1,\"increment_sec\":1,\"enabled\":true,\"priority\":50}" | jq .
