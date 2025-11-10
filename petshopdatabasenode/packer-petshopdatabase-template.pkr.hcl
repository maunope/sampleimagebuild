# packer-petshopdatabase-template.pkr.hcl

# Define variables that will be passed in from the Cloud Build command.
variable "project_id" {
  type    = string
  default = "your-gcp-project-id"
}

variable "image_name" {
  type    = string
  default = "packer-petshopdatabase-image"
}

# Packer block to define required plugins and their versions.
packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = "1.2.4"
    }
  }
}

# Define the source image and builder configuration.
source "googlecompute" "petshopdatabase-image-from-mysql" {
  project_id = var.project_id
  # MODIFIED: Use the mysql node image family as the source.
  source_image_family = "custom-mysqlnode-family"
  zone                = "europe-west4-a"

  # Specify the network and subnetwork for the temporary VM.
  network          = "packer-build-vpc"
  subnetwork       = "packer-build-subnet"
  omit_external_ip = true

  enable_secure_boot = true
  use_internal_ip    = true

  image_name = var.image_name
  # MODIFIED: Place the new image in a new family.
  image_family        = "petshopdatabasenode-family"
  image_description   = "Debian 11 image with MySQL and a petshop database, built on top of the custom-mysqlnode-family."
  ssh_username        = "packer"
}

# The 'build' block defines what Packer will do.
build {
  sources = ["source.googlecompute.petshopdatabase-image-from-mysql"]

  # Provisioners are used to install software or configure the machine.
  provisioner "shell" {
    inline = [
      "echo 'Waiting for MySQL to become ready...'",
      "sleep 15",
      "# MODIFIED: Create petshop database and products table",
      "sudo mysql -u root -proot -e 'CREATE DATABASE petshop;'",
      "sudo mysql -u root -proot -e 'USE petshop; CREATE TABLE products (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255));'",
      "sudo mysql -u root -proot -e 'USE petshop; INSERT INTO products (name) VALUES (\\\"Golden Retriever\\\"), (\\\"Siamese Cat\\\"), (\\\"Parrot\\\");'",
      "echo 'Petshop database and table created successfully.'"
    ]
  }
}