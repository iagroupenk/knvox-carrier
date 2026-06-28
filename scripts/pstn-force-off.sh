#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
INSERT INTO billing.system_settings(key, value)
VALUES ('pstn_enabled', 'false')
ON CONFLICT (key) DO UPDATE SET value = 'false';

INSERT INTO billing.pstn_safety_events(event_type, details)
VALUES ('pstn_force_off', jsonb_build_object('reason', 'manual_cli'));

SELECT key, value
FROM billing.system_settings
WHERE key = 'pstn_enabled';
SQL
