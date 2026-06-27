#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

USERNAME="${1:-1001}"
EXPORT_DIR="exports/sip"
mkdir -p "${EXPORT_DIR}"

ROW="$(
./scripts/compose.sh exec -T postgres psql \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  -v username="$USERNAME" \
  -AtF $'\t' <<'SQL'
SELECT
  username,
  customer_code,
  COALESCE(display_name, username),
  auth_password,
  COALESCE(realm, 'knvox.local'),
  enabled,
  cps_limit,
  max_concurrent_calls,
  COALESCE(allowed_ip_cidr, '')
FROM billing.sip_accounts
WHERE username = :'username'
LIMIT 1;
SQL
)"

if [ -z "$ROW" ]; then
  echo "ERROR: compte SIP introuvable : ${USERNAME}"
  exit 1
fi

IFS=$'\t' read -r USER CUSTOMER DISPLAY PASSWORD REALM ENABLED CPS CONCURRENT ALLOWED_IP <<< "$ROW"

OUT="${EXPORT_DIR}/softphone_${USER}_$(date +%Y%m%d-%H%M%S).txt"

cat > "$OUT" <<CARD
====================================
 KNVOX SIP PROVISIONING CARD
====================================

Customer code : ${CUSTOMER}
Display name  : ${DISPLAY}

SIP server    : ${SIP_PUBLIC_HOST}
SIP port      : ${SIP_PUBLIC_PORT}
Transport     : ${SIP_TRANSPORT}

Username      : ${USER}
Password      : ${PASSWORD}
Realm/domain  : ${REALM}

Enabled       : ${ENABLED}
CPS limit     : ${CPS}
Concurrent    : ${CONCURRENT}
Allowed IP    : ${ALLOWED_IP}

Test number   : 9996

Important:
- Utiliser UDP 5060.
- Appel test uniquement vers 9996.
- PSTN désactivé.
CARD

chmod 600 "$OUT"

cat "$OUT"

echo ""
echo "Fiche générée : $OUT"
