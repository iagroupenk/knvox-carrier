#!/bin/bash
set -e

cd "$(dirname "$0")/.."

SERVICE="${1:-}"

if [ -z "$SERVICE" ]; then
  ./scripts/compose.sh logs --tail=150 -f
else
  ./scripts/compose.sh logs --tail=150 -f "$SERVICE"
fi
