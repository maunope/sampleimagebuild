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
    # CORRECTED: Use the official registry source and the correct plugin name 'googlecompute'
    googlecompute = {
       source  = "github.com/hashicorp/googlecompute"
      version = "~> 1.2" 
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
  network             = "manual-vpc"
  subnetwork          = "west4subnet"

  # ADDED: Comply with constraints/compute.vmExternalIpAccess
  #no_external_ip      = true

  # ADDED: Comply with constraints/compute.requireShieldedVm
  shielded_instance_config {
    enable_secure_boot = true
  }
  image_name          = var.image_name
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
      "sudo apt-get update",
      "sudo apt-get install -y apache2",
      "touch /tmp/sample-32.txt"
    ]
  }
}