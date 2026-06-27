#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX SIP REGISTRATION STATUS"
echo "===================================="

echo ""
echo "[1/4] FreeSWITCH status"
./scripts/fs_cli.sh -x "status" || true

echo ""
echo "[2/4] Profile internal"
./scripts/fs_cli.sh -x "sofia status profile internal" || true

echo ""
echo "[3/4] Registrations internal"
./scripts/fs_cli.sh -x "sofia status profile internal reg" || true

echo ""
echo "[4/4] Comptes SIP DB actifs"

set -a
source .env
set +a

./scripts/compose.sh exec -T postgres psql \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" <<'SQL'
SELECT
  username,
  customer_code,
  display_name,
  enabled,
  cps_limit,
  max_concurrent_calls,
  updated_at
FROM billing.sip_accounts
WHERE enabled = true
ORDER BY username;
SQL
