#!/bin/bash
set -euo pipefail

cd /opt/knvox-carrier

echo "=== KNVOX V1.5.3 SIP AUTH HARDENING SHORT ==="

set -a
source .env
set +a

mkdir -p scripts docs logs/kamailio-auth database/schemas

if ! grep -q "^SIP_REALM=" .env; then
  echo "SIP_REALM=knvox.enaes.net" >> .env
fi

chmod 600 .env

set -a
source .env
set +a

echo "[1/5] SQL allowlist IP"

cat > database/schemas/sip_auth_hardening_v1.sql <<'SQL'
CREATE OR REPLACE FUNCTION billing.set_sip_allowed_ip(
    p_username TEXT,
    p_allowed_ip_cidr TEXT
)
RETURNS TABLE (
    username TEXT,
    customer_code TEXT,
    enabled BOOLEAN,
    allowed_ip_cidr TEXT,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_allowed_ip_cidr IS NOT NULL AND trim(p_allowed_ip_cidr) <> '' THEN
        PERFORM p_allowed_ip_cidr::cidr;
    END IF;

    UPDATE billing.sip_accounts sa
    SET allowed_ip_cidr = NULLIF(trim(p_allowed_ip_cidr), ''),
        updated_at = now()
    WHERE sa.username = p_username;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SIP account not found: %', p_username;
    END IF;

    RETURN QUERY
    SELECT sa.username, sa.customer_code, sa.enabled, sa.allowed_ip_cidr, sa.updated_at
    FROM billing.sip_accounts sa
    WHERE sa.username = p_username;
END;
$$;

CREATE OR REPLACE FUNCTION billing.clear_sip_allowed_ip(
    p_username TEXT
)
RETURNS TABLE (
    username TEXT,
    customer_code TEXT,
    enabled BOOLEAN,
    allowed_ip_cidr TEXT,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM billing.set_sip_allowed_ip(p_username, NULL);
END;
$$;
SQL

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < database/schemas/sip_auth_hardening_v1.sql

echo "[2/5] Realm DB"

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v realm="$SIP_REALM" <<'SQL'
UPDATE billing.sip_accounts
SET realm = :'realm',
    updated_at = now()
WHERE realm IS NULL
   OR realm = ''
   OR realm = 'knvox.local';

SELECT username, customer_code, realm, enabled, allowed_ip_cidr
FROM billing.sip_accounts
ORDER BY username;
SQL

echo "[3/5] Register guard script"

cat > scripts/kamailio-register-guard.sh <<'SCRIPT'
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
SCRIPT

chmod +x scripts/kamailio-register-guard.sh

echo "[4/5] Patch Kamailio + compose"

python3 - <<'PY'
from pathlib import Path

cfg = Path("storage/telephony/kamailio/kamailio.cfg")
s = cfg.read_text()

if "knvox-register-guard.sh" not in s:
    needle = 'if (is_method("REGISTER")) {'
    idx = s.find(needle)
    if idx == -1:
        raise SystemExit("ERREUR: bloc REGISTER introuvable")

    insert_at = idx + len(needle)
    guard = '''
        if (!exec_msg("/usr/local/bin/knvox-register-guard.sh '$fU' '$si'")) {
            xlog("L_WARN", "KNVOX REGISTER blocked user=$fU from $si ua=$ua\\\\n");
            sl_send_reply("403", "SIP Registration Denied");
            exit;
        }
        xlog("L_INFO", "KNVOX REGISTER allowed user=$fU from $si\\\\n");
'''
    s = s[:insert_at] + guard + s[insert_at:]
    cfg.write_text(s)
    print("REGISTER guard ajouté.")
else:
    print("REGISTER guard déjà présent.")

compose = Path("compose/telephony/docker-compose.yml")
t = compose.read_text()

mount = "./scripts/kamailio-register-guard.sh:/usr/local/bin/knvox-register-guard.sh:ro"

if mount not in t:
    lines = t.splitlines()
    out = []
    inserted = False
    for line in lines:
        out.append(line)
        if "kamailio-authorize-call.sh:/usr/local/bin/knvox-authorize-call.sh:ro" in line and not inserted:
            out.append("      - " + mount)
            inserted = True
    if not inserted:
        raise SystemExit("ERREUR: mount authorize-call introuvable")
    t = "\n".join(out) + "\n"

if "KNVOX_REGISTER_LOG:" not in t:
    t = t.replace(
        "KNVOX_AUTH_LOG: /var/log/knvox/auth.log",
        "KNVOX_AUTH_LOG: /var/log/knvox/auth.log\n      KNVOX_REGISTER_LOG: /var/log/knvox/register-guard.log"
    )

compose.write_text(t)
PY

echo "[5/5] Scripts test"

cat > scripts/sip-auth-hardening-test.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== TEST SIP AUTH HARDENING ==="

echo "[1] 1002 doit être autorisé"
./scripts/kamailio-register-guard.sh 1002 196.118.37.197
echo "OK 1002 autorisé"

echo "[2] 9999 doit être bloqué"
if ./scripts/kamailio-register-guard.sh 9999 196.118.37.197; then
  echo "ERREUR: 9999 autorisé"
  exit 1
else
  echo "OK 9999 bloqué"
fi

echo "[3] allowlist IP 1002"
set -a
source .env
set +a

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v username="1002" -v cidr="196.118.37.197/32" <<'SQL'
SELECT * FROM billing.set_sip_allowed_ip(:'username', :'cidr');
SQL

./scripts/kamailio-register-guard.sh 1002 196.118.37.197
echo "OK IP autorisée"

if ./scripts/kamailio-register-guard.sh 1002 8.8.8.8; then
  echo "ERREUR: IP non autorisée acceptée"
  exit 1
else
  echo "OK IP non autorisée bloquée"
fi

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v username="1002" <<'SQL'
SELECT * FROM billing.clear_sip_allowed_ip(:'username');
SQL

make fs-sip-sync
make health

echo "TEST OK"
SCRIPT

chmod +x scripts/sip-auth-hardening-test.sh

cat > scripts/sip-register-guard-tail.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs/kamailio-auth
touch logs/kamailio-auth/register-guard.log
tail -F logs/kamailio-auth/register-guard.log
SCRIPT

chmod +x scripts/sip-register-guard-tail.sh

./scripts/compose.sh config >/dev/null
./scripts/compose.sh exec -T kamailio kamailio -c -f /etc/kamailio/kamailio.cfg

echo "V1.5.3 short installée."
