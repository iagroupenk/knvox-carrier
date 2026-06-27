#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
set -a
source .env
set +a

CUSTOMER="${1:-TEST1000}"
USERNAME="${2:-2001}"
DISPLAY="${3:-SIP Account ${USERNAME}}"
PASSWORD="${4:-}"

if [ -z "$PASSWORD" ]; then
  BODY="{\"username\":\"${USERNAME}\",\"customer_code\":\"${CUSTOMER}\",\"display_name\":\"${DISPLAY}\",\"realm\":\"knvox.local\",\"enabled\":true,\"cps_limit\":1,\"max_concurrent_calls\":2,\"notes\":\"Created by CLI\"}"
else
  BODY="{\"username\":\"${USERNAME}\",\"customer_code\":\"${CUSTOMER}\",\"display_name\":\"${DISPLAY}\",\"auth_password\":\"${PASSWORD}\",\"realm\":\"knvox.local\",\"enabled\":true,\"cps_limit\":1,\"max_concurrent_calls\":2,\"notes\":\"Created by CLI\"}"
fi

curl -fsS \
  -X POST \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/sip-accounts" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "${BODY}" | jq .
