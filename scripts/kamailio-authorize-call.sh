#!/bin/bash
set -euo pipefail

CUSTOMER="${1:-TEST1000}"
SRC="${2:-unknown}"
DST="${3:-unknown}"
CALLID="${4:-unknown}"

API_PORT="${BILLING_API_PORT:-8088}"
API_TOKEN="${BILLING_API_TOKEN:-}"
LOGFILE="${KNVOX_AUTH_LOG:-/var/log/knvox/auth.log}"

mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true

if [ -z "$API_TOKEN" ]; then
  echo "$(date -Is) DENY missing_api_token customer=${CUSTOMER} src=${SRC} dst=${DST} callid=${CALLID}" >> "$LOGFILE" 2>/dev/null || true
  exit 1
fi

PAYLOAD=$(jq -nc \
  --arg customer "$CUSTOMER" \
  --arg src "$SRC" \
  --arg dst "$DST" \
  --arg callid "$CALLID" \
  '{customer_code:$customer,src:$src,dst:$dst,call_id:$callid}')

RESP=$(curl -fsS \
  --max-time 2 \
  -X POST \
  "http://127.0.0.1:${API_PORT}/api/v1/authorize-call" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${API_TOKEN}" \
  -d "$PAYLOAD" 2>/dev/null || true)

ALLOWED=$(printf '%s' "$RESP" | jq -r '.allowed // false' 2>/dev/null || echo "false")
REASON=$(printf '%s' "$RESP" | jq -r '.reason // "api_error"' 2>/dev/null || echo "api_error")
RATE=$(printf '%s' "$RESP" | jq -r '.rate_per_min // 0' 2>/dev/null || echo "0")
BALANCE=$(printf '%s' "$RESP" | jq -r '.customer_balance // 0' 2>/dev/null || echo "0")

echo "$(date -Is) allowed=${ALLOWED} reason=${REASON} customer=${CUSTOMER} src=${SRC} dst=${DST} callid=${CALLID} rate=${RATE} balance=${BALANCE}" >> "$LOGFILE" 2>/dev/null || true

if [ "$ALLOWED" = "true" ]; then
  exit 0
fi

exit 1
