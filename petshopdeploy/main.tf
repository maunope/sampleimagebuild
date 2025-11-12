
# Terraform configuration to deploy the Pet Shop application

# -----------------------------------------------------------------------------
# 1. Configuration and Providers
# -----------------------------------------------------------------------------
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.20"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  # ADDED: Configure the GCS backend for storing Terraform state.
  # The bucket name will be passed in during the 'terraform init' step.
  backend "gcs" {
    prefix = "petshop-deploy"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

//todo move this to a shared locals.tf
variable "project_id" {
  description = "The Google Cloud project ID to deploy resources into."
  type        = string
  default     = "dummy"
}
variable "region" {
  description = "The Google Cloud region to deploy resources into."
  type        = string
  default     = "europe-west4"
}
variable "db_username" {
  description = "The username for the Pet Shop database."
  type        = string
  default     = "petshopuser"
}
locals {
  vpc_name      = "petshop-vpc"
  db_name       = "petshop-db"
  dns_zone_name = "petshop-private-zone"
  dns_name      = "petshop.internal."
  http_tag      = "allow-http"
  db_tag        = "allow-mysql"
}

# -----------------------------------------------------------------------------
# Logging Configuration
# -----------------------------------------------------------------------------

# ADDED: Manage the default logging sink to add an exclusion for health checks.
resource "google_logging_project_sink" "default_sink_exclusion" {
  name    = "_Default"
  project = var.project_id

  # This must be set to the destination of the default sink to manage it.
  destination = "logging.googleapis.com/projects/${var.project_id}/locations/global/buckets/_Default"

  exclusions {
    name        = "exclude-gcp-health-checks"
    description = "Exclude logs from Google Cloud health checks to reduce noise."
    filter      = "httpRequest.userAgent=\"GoogleHC/1.0\""
  }
}

# -----------------------------------------------------------------------------
# Secret Manager for DB Credentials
# -----------------------------------------------------------------------------

# ADDED: Create a secret to hold the database credentials
resource "google_secret_manager_secret" "db_credentials" {
  secret_id = "petshop-db-credentials"
  project   = var.project_id

  replication {
    auto {} # CORRECTED: Used 'auto {}' for automatic replication
  }
}

# ADDED: Generate a random password for the database.
# This password will be stored in the Terraform state but not in the code.
resource "random_password" "db_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ADDED: Add a version to the secret with the database credentials
resource "google_secret_manager_secret_version" "db_credentials_version" {
  secret = google_secret_manager_secret.db_credentials.id
  secret_data = jsonencode({
    # Use the variable for username and the random value for password
    username = var.db_username
    password = random_password.db_password.result
  })
}

# ADDED: Create a separate secret for the database root user.
resource "google_secret_manager_secret" "db_root_credentials" {
  secret_id = "petshop-db-root-credentials"
  project   = var.project_id

  replication {
    auto {}
  }
}

# ADDED: Generate a random password for the root user.
resource "random_password" "db_root_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ADDED: Add a version to the root secret with the username 'root' and the random password.
resource "google_secret_manager_secret_version" "db_root_credentials_version" {
  secret = google_secret_manager_secret.db_root_credentials.id
  secret_data = jsonencode({
    username = "root"
    password = random_password.db_root_password.result
  })
}
# -----------------------------------------------------------------------------
# Application Service Account
# -----------------------------------------------------------------------------

# ADDED: Create a dedicated service account for the Pet Shop application instances.
resource "google_service_account" "petshop_sa" {
  account_id   = "petshopsa"
  display_name = "Pet Shop Application Service Account"
  project      = var.project_id
}

# ADDED: Grant the new service account the minimum necessary roles for its function.
resource "google_project_iam_member" "petshop_sa_minimal_roles" {
  for_each = toset([
    "roles/logging.logWriter",       # To write logs
    "roles/monitoring.metricWriter", # To write metrics
  ])
  project = var.project_id
  role    = each.key
  member  = google_service_account.petshop_sa.member
}
# ADDED: Grant the new service account access to the database credentials secret.
resource "google_secret_manager_secret_iam_member" "petshop_sa_secret_accessor" {
  project   = google_secret_manager_secret.db_credentials.project
  secret_id = google_secret_manager_secret.db_credentials.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.petshop_sa.member

  depends_on = [google_secret_manager_secret_version.db_credentials_version]
}

# ADDED: Create a dedicated service account for the Pet Shop database instance.
resource "google_service_account" "petshop_db_sa" {
  account_id   = "petshopdbsa"
  display_name = "Pet Shop Database Service Account"
  project      = var.project_id
}

# ADDED: Grant the database service account the minimum necessary roles.
resource "google_project_iam_member" "petshop_db_sa_minimal_roles" {
  for_each = toset([
    "roles/logging.logWriter",       # To write logs
    "roles/monitoring.metricWriter", # To write metrics
  ])
  project = var.project_id
  role    = each.key
  member  = google_service_account.petshop_db_sa.member
}

# ADDED: Grant the database service account access to its own credentials secret.
# This is required for the startup script to fetch the password.
resource "google_secret_manager_secret_iam_member" "petshop_db_sa_secret_accessor" {
  project   = google_secret_manager_secret.db_credentials.project
  secret_id = google_secret_manager_secret.db_credentials.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.petshop_db_sa.member

  depends_on = [google_secret_manager_secret_version.db_credentials_version]
}

# ADDED: Grant the database service account access to the ROOT credentials secret.
# This is required for the startup script to set the root password.
resource "google_secret_manager_secret_iam_member" "petshop_db_sa_root_secret_accessor" {
  project   = google_secret_manager_secret.db_root_credentials.project
  secret_id = google_secret_manager_secret.db_root_credentials.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.petshop_db_sa.member

  depends_on = [google_secret_manager_secret_version.db_root_credentials_version]
}

# ADDED: Create a DNS A record for the database instance
resource "google_dns_record_set" "db_dns_record" {
  name         = "${local.db_name}.${data.terraform_remote_state.foundation.outputs.dns_name}"
  managed_zone = data.terraform_remote_state.foundation.outputs.dns_zone_name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_instance.petshop_db_instance.network_interface[0].network_ip]
}

# -----------------------------------------------------------------------------
# 3. Instance Template and Managed Instance Group (MIG)
# -----------------------------------------------------------------------------

# Create an instance template using the final Pet Shop image
resource "google_compute_instance_template" "petshop_template" {
  name_prefix  = "petshop-instance-template-"
  machine_type = "e2-small"

  # Use the latest image from the petshopnode-family
  disk {
    source_image = data.google_compute_image.latest_petshop_node_image.self_link
    auto_delete  = true
    boot         = true
  }

  # Configure networking
  network_interface {
    subnetwork = data.terraform_remote_state.foundation.outputs.subnet_id
    # No access_config block to prevent assigning external IPs, complying with org policy.
  }

  # FIXED: Assign the dedicated service account with the full cloud-platform scope URI.
  service_account {
    email = google_service_account.petshop_sa.email
    # CORRECTED: Added the full set of default scopes in addition to cloud-platform to ensure all APIs are accessible.
    # While cloud-platform should be sufficient, this provides a more robust set of permissions.
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/userinfo.email",
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.full_control",
    ]
  }

  # Enable Shielded VM to comply with organization policy.
  shielded_instance_config {
    enable_secure_boot = true
  }

  # Apply the firewall tag
  tags = [data.terraform_remote_state.foundation.outputs.http_tag]

  # Lifecycle rule to ensure the new instance template is created before the old one is destroyed.
  lifecycle {
    create_before_destroy = true
  }
}

# ADDED: Create a dedicated instance for the MySQL database
resource "google_compute_instance" "petshop_db_instance" {
  name         = local.db_name
  machine_type = "e2-small"
  zone         = "${var.region}-a"

  # Use the latest image from the petshopdatabasenode-family
  boot_disk {
    initialize_params {
      image = data.google_compute_image.latest_petshop_db_image.self_link
    }
    auto_delete = true
  }

  # FIXED: Assign the dedicated service account with the full cloud-platform scope URI.
  service_account {
    email = google_service_account.petshop_db_sa.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/userinfo.email",
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.full_control",
    ]
  }

  # Configure networking
  network_interface {
    subnetwork = data.terraform_remote_state.foundation.outputs.subnet_id
    # No access_config to keep the instance internal
  }

  shielded_instance_config {
    enable_secure_boot = true
  }

  tags = [data.terraform_remote_state.foundation.outputs.db_tag]

  # FIXED: Removed create_before_destroy for fixed-name instance to avoid "already exists" error.
  # This will cause brief downtime during database instance updates.
  lifecycle {
  }
}

# Create a regional Managed Instance Group (MIG)
resource "google_compute_region_instance_group_manager" "petshop_mig" {
  name   = "petshop-mig"
  region = var.region

  version {
    instance_template = google_compute_instance_template.petshop_template.id
  }

  base_instance_name = "petshop-vm"
  target_size        = 2

  # ADDED: Map the port name used by the backend service to a port number.
  named_port {
    name = "http"
    port = 80
  }
}

# -----------------------------------------------------------------------------
# 4. HTTP Load Balancer
# -----------------------------------------------------------------------------

# Create a health check for the load balancer
resource "google_compute_health_check" "http_health_check" {
  name                = "petshop-http-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port         = 80
    request_path = "/"
  }
}

# Create the backend service
resource "google_compute_backend_service" "petshop_backend" {
  name                  = "petshop-backend-service"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 10
  health_checks         = [google_compute_health_check.http_health_check.id]

  backend {
    group = google_compute_region_instance_group_manager.petshop_mig.instance_group
  }
}

# Create the URL map to route all traffic to the backend
resource "google_compute_url_map" "petshop_url_map" {
  name            = "petshop-lb-url-map"
  default_service = google_compute_backend_service.petshop_backend.id
}

# Create the target HTTP proxy
resource "google_compute_target_http_proxy" "petshop_proxy" {
  name    = "petshop-target-proxy"
  url_map = google_compute_url_map.petshop_url_map.id
}

# Create the global forwarding rule (the public IP address)
resource "google_compute_global_forwarding_rule" "petshop_forwarding_rule" {
  name                  = "petshop-forwarding-rule"
  target                = google_compute_target_http_proxy.petshop_proxy.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL"
}

# -----------------------------------------------------------------------------
# 5. Outputs
# -----------------------------------------------------------------------------

output "website_ip" {
  description = "the public IP address of the Pet Shop website."
  value       = google_compute_global_forwarding_rule.petshop_forwarding_rule.ip_address
}

##
