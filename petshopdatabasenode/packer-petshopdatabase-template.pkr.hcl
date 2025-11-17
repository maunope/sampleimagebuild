# packer-petshopdatabase-template.pkr.hcl

# Define variables that will be passed in from the Cloud Build command.
variable "project_id" {
  type    = string
  default = "your-gcp-project-id"
}

variable "image_name" {
  type    = string
  default = "packer-petshop-database-image"
}

variable "zone" {
  type    = string
  default = "europe-west4-a"
}

# Packer block to define required plugins and their versions.
packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = "1.2.4"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1.1"
    }
  }
}

# Define the source image and builder configuration.
source "googlecompute" "petshop-database-image-from-mysql" {
  project_id          = var.project_id
  source_image_family = "custom-mysqlnode-family"
  zone                = var.zone

  network          = "packer-build-vpc"
  subnetwork       = "packer-build-subnet"
  omit_external_ip = true

  enable_secure_boot = true
  use_internal_ip    = true

  image_name          = var.image_name
  image_family        = "custom-petshopdatabasenode-family"
  image_description   = "MySQL image with the Pet Shop database schema imported."
  ssh_username        = "packer"
}

# The 'build' block defines what Packer will do.
build {
  sources = ["source.googlecompute.petshop-database-image-from-mysql"]

  # A preliminary shell provisioner to ensure Python is present for Ansible.
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
    user          = "packer"
  }
}