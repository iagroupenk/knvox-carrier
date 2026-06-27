#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
set -a
source .env
set +a

CUSTOMER="${1:-TEST1000}"
LOCKED="${2:-true}"

curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/customers/${CUSTOMER}/fraud-lock" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"fraud_locked\":${LOCKED}}" | jq .
