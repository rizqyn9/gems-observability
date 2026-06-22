# Production Multi-Node - High Availability Setup
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "asia-southeast2"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "asia-southeast2-a"
}

variable "instance_count" {
  description = "Number of LGTM instances for HA"
  type        = number
  default     = 3
}

locals {
  environment = "production-multi"
  labels = {
    managed_by = "terraform"
    team       = "observability"
  }
}

# Service Account for LGTM instances
resource "google_service_account" "lgtm" {
  project      = var.project_id
  account_id   = "prod-multi-lgtm-sa"
  display_name = "LGTM Service Account - Production Multi"
}

resource "google_project_iam_member" "lgtm_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.lgtm.email}"
}

resource "google_project_iam_member" "lgtm_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.lgtm.email}"
}

resource "google_project_iam_member" "lgtm_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.lgtm.email}"
}

# Network
module "network" {
  source = "../../modules/network"

  project_id   = var.project_id
  region       = var.region
  environment  = local.environment
  network_name = "prod-multi-lgtm-vpc"
  subnet_cidr  = "10.2.0.0/24"
}

# Storage
module "storage" {
  source = "../../modules/storage"

  project_id         = var.project_id
  region             = var.region
  environment        = local.environment
  storage_class      = "STANDARD"
  lifecycle_age_days = 30
  labels             = local.labels
}

# Compute - Multiple Instances for HA
module "compute" {
  source = "../../modules/compute"

  project_id            = var.project_id
  region                = var.region
  zone                  = var.zone
  environment           = local.environment
  instance_type         = "n2-standard-8"
  use_spot              = false
  disk_size_gb          = 500
  network_id            = module.network.network_id
  subnet_id             = module.network.subnet_id
  service_account_email = google_service_account.lgtm.email
  instance_count        = var.instance_count
  tags                  = ["grafana", "loki", "tempo", "mimir"]
  labels                = local.labels

  startup_script = templatefile("${path.module}/../../scripts/startup-ha.sh", {
    loki_bucket    = module.storage.loki_bucket_name
    tempo_bucket   = module.storage.tempo_bucket_name
    mimir_bucket   = module.storage.mimir_bucket_name
    grafana_bucket = module.storage.grafana_bucket_name
    environment    = local.environment
    instance_count = var.instance_count
  })
}

# Load Balancer for Grafana
resource "google_compute_global_address" "grafana" {
  project = var.project_id
  name    = "prod-multi-grafana-ip"
}

resource "google_compute_health_check" "grafana" {
  project = var.project_id
  name    = "prod-multi-grafana-health"

  http_health_check {
    port         = 3000
    request_path = "/api/health"
  }

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
}

resource "google_compute_instance_group" "lgtm" {
  project   = var.project_id
  name      = "prod-multi-lgtm-ig"
  zone      = var.zone
  instances = module.compute.instance_ids

  named_port {
    name = "grafana"
    port = 3000
  }

  named_port {
    name = "loki"
    port = 3100
  }

  named_port {
    name = "tempo"
    port = 3200
  }

  named_port {
    name = "mimir"
    port = 9009
  }
}

resource "google_compute_backend_service" "grafana" {
  project       = var.project_id
  name          = "prod-multi-grafana-backend"
  health_checks = [google_compute_health_check.grafana.id]
  port_name     = "grafana"
  protocol      = "HTTP"
  timeout_sec   = 30

  backend {
    group           = google_compute_instance_group.lgtm.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  log_config {
    enable = true
  }
}

resource "google_compute_url_map" "grafana" {
  project         = var.project_id
  name            = "prod-multi-grafana-lb"
  default_service = google_compute_backend_service.grafana.id
}

resource "google_compute_target_http_proxy" "grafana" {
  project = var.project_id
  name    = "prod-multi-grafana-proxy"
  url_map = google_compute_url_map.grafana.id
}

resource "google_compute_global_forwarding_rule" "grafana" {
  project    = var.project_id
  name       = "prod-multi-grafana-rule"
  target     = google_compute_target_http_proxy.grafana.id
  port_range = "80"
  ip_address = google_compute_global_address.grafana.address
}

output "instance_names" {
  description = "Names of all LGTM instances"
  value       = module.compute.instance_names
}

output "instance_public_ips" {
  description = "Public IPs of all LGTM instances"
  value       = module.compute.instance_public_ips
}

output "grafana_lb_ip" {
  description = "Load Balancer IP for Grafana"
  value       = google_compute_global_address.grafana.address
}

output "grafana_url" {
  description = "Grafana URL via Load Balancer"
  value       = "http://${google_compute_global_address.grafana.address}"
}

output "storage_buckets" {
  description = "GCS buckets for LGTM"
  value       = module.storage.bucket_urls
}

output "instance_group" {
  description = "Instance group for LGTM cluster"
  value       = google_compute_instance_group.lgtm.id
}
