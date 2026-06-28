#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX PROVIDER GATEWAY VAULT TEST"
echo "===================================="

if [ ! -f secrets/provider-trunks/SIM-FR-1.json.enc ]; then
  AUTH_USERNAME="sandbox-user" \
  AUTH_PASSWORD="$(openssl rand -hex 16)" \
  FROM_DOMAIN="sandbox.invalid" \
  ./scripts/provider-credential-set.sh SIM-FR-1
fi

./scripts/provider-gateway-vault-build.sh
./scripts/provider-gateway-vault-audit.sh
make pstn-safety-audit
make health

echo "Test V1.6.3 terminé. Aucun trunk réel connecté."
