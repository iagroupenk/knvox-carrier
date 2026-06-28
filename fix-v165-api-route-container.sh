#!/bin/bash
set -euo pipefail

cd /opt/knvox-carrier

echo "=== FIX V1.6.5 API route dans container billing-api ==="

CID="$(./scripts/compose.sh ps -q billing-api)"

if [ -z "$CID" ]; then
  echo "ERREUR: container billing-api introuvable"
  exit 1
fi

echo "Container: $CID"

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

echo "Fichier API actif dans container: $API_FILE"

echo "[1/4] Vérification route côté host"
grep -n "external-call/dry-run" services/api/app/main.py || {
  echo "ERREUR: route absente du main.py host"
  exit 1
}

echo "[2/4] Copie main.py host vers container"
docker cp services/api/app/main.py "$CID:$API_FILE"

echo "[3/4] Vérification syntaxe dans container"
docker exec "$CID" sh -lc "python -m py_compile '$API_FILE'"

echo "[4/4] Restart billing-api"
./scripts/compose.sh restart billing-api
sleep 8

set -a
source .env
set +a

API_URL="${BILLING_API_URL:-http://127.0.0.1:${BILLING_API_PORT:-8088}}"

echo ""
echo "Routes dry-run chargées :"
curl -fsS "${API_URL}/openapi.json" | jq -r '.paths | keys[]' | grep dry-run || {
  echo "ERREUR: endpoint toujours absent"
  exit 1
}

echo ""
echo "FIX OK"
