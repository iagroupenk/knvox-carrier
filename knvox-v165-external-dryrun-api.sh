#!/bin/bash
set -euo pipefail

cd /opt/knvox-carrier

echo "=== KNVOX V1.6.5 External Call Dry-Run API ==="

set -a
source .env
set +a

mkdir -p scripts docs database/schemas exports/audits

echo "[1/5] SQL dry-run events"

cat > database/schemas/external_call_dryrun_v1.sql <<'SQL'
CREATE TABLE IF NOT EXISTS billing.external_call_dry_run_events (
    id BIGSERIAL PRIMARY KEY,
    customer_code TEXT,
    src TEXT,
    dst TEXT,
    call_id TEXT,
    selected_provider_code TEXT,
    route_allowed BOOLEAN,
    route_reason TEXT,
    pstn_enabled BOOLEAN,
    request JSONB NOT NULL DEFAULT '{}'::jsonb,
    response JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO billing.system_settings(key, value)
VALUES ('pstn_enabled', 'false')
ON CONFLICT (key) DO UPDATE SET value = 'false';
SQL

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < database/schemas/external_call_dryrun_v1.sql

echo "[2/5] Patch API main.py"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("services/api/app/main.py")
s = p.read_text()

s = re.sub(
    r'app = FastAPI\(title=APP_NAME, version="[^"]+"\)',
    'app = FastAPI(title=APP_NAME, version="1.6.5")',
    s
)

marker = "# === KNVOX V1.6.5 External Call Dry-Run API ==="

if marker not in s:
    s += r'''

# === KNVOX V1.6.5 External Call Dry-Run API ===

import os as _knvox_os
import json as _knvox_json
import uuid as _knvox_uuid
from decimal import Decimal as _KnvoxDecimal
from datetime import date as _KnvoxDate, datetime as _KnvoxDateTime
from typing import Optional as _KnvoxOptional
from pydantic import BaseModel as _KnvoxBaseModel
from fastapi import Header as _KnvoxHeader, HTTPException as _KnvoxHTTPException


class ExternalCallDryRunRequest(_KnvoxBaseModel):
    customer_code: str = "TEST1000"
    src: str = "1000"
    dst: str
    call_id: _KnvoxOptional[str] = None


def _knvox_v165_clean(value):
    if isinstance(value, _KnvoxDecimal):
        return float(value)
    if isinstance(value, (_KnvoxDateTime, _KnvoxDate)):
        return value.isoformat()
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="ignore")
    if isinstance(value, dict):
        return {k: _knvox_v165_clean(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_knvox_v165_clean(v) for v in value]
    return value


def _knvox_v165_conn():
    for name in ("get_conn", "get_db_connection", "db_connect"):
        fn = globals().get(name)
        if callable(fn):
            return fn()

    import psycopg2

    return psycopg2.connect(
        host=_knvox_os.getenv("POSTGRES_HOST") or _knvox_os.getenv("DB_HOST") or "postgres",
        port=int(_knvox_os.getenv("POSTGRES_PORT", "5432")),
        dbname=_knvox_os.getenv("POSTGRES_DB") or _knvox_os.getenv("DB_NAME"),
        user=_knvox_os.getenv("POSTGRES_USER") or _knvox_os.getenv("DB_USER"),
        password=_knvox_os.getenv("POSTGRES_PASSWORD") or _knvox_os.getenv("DB_PASSWORD"),
    )


def _knvox_v165_auth(api_key: _KnvoxOptional[str]):
    expected = _knvox_os.getenv("BILLING_API_TOKEN", "")
    if not expected:
        raise _KnvoxHTTPException(status_code=500, detail="BILLING_API_TOKEN missing")
    if api_key != expected:
        raise _KnvoxHTTPException(status_code=401, detail="Invalid API key")


@app.post("/api/v1/external-call/dry-run")
def external_call_dry_run(
    payload: ExternalCallDryRunRequest,
    x_knvox_api_key: _KnvoxOptional[str] = _KnvoxHeader(default=None),
):
    _knvox_v165_auth(x_knvox_api_key)

    call_id = payload.call_id or f"external-dry-run-{payload.dst}-{_knvox_uuid.uuid4().hex[:12]}"

    conn = _knvox_v165_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM billing.provider_route_simulate(%s, %s, %s, %s);",
                (payload.customer_code, payload.src, payload.dst, call_id),
            )
            row = cur.fetchone()

            if not row:
                raise _KnvoxHTTPException(status_code=404, detail="No route simulation result")

            cols = [d[0] for d in cur.description]
            route = {cols[i]: _knvox_v165_clean(row[i]) for i in range(len(cols))}

            response = {
                "dry_run": True,
                "execution_mode": "NO_DIAL_NO_PSTN",
                "call_was_placed": False,
                "external_call_allowed": False,
                "safety_message": "Dry-run only. No SIP INVITE sent. No PSTN trunk used.",
                "route": route,
            }

            cur.execute(
                """
                INSERT INTO billing.external_call_dry_run_events(
                    customer_code,
                    src,
                    dst,
                    call_id,
                    selected_provider_code,
                    route_allowed,
                    route_reason,
                    pstn_enabled,
                    request,
                    response
                )
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb,%s::jsonb);
                """,
                (
                    payload.customer_code,
                    payload.src,
                    payload.dst,
                    call_id,
                    route.get("selected_provider_code"),
                    route.get("route_allowed"),
                    route.get("route_reason"),
                    route.get("pstn_enabled"),
                    _knvox_json.dumps(payload.dict()),
                    _knvox_json.dumps(response),
                ),
            )

        conn.commit()
        return response

    finally:
        try:
            conn.close()
        except Exception:
            pass
'''

p.write_text(s)
print("main.py patched V1.6.5")
PY

python3 -m py_compile services/api/app/main.py

echo "[3/5] Scripts dry-run"

cat > scripts/external-call-dry-run.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

DST="${1:-33612345678}"
CUSTOMER="${CUSTOMER_CODE:-TEST1000}"
SRC="${SRC:-1000}"

API_URL="${BILLING_API_URL:-http://127.0.0.1:${BILLING_API_PORT:-8088}}"

DATA="$(jq -n \
  --arg customer_code "$CUSTOMER" \
  --arg src "$SRC" \
  --arg dst "$DST" \
  '{customer_code:$customer_code, src:$src, dst:$dst}')"

curl -fsS \
  -X POST \
  -H "Content-Type: application/json" \
  -H "X-KNVOX-API-Key: ${BILLING_API_TOKEN}" \
  -d "$DATA" \
  "${API_URL}/api/v1/external-call/dry-run" | jq .
SCRIPT

cat > scripts/external-call-dry-run-test.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX EXTERNAL CALL DRY-RUN TEST"
echo "===================================="

echo ""
echo "[1/5] Force PSTN OFF"
make pstn-force-off

echo ""
echo "[2/5] Dry-run France sandbox"
./scripts/external-call-dry-run.sh 33612345678

echo ""
echo "[3/5] Dry-run préfixe bloqué 882"
./scripts/external-call-dry-run.sh 882123456 || true

echo ""
echo "[4/5] Derniers dry-runs API"
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
FROM billing.external_call_dry_run_events
ORDER BY created_at DESC
LIMIT 10;
SQL

echo ""
echo "[5/5] Safety + health"
make pstn-safety-audit
make health

echo ""
echo "Test V1.6.5 terminé. Aucun appel réel placé."
SCRIPT

chmod +x scripts/external-call-dry-run*.sh

echo "[4/5] Docs + Makefile"

cat > docs/EXTERNAL_CALL_DRY_RUN_API.md <<'DOC'
# KNVOX V1.6.5 - External Call Dry-Run API

Endpoint :

POST /api/v1/external-call/dry-run

Objectif :

- Simuler un appel externe via API
- Retourner provider, destination, sell rate, buy rate, marge
- Confirmer que PSTN reste OFF
- Ne jamais envoyer d'INVITE SIP
- Journaliser dans billing.external_call_dry_run_events

Sécurité :

- Aucun trunk réel utilisé
- Aucun fichier gateway actif
- pstn_enabled reste false
- dry_run=true
- call_was_placed=false

Test :

make external-call-dry-run-test
DOC

python3 - <<'PY'
from pathlib import Path

p = Path("Makefile")
s = p.read_text()

targets = ["external-call-dry-run", "external-call-dry-run-test"]

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
external-call-dry-run:
>./scripts/external-call-dry-run.sh $${DST:-33612345678}

external-call-dry-run-test:
>./scripts/external-call-dry-run-test.sh
"""

if "external-call-dry-run-test:" not in s:
    s = s.rstrip() + "\n\n" + block

p.write_text(s)
PY

echo "[5/5] Restart billing-api"

./scripts/compose.sh config >/dev/null
./scripts/compose.sh restart billing-api
sleep 8

echo ""
echo "V1.6.5 External Call Dry-Run API installée."
echo ""
echo "Prochaines commandes :"
echo "make external-call-dry-run-test"
echo "make health"
