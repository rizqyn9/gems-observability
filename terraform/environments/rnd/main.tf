# RnD Environment - Single Node Spot Instance
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
  environment = "rnd"
  labels = {
    managed_by = "terraform"
    team       = "observability"
  }
}

# Service Account for LGTM instances
resource "google_service_account" "lgtm" {
  project      = var.project_id
  account_id   = "${local.environment}-lgtm-sa"
  display_name = "LGTM Service Account - RnD"
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

# Network
module "network" {
  source = "../../modules/network"

  project_id   = var.project_id
  region       = var.region
  environment  = local.environment
  network_name = "${local.environment}-lgtm-vpc"
  subnet_cidr  = "10.0.1.0/24"
}

# Storage
module "storage" {
  source = "../../modules/storage"

  project_id         = var.project_id
  region             = var.region
  environment        = local.environment
  storage_class      = "STANDARD"
  lifecycle_age_days = 7
  labels             = local.labels
}

# Compute - Single Spot Instance
module "compute" {
  source = "../../modules/compute"

  project_id            = var.project_id
  region                = var.region
  zone                  = var.zone
  environment           = local.environment
  instance_type         = "n2-standard-4"
  use_spot              = true
  disk_size_gb          = 100
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

output "instance_public_ip" {
  description = "Public IP of the LGTM instance"
  value       = module.compute.instance_public_ips[0]
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
