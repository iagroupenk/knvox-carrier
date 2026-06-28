#!/bin/bash
set -euo pipefail

echo "================================================"
echo " KNVOX Carrier Platform - V1.6.0 Provider Trunk Sandbox"
echo "================================================"

cd /opt/knvox-carrier

set -a
source .env
set +a

mkdir -p database/schemas scripts docs exports/trunks storage/telephony/freeswitch/conf/sip_profiles/external

echo "[1/6] Git ignore exports trunks..."

if ! grep -q "^/exports/" .gitignore 2>/dev/null; then
  echo "" >> .gitignore
  echo "/exports/" >> .gitignore
fi

echo "[2/6] SQL provider trunks sandbox..."

cat > database/schemas/provider_trunk_sandbox_v1.sql <<'SQL'
CREATE SCHEMA IF NOT EXISTS billing;

CREATE TABLE IF NOT EXISTS billing.provider_trunks (
    provider_code TEXT PRIMARY KEY,
    trunk_name TEXT NOT NULL,
    sip_host TEXT NOT NULL,
    sip_port INTEGER NOT NULL DEFAULT 5060,
    transport TEXT NOT NULL DEFAULT 'udp',
    auth_username TEXT,
    auth_password TEXT,
    from_domain TEXT,
    register BOOLEAN NOT NULL DEFAULT false,
    enabled BOOLEAN NOT NULL DEFAULT false,
    sandbox_only BOOLEAN NOT NULL DEFAULT true,
    max_cps INTEGER NOT NULL DEFAULT 1,
    max_concurrent_calls INTEGER NOT NULL DEFAULT 2,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS billing.provider_trunk_events (
    id BIGSERIAL PRIMARY KEY,
    provider_code TEXT,
    event_type TEXT NOT NULL,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION billing.upsert_provider_trunk(
    p_provider_code TEXT,
    p_trunk_name TEXT,
    p_sip_host TEXT,
    p_sip_port INTEGER DEFAULT 5060,
    p_transport TEXT DEFAULT 'udp',
    p_auth_username TEXT DEFAULT NULL,
    p_auth_password TEXT DEFAULT NULL,
    p_from_domain TEXT DEFAULT NULL,
    p_register BOOLEAN DEFAULT false,
    p_enabled BOOLEAN DEFAULT false,
    p_sandbox_only BOOLEAN DEFAULT true,
    p_max_cps INTEGER DEFAULT 1,
    p_max_concurrent_calls INTEGER DEFAULT 2,
    p_notes TEXT DEFAULT NULL
)
RETURNS TABLE (
    provider_code TEXT,
    trunk_name TEXT,
    sip_host TEXT,
    sip_port INTEGER,
    transport TEXT,
    register BOOLEAN,
    enabled BOOLEAN,
    sandbox_only BOOLEAN,
    max_cps INTEGER,
    max_concurrent_calls INTEGER,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE billing.provider_trunks pt
    SET
        trunk_name = p_trunk_name,
        sip_host = p_sip_host,
        sip_port = p_sip_port,
        transport = lower(p_transport),
        auth_username = p_auth_username,
        auth_password = p_auth_password,
        from_domain = p_from_domain,
        register = p_register,
        enabled = p_enabled,
        sandbox_only = p_sandbox_only,
        max_cps = p_max_cps,
        max_concurrent_calls = p_max_concurrent_calls,
        notes = p_notes,
        updated_at = now()
    WHERE pt.provider_code = p_provider_code;

    IF NOT FOUND THEN
        INSERT INTO billing.provider_trunks(
            provider_code,
            trunk_name,
            sip_host,
            sip_port,
            transport,
            auth_username,
            auth_password,
            from_domain,
            register,
            enabled,
            sandbox_only,
            max_cps,
            max_concurrent_calls,
            notes
        )
        VALUES (
            p_provider_code,
            p_trunk_name,
            p_sip_host,
            p_sip_port,
            lower(p_transport),
            p_auth_username,
            p_auth_password,
            p_from_domain,
            p_register,
            p_enabled,
            p_sandbox_only,
            p_max_cps,
            p_max_concurrent_calls,
            p_notes
        );
    END IF;

    INSERT INTO billing.provider_trunk_events(provider_code, event_type, details)
    VALUES (
        p_provider_code,
        'provider_trunk_upsert',
        jsonb_build_object(
            'sip_host', p_sip_host,
            'sip_port', p_sip_port,
            'transport', lower(p_transport),
            'register', p_register,
            'enabled', p_enabled,
            'sandbox_only', p_sandbox_only
        )
    );

    RETURN QUERY
    SELECT
        pt.provider_code,
        pt.trunk_name,
        pt.sip_host,
        pt.sip_port,
        pt.transport,
        pt.register,
        pt.enabled,
        pt.sandbox_only,
        pt.max_cps,
        pt.max_concurrent_calls,
        pt.updated_at
    FROM billing.provider_trunks pt
    WHERE pt.provider_code = p_provider_code;
END;
$$;

CREATE OR REPLACE FUNCTION billing.set_provider_trunk_status(
    p_provider_code TEXT,
    p_enabled BOOLEAN
)
RETURNS TABLE (
    provider_code TEXT,
    trunk_name TEXT,
    enabled BOOLEAN,
    sandbox_only BOOLEAN,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE billing.provider_trunks pt
    SET enabled = p_enabled,
        updated_at = now()
    WHERE pt.provider_code = p_provider_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Provider trunk not found: %', p_provider_code;
    END IF;

    INSERT INTO billing.provider_trunk_events(provider_code, event_type, details)
    VALUES (
        p_provider_code,
        'provider_trunk_status',
        jsonb_build_object('enabled', p_enabled)
    );

    RETURN QUERY
    SELECT
        pt.provider_code,
        pt.trunk_name,
        pt.enabled,
        pt.sandbox_only,
        pt.updated_at
    FROM billing.provider_trunks pt
    WHERE pt.provider_code = p_provider_code;
END;
$$;

SELECT billing.upsert_provider_trunk(
    'SIM-FR-1',
    'France Sandbox Provider',
    'sandbox.invalid',
    5060,
    'udp',
    NULL,
    NULL,
    'sandbox.invalid',
    false,
    false,
    true,
    1,
    2,
    'Sandbox only - no real SIP connection'
);

SELECT billing.upsert_provider_trunk(
    'SIM-WORLD-1',
    'World Sandbox Provider',
    'sandbox.invalid',
    5060,
    'udp',
    NULL,
    NULL,
    'sandbox.invalid',
    false,
    false,
    true,
    1,
    2,
    'Sandbox only - no real SIP connection'
);

SELECT billing.upsert_provider_trunk(
    'SIM-UK-1',
    'UK Sandbox Provider',
    'sandbox.invalid',
    5060,
    'udp',
    NULL,
    NULL,
    'sandbox.invalid',
    false,
    false,
    true,
    1,
    2,
    'Sandbox only - no real SIP connection'
);
SQL

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < database/schemas/provider_trunk_sandbox_v1.sql

echo "[3/6] Scripts provider trunk..."

cat > scripts/provider-trunk-list.sh <<'SCRIPT'
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
  sip_host,
  sip_port,
  transport,
  register,
  enabled,
  sandbox_only,
  max_cps,
  max_concurrent_calls,
  updated_at
FROM billing.provider_trunks
ORDER BY provider_code;
SQL
SCRIPT

cat > scripts/provider-trunk-upsert.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

PROVIDER="${1:-SIM-FR-1}"
NAME="${2:-Sandbox Provider}"
HOST="${3:-sandbox.invalid}"
PORT="${4:-5060}"
TRANSPORT="${5:-udp}"
ENABLED="${6:-false}"

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -v provider="$PROVIDER" \
  -v name="$NAME" \
  -v host="$HOST" \
  -v port="$PORT" \
  -v transport="$TRANSPORT" \
  -v enabled="$ENABLED" <<'SQL'
SELECT *
FROM billing.upsert_provider_trunk(
  :'provider',
  :'name',
  :'host',
  :'port'::INTEGER,
  :'transport',
  NULL,
  NULL,
  :'host',
  false,
  :'enabled'::BOOLEAN,
  true,
  1,
  2,
  'Created by CLI sandbox'
);
SQL
SCRIPT

cat > scripts/provider-trunk-status-set.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

PROVIDER="${1:-SIM-FR-1}"
ENABLED="${2:-false}"

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -v provider="$PROVIDER" \
  -v enabled="$ENABLED" <<'SQL'
SELECT *
FROM billing.set_provider_trunk_status(:'provider', :'enabled'::BOOLEAN);
SQL
SCRIPT

cat > scripts/provider-trunk-events.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
SELECT
  created_at,
  provider_code,
  event_type,
  details
FROM billing.provider_trunk_events
ORDER BY created_at DESC
LIMIT 50;
SQL
SCRIPT

cat > scripts/provider-trunk-generate-freeswitch.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

OUT="storage/telephony/freeswitch/conf/sip_profiles/external/knvox-provider-gateways.generated.xml.disabled"
EXPORT="exports/trunks/provider_trunks_$(date +%Y%m%d-%H%M%S).csv"

mkdir -p "$(dirname "$OUT")" exports/trunks

TMP="$(mktemp)"

./scripts/compose.sh exec -T postgres psql \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  -AtF $'\t' <<'SQL' > "$TMP"
SELECT
  provider_code,
  trunk_name,
  sip_host,
  sip_port,
  transport,
  COALESCE(auth_username, ''),
  COALESCE(auth_password, ''),
  COALESCE(from_domain, sip_host),
  register,
  enabled,
  sandbox_only
FROM billing.provider_trunks
ORDER BY provider_code;
SQL

python3 - "$TMP" "$OUT" "$EXPORT" <<'PY'
import sys
import html
from pathlib import Path

tmp = Path(sys.argv[1])
out = Path(sys.argv[2])
export = Path(sys.argv[3])

rows = []
for line in tmp.read_text().splitlines():
    if not line.strip():
        continue
    parts = line.split("\t")
    while len(parts) < 11:
        parts.append("")
    rows.append(parts[:11])

xml = []
xml.append("<include>")
xml.append("  <!-- KNVOX generated sandbox provider gateways. -->")
xml.append("  <!-- File intentionally .disabled : FreeSWITCH does NOT load this file. -->")
xml.append("  <!-- Do not rename to .xml until PSTN activation procedure is approved. -->")

csv = ["provider_code,trunk_name,sip_host,sip_port,transport,auth_username,auth_password,from_domain,register,enabled,sandbox_only"]

for r in rows:
    provider, name, host, port, transport, user, password, domain, register, enabled, sandbox = r

    p = html.escape(provider)
    h = html.escape(host)
    d = html.escape(domain or host)
    u = html.escape(user)
    pw = html.escape(password)
    tr = html.escape(transport or "udp")

    xml.append(f'  <gateway name="{p}">')
    xml.append(f'    <param name="proxy" value="{h}:{port}"/>')
    xml.append(f'    <param name="realm" value="{d}"/>')
    if u:
        xml.append(f'    <param name="username" value="{u}"/>')
    if pw:
        xml.append(f'    <param name="password" value="{pw}"/>')
    xml.append(f'    <param name="register" value="{str(register).lower()}"/>')
    xml.append(f'    <param name="extension" value="{p}"/>')
    xml.append(f'    <param name="context" value="public"/>')
    xml.append(f'    <param name="caller-id-in-from" value="true"/>')
    xml.append(f'    <!-- transport={tr} enabled={enabled} sandbox_only={sandbox} -->')
    xml.append("  </gateway>")

    def q(v):
        return '"' + str(v).replace('"', '""') + '"'
    csv.append(",".join(q(x) for x in r))

xml.append("</include>")
out.write_text("\n".join(xml) + "\n")
export.write_text("\n".join(csv) + "\n")
PY

chmod 600 "$OUT" "$EXPORT"
rm -f "$TMP"

echo "XML sandbox généré : $OUT"
echo "CSV local généré   : $EXPORT"
echo ""
echo "IMPORTANT : fichier .disabled, aucun trunk réel n'est chargé par FreeSWITCH."
SCRIPT

chmod +x scripts/provider-trunk-*.sh

echo "[4/6] Test script..."

cat > scripts/provider-trunk-sandbox-test.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX PROVIDER TRUNK SANDBOX TEST"
echo "===================================="

echo ""
echo "[1/6] Liste trunks sandbox"
./scripts/provider-trunk-list.sh

echo ""
echo "[2/6] Génération XML FreeSWITCH désactivé"
./scripts/provider-trunk-generate-freeswitch.sh

echo ""
echo "[3/6] Vérification PSTN désactivé"
./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
SELECT key, value
FROM billing.system_settings
WHERE key IN ('pstn_enabled', 'require_balance', 'min_call_balance')
ORDER BY key;
SQL

echo ""
echo "[4/6] Simulation route fournisseur existante si disponible"
if [ -x ./scripts/provider-route-test.sh ]; then
  ./scripts/provider-route-test.sh || true
else
  echo "provider-route-test.sh absent, simulation ignorée."
fi

echo ""
echo "[5/6] Events trunks"
./scripts/provider-trunk-events.sh

echo ""
echo "[6/6] Health"
make health

echo ""
echo "Test V1.6.0 terminé."
echo "Aucun trunk réel connecté."
SCRIPT

chmod +x scripts/provider-trunk-sandbox-test.sh

echo "[5/6] Documentation..."

cat > docs/PROVIDER_TRUNK_SANDBOX_GATEWAY.md <<'DOC'
# KNVOX V1.6.0 - Provider Trunk Sandbox Gateway

## Objectif

Préparer la couche trunks fournisseurs sans activer de vrai trafic PSTN.

## Ce que fait cette version

- Ajoute `billing.provider_trunks`
- Ajoute un registre de trunks fournisseurs sandbox
- Génère un fichier FreeSWITCH gateway volontairement désactivé
- Exporte un CSV local dans `exports/trunks/`
- Vérifie que `pstn_enabled=false`

## Fichier FreeSWITCH généré

storage/telephony/freeswitch/conf/sip_profiles/external/knvox-provider-gateways.generated.xml.disabled

Le fichier reste en `.disabled`.

FreeSWITCH ne le charge pas.

## Sécurité

- PSTN désactivé
- Aucun trunk réel connecté
- Aucun appel externe réel ne sort
- Les exports contenant des paramètres trunk sont ignorés par Git

## Commandes

make provider-trunk-sandbox-test
make provider-trunk-list
make provider-trunk-generate
make provider-trunk-events

## Activation réelle future

Avant de renommer le fichier `.disabled` en `.xml`, il faudra :

1. valider le provider réel
2. définir IP allowlist fournisseur
3. valider les tarifs buy/sell
4. activer les limites CPS/concurrent
5. activer le débit wallet
6. activer `pstn_enabled=true` seulement après validation
DOC

echo "[6/6] Makefile..."

python3 - <<'PY'
from pathlib import Path

p = Path("Makefile")
s = p.read_text()

targets = [
    "provider-trunk-list",
    "provider-trunk-upsert",
    "provider-trunk-status-set",
    "provider-trunk-events",
    "provider-trunk-generate",
    "provider-trunk-sandbox-test",
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
provider-trunk-list:
>./scripts/provider-trunk-list.sh

provider-trunk-upsert:
>./scripts/provider-trunk-upsert.sh $${PROVIDER_CODE:-SIM-FR-1} "$${PROVIDER_NAME:-Sandbox Provider}" $${PROVIDER_HOST:-sandbox.invalid} $${PROVIDER_PORT:-5060} $${PROVIDER_TRANSPORT:-udp} $${PROVIDER_ENABLED:-false}

provider-trunk-status-set:
>./scripts/provider-trunk-status-set.sh $${PROVIDER_CODE:-SIM-FR-1} $${PROVIDER_ENABLED:-false}

provider-trunk-events:
>./scripts/provider-trunk-events.sh

provider-trunk-generate:
>./scripts/provider-trunk-generate-freeswitch.sh

provider-trunk-sandbox-test:
>./scripts/provider-trunk-sandbox-test.sh
"""

if "provider-trunk-sandbox-test:" not in s:
    s = s.rstrip() + "\n\n" + block

p.write_text(s)
PY

./scripts/compose.sh config >/dev/null

echo ""
echo "V1.6.0 Provider Trunk Sandbox installée."
echo ""
echo "Prochaines commandes :"
echo "make provider-trunk-sandbox-test"
echo "make health"
