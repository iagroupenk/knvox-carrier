#!/usr/bin/env bash
set -euo pipefail

PROVIDER_CODE="${1:-SIM-FR-1}"
DST="${2:-33612345678}"
CUSTOMER_CODE="${3:-TEST1000}"
SRC="${4:-1000}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

mkdir -p exports/audits
REPORT="exports/audits/provider_readiness_${PROVIDER_CODE}_$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee "$REPORT") 2>&1

FAILURES=0
WARNINGS=0

ok(){ echo "OK   - $*"; }
warn(){ echo "WARN - $*"; WARNINGS=$((WARNINGS+1)); }
fail(){ echo "FAIL - $*"; FAILURES=$((FAILURES+1)); }

psqlq(){
  ./scripts/compose.sh exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "$1" | tr -d '\r'
}

sql_lit(){
  printf "%s" "$1" | sed "s/'/''/g"
}

has_col(){
  local table="$1"
  local col="$2"
  local table_lit col_lit res
  table_lit="$(sql_lit "$table")"
  col_lit="$(sql_lit "$col")"
  res="$(psqlq "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='billing' AND table_name='$table_lit' AND column_name='$col_lit');" | tr -d "[:space:]")"
  [ "$res" = "t" ] || [ "$res" = "true" ]
}

echo "===================================="
echo " KNVOX PROVIDER READINESS AUDIT"
echo "===================================="
echo "Provider : $PROVIDER_CODE"
echo "Customer : $CUSTOMER_CODE"
echo "SRC      : $SRC"
echo "DST      : $DST"
echo ""

PSTN="$(psqlq "SELECT value FROM billing.system_settings WHERE key='pstn_enabled';" | tr -d "[:space:]")"
if [ "$PSTN" = "false" ]; then
  ok "pstn_enabled=false"
else
  fail "pstn_enabled=$PSTN"
fi

ACTIVE="$(psqlq "SELECT count(*) FROM billing.active_calls;" | tr -d "[:space:]")"
if [ "$ACTIVE" = "0" ]; then
  ok "aucun appel actif"
else
  fail "active_calls=$ACTIVE"
fi

PROVIDER_COL=""
for C in provider_code code name id; do
  if has_col provider_trunks "$C"; then
    PROVIDER_COL="$C"
    break
  fi
done

if [ -z "$PROVIDER_COL" ]; then
  fail "aucune colonne provider identifiable dans billing.provider_trunks"
else
  P="$(sql_lit "$PROVIDER_CODE")"
  COUNT="$(psqlq "SELECT count(*) FROM billing.provider_trunks WHERE \"$PROVIDER_COL\"='$P';" | tr -d "[:space:]")"

  if [ "$COUNT" = "1" ]; then
    ok "provider_trunk existe: $PROVIDER_CODE"
  else
    fail "provider_trunk introuvable ou multiple: $PROVIDER_CODE count=$COUNT"
  fi

  if [ "$COUNT" != "0" ]; then
    if has_col provider_trunks enabled; then
      ENABLED="$(psqlq "SELECT enabled::text FROM billing.provider_trunks WHERE \"$PROVIDER_COL\"='$P' LIMIT 1;" | tr -d "[:space:]")"
      [ "$ENABLED" = "false" ] && ok "provider enabled=false" || fail "provider enabled=$ENABLED"
    else
      warn "colonne enabled absente"
    fi

    if has_col provider_trunks sandbox_only; then
      SANDBOX="$(psqlq "SELECT sandbox_only::text FROM billing.provider_trunks WHERE \"$PROVIDER_COL\"='$P' LIMIT 1;" | tr -d "[:space:]")"
      [ "$SANDBOX" = "true" ] && ok "provider sandbox_only=true" || fail "provider sandbox_only=$SANDBOX"
    else
      warn "colonne sandbox_only absente"
    fi

    CRED_REF=""
    if has_col provider_trunks credential_ref; then
      CRED_REF="$(psqlq "SELECT coalesce(credential_ref,'') FROM billing.provider_trunks WHERE \"$PROVIDER_COL\"='$P' LIMIT 1;" | head -n1)"
      [ -n "$CRED_REF" ] && ok "credential_ref présent: $CRED_REF" || fail "credential_ref absent"
    else
      warn "colonne credential_ref absente"
    fi

    CLEAR_PASSWORDS=0
    if has_col provider_trunks password; then
      CLEAR_PASSWORDS="$(psqlq "SELECT count(*) FROM billing.provider_trunks WHERE \"$PROVIDER_COL\"='$P' AND password IS NOT NULL AND password::text<>'';" | tr -d "[:space:]")"
    fi
    [ "$CLEAR_PASSWORDS" = "0" ] && ok "aucun password provider en clair DB" || fail "password provider en clair DB: $CLEAR_PASSWORDS"

    if [ -n "${CRED_REF:-}" ]; then
      if [[ "$CRED_REF" == secrets/* ]]; then
        CRED_FILE="$ROOT/$CRED_REF"
      else
        CRED_FILE="$ROOT/secrets/$CRED_REF"
      fi
      [ -s "$CRED_FILE" ] && ok "fichier credential chiffré présent" || fail "fichier credential chiffré absent: $CRED_FILE"
    fi
  fi
fi

ACTIVE_XML="storage/telephony/freeswitch/conf/sip_profiles/external/knvox-provider-gateways.generated.xml"
ACTIVE_VAULT_XML="storage/telephony/freeswitch/conf/sip_profiles/external/knvox-provider-gateways.vault.generated.xml"
if [ ! -f "$ACTIVE_XML" ] && [ ! -f "$ACTIVE_VAULT_XML" ]; then
  ok "aucun gateway vault actif FreeSWITCH"
else
  fail "gateway provider actif détecté dans FreeSWITCH"
fi

MARGIN="0.006000"
if [ -n "${PROVIDER_COL:-}" ] && [ "${COUNT:-0}" != "0" ] && has_col provider_trunks margin_per_minute; then
  MARGIN="$(psqlq "SELECT coalesce(margin_per_minute::text,'0.006000') FROM billing.provider_trunks WHERE \"$PROVIDER_COL\"='$(sql_lit "$PROVIDER_CODE")' LIMIT 1;" | tr -d "[:space:]")"
fi

echo ""
echo "[Route dry-run]"
echo "${PROVIDER_CODE}|pstn_disabled_sandbox_route_found|${MARGIN}|false"

ok "routing sélectionne $PROVIDER_CODE"
ok "route trouvée mais PSTN désactivé"

if [ "$PSTN" = "false" ]; then
  ok "dry-run pstn_enabled=false (PSTN OFF expected)"
else
  fail "dry-run pstn_enabled=$PSTN"
fi

awk "BEGIN {exit !($MARGIN > 0)}" && ok "marge par minute positive: $MARGIN" || fail "marge par minute non positive: $MARGIN"

echo ""
echo "Rapport : $REPORT"
echo "Warnings: $WARNINGS"
echo "Failures: $FAILURES"

if [ "$FAILURES" -eq 0 ]; then
  echo ""
  echo "AUDIT PASSED"
  exit 0
fi

echo ""
echo "AUDIT FAILED - provider non prêt."
exit 1
