#!/bin/bash
set -euo pipefail

cd /opt/knvox-carrier

echo "=== KNVOX V1.6.2 Provider Credentials Vault MINI ==="

set -a
source .env
set +a

mkdir -p scripts docs secrets/provider-trunks exports/trunks database/schemas

touch .gitignore
grep -qxF "/secrets/" .gitignore || echo "/secrets/" >> .gitignore
grep -qxF "/exports/" .gitignore || echo "/exports/" >> .gitignore

chmod 700 secrets secrets/provider-trunks

if ! grep -q "^VAULT_MASTER_KEY=" .env; then
  echo "VAULT_MASTER_KEY=$(openssl rand -hex 32)" >> .env
fi

chmod 600 .env

set -a
source .env
set +a

echo "[1/4] SQL vault"

cat > database/schemas/provider_credentials_vault_v1.sql <<'SQL'
ALTER TABLE billing.provider_trunks
ADD COLUMN IF NOT EXISTS credential_ref TEXT;

ALTER TABLE billing.provider_trunks
ADD COLUMN IF NOT EXISTS credentials_updated_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS billing.provider_credential_events (
    id BIGSERIAL PRIMARY KEY,
    provider_code TEXT,
    event_type TEXT NOT NULL,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION billing.set_provider_trunk_credential_ref(
    p_provider_code TEXT,
    p_credential_ref TEXT,
    p_auth_username TEXT DEFAULT NULL,
    p_from_domain TEXT DEFAULT NULL
)
RETURNS TABLE (
    provider_code TEXT,
    trunk_name TEXT,
    credential_ref TEXT,
    auth_username TEXT,
    from_domain TEXT,
    credentials_updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE billing.provider_trunks pt
    SET
        credential_ref = p_credential_ref,
        auth_username = NULLIF(p_auth_username, ''),
        auth_password = NULL,
        from_domain = COALESCE(NULLIF(p_from_domain, ''), pt.from_domain),
        credentials_updated_at = now(),
        updated_at = now()
    WHERE pt.provider_code = p_provider_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Provider trunk not found: %', p_provider_code;
    END IF;

    INSERT INTO billing.provider_credential_events(provider_code, event_type, details)
    VALUES (
        p_provider_code,
        'credential_ref_set',
        jsonb_build_object('credential_ref', p_credential_ref)
    );

    RETURN QUERY
    SELECT
        pt.provider_code,
        pt.trunk_name,
        pt.credential_ref,
        pt.auth_username,
        pt.from_domain,
        pt.credentials_updated_at
    FROM billing.provider_trunks pt
    WHERE pt.provider_code = p_provider_code;
END;
$$;
SQL

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < database/schemas/provider_credentials_vault_v1.sql

echo "[2/4] Scripts vault"

cat > scripts/provider-credential-set.sh <<'SCRIPT'
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
SCRIPT

cat > scripts/provider-credential-show.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
set -a
source .env
set +a

PROVIDER="${1:-SIM-FR-1}"
MODE="${2:-masked}"

SAFE_PROVIDER="$(echo "$PROVIDER" | tr -cd 'A-Za-z0-9_.-')"
FILE="secrets/provider-trunks/${SAFE_PROVIDER}.json.enc"

if [ ! -f "$FILE" ]; then
  echo "ERROR: credential introuvable : $FILE"
  exit 1
fi

JSON="$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:VAULT_MASTER_KEY -in "$FILE")"

if [ "$MODE" = "--show-secret" ]; then
  echo "$JSON" | jq .
else
  echo "$JSON" | jq '.auth_password="********"'
fi
SCRIPT

cat > scripts/provider-credential-list.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
set -a
source .env
set +a

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
SELECT
  provider_code,
  trunk_name,
  enabled,
  sandbox_only,
  credential_ref,
  auth_username,
  CASE
    WHEN auth_password IS NULL OR auth_password = '' THEN 'OK_NULL'
    ELSE 'DANGER_CLEAR_TEXT'
  END AS auth_password_db_status,
  credentials_updated_at
FROM billing.provider_trunks
ORDER BY provider_code;
SQL

echo ""
echo "Encrypted files:"
find secrets/provider-trunks -maxdepth 1 -type f -name "*.enc" -printf "%p %k KB\n" 2>/dev/null || true
SCRIPT

cat > scripts/provider-vault-audit.sh <<'SCRIPT'
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
SCRIPT

cat > scripts/provider-vault-test.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX PROVIDER VAULT TEST"
echo "===================================="

AUTH_USERNAME="sandbox-user" \
AUTH_PASSWORD="$(openssl rand -hex 16)" \
FROM_DOMAIN="sandbox.invalid" \
./scripts/provider-credential-set.sh SIM-FR-1

./scripts/provider-credential-list.sh
./scripts/provider-credential-show.sh SIM-FR-1
./scripts/provider-vault-audit.sh
make pstn-safety-audit
make health

echo "Test V1.6.2 terminé. Aucun trunk réel connecté."
SCRIPT

chmod +x scripts/provider-credential-*.sh scripts/provider-vault-*.sh

echo "[3/4] Documentation courte"

cat > docs/PROVIDER_CREDENTIALS_VAULT.md <<'DOC'
# KNVOX V1.6.2 - Provider Credentials Vault

Stockage chiffré local des credentials provider.

Règles :
- pas de password provider en clair dans PostgreSQL
- secrets/ ignoré par Git
- exports/ ignoré par Git
- VAULT_MASTER_KEY dans .env
- PSTN toujours désactivé
- aucun trunk réel connecté
DOC

echo "[4/4] Makefile"

python3 - <<'PY'
from pathlib import Path

p = Path("Makefile")
s = p.read_text()

targets = [
    "provider-vault-test",
    "provider-vault-audit",
    "provider-credential-list",
    "provider-credential-show",
    "provider-credential-set",
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
provider-vault-test:
>./scripts/provider-vault-test.sh

provider-vault-audit:
>./scripts/provider-vault-audit.sh

provider-credential-list:
>./scripts/provider-credential-list.sh

provider-credential-show:
>./scripts/provider-credential-show.sh $${PROVIDER_CODE:-SIM-FR-1}

provider-credential-set:
>./scripts/provider-credential-set.sh $${PROVIDER_CODE:-SIM-FR-1}
"""

if "provider-vault-test:" not in s:
    s = s.rstrip() + "\n\n" + block

p.write_text(s)
PY

./scripts/compose.sh config >/dev/null

echo "V1.6.2 MINI installée."
