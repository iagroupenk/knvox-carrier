#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
set -a
source .env
set +a

FAIL=0
ok(){ echo "OK   - $1"; }
fail(){ FAIL=$((FAIL+1)); echo "FAIL - $1"; }

psql_scalar() {
  ./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "$1" | tr -d '[:space:]'
}

echo "===================================="
echo " KNVOX PROVIDER VAULT AUDIT"
echo "===================================="

[ -n "${VAULT_MASTER_KEY:-}" ] && ok "VAULT_MASTER_KEY présent" || fail "VAULT_MASTER_KEY absent"

if git check-ignore -q secrets/provider-trunks/test.enc; then
  ok "secrets/ ignoré par Git"
else
  fail "secrets/ non ignoré par Git"
fi

CLEAR_DB="$(psql_scalar "SELECT count(*) FROM billing.provider_trunks WHERE auth_password IS NOT NULL AND auth_password <> '';")"
[ "$CLEAR_DB" = "0" ] && ok "aucun password provider en clair DB" || fail "password provider en clair DB: $CLEAR_DB"

PSTN="$(psql_scalar "SELECT COALESCE((SELECT value FROM billing.system_settings WHERE key='pstn_enabled'), 'false');")"
[ "$PSTN" = "false" ] && ok "pstn_enabled=false" || fail "pstn_enabled=$PSTN"

ACTIVE_XML="storage/telephony/freeswitch/conf/sip_profiles/external/knvox-provider-gateways.generated.xml"
[ ! -f "$ACTIVE_XML" ] && ok "aucun gateway provider actif .xml" || fail "gateway .xml actif détecté"

ENC_COUNT="$(find secrets/provider-trunks -type f -name '*.enc' 2>/dev/null | wc -l | tr -d ' ')"
[ "$ENC_COUNT" -ge 1 ] && ok "credential chiffré présent: $ENC_COUNT" || fail "aucun credential chiffré"

echo "Failures: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "AUDIT PASSED"
