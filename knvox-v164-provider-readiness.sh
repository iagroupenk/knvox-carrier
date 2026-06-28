#!/bin/bash
set -euo pipefail

cd /opt/knvox-carrier

echo "=== KNVOX V1.6.4 Provider Readiness Audit ==="

set -a
source .env
set +a

mkdir -p scripts docs exports/audits

cat > scripts/provider-readiness-audit.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

PROVIDER="${1:-${PROVIDER_CODE:-SIM-FR-1}}"
DST="${2:-${DST:-33612345678}}"
CUSTOMER="${3:-${CUSTOMER_CODE:-TEST1000}}"
SRC="${4:-${SRC:-1000}}"

mkdir -p exports/audits

REPORT="exports/audits/provider_readiness_${PROVIDER}_$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee "$REPORT") 2>&1

FAIL=0
WARN=0

ok(){ echo "OK   - $1"; }
warn(){ WARN=$((WARN+1)); echo "WARN - $1"; }
fail(){ FAIL=$((FAIL+1)); echo "FAIL - $1"; }

psql_scalar() {
  ./scripts/compose.sh exec -T postgres psql \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    -Atc "$1" | tr -d '\r' | sed '/^[[:space:]]*$/d' | tail -n 1
}

echo "===================================="
echo " KNVOX PROVIDER READINESS AUDIT"
echo "===================================="
echo "Provider : $PROVIDER"
echo "Customer : $CUSTOMER"
echo "SRC      : $SRC"
echo "DST      : $DST"
echo ""

PSTN="$(psql_scalar "SELECT COALESCE((SELECT value FROM billing.system_settings WHERE key='pstn_enabled'), 'false');")"
[ "$PSTN" = "false" ] && ok "pstn_enabled=false" || fail "pstn_enabled=$PSTN"

ACTIVE_CALLS="$(psql_scalar "SELECT count(*) FROM billing.active_calls;")"
[ "$ACTIVE_CALLS" = "0" ] && ok "aucun appel actif" || fail "active_calls=$ACTIVE_CALLS"

PROVIDER_COUNT="$(psql_scalar "SELECT count(*) FROM billing.provider_trunks WHERE provider_code='${PROVIDER}';")"
[ "$PROVIDER_COUNT" = "1" ] && ok "provider_trunk existe: $PROVIDER" || fail "provider_trunk absent: $PROVIDER"

ENABLED="$(psql_scalar "SELECT COALESCE(enabled::text,'false') FROM billing.provider_trunks WHERE provider_code='${PROVIDER}' LIMIT 1;")"
[ "$ENABLED" = "false" ] && ok "provider enabled=false" || warn "provider enabled=$ENABLED"

SANDBOX="$(psql_scalar "SELECT COALESCE(sandbox_only::text,'true') FROM billing.provider_trunks WHERE provider_code='${PROVIDER}' LIMIT 1;")"
[ "$SANDBOX" = "true" ] && ok "provider sandbox_only=true" || warn "provider sandbox_only=$SANDBOX"

CLEAR_DB="$(psql_scalar "SELECT count(*) FROM billing.provider_trunks WHERE provider_code='${PROVIDER}' AND auth_password IS NOT NULL AND auth_password <> '';")"
[ "$CLEAR_DB" = "0" ] && ok "aucun password provider en clair DB" || fail "password provider en clair DB"

CRED_REF="$(psql_scalar "SELECT COALESCE(credential_ref,'') FROM billing.provider_trunks WHERE provider_code='${PROVIDER}' LIMIT 1;")"

if [ -n "$CRED_REF" ]; then
  ok "credential_ref présent: $CRED_REF"
else
  fail "credential_ref absent"
fi

if [ -n "$CRED_REF" ] && [ -f "secrets/${CRED_REF}" ]; then
  ok "fichier credential chiffré présent"
  TMP="$(mktemp)"
  if openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
      -pass env:VAULT_MASTER_KEY \
      -in "secrets/${CRED_REF}" > "$TMP" 2>/dev/null; then
    ok "credential vault déchiffrable"
  else
    fail "credential vault non déchiffrable"
  fi
  rm -f "$TMP"
else
  fail "fichier credential chiffré absent"
fi

SECRET_XML="secrets/provider-trunks/generated/knvox-provider-gateways.vault.generated.xml.disabled"
ACTIVE_XML="storage/telephony/freeswitch/conf/sip_profiles/external/knvox-provider-gateways.vault.generated.xml"

[ -f "$SECRET_XML" ] && ok "gateway vault .disabled présent dans secrets/" || warn "gateway vault .disabled absent"
[ ! -f "$ACTIVE_XML" ] && ok "aucun gateway vault actif FreeSWITCH" || fail "gateway vault actif détecté"

echo ""
echo "[Route dry-run]"
CALLID="readiness-${DST}-$(date +%s)"

ROUTE_LINE="$(
./scripts/compose.sh exec -T postgres psql \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  -AtF '|' \
  -v customer="$CUSTOMER" \
  -v src="$SRC" \
  -v dst="$DST" \
  -v callid="$CALLID" <<'SQL'
SELECT
  COALESCE(selected_provider_code,''),
  COALESCE(route_reason,''),
  COALESCE(margin_per_min::TEXT,''),
  COALESCE(pstn_enabled::TEXT,'')
FROM billing.provider_route_simulate(:'customer', :'src', :'dst', :'callid');
SQL
)"

echo "$ROUTE_LINE"

IFS='|' read -r ROUTE_PROVIDER ROUTE_REASON MARGIN ROUTE_PSTN <<< "$ROUTE_LINE"

[ "$ROUTE_PROVIDER" = "$PROVIDER" ] && ok "routing sélectionne $PROVIDER" || fail "routing provider=$ROUTE_PROVIDER attendu=$PROVIDER"
[ "$ROUTE_REASON" = "pstn_disabled_sandbox_route_found" ] && ok "route trouvée mais PSTN désactivé" || warn "route_reason=$ROUTE_REASON"
[ "$ROUTE_PSTN" = "f" ] && ok "dry-run confirme pstn_enabled=false" || fail "dry-run pstn_enabled=$ROUTE_PSTN"

if awk "BEGIN {exit !($MARGIN > 0)}"; then
  ok "marge par minute positive: $MARGIN"
else
  fail "marge non positive: $MARGIN"
fi

echo ""
echo "Rapport : $REPORT"
echo "Warnings: $WARN"
echo "Failures: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "AUDIT FAILED - provider non prêt."
  exit 1
fi

echo ""
echo "AUDIT PASSED - provider prêt en sandbox, PSTN toujours OFF."
SCRIPT

chmod +x scripts/provider-readiness-audit.sh

cat > scripts/provider-readiness-test.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX PROVIDER READINESS TEST"
echo "===================================="

if [ ! -f secrets/provider-trunks/SIM-FR-1.json.enc ]; then
  AUTH_USERNAME="sandbox-user" \
  AUTH_PASSWORD="$(openssl rand -hex 16)" \
  FROM_DOMAIN="sandbox.invalid" \
  ./scripts/provider-credential-set.sh SIM-FR-1
fi

make pstn-force-off
make provider-gateway-vault-build

./scripts/provider-readiness-audit.sh SIM-FR-1 33612345678 TEST1000 1000

make pstn-safety-audit
make health

echo ""
echo "Test V1.6.4 terminé. Aucun trunk réel connecté."
SCRIPT

chmod +x scripts/provider-readiness-test.sh

cat > docs/PROVIDER_READINESS_AUDIT.md <<'DOC'
# KNVOX V1.6.4 - Provider Readiness Audit

Objectif : vérifier qu'un provider sandbox est prêt techniquement avant toute future activation réelle.

Contrôles :

- PSTN OFF
- Aucun appel actif
- Provider trunk présent
- Credential vault présent et déchiffrable
- Aucun mot de passe provider en clair DB
- Aucun gateway actif FreeSWITCH
- Route sandbox trouvée
- Marge positive
- Gateway généré en .disabled

Commandes :

make provider-readiness-test
make provider-readiness-audit

Cette version ne connecte aucun trunk réel.
DOC

python3 - <<'PY'
from pathlib import Path

p = Path("Makefile")
s = p.read_text()

targets = [
    "provider-readiness-test",
    "provider-readiness-audit",
]

lines = s.splitlines()
for i, line in enumerate(lines):
    if line.startswith(".PHONY:"):
        for t in targets:
            if t not in line:
                line += " " + t
        lines[i] = line
        break

s = "\n".join(lines) + "\n"

block = """
provider-readiness-test:
>./scripts/provider-readiness-test.sh

provider-readiness-audit:
>./scripts/provider-readiness-audit.sh $${PROVIDER_CODE:-SIM-FR-1} $${DST:-33612345678} $${CUSTOMER_CODE:-TEST1000} $${SRC:-1000}
"""

if "provider-readiness-test:" not in s:
    s = s.rstrip() + "\n\n" + block

p.write_text(s)
PY

./scripts/compose.sh config >/dev/null

echo "V1.6.4 Provider Readiness Audit installée."
