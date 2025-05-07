#!/bin/bash

# Azure-specific Docker setup script for IYKonect infrastructure

set -e

# Logging function
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
}

# Source VM metadata from the permanent manifest file
METADATA_FILE="/opt/iykonect/metadata/vm_metadata.sh"

if [ -f "$METADATA_FILE" ]; then
    log "Loading VM metadata from $METADATA_FILE"
    source "$METADATA_FILE"
    log "Metadata loaded successfully"
else
    log "Metadata file not found, falling back to Azure Instance Metadata Service"
    # Fallback to Azure Instance Metadata Service
    VM_NAME=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text")
    RESOURCE_GROUP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text")
    LOCATION=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")
    PUBLIC_IP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text")
    PRIVATE_IP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2021-02-01&format=text")
fi

log "==============================================="
log "Starting Azure-specific Docker installation and setup"
log "==============================================="
log "VM Information:"
log "Name: $VM_NAME"
log "Resource Group: $RESOURCE_GROUP"
log "Location: $LOCATION"
log "Public IP: $PUBLIC_IP"
log "Private IP: $PRIVATE_IP"

# Install Docker
log "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

# System settings
log "Configuring system settings for Docker..."
echo "fs.inotify.max_user_watches = 524288" >> /etc/sysctl.conf
sysctl -p

# Install Docker packages
log "Installing Docker packages..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io
systemctl enable docker
systemctl start docker

# Docker basic setup
log "Setting up Docker environment..."
docker system prune -af

# Create necessary directories for application
log "Creating application directories..."
mkdir -p /opt/iykonect/config
mkdir -p /opt/iykonect/env
mkdir -p /opt/iykonect/prometheus
mkdir -p /opt/iykonect/grafana
mkdir -p /opt/iykonect/logs
mkdir -p /opt/iykonect/nginx/conf.d

# Copy Nginx configuration files from scripts directory
log "Copying Nginx configuration files..."
cp /opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/nginx.conf /opt/iykonect/nginx/
cp /opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/default.conf /opt/iykonect/nginx/conf.d/

# Ensure the scripts are executable
log "Setting execute permissions on scripts..."
chmod +x /opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/container-health-check.sh
chmod +x /opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/redeploy.sh

# Now that Docker is installed, call redeploy.sh to handle container deployment
log "==============================================="
log "Calling redeploy.sh to handle container deployment"
log "==============================================="

# Set environment variables for redeploy.sh
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-eu-west-1}
export AZURE_VM=true
export AZURE_LOCATION=$LOCATION
export AZURE_RESOURCE_GROUP=$RESOURCE_GROUP

# Call redeploy.sh to handle deployment
/opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/redeploy.sh

# Final message
log "==============================================="
log "Docker installation and deployment complete"
log "==============================================="