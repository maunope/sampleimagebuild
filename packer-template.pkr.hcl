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

# Define the source image and builder configuration.
source "googlecompute" "debian-image" {
  project_id          = var.project_id
  source_image_family = "debian-11" # Using Debian 11 family
  zone                = "europe-west4-a"
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
      "touch /tmp/sample-26.txt"

    ]
  }
}
