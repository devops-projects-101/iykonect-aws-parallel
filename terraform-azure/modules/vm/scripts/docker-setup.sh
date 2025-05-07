#!/bin/bash

# Azure-specific Docker setup script for IYKonect infrastructure

set -e

# Logging function
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
}

# Source VM metadata from the permanent manifest file
METADATA_FILE="/opt/iykonect/metadata/vm_metadata.sh"

log "Loading VM metadata from $METADATA_FILE"
source "$METADATA_FILE"

log "==============================================="
log "Starting Azure-specific Docker installation and setup"
log "==============================================="
log "VM Information:"
log "Name: $VM_NAME"
log "Resource Group: $RESOURCE_GROUP"
log "Location: $LOCATION"
log "Public IP: $PUBLIC_IP"
log "Private IP: $PRIVATE_IP"
log "Repository Location: $AZURE_REPO_LOCATION"

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

# Copy Nginx configuration files from repository
log "Copying Nginx configuration files..."
cp $AZURE_REPO_LOCATION/terraform-azure/modules/vm/scripts/nginx.conf /opt/iykonect/nginx/
cp $AZURE_REPO_LOCATION/terraform-azure/modules/vm/scripts/default.conf /opt/iykonect/nginx/conf.d/

# Now that Docker is installed, call redeploy.sh to handle container deployment
log "==============================================="
log "Calling redeploy.sh to handle container deployment"
log "==============================================="

# Set environment variables for redeploy.sh
export AZURE_VM=true

# Call redeploy.sh to handle deployment
$AZURE_REPO_LOCATION/terraform-azure/modules/vm/scripts/redeploy.sh

# Final message
log "==============================================="
log "Docker installation and deployment complete"
log "==============================================="