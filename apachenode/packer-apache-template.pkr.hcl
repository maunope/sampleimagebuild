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
      "echo 'Waiting for system to become ready...'",
      "sleep 15",
      "sudo apt-get update -y",
      "sudo apt-get upgrade -y",
      "# MODIFIED: Install Apache web server and PHP",
      "sudo apt-get install -y apache2 php libapache2-mod-php php-mysql",
      "# MODIFIED: Enable Apache to start on boot",
      "sudo systemctl enable apache2",
      "echo 'Apache and PHP installation complete.'",
      "# ADDED: Configure Ops Agent to ship Apache logs to Cloud Logging",
      "sudo bash -c 'cat <<EOF >> /etc/google-cloud-ops-agent/config.yaml
logging:
  receivers:
    apache_access:
      type: files
      include_paths:
        - /var/log/apache2/access.log
    apache_error:
      type: files
      include_paths:
        - /var/log/apache2/error.log
  processors:
    apache_access_parser:
      type: apache_access
      field_name: message
    apache_error_parser:
      type: apache_error
      field_name: message
  service:
    pipelines:
      apache_access:
        receivers: [apache_access]
        processors: [apache_access_parser]
      apache_error:
        receivers: [apache_error]
        processors: [apache_error_parser]
EOF'",
      "sudo systemctl restart google-cloud-ops-agent",
      "echo 'Ops Agent configured for Apache logs and restarted.'",
      "# MODIFIED: Create a dynamic PHP index page",
      "sudo rm /var/www/html/index.html",
      "sudo bash -c 'cat > /var/www/html/index.php <<EOF",
      "<!DOCTYPE html>",
      "<html>",
      "<head><title>Apache & PHP</title></head>",
      "<body><h1>Hello from your dynamic website!</h1>",
      "<p>Your IP address is: <?php echo $_SERVER[\\\"REMOTE_ADDR\\\"]; ?></p>",
      "<p><a href=\\\"phpinfo.php\\\">View PHP Info</a></p>",
      "</body></html>",
      "EOF'",
      "# ADDED: Create a phpinfo page for diagnostics",
      "sudo bash -c 'cat > /var/www/html/phpinfo.php <<EOF",
      "<?php phpinfo(); ?>",
      "EOF'"
    ]
  }
}
