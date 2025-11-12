# Pet Shop Application - Layered Image Build and Deployment Demo

This repository contains a demonstration of how to build and deploy a fictional "Pet Shop" application on Google Cloud. The project showcases a layered approach to both VM image creation and infrastructure management.

The core concepts highlighted are:
-   **Layered VM Images**: Using Packer and Cloud Build to create a pipeline that builds specialized VM images on top of base images.
-   **Infrastructure as Code (IaC)**: Using Terraform to define and manage all cloud resources in a structured, version-controlled way.
-   **Layered Infrastructure**: The Terraform code is split into distinct layers (`foundation`, `pipelines`, `petshopdeploy`) to separate concerns and improve reusability.

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

-   `./customimage/`: Base image with common tools like the Ops Agent.
-   `./mysqlnode/`: Image containing the MySQL server.
-   `./petshopdatabasenode/`: Image containing the MySQL server pre-configured with the Pet Shop application's database schema.
-   `./petshopnode/`: The final application image, containing the web application code, built on top of the base images.
-   `./website/`: Contains the source code for the Pet Shop web application.