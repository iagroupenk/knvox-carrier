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

SECRET_XML="secrets/provider-trunks/generated/knvox-provider-gateways.vault.generated.xml.disabled"
ACTIVE_XML="storage/telephony/freeswitch/conf/sip_profiles/external/knvox-provider-gateways.vault.generated.xml"

echo "===================================="
echo " KNVOX PROVIDER GATEWAY VAULT AUDIT"
echo "===================================="

[ -f "$SECRET_XML" ] && ok "gateway vault .disabled présent dans secrets/" || fail "gateway vault absent"
git check-ignore -q "$SECRET_XML" && ok "gateway vault ignoré par Git" || fail "gateway vault non ignoré par Git"

[ ! -f "$ACTIVE_XML" ] && ok "aucun gateway vault actif dans FreeSWITCH" || fail "gateway vault actif détecté"

CLEAR_DB="$(psql_scalar "SELECT count(*) FROM billing.provider_trunks WHERE auth_password IS NOT NULL AND auth_password <> '';")"
[ "$CLEAR_DB" = "0" ] && ok "aucun password provider en clair DB" || fail "password provider en clair DB: $CLEAR_DB"

PSTN="$(psql_scalar "SELECT COALESCE((SELECT value FROM billing.system_settings WHERE key='pstn_enabled'), 'false');")"
[ "$PSTN" = "false" ] && ok "pstn_enabled=false" || fail "pstn_enabled=$PSTN"

CRED_REFS="$(psql_scalar "SELECT count(*) FROM billing.provider_trunks WHERE credential_ref IS NOT NULL AND credential_ref <> '';")"
[ "$CRED_REFS" -ge 1 ] && ok "credential_ref provider présent: $CRED_REFS" || fail "aucun credential_ref provider"

echo "Failures: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1

echo "AUDIT PASSED"
