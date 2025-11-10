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
    script = <<-EOT
      set -e
      echo 'Waiting for system to become ready...'
      sleep 15
      sudo apt-get update -y
      sudo apt-get upgrade -y

      echo "Installing MariaDB Server..."
      sudo apt-get install -y mariadb-server
      sudo systemctl enable mariadb

      echo "Configuring MariaDB for remote access and logging..."
      sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY 'root' WITH GRANT OPTION;"
      sudo mysql -e "FLUSH PRIVILEGES;"
      sudo sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mysql/mariadb.conf.d/50-server.cnf

      sudo mkdir -p /var/log/mysql
      sudo touch /var/log/mysql/error.log /var/log/mysql/mysql.log /var/log/mysql/mysql-slow.log
      sudo chown -R mysql:mysql /var/log/mysql

      sudo sed -i '/^\\[mysqld\\]/a log_error = /var/log/mysql/error.log' /etc/mysql/mariadb.conf.d/50-server.cnf
      sudo sed -i '/^\\[mysqld\\]/a general_log_file = /var/log/mysql/mysql.log' /etc/mysql/mariadb.conf.d/50-server.cnf
      sudo sed -i '/^\\[mysqld\\]/a general_log = 1' /etc/mysql/mariadb.conf.d/50-server.cnf
      sudo sed -i '/^\\[mysqld\\]/a slow_query_log_file = /var/log/mysql/mysql-slow.log' /etc/mysql/mariadb.conf.d/50-server.cnf
      sudo sed -i '/^\\[mysqld\\]/a slow_query_log = 1' /etc/mysql/mariadb.conf.d/50-server.cnf
      sudo systemctl restart mariadb

      echo "Installing Google Cloud Ops Agent..."
      curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
      sudo bash add-google-cloud-ops-agent-repo.sh --also-install

      echo "Configuring Google Cloud Ops Agent for MariaDB logging..."
      sudo mkdir -p /etc/google-cloud-ops-agent
      sudo tee /etc/google-cloud-ops-agent/config.yaml > /dev/null <<'EOF'
      logging:
        receivers:
          mysql_error:
            type: mysql_error
          mysql_general:
            type: mysql_general
          mysql_slow:
            type: mysql_slow
        service:
          pipelines:
            mysql:
              receivers:
                - mysql_error
                - mysql_general
                - mysql_slow
      EOF

      echo "Restarting Ops Agent to apply configuration..."
      sudo systemctl restart google-cloud-ops-agent

      echo "MariaDB installation and configuration complete."
    EOT
  }
}
