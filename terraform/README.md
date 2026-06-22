# LGTM Stack Terraform Modules

Infrastructure as Code untuk deployment LGTM (Loki, Grafana, Tempo, Mimir) observability stack di GCP dengan GCS sebagai backend storage.

## Struktur

```
terraform/
├── modules/
│   ├── compute/       # VM instances untuk LGTM stack
│   ├── network/       # VPC, Subnet, Firewall rules
│   └── storage/       # GCS buckets untuk Loki, Tempo, Mimir, Grafana
├── environments/
│   ├── rnd/                    # RnD: Single node spot instance
│   ├── production-single/      # Production: Single node
│   └── production-multi/       # Production: Multi-node HA
└── scripts/
    ├── startup.sh              # Startup script untuk single node
    └── startup-ha.sh           # Startup script untuk HA setup
```

## Skenario Deployment

### 1. RnD (Research & Development)
- **Instance**: 1x n2-standard-4 (spot instance)
- **Storage**: GCS buckets dengan lifecycle 7 hari
- **Use case**: Testing, development, proof of concept
- **Cost**: Minimal (spot pricing)

### 2. Production Single Node
- **Instance**: 1x n2-standard-8 (non-spot)
- **Storage**: GCS buckets dengan lifecycle 30 hari
- **Disk**: 500GB SSD
- **Use case**: Small to medium production workloads
- **Features**: Static IP, monitoring

### 3. Production Multi-Node (High Availability)
- **Instance**: 3x n2-standard-8 (non-spot)
- **Storage**: GCS buckets dengan lifecycle 30 hari
- **Disk**: 500GB SSD per node
- **Use case**: High availability production workloads
- **Features**: 
  - Load balancer untuk Grafana
  - Consul untuk service discovery
  - Replication factor 3
  - Auto-scaling ready

## Komponen LGTM Stack

### Loki (Logs)
- Port: 3100
- Storage: GCS
- Retention: 30 hari (configurable)

### Grafana (Visualization)
- Port: 3000
- Default credentials: admin/admin
- Pre-configured datasources untuk Loki, Tempo, Mimir

### Tempo (Traces)
- Port: 3200
- OTLP: 4317 (gRPC), 4318 (HTTP)
- Storage: GCS

### Mimir (Metrics)
- Port: 9009
- Prometheus compatible
- Storage: GCS

## Prerequisites

1. GCP Project dengan billing enabled
2. Terraform >= 1.5
3. gcloud CLI authenticated
4. Required GCP APIs enabled:
   - Compute Engine API
   - Cloud Storage API
   - Cloud Resource Manager API

## Usage

### 1. Setup GCP Authentication

```bash
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

### 2. Deploy RnD Environment

```bash
cd terraform/environments/rnd
terraform init
terraform plan -var="project_id=YOUR_PROJECT_ID"
terraform apply -var="project_id=YOUR_PROJECT_ID"
```

### 3. Deploy Production Single Node

```bash
cd terraform/environments/production-single
terraform init
terraform plan -var="project_id=YOUR_PROJECT_ID"
terraform apply -var="project_id=YOUR_PROJECT_ID"
```

### 4. Deploy Production Multi-Node HA

```bash
cd terraform/environments/production-multi
terraform init
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="instance_count=3"
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="instance_count=3"
```

## Outputs

Setiap environment akan output:
- Instance public IPs
- Grafana URL
- Loki URL
- Tempo URL
- Mimir URL
- GCS bucket names

### Accessing Services

Setelah deployment selesai (tunggu ~5 menit untuk startup script):

```bash
# Get outputs
terraform output

# Access Grafana
open http://$(terraform output -raw grafana_url)

# Test Loki
curl http://$(terraform output -raw instance_public_ip):3100/ready

# Test Tempo
curl http://$(terraform output -raw instance_public_ip):3200/ready

# Test Mimir
curl http://$(terraform output -raw instance_public_ip):9009/ready
```

## Customization

### Mengubah Instance Type

Edit file `main.tf` di environment yang diinginkan:

```hcl
module "compute" {
  instance_type = "n2-standard-16"  # Sesuaikan dengan kebutuhan
}
```

### Mengubah Storage Lifecycle

Edit file `main.tf`:

```hcl
module "storage" {
  lifecycle_age_days = 60  # Ubah retention period
}
```

### Mengubah Network CIDR

Edit file `main.tf`:

```hcl
module "network" {
  subnet_cidr = "10.10.0.0/24"  # Custom CIDR
}
```

## Monitoring & Maintenance

### Check Service Health

```bash
# SSH ke instance
gcloud compute ssh INSTANCE_NAME --zone=ZONE

# Check docker containers
sudo docker ps

# Check logs
sudo docker logs loki
sudo docker logs tempo
sudo docker logs mimir
sudo docker logs grafana

# Restart services
cd /opt/lgtm
sudo docker-compose restart
```

### Backup & Restore

Data disimpan di GCS buckets dengan versioning enabled. Untuk backup:

```bash
# List backups
gsutil ls gs://PROJECT_ID-ENV-loki/
gsutil ls gs://PROJECT_ID-ENV-tempo/
gsutil ls gs://PROJECT_ID-ENV-mimir/
```

## Cleanup

```bash
# Destroy infrastructure
terraform destroy -var="project_id=YOUR_PROJECT_ID"

# Hapus GCS buckets (optional, HATI-HATI!)
gsutil rm -r gs://PROJECT_ID-ENV-loki
gsutil rm -r gs://PROJECT_ID-ENV-tempo
gsutil rm -r gs://PROJECT_ID-ENV-mimir
gsutil rm -r gs://PROJECT_ID-ENV-grafana
```

## Cost Estimation

### RnD (Spot Instance)
- Compute: ~$30-50/month
- Storage: ~$20/month (depends on volume)
- **Total**: ~$50-70/month

### Production Single
- Compute: ~$200-250/month
- Storage: ~$50-100/month
- **Total**: ~$250-350/month

### Production Multi-Node
- Compute: ~$600-750/month (3 nodes)
- Storage: ~$100-200/month
- Load Balancer: ~$20/month
- **Total**: ~$720-970/month

## Troubleshooting

### Service tidak start
```bash
sudo systemctl status docker
sudo docker-compose -f /opt/lgtm/docker-compose.yml logs
```

### Tidak bisa akses dari internet
Check firewall rules:
```bash
gcloud compute firewall-rules list
```

### GCS permission error
Check service account permissions:
```bash
gcloud projects get-iam-policy PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:*lgtm*"
```

## Security Notes

1. Default Grafana password adalah `admin/admin` - **GANTI SEGERA**
2. Firewall rules membuka port ke 0.0.0.0/0 - sesuaikan dengan IP range internal jika diperlukan
3. Gunakan Cloud IAP atau VPN untuk akses production
4. Enable GCS encryption at rest
5. Setup audit logging untuk compliance

## Next Steps

1. Setup monitoring untuk LGTM stack itu sendiri
2. Configure alerting di Grafana
3. Setup backup automation
4. Implement disaster recovery plan
5. Document dashboards dan queries
6. Setup log forwarding dari aplikasi ke Loki
7. Implement distributed tracing dengan Tempo
8. Configure Prometheus remote write ke Mimir
