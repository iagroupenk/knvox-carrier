#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
set -a
source .env
set +a

CUSTOMER="${1:-TEST1000}"
CPS="${2:-1}"
CONCURRENT="${3:-2}"
DAILY="${4:-20.0}"
MAXRATE="${5:-0.5}"

curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/customers/${CUSTOMER}/limits" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"cps_limit\":${CPS},\"max_concurrent_calls\":${CONCURRENT},\"daily_spend_limit\":${DAILY},\"max_rate_per_min\":${MAXRATE},\"max_call_duration_sec\":3600}" | jq .
