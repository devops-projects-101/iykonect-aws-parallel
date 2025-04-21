# IYKonect AWS Parallel Infrastructure

This repository contains Terraform code to deploy the IYKonect application infrastructure in AWS. The infrastructure includes VPC, EC2, IAM, and related components to run the IYKonect application stack.

## Architecture Overview

The architecture provisions the following AWS resources:
- **VPC** with public subnet and internet gateway
- **EC2** instance with Ubuntu 20.04 and auto-scaling configuration
- **IAM** roles and policies for S3 and ECR access
- **Security groups** for appropriate network access

The EC2 instance runs the following containerized services:
- Redis service for caching
- API service (backend)
- React application (frontend)
- Prometheus for monitoring
- Grafana for visualization
- SonarQube for code quality analysis
- Grafana renderer for PDF exports

## Prerequisites

- AWS Account with appropriate permissions
- AWS CLI installed and configured
- Terraform v1.6.6 or later
- Docker images pushed to ECR repository

## Setup and Deployment

### AWS Secrets Manager Setup

Before deploying, ensure you've created a secret in AWS Secrets Manager with the following structure:

```json
{
  "DB_USERNAME": "your_db_username",
  "DB_PASSWORD": "your_db_password",
  "API_KEY": "your_api_key",
  "JWT_SECRET": "your_jwt_secret",
  "REDIS_PASSWORD": "your_redis_password",
  "OTHER_SECRET_1": "value1",
  "OTHER_SECRET_2": "value2"
}
```

Create the secret using AWS CLI:
```bash
aws secretsmanager create-secret --name iykonect-app-secrets \
    --description "IYKonect application secrets" \
    --secret-string '{"DB_USERNAME":"user","DB_PASSWORD":"password","API_KEY":"key","JWT_SECRET":"secret","REDIS_PASSWORD":"redis_pwd"}'
```

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

### CI/CD Deployment

The repository includes both GitHub Actions and GitLab CI/CD workflows for automated deployments:

#### GitHub Actions

The workflow in `.github/workflows/terraform.yml` allows:
- Automatic infrastructure creation on push to main branch
- Manual triggers for creating or destroying infrastructure
- Validation on pull requests

Required GitHub secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`

#### GitLab CI/CD

The pipeline in `.gitlab-ci.yml` provides:
- Infrastructure validation
- Planning and applying changes
- Manual destroy option
- EC2 instance recreation option

Required GitLab variables:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`

## Docker Images

The deployment uses the following container images from ECR:
- `iykonect-images:redis` - Redis cache service
- `iykonect-images:api-latest` - Backend API service
- `iykonect-images:web-latest` - Frontend React application
- `iykonect-images:prometheus` - Prometheus monitoring
- `iykonect-images:grafana` - Grafana dashboard
- `grafana/grafana-image-renderer:latest` - Grafana renderer for PDF exports

## Endpoints

After deployment, the following endpoints will be available:
- API: `http://<instance-ip>:8000`
- Web App: `http://<instance-ip>:3000`
- Prometheus: `http://<instance-ip>:9090`
- Grafana: `http://<instance-ip>:3100`
- SonarQube: `http://<instance-ip>:9000`
- Renderer: `http://<instance-ip>:8081`

## Terraform Modules

### VPC Module
Creates the VPC, subnets, route tables, and internet gateway.

### EC2 Module
Creates the EC2 instance with security group, user data script, and IAM role.

### EFS Module
Creates an Elastic File System for persistent storage (currently not in use but available).

## License

Copyright (c) 2025 IYKonect. All rights reserved.