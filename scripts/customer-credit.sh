#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
set -a
source .env
set +a

CUSTOMER="${1:-TEST1000}"
AMOUNT="${2:-10.00}"
REFERENCE="${3:-manual-credit-$(date +%s)}"

curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/customers/${CUSTOMER}/credit" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"amount\":${AMOUNT},\"reference\":\"${REFERENCE}\",\"note\":\"CLI credit\"}" | jq .
