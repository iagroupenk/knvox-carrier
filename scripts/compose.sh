#!/bin/bash
set -e

cd "$(dirname "$0")/.."

FILES=(-f docker-compose.yml)

if [ -f compose/telephony/docker-compose.yml ]; then
  FILES+=(-f compose/telephony/docker-compose.yml)
fi

if [ -f compose/billing/docker-compose.yml ]; then
  FILES+=(-f compose/billing/docker-compose.yml)
fi

exec docker compose "${FILES[@]}" "$@"
