#!/bin/bash
set -euo pipefail

CALLID="${1:-unknown}"
REASON="${2:-normal}"

API_PORT="${BILLING_API_PORT:-8088}"
API_TOKEN="${BILLING_API_TOKEN:-}"
LOGFILE="${KNVOX_AUTH_LOG:-/var/log/knvox/auth.log}"

mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true

PAYLOAD=$(jq -nc \
  --arg callid "$CALLID" \
  --arg reason "$REASON" \
  '{call_id:$callid,reason:$reason}')

RESP=$(curl -fsS \
  --max-time 2 \
  -X POST \
  "http://127.0.0.1:${API_PORT}/api/v1/end-call" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${API_TOKEN}" \
  -d "$PAYLOAD" 2>/dev/null || true)

FOUND=$(printf '%s' "$RESP" | jq -r '.found // false' 2>/dev/null || echo "false")
COST=$(printf '%s' "$RESP" | jq -r '.cost // 0' 2>/dev/null || echo "0")
DURATION=$(printf '%s' "$RESP" | jq -r '.duration_sec // 0' 2>/dev/null || echo "0")
BALANCE=$(printf '%s' "$RESP" | jq -r '.balance_after // 0' 2>/dev/null || echo "0")
RESULT_REASON=$(printf '%s' "$RESP" | jq -r '.reason // "api_error"' 2>/dev/null || echo "api_error")

echo "$(date -Is) END found=${FOUND} reason=${RESULT_REASON} callid=${CALLID} duration=${DURATION} cost=${COST} balance_after=${BALANCE}" >> "$LOGFILE" 2>/dev/null || true

exit 0
