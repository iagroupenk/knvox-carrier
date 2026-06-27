#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "ERROR: .env introuvable"
  exit 1
fi

set -a
source .env
set +a

TS=$(date +"%Y%m%d-%H%M%S")
DEST="backups/${TS}"
ABS_DEST="$(readlink -f "$DEST")"

mkdir -p "$DEST"
chmod 700 backups "$DEST"

echo "===================================="
echo " KNVOX BACKUP ${TS}"
echo "===================================="

echo "[1/8] Backup PostgreSQL..."
docker compose exec -T postgres pg_dumpall -U "$POSTGRES_USER" > "${DEST}/postgres_dump.sql"

backup_container_path() {
  CONTAINER="$1"
  PATH_IN_CONTAINER="$2"
  OUTFILE="$3"

  if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "Backup ${CONTAINER}:${PATH_IN_CONTAINER} -> ${OUTFILE}"
    docker run --rm \
      --volumes-from "$CONTAINER" \
      -v "${ABS_DEST}:/backup" \
      alpine:3.20 \
      tar czf "/backup/${OUTFILE}" -C "$PATH_IN_CONTAINER" . || echo "WARNING: backup failed for ${CONTAINER}"
  else
    echo "WARNING: container ${CONTAINER} not found"
  fi
}

echo "[2/8] Backup Redis..."
backup_container_path knvox-redis /data redis_data.tgz

echo "[3/8] Backup RabbitMQ..."
backup_container_path knvox-rabbitmq /var/lib/rabbitmq rabbitmq_data.tgz

echo "[4/8] Backup MinIO..."
backup_container_path knvox-minio /data minio_data.tgz

echo "[5/8] Backup Grafana..."
backup_container_path knvox-grafana /var/lib/grafana grafana_data.tgz

echo "[6/8] Backup Prometheus..."
backup_container_path knvox-prometheus /prometheus prometheus_data.tgz

echo "[7/8] Backup Loki..."
backup_container_path knvox-loki /loki loki_data.tgz

echo "[8/8] Backup configuration..."
cp docker-compose.yml "${DEST}/docker-compose.yml"
cp .env "${DEST}/env.backup"
tar czf "${DEST}/configs.tgz" configs scripts docs Makefile README.md 2>/dev/null || true

sha256sum "${DEST}"/* > "${DEST}/SHA256SUMS"

tar czf "backups/knvox-backup-${TS}.tgz" -C backups "${TS}"

echo ""
echo "Backup terminé : backups/knvox-backup-${TS}.tgz"
