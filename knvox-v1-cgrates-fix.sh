#!/bin/bash
set -euo pipefail

echo "================================================"
echo " KNVOX Carrier Platform - V1.3.1 CGRateS Fix"
echo "================================================"

cd /opt/knvox-carrier

set -a
source .env
set +a

mkdir -p configs/cgrates storage/billing/{cgrates,cdr}

echo "[1/5] Arrêt CGRateS..."
./scripts/compose.sh stop cgr-engine || true

echo "[2/5] Backup ancienne config CGRateS..."
if [ -d configs/cgrates ]; then
  tar czf "configs/cgrates.backup.$(date +%Y%m%d-%H%M%S).tgz" configs/cgrates || true
fi

echo "[3/5] Création cgrates.json minimal KNVOX..."

cat > configs/cgrates/cgrates.json <<CGRJSON
{
  "general": {
    "node_id": "knvox-cgr-engine",
    "logger": "*stdout",
    "log_level": 6,
    "default_tenant": "knvox",
    "default_category": "call",
    "default_request_type": "*prepaid",
    "default_timezone": "Europe/Paris"
  },

  "listen": {
    "rpc_json": ":2012",
    "rpc_gob": ":2013",
    "http": ":2080",
    "birpc_json": ":2014"
  },

  "data_db": {
    "db_type": "*redis",
    "db_host": "redis",
    "db_port": 6379,
    "db_name": "10",
    "db_user": "",
    "db_password": "${REDIS_PASSWORD}"
  },

  "stor_db": {
    "db_type": "*redis",
    "db_host": "redis",
    "db_port": 6379,
    "db_name": "11",
    "db_user": "",
    "db_password": "${REDIS_PASSWORD}"
  },

  "schedulers": {
    "enabled": true
  },

  "rals": {
    "enabled": true
  },

  "cdrs": {
    "enabled": true,
    "rals_conns": ["*internal"]
  },

  "chargers": {
    "enabled": true
  },

  "sessions": {
    "enabled": true,
    "rals_conns": ["*internal"],
    "cdrs_conns": ["*internal"],
    "debit_interval": "10s",
    "client_protocol": 1.0
  },

  "attributes": {
    "enabled": true
  },

  "resources": {
    "enabled": true
  },

  "stats": {
    "enabled": true
  },

  "thresholds": {
    "enabled": true
  },

  "routes": {
    "enabled": true
  },

  "apiers": {
    "enabled": true
  }
}
CGRJSON

chmod 600 configs/cgrates/cgrates.json

echo "[4/5] Mise à jour billing-status..."

cat > scripts/billing-status.sh <<'BILLSTATUS'
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
BILLSTATUS

chmod +x scripts/*.sh

echo "[5/5] Redémarrage CGRateS..."
./scripts/compose.sh up -d --force-recreate cgr-engine

sleep 20

./scripts/compose.sh ps cgr-engine
./scripts/compose.sh logs --tail=120 cgr-engine

echo ""
echo "V1.3.1 CGRateS Fix terminé."
