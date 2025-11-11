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
  # ADDED: Configure the GCS backend for storing Terraform state.
  # The bucket name will be passed in during the 'terraform init' step.
  backend "gcs" {
    prefix = "petshop-foundation"
  }
}

provider "google" {
  project = local.project_id
  region  = local.region
}

locals {
  project_id    = "mnosedademo"
  region        = "europe-west4"
  vpc_name      = "petshop-vpc"
  db_name       = "petshop-db"
  dns_zone_name = "petshop-private-zone"
  dns_name      = "petshop.internal."
  http_tag      = "allow-http"
  db_tag        = "allow-mysql"
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

# ADDED: Create a firewall rule to allow internal MySQL traffic
resource "google_compute_firewall" "allow_mysql_internal" {
  name    = "${local.vpc_name}-allow-mysql-internal"
  network = google_compute_network.petshop_vpc.name
  allow {
    protocol = "tcp"
    ports    = ["3306"]
  }
  # Only allow traffic from within the same subnet
  source_ranges = [google_compute_subnetwork.petshop_subnet.ip_cidr_range]
  # Apply this rule only to instances with the 'allow-mysql' tag
  target_tags = [local.db_tag]
}

# ADDED: Create a router for the NAT gateway
resource "google_compute_router" "petshop_router" {
  name    = "petshop-router"
  region  = google_compute_subnetwork.petshop_subnet.region
  network = google_compute_network.petshop_vpc.id
}

# ADDED: Create the Cloud NAT gateway to allow egress traffic from the instances
resource "google_compute_router_nat" "petshop_nat" {
  name                               = "petshop-nat-gateway"
  router                             = google_compute_router.petshop_router.name
  region                             = google_compute_router.petshop_router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.petshop_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# -----------------------------------------------------------------------------
# 3. Cloud DNS Private Zone
# -----------------------------------------------------------------------------

# ADDED: Create a private DNS zone for service discovery
resource "google_dns_managed_zone" "petshop_private_zone" {
  name        = local.dns_zone_name
  dns_name    = local.dns_name
  description = "Private DNS zone for the Petshop application"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.petshop_vpc.id
    }
  }
}
