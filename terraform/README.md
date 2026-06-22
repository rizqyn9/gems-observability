# LGTM Stack Terraform Modules

Infrastructure as Code for deploying LGTM (Loki, Grafana, Tempo, Mimir) observability stack on GCP with GCS as backend storage.

## Structure

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

## Deployment Scenarios

### 1. RnD (Research & Development)
- **Instance**: 1x n2-standard-4 (spot instance)
- **Storage**: GCS buckets with 7-day lifecycle
- **Use case**: Testing, development, proof of concept
- **Cost**: Minimal (spot pricing)

### 2. Production Single Node
- **Instance**: 1x n2-standard-8 (non-spot)
- **Storage**: GCS buckets with 30-day lifecycle
- **Disk**: 500GB SSD
- **Use case**: Small to medium production workloads
- **Features**: Static IP, monitoring

### 3. Production Multi-Node (High Availability)
- **Instance**: 3x n2-standard-8 (non-spot)
- **Storage**: GCS buckets with 30-day lifecycle
- **Disk**: 500GB SSD per node
- **Use case**: High availability production workloads
- **Features**: 
  - Load balancer for Grafana
  - Consul for service discovery
  - Replication factor 3
  - Auto-scaling ready

## LGTM Stack Components

### Loki (Logs)
- Port: 3100
- Storage: GCS
- Retention: 30 days (configurable)

### Grafana (Visualization)
- Port: 3000
- Default credentials: admin/admin
- Pre-configured datasources for Loki, Tempo, Mimir

### Tempo (Traces)
- Port: 3200
- OTLP: 4317 (gRPC), 4318 (HTTP)
- Storage: GCS

### Mimir (Metrics)
- Port: 9009
- Prometheus compatible
- Storage: GCS

## Prerequisites

1. GCP Project with billing enabled
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

Each environment will output:
- Instance public IPs
- Grafana URL
- Loki URL
- Tempo URL
- Mimir URL
- GCS bucket names

### Accessing Services

After deployment completes (wait ~5 minutes for startup script to finish):

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

### Change Instance Type

Edit the `main.tf` file in your desired environment:

```hcl
module "compute" {
  instance_type = "n2-standard-16"  # Adjust to your needs
}
```

### Change Storage Lifecycle

Edit the `main.tf` file:

```hcl
module "storage" {
  lifecycle_age_days = 60  # Change retention period
}
```

### Change Network CIDR

Edit the `main.tf` file:

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

Data is stored in GCS buckets with versioning enabled. To backup:

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

# Delete GCS buckets (optional, CAUTION!)
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

### Service won't start
```bash
sudo systemctl status docker
sudo docker-compose -f /opt/lgtm/docker-compose.yml logs
```

### Cannot access from internet
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

1. Default Grafana password is `admin/admin` - **CHANGE IMMEDIATELY**
2. Firewall rules open ports to 0.0.0.0/0 - adjust to internal IP range if needed
3. Use Cloud IAP or VPN for production access
4. Enable GCS encryption at rest
5. Setup audit logging for compliance

## Next Steps

1. Setup monitoring for the LGTM stack itself
2. Configure alerting in Grafana
3. Setup backup automation
4. Implement disaster recovery plan
5. Document dashboards and queries
6. Setup log forwarding from applications to Loki
7. Implement distributed tracing with Tempo
8. Configure Prometheus remote write to Mimir
