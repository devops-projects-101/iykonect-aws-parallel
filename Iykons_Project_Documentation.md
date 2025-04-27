# Iykons Project Documentation

This document provides an overview of the existing setup, the planned control environment configuration, and the migration strategy for the Iykons project. It focuses on how repositories, environment variables, and infrastructure are currently organized and how they will evolve.

---

## 1. Current Setup

### 1.1 Code Repository and Deployment
- A code repository exists, using a traditional (on-premises-alike) deployment pipelines.
- Multiple environment-specific variables are used:
  - Example:  
    - `AppSettings__AWSS3URL` and `REACT_APP_AWS_S3_BUCKET_NAME`  
      - Both reference the same bucket but use different variables.  
    - `DEMO_CONNECTION_STRING_P` and `DEMO_CONNECTION_STRING`  
      - One is for production, and the other for QA environments.

### 1.2 Infrastructure
- Infrastructure is in place to handle different environment-specific variables for various deployment targets.

---

## 2. Control Environment Configuration

### 2.1 Developer Responsibilities
1. Maintain a code repository with separate Dockerfiles and GitHub Actions push workflows (CI Pipeline)  
   - Builds and pushes standalone images to a container registry.
2. Secrets from GitHub Actions variables will be stored in AWS Secrets Manager.
3. Provide Dockerfiles and Docker run/compose commands for running the applications.
4. Perform end-to-end testing to ensure containerized applications are production-ready.

### 2.2 DevOps Responsibilities
1. Manage an AWS infrastructure repository following cloud-native best practices. ( CD Pipeline)
   - Setup includes one EC2 instance (PROD), AWS Secrets Manager, and ECR for image storage.


[![image.png](https://i.postimg.cc/tgDdNCR3/image.png)](https://postimg.cc/SX2zy4MR)](https://postimg.cc/vcT8Rz9H)


---
## 3. Migrtion Phase-1

### 3.1 Developer Responsibilities
same as 2.1

### 3.2 DevOps Responsibilities
1. Manage an AWS infrastructure repository following cloud-native best practices. ( CD Pipeline)
   - Setup includes one EC2 instance, RDS, AWS Secrets Manager, and ECR for image storage.
2. Provision a single production instance in Azure.  
   - Existing configuration remains:
     - Azure VM and Azure Database will be used.  
     - Files continue to reside on S3, secrets in AWS Secrets Manager, and images in ECR.

[![image.png](https://i.postimg.cc/CK5rPHw1/image.png)](https://postimg.cc/VSyF5trQ)

---

## 4. Migration Phase-2

### 4.1 Developer Tasks
1. The development team will maintain the entire continuous integration pipeline.
2. Update the code repository to build and push standalone images to the container registry.  
   - Merging into the main branch triggers a release build that automatically pushes to Azure Container Registry (ACR).
3. Define global variables, optimize code, and move secrets to Azure Key Vault.  
   - Use a consistent naming convention with environment prefixes (e.g., `prod/****` or `qa/***`)  
   - All applications share global variables; differentiation occurs based on GitHub Actions triggers (QA or Prod).
4. Migrate AWS services to Azure equivalents:  
   - S3 → Azure Blob Storage  
   - ECR → ACR  
   - AWS Secrets Manager → Azure Key Vault  
   - Transfer access keys with minimal disruption.
5. Continue providing end-to-end testing to validate containerized applications.

### 4.2 DevOps Tasks
1. Introduce and maintain a new deployment pipeline with Infrastructure as Code (Terraform).
2. Create an Azure infrastructure repository using fully cloud-native architecture.  
   - Use Virtual Machine Scale Sets (VMSS), Azure DNS, and Azure Load Balancer services.  
   - Move secrets from AWS Secrets Manager to Azure Key Vault.  
   - Transition images from ECR to ACR.  
   - Replace S3 with Azure Blob Storage, including backup best practices.
3. Deploy a load-balanced system aligned with Azure’s cloud-native recommendations.

[![![image.png](https://i.postimg.cc/T3QX8FRR/image.png)](https://postimg.cc/FYf63Pdq)

[![image.png](https://i.postimg.cc/g2tBHWz6/image.png)](https://postimg.cc/w1JV9ns6)

---

