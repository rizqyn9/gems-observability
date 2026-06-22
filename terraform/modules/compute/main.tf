# Compute module for LGTM stack
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

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "instance_type" {
  description = "Instance type for compute"
  type        = string
  default     = "n2-standard-4"
}

variable "use_spot" {
  description = "Use spot instances"
  type        = bool
  default     = false
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 100
}

variable "network_id" {
  description = "Network ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}

variable "service_account_email" {
  description = "Service account email"
  type        = string
}

variable "startup_script" {
  description = "Startup script for instance"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Network tags"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Instance labels"
  type        = map(string)
  default     = {}
}

variable "instance_count" {
  description = "Number of instances"
  type        = number
  default     = 1
}

resource "google_compute_instance" "lgtm" {
  count        = var.instance_count
  project      = var.project_id
  name         = "${var.environment}-lgtm-${count.index + 1}"
  machine_type = var.instance_type
  zone         = var.zone

  tags = concat(var.tags, ["lgtm", var.environment])

  labels = merge(var.labels, {
    environment = var.environment
    service     = "lgtm"
  })

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.disk_size_gb
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = var.network_id
    subnetwork = var.subnet_id

    access_config {
      # Ephemeral public IP
    }
  }

  scheduling {
    automatic_restart   = !var.use_spot
    on_host_maintenance = var.use_spot ? "TERMINATE" : "MIGRATE"
    preemptible         = var.use_spot
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  metadata = {
    startup-script = var.startup_script
  }

  lifecycle {
    create_before_destroy = true
  }
}

output "instance_names" {
  description = "Instance names"
  value       = google_compute_instance.lgtm[*].name
}

output "instance_ips" {
  description = "Instance internal IPs"
  value       = google_compute_instance.lgtm[*].network_interface[0].network_ip
}

output "instance_public_ips" {
  description = "Instance public IPs"
  value       = google_compute_instance.lgtm[*].network_interface[0].access_config[0].nat_ip
}

output "instance_ids" {
  description = "Instance IDs"
  value       = google_compute_instance.lgtm[*].id
}
