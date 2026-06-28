#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX PROVIDER VAULT TEST"
echo "===================================="

AUTH_USERNAME="sandbox-user" \
AUTH_PASSWORD="$(openssl rand -hex 16)" \
FROM_DOMAIN="sandbox.invalid" \
./scripts/provider-credential-set.sh SIM-FR-1

./scripts/provider-credential-list.sh
./scripts/provider-credential-show.sh SIM-FR-1
./scripts/provider-vault-audit.sh
make pstn-safety-audit
make health

echo "Test V1.6.2 terminé. Aucun trunk réel connecté."
