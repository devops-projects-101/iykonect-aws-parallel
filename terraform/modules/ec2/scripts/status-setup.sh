#!/bin/bash

# Function for logging
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
}

log "Setting up system status command..."

# Setup status command
cat << 'EOF' > /usr/local/bin/status
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
echo "📝 RECENT LOGS"
echo "──────────────"
tail -n 10 /var/log/user-data.log
EOF

chmod +x /usr/local/bin/status
echo "alias status='/usr/local/bin/status'" >> /etc/profile.d/iykonect-welcome.sh

log "Status command setup completed"