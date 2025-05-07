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




# Create backup directories
log "Creating backup directories..."
mkdir -p /opt/iykonect/backups/scripts
mkdir -p /opt/iykonect/backups/env

# Backup this script
log "Backing up user-data script..."
cp "$0" /opt/iykonect/backups/scripts/user-data.sh.$(date +%Y%m%d_%H%M%S)
chmod 600 /opt/iykonect/backups/scripts/user-data.sh.*

# Update package repositories and install required packages
log "Updating package repositories and installing required packages..."
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

# Set variables directly from Terraform
log "Setting up configuration variables..."
aws_access_key="${aws_access_key}"
aws_secret_key="${aws_secret_key}"
aws_region="${aws_region}"
admin_username="${admin_username}"


aws_region="eu-west-1"


log "Configuration values set successfully"
log "AWS Region: $aws_region"
log "Admin Username: $admin_username"


# Export AWS credentials for ECR access
export AWS_ACCESS_KEY_ID="$aws_access_key"
export AWS_SECRET_ACCESS_KEY="$aws_secret_key"
export AWS_DEFAULT_REGION="$aws_region"

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

# Set Azure-specific variables at runtime
# Using BASH_VAR format for variables that should be determined at runtime
AZURE_VM="true"

# Using single quotes to prevent Terraform from processing these as template variables
log 'Getting Azure VM metadata at runtime...'
log 'Hostname, IP addresses, and other Azure metadata will be determined when the script runs on the VM'

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
cat > /opt/iykonect/backups/deployment_manifest_$DEPLOY_TIMESTAMP.txt << EOF
Deployment Timestamp: $DEPLOY_TIMESTAMP
VM Name: $VM_NAME
Resource Group: $RESOURCE_GROUP
Location: $LOCATION
Public IP: $PUBLIC_IP
Private IP: $PRIVATE_IP
AWS Region: $AWS_DEFAULT_REGION
EOF

chmod 600 /opt/iykonect/backups/deployment_manifest_$DEPLOY_TIMESTAMP.txt

# Download code from AWS S3
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

# Create symlinks to the Azure script directory for easier access
mkdir -p /opt/iykonect-azure
ln -sf /opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/azure-monitor-setup.sh /opt/iykonect-azure/
ln -sf /opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/container-health-check.sh /opt/iykonect-azure/
ln -sf /opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/docker-setup.sh /opt/iykonect-azure/
ln -sf /opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/redeploy.sh /opt/iykonect-azure/
ln -sf /opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/secrets-setup.sh /opt/iykonect-azure/
ln -sf /opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/status-setup.sh /opt/iykonect-azure/

# Execute Azure metadata collection at runtime
# This is done here to avoid Terraform template variable issues
cat > /opt/get-azure-metadata.sh << 'EOFMETADATA'
#!/bin/bash
# This script runs at VM boot time and collects Azure metadata
LOCAL_VM_HOSTNAME=$(hostname)
PUBLIC_IP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text")
PRIVATE_IP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2021-02-01&format=text")
RESOURCE_GROUP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text")
LOCATION=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")

# Log the collected metadata
echo "[$(date)] Instance info: VM=$LOCAL_VM_HOSTNAME, Location=$LOCATION, Public IP=$PUBLIC_IP, Private IP=$PRIVATE_IP" | sudo tee -a /var/log/user-data.log

# Export variables for other scripts
export LOCAL_VM_HOSTNAME
export PUBLIC_IP
export PRIVATE_IP
export RESOURCE_GROUP
export LOCATION
EOFMETADATA

chmod +x /opt/get-azure-metadata.sh
/opt/get-azure-metadata.sh

# Execute Azure-specific status command setup
log "Running Azure status command setup..."
/opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/status-setup.sh
log "Azure status command setup completed"

# Execute Azure-specific Secret Manager setup
log "Running Azure secrets setup..."
/opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/secrets-setup.sh
log "Azure secrets setup completed"

# Execute Azure Monitor setup - COMMENTED OUT PER REQUEST
log "Skipping Azure Monitor setup as requested..."
# /opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/azure-monitor-setup.sh
# log "Azure Monitor setup completed"

# Execute Azure-specific Docker setup and deployment
log "Running Azure Docker setup and deployment..."
/opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/docker-setup.sh
log "Azure Docker setup and deployment completed"

# Create a logs dashboard shortcut
log "Creating logs dashboard shortcut..."
cat > /usr/local/bin/logs-dashboard << 'EOF'
#!/bin/bash
echo "=============================================="
echo "    IYKonect Azure Dashboard Access URLs     "
echo "=============================================="
echo ""
echo "Last 20 lines of user-data.log:"
echo "--------------------------------------------"
tail -n 20 /var/log/user-data.log
echo ""
echo "For more logs, use: tail -n 100 /var/log/user-data.log"
echo "=============================================="
EOF
chmod +x /usr/local/bin/logs-dashboard

# Add logs-dashboard to aliases
mkdir -p /etc/profile.d
echo "alias logs-dashboard='/usr/local/bin/logs-dashboard'" >> /etc/profile.d/iykonect-welcome.sh
chmod +x /etc/profile.d/iykonect-welcome.sh

# Final status
log "=== Azure VM User Data Script Complete ==="