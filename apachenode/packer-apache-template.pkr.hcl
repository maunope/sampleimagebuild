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
source "googlecompute" "apache-image-from-custom-debian" {
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
  image_family        = "custom-apachenode-family"
  image_description   = "Debian 11 image with Apache and PHP, built on top of the custom-debian-family."
  ssh_username        = "packer"
}

# The 'build' block defines what Packer will do.
build {
  sources = ["source.googlecompute.apache-image-from-custom-debian"]

  # Provisioners are used to install software or configure the machine.
  provisioner "shell" {
    inline = [
      "set -e",
      "echo 'Waiting for system to become ready...'",
      "sleep 15",
      "sudo apt-get update -y",
      "sudo apt-get upgrade -y",
      "echo 'Installing Apache2...'",
      "sudo apt-get install -y apache2",
      "sudo systemctl enable apache2",
      "echo 'Installing Google Cloud Ops Agent...'",
      "curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh",
      "sudo bash add-google-cloud-ops-agent-repo.sh --also-install",
      "echo 'Configuring Google Cloud Ops Agent for Apache logging... '",
      "sudo mkdir -p /etc/google-cloud-ops-agent",
      "sudo tee /etc/google-cloud-ops-agent/config.yaml > /dev/null <<'EOF'",
      "logging:",
      "  receivers:",
      "    apache_access:",
      "      type: apache_access",
      "    apache_error:",
      "      type: apache_error",
      "  service:",
      "    pipelines:",
      "      apache:",
      "        receivers:",
      "          - apache_access",
      "          - apache_error",
      "EOF",
      "echo 'Restarting Ops Agent to apply configuration...'",
      "sudo systemctl restart google-cloud-ops-agent",
      "echo 'Apache installation and configuration complete.'"
    ]
  }
}
