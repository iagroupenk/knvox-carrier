#!/bin/bash
set -euo pipefail

SIP_USERNAME="${1:-}"
SOURCE_IP="${2:-}"

if [ -f /opt/knvox-carrier/.env ]; then
  set -a
  source /opt/knvox-carrier/.env
  set +a
fi

API_URL="${BILLING_API_URL:-http://127.0.0.1:${BILLING_API_PORT:-8088}}"
TOKEN="${BILLING_API_TOKEN:-}"
LOG_FILE="${KNVOX_REGISTER_LOG:-/var/log/knvox/register-guard.log}"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

log_line() {
  echo "$(date -Is) $*" >> "$LOG_FILE" 2>/dev/null || true
}

if [ -z "$TOKEN" ]; then
  log_line "DENY username=${SIP_USERNAME} ip=${SOURCE_IP} reason=missing_api_token"
  exit 1
fi

if [ -z "$SIP_USERNAME" ] || [ -z "$SOURCE_IP" ]; then
  log_line "DENY username=${SIP_USERNAME} ip=${SOURCE_IP} reason=missing_arguments"
  exit 1
fi

RESOLVE_JSON="$(curl -fsS \
  -H "X-KNVOX-API-Key: ${TOKEN}" \
  "${API_URL}/api/v1/call-control/resolve-sip-account/${SIP_USERNAME}?source_ip=${SOURCE_IP}" || true)"

if [ -z "$RESOLVE_JSON" ]; then
  log_line "DENY username=${SIP_USERNAME} ip=${SOURCE_IP} reason=resolve_api_error"
  exit 1
fi

ALLOWED="$(echo "$RESOLVE_JSON" | jq -r '.allowed // false')"
CUSTOMER_CODE="$(echo "$RESOLVE_JSON" | jq -r '.customer_code // empty')"
REASON="$(echo "$RESOLVE_JSON" | jq -r '.reason // "unknown"')"
ALLOWED_IP="$(echo "$RESOLVE_JSON" | jq -r '.allowed_ip_cidr // empty')"

if [ "$ALLOWED" = "true" ]; then
  log_line "ALLOW username=${SIP_USERNAME} customer=${CUSTOMER_CODE} ip=${SOURCE_IP} allowed_ip=${ALLOWED_IP} reason=${REASON}"
  exit 0
fi

log_line "DENY username=${SIP_USERNAME} customer=${CUSTOMER_CODE} ip=${SOURCE_IP} allowed_ip=${ALLOWED_IP} reason=${REASON}"
exit 1
