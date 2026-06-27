#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX FREESWITCH SIP PROVISIONING STATUS"
echo "===================================="
echo ""

echo "Comptes SIP DB actifs 1000-1019:"
./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
SELECT
  username,
  customer_code,
  display_name,
  realm,
  enabled,
  cps_limit,
  max_concurrent_calls,
  updated_at
FROM billing.sip_accounts
WHERE username ~ '^(100[0-9]|101[0-9])$'
ORDER BY username;
SQL

echo ""
echo "Fichier XML généré:"
ls -lh storage/telephony/freeswitch/conf/directory/default/knvox-db-sip-accounts.xml 2>/dev/null || true

echo ""
echo "Derniers exports SIP locaux:"
ls -lht exports/sip 2>/dev/null | head || true

echo ""
echo "FreeSWITCH status:"
if [ -x ./scripts/fs_cli.sh ]; then
  ./scripts/fs_cli.sh -x "status" || true
  ./scripts/fs_cli.sh -x "sofia status profile internal" || true
else
  ./scripts/compose.sh exec -T freeswitch fs_cli -x "status" || true
fi
