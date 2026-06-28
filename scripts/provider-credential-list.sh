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
