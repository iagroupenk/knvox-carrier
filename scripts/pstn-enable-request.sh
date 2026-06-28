#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX PSTN ENABLE REQUEST"
echo "===================================="
echo ""
echo "REFUS: V1.6.1 ne permet pas d'activer le PSTN réel."
echo "Raison: activation trunk réel réservée à une version dédiée avec validation complète."
echo ""

./scripts/pstn-safety-audit.sh || true

echo ""
echo "pstn_enabled reste OFF."
exit 1
