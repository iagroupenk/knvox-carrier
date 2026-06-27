#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

CUSTOMER="${1:-TEST1000}"
DATE_FROM="${2:-2026-01-01}"
DATE_TO="${3:-2026-12-31}"

set -a
source .env
set +a

curl -fsS \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/reports/customers/${CUSTOMER}/margin?date_from=${DATE_FROM}&date_to=${DATE_TO}" | jq .
