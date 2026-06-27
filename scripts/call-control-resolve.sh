#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
set -a
source .env
set +a

USERNAME="${1:-1000}"
SOURCE_IP="${2:-127.0.0.1}"

curl -fsS \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  "http://127.0.0.1:${BILLING_API_PORT}/api/v1/call-control/resolve-sip-account/${USERNAME}?source_ip=${SOURCE_IP}" | jq .
