#!/bin/bash
set -euo pipefail

echo "================================================"
echo " KNVOX Carrier Platform - V1.6.1 PSTN Safety"
echo "================================================"

cd /opt/knvox-carrier

set -a
source .env
set +a

mkdir -p scripts docs exports/audits database/schemas

if ! grep -q "^/exports/" .gitignore 2>/dev/null; then
  echo "" >> .gitignore
  echo "/exports/" >> .gitignore
fi

echo "[1/5] SQL events PSTN safety"

cat > database/schemas/pstn_safety_v1.sql <<'SQL'
CREATE SCHEMA IF NOT EXISTS billing;

CREATE TABLE IF NOT EXISTS billing.pstn_safety_events (
    id BIGSERIAL PRIMARY KEY,
    event_type TEXT NOT NULL,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO billing.system_settings(key, value)
VALUES ('pstn_enabled', 'false')
ON CONFLICT (key) DO UPDATE SET value = 'false';

INSERT INTO billing.pstn_safety_events(event_type, details)
VALUES ('pstn_safety_installed', jsonb_build_object('pstn_enabled', false));
SQL

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < database/schemas/pstn_safety_v1.sql

echo "[2/5] Scripts PSTN"

cat > scripts/pstn-force-off.sh <<'SCRIPT'
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
SCRIPT

cat > scripts/pstn-status.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX PSTN STATUS"
echo "===================================="

echo ""
echo "[1/4] Settings"
./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
SELECT key, value
FROM billing.system_settings
WHERE key IN ('pstn_enabled', 'require_balance', 'min_call_balance')
ORDER BY key;
SQL

echo ""
echo "[2/4] Provider trunks"
./scripts/provider-trunk-list.sh || true

echo ""
echo "[3/4] Active calls"
./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
SELECT count(*) AS active_calls
FROM billing.active_calls;
SQL

echo ""
echo "[4/4] Dernières décisions routing"
./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
SELECT
  created_at,
  customer_code,
  src,
  dst,
  selected_provider_code,
  route_allowed,
  route_reason,
  pstn_enabled
FROM billing.routing_decisions
ORDER BY created_at DESC
LIMIT 10;
SQL
SCRIPT

cat > scripts/pstn-safety-audit.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

mkdir -p exports/audits

REPORT="exports/audits/pstn_safety_$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee "$REPORT") 2>&1

FAIL=0
WARN=0

psql_scalar() {
  ./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "$1" | tr -d '[:space:]'
}

ok() {
  echo "OK   - $1"
}

warn() {
  WARN=$((WARN+1))
  echo "WARN - $1"
}

fail() {
  FAIL=$((FAIL+1))
  echo "FAIL - $1"
}

echo "===================================="
echo " KNVOX PSTN SAFETY AUDIT"
echo "===================================="
echo ""

PSTN="$(psql_scalar "SELECT COALESCE((SELECT value FROM billing.system_settings WHERE key='pstn_enabled'), 'false');")"
if [ "$PSTN" = "false" ]; then
  ok "pstn_enabled=false"
else
  fail "pstn_enabled=${PSTN}"
fi

ACTIVE_CALLS="$(psql_scalar "SELECT count(*) FROM billing.active_calls;")"
if [ "$ACTIVE_CALLS" = "0" ]; then
  ok "aucun appel actif"
else
  fail "active_calls=${ACTIVE_CALLS}"
fi

TRUNKS="$(psql_scalar "SELECT count(*) FROM billing.provider_trunks;")"
if [ "$TRUNKS" -ge 1 ]; then
  ok "provider_trunks présents: ${TRUNKS}"
else
  fail "aucun provider_trunk"
fi

SANDBOX_ENABLED="$(psql_scalar "SELECT count(*) FROM billing.provider_trunks WHERE enabled=true AND sandbox_only=true;")"
if [ "$SANDBOX_ENABLED" = "0" ]; then
  ok "aucun trunk sandbox activé"
else
  fail "trunk sandbox activé: ${SANDBOX_ENABLED}"
fi

REAL_ENABLED="$(psql_scalar "SELECT count(*) FROM billing.provider_trunks WHERE enabled=true AND sandbox_only=false;")"
if [ "$REAL_ENABLED" = "0" ]; then
  ok "aucun trunk réel activé"
else
  warn "trunk réel activé détecté: ${REAL_ENABLED}"
fi

ACTIVE_XML="storage/telephony/freeswitch/conf/sip_profiles/external/knvox-provider-gateways.generated.xml"
DISABLED_XML="storage/telephony/freeswitch/conf/sip_profiles/external/knvox-provider-gateways.generated.xml.disabled"

if [ -f "$ACTIVE_XML" ]; then
  fail "fichier trunk FreeSWITCH actif présent: $ACTIVE_XML"
else
  ok "aucun fichier trunk FreeSWITCH actif .xml"
fi

if [ -f "$DISABLED_XML" ]; then
  ok "fichier trunk sandbox .disabled présent"
else
  warn "fichier .disabled absent, relancer make provider-trunk-generate"
fi

BLOCKED="$(psql_scalar "SELECT count(*) FROM billing.blocked_prefixes;")"
if [ "$BLOCKED" -ge 1 ]; then
  ok "préfixes bloqués présents: ${BLOCKED}"
else
  fail "aucun préfixe bloqué"
fi

BAD_MARGIN="$(psql_scalar "SELECT count(*) FROM billing.routing_decisions WHERE margin_per_min < 0 AND created_at > now() - interval '7 days';")"
if [ "$BAD_MARGIN" = "0" ]; then
  ok "aucune marge négative récente dans routing_decisions"
else
  fail "marges négatives récentes détectées: ${BAD_MARGIN}"
fi

REQUIRE_BALANCE="$(psql_scalar "SELECT COALESCE((SELECT value FROM billing.system_settings WHERE key='require_balance'), 'true');")"
if [ "$REQUIRE_BALANCE" = "true" ]; then
  ok "require_balance=true"
else
  warn "require_balance=${REQUIRE_BALANCE}"
fi

echo ""
echo "Rapport: $REPORT"
echo "Warnings: $WARN"
echo "Failures: $FAIL"

STATUS="pstn_safety_passed"
if [ "$FAIL" -gt 0 ]; then
  STATUS="pstn_safety_failed"
fi

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -v event="$STATUS" \
  -v failed="$FAIL" \
  -v warned="$WARN" <<'SQL'
INSERT INTO billing.pstn_safety_events(event_type, details)
VALUES (
  :'event',
  jsonb_build_object(
    'failed', :'failed'::INTEGER,
    'warnings', :'warned'::INTEGER
  )
);
SQL

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "AUDIT FAILED - PSTN activation interdite."
  exit 1
fi

echo ""
echo "AUDIT PASSED - PSTN toujours désactivé."
SCRIPT

cat > scripts/pstn-enable-request.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX PSTN ENABLE REQUEST"
echo "===================================="
echo ""
echo "REFUS: V1.6.1 ne permet pas d'activer le PSTN réel."
echo "Raison: activation trunk réel réservée à une version dédiée avec validation complète."
echo ""

./scripts/pstn-safety-audit.sh || true

echo ""
echo "pstn_enabled reste OFF."
exit 1
SCRIPT

chmod +x scripts/pstn-*.sh

echo "[3/5] Documentation"

cat > docs/PSTN_ACTIVATION_SAFETY_CHECKLIST.md <<'DOC'
# KNVOX V1.6.1 - PSTN Activation Safety Checklist

Objectif : empêcher toute activation PSTN accidentelle.

Commandes :

make pstn-force-off
make pstn-safety-audit
make pstn-status
make pstn-enable-request

Règles :

- pstn_enabled doit rester false
- aucun trunk réel actif
- aucun fichier FreeSWITCH gateway .xml actif
- seuls les fichiers .disabled sont autorisés
- aucun appel actif avant audit
- préfixes bloqués obligatoires
- marge négative interdite

Cette version ne connecte aucun trunk réel.
DOC

echo "[4/5] Makefile"

python3 - <<'PY'
from pathlib import Path

p = Path("Makefile")
s = p.read_text()

targets = [
    "pstn-force-off",
    "pstn-status",
    "pstn-safety-audit",
    "pstn-enable-request",
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
pstn-force-off:
>./scripts/pstn-force-off.sh

pstn-status:
>./scripts/pstn-status.sh

pstn-safety-audit:
>./scripts/pstn-safety-audit.sh

pstn-enable-request:
>./scripts/pstn-enable-request.sh
"""

if "pstn-safety-audit:" not in s:
    s = s.rstrip() + "\n\n" + block

p.write_text(s)
PY

echo "[5/5] Validation compose"
./scripts/compose.sh config >/dev/null

echo ""
echo "V1.6.1 PSTN Safety installée."
echo ""
echo "Prochaines commandes :"
echo "make pstn-force-off"
echo "make pstn-safety-audit"
echo "make pstn-status"
echo "make health"
