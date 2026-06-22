#!/bin/bash
set -e

# Startup script for multi-node HA LGTM installation
LOKI_BUCKET="${loki_bucket}"
TEMPO_BUCKET="${tempo_bucket}"
MIMIR_BUCKET="${mimir_bucket}"
GRAFANA_BUCKET="${grafana_bucket}"
ENVIRONMENT="${environment}"
INSTANCE_COUNT="${instance_count}"

# Get instance metadata
INSTANCE_NAME=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)
INSTANCE_IP=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)
ZONE=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d'/' -f4)

# Update system
apt-get update
apt-get install -y docker.io docker-compose curl wget git consul

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Create directories
mkdir -p /opt/lgtm/{loki,tempo,mimir,grafana}
mkdir -p /etc/lgtm

# Setup Consul for service discovery
cat > /etc/consul.d/consul.hcl <<EOF
datacenter = "dc1"
data_dir = "/opt/consul"
client_addr = "0.0.0.0"
bind_addr = "$INSTANCE_IP"
retry_join = ["production-multi-lgtm-1", "production-multi-lgtm-2", "production-multi-lgtm-3"]
server = false
EOF

systemctl enable consul
systemctl start consul

# Loki HA configuration
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
  replication_factor: 3
  ring:
    kvstore:
      store: consul
      consul:
        host: localhost:8500
    heartbeat_timeout: 1m

memberlist:
  join_members:
    - production-multi-lgtm-1:7946
    - production-multi-lgtm-2:7946
    - production-multi-lgtm-3:7946

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
  ingestion_rate_mb: 128
  ingestion_burst_size_mb: 256

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: true
  retention_period: 720h

ingester:
  lifecycler:
    ring:
      kvstore:
        store: consul
        consul:
          host: localhost:8500
      replication_factor: 3
EOF

# Tempo HA configuration
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
  ring:
    kvstore:
      store: consul
      consul:
        host: localhost:8500

ingester:
  lifecycler:
    ring:
      kvstore:
        store: consul
        consul:
          host: localhost:8500
      replication_factor: 3

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
  ring:
    kvstore:
      store: consul
      consul:
        host: localhost:8500
  compaction:
    block_retention: 720h
EOF

# Mimir HA configuration
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

ingester:
  ring:
    kvstore:
      store: consul
      consul:
        host: localhost:8500
    replication_factor: 3

distributor:
  ring:
    kvstore:
      store: consul
      consul:
        host: localhost:8500

compactor:
  ring:
    kvstore:
      store: consul
      consul:
        host: localhost:8500
  data_dir: /tmp/mimir/compactor
  deletion_delay: 2h

store_gateway:
  sharding_ring:
    kvstore:
      store: consul
      consul:
        host: localhost:8500

limits:
  ingestion_rate: 200000
  ingestion_burst_size: 400000
EOF

# Docker Compose file for HA
cat > /opt/lgtm/docker-compose.yml <<EOF
version: '3.8'

services:
  loki:
    image: grafana/loki:latest
    container_name: loki
    network_mode: host
    volumes:
      - /etc/lgtm/loki-config.yaml:/etc/loki/local-config.yaml
      - /opt/lgtm/loki:/loki
    command: -config.file=/etc/loki/local-config.yaml -target=all
    restart: unless-stopped

  tempo:
    image: grafana/tempo:latest
    container_name: tempo
    network_mode: host
    volumes:
      - /etc/lgtm/tempo-config.yaml:/etc/tempo/tempo.yaml
      - /opt/lgtm/tempo:/tmp/tempo
    command: -config.file=/etc/tempo/tempo.yaml -target=all
    restart: unless-stopped

  mimir:
    image: grafana/mimir:latest
    container_name: mimir
    network_mode: host
    volumes:
      - /etc/lgtm/mimir-config.yaml:/etc/mimir/mimir.yaml
      - /opt/lgtm/mimir:/tmp/mimir
    command: -config.file=/etc/mimir/mimir.yaml -target=all
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
      - GF_DATABASE_TYPE=postgres
    restart: unless-stopped
EOF

# Start LGTM stack
cd /opt/lgtm
docker-compose up -d

# Wait for services to start
sleep 60

# Configure Grafana datasources
cat > /tmp/datasources.yaml <<EOF
apiVersion: 1

datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://localhost:3100
    isDefault: false
    jsonData:
      maxLines: 1000

  - name: Tempo
    type: tempo
    access: proxy
    url: http://localhost:3200
    isDefault: false

  - name: Mimir
    type: prometheus
    access: proxy
    url: http://localhost:9009/prometheus
    isDefault: true
    jsonData:
      timeInterval: 30s
EOF

docker cp /tmp/datasources.yaml grafana:/etc/grafana/provisioning/datasources/datasources.yaml
docker restart grafana

echo "LGTM HA stack installation completed for $INSTANCE_NAME in environment: $ENVIRONMENT"
