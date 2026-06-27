#!/bin/bash
set -e

cd "$(dirname "$0")/.."

SERVICE="${1:-}"

if [ -z "$SERVICE" ]; then
  docker compose logs --tail=150 -f
else
  docker compose logs --tail=150 -f "$SERVICE"
fi
