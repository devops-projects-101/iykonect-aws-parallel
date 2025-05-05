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
    software-properties-common

aws_region="eu-west-1"

# Export AWS credentials for ECR access
export AWS_ACCESS_KEY_ID="${aws_access_key}"
export AWS_SECRET_ACCESS_KEY="${aws_secret_key}"
export AWS_DEFAULT_REGION="eu-west-1"

# Create AWS credentials for both root and admin user
log "Setting up AWS credentials..."
mkdir -p /home/${admin_username}/.aws
cat > /home/${admin_username}/.aws/credentials << EOC
[default]
aws_access_key_id = ${aws_access_key}
aws_secret_access_key = ${aws_secret_key}
region = eu-west-1
EOC

cat > /home/${admin_username}/.aws/config << EOC
[default]
region = eu-west-1
output = json
EOC

chown -R ${admin_username}:${admin_username} /home/${admin_username}/.aws
chmod 600 /home/${admin_username}/.aws/credentials
chmod 600 /home/${admin_username}/.aws/config

# Also set up root AWS credentials for system-level operations
mkdir -p /root/.aws
cp /home/${admin_username}/.aws/credentials /root/.aws/
cp /home/${admin_username}/.aws/config /root/.aws/
chmod 600 /root/.aws/credentials
chmod 600 /root/.aws/config

# Set Azure-specific variables at runtime, not through template
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

# Install Azure CLI for better integration with Azure services
log "Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | bash
log "Azure CLI installation completed"

# Install Azure Monitor agent properly for Ubuntu 20.04
log "Installing Azure Monitor agent..."
# First, add Microsoft repository and signing key
wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

# Update apt and install the Log Analytics agent instead of azure-monitor-agent
# which is not available for Ubuntu 20.04 in the standard repositories
apt-get update
apt-get install -y microsoft-monitoring-agent

# Install the dependency agent for enhanced monitoring
curl -sSO https://aka.ms/dependencyagentlinux
sh ./dependencyagentlinux
rm ./dependencyagentlinux

log "Azure Monitoring agents installation completed"

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

# Execute Azure Monitor setup
log "Running Azure Monitor setup..."
/opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/azure-monitor-setup.sh
log "Azure Monitor setup completed"

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