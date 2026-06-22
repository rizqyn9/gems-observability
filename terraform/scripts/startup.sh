#!/bin/bash
set -e

# Startup script for single-node LGTM installation
LOKI_BUCKET="${loki_bucket}"
TEMPO_BUCKET="${tempo_bucket}"
MIMIR_BUCKET="${mimir_bucket}"
GRAFANA_BUCKET="${grafana_bucket}"
ENVIRONMENT="${environment}"

# Update system
apt-get update
apt-get install -y docker.io docker-compose curl wget git

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Create directories
mkdir -p /opt/lgtm/{loki,tempo,mimir,grafana}
mkdir -p /etc/lgtm

# Loki configuration
cat > /etc/lgtm/loki-config.yaml <<EOF
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  path_prefix: /loki
  storage:
    gcs:
      bucket_name: $LOKI_BUCKET
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: gcs
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  gcs:
    bucket_name: $LOKI_BUCKET

limits_config:
  retention_period: 720h
  ingestion_rate_mb: 64
  ingestion_burst_size_mb: 128

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: true
  retention_period: 720h
EOF

# Tempo configuration
cat > /etc/lgtm/tempo-config.yaml <<EOF
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        http:
          endpoint: 0.0.0.0:4318
        grpc:
          endpoint: 0.0.0.0:4317

storage:
  trace:
    backend: gcs
    gcs:
      bucket_name: $TEMPO_BUCKET
    wal:
      path: /tmp/tempo/wal
    block:
      version: vParquet4

compactor:
  compaction:
    block_retention: 720h
EOF

# Mimir configuration
cat > /etc/lgtm/mimir-config.yaml <<EOF
multitenancy_enabled: false

server:
  http_listen_port: 9009
  grpc_listen_port: 9095

common:
  storage:
    backend: gcs
    gcs:
      bucket_name: $MIMIR_BUCKET

blocks_storage:
  backend: gcs
  gcs:
    bucket_name: $MIMIR_BUCKET
  tsdb:
    dir: /tmp/mimir/tsdb
  bucket_store:
    sync_dir: /tmp/mimir/tsdb-sync

compactor:
  data_dir: /tmp/mimir/compactor
  deletion_delay: 2h

limits:
  ingestion_rate: 100000
  ingestion_burst_size: 200000
EOF

# Docker Compose file
cat > /opt/lgtm/docker-compose.yml <<EOF
version: '3.8'

services:
  loki:
    image: grafana/loki:latest
    container_name: loki
    ports:
      - "3100:3100"
    volumes:
      - /etc/lgtm/loki-config.yaml:/etc/loki/local-config.yaml
      - /opt/lgtm/loki:/loki
    command: -config.file=/etc/loki/local-config.yaml
    restart: unless-stopped

  tempo:
    image: grafana/tempo:latest
    container_name: tempo
    ports:
      - "3200:3200"
      - "4317:4317"
      - "4318:4318"
    volumes:
      - /etc/lgtm/tempo-config.yaml:/etc/tempo/tempo.yaml
      - /opt/lgtm/tempo:/tmp/tempo
    command: -config.file=/etc/tempo/tempo.yaml
    restart: unless-stopped

  mimir:
    image: grafana/mimir:latest
    container_name: mimir
    ports:
      - "9009:9009"
      - "9090:9090"
    volumes:
      - /etc/lgtm/mimir-config.yaml:/etc/mimir/mimir.yaml
      - /opt/lgtm/mimir:/tmp/mimir
    command: -config.file=/etc/mimir/mimir.yaml
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    volumes:
      - /opt/lgtm/grafana:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_AUTH_ANONYMOUS_ENABLED=false
      - GF_INSTALL_PLUGINS=grafana-clock-panel
    restart: unless-stopped
EOF

# Start LGTM stack
cd /opt/lgtm
docker-compose up -d

# Wait for Grafana to start
sleep 30

# Configure Grafana datasources
cat > /tmp/datasources.yaml <<EOF
apiVersion: 1

datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: false
    jsonData:
      maxLines: 1000

  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    isDefault: false

  - name: Mimir
    type: prometheus
    access: proxy
    url: http://mimir:9009/prometheus
    isDefault: true
    jsonData:
      timeInterval: 30s
EOF

docker cp /tmp/datasources.yaml grafana:/etc/grafana/provisioning/datasources/datasources.yaml
docker restart grafana

echo "LGTM stack installation completed for environment: $ENVIRONMENT"
