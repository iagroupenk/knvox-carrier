#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
set -a
source .env
set +a

CUSTOMER="${1:-TEST1000}"

curl -fsS \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/customers/${CUSTOMER}/cdrs" | jq .
