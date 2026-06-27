#!/bin/bash

set -e

echo "========================================="
echo " KNVOX Carrier Platform Bootstrap v1.0.0 "
echo "========================================="

PROJECT_ROOT=$(pwd)

echo "[1/8] Création des dossiers..."

mkdir -p compose/{core,database,monitoring,security,storage,telephony,billing,crm,frontend,api,ai,automation,development}
mkdir -p configs/{traefik,postgres,redis,rabbitmq,minio,grafana,prometheus,loki,kamailio,freeswitch,rtpengine,cgrates}
mkdir -p services/{api,frontend,crm,billing,notifications,ai}
mkdir -p database/{migrations,seed,schemas}
mkdir -p scripts
mkdir -p docs
mkdir -p backups
mkdir -p logs
mkdir -p storage
mkdir -p ssl
mkdir -p tests
mkdir -p monitoring
mkdir -p .github/workflows

echo "[2/8] Création des fichiers..."

touch docker-compose.yml
touch Makefile
touch README.md
touch LICENSE
touch .env.example
touch .gitignore

touch compose/core/docker-compose.yml
touch compose/database/docker-compose.yml
touch compose/monitoring/docker-compose.yml
touch compose/security/docker-compose.yml
touch compose/storage/docker-compose.yml
touch compose/telephony/docker-compose.yml
touch compose/billing/docker-compose.yml
touch compose/crm/docker-compose.yml
touch compose/frontend/docker-compose.yml
touch compose/api/docker-compose.yml
touch compose/ai/docker-compose.yml

echo "[3/8] README"

cat > README.md <<EOF
# KNVOX Carrier Platform

Enterprise Open Source VoIP Carrier Platform

Version : 1.0.0

Architecture :

- Docker
- Kamailio
- FreeSWITCH
- RTPEngine
- CGRateS
- PostgreSQL
- Redis
- RabbitMQ
- MinIO
- Traefik
- Grafana

EOF

echo "[4/8] .gitignore"

cat > .gitignore <<EOF
.env
logs/
storage/
backups/
*.log
*.pid
*.swp
EOF

echo "[5/8] .env.example"

cat > .env.example <<EOF

PROJECT_NAME=KNVOX

DOMAIN=knvox.enaes.net

TIMEZONE=Africa/Casablanca

POSTGRES_PASSWORD=ChangeMe

REDIS_PASSWORD=ChangeMe

RABBITMQ_PASSWORD=ChangeMe

MINIO_ROOT_USER=minio

MINIO_ROOT_PASSWORD=ChangeMe

EOF

echo "[6/8] Scripts"

cat > scripts/start.sh <<EOF
#!/bin/bash
docker compose up -d
EOF

cat > scripts/stop.sh <<EOF
#!/bin/bash
docker compose down
EOF

cat > scripts/restart.sh <<EOF
#!/bin/bash
docker compose restart
EOF

chmod +x scripts/*.sh

echo "[7/8] Makefile"

cat > Makefile <<EOF
start:
	docker compose up -d

stop:
	docker compose down

restart:
	docker compose restart
EOF

echo "[8/8] Bootstrap terminé"

echo ""
echo "KNVOX Carrier Platform initialisé avec succès."
