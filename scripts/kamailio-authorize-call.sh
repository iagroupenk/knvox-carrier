#!/bin/bash
set -euo pipefail

SIP_USERNAME="${1:-}"
SRC="${2:-}"
DST="${3:-}"
CALL_ID="${4:-}"
SOURCE_IP="${5:-}"

if [ -f /opt/knvox-carrier/.env ]; then
  set -a
  source /opt/knvox-carrier/.env
  set +a
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
if [ -n "${ROOT_DIR}" ] && [ -f "${ROOT_DIR}/.env" ]; then
  set -a
  source "${ROOT_DIR}/.env"
  set +a
fi

API_URL="${BILLING_API_URL:-http://127.0.0.1:${BILLING_API_PORT:-8088}}"
TOKEN="${BILLING_API_TOKEN:-}"
LOG_FILE="${KNVOX_AUTH_LOG:-/var/log/knvox/kamailio-auth.log}"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

log_line() {
  echo "$(date -Is) $*" >> "$LOG_FILE" 2>/dev/null || true
}

if [ -z "$TOKEN" ]; then
  log_line "DENY username=${SIP_USERNAME} reason=missing_api_token call_id=${CALL_ID}"
  exit 1
fi

if [ -z "$SIP_USERNAME" ] || [ -z "$DST" ] || [ -z "$CALL_ID" ]; then
  log_line "DENY username=${SIP_USERNAME} reason=missing_arguments call_id=${CALL_ID}"
  exit 1
fi

RESOLVE_JSON="$(curl -fsS \
  -H "X-KNVOX-API-Key: ${TOKEN}" \
  "${API_URL}/api/v1/call-control/resolve-sip-account/${SIP_USERNAME}?source_ip=${SOURCE_IP}" || true)"

if [ -z "$RESOLVE_JSON" ]; then
  log_line "DENY username=${SIP_USERNAME} reason=resolve_api_error call_id=${CALL_ID}"
  exit 1
fi

RESOLVE_ALLOWED="$(echo "$RESOLVE_JSON" | jq -r '.allowed // false')"
CUSTOMER_CODE="$(echo "$RESOLVE_JSON" | jq -r '.customer_code // empty')"
RESOLVE_REASON="$(echo "$RESOLVE_JSON" | jq -r '.reason // "unknown"')"

if [ "$RESOLVE_ALLOWED" != "true" ] || [ -z "$CUSTOMER_CODE" ]; then
  log_line "DENY username=${SIP_USERNAME} customer=${CUSTOMER_CODE} reason=${RESOLVE_REASON} src=${SRC} dst=${DST} ip=${SOURCE_IP} call_id=${CALL_ID}"
  exit 1
fi

START_JSON="$(curl -fsS \
  -X POST \
  "${API_URL}/api/v1/start-call" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${TOKEN}" \
  -d "{\"customer_code\":\"${CUSTOMER_CODE}\",\"src\":\"${SRC}\",\"dst\":\"${DST}\",\"call_id\":\"${CALL_ID}\"}" || true)"

if [ -z "$START_JSON" ]; then
  log_line "DENY username=${SIP_USERNAME} customer=${CUSTOMER_CODE} reason=start_call_api_error src=${SRC} dst=${DST} call_id=${CALL_ID}"
  exit 1
fi

START_ALLOWED="$(echo "$START_JSON" | jq -r '.allowed // false')"
START_REASON="$(echo "$START_JSON" | jq -r '.reason // "unknown"')"

if [ "$START_ALLOWED" = "true" ]; then
  log_line "ALLOW username=${SIP_USERNAME} customer=${CUSTOMER_CODE} reason=${START_REASON} src=${SRC} dst=${DST} ip=${SOURCE_IP} call_id=${CALL_ID}"
  exit 0
fi

log_line "DENY username=${SIP_USERNAME} customer=${CUSTOMER_CODE} reason=${START_REASON} src=${SRC} dst=${DST} ip=${SOURCE_IP} call_id=${CALL_ID}"
exit 1
