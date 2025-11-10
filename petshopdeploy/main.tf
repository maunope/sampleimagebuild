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

# ADDED: Create a DNS A record for the database instance
resource "google_dns_record_set" "db_dns_record" {
  name         = "${local.db_name}.${google_dns_managed_zone.petshop_private_zone.dns_name}"
  managed_zone = google_dns_manåaged_zone.petshop_private_zone.name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_instance.petshop_db_instance.network_interface[0].network_ip]
}

# ADDED: Data source to get the latest image from the petshop database family.
# This will be used to trigger an update when a new image is available.
data "google_compute_image" "latest_petshop_db_image" {
  family  = "custom-mysqlnode-family" # Corrected family name to match Packer output
  project = local.project_id
}

# ADDED: Data source to get the latest image from the petshop node family.
data "google_compute_image" "latest_petshop_node_image" {
  family  = "custom-apachenode-family" # Corrected family name to match Packer output
  project = local.project_id
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
    subnetwork = google_compute_subnetwork.petshop_subnet.id
    # No access_config block to prevent assigning external IPs, complying with org policy.
  }

  # Enable Shielded VM to comply with organization policy.
  shielded_instance_config {
    enable_secure_boot = true
  }

  # Apply the firewall tag
  tags = [local.http_tag]

  # Lifecycle rule to ensure the new instance template is created before the old one is destroyed.
  lifecycle {
    create_before_destroy = true
  }
}

# ADDED: Create a dedicated instance for the MySQL database
resource "google_compute_instance" "petshop_db_instance" {
  name         = local.db_name
  machine_type = "e2-small"
  zone         = "${local.region}-a"

  # Use the latest image from the petshopdatabasenode-family
  boot_disk {
    initialize_params {
      image = data.google_compute_image.latest_petshop_db_image.self_link
    }
    auto_delete = true
  }

  # Configure networking
  network_interface {
    subnetwork = google_compute_subnetwork.petshop_subnet.id
    # No access_config to keep the instance internal
  }

  shielded_instance_config {
    enable_secure_boot = true
  }

  tags = [local.db_tag]

  # ADDED: Lifecycle rule to ensure the new instance is created before the old one is destroyed.
  # This minimizes downtime during an image update.
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
  description = "The public IP address of the Pet Shop website."
  value       = google_compute_global_forwarding_rule.petshop_forwarding_rule.ip_address
}
