#!/bin/bash
set -e

cd "$(dirname "$0")/.."

FAIL=0

echo "===================================="
echo " KNVOX HEALTHCHECK"
echo "===================================="
echo ""

if ! systemctl is-active --quiet docker; then
  echo "ERROR: Docker is not running"
  FAIL=1
else
  echo "OK: Docker is running"
fi

echo ""

for svc in $(docker compose ps --services); do
  CID=$(docker compose ps -q "$svc" || true)

  if [ -z "$CID" ]; then
    echo "ERROR: $svc has no container"
    FAIL=1
    continue
  fi

  STATUS=$(docker inspect -f '{{.State.Status}}' "$CID")
  HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CID")

  if [ "$STATUS" != "running" ]; then
    echo "ERROR: $svc status=$STATUS health=$HEALTH"
    FAIL=1
  elif [ "$HEALTH" = "unhealthy" ]; then
    echo "ERROR: $svc status=$STATUS health=$HEALTH"
    FAIL=1
  else
    echo "OK: $svc status=$STATUS health=$HEALTH"
  fi
done

echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "GLOBAL STATUS: OK"
  exit 0
else
  echo "GLOBAL STATUS: ERROR"
  exit 1
fi
