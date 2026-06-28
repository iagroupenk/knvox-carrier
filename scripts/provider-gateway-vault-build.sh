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
