# Network module for LGTM stack
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "asia-southeast2"
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "network_name" {
  description = "VPC network name"
  type        = string
}

variable "subnet_cidr" {
  description = "Subnet CIDR range"
  type        = string
  default     = "10.0.0.0/24"
}

# VPC Network
resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = var.network_name
  auto_create_subnetworks = false
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  project       = var.project_id
  name          = "${var.network_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id

  private_ip_google_access = true
}

# Firewall rules for LGTM stack
resource "google_compute_firewall" "allow_internal" {
  project = var.project_id
  name    = "${var.network_name}-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["lgtm"]
}

# Grafana UI
resource "google_compute_firewall" "allow_grafana" {
  project = var.project_id
  name    = "${var.network_name}-allow-grafana"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["lgtm", "grafana"]
}

# Loki ingestion
resource "google_compute_firewall" "allow_loki" {
  project = var.project_id
  name    = "${var.network_name}-allow-loki"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["3100"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["lgtm", "loki"]
}

# Tempo ingestion
resource "google_compute_firewall" "allow_tempo" {
  project = var.project_id
  name    = "${var.network_name}-allow-tempo"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["3200", "4317", "4318"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["lgtm", "tempo"]
}

# Mimir/Prometheus
resource "google_compute_firewall" "allow_mimir" {
  project = var.project_id
  name    = "${var.network_name}-allow-mimir"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["9009", "9090"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["lgtm", "mimir"]
}

# SSH access
resource "google_compute_firewall" "allow_ssh" {
  project = var.project_id
  name    = "${var.network_name}-allow-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["lgtm"]
}

# Cloud NAT for outbound traffic
resource "google_compute_router" "router" {
  project = var.project_id
  name    = "${var.network_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  project                            = var.project_id
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

output "network_id" {
  description = "VPC network ID"
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "subnet_id" {
  description = "Subnet ID"
  value       = google_compute_subnetwork.subnet.id
}

output "subnet_name" {
  description = "Subnet name"
  value       = google_compute_subnetwork.subnet.name
}
