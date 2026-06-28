#!/bin/bash
set -euo pipefail

cd /opt/knvox-carrier

echo "=== KNVOX V1.6.3 Provider Gateway Builder From Vault ==="

set -a
source .env
set +a

mkdir -p scripts docs secrets/provider-trunks/generated exports/trunks

touch .gitignore
grep -qxF "/secrets/" .gitignore || echo "/secrets/" >> .gitignore
grep -qxF "/exports/" .gitignore || echo "/exports/" >> .gitignore

chmod 700 secrets secrets/provider-trunks secrets/provider-trunks/generated

cat > scripts/provider-gateway-vault-build.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

OUT="secrets/provider-trunks/generated/knvox-provider-gateways.vault.generated.xml.disabled"
MASKED="exports/trunks/provider_gateway_vault_masked_$(date +%Y%m%d-%H%M%S).txt"
TMP="$(mktemp)"

mkdir -p secrets/provider-trunks/generated exports/trunks

xml_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g'
}

./scripts/compose.sh exec -T postgres psql \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  -AtF $'\t' \
  -c "
SELECT
  provider_code,
  trunk_name,
  sip_host,
  sip_port,
  transport,
  COALESCE(auth_username, ''),
  COALESCE(from_domain, sip_host),
  COALESCE(credential_ref, ''),
  enabled,
  sandbox_only
FROM billing.provider_trunks
ORDER BY provider_code;
" > "$TMP"

{
  echo "<include>"
  echo "  <!-- KNVOX generated from encrypted vault. -->"
  echo "  <!-- SECURITY: stored under secrets/, ignored by Git. -->"
  echo "  <!-- File intentionally .disabled : FreeSWITCH does NOT load it. -->"

  while IFS=$'\t' read -r PROVIDER NAME HOST PORT TRANSPORT DB_USER DB_DOMAIN CRED_REF ENABLED SANDBOX; do
    [ -z "$PROVIDER" ] && continue

    USERNAME="$DB_USER"
    PASSWORD=""
    DOMAIN="$DB_DOMAIN"

    if [ -n "$CRED_REF" ] && [ -f "secrets/${CRED_REF}" ]; then
      if JSON="$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:VAULT_MASTER_KEY -in "secrets/${CRED_REF}" 2>/dev/null)"; then
        USERNAME="$(echo "$JSON" | jq -r '.auth_username // empty')"
        PASSWORD="$(echo "$JSON" | jq -r '.auth_password // empty')"
        DOMAIN="$(echo "$JSON" | jq -r '.from_domain // empty')"
        DOMAIN="${DOMAIN:-$DB_DOMAIN}"
      fi
    fi

    P="$(xml_escape "$PROVIDER")"
    H="$(xml_escape "$HOST")"
    D="$(xml_escape "$DOMAIN")"
    U="$(xml_escape "$USERNAME")"
    PW="$(xml_escape "$PASSWORD")"
    TR="$(xml_escape "$TRANSPORT")"

    echo "  <gateway name=\"$P\">"
    echo "    <param name=\"proxy\" value=\"$H:$PORT\"/>"
    echo "    <param name=\"realm\" value=\"$D\"/>"

    if [ -n "$U" ]; then
      echo "    <param name=\"username\" value=\"$U\"/>"
    fi

    if [ -n "$PW" ]; then
      echo "    <param name=\"password\" value=\"$PW\"/>"
    else
      echo "    <!-- WARNING: no decrypted password available -->"
    fi

    echo "    <param name=\"register\" value=\"false\"/>"
    echo "    <param name=\"extension\" value=\"$P\"/>"
    echo "    <param name=\"context\" value=\"public\"/>"
    echo "    <param name=\"caller-id-in-from\" value=\"true\"/>"
    echo "    <!-- transport=$TR enabled=$ENABLED sandbox_only=$SANDBOX credential_ref=$CRED_REF -->"
    echo "  </gateway>"
  done < "$TMP"

  echo "</include>"
} > "$OUT"

chmod 600 "$OUT"
rm -f "$TMP"

{
  echo "KNVOX Provider Gateway Vault Build"
  echo "Generated: $(date -Is)"
  echo "Secret XML: $OUT"
  echo ""
  echo "Provider credentials status:"
  ./scripts/provider-credential-list.sh
} > "$MASKED"

chmod 600 "$MASKED"

echo "Gateway vault généré : $OUT"
echo "Rapport masqué       : $MASKED"
echo ""
echo "IMPORTANT : fichier dans secrets/ et .disabled. Aucun trunk réel chargé."
SCRIPT

cat > scripts/provider-gateway-vault-audit.sh <<'SCRIPT'
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
SCRIPT

cat > scripts/provider-gateway-vault-test.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX PROVIDER GATEWAY VAULT TEST"
echo "===================================="

if [ ! -f secrets/provider-trunks/SIM-FR-1.json.enc ]; then
  AUTH_USERNAME="sandbox-user" \
  AUTH_PASSWORD="$(openssl rand -hex 16)" \
  FROM_DOMAIN="sandbox.invalid" \
  ./scripts/provider-credential-set.sh SIM-FR-1
fi

./scripts/provider-gateway-vault-build.sh
./scripts/provider-gateway-vault-audit.sh
make pstn-safety-audit
make health

echo "Test V1.6.3 terminé. Aucun trunk réel connecté."
SCRIPT

chmod +x scripts/provider-gateway-vault-*.sh

cat > docs/PROVIDER_GATEWAY_BUILDER_FROM_VAULT.md <<'DOC'
# KNVOX V1.6.3 - Provider Gateway Builder From Vault

Objectif : générer une configuration gateway FreeSWITCH depuis les credentials chiffrés.

Règles :

- Le fichier généré reste dans `secrets/`
- Le fichier reste en `.disabled`
- FreeSWITCH ne charge rien
- Aucun password provider en clair dans PostgreSQL
- Rien de secret dans GitHub
- PSTN toujours désactivé

Commandes :

make provider-gateway-vault-test
make provider-gateway-vault-build
make provider-gateway-vault-audit
DOC

python3 - <<'PY'
from pathlib import Path

p = Path("Makefile")
s = p.read_text()

targets = [
    "provider-gateway-vault-test",
    "provider-gateway-vault-build",
    "provider-gateway-vault-audit",
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
provider-gateway-vault-test:
>./scripts/provider-gateway-vault-test.sh

provider-gateway-vault-build:
>./scripts/provider-gateway-vault-build.sh

provider-gateway-vault-audit:
>./scripts/provider-gateway-vault-audit.sh
"""

if "provider-gateway-vault-test:" not in s:
    s = s.rstrip() + "\n\n" + block

p.write_text(s)
PY

./scripts/compose.sh config >/dev/null

echo "V1.6.3 installée."
