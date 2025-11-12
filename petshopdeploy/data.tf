# This data source reads the outputs from the foundation's remote state file.
data "terraform_remote_state" "foundation" {
  backend = "gcs"
  config = {
    # CORRECTED: The bucket name must point to the single, correct state bucket.
    bucket = "${var.project_id}-tf-state"
    prefix = "petshop-foundation" # The path to the foundation state file
  }
}

# Data sources for compute images remain here.
data "google_compute_image" "latest_petshop_db_image" {
  family  = "petshopdatabasenode-family"
  project = var.project_id
}

data "google_compute_image" "latest_petshop_node_image" {
  family  = "petshopnode-family"
  project = var.project_id
}
