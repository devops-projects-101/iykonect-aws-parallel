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

log "Starting initial setup on Azure VM..."

# Install required packages
log "Installing required packages..."
apt-get update
apt-get install -y \
    awscli \
    jq \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    htop \
    unzip \
    software-properties-common \
    azure-cli

# Create a timestamp for the current deployment
DEPLOY_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Set variables directly from Terraform input
log "Setting up configuration variables..."
aws_access_key="${aws_access_key}"
aws_secret_key="${aws_secret_key}"
aws_region="${aws_region}"
admin_username="${admin_username}"
vm_name="${vm_name}"
resource_group="${resource_group}"
location="${location}"
public_ip="${public_ip}"
private_ip="${private_ip}"

log "Configuration values set successfully"
log "VM Name: $vm_name"
log "Resource Group: $resource_group"
log "Location: $location"
log "Public IP: $public_ip"
log "Private IP: $private_ip"
log "AWS Region: $aws_region"
log "Admin Username: $admin_username"

# Export AWS credentials for ECR access
export AWS_ACCESS_KEY_ID="$aws_access_key"
export AWS_SECRET_ACCESS_KEY="$aws_secret_key"
export AWS_DEFAULT_REGION="$aws_region"

# Export Azure variables for other scripts
export VM_NAME="$vm_name"
export RESOURCE_GROUP="$resource_group"
export LOCATION="$location"
export PUBLIC_IP="$public_ip"
export PRIVATE_IP="$private_ip"

# Create permanent VM metadata manifest file that can be sourced by other scripts
log "Creating permanent VM metadata manifest file..."
MANIFEST_DIR="/opt/iykonect/metadata"
mkdir -p $MANIFEST_DIR

cat > $MANIFEST_DIR/vm_metadata.sh << EOF
#!/bin/bash
# This file contains VM metadata and is automatically generated
# Last updated: $(date)

# Azure VM Metadata
export VM_NAME="$vm_name"
export RESOURCE_GROUP="$resource_group"
export LOCATION="$location"
export PUBLIC_IP="$public_ip"
export PRIVATE_IP="$private_ip"

# AWS Configuration
export AWS_DEFAULT_REGION="$aws_region"
EOF

chmod 644 $MANIFEST_DIR/vm_metadata.sh
log "VM metadata manifest created at $MANIFEST_DIR/vm_metadata.sh"

# Create AWS credentials for both root and admin user
log "Setting up AWS credentials..."
mkdir -p /home/$admin_username/.aws
cat > /home/$admin_username/.aws/credentials << EOC
[default]
aws_access_key_id = $aws_access_key
aws_secret_access_key = $aws_secret_key
region = $aws_region
EOC

cat > /home/$admin_username/.aws/config << EOC
[default]
region = $aws_region
output = json
EOC

chown -R $admin_username:$admin_username /home/$admin_username/.aws
chmod 600 /home/$admin_username/.aws/credentials
chmod 600 /home/$admin_username/.aws/config

# Also set up root AWS credentials for system-level operations
mkdir -p /root/.aws
cp /home/$admin_username/.aws/credentials /root/.aws/
cp /home/$admin_username/.aws/config /root/.aws/
chmod 600 /root/.aws/credentials
chmod 600 /root/.aws/config

# After setting up AWS credentials, backup the credentials
log "Backing up AWS credentials..."
mkdir -p /opt/iykonect/backups/aws
cp -r /root/.aws /opt/iykonect/backups/aws/credentials.$DEPLOY_TIMESTAMP
chmod -R 600 /opt/iykonect/backups/aws

# Set Azure-specific variables
AZURE_VM="true"

# Create directories for the repository and necessary config directories
log "Creating directories for repository and configurations..."
mkdir -p /opt/iykonect-aws-repo
mkdir -p /opt/iykonect/config
mkdir -p /opt/iykonect/env
mkdir -p /opt/iykonect/prometheus
mkdir -p /opt/iykonect/grafana
mkdir -p /opt/iykonect/logs
mkdir -p /opt/iykonect/backups/env
mkdir -p /opt/iykonect/backups/scripts

# After setting environment variables, create a snapshot
log "Creating environment variables snapshot..."
env | grep -v "^_" > /opt/iykonect/backups/env/environment.$DEPLOY_TIMESTAMP

# Create a deployment manifest
log "Creating deployment manifest..."
cat > /opt/iykonect/backups/deployment_manifest_$DEPLOY_TIMESTAMP.txt << EOF
Deployment Timestamp: $DEPLOY_TIMESTAMP
VM Name: $VM_NAME
Resource Group: $RESOURCE_GROUP
Location: $LOCATION
Public IP: $PUBLIC_IP
Private IP: $PRIVATE_IP
AWS Region: $AWS_DEFAULT_REGION
EOF

log "Deployment manifest created at /opt/iykonect/backups/deployment_manifest_$DEPLOY_TIMESTAMP.txt"

# Create a backup directory for deployment scripts
mkdir -p /opt/iykonect/backups/scripts

# Clone the repository for configuration files or copy from mounted disk
log "Setting up repository for configuration files..."
git config --global credential.helper store
cd /opt/iykonect-aws-repo
git clone https://github.com/organization/iykonect-aws-repo.git . || echo "Warning: Unable to clone the repository, using local files instead"

# Make scripts executable and create Azure-specific directory
mkdir -p /opt/iykonect-azure
ln -sf /opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/docker-setup.sh /opt/iykonect-azure/
ln -sf /opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/redeploy.sh /opt/iykonect-azure/
ln -sf /opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/secrets-setup.sh /opt/iykonect-azure/
ln -sf /opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/status-setup.sh /opt/iykonect-azure/

# Execute Azure-specific status command setup
log "Running Azure status command setup..."
/opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/status-setup.sh
log "Azure status command setup completed"

# Execute Azure-specific Secret Manager setup
log "Running Azure-specific secrets setup..."
/opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/secrets-setup.sh
log "Azure secrets setup completed"

# Execute Docker setup
log "Running Docker setup and configuration..."
/opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/docker-setup.sh
log "Docker setup and configuration completed"

# Execute Docker container deployment
log "Running container deployment..."
/opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/redeploy.sh
log "Container deployment completed"

log "Azure VM setup completed successfully!"