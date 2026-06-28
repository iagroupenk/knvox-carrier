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
LOG_FILE="${KNVOX_AUTH_LOG:-/var/log/knvox/auth.log}"
CACHE_FILE="${KNVOX_AUTH_CACHE_FILE:-/tmp/knvox-authorized-callids.cache}"
CACHE_TTL="${KNVOX_AUTH_CACHE_TTL:-180}"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

log_line() {
  echo "$(date -Is) $*" >> "$LOG_FILE" 2>/dev/null || true
}

cleanup_cache() {
  NOW="$(date +%s)"
  TMP_FILE="${CACHE_FILE}.tmp"

  if [ -f "$CACHE_FILE" ]; then
    awk -F'|' -v now="$NOW" -v ttl="$CACHE_TTL" '($1 + ttl) > now {print $0}' "$CACHE_FILE" > "$TMP_FILE" 2>/dev/null || true
    mv "$TMP_FILE" "$CACHE_FILE" 2>/dev/null || true
  else
    touch "$CACHE_FILE" 2>/dev/null || true
  fi
}

is_duplicate_allowed() {
  [ -f "$CACHE_FILE" ] || return 1

  awk -F'|' \
    -v callid="$CALL_ID" \
    -v user="$SIP_USERNAME" \
    -v src="$SRC" \
    -v dst="$DST" \
    '$2==callid && $3==user && $4==src && $5==dst {found=1} END {exit !found}' \
    "$CACHE_FILE"
}

store_allowed_callid() {
  NOW="$(date +%s)"
  echo "${NOW}|${CALL_ID}|${SIP_USERNAME}|${SRC}|${DST}|${CUSTOMER_CODE}" >> "$CACHE_FILE" 2>/dev/null || true
}

if [ -z "$TOKEN" ]; then
  log_line "DENY username=${SIP_USERNAME} reason=missing_api_token call_id=${CALL_ID}"
  exit 1
fi

if [ -z "$SIP_USERNAME" ] || [ -z "$DST" ] || [ -z "$CALL_ID" ]; then
  log_line "DENY username=${SIP_USERNAME} reason=missing_arguments call_id=${CALL_ID}"
  exit 1
fi

cleanup_cache

if is_duplicate_allowed; then
  log_line "ALLOW_DUPLICATE username=${SIP_USERNAME} src=${SRC} dst=${DST} call_id=${CALL_ID} reason=duplicate_invite_cached"
  exit 0
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

BODY="$(jq -cn \
  --arg customer_code "$CUSTOMER_CODE" \
  --arg src "$SRC" \
  --arg dst "$DST" \
  --arg call_id "$CALL_ID" \
  '{customer_code:$customer_code,src:$src,dst:$dst,call_id:$call_id}')"

START_JSON="$(curl -fsS \
  -X POST \
  "${API_URL}/api/v1/start-call" \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${TOKEN}" \
  -d "$BODY" || true)"

if [ -z "$START_JSON" ]; then
  log_line "DENY username=${SIP_USERNAME} customer=${CUSTOMER_CODE} reason=start_call_api_error src=${SRC} dst=${DST} call_id=${CALL_ID}"
  exit 1
fi

START_ALLOWED="$(echo "$START_JSON" | jq -r '.allowed // false')"
START_REASON="$(echo "$START_JSON" | jq -r '.reason // "unknown"')"

if [ "$START_ALLOWED" = "true" ]; then
  store_allowed_callid
  log_line "ALLOW username=${SIP_USERNAME} customer=${CUSTOMER_CODE} reason=${START_REASON} src=${SRC} dst=${DST} ip=${SOURCE_IP} call_id=${CALL_ID}"
  exit 0
fi

log_line "DENY username=${SIP_USERNAME} customer=${CUSTOMER_CODE} reason=${START_REASON} src=${SRC} dst=${DST} ip=${SOURCE_IP} call_id=${CALL_ID}"
exit 1
