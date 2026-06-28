#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== TEST SIP AUTH HARDENING ==="

echo "[1] 1002 doit être autorisé"
./scripts/kamailio-register-guard.sh 1002 196.118.37.197
echo "OK 1002 autorisé"

echo "[2] 9999 doit être bloqué"
if ./scripts/kamailio-register-guard.sh 9999 196.118.37.197; then
  echo "ERREUR: 9999 autorisé"
  exit 1
else
  echo "OK 9999 bloqué"
fi

echo "[3] allowlist IP 1002"
set -a
source .env
set +a

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v username="1002" -v cidr="196.118.37.197/32" <<'SQL'
SELECT * FROM billing.set_sip_allowed_ip(:'username', :'cidr');
SQL

./scripts/kamailio-register-guard.sh 1002 196.118.37.197
echo "OK IP autorisée"

if ./scripts/kamailio-register-guard.sh 1002 8.8.8.8; then
  echo "ERREUR: IP non autorisée acceptée"
  exit 1
else
  echo "OK IP non autorisée bloquée"
fi

./scripts/compose.sh exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v username="1002" <<'SQL'
SELECT * FROM billing.clear_sip_allowed_ip(:'username');
SQL

make fs-sip-sync
make health

echo "TEST OK"
