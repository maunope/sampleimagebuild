# -----------------------------------------------------------------------------
# 1. Configuration, Providers, and Variables
# -----------------------------------------------------------------------------
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.20"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.20"
    }
  }
}

# ADDED: Explicit provider configuration. This tells Terraform how to
# configure and use the providers declared above.
provider "google" {
  project = var.project_id
}

provider "google-beta" {
  project = var.project_id
  alias   = "beta"
}


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
  github_owner                     = "maunope"
  github_repo                      = "sampleimagebuild"
  debian_ops_agent_image_name      = "debian-ops-agent-image"
  apache_node_image_name           = "apache-node-image"
  petshop_node_image_name          = "petshop-node-image"
  mysql_node_image_name            = "mysql-node-image"
  petshop_database_node_image_name = "petshop-database-node-image"
}

# -----------------------------------------------------------------------------
# 2. API and Service Enablement
# -----------------------------------------------------------------------------

# Pre-enable the Compute Engine API before anything else to ensure dependent resources can be created.
resource "google_project_service" "compute_api" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "enabled_apis" {
  for_each = toset([
    "cloudbuild.googleapis.com",
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "servicenetworking.googleapis.com", # Required for VPC peering for the private pool
    # ADDED: APIs required for the petshopdeploy stage
    "logging.googleapis.com",
    "secretmanager.googleapis.com",
  ])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false

  depends_on = [google_project_service.compute_api]
}

# -----------------------------------------------------------------------------
# 3. Networking (VPC, Subnet, NAT)
# -----------------------------------------------------------------------------

# Create a custom VPC for the build environment
resource "google_compute_network" "build_vpc" {
  project                 = var.project_id
  name                    = "packer-build-vpc"
  auto_create_subnetworks = false
  # Explicitly depend on the Compute API being enabled.
  depends_on = [
    google_project_service.compute_api
  ]
}

# Create a subnet in the specified region
resource "google_compute_subnetwork" "build_subnet" {
  project                  = var.project_id
  name                     = "packer-build-subnet"
  ip_cidr_range            = "10.10.0.0/24"
  region                   = var.region
  network                  = google_compute_network.build_vpc.id
  private_ip_google_access = true
}

# Reserve an IP range for the Service Networking API, required for the private pool
resource "google_compute_global_address" "private_service_access_range" {
  project       = var.project_id
  name          = "private-service-access-for-packer-pool"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.build_vpc.id
}

# Establish the VPC peering connection for the private pool
resource "google_service_networking_connection" "private_service_access_connection" {
  network                 = google_compute_network.build_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_access_range.name]
  depends_on              = [google_project_service.enabled_apis]
}

# Create a router for the NAT gateway
resource "google_compute_router" "build_router" {
  project = var.project_id
  name    = "packer-build-router"
  region  = var.region
  network = google_compute_network.build_vpc.id
}

# Create the Cloud NAT gateway to allow egress traffic from the private pool
resource "google_compute_router_nat" "build_nat" {
  project                            = var.project_id
  name                               = "packer-build-nat-gateway"
  router                             = google_compute_router.build_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.build_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}


resource "google_compute_firewall" "allow_ssh_from_anywhere" {
  project = var.project_id
  name    = "packer-build-vpc-allow-ssh"
  network = google_compute_network.build_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  description   = "Allow SSH access from anywhere for Packer builds"
}

# -----------------------------------------------------------------------------
# 4. Cloud Build Private Worker Pool
# -----------------------------------------------------------------------------


resource "google_cloudbuild_worker_pool" "packer_private_pool" {
  name     = "packer_private_pool"
  location = var.region
  project  = var.project_id
  worker_config {
    disk_size_gb   = 100
    machine_type   = "e2-standard-4"
    no_external_ip = false
  }
  network_config {
    peered_network          = google_compute_network.build_vpc.id
    peered_network_ip_range = "/29"
  }
  depends_on = [google_service_networking_connection.private_service_access_connection]
}

# -----------------------------------------------------------------------------
# 5. Service Accounts and IAM Permissions
# -----------------------------------------------------------------------------

# Get the default Cloud Build Service Account identity
data "google_project" "project" {
  project_id = var.project_id
}

locals {
  cloudbuild_sa = "service-${data.google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

# Grant required roles to the default Cloud Build Service Account
resource "google_project_iam_member" "cloudbuild_sa_roles" {
  for_each = toset([
    "roles/cloudbuild.builds.builder",         // Cloud Build Service Account
    "roles/logging.logWriter",                 // Logs Writer
    "roles/serviceusage.serviceUsageConsumer", // Service Usage Consumer
    "roles/storage.objectCreator",             // Storage Object Creator
  ])
  project    = var.project_id
  role       = each.key
  member     = "serviceAccount:${local.cloudbuild_sa}"
  depends_on = [google_project_service.enabled_apis]
}

# Create a dedicated service account for the Packer build trigger
resource "google_service_account" "packer_builder_sa" {
  project      = var.project_id
  account_id   = "packer-builder"
  display_name = "Packer Image Builder Service Account"
}

# Grant required roles to the Packer builder service account
resource "google_project_iam_member" "packer_builder_sa_roles" {
  for_each = toset([
    # Original roles for Packer and basic TF state management
    "roles/cloudbuild.builds.builder",
    "roles/compute.admin",
    "roles/compute.imageUser", # Compute Image User
    "roles/iam.serviceAccountUser",
    "roles/storage.admin",
    # Roles for managing specific resources in the petshop deployment
    "roles/dns.admin",
    "roles/logging.configWriter",
    "roles/logging.logWriter", # Logs Writer
    "roles/secretmanager.admin",
    "roles/secretmanager.secretAccessor", # Secret Manager Secret Accessor
    # ADDED: Role required for the petshopdeploy stage to create other service accounts
    "roles/iam.serviceAccountAdmin",
    # ADDED: Role required to grant IAM permissions at the project level (for foundation).
    "roles/resourcemanager.projectIamAdmin",
    # Add Editor role on top to ensure all permissions
    "roles/editor"
  ])
  project = var.project_id
  role    = each.key
  member  = google_service_account.packer_builder_sa.member
}

# ADDED: Grant the default Compute Engine service account permission to use custom images.
# This is critical for Managed Instance Groups to be able to create instances from your images.
data "google_compute_default_service_account" "default" {
  project = var.project_id
}

resource "google_project_iam_member" "compute_sa_image_user" {
  project    = var.project_id
  role       = "roles/compute.imageUser"
  member     = "serviceAccount:${data.google_compute_default_service_account.default.email}"
  depends_on = [google_project_service.enabled_apis]
}

# Grant Editor role to a specific user
resource "google_project_iam_member" "editor_for_lucace" {
  project = var.project_id
  role    = "roles/editor"
  member  = "user:lucace@mnoseda.altostrat.com"
}

# Grant Browser role to a specific user on the organization
resource "google_organization_iam_member" "browser_for_lucace_on_org" {
  org_id = "806931298675"
  role   = "roles/browser"
  member = "user:lucace@mnoseda.altostrat.com"
}


# -----------------------------------------------------------------------------
# 6. GitHub Connection and Cloud Build Trigger
# -----------------------------------------------------------------------------

# Create a connection to GitHub
# Create a trigger that fires on commits to the main branch
resource "google_cloudbuild_trigger" "github_trigger" {
  project         = var.project_id
  location        = var.region
  name            = "packer-image-builder-on-main-commit"
  description     = "Triggers build on commit to main branch of ${local.github_repo}"
  service_account = google_service_account.packer_builder_sa.id

  # ADDED: Only trigger for changes in the 'customimage' folder.
  included_files = ["customimage/**"]
  filename       = "customimage/cloudbuild.yaml" // Assumes cloudbuild.yaml is in the root of the repo

  # REVERTED: Use 1st generation github block for a simpler connection.
  # This requires authorizing the Cloud Build GitHub App in your repository settings.
  github {
    owner = local.github_owner
    name  = local.github_repo
    push {
      branch = "^main$" // Regex for an exact match on the 'main' branch
    }
  }

  substitutions = {
    _GCP_PROJECT = var.project_id
    _IMAGE_NAME  = local.debian_ops_agent_image_name
    _REGION      = var.region
    _ZONE        = "${var.region}-a"
  }

  depends_on = [
    google_project_iam_member.packer_builder_sa_roles,
    google_cloudbuild_worker_pool.packer_private_pool
  ]
}

# ADDED: A new trigger for the MySQL image build.
resource "google_cloudbuild_trigger" "mysql_node_trigger" {
  project         = var.project_id
  location        = var.region
  name            = "packer-mysql-image-builder-on-commit"
  description     = "Triggers build on commit to mysqlnode folder"
  service_account = google_service_account.packer_builder_sa.id

  # Only trigger for changes in the 'mysqlnode' folder.
  included_files = ["mysqlnode/**"]
  filename       = "mysqlnode/cloudbuild.yaml"

  github {
    owner = local.github_owner
    name  = local.github_repo
    push {
      branch = "^main$" // Regex for an exact match on the 'main' branch
    }
  }

  substitutions = {
    _GCP_PROJECT = var.project_id
    _IMAGE_NAME  = local.mysql_node_image_name
    _REGION      = var.region
    _ZONE        = "${var.region}-a"
  }

  depends_on = [
    google_project_iam_member.packer_builder_sa_roles,
    google_cloudbuild_worker_pool.packer_private_pool
  ]
}

# ADDED: A new trigger for the Petshop Database image build.
resource "google_cloudbuild_trigger" "petshop_database_node_trigger" {
  project         = var.project_id
  location        = var.region
  name            = "packer-petshop-database-image-builder-on-commit"
  description     = "Triggers build on commit to petshopdatabasenode folder"
  service_account = google_service_account.packer_builder_sa.id

  # Only trigger for changes in the 'petshopdatabasenode' folder.
  included_files = ["petshopdatabasenode/**"]
  filename       = "petshopdatabasenode/cloudbuild.yaml"

  github {
    owner = local.github_owner
    name  = local.github_repo
    push {
      branch = "^main$" // Regex for an exact match on the 'main' branch
    }
  }

  substitutions = {
    _GCP_PROJECT = var.project_id
    _IMAGE_NAME  = local.petshop_database_node_image_name
    _REGION      = var.region
    _ZONE        = "${var.region}-a" # Pass the zone to the build
  }

  depends_on = [
    google_project_iam_member.packer_builder_sa_roles,
    google_cloudbuild_worker_pool.packer_private_pool
  ]
}

# ADDED: A new trigger for the Pet Shop application image build.
resource "google_cloudbuild_trigger" "petshop_node_trigger" {
  project         = var.project_id
  location        = var.region
  name            = "packer-petshop-image-builder-on-commit"
  description     = "Triggers build on commit to petshopnode folder"
  service_account = google_service_account.packer_builder_sa.id

  # MODIFIED: Trigger for changes in the 'petshopnode' OR 'website' folders.
  included_files = ["petshopnode/**", "website/**"]
  filename       = "petshopnode/cloudbuild.yaml"

  github {
    owner = local.github_owner
    name  = local.github_repo
    push {
      branch = "^main$" // Regex for an exact match on the 'main' branch
    }
  }

  substitutions = {
    _GCP_PROJECT = var.project_id
    _IMAGE_NAME  = local.petshop_node_image_name
    _REGION      = var.region
    _ZONE        = "${var.region}-a"
  }

  depends_on = [
    google_project_iam_member.packer_builder_sa_roles,
    google_cloudbuild_worker_pool.packer_private_pool
  ]
}


# ADDED: A new trigger for the Apache image build.
resource "google_cloudbuild_trigger" "apache_node_trigger" {
  project         = var.project_id
  location        = var.region
  name            = "packer-apache-image-builder-on-commit"
  description     = "Triggers build on commit to apachenode folder"
  service_account = google_service_account.packer_builder_sa.id

  # Only trigger for changes in the 'apachenode' folder.
  included_files = ["apachenode/**"]
  filename       = "apachenode/cloudbuild.yaml"

  github {
    owner = local.github_owner
    name  = local.github_repo
    push {
      branch = "^main$" // Regex for an exact match on the 'main' branch
    }
  }

  substitutions = {
    _GCP_PROJECT = var.project_id
    _IMAGE_NAME  = local.apache_node_image_name
    _REGION      = var.region
    _ZONE        = "${var.region}-a"
  }

  depends_on = [
    google_project_iam_member.packer_builder_sa_roles,
    google_cloudbuild_worker_pool.packer_private_pool
  ]
}

# ADDED: A new trigger for applying Terraform configuration.
resource "google_cloudbuild_trigger" "terraform_apply_trigger" {
  project         = var.project_id
  location        = var.region
  name            = "terraform-apply-on-commit"
  description     = "Triggers Terraform apply on commit to petshopdeploy folder"
  service_account = google_service_account.packer_builder_sa.id # For simplicity, reusing the packer SA.

  # Only trigger for changes in the 'petshopdeploy' folder.
  included_files = ["petshopdeploy/**/*.tf"]
  filename       = "petshopdeploy/cloudbuild.yaml"

  github {
    owner = local.github_owner
    name  = local.github_repo
    push {
      branch = "^main$" # Regex for an exact match on the 'main' branch
    }
  }

  # ADDED: Pass variables to the Terraform deployment via substitutions.
  # These values will be available inside the cloudbuild.yaml and are used
  # to configure the deployment for a specific environment.
  substitutions = {
    _PROJECT_ID  = var.project_id
    _REGION      = var.region
    _ZONE        = "${var.region}-a"
    _DB_USERNAME = var.db_username
  }

  depends_on = [
    google_project_iam_member.packer_builder_sa_roles,
    google_cloudbuild_worker_pool.packer_private_pool
  ]
}

# ADDED: A new trigger for applying the Foundation Terraform configuration.
resource "google_cloudbuild_trigger" "terraform_apply_foundation_trigger" {
  project         = var.project_id
  location        = var.region
  name            = "terraform-apply-foundation-on-commit"
  description     = "Triggers Terraform apply on commit to foundation folder"
  service_account = google_service_account.packer_builder_sa.id

  # Only trigger for changes in the 'foundation' folder.
  included_files = ["foundation/**/*.tf"]
  filename       = "foundation/cloudbuild.yaml"

  github {
    owner = local.github_owner
    name  = local.github_repo
    push {
      branch = "^main$"
    }
  }

  substitutions = {
    _PROJECT_ID = var.project_id
    _REGION     = var.region
    _ZONE       = "${var.region}-a"
  }

  # ADDED: Require manual approval before this trigger can execute.
  # This is a critical safety measure for foundational infrastructure.
  approval_config {
    approval_required = true
  }

  depends_on = [google_project_iam_member.packer_builder_sa_roles]
}
