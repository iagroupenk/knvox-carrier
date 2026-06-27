#!/bin/bash
set -euo pipefail

echo "================================================"
echo " KNVOX Carrier Platform - V1.3.2 CGRateS Internal DB Fix"
echo "================================================"

cd /opt/knvox-carrier

set -a
source .env
set +a

echo "[1/5] Arrêt CGRateS..."
./scripts/compose.sh stop cgr-engine || true

echo "[2/5] Backup config actuelle..."
mkdir -p configs/cgrates
cp configs/cgrates/cgrates.json "configs/cgrates/cgrates.json.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

echo "[3/5] Réécriture config CGRateS en mode internal..."

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

echo "[4/5] Redémarrage propre CGRateS..."
./scripts/compose.sh rm -f cgr-engine || true
./scripts/compose.sh up -d --force-recreate cgr-engine

sleep 20

echo "[5/5] Statut CGRateS..."
./scripts/compose.sh ps cgr-engine
./scripts/compose.sh logs --tail=120 cgr-engine

echo ""
echo "V1.3.2 terminé."
