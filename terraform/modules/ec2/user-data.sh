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

# Initial setup
log "Starting initial setup..."
apt-get update && apt-get install -y awscli jq apt-transport-https ca-certificates curl gnupg lsb-release htop collectd unzip cowsay
log "Package installation completed"

# Get instance metadata
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
log "Instance info: Region=${AWS_REGION}, ID=${INSTANCE_ID}, IP=${PUBLIC_IP}"

# Create directories for the repository
log "Creating directories for repository..."
mkdir -p /opt/iykonect-aws-repo

# Download code from S3 (using hardcoded bucket and path)
log "Downloading code repository from S3..."
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
ln -sf /opt/iykonect-aws-repo/terraform/modules/ec2/scripts/cloudwatch-setup.sh /opt/iykonect-aws/
ln -sf /opt/iykonect-aws-repo/terraform/modules/ec2/scripts/secrets-setup.sh /opt/iykonect-aws/
ln -sf /opt/iykonect-aws-repo/terraform/modules/ec2/scripts/docker-setup.sh /opt/iykonect-aws/
ln -sf /opt/iykonect-aws-repo/terraform/modules/ec2/scripts/status-setup.sh /opt/iykonect-aws/

# Execute status command setup
log "Running status command setup..."
/opt/iykonect-aws-repo/terraform/modules/ec2/scripts/status-setup.sh
log "Status command setup completed"

# Execute CloudWatch setup
log "Running CloudWatch setup..."
/opt/iykonect-aws-repo/terraform/modules/ec2/scripts/cloudwatch-setup.sh
log "CloudWatch setup completed"

# Execute Secret Manager setup
log "Running Secrets Manager setup..."
/opt/iykonect-aws-repo/terraform/modules/ec2/scripts/secrets-setup.sh
log "Secrets Manager setup completed"

# Execute Docker setup
log "Running Docker setup and deployment..."
/opt/iykonect-aws-repo/terraform/modules/ec2/scripts/docker-setup.sh
log "Docker setup and deployment completed"

# Final status
log "=== Main User Data Script Complete ==="