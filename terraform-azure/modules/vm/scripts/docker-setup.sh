#!/bin/bash

# Azure-specific Docker setup script for IYKonect infrastructure

set -e

# Logging function

log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
}


log "Starting from docker setup"

# Source VM metadata from the permanent manifest file
METADATA_FILE="/opt/iykonect/metadata/vm_metadata.sh"

log "Loading VM metadata from $METADATA_FILE"
source "$METADATA_FILE"

log "==============================================="
log "Starting Azure-specific Docker installation and setup"
log "==============================================="

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