#!/bin/bash

# Function for logging
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
}

log "Setting up system status command..."

# Get instance metadata
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Install cowsay if not already installed
log "Installing cowsay for welcome messages..."
apt-get update -qq && apt-get install -y cowsay

# Setup welcome message
cat << 'EOF' > /etc/profile.d/welcome.sh
#!/bin/bash

# Get instance metadata for the welcome message
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# ANSI color codes
BLUE="\033[0;34m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# Use cowsay for welcome message
cowsay -f tux "Welcome to IYKonect AWS Environment"
echo

echo -e "${YELLOW}SYSTEM INFO:${NC}"
uptime
echo

echo -e "${GREEN}AVAILABLE COMMANDS:${NC}"
echo -e "  ${YELLOW}status${NC}        - Show complete system status dashboard"
echo -e "  ${YELLOW}health-check${NC}  - Check container health status"
echo -e "  ${YELLOW}detailed-logs${NC} - View detailed deployment logs (last 200 lines)"
echo -e "  ${YELLOW}redeploy${NC}      - Redeploy all containers with latest images"
echo

echo -e "${GREEN}APPLICATION URLs:${NC}"
echo -e "  API:           http://${PUBLIC_IP}:8000"
echo -e "  Web:           http://${PUBLIC_IP}:3000"
echo -e "  Signable:      http://${PUBLIC_IP}:8082"
echo -e "  Email Server:  http://${PUBLIC_IP}:8025"
echo -e "  Company House: http://${PUBLIC_IP}:8083"
echo -e "  Prometheus:    http://${PUBLIC_IP}:9090"
echo -e "  Grafana:       http://${PUBLIC_IP}:3100"
echo -e "  Nginx Control: http://${PUBLIC_IP}:8008"
echo

echo -e "${YELLOW}Type '${GREEN}status${YELLOW}' to get started with a full system overview.${NC}"
echo -e "$(cowsay  "May the Force be with you!")"
echo
EOF

chmod +x /etc/profile.d/welcome.sh

# Setup status command
cat << EOF > /usr/local/bin/status
#!/bin/bash
clear
cowsay -f elephant "SYSTEM STATUS BOARD"
echo
echo "📊 SYSTEM INFO"
echo "──────────────"
uptime
echo "CPU Usage (top 5 processes):"
ps -eo pcpu,pid,user,args | sort -k 1 -r | head -5
echo "Memory Usage:"
free -h
echo
echo "🐳 DOCKER CONTAINERS"
echo "──────────────"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo
echo "🩺 CONTAINER HEALTH CHECK"
echo "──────────────────"
# Call the separate container health check script
/opt/iykonect-aws-repo/terraform/modules/ec2/scripts/container-health-check.sh
echo
echo "🌐 APPLICATION URLs"
echo "──────────────────"
echo "API URL:           http://${PUBLIC_IP}:8000"
echo "Web URL:           http://${PUBLIC_IP}:3000"
echo "Signable URL:      http://${PUBLIC_IP}:8082"
echo "Email Server URL:  http://${PUBLIC_IP}:8025"
echo "Company House URL: http://${PUBLIC_IP}:8083"
echo "Redis Port:        ${PUBLIC_IP}:6379"
echo "Prometheus URL:    http://${PUBLIC_IP}:9090"
echo "Grafana URL:       http://${PUBLIC_IP}:3100"
echo "Nginx Control URL: http://${PUBLIC_IP}:8008"
echo
echo "👀 MONITORING"
echo "────────────"
echo "CloudWatch Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=IYKonect-Dashboard-${INSTANCE_ID}"
echo
echo "📝 RECENT LOGS"
echo "──────────────"
echo "Last 10 lines of logs (use 'tail -n 200 /var/log/user-data.log' for more):"
tail -n 10 /var/log/user-data.log

# Additional command to show more logs
echo
echo "To view detailed logs (200 lines), type: tail -n 200 /var/log/user-data.log"
EOF

chmod +x /usr/local/bin/status
echo "alias status='/usr/local/bin/status'" >> /etc/profile.d/iykonect-welcome.sh

# Create a shortcut for viewing detailed logs
cat << EOF > /usr/local/bin/detailed-logs
#!/bin/bash
cowsay -f sheep "DETAILED DEPLOYMENT LOGS"
echo
tail -n 200 /var/log/user-data.log
EOF

chmod +x /usr/local/bin/detailed-logs
echo "alias detailed-logs='/usr/local/bin/detailed-logs'" >> /etc/profile.d/iykonect-welcome.sh

# Create a shortcut specifically for container health checks
cat << EOF > /usr/local/bin/health-check
#!/bin/bash
clear
cowsay -f dragon "CONTAINER HEALTH CHECKER"
echo
/opt/iykonect-aws-repo/terraform/modules/ec2/scripts/container-health-check.sh
EOF

chmod +x /usr/local/bin/health-check
echo "alias health-check='/usr/local/bin/health-check'" >> /etc/profile.d/iykonect-welcome.sh

# Create a shortcut for redeploying all containers
cat << EOF > /usr/local/bin/redeploy
#!/bin/bash
clear
cowsay -f vader "CONTAINER REDEPLOYMENT"
echo
echo "⚠️  WARNING: This will stop and replace all running containers!"
echo "Press CTRL+C within 5 seconds to cancel, or wait to continue..."
sleep 5
echo "Starting redeployment process..."
echo

# Execute the redeploy script
/opt/iykonect-aws-repo/terraform/modules/ec2/scripts/redeploy.sh

# Show health check after redeployment
echo
echo "Final health status:"
/opt/iykonect-aws-repo/terraform/modules/ec2/scripts/container-health-check.sh
EOF

chmod +x /usr/local/bin/redeploy
echo "alias redeploy='/usr/local/bin/redeploy'" >> /etc/profile.d/iykonect-welcome.sh

log "Status command and welcome message setup completed"