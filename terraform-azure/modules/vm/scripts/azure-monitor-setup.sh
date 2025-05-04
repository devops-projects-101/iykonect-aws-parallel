#!/bin/bash

# This is a wrapper script for Azure Monitor setup

set -e

# Logging function
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/azure-monitor-setup.log
}

log "Starting Azure Monitor setup..."

# Install Azure Monitor agent
log "Installing Azure Monitor agent..."
curl -sL https://aka.ms/InstallAzureMonitorLinuxAgent | sudo bash

# Configure Azure Monitor to collect Docker metrics
log "Configuring Azure Monitor to collect Docker metrics..."
cat > /etc/azuremonitoragent/config.d/docker.toml << 'EOF'
# Azure Monitor agent configuration for Docker

[inputs.docker]
  endpoint = "unix:///var/run/docker.sock"
  gather_services = false
  container_names = []
  container_name_include = []
  container_name_exclude = []
  timeout = "5s"
  perdevice = true
  total = false
EOF

# Restart the agent to apply changes
systemctl restart azuremonitoragent

log "Azure Monitor setup completed."