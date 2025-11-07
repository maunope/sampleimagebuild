# packer-petshop-template.pkr.hcl

# Define variables that will be passed in from the Cloud Build command.
variable "project_id" {
  type    = string
  default = "your-gcp-project-id"
}

variable "image_name" {
  type    = string
  default = "packer-petshop-image"
}

# Packer block to define required plugins.
packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = "1.2.4"
    }
  }
}

# Define the source image and builder configuration.
source "googlecompute" "petshop-image-from-apache" {
  project_id = var.project_id
  # MODIFIED: Use the Apache image family as the source.
  source_image_family = "custom-apachenode-family"
  zone                = "europe-west4-a"

  # Specify the network and subnetwork for the temporary VM.
  network          = "packer-build-vpc"
  subnetwork       = "packer-build-subnet"
  omit_external_ip = true

  enable_secure_boot = true
  use_internal_ip    = true

  image_name = var.image_name
  # MODIFIED: Place the new image in the final application family.
  image_family        = "petshopnode-family"
  image_description   = "Debian image with Apache and the Pet Shop website."
  ssh_username        = "packer"
}

# The 'build' block defines what Packer will do.
build {
  sources = ["source.googlecompute.petshop-image-from-apache"]

  # ADDED: Use a file provisioner to upload the website files.
  # The source path is relative to the 'petshopnode' directory where the build runs.
  provisioner "file" {
    source      = "../website/"
te    destination = "/tmp/website/"
  }

  # Use a shell provisioner to move the files into the Apache root.
  provisioner "shell" {
    inline = [
      "echo 'Copying website files to Apache document root...'",
      "sudo rm -rf /var/www/html/*",
      "sudo mv /tmp/website/* /var/www/html/",
      "sudo chown -R www-data:www-data /var/www/html",
      "echo 'Website deployment complete.'",
      "touch /tmp/2.txt"

    ]
  }
}