#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX PROVIDER READINESS TEST"
echo "===================================="

if [ ! -f secrets/provider-trunks/SIM-FR-1.json.enc ]; then
  AUTH_USERNAME="sandbox-user" \
  AUTH_PASSWORD="$(openssl rand -hex 16)" \
  FROM_DOMAIN="sandbox.invalid" \
  ./scripts/provider-credential-set.sh SIM-FR-1
fi

make pstn-force-off
make provider-gateway-vault-build

./scripts/provider-readiness-audit.sh SIM-FR-1 33612345678 TEST1000 1000

make pstn-safety-audit
make health

echo ""
echo "Test V1.6.4 terminé. Aucun trunk réel connecté."
