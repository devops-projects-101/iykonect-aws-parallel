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

# Setup status command
cat << EOF > /usr/local/bin/status
#!/bin/bash
clear
echo "╔══════════════════════════════════════════════════╗"
echo "║               SYSTEM STATUS BOARD                ║"
echo "╚══════════════════════════════════════════════════╝"
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
/usr/local/bin/check-container-health
echo
echo "🌐 APPLICATION URLs"
echo "──────────────────"
echo "API URL:           http://${PUBLIC_IP}:8000"
echo "Web URL:           http://${PUBLIC_IP}:5001"
echo "Signable URL:      http://${PUBLIC_IP}:8082"
echo "Email Server URL:  http://${PUBLIC_IP}:8025"
echo "Company House URL: http://${PUBLIC_IP}:8083"
echo "Redis Port:        ${PUBLIC_IP}:6379"
echo "Prometheus URL:    http://${PUBLIC_IP}:9090"
echo "Grafana URL:       http://${PUBLIC_IP}:3100"
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
echo "╔══════════════════════════════════════════════════╗"
echo "║             DETAILED DEPLOYMENT LOGS             ║"
echo "╚══════════════════════════════════════════════════╝"
echo
tail -n 200 /var/log/user-data.log
EOF

chmod +x /usr/local/bin/detailed-logs
echo "alias detailed-logs='/usr/local/bin/detailed-logs'" >> /etc/profile.d/iykonect-welcome.sh

log "Status command setup completed"