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
  }
}

provider "google" {
  project = local.project_id
  region  = local.region
}

locals {
  project_id = "mnosedademo"
  region     = "europe-west4"
  vpc_name   = "petshop-vpc"
  http_tag   = "allow-http"
}

# -----------------------------------------------------------------------------
# 2. Networking (VPC and Firewall)
# -----------------------------------------------------------------------------

# Create a custom VPC for the application
resource "google_compute_network" "petshop_vpc" {
  name                    = local.vpc_name
  auto_create_subnetworks = false
}

# Create a subnet in the specified region
resource "google_compute_subnetwork" "petshop_subnet" {
  name          = "petshop-subnet-${local.region}"
  ip_cidr_range = "10.20.0.0/24"
  region        = local.region
  network       = google_compute_network.petshop_vpc.id
}

# Create a firewall rule to allow HTTP traffic to tagged instances
resource "google_compute_firewall" "allow_http" {
  name    = "${local.vpc_name}-allow-http"
  network = google_compute_network.petshop_vpc.name
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.http_tag]
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
    source_image = "projects/${local.project_id}/global/images/family/petshopnode-family"
    auto_delete  = true
    boot         = true
  }

  # Configure networking
  network_interface {
    subnetwork = google_compute_subnetwork.petshop_subnet.id
    # An access_config block is required for external connectivity
    access_config {}
  }

  # Apply the firewall tag
  tags = [local.http_tag]

  lifecycle {
    create_before_destroy = true
  }
}

# Create a regional Managed Instance Group (MIG)
resource "google_compute_region_instance_group_manager" "petshop_mig" {
  name   = "petshop-mig"
  region = local.region

  version {
    instance_template = google_compute_instance_template.petshop_template.id
  }

  base_instance_name = "petshop-vm"
  target_size        = 1
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

  http_check {
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
  description = "The public IP address of the Pet Shop website."
  value       = google_compute_global_forwarding_rule.petshop_forwarding_rule.ip_address
}
