# packer-apache-template.pkr.hcl

# Define variables that will be passed in from the Cloud Build command.
variable "project_id" {
  type    = string
  default = "your-gcp-project-id"
}

variable "image_name" {
  type    = string
  default = "packer-apache-image"
}

variable "zone" {
  type    = string
  default = "europe-west4-a" # Default value
}

# Packer block to define required plugins and their versions.
packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = "1.2.4"
    }
    # ADDED: Declare the Ansible provisioner plugin.
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1.1"
    }
  }
}

# Define the source image and builder configuration.
source "googlecompute" "apache-image-from-custom-debian" {
  project_id = var.project_id
  # MODIFIED: Use the previously created image family as the source.
  source_image_family = "custom-debian-family"
  zone                = var.zone

  # Specify the network and subnetwork for the temporary VM.
  network          = "packer-build-vpc"
  subnetwork       = "packer-build-subnet"
  omit_external_ip = true

  enable_secure_boot = true
  use_internal_ip    = true

  image_name = var.image_name
  # MODIFIED: Place the new image in a new family.
  image_family        = "custom-apachenode-family"
  image_description   = "Debian 11 image with Apache and PHP, built on top of the custom-debian-family."
  ssh_username        = "packer"
}

# The 'build' block defines what Packer will do.
build {
  sources = ["source.googlecompute.apache-image-from-custom-debian"]

  # A preliminary shell provisioner to ensure Python is present, which is required by Ansible.
  # This is a safe check even if the base image already has it.
  provisioner "shell" {
    inline = [
      "echo 'Waiting for apt locks to be released...'",
      "while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 5; done",
      "sudo apt-get update -y && sudo apt-get install -y python3"
    ]
  }

  # The Ansible provisioner executes the playbook to configure the image.
  provisioner "ansible" {
    playbook_file = "playbook.yml"
    # This tells Ansible to use the 'packer' user and its sudo privileges.
    user          = "packer"
  }
}
