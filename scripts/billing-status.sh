#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX BILLING STATUS"
echo "===================================="
echo ""

./scripts/compose.sh ps cgr-engine || true

echo ""
echo "Port CGRateS JSON-RPC local:"
ss -lntp | grep ":${CGRATES_JSONRPC_PORT}" || true

echo ""
echo "CGRateS logs:"
./scripts/compose.sh logs --tail=100 cgr-engine || true

echo ""
echo "PostgreSQL billing tables:"
./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt billing.*" || true

echo ""
echo "CGRateS console status:"
docker run --rm --network host "${CGRATES_CONSOLE_IMAGE}" -server "127.0.0.1:${CGRATES_JSONRPC_PORT}" status || true
