# Storage module for LGTM stack (GCS buckets)
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

variable "storage_class" {
  description = "Storage class for buckets"
  type        = string
  default     = "STANDARD"
}

variable "lifecycle_age_days" {
  description = "Days before transitioning to coldline"
  type        = number
  default     = 30
}

variable "labels" {
  description = "Labels for buckets"
  type        = map(string)
  default     = {}
}

# Loki bucket for logs
resource "google_storage_bucket" "loki" {
  project       = var.project_id
  name          = "${var.project_id}-${var.environment}-loki"
  location      = var.region
  storage_class = var.storage_class
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.lifecycle_age_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  labels = merge(var.labels, {
    environment = var.environment
    service     = "loki"
  })
}

# Tempo bucket for traces
resource "google_storage_bucket" "tempo" {
  project       = var.project_id
  name          = "${var.project_id}-${var.environment}-tempo"
  location      = var.region
  storage_class = var.storage_class
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.lifecycle_age_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  labels = merge(var.labels, {
    environment = var.environment
    service     = "tempo"
  })
}

# Mimir bucket for metrics
resource "google_storage_bucket" "mimir" {
  project       = var.project_id
  name          = "${var.project_id}-${var.environment}-mimir"
  location      = var.region
  storage_class = var.storage_class
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.lifecycle_age_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  labels = merge(var.labels, {
    environment = var.environment
    service     = "mimir"
  })
}

# Grafana bucket for dashboards and configurations
resource "google_storage_bucket" "grafana" {
  project       = var.project_id
  name          = "${var.project_id}-${var.environment}-grafana"
  location      = var.region
  storage_class = var.storage_class
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  labels = merge(var.labels, {
    environment = var.environment
    service     = "grafana"
  })
}

output "loki_bucket_name" {
  description = "Loki bucket name"
  value       = google_storage_bucket.loki.name
}

output "tempo_bucket_name" {
  description = "Tempo bucket name"
  value       = google_storage_bucket.tempo.name
}

output "mimir_bucket_name" {
  description = "Mimir bucket name"
  value       = google_storage_bucket.mimir.name
}

output "grafana_bucket_name" {
  description = "Grafana bucket name"
  value       = google_storage_bucket.grafana.name
}

output "bucket_urls" {
  description = "All bucket URLs"
  value = {
    loki    = google_storage_bucket.loki.url
    tempo   = google_storage_bucket.tempo.url
    mimir   = google_storage_bucket.mimir.url
    grafana = google_storage_bucket.grafana.url
  }
}
