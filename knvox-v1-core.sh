#!/bin/bash
set -e

DOMAIN="knvox.enaes.net"
ACME_EMAIL="admin@enaes.net"

echo "================================================"
echo " KNVOX Carrier Platform - V1.0.1 Core Infra"
echo "================================================"

echo "[1/9] Installation des paquets système..."

apt-get update
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  git \
  jq \
  tree \
  openssl \
  apt-transport-https \
  lsb-release

echo "[2/9] Installation Docker officiel..."

install -m 0755 -d /etc/apt/keyrings

if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

echo "[3/9] Génération du fichier .env..."

if [ ! -f .env ]; then
cat > .env <<ENVEOF
PROJECT_NAME=knvox
DOMAIN=${DOMAIN}
ACME_EMAIL=${ACME_EMAIL}
TIMEZONE=Europe/Paris

POSTGRES_DB=knvox
POSTGRES_USER=knvox
POSTGRES_PASSWORD=$(openssl rand -hex 32)

REDIS_PASSWORD=$(openssl rand -hex 32)

RABBITMQ_USER=knvox
RABBITMQ_PASSWORD=$(openssl rand -hex 32)

MINIO_ROOT_USER=knvoxadmin
MINIO_ROOT_PASSWORD=$(openssl rand -hex 32)

GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 24)

ENVEOF
fi

echo "[4/9] Création des dossiers de configuration..."

mkdir -p configs/prometheus
mkdir -p configs/grafana/provisioning/datasources
mkdir -p configs/loki
mkdir -p configs/promtail
mkdir -p logs/traefik
mkdir -p storage/{postgres,redis,rabbitmq,minio,grafana,prometheus,loki,portainer,uptime}

echo "[5/9] Configuration Prometheus..."

cat > configs/prometheus/prometheus.yml <<'PROMEOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets:
          - prometheus:9090

  - job_name: traefik
    static_configs:
      - targets:
          - traefik:8082

  - job_name: node-exporter
    static_configs:
      - targets:
          - node-exporter:9100

  - job_name: cadvisor
    static_configs:
      - targets:
          - cadvisor:8080
PROMEOF

echo "[6/9] Configuration Grafana datasources..."

cat > configs/grafana/provisioning/datasources/datasources.yml <<'GRAFEOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
GRAFEOF

echo "[7/9] Configuration Loki / Promtail..."

cat > configs/loki/loki-config.yml <<'LOKIEOF'
auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  allow_structured_metadata: false
LOKIEOF

cat > configs/promtail/promtail-config.yml <<'PROMTAILEOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s

    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: 'container'

      - source_labels: ['__meta_docker_container_log_stream']
        target_label: 'stream'
PROMTAILEOF

echo "[8/9] Création docker-compose.yml..."

cat > docker-compose.yml <<'COMPOSEEOF'
services:

  traefik:
    image: traefik:v3
    container_name: knvox-traefik
    restart: unless-stopped
    command:
      - --api.dashboard=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --entrypoints.metrics.address=:8082
      - --metrics.prometheus=true
      - --metrics.prometheus.entrypoint=metrics
      - --certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}
      - --certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json
      - --certificatesresolvers.letsencrypt.acme.httpchallenge=true
      - --certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web
      - --entrypoints.web.http.redirections.entrypoint.to=websecure
      - --entrypoints.web.http.redirections.entrypoint.scheme=https
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_letsencrypt:/letsencrypt
      - ./logs/traefik:/logs
    networks:
      - frontend
      - backend
      - monitoring

  portainer:
    image: portainer/portainer-ce:lts
    container_name: knvox-portainer
    restart: unless-stopped
    command: -H unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    labels:
      - traefik.enable=true
      - traefik.http.routers.portainer.rule=Host(`portainer.${DOMAIN}`)
      - traefik.http.routers.portainer.entrypoints=websecure
      - traefik.http.routers.portainer.tls.certresolver=letsencrypt
      - traefik.http.services.portainer.loadbalancer.server.port=9000
    networks:
      - frontend
      - management

  postgres:
    image: postgres:16-alpine
    container_name: knvox-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      TZ: ${TIMEZONE}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - database
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: knvox-redis
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes", "--requirepass", "${REDIS_PASSWORD}"]
    volumes:
      - redis_data:/data
    networks:
      - database
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  rabbitmq:
    image: rabbitmq:3-management-alpine
    container_name: knvox-rabbitmq
    restart: unless-stopped
    environment:
      RABBITMQ_DEFAULT_USER: ${RABBITMQ_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_PASSWORD}
      TZ: ${TIMEZONE}
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    labels:
      - traefik.enable=true
      - traefik.http.routers.rabbitmq.rule=Host(`rabbitmq.${DOMAIN}`)
      - traefik.http.routers.rabbitmq.entrypoints=websecure
      - traefik.http.routers.rabbitmq.tls.certresolver=letsencrypt
      - traefik.http.services.rabbitmq.loadbalancer.server.port=15672
    networks:
      - frontend
      - database
      - backend
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
      interval: 15s
      timeout: 5s
      retries: 5

  minio:
    image: minio/minio:latest
    container_name: knvox-minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
      TZ: ${TIMEZONE}
    volumes:
      - minio_data:/data
    labels:
      - traefik.enable=true
      - traefik.http.routers.minio.rule=Host(`minio.${DOMAIN}`)
      - traefik.http.routers.minio.entrypoints=websecure
      - traefik.http.routers.minio.tls.certresolver=letsencrypt
      - traefik.http.services.minio.loadbalancer.server.port=9001
    networks:
      - frontend
      - storage

  prometheus:
    image: prom/prometheus:latest
    container_name: knvox-prometheus
    restart: unless-stopped
    volumes:
      - ./configs/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:latest
    container_name: knvox-grafana
    restart: unless-stopped
    environment:
      GF_SECURITY_ADMIN_USER: ${GRAFANA_ADMIN_USER}
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
      GF_USERS_ALLOW_SIGN_UP: "false"
      TZ: ${TIMEZONE}
    volumes:
      - grafana_data:/var/lib/grafana
      - ./configs/grafana/provisioning:/etc/grafana/provisioning
    labels:
      - traefik.enable=true
      - traefik.http.routers.grafana.rule=Host(`grafana.${DOMAIN}`)
      - traefik.http.routers.grafana.entrypoints=websecure
      - traefik.http.routers.grafana.tls.certresolver=letsencrypt
      - traefik.http.services.grafana.loadbalancer.server.port=3000
    networks:
      - frontend
      - monitoring

  loki:
    image: grafana/loki:latest
    container_name: knvox-loki
    restart: unless-stopped
    command: -config.file=/etc/loki/loki-config.yml
    volumes:
      - ./configs/loki/loki-config.yml:/etc/loki/loki-config.yml:ro
      - loki_data:/loki
    networks:
      - monitoring

  promtail:
    image: grafana/promtail:latest
    container_name: knvox-promtail
    restart: unless-stopped
    command: -config.file=/etc/promtail/promtail-config.yml
    volumes:
      - ./configs/promtail/promtail-config.yml:/etc/promtail/promtail-config.yml:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
    networks:
      - monitoring
    depends_on:
      - loki

  node-exporter:
    image: prom/node-exporter:latest
    container_name: knvox-node-exporter
    restart: unless-stopped
    pid: host
    command:
      - --path.rootfs=/host
    volumes:
      - /:/host:ro,rslave
    networks:
      - monitoring

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: knvox-cadvisor
    restart: unless-stopped
    privileged: true
    devices:
      - /dev/kmsg
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    networks:
      - monitoring

  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: knvox-uptime
    restart: unless-stopped
    volumes:
      - uptime_data:/app/data
    labels:
      - traefik.enable=true
      - traefik.http.routers.uptime.rule=Host(`status.${DOMAIN}`)
      - traefik.http.routers.uptime.entrypoints=websecure
      - traefik.http.routers.uptime.tls.certresolver=letsencrypt
      - traefik.http.services.uptime.loadbalancer.server.port=3001
    networks:
      - frontend
      - monitoring

networks:
  frontend:
    name: knvox_frontend
  backend:
    name: knvox_backend
  database:
    name: knvox_database
  storage:
    name: knvox_storage
  monitoring:
    name: knvox_monitoring
  management:
    name: knvox_management

volumes:
  traefik_letsencrypt:
  portainer_data:
  postgres_data:
  redis_data:
  rabbitmq_data:
  minio_data:
  prometheus_data:
  grafana_data:
  loki_data:
  uptime_data:
COMPOSEEOF

echo "[9/9] Validation docker compose..."

docker compose config >/dev/null

echo ""
echo "================================================"
echo " V1.0.1 prête."
echo "================================================"
echo ""
echo "Domaine configuré : ${DOMAIN}"
echo ""
echo "Mots de passe générés dans :"
echo "/opt/knvox-carrier/.env"
echo ""
echo "Prochaine commande :"
echo "docker compose up -d"
echo ""
