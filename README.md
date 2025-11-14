# Pet Shop Application - Layered Image Build and Deployment Demo

This repository contains a demonstration of how to build and deploy a fictional "Pet Shop" application on Google Cloud. The project showcases a layered approach to both VM image creation and infrastructure management.

The core concepts highlighted are:
-   **Layered VM Images**: Using Packer and Cloud Build to create a pipeline that builds specialized VM images on top of base images.
-   **Infrastructure as Code (IaC)**: Using Terraform to define and manage all cloud resources in a structured, version-controlled way.
-   **Layered Infrastructure**: The Terraform code is split into distinct layers (`foundation`, `pipelines`, `petshopdeploy`) to separate concerns and improve reusability.

---

## Installation and Deployment Guide

Follow these steps to deploy the entire application and its supporting infrastructure.

### Prerequisites

1.  A Google Cloud Project with billing enabled.
2.  The `gcloud` CLI installed and authenticated (`gcloud auth login`, `gcloud config set project YOUR_PROJECT_ID`).
3.  Terraform installed locally.

### Step 1: Connect GitHub Repository (Manual UI Step)

This one-time manual step is required to authorize Cloud Build to access your GitHub repository. This cannot be fully automated with Terraform due to the OAuth authentication flow with GitHub.

1.  In the Google Cloud Console, navigate to **Cloud Build** > **Triggers**.
2.  Click **Connect Repository**.
3.  Select **GitHub (Cloud Build GitHub App)** as the source.
4.  Follow the authentication prompts to install and authorize the Google Cloud Build app on your GitHub account and select the repository you want to connect.

### Step 2: Deploy the CI/CD Pipelines

This step uses Terraform to create the private worker pool, service accounts, and all the Cloud Build triggers needed for the subsequent steps.

1.  Navigate to the `pipelines` directory:
    ```bash
    cd pipelines
    ```
2.  Edit the `terraform.tfvars` file and set your `project_id` and `region`.
3.  Initialize and apply the Terraform configuration:
    ```bash
    terraform init
    terraform apply
    ```

### Step 3: Build Infrastructure and VM Images

Now that the triggers exist, you must run them in a specific order to build the infrastructure layers and VM images correctly. Navigate to **Cloud Build** > **Triggers** in the console to run each trigger. **Wait for linux image build to complete** before starting Apache and MySQL ones, and wait for them both to finish before launching pethsop specific nodes builds. This is the most time-consuming part of the process, as building multiple VM images can take a significant amount of time.

1.  **Deploy Foundation Infrastructure**:
    *   Find the `terraform-apply-foundation-on-commit` trigger and click **Run**.
    *   Go to the build history, find the running build, and click **Approve** when prompted.

2.  **Build Base Images (in order)**:
    *   Run `packer-image-builder-on-main-commit` (builds the base Debian image).
    *   Run `packer-mysql-image-builder-on-commit` (builds the MySQL image).
    *   Run `packer-apache-image-builder-on-commit` (builds the Apache/PHP image).

3.  **Build Application-Specific Images**:
    *   Run `packer-petshop-database-image-builder-on-commit` (builds the DB image with the schema).
    *   Run `packer-petshop-image-builder-on-commit` (builds the final application image with the website code).

### Step 4: Deploy the Pet Shop Application

Finally, run the trigger that deploys the application using the infrastructure and images created in the previous steps.

1.  In the Cloud Build Triggers UI, find the `terraform-apply-on-commit` trigger and click **Run**.
2.  This will execute the Terraform configuration in the `petshopdeploy` directory, creating the secrets, instance groups, and load balancer.
3.  Once the build is complete, you can find the public IP address of the website in the Terraform output.

---

## Directory Structure

The repository is organized into several directories, each with a specific role in the build and deployment process. The primary infrastructure is managed across three Terraform configurations.

### Terraform Configurations

Terraform is used to provision all the necessary cloud infrastructure. The configuration is split into logical layers:

*   `./foundation/`
    This directory contains the Terraform code for the foundational infrastructure. It sets up the core networking and security components that the application relies on. This includes:
    -   A custom Virtual Private Cloud (VPC) and subnet.
    -   Firewall rules for allowing HTTP, SSH, and internal database traffic.
    -   A Cloud NAT gateway to allow instances without public IPs to access the internet.
    -   A private Cloud DNS zone for service discovery within the VPC.

*   `./pipelines/`
    This directory defines the Continuous Integration (CI) infrastructure using Terraform. It sets up Cloud Build to automatically build new VM images whenever code changes are pushed to the repository. Key resources include:
    -   A dedicated VPC and private worker pool for running secure builds.
    -   Service Accounts and IAM permissions required for the build pipelines to create images and access other resources.
    -   Cloud Build triggers that watch specific folders (e.g., `petshopnode`, `mysqlnode`) and initiate a build using the corresponding `cloudbuild.yaml` file.

*   `./petshopdeploy/`
    This directory contains the Terraform configuration to deploy the Pet Shop application itself. It uses the images built by the CI pipeline and the network created by the foundation layer. Its responsibilities include:
    -   Deploying a Managed Instance Group (MIG) for the web application, using an instance template.
    -   Provisioning a dedicated Compute Engine instance for the database.
    -   Setting up a Global External HTTP Load Balancer to expose the application to the internet.
    -   Managing application-specific Service Accounts and secrets (e.g., database credentials).

### Image Source & Build Configuration

These folders contain the Packer templates, scripts, and Cloud Build configurations needed to create the various VM images. Each directory corresponds to a specific layer of the application stack.

-   `./debiannode/`: Base image with common tools like the Ops Agent.
-   `./mysqlnode/`: Image containing the MySQL server.
-   `./petshopdatabasenode/`: Image containing the MySQL server pre-configured with the Pet Shop application's database schema.
-   `./petshopnode/`: The final application image, containing the web application code, built on top of the base images.
-   `./website/`: Contains the source code for the Pet Shop web application.