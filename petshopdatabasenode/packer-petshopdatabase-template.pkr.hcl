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
      "# Create petshop database and tables.",
      "sudo mysql -u root -e 'CREATE DATABASE IF NOT EXISTS petshop;'",
      "sudo mysql -u root -e 'USE petshop; CREATE TABLE IF NOT EXISTS products (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255));'",
      "sudo mysql -u root -e \"USE petshop; INSERT INTO products (name) VALUES ('Golden Retriever'), ('Siamese Cat'), ('Parrot'), ('Goldfish'), ('Hamster'), ('Canary'), ('Iguana'), ('Ferret'), ('Rabbit'), ('Turtle');\"",
      "echo 'Petshop database, table, and seed data created successfully.'"
    ]
  }

  # CORRECTED: Create the first-boot script inline and set up the systemd service in a single step.
  provisioner "shell" {
    inline = [
      "echo 'Creating first-boot configuration script...'",
      "# Create the script that will run on first boot.",
      "cat <<'EOT' | sudo tee /usr/local/bin/configure-db.sh",
      "#!/bin/bash",
      "set -e",
      "PROJECT_ID=\\$(curl -s \"http://metadata.google.internal/computeMetadata/v1/project/project-id\" -H \"Metadata-Flavor: Google\")",
      "if [ -z \"\\$PROJECT_ID\" ]; then echo 'FATAL: Could not get project ID' >&2; exit 1; fi",
      "echo 'First boot: Configuring MySQL in project \\$PROJECT_ID...'",
      "APP_USER_PAYLOAD=\\$(gcloud secrets versions access latest --secret=\"petshop-db-credentials\" --project=\"\\$PROJECT_ID\")",
      "DB_USERNAME=\\$(echo \"\\$APP_USER_PAYLOAD\" | jq -r .username)",
      "DB_PASSWORD=\\$(echo \"\\$APP_USER_PAYLOAD\" | jq -r .password)",
      "ROOT_PASSWORD=\\$(gcloud secrets versions access latest --secret=\"petshop-db-root-credentials\" --project=\"\\$PROJECT_ID\")",
      "while ! mysqladmin ping --silent; do echo 'Waiting for MySQL...'; sleep 2; done",
      "mysql -u root <<-MYSQL_SCRIPT",
      "CREATE USER '\\${DB_USERNAME}'@'%' IDENTIFIED BY '\\${DB_PASSWORD}';",
      "GRANT ALL PRIVILEGES ON *.* TO '\\${DB_USERNAME}'@'%' WITH GRANT OPTION;",
      "ALTER USER 'root'@'localhost' IDENTIFIED BY '\\${ROOT_PASSWORD}';",
      "CREATE USER '\\${DB_USERNAME}'@'%' IDENTIFIED BY '\\${DB_PASSWORD}';",
      "GRANT ALL PRIVILEGES ON *.* TO '\\${DB_USERNAME}'@'%' WITH GRANT OPTION;",
      "ALTER USER 'root'@'localhost' IDENTIFIED BY '\\${ROOT_PASSWORD}';",
      "FLUSH PRIVILEGES;",


      "FLUSH PRIVILEGES;",
      "MYSQL_SCRIPT",
      "echo 'MySQL users configured successfully.'",
      "systemctl disable configure-db.service",
      "echo 'Configuration complete. Service disabled.'",
      "EOT",

      "sudo chmod +x /usr/local/bin/configure-db.sh",

      "echo 'Creating and enabling systemd service...'",
      "# Create the systemd service file to run the script.",
      "cat <<'EOT' | sudo tee /etc/systemd/system/configure-db.service",
      "[Unit]",
      "Description=First-boot MySQL Configuration",
      "After=network-online.target mysql.service",
      "[Service]",
      "ExecStart=/usr/local/bin/configure-db.sh",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOT",

      "# Enable the service so it runs on the next boot.",
      "sudo systemctl enable configure-db.service",
      "echo 'Service enabled. It will run on next boot.'"
    ]
  }
} 