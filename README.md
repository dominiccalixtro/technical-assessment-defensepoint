# Wazuh Deployment on AWS using Terraform and Docker Compose

## Overview

This project demonstrates the deployment of a Wazuh monitoring stack on AWS using Terraform for infrastructure provisioning and Docker Compose for application deployment. The solution emphasizes security best practices, modular infrastructure design, and automated installation.

The stack includes:

* Wazuh Manager
* Wazuh Indexer
* Wazuh Dashboard

All services run in Docker containers on an EC2 instance in a private subnet with proper network architecture.

---

## Directory Structure

```
assessment/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── provider.tf
├── scripts/
│   └── setup.sh
├── docker/
│   └── docker-compose.yml
└── README.md
```

---

## Prerequisites

* AWS Account with sufficient permissions
* Terraform CLI installed (v1.5+ recommended)
* AWS CLI configured with credentials
* IAM user with S3 and EC2 access for Terraform state and provisioning

---

## Infrastructure Setup

### 1. Terraform Backend

An S3 bucket is used to store Terraform state securely. Ensure you configure the backend in `provider.tf`:

```hcl
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "wazuh/terraform.tfstate"
    region = "us-east-1"
  }
}
```

---

### 2. Provisioning Infrastructure

Navigate to the `terraform` directory and initialize Terraform:

```bash
cd terraform
terraform init
terraform validate
terraform plan -out=plan.out
terraform apply plan.out
```

**Provisioned resources:**

* VPC with public and private subnets across 2 availability zones
* Internet Gateway for public subnet
* NAT Gateway for private subnet
* Private EC2 instance (`t3.xlarge`) for Wazuh
* Security groups with minimal required access
* IAM roles and policies
* S3 bucket for Terraform state

---

### 3. EC2 Access

The EC2 instance is deployed in a private subnet and is accessible via **AWS Systems Manager Session Manager (SSM)**.

To connect:

```bash
aws ssm start-session --target <instance-id>
```

Replace `<instance-id>` with the private EC2 instance ID from Terraform outputs.

---

## Application Deployment

### 1. Installation Script

The EC2 instance is configured using `setup.sh` located in `scripts/`. This script:

* Installs Docker and Docker Compose
* Downloads the official Wazuh Docker Compose setup
* Updates images to a valid stable version (4.8.0)
* Removes problematic mounts for Dashboard config
* Starts Wazuh stack containers
* Configures basic system logging

To run manually via Session Manager:

```bash
sudo bash /home/ec2-user/setup.sh
```

*Note: The script is also executed automatically during EC2 user-data provisioning.*

---

### 2. Docker Compose File

The Docker Compose file is located at `docker/docker-compose.yml`:

* Defines Wazuh Manager, Indexer, and Dashboard
* Includes volume mounts for persistent data (`/opt/wazuh/data`)
* Includes environment variables for container configuration
* Includes basic health checks to ensure containers start correctly

Start the stack manually (if needed):

```bash
cd /opt/wazuh
docker-compose up -d
```

Check container status:

```bash
docker ps
docker-compose ps
```

---

## Testing the Deployment

1. **Verify containers are running:**

```bash
docker ps
```

Expected output:

* `wazuh-manager`
* `wazuh-indexer`
* `wazuh-dashboard`

2. **Check logs for errors:**

```bash
docker-compose logs -f
```

3. **Access Wazuh Dashboard:**
   Since the instance is in a private subnet, you may need a VPN or port forwarding via a bastion or SSM port forwarding:

```bash
aws ssm start-session --target <instance-id> --document-name AWS-StartPortForwardingSession --parameters '{"portNumber":["5601"], "localPortNumber":["5601"]}'
```

Then access in browser:

```
http://localhost:5601
```

---

## Cleanup

To avoid unnecessary costs, destroy all Terraform-managed resources:

```bash
cd terraform
terraform destroy
```

---

## Assumptions

* Terraform S3 backend bucket already exists or will be created manually.
* EC2 instance runs Amazon Linux 2.
* Wazuh version 4.8.0 is used for stability.
* Dashboard config file mount is not required for initial deployment.

---

## Security Considerations

* EC2 instance in private subnet with no direct internet exposure
* Access via SSM Session Manager only
* Least privilege IAM roles for EC2 and Terraform
* Proper tagging for all resources

---

## Notes

* Startup dependencies are handled by Docker Compose `depends_on`.
* All scripts include basic error handling.
* Logs are stored via system logging (`rsyslog`) on EC2.
* Cost optimization considered via instance sizing (`t3.xlarge`) and minimal resources.

---

## References

* [Wazuh Docker Deployment](https://github.com/wazuh/wazuh-docker)
* [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

```
```
