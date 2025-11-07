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
# This tells 'packer init' what plugins to download and install.
packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = "~> 1.0" # Use a compatible version, e.g., latest 1.x
    }
  }
}


# Define the source image and builder configuration.
source "googlecompute" "debian-image" {
  project_id          = var.project_id
  source_image_family = "debian-11" # Using Debian 11 family
  zone                = "europe-west4-a"

  # ADDED: Specify the network and subnetwork for the temporary VM.
  # Replace 'your-vpc-name' and 'your-subnetwork-name' with your actual network resources.
  network             = "manual-vpc"
  subnetwork          = "your-subnetwork-name"
  image_name          = var.image_name
  image_description   = "Debian 11 image with custom configurations built by Packer."
  ssh_username        = "packer"
}

# The 'build' block defines what Packer will do.
build {
  sources = ["source.googlecompute.debian-image"]

  # Provisioners are used to install software or configure the machine.
  # This example updates the package manager and installs apache2.
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y apache2",
      "touch /tmp/sample-32.txt"

    ]
  }
}
