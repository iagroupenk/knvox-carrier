#!/bin/bash
set -euo pipefail

echo "================================================"
echo " KNVOX Carrier Platform - V1.0.2 Operations"
echo "================================================"

mkdir -p scripts docs backups logs storage ssl

echo "[1/7] Sécurisation .env et .gitignore..."

if [ -f .env ]; then
  chmod 600 .env
fi

cat > .gitignore <<'GITIGNORE'
.env
*.env
!.env.example

logs/
storage/
backups/
ssl/

*.log
*.pid
*.swp
.DS_Store

__pycache__/
node_modules/
dist/
build/
GITIGNORE

echo "[2/7] Script status..."

cat > scripts/status.sh <<'STATUS'
#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX PLATFORM STATUS"
echo "===================================="
echo ""

echo "Docker:"
systemctl is-active docker || true
echo ""

echo "Containers:"
docker compose ps
echo ""

echo "URLs:"
if [ -f .env ]; then
  DOMAIN=$(grep '^DOMAIN=' .env | cut -d= -f2)
  echo "Portainer : https://portainer.${DOMAIN}"
  echo "Grafana   : https://grafana.${DOMAIN}"
  echo "MinIO     : https://minio.${DOMAIN}"
  echo "RabbitMQ  : https://rabbitmq.${DOMAIN}"
  echo "Status    : https://status.${DOMAIN}"
fi
STATUS

echo "[3/7] Script healthcheck..."

cat > scripts/healthcheck.sh <<'HEALTH'
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
HEALTH

echo "[4/7] Script logs..."

cat > scripts/logs.sh <<'LOGS'
#!/bin/bash
set -e

cd "$(dirname "$0")/.."

SERVICE="${1:-}"

if [ -z "$SERVICE" ]; then
  docker compose logs --tail=150 -f
else
  docker compose logs --tail=150 -f "$SERVICE"
fi
LOGS

echo "[5/7] Script backup..."

cat > scripts/backup.sh <<'BACKUP'
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
BACKUP

echo "[6/7] Script firewall..."

cat > scripts/firewall.sh <<'FIREWALL'
#!/bin/bash
set -e

SSH_PORT="${SSH_PORT:-22}"

echo "===================================="
echo " KNVOX FIREWALL"
echo "===================================="
echo "SSH port autorisé : ${SSH_PORT}"
echo ""

apt-get update
apt-get install -y ufw

ufw default deny incoming
ufw default allow outgoing

ufw allow "${SSH_PORT}/tcp"
ufw allow 80/tcp
ufw allow 443/tcp

ufw --force enable
ufw status numbered
FIREWALL

echo "[7/7] Documentation et Makefile..."

cat > docs/RUNBOOK.md <<'RUNBOOK'
# KNVOX Carrier Platform - Runbook

## Commandes principales

make start
make stop
make restart
make status
make health
make logs
make backup
make firewall

## Interfaces

Les accès sont disponibles dans le fichier .env.

Portainer : https://portainer.DOMAIN
Grafana   : https://grafana.DOMAIN
MinIO     : https://minio.DOMAIN
RabbitMQ  : https://rabbitmq.DOMAIN
Status    : https://status.DOMAIN

## Mots de passe

Les mots de passe sont stockés dans .env.

Ne jamais envoyer .env sur GitHub.
RUNBOOK

cat > docs/SECURITY.md <<'SECURITY'
# KNVOX Security Notes

## Ports publics V1

- 22/tcp SSH
- 80/tcp HTTP
- 443/tcp HTTPS

Les services internes ne doivent pas être exposés directement.

## Secrets

Le fichier .env contient les mots de passe.
Il doit rester local au serveur.

## Firewall

Pour activer UFW avec SSH sur le port 22 :

./scripts/firewall.sh

Si SSH utilise un autre port :

SSH_PORT=2222 ./scripts/firewall.sh
SECURITY

cat > Makefile <<'MAKEFILE'
start:
docker compose up -d

stop:
docker compose down

restart:
docker compose restart

status:
./scripts/status.sh

health:
./scripts/healthcheck.sh

logs:
./scripts/logs.sh

backup:
./scripts/backup.sh

pull:
docker compose pull

update:
docker compose pull
docker compose up -d

firewall:
./scripts/firewall.sh
MAKEFILE

chmod +x scripts/*.sh

echo ""
echo "V1.0.2 Operations installée."
echo ""
echo "Commandes de test :"
echo "make status"
echo "make health"
echo "make backup"
