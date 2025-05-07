#!/bin/bash

# Azure-specific status command setup script

# Function for logging
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
}

log "Starting from status setup"
log "Setting up system status command for Azure VM..."

# Source VM metadata from the permanent manifest file
METADATA_FILE="/opt/iykonect/metadata/vm_metadata.sh"

log "Loading VM metadata from $METADATA_FILE"
source "$METADATA_FILE"

# Setup welcome message for Azure - update to use metadata file
cat << 'EOF' > /etc/profile.d/azure-welcome.sh
#!/bin/bash

# Source VM metadata from the permanent manifest file
METADATA_FILE="/opt/iykonect/metadata/vm_metadata.sh"

if [ -f "$METADATA_FILE" ]; then
    source "$METADATA_FILE"
else
    # Fallback to Azure Instance Metadata Service
    VM_NAME=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text")
    PUBLIC_IP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text")
    LOCATION=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")
fi

# ANSI color codes
BLUE="\033[0;34m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

# Display welcome message
echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}     Welcome to IYKonect Azure Environment     ${NC}"
echo -e "${BLUE}===============================================${NC}"
echo

echo -e "${YELLOW}AZURE VM INFO:${NC}"
echo -e "  VM Name:      ${GREEN}$VM_NAME${NC}"
echo -e "  Location:     ${GREEN}$LOCATION${NC}"
echo -e "  Public IP:    ${GREEN}$PUBLIC_IP${NC}"
echo -e "  System Load:  ${GREEN}$(uptime | awk -F'[a-z]:' '{ print $2}')${NC}"
echo

echo -e "${CYAN}AVAILABLE COMMANDS:${NC}"
echo -e "  ${YELLOW}az-status${NC}      - Show complete Azure system status dashboard"
echo -e "  ${YELLOW}az-health${NC}      - Check Azure VM container health status"
echo -e "  ${YELLOW}az-logs${NC}        - View detailed Azure deployment logs"
echo -e "  ${YELLOW}az-redeploy${NC}    - Redeploy all containers with latest images"
echo

echo -e "${CYAN}APPLICATION URLs:${NC}"
echo -e "  API:           ${GREEN}http://${PUBLIC_IP}:8000${NC}"
echo -e "  Web:           ${GREEN}http://${PUBLIC_IP}:3000${NC}"
echo -e "  Signable:      ${GREEN}http://${PUBLIC_IP}:8082${NC}"
echo -e "  Email Server:  ${GREEN}http://${PUBLIC_IP}:8025${NC}"
echo -e "  Company House: ${GREEN}http://${PUBLIC_IP}:8083${NC}"
echo -e "  Prometheus:    ${GREEN}http://${PUBLIC_IP}:9090${NC}"
echo -e "  Grafana:       ${GREEN}http://${PUBLIC_IP}:3100${NC}"
echo -e "  Nginx Control: ${GREEN}http://${PUBLIC_IP}:8008${NC}"
echo

echo -e "${YELLOW}Type '${GREEN}az-status${YELLOW}' to get started with a full system overview.${NC}"
echo -e "${BLUE}===============================================${NC}"
echo
EOF

chmod +x /etc/profile.d/azure-welcome.sh

# Setup Azure status command
cat << 'EOF' > /usr/local/bin/az-status
#!/bin/bash
clear

# Get Azure instance metadata for status command
METADATA_FILE="/opt/iykonect/metadata/vm_metadata.sh"

if [ -f "$METADATA_FILE" ]; then
    source "$METADATA_FILE"
else
    # Fallback to Azure Instance Metadata Service
    VM_NAME=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text")
    RESOURCE_GROUP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text")
    LOCATION=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")
    SUBSCRIPTION_ID=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/subscriptionId?api-version=2021-02-01&format=text")
    PUBLIC_IP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text")
    PRIVATE_IP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2021-02-01&format=text")
fi

# ANSI color codes
BLUE="\033[0;34m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}          AZURE VM STATUS DASHBOARD            ${NC}"
echo -e "${BLUE}===============================================${NC}"
echo

echo -e "${CYAN}📊 AZURE VM INFO${NC}"
echo -e "──────────────────────────────────"
echo -e "VM Name:         ${GREEN}$VM_NAME${NC}"
echo -e "Resource Group:  ${GREEN}$RESOURCE_GROUP${NC}"
echo -e "Location:        ${GREEN}$LOCATION${NC}"
echo -e "Public IP:       ${GREEN}$PUBLIC_IP${NC}"
echo -e "Private IP:      ${GREEN}$PRIVATE_IP${NC}"
echo

echo -e "${CYAN}🖥️  SYSTEM RESOURCES${NC}"
echo -e "──────────────────────────────────"
echo -e "Uptime & Load: $(uptime)"
echo
echo -e "CPU Usage (top 5 processes):"
ps -eo pcpu,pid,user,args | sort -k 1 -r | head -5
echo
echo -e "Memory Usage:"
free -h
echo
echo -e "Disk Usage:"
df -h / | tail -n 1 | awk '{print $5 " used (" $3 " of " $2 ")"}'
echo

echo -e "${CYAN}🐳 DOCKER CONTAINERS${NC}"
echo -e "──────────────────────────────────"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo

echo -e "${CYAN}🩺 CONTAINER HEALTH CHECK${NC}"
echo -e "──────────────────────────────────"
# Call the container health check script but suppress the header to avoid duplication
/opt/iykonect-repo/terraform-azure/modules/vm/scripts/container-health-check.sh | grep -v "====" | grep -v "AZURE VM CONTAINER HEALTH CHECK" | grep -v "VM:" | grep -v "Location:" | grep -v "Private IP:" | grep -v "-----" | grep -v "APPLICATION ACCESS URLS"
echo

echo -e "${CYAN}🔄 AZURE CONNECTIVITY STATUS${NC}"
echo -e "──────────────────────────────────"
# Test connectivity to Azure resources
if curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" >/dev/null 2>&1; then
    echo -e "Azure IMDS:      ${GREEN}CONNECTED${NC}"
else
    echo -e "Azure IMDS:      ${RED}DISCONNECTED${NC}"
fi

# Check if Azure CLI is installed and authenticated
if command -v az >/dev/null 2>&1; then
    echo -e "Azure CLI:       ${GREEN}INSTALLED${NC}"
    if az account show >/dev/null 2>&1; then
        echo -e "Azure Auth:      ${GREEN}AUTHENTICATED${NC}"
        CURRENT_ACCOUNT=$(az account show --query name -o tsv 2>/dev/null)
        echo -e "Current Account: ${GREEN}${CURRENT_ACCOUNT}${NC}"
    else
        echo -e "Azure Auth:      ${RED}NOT AUTHENTICATED${NC}"
    fi
else
    echo -e "Azure CLI:       ${RED}NOT INSTALLED${NC}"
fi
echo

echo -e "${CYAN}🌐 APPLICATION URLS${NC}"
echo -e "──────────────────────────────────"
echo -e "Web Application: ${GREEN}http://$PUBLIC_IP:3000${NC}"
echo -e "API:            ${GREEN}http://$PUBLIC_IP:8000${NC}"
echo -e "Signable API:   ${GREEN}http://$PUBLIC_IP:8082${NC}"
echo -e "Company House:  ${GREEN}http://$PUBLIC_IP:8083${NC}"
echo -e "Email Server:   ${GREEN}http://$PUBLIC_IP:8025${NC}"
echo -e "Prometheus:     ${GREEN}http://$PUBLIC_IP:9090${NC}"
echo -e "Grafana:        ${GREEN}http://$PUBLIC_IP:3100${NC}"
echo -e "Nginx Control:  ${GREEN}http://$PUBLIC_IP:8008${NC}"
echo

echo -e "${CYAN}📝 RECENT LOGS${NC}"
echo -e "──────────────────────────────────"
echo -e "Last 10 lines of user-data.log:"
tail -n 10 /var/log/user-data.log
echo
echo -e "${YELLOW}For more logs, run: ${GREEN}az-logs${NC}"
echo -e "${BLUE}===============================================${NC}"
EOF

chmod +x /usr/local/bin/az-status
echo "alias az-status='/usr/local/bin/az-status'" >> /etc/profile.d/iykonect-welcome.sh

# Create the Azure logs viewer command
cat << 'EOF' > /usr/local/bin/az-logs
#!/bin/bash
clear
echo "===================================================="
echo "         AZURE VM DETAILED DEPLOYMENT LOGS          "
echo "===================================================="
echo
echo "Displaying last 200 lines of deployment logs..."
echo "Press CTRL+C to exit."
echo
tail -n 200 /var/log/user-data.log
EOF

chmod +x /usr/local/bin/az-logs
echo "alias az-logs='/usr/local/bin/az-logs'" >> /etc/profile.d/iykonect-welcome.sh

# Create the Azure container health check command
cat << 'EOF' > /usr/local/bin/az-health
#!/bin/bash
clear
echo "===================================================="
echo "         AZURE VM CONTAINER HEALTH CHECKER          "
echo "===================================================="
/opt/iykonect-repo/terraform-azure/modules/vm/scripts/container-health-check.sh
EOF

chmod +x /usr/local/bin/az-health
echo "alias az-health='/usr/local/bin/az-health'" >> /etc/profile.d/iykonect-welcome.sh

# Create the Azure redeploy command
cat << 'EOF' > /usr/local/bin/az-redeploy
#!/bin/bash
clear
echo "===================================================="
echo "         AZURE VM CONTAINER REDEPLOYMENT            "
echo "===================================================="
echo
echo "⚠️  WARNING: This will stop and replace all running containers!"
echo "Press CTRL+C within 5 seconds to cancel, or wait to continue..."
sleep 5
echo "Starting redeployment process on Azure VM..."
echo

# Execute the Azure redeploy script
/opt/iykonect-repo/terraform-azure/modules/vm/scripts/redeploy.sh

# Show health check after redeployment
echo
echo "Final health status:"
/opt/iykonect-repo/terraform-azure/modules/vm/scripts/container-health-check.sh
EOF

chmod +x /usr/local/bin/az-redeploy
echo "alias az-redeploy='/usr/local/bin/az-redeploy'" >> /etc/profile.d/iykonect-welcome.sh

log "Azure VM status commands and welcome message setup completed"