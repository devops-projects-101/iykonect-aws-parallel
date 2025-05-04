#!/bin/bash

# Ensure script runs as root
if [ "$(id -u)" != "0" ]; then
   exec sudo "$0" "$@"
fi

set -e

# Logging function
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
}

# Export AWS credentials for ECR access
export AWS_ACCESS_KEY_ID="${aws_access_key}"
export AWS_SECRET_ACCESS_KEY="${aws_secret_key}"
export AWS_DEFAULT_REGION="${aws_region}"

# Initial setup
log "Starting initial setup on Azure VM..."
apt-get update && apt-get install -y awscli jq apt-transport-https ca-certificates curl gnupg lsb-release htop unzip azure-cli
log "Package installation completed"

# Set Azure-specific variables
AZURE_VM="true"
HOSTNAME=$(hostname)
PUBLIC_IP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text")
PRIVATE_IP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2021-02-01&format=text")
log "Instance info: VM=${HOSTNAME}, Public IP=${PUBLIC_IP}, Private IP=${PRIVATE_IP}"

# Create directories for the repository
log "Creating directories for repository..."
mkdir -p /opt/iykonect-aws-repo

# Download code from AWS S3 (using hardcoded bucket and path)
log "Downloading code repository from AWS S3..."
aws s3 cp s3://iykonect-aws-parallel/code-deploy/repo-content.zip /tmp/repo-content.zip
if [ $? -ne 0 ]; then
    log "ERROR: Failed to download repository content from S3."
    exit 1
fi

# Extract repository content directly to /opt
log "Extracting repository content to /opt/iykonect-aws-repo..."
unzip -q /tmp/repo-content.zip -d /opt/iykonect-aws-repo
rm -f /tmp/repo-content.zip
log "Repository content extracted successfully"

# Set execute permissions on all shell scripts
log "Setting execute permissions on scripts..."
find /opt/iykonect-aws-repo -name "*.sh" -exec chmod +x {} \;

# Create symlinks to the script directory for easier access
mkdir -p /opt/iykonect-aws
ln -sf /opt/iykonect-aws-repo/terraform/modules/ec2/scripts/secrets-setup.sh /opt/iykonect-aws/
ln -sf /opt/iykonect-aws-repo/terraform/modules/ec2/scripts/docker-setup.sh /opt/iykonect-aws/
ln -sf /opt/iykonect-aws-repo/terraform/modules/ec2/scripts/status-setup.sh /opt/iykonect-aws/

# Execute status command setup
log "Running status command setup..."
/opt/iykonect-aws-repo/terraform/modules/ec2/scripts/status-setup.sh
log "Status command setup completed"

# We're not setting up CloudWatch on Azure, but we'll set up Azure Monitor instead
log "Setting up Azure Monitor agent..."
curl -sL https://aka.ms/InstallAzureMonitorLinuxAgent | sudo bash
log "Azure Monitor setup completed"

# Execute Secret Manager setup (using AWS Secrets Manager as requested)
log "Running AWS Secrets Manager setup..."
/opt/iykonect-aws-repo/terraform/modules/ec2/scripts/secrets-setup.sh
log "Secrets Manager setup completed"

# Execute Docker setup
log "Running Docker setup and deployment..."
/opt/iykonect-aws-repo/terraform/modules/ec2/scripts/docker-setup.sh
log "Docker setup and deployment completed"

# Final status
log "=== Azure VM User Data Script Complete ==="