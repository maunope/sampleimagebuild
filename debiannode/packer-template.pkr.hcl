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

variable "zone" {
  type    = string
  default = "europe-west4-a"
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
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1"
    }
  }
}

# Define the source image and builder configuration.
# CORRECTED: The source type must match the plugin name 'googlecompute'
source "googlecompute" "debian-image" {
  project_id          = var.project_id
  source_image_family = "debian-11"
  zone                = var.zone

  # ADDED: Specify the network and subnetwork for the temporary VM.
  network             = "packer-build-vpc"
  subnetwork          = "packer-build-subnet"

  omit_external_ip = true


  enable_secure_boot = true
  use_internal_ip    = true

  #
  image_name          = var.image_name
  image_family        = "custom-debian-family" # ADDED: Create/use an image family
  image_description   = "Debian 11 image with custom configurations built by Packer."
  ssh_username        = "packer"
}

# The 'build' block defines what Packer will do.
build {
  # CORRECTED: The source reference must match the corrected source type and name
  sources = ["source.googlecompute.debian-image"]

  # Provisioners are used to install software or configure the machine.
  # First, install python, required for the ansible provisioner.
  provisioner "shell" {
    inline = [
      "# Wait for any automatic apt process to finish",
      "while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do echo 'Waiting for apt lock...'; sleep 10; done",
      "# Forcefully remove the package that causes the lock",
      "sudo apt-get -y remove unattended-upgrades",
      "# Now, safely update and install python",
      "sudo apt-get update -y",
      "sudo apt-get install -y python3",
      "# Grant packer user passwordless sudo privileges for Ansible",
      "echo 'packer ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/packer"
    ]
  }

  provisioner "ansible" {
    playbook_file   = "ansible/playbook.yml"
    extra_arguments = [
      "--extra-vars",
      "ansible_remote_tmp=/tmp"
    ]
  }
}
