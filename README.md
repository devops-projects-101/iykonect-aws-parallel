# IYKonect AWS Parallel Infrastructure

This repository contains Terraform code to deploy the IYKonect application infrastructure in AWS, implementing the Control Environment Configuration as part of the organization's cloud migration strategy. The infrastructure is designed with cloud-native best practices to support containerized application deployment.

## Project Context

This repository represents the DevOps responsibility in the Control Environment Configuration phase, providing:
- Terraform-managed AWS infrastructure with proper tagging
- Automated CI/CD pipelines for infrastructure deployment
- Container-ready environment for application services
- Standardized monitoring and logging

## Architecture Overview

[![Infrastructure Diagram](https://i.postimg.cc/CK5rPHw1/image.png)](https://postimg.cc/VSyF5trQ)

The architecture provisions the following AWS resources:
- **VPC** with public subnet and internet gateway
- **EC2** instance with Ubuntu 20.04 for container hosting
- **IAM** roles and policies for S3, ECR, Secrets Manager, and CloudWatch access
- **Security groups** for appropriate network access
- **S3 buckets** for state storage
- **CloudWatch** for monitoring and logging

The EC2 instance runs the following containerized services:
- Redis service for caching
- API service (backend)
- React application (frontend)
- Prometheus for monitoring
- Grafana for visualization
- SonarQube for code quality analysis
- Grafana renderer for PDF exports

## CI/CD Pipeline

This repository implements two key pipelines:

### Continuous Integration (CI)
- Managed by the development team
- Builds and pushes Docker images to ECR
- Uses GitHub Actions for automation
- Integrates with AWS Secrets Manager
- Developer-maintained repositories available at: [https://github.com/iykons](https://github.com/iykons)

#### Code Repository Integration
The CI pipeline relies on the following code repositories that handle the image building and pushing to ECR:
- **[iykons/api-service](https://github.com/iykons/api-service)**: Backend API service
- **[iykons/react-frontend](https://github.com/iykons/react-frontend)**: React frontend application
- **[iykons/monitoring-stack](https://github.com/iykons/monitoring-stack)**: Prometheus and Grafana services

Each repository contains:
- Dockerfiles for containerization
- GitHub Actions workflows for automated builds
- Configuration to pull secrets from AWS Secrets Manager
- ECR push actions for container image delivery

The workflow typically:
1. Authenticates with AWS
2. Retrieves secrets from AWS Secrets Manager
3. Builds Docker images with the necessary environment variables
4. Tags images with appropriate version/commit information
5. Pushes images to the ECR repository
6. Notifies this infrastructure repository when new images are available

### Continuous Deployment (CD)
- Managed via Terraform workflow in this repository
- Deploys and maintains AWS infrastructure
- Ensures consistent resource tagging

## Prerequisites

- AWS Account with appropriate permissions
- AWS CLI installed and configured
- Terraform v1.6.6 or later
- Docker and Docker Compose for local testing
- GitHub repository secrets configured for CI/CD

## Setup and Deployment

### AWS Secrets Manager Setup

Before deploying, ensure you've created the required secrets in AWS Secrets Manager:

```bash
aws secretsmanager create-secret --name iykonect-app-secrets \
    --description "IYKonect application secrets" \
    --secret-string '{"DB_USERNAME":"user","DB_PASSWORD":"password","API_KEY":"key","JWT_SECRET":"secret","REDIS_PASSWORD":"redis_pwd"}'
```

### Required GitHub Secrets

Configure the following secrets in your GitHub repository settings:
- `AWS_ACCESS_KEY_ID`: AWS access key with permissions to create resources
- `AWS_SECRET_ACCESS_KEY`: Corresponding AWS secret key
- `AWS_REGION`: Default AWS region (e.g., eu-west-1)

### Manual Deployment

1. Clone the repository
```bash
git clone https://github.com/your-org/iykonect-aws-parallel.git
cd iykonect-aws-parallel/terraform
```

2. Initialize Terraform
```bash
terraform init
```

3. Create a `terraform.tfvars` file with the following content:
```
aws_access_key = "YOUR_AWS_ACCESS_KEY"
aws_secret_key = "YOUR_AWS_SECRET_KEY"
aws_region     = "eu-west-1"
prefix         = "iykonect-migrate"
```

4. Apply the Terraform configuration
```bash
terraform apply
```

### GitHub Actions Workflow

The workflow in `.github/workflows/terraform.yml` provides:
- **Infrastructure validation** on pull requests
- **Automated deployment** when merging to main
- **Manual workflow dispatch** with options:
  - `create_infra`: Deploy or update infrastructure
  - `destroy_infra`: Tear down infrastructure

## Infrastructure Components

### VPC Module
Creates a secure network environment with:
- Virtual Private Cloud with CIDR block 10.0.0.0/16
- Public subnet with auto-assigned public IPs
- Internet Gateway for outbound connectivity
- Route tables and associations
- Consistent resource tagging

### EC2 Module
Provisions a compute instance with:
- Ubuntu 20.04 LTS AMI
- Docker runtime environment
- User data script for automatic container orchestration
- Security group with appropriate ports
- IAM role with least-privilege policies
- CloudWatch integration

### Security and IAM
Implements security best practices:
- Resource-specific IAM roles following principle of least privilege
- Policy-based access to AWS services
- Encrypted EBS volumes
- Port-specific security groups
- Secrets management integration

## Endpoints and Access

After deployment, the following endpoints will be available:
- API: `http://<instance-ip>:8000`
- Web App: `http://<instance-ip>:3000`
- Prometheus: `http://<instance-ip>:9090`
- Grafana: `http://<instance-ip>:3100`
- SonarQube: `http://<instance-ip>:9000`

## Monitoring and Observability

The infrastructure includes:
- CloudWatch Agent for logs and metrics collection
- CloudWatch Dashboards for visualization
- Prometheus for container-level monitoring
- Grafana for metric visualization and alerting

## Future Enhancements

As part of the migration strategy outlined in the project documentation:
1. **Migration Phase-1**: 
   - Integration with RDS for database services
   - Expanded container orchestration

2. **Migration Phase-2**:
   - Migration to Azure with equivalent services
   - Transition from AWS to Azure managed services:
     - S3 → Azure Blob Storage
     - ECR → Azure Container Registry
     - AWS Secrets Manager → Azure Key Vault

## Tagging Strategy

All resources are tagged consistently with:
- `ManagedBy: Terraform` - Identifies infrastructure-as-code managed resources
- `Project: iykonect` - Associates resources with the project
- `Environment: parallel` - Identifies the environment
- `Name: <resource-specific-name>` - Provides a descriptive resource name

## License

Copyright (c) 2025 IYKonect. All rights reserved.