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
apt-get update && apt-get install -y awscli jq apt-transport-https ca-certificates curl gnupg lsb-release htop collectd git
log "Package installation completed"

# Get instance metadata
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
log "Instance info: Region=${AWS_REGION}, ID=${INSTANCE_ID}, IP=${PUBLIC_IP}"

# Create directory for the repository
log "Creating directory for repository..."
mkdir -p /opt/iykonect-aws

# Clone the entire repository
log "Cloning the entire repository..."
git clone --depth=1 https://github.com/iykonect/iykonect-aws-parallel.git /opt/iykonect-aws-repo
if [ $? -ne 0 ]; then
    log "ERROR: Failed to clone repository. Creating local scripts..."
    
    # If git clone fails, create local scripts (this is just a fallback)
    log "Creating local setup scripts as fallback..."
    mkdir -p /opt/iykonect-aws/scripts
    
    # You could add fallback script content here if needed
    # For now, we'll exit with an error since we're expecting the git clone to work
    log "CRITICAL ERROR: Could not clone repository and no fallback scripts are defined."
    exit 1
else
    log "Repository cloned successfully to /opt/iykonect-aws-repo"
    
    # Set execute permissions on all shell scripts
    log "Setting execute permissions on scripts..."
    find /opt/iykonect-aws-repo -name "*.sh" -exec chmod +x {} \;
    
    # Create symlinks to the script directory for easier access
    ln -sf /opt/iykonect-aws-repo/terraform/modules/ec2/scripts/cloudwatch-setup.sh /opt/iykonect-aws/
    ln -sf /opt/iykonect-aws-repo/terraform/modules/ec2/scripts/secrets-setup.sh /opt/iykonect-aws/
    ln -sf /opt/iykonect-aws-repo/terraform/modules/ec2/scripts/docker-setup.sh /opt/iykonect-aws/
    ln -sf /opt/iykonect-aws-repo/terraform/modules/ec2/scripts/status-setup.sh /opt/iykonect-aws/
fi

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
log "=== Deployment Complete ==="
log "API URL: http://${PUBLIC_IP}:8000"
log "Web URL: http://${PUBLIC_IP}:5001"
log "Signable URL: http://${PUBLIC_IP}:8082"
log "Email Server URL: http://${PUBLIC_IP}:8025"
log "Company House URL: http://${PUBLIC_IP}:8083"
log "Redis Port: ${PUBLIC_IP}:6379"
log "Prometheus URL: http://${PUBLIC_IP}:9090"
log "Grafana URL: http://${PUBLIC_IP}:3100"
log "Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=IYKonect-Dashboard-${INSTANCE_ID}"