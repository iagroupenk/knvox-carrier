#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
set -a
source .env
set +a

CODE="${1:-CC-DEMO-001}"
NAME="${2:-Demo Call Center}"
BALANCE="${3:-25.00}"
CPS="${4:-1}"
CONCURRENT="${5:-2}"

curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/customers" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "{\"code\":\"${CODE}\",\"name\":\"${NAME}\",\"currency\":\"EUR\",\"prepaid_balance\":${BALANCE},\"cps_limit\":${CPS},\"max_concurrent_calls\":${CONCURRENT},\"daily_spend_limit\":20.0,\"max_rate_per_min\":0.5,\"max_call_duration_sec\":3600}" | jq .
