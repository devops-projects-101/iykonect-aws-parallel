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

# Install Log Analytics agent (OMS Agent) instead of Azure Monitor agent
# The Azure Monitor agent is not available for Ubuntu 20.04 in the standard repositories
log "Installing Log Analytics agent (OMS Agent) for Ubuntu 20.04..."

# Add Microsoft signing key and repo
wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

# Update package lists and install Log Analytics agent
apt-get update
apt-get install -y microsoft-monitoring-agent

# Install the dependency agent for enhanced monitoring capabilities
log "Installing Azure Dependency agent..."
curl -sSO https://aka.ms/dependencyagentlinux
sh ./dependencyagentlinux
rm ./dependencyagentlinux

log "Azure monitoring agents installed successfully"

# Configure monitoring for Docker
log "Configuring monitoring for Docker containers..."

# Create directories for logs
mkdir -p /opt/iykonect/logs
mkdir -p /opt/iykonect/monitor

# Create a Docker stats collection script
cat > /opt/iykonect/monitor/docker-stats.sh << 'EOF'
#!/bin/bash
STATS_FILE="/opt/iykonect/logs/docker-stats.log"
echo "Timestamp: $(date)" > $STATS_FILE
echo "Docker Containers:" >> $STATS_FILE
docker ps --format "{{.Names}}" | while read container; do
  echo "Container: $container" >> $STATS_FILE
  docker stats --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" $container >> $STATS_FILE
  echo "" >> $STATS_FILE
done
EOF

chmod +x /opt/iykonect/monitor/docker-stats.sh

# Create a cron job to collect Docker stats every minute
cat > /etc/cron.d/docker-stats << 'EOF'
* * * * * root /opt/iykonect/monitor/docker-stats.sh > /dev/null 2>&1
EOF

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
echo "Docker Stats Summary:"
echo "--------------------------------------------"
tail -n 10 /opt/iykonect/logs/docker-stats.log
echo ""
echo "For more logs, use: tail -n 100 /var/log/user-data.log"
echo "=============================================="
EOF

chmod +x /usr/local/bin/logs-dashboard

# Add an enhanced monitoring dashboard script
cat > /usr/local/bin/az-monitor << 'EOF'
#!/bin/bash
clear
echo "=============================================="
echo "    IYKonect Azure Monitoring Dashboard      "
echo "=============================================="
echo ""
echo "SYSTEM RESOURCES:"
echo "--------------------------------------------"
echo "CPU Usage:"
top -bn1 | head -n 5
echo ""
echo "Memory Usage:"
free -h
echo ""
echo "Disk Usage:"
df -h /
echo ""
echo "DOCKER CONTAINERS:"
echo "--------------------------------------------"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "RECENT LOGS:"
echo "--------------------------------------------"
echo "Last 10 lines of user-data.log:"
tail -n 10 /var/log/user-data.log
echo ""
echo "=============================================="
EOF

chmod +x /usr/local/bin/az-monitor

# Add logs-dashboard and az-monitor to aliases
mkdir -p /etc/profile.d
echo "alias logs-dashboard='/usr/local/bin/logs-dashboard'" >> /etc/profile.d/iykonect-welcome.sh
echo "alias az-monitor='/usr/local/bin/az-monitor'" >> /etc/profile.d/iykonect-welcome.sh

log "Enhanced Azure Monitor setup completed with dashboard for system monitoring."
log "You can use the 'logs-dashboard' command to access log dashboards."
log "You can use the 'az-monitor' command to access the system monitoring dashboard."