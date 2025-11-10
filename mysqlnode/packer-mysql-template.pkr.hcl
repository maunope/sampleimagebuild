# packer-mysql-template.pkr.hcl

# Define variables that will be passed in from the Cloud Build command.
variable "project_id" {
  type    = string
  default = "your-gcp-project-id"
}

variable "image_name" {
  type    = string
  default = "packer-mysql-image"
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
source "googlecompute" "mysql-image-from-custom-debian" {
  project_id = var.project_id
  # MODIFIED: Use the previously created image family as the source.
  source_image_family = "custom-debian-family"
  zone                = "europe-west4-a"

  # Specify the network and subnetwork for the temporary VM.
  network          = "packer-build-vpc"
  subnetwork       = "packer-build-subnet"
  omit_external_ip = true

  enable_secure_boot = true
  use_internal_ip    = true

  image_name = var.image_name
  # MODIFIED: Place the new image in a new family.
  image_family        = "custom-mysqlnode-family"
  image_description   = "Debian 11 image with MySQL, built on top of the custom-debian-family."
  ssh_username        = "packer"
}

# The 'build' block defines what Packer will do.
build {
  sources = ["source.googlecompute.mysql-image-from-custom-debian"]

  # Provisioners are used to install software or configure the machine.
  provisioner "shell" {
    inline = [
      "echo 'Waiting for system to become ready...'",
      "sleep 15",
      "sudo apt-get update -y",
      "sudo apt-get upgrade -y",
      "# MODIFIED: Install MySQL Server",
      "sudo apt-get install -y mysql-server",
      "# MODIFIED: Enable MySQL to start on boot",
      "sudo systemctl enable mysql",
      "# MODIFIED: Set root password and allow remote connections",
      "sudo mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'root';\"",
      "sudo sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mysql/mysql.conf.d/mysqld.cnf",
      "echo 'MySQL installation and configuration complete.'",
      "touch /tmp/2.txt"
    ]
  }
}
