#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
set -a
source .env
set +a

PROVIDER="${1:-SIM-FR-1}"
AUTH_USERNAME="${AUTH_USERNAME:-sandbox-user}"
AUTH_PASSWORD="${AUTH_PASSWORD:-$(openssl rand -hex 16)}"
FROM_DOMAIN="${FROM_DOMAIN:-sandbox.invalid}"

SAFE_PROVIDER="$(echo "$PROVIDER" | tr -cd 'A-Za-z0-9_.-')"
CRED_REF="provider-trunks/${SAFE_PROVIDER}.json.enc"
OUT="secrets/${CRED_REF}"
TMP="$(mktemp)"

mkdir -p secrets/provider-trunks
chmod 700 secrets secrets/provider-trunks

jq -n \
  --arg provider_code "$PROVIDER" \
  --arg auth_username "$AUTH_USERNAME" \
  --arg auth_password "$AUTH_PASSWORD" \
  --arg from_domain "$FROM_DOMAIN" \
  --arg created_at "$(date -Is)" \
  '{provider_code:$provider_code, auth_username:$auth_username, auth_password:$auth_password, from_domain:$from_domain, created_at:$created_at}' > "$TMP"

openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 \
  -pass env:VAULT_MASTER_KEY \
  -in "$TMP" \
  -out "$OUT"

chmod 600 "$OUT"
rm -f "$TMP"

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -v provider="$PROVIDER" \
  -v credref="$CRED_REF" \
  -v username="$AUTH_USERNAME" \
  -v domain="$FROM_DOMAIN" <<'SQL'
SELECT *
FROM billing.set_provider_trunk_credential_ref(:'provider', :'credref', :'username', :'domain');
SQL

echo "Credential chiffré : $OUT"
echo "Password provider non stocké en clair dans PostgreSQL."
