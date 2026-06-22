# Production Single Node - Non-Spot Instance
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

locals {
  environment = "production-single"
  labels = {
    managed_by = "terraform"
    team       = "observability"
  }
}

# Service Account for LGTM instances
resource "google_service_account" "lgtm" {
  project      = var.project_id
  account_id   = "prod-single-lgtm-sa"
  display_name = "LGTM Service Account - Production Single"
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
  network_name = "prod-single-lgtm-vpc"
  subnet_cidr  = "10.1.0.0/24"
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

# Compute - Single Production Instance
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
  instance_count        = 1
  tags                  = ["grafana", "loki", "tempo", "mimir"]
  labels                = local.labels

  startup_script = templatefile("${path.module}/../../scripts/startup.sh", {
    loki_bucket    = module.storage.loki_bucket_name
    tempo_bucket   = module.storage.tempo_bucket_name
    mimir_bucket   = module.storage.mimir_bucket_name
    grafana_bucket = module.storage.grafana_bucket_name
    environment    = local.environment
  })
}

# Static IP for production
resource "google_compute_address" "lgtm" {
  project = var.project_id
  name    = "prod-single-lgtm-ip"
  region  = var.region
}

output "instance_public_ip" {
  description = "Public IP of the LGTM instance"
  value       = module.compute.instance_public_ips[0]
}

output "static_ip" {
  description = "Reserved static IP"
  value       = google_compute_address.lgtm.address
}

output "grafana_url" {
  description = "Grafana URL"
  value       = "http://${module.compute.instance_public_ips[0]}:3000"
}

output "loki_url" {
  description = "Loki URL"
  value       = "http://${module.compute.instance_public_ips[0]}:3100"
}

output "tempo_url" {
  description = "Tempo URL"
  value       = "http://${module.compute.instance_public_ips[0]}:3200"
}

output "mimir_url" {
  description = "Mimir URL"
  value       = "http://${module.compute.instance_public_ips[0]}:9009"
}

output "storage_buckets" {
  description = "GCS buckets for LGTM"
  value       = module.storage.bucket_urls
}
