#!/bin/bash
set -euo pipefail

cd /opt/knvox-carrier

echo "=== HOTFIX V1.6.5 dry-run API 500 ==="

echo "[1/5] Dernières logs billing-api"
./scripts/compose.sh logs --tail=80 billing-api || true

echo ""
echo "[2/5] Patch main.py"

python3 - <<'PY'
from pathlib import Path

p = Path("services/api/app/main.py")
s = p.read_text()

start = s.find("def _knvox_v165_auth(")
end = s.find('@app.post("/api/v1/external-call/dry-run")', start)

if start == -1 or end == -1:
    raise SystemExit("Bloc _knvox_v165_auth ou route dry-run introuvable")

auth_new = '''def _knvox_v165_auth(api_key: _KnvoxOptional[str]):
    candidates = [
        _knvox_os.getenv("BILLING_API_TOKEN", ""),
        _knvox_os.getenv("KNVOX_API_TOKEN", ""),
        _knvox_os.getenv("API_TOKEN", ""),
        str(globals().get("BILLING_API_TOKEN", "") or ""),
        str(globals().get("KNVOX_API_TOKEN", "") or ""),
        str(globals().get("API_TOKEN", "") or ""),
    ]

    expected = ""
    for item in candidates:
        if item:
            expected = str(item)
            break

    if not expected:
        raise _KnvoxHTTPException(
            status_code=500,
            detail="API token missing in billing-api environment"
        )

    if api_key != expected:
        raise _KnvoxHTTPException(status_code=401, detail="Invalid API key")
'''

s = s[:start] + auth_new + "\n\n" + s[end:]

old = '''            cols = [d[0] for d in cur.description]
            route = {cols[i]: _knvox_v165_clean(row[i]) for i in range(len(cols))}
'''

new = '''            if hasattr(row, "keys"):
                route = {str(k): _knvox_v165_clean(row[k]) for k in row.keys()}
            else:
                cols = [d[0] for d in cur.description]
                route = {cols[i]: _knvox_v165_clean(row[i]) for i in range(len(cols))}
'''

if old in s:
    s = s.replace(old, new)
elif 'if hasattr(row, "keys"):' not in s:
    raise SystemExit("Bloc mapping row introuvable")

p.write_text(s)
print("Patch V1.6.5 appliqué")
PY

python3 -m py_compile services/api/app/main.py

echo ""
echo "[3/5] Copie dans container billing-api"

CID="$(./scripts/compose.sh ps -q billing-api)"

API_FILE="$(
docker exec "$CID" sh -lc 'python - <<PY
import inspect
try:
    import app.main as m
except Exception:
    import main as m
print(inspect.getfile(m))
PY'
)"

echo "API file: $API_FILE"

docker cp services/api/app/main.py "$CID:$API_FILE"
docker exec "$CID" sh -lc "python -m py_compile '$API_FILE'"

echo ""
echo "[4/5] Restart billing-api"
./scripts/compose.sh restart billing-api
sleep 8

echo ""
echo "[5/5] Vérification route"
set -a
source .env
set +a

API_URL="${BILLING_API_URL:-http://127.0.0.1:${BILLING_API_PORT:-8088}}"

curl -fsS "${API_URL}/openapi.json" | jq -r '.paths | keys[]' | grep external-call

echo ""
echo "HOTFIX OK"
