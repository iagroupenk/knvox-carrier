#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
set -a
source .env
set +a

PROVIDER="${1:-SIM-FR-1}"
MODE="${2:-masked}"

SAFE_PROVIDER="$(echo "$PROVIDER" | tr -cd 'A-Za-z0-9_.-')"
FILE="secrets/provider-trunks/${SAFE_PROVIDER}.json.enc"

if [ ! -f "$FILE" ]; then
  echo "ERROR: credential introuvable : $FILE"
  exit 1
fi

JSON="$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:VAULT_MASTER_KEY -in "$FILE")"

if [ "$MODE" = "--show-secret" ]; then
  echo "$JSON" | jq .
else
  echo "$JSON" | jq '.auth_password="********"'
fi
