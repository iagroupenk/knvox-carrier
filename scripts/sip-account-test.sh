#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX SIP ACCOUNT ADMIN TEST"
echo "===================================="

echo ""
echo "[1/7] Création compte SIP 2001 pour TEST1000"
./scripts/sip-account-create.sh TEST1000 2001 "TEST1000 SIP 2001"

echo ""
echo "[2/7] Liste comptes SIP"
./scripts/sip-account-list.sh

echo ""
echo "[3/7] Détail compte SIP 2001"
./scripts/sip-account-show.sh 2001

echo ""
echo "[4/7] Comptes SIP client TEST1000"
./scripts/customer-sip-accounts.sh TEST1000

echo ""
echo "[5/7] Désactivation compte SIP 2001"
./scripts/sip-account-status.sh 2001 false

echo ""
echo "[6/7] Réactivation compte SIP 2001"
./scripts/sip-account-status.sh 2001 true

echo ""
echo "[7/7] Events + health"
./scripts/sip-account-events.sh
make health

echo ""
echo "Test SIP Account Admin terminé."
