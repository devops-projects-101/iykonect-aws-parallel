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


# Set default AWS region if not provided
if [ -z "$aws_region" ]; then
    log "AWS region not provided, using default: eu-west-1"
    aws_region="eu-west-1"
fi



log "Configuration values set successfully"
log "VM Name: $vm_name"
log "Resource Group: $resource_group"
log "Location: $location"
log "Public IP: $public_ip"
log "Private IP: $private_ip"
log "AWS Region: $aws_region"
log "Admin Username: $admin_username"


# Set repo location
AZURE_REPO_LOCATION="/opt/iykonect-repo"
log "Azure repo location: $AZURE_REPO_LOCATION"

# Use Azure Instance Metadata Service if any values are missing
if [ -z "$vm_name" ] || [ -z "$resource_group" ] || [ -z "$location" ] || [ -z "$public_ip" ] || [ -z "$private_ip" ]; then
    log "Some metadata values missing, using Azure Instance Metadata Service to fill gaps..."
    
    if [ -z "$vm_name" ]; then
        vm_name=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text")
        log "Retrieved VM name: $vm_name"
    fi
    
    if [ -z "$resource_group" ]; then
        resource_group=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text")
        log "Retrieved resource group: $resource_group"
    fi
    
    if [ -z "$location" ]; then
        location=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")
        log "Retrieved location: $location"
    fi
    
    if [ -z "$public_ip" ]; then
        public_ip=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text")
        log "Retrieved public IP: $public_ip"
    fi
    
    if [ -z "$private_ip" ]; then
        private_ip=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2021-02-01&format=text")
        log "Retrieved private IP: $private_ip"
    fi
fi

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
export AZURE_REPO_LOCATION="$AZURE_REPO_LOCATION"

# Create permanent VM metadata manifest file that can be sourced by other scripts
log "Creating permanent VM metadata manifest file..."
MANIFEST_DIR="/opt/iykonect/metadata"
mkdir -p $MANIFEST_DIR

cat > $MANIFEST_DIR/vm_metadata.sh << EOF
#!/bin/bash
# This file contains VM metadata and is automatically generated
# Last updated: $(date)

# Repository Location
export AZURE_REPO_LOCATION="$AZURE_REPO_LOCATION"

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
mkdir -p $AZURE_REPO_LOCATION
mkdir -p /opt/iykonect/config
mkdir -p /opt/iykonect/env
mkdir -p /opt/iykonect/prometheus
mkdir -p /opt/iykonect/grafana
mkdir -p /opt/iykonect/nginx
mkdir -p /opt/iykonect/nginx/conf.d
mkdir -p /opt/iykonect/logs
mkdir -p /opt/iykonect/backups/env
mkdir -p /opt/iykonect/backups/scripts
mkdir -p /opt/iykonect-azure

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
Repository Location: $AZURE_REPO_LOCATION
EOF

log "Deployment manifest created at /opt/iykonect/backups/deployment_manifest_$DEPLOY_TIMESTAMP.txt"

# Create a backup directory for deployment scripts
mkdir -p /opt/iykonect/backups/scripts

# Download latest release from S3 bucket instead of git clone
log "Downloading latest release from S3 bucket..."
cd /tmp
aws s3 cp s3://iykonect-aws-parallel/code-deploy/repo-content.zip /tmp/repo-content.zip

if [ $? -ne 0 ]; then
    log "ERROR: Failed to download repository content from S3."
    exit 1
fi

# Extract only VM scripts to repo location instead of everything
log "Extracting VM scripts from repository content..."
mkdir -p /tmp/repo-extract
unzip -q /tmp/repo-content.zip -d /tmp/repo-extract/

# Create repo directory and copy only needed VM scripts
log "Copying VM scripts to $AZURE_REPO_LOCATION..."
mkdir -p $AZURE_REPO_LOCATION/terraform-azure/modules/vm/scripts

# Copy only the VM scripts
cp -r /tmp/repo-extract/terraform-azure/modules/vm/scripts/* $AZURE_REPO_LOCATION/terraform-azure/modules/vm/scripts/

# Remove temporary extraction directory
rm -rf /tmp/repo-extract
rm -f /tmp/repo-content.zip
log "Repository content extracted and organized successfully"

# Make all scripts executable
log "Setting execute permissions on scripts..."
find $AZURE_REPO_LOCATION -name "*.sh" -exec chmod +x {} \;

# Create symbolic links for frequently used scripts
ln -sf $AZURE_REPO_LOCATION/terraform-azure/modules/vm/scripts/docker-setup.sh /opt/iykonect-azure/
ln -sf $AZURE_REPO_LOCATION/terraform-azure/modules/vm/scripts/redeploy.sh /opt/iykonect-azure/
ln -sf $AZURE_REPO_LOCATION/terraform-azure/modules/vm/scripts/secrets-setup.sh /opt/iykonect-azure/
ln -sf $AZURE_REPO_LOCATION/terraform-azure/modules/vm/scripts/status-setup.sh /opt/iykonect-azure/
ln -sf $AZURE_REPO_LOCATION/terraform-azure/modules/vm/scripts/container-health-check.sh /opt/iykonect-azure/

# Copy nginx configuration to the nginx directory
cp $AZURE_REPO_LOCATION/terraform-azure/modules/vm/scripts/nginx.conf /opt/iykonect/nginx/
cp $AZURE_REPO_LOCATION/terraform-azure/modules/vm/scripts/default.conf /opt/iykonect/nginx/conf.d/


log "Initial setup completed successfully"

# Execute status command setup
log "Running status command setup..."
/opt/iykonect-azure/status-setup.sh
log "Status command setup completed"

# Execute Docker setup
log "Running Docker setup and deployment..."
/opt/iykonect-azure/docker-setup.sh
log "Docker setup and deployment completed"

# Final status
log "=== Main User Data Script Complete ==="