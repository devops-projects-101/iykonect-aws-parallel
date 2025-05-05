#!/bin/bash

# Enhanced Azure Monitor setup script with dashboard for user-data.log visualization

set -e

# Logging function
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/azure-monitor-setup.log
}

log "Starting enhanced Azure Monitor setup..."

# Get instance metadata for Azure
VM_NAME=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text")
RESOURCE_GROUP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text")
SUBSCRIPTION_ID=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/subscriptionId?api-version=2021-02-01&format=text")
LOCATION=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")

log "VM Information:"
log "Name: $VM_NAME"
log "Resource Group: $RESOURCE_GROUP"
log "Subscription ID: $SUBSCRIPTION_ID"
log "Location: $LOCATION"

# Install Azure Monitor agent using packages instead of the redirection script
log "Installing Azure Monitor agent using direct package installation..."
# Add Microsoft signing key and repo
wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

# Update package lists and install Azure Monitor agent
apt-get update
apt-get install -y azure-monitor-agent

# Configure Azure Monitor to collect Docker metrics
log "Configuring Azure Monitor to collect Docker metrics..."
mkdir -p /etc/azuremonitoragent/config-cache/configchunks

# Create Docker metrics collection configuration
cat > /etc/azuremonitoragent/config-cache/configchunks/docker.json << 'EOF'
{
  "logs": [
    {
      "name": "dockerContainerLogs",
      "streams": ["stdout", "stderr"],
      "extensionName": "DockerContainerInsights",
      "extensionSettings": {
        "containerId": "*"
      }
    }
  ],
  "metrics": [
    {
      "name": "dockerContainerStats",
      "extensionName": "DockerContainerInsights",
      "extensionSettings": {
        "containerId": "*"
      }
    }
  ]
}
EOF

# Configure log collection for user data log
log "Configuring log collection for user-data.log..."
cat > /etc/azuremonitoragent/config-cache/configchunks/userdatalogs.json << 'EOF'
{
  "logs": [
    {
      "name": "userDataLog",
      "streams": ["file"],
      "extensionName": "File",
      "extensionSettings": {
        "path": "/var/log/user-data.log"
      }
    },
    {
      "name": "systemLog",
      "streams": ["file"],
      "extensionName": "File",
      "extensionSettings": {
        "path": "/var/log/syslog"
      }
    },
    {
      "name": "dockerLog",
      "streams": ["file"],
      "extensionName": "File",
      "extensionSettings": {
        "path": "/var/log/docker.log"
      }
    }
  ]
}
EOF

# Restart the Azure Monitor agent to apply changes
log "Restarting Azure Monitor agent..."
systemctl restart azuremonitoragent || log "Warning: Couldn't restart azuremonitoragent, may need to be started first"
systemctl enable azuremonitoragent

# Create a service for tailing user-data.log to the dashboard
log "Setting up user-data.log streaming service..."
cat > /etc/systemd/system/log-stream.service << 'EOF'
[Unit]
Description=Stream user-data.log to dashboard
After=docker.service

[Service]
Type=simple
ExecStart=/bin/bash -c "tail -f /var/log/user-data.log | tee -a /opt/iykonect/logs/user-data-stream.log"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create log directory
mkdir -p /opt/iykonect/logs

# Enable and start the service
systemctl daemon-reload
systemctl enable log-stream
systemctl start log-stream || log "Warning: Couldn't start log-stream service"

# Create a shortcut for viewing logs
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

log "Enhanced Azure Monitor setup completed with dashboard for user-data.log visualization."
log "You can use the 'logs-dashboard' command to access log dashboards."