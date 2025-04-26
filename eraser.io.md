title Iykonect AWS Parallel: Terraform Infrastructure & Monitoring

User [icon: user]

GitHub Actions [icon: github] {
  Iykons Deploy Workflow [icon: git-branch, label: "Deploy Workflow"]
  Checkout Code [icon:git-commit, label:"Checkout Code"]
  Terraform Init [icon:terraform, label:"Terraform Init"] 
  Terraform Validate [icon:terraform, label:"Terraform Validate"]
  Terraform Plan [icon:terraform, label:"Terraform Plan"]
  Terraform Apply [icon:terraform, label:"Terraform Apply"]
  Generate Diagram [icon:image, label:"Generate Infrastructure Diagram"]
}

AWS [icon: aws] {
  
  S3 Bucket [icon: aws-s3, label: "iykonect-aws-parallel"] {
    Terraform State [icon: aws-s3, label: "terraform.tfstate"]
    Infrastructure Diagrams [icon: aws-s3, label: "diagrams/"]
  }
  
  CloudWatch Dashboard [icon: aws-cloudwatch, label: "Dashboard"]
  Secrets Manager [icon: aws-secrets-manager]
  
  Iykonect VPC [icon: aws-vpc] {
    Public Subnet [icon: aws-subnet-public] {
      EC2 Instance [icon: aws-ec2, label: "Ubuntu 20.04"] {
        Docker [icon: docker] {
          API Container [icon: package, label: "api"]
          React App Container [icon: react, label: "react-app"]
          Prometheus Container [icon: prometheus, label: "prometheus"]
          Grafana Container [icon: grafana, label: "grafana"]
          SonarQube Container [icon: sonarqube, label: "sonarqube"]
        }
        CloudWatch Agent [icon: aws-cloudwatch]
        EC2 IAM Role [icon:aws-iam, label:"EC2 Role"]
        EC2 IAM Policies [icon:aws-iam-policy, label:"S3/ECR Access"]
      }
      Security Group [icon: aws-security-group, label: "Instance SG"]
    }
  }
}

Terraform [icon: terraform]

// Connections
User > GitHub Actions: "trigger PR/push"
GitHub Actions > Terraform: "run init/plan/apply"
Terraform > S3 Bucket.Terraform State: store state
Terraform > AWS: provision resources

// Docker Services
EC2 Instance > Docker: runs containers
Docker > API Container: host
Docker > React App Container: host
Docker > Prometheus Container: monitoring
Docker > Grafana Container: dashboards
Docker > SonarQube Container: code quality

// Monitoring & Logging
CloudWatch Agent > CloudWatch Dashboard: "send metrics/logs"

// User Access
User > API Container: API access
User > React App Container: web access
User > Grafana Container: monitoring dashboards
User > SonarQube Container: code quality reports

// IAM & Security
EC2 IAM Role > EC2 Instance: attach role
EC2 IAM Policies > EC2 IAM Role: attach policies
Security Group > EC2 Instance: control access

// GitHub Actions Workflow
Iykons Deploy Workflow > Checkout Code: "checkout"
Checkout Code > Terraform Init: "initialize"
Terraform Init > Terraform Validate: "validate"
Terraform Validate > Terraform Plan: "plan"
Terraform Plan > Terraform Apply: "apply if approved"
Terraform Apply > Generate Diagram: "create visualization"
Generate Diagram > S3 Bucket.Infrastructure Diagrams: "upload diagrams"

// Other Connections
EC2 Instance > S3 Bucket: "access permissions"
Secrets Manager > EC2 Instance: "fetch secrets"
