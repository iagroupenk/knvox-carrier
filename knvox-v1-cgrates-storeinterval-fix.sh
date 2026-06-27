#!/bin/bash
set -euo pipefail

echo "================================================"
echo " KNVOX Carrier Platform - V1.3.3 CGRateS StoreInterval Fix"
echo "================================================"

cd /opt/knvox-carrier

set -a
source .env
set +a

echo "[1/5] Arrêt CGRateS..."
./scripts/compose.sh stop cgr-engine || true
./scripts/compose.sh rm -sf cgr-engine || true

echo "[2/5] Backup config actuelle..."
mkdir -p configs/cgrates
cp configs/cgrates/cgrates.json "configs/cgrates/cgrates.json.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

echo "[3/5] Réécriture cgrates.json pilote..."

cat > configs/cgrates/cgrates.json <<'CGRJSON'
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
    "db_type": "*internal"
  },

  "stor_db": {
    "db_type": "*internal"
  },

  "rals": {
    "enabled": true,
    "thresholds_conns": [],
    "stats_conns": [],
    "sessions_conns": []
  },

  "cdrs": {
    "enabled": true,
    "rals_conns": ["*internal"],
    "store_cdrs": true
  },

  "chargers": {
    "enabled": true,
    "attributes_conns": []
  },

  "sessions": {
    "enabled": true,
    "apiers_conns": ["*internal"],
    "chargers_conns": ["*internal"],
    "rals_conns": ["*internal"],
    "cdrs_conns": ["*internal"],
    "resources_conns": [],
    "thresholds_conns": [],
    "stats_conns": [],
    "routes_conns": [],
    "attributes_conns": [],
    "debit_interval": "10s",
    "store_session_costs": false,
    "client_protocol": 1.0
  },

  "attributes": {
    "enabled": true,
    "stats_conns": [],
    "resources_conns": [],
    "apiers_conns": []
  },

  "resources": {
    "enabled": false,
    "store_interval": "-1",
    "thresholds_conns": []
  },

  "stats": {
    "enabled": false,
    "store_interval": "-1",
    "thresholds_conns": []
  },

  "trends": {
    "enabled": false,
    "store_interval": "-1",
    "stats_conns": [],
    "thresholds_conns": []
  },

  "rankings": {
    "enabled": false,
    "store_interval": "-1",
    "stats_conns": [],
    "thresholds_conns": []
  },

  "thresholds": {
    "enabled": false,
    "store_interval": "-1",
    "sessions_conns": [],
    "apiers_conns": []
  },

  "routes": {
    "enabled": true,
    "attributes_conns": []
  },

  "apiers": {
    "enabled": true
  }
}
CGRJSON

chmod 600 configs/cgrates/cgrates.json

echo "[4/5] Redémarrage CGRateS..."
./scripts/compose.sh up -d --force-recreate cgr-engine

sleep 25

echo "[5/5] Statut CGRateS..."
./scripts/compose.sh ps cgr-engine
./scripts/compose.sh logs --tail=160 cgr-engine

echo ""
echo "V1.3.3 CGRateS StoreInterval Fix terminé."
