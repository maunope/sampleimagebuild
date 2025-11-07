# packer-template.pkr.hcl

# Define variables that will be passed in from the Cloud Build command.
variable "project_id" {
  type    = string
  default = "your-gcp-project-id"
}

variable "image_name" {
  type    = string
  default = "packer-debian-image"
}

# Packer block to define required plugins and their versions.
packer {
  required_plugins {

    googlecompute = {
      # This is the path the old Packer version is strictly demanding.
      source  = "github.com/hashicorp/googlecompute" 
      # Version 1.2.4 is the latest on this path and supports no_external_ip and shielded_instance_config.
      version = "1.2.4" 
    }
  }
}

# Define the source image and builder configuration.
# CORRECTED: The source type must match the plugin name 'googlecompute'
source "googlecompute" "debian-image" {
  project_id          = var.project_id
  source_image_family = "debian-11"
  zone                = "europe-west4-a"

  # ADDED: Specify the network and subnetwork for the temporary VM.
  network             = "packer-build-vpc"
  subnetwork          = "packer-build-subnet"

  omit_external_ip = true


  enable_secure_boot = true
  use_internal_ip    = true

  #
  image_name          = var.image_name
  image_family        = "custome-debian-family" # ADDED: Create/use an image family
  image_description   = "Debian 11 image with custom configurations built by Packer."
  ssh_username        = "packer"
}

# The 'build' block defines what Packer will do.
build {
  # CORRECTED: The source reference must match the corrected source type and name
  sources = ["source.googlecompute.debian-image"]

  # Provisioners are used to install software or configure the machine.
  provisioner "shell" {
    inline = [
      "echo 'Waiting for system to become ready...'",
      "sleep 30",
      "sudo apt-get update -y",
      "# MODIFIED: Install Google Cloud Ops Agent",
      "curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh",
      "sudo bash add-google-cloud-ops-agent-repo.sh --also-install",
      "# MODIFIED: Set ulimit permanently for all users",
      "echo '* soft nofile 64000' | sudo tee /etc/security/limits.d/99-packer.conf",
      "echo '* hard nofile 64000' | sudo tee -a /etc/security/limits.d/99-packer.conf"
    ]
  }
}
