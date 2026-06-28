#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

mkdir -p exports/audits

REPORT="exports/audits/pstn_safety_$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee "$REPORT") 2>&1

FAIL=0
WARN=0

psql_scalar() {
  ./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "$1" | tr -d '[:space:]'
}

ok() {
  echo "OK   - $1"
}

warn() {
  WARN=$((WARN+1))
  echo "WARN - $1"
}

fail() {
  FAIL=$((FAIL+1))
  echo "FAIL - $1"
}

echo "===================================="
echo " KNVOX PSTN SAFETY AUDIT"
echo "===================================="
echo ""

PSTN="$(psql_scalar "SELECT COALESCE((SELECT value FROM billing.system_settings WHERE key='pstn_enabled'), 'false');")"
if [ "$PSTN" = "false" ]; then
  ok "pstn_enabled=false"
else
  fail "pstn_enabled=${PSTN}"
fi

ACTIVE_CALLS="$(psql_scalar "SELECT count(*) FROM billing.active_calls;")"
if [ "$ACTIVE_CALLS" = "0" ]; then
  ok "aucun appel actif"
else
  fail "active_calls=${ACTIVE_CALLS}"
fi

TRUNKS="$(psql_scalar "SELECT count(*) FROM billing.provider_trunks;")"
if [ "$TRUNKS" -ge 1 ]; then
  ok "provider_trunks présents: ${TRUNKS}"
else
  fail "aucun provider_trunk"
fi

SANDBOX_ENABLED="$(psql_scalar "SELECT count(*) FROM billing.provider_trunks WHERE enabled=true AND sandbox_only=true;")"
if [ "$SANDBOX_ENABLED" = "0" ]; then
  ok "aucun trunk sandbox activé"
else
  fail "trunk sandbox activé: ${SANDBOX_ENABLED}"
fi

REAL_ENABLED="$(psql_scalar "SELECT count(*) FROM billing.provider_trunks WHERE enabled=true AND sandbox_only=false;")"
if [ "$REAL_ENABLED" = "0" ]; then
  ok "aucun trunk réel activé"
else
  warn "trunk réel activé détecté: ${REAL_ENABLED}"
fi

ACTIVE_XML="storage/telephony/freeswitch/conf/sip_profiles/external/knvox-provider-gateways.generated.xml"
DISABLED_XML="storage/telephony/freeswitch/conf/sip_profiles/external/knvox-provider-gateways.generated.xml.disabled"

if [ -f "$ACTIVE_XML" ]; then
  fail "fichier trunk FreeSWITCH actif présent: $ACTIVE_XML"
else
  ok "aucun fichier trunk FreeSWITCH actif .xml"
fi

if [ -f "$DISABLED_XML" ]; then
  ok "fichier trunk sandbox .disabled présent"
else
  warn "fichier .disabled absent, relancer make provider-trunk-generate"
fi

BLOCKED="$(psql_scalar "SELECT count(*) FROM billing.blocked_prefixes;")"
if [ "$BLOCKED" -ge 1 ]; then
  ok "préfixes bloqués présents: ${BLOCKED}"
else
  fail "aucun préfixe bloqué"
fi

BAD_MARGIN="$(psql_scalar "SELECT count(*) FROM billing.routing_decisions WHERE margin_per_min < 0 AND created_at > now() - interval '7 days';")"
if [ "$BAD_MARGIN" = "0" ]; then
  ok "aucune marge négative récente dans routing_decisions"
else
  fail "marges négatives récentes détectées: ${BAD_MARGIN}"
fi

REQUIRE_BALANCE="$(psql_scalar "SELECT COALESCE((SELECT value FROM billing.system_settings WHERE key='require_balance'), 'true');")"
if [ "$REQUIRE_BALANCE" = "true" ]; then
  ok "require_balance=true"
else
  warn "require_balance=${REQUIRE_BALANCE}"
fi

echo ""
echo "Rapport: $REPORT"
echo "Warnings: $WARN"
echo "Failures: $FAIL"

STATUS="pstn_safety_passed"
if [ "$FAIL" -gt 0 ]; then
  STATUS="pstn_safety_failed"
fi

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -v event="$STATUS" \
  -v failed="$FAIL" \
  -v warned="$WARN" <<'SQL'
INSERT INTO billing.pstn_safety_events(event_type, details)
VALUES (
  :'event',
  jsonb_build_object(
    'failed', :'failed'::INTEGER,
    'warnings', :'warned'::INTEGER
  )
);
SQL

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "AUDIT FAILED - PSTN activation interdite."
  exit 1
fi

echo ""
echo "AUDIT PASSED - PSTN toujours désactivé."
