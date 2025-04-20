#!/bin/bash

# Ensure script runs as root
if [ "$(id -u)" != "0" ]; then
   exec sudo "$0" "$@"
fi

set -x
set -e

# Logging functions with proper permissions
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
}

ssm_log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/ssm.log
}

# Create SSM log file with proper permissions
touch /var/log/ssm.log
chmod 644 /var/log/ssm.log
ssm_log "SSM log file initialized"

#region Variables
AWS_REGION=eu-west-1

# Verify port is available
check_port() {
    local port=$1
    if lsof -i:"$port" >/dev/null 2>&1; then
        log "ERROR: Port $port is already in use"
        return 1
    fi
    return 0
}

# Wait for container to be healthy
wait_for_container() {
    local container=$1
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if [ "$(docker inspect -f '{{.State.Status}}' $container 2>/dev/null)" = "running" ]; then
            log "Container $container is running"
            return 0
        fi
        log "Waiting for container $container to be ready (attempt $attempt/$max_attempts)"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log "ERROR: Container $container failed to start properly"
    docker logs $container
    return 1
}

# Initial setup and packages
log "Starting initial setup..."
apt-get update
apt-get install -y awscli jq apt-transport-https ca-certificates curl gnupg lsb-release htop

# Install SSM Agent
log "Installing SSM Agent..."
mkdir -p /tmp/ssm
cd /tmp/ssm
wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
dpkg -i amazon-ssm-agent.deb
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
log "SSM Agent installed and started"

# Setup status command
cat << 'EOF' > /usr/local/bin/status
#!/bin/bash
clear
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                     SYSTEM STATUS BOARD                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"

# System Info
echo
echo "📊 SYSTEM INFO"
echo "──────────────"
uptime
echo
echo "CPU Usage (top 5 processes):"
ps -eo pcpu,pid,user,args | sort -k 1 -r | head -5
echo
echo "Memory Usage:"
free -h
echo

# Container Status
echo "🐳 DOCKER CONTAINERS"
echo "──────────────────"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo

# Recent Logs
echo "📝 RECENT SYSTEM LOGS"
echo "──────────────────"
tail -n 10 /var/log/user-data.log
echo

# SSM Operation Logs
echo "🔄 RECENT SSM OPERATION LOGS"
echo "──────────────────"
tail -n 10 /var/log/ssm.log
echo

# Container Logs
echo "📋 RECENT CONTAINER LOGS"
echo "──────────────────"
for container in redis_service api prometheus grafana-app react-app renderer; do
    if docker ps -q -f name=$container >/dev/null 2>&1; then
        echo "[$container]"
        docker logs --tail 5 $container 2>&1
        echo
    fi
done

# Help Section
echo "ℹ️  AVAILABLE COMMANDS"
echo "──────────────────"
echo "status                    - Show this dashboard"
echo "docker ps                 - List running containers"
echo "docker logs CONTAINER     - View container logs"
echo "tail -f /var/log/user-data.log   - Follow system logs"
echo "tail -f /var/log/ssm.log - Follow SSM operation logs"
echo
EOF

chmod +x /usr/local/bin/status

# Add status command to profile
echo "alias status='/usr/local/bin/status'" >> /etc/profile.d/iykonect-welcome.sh

# Verify AWS Configuration first
log "Verifying AWS configuration..."
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log "ERROR: AWS credentials validation failed"
    exit 1
fi
log "AWS credentials verified successfully"

# Verify S3 access
log "Verifying S3 bucket access..."
if ! aws s3 ls s3://iykonect-aws-parallel/ > /dev/null 2>&1; then
    log "ERROR: S3 bucket access verification failed"
    exit 1
fi
log "S3 bucket access verified successfully"

# Verify ECR access
log "Verifying ECR permissions..."
if ! aws ecr list-images --repository-name iykonect-images --region ${AWS_REGION} --output table > /dev/null 2>&1; then
    log "ERROR: ECR access verification failed"
    exit 1
fi
log "ECR permissions verified successfully"

# Install Docker
log "Installing Docker..."
apt-get remove docker docker-engine docker.io containerd runc || true
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Configure system settings
cat << EOF | tee -a /etc/sysctl.conf
fs.inotify.max_user_watches = 524288
EOF
sysctl -p

# Install Docker packages
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io
systemctl enable docker
systemctl start docker

# Docker setup
log "Setting up Docker environment..."
docker system prune -af
docker network create app-network || true
log "Docker environment ready"

# Login to ECR
log "Logging into ECR..."
LOGIN_OUTPUT=$(aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com 2>&1)
log "ECR login output: ${LOGIN_OUTPUT}"

# Install system utilities for monitoring
log "Installing system utilities..."
apt-get install -y lsof net-tools
log "System utilities installed"

# Create Docker configuration file
cat << 'EOF' > /etc/docker-config.env
# Generated from terraform docker-config.tf
DOCKER_REGISTRY=${docker_registry}

# Redis
REDIS_IMAGE=${redis_image}
REDIS_PORT=${redis_port}
REDIS_PASSWORD=IYKONECTpassword

# API
API_IMAGE=${api_image}
API_PORT=${api_port}

# Prometheus
PROMETHEUS_IMAGE=${prometheus_image}
PROMETHEUS_PORT=${prometheus_port}

# Grafana
GRAFANA_IMAGE=${grafana_image}
GRAFANA_PORT=${grafana_port}

# React
REACT_IMAGE=${react_image}
REACT_PORT=${react_port}

# Renderer
RENDERER_IMAGE=${renderer_image}
RENDERER_PORT=${renderer_port}
EOF

# Source the config
source /etc/docker-config.env

# Deploy containers in order of dependencies
log "Starting container deployments"

# 1. Redis (base service)
if ! check_port $${REDIS_PORT%:*}; then
    log "ERROR: Port $${REDIS_PORT%:*} is not available for Redis"
    exit 1
fi
log "Deploying Redis..."
docker run -d --network app-network --restart always --name redis_service -p $REDIS_PORT \
    -e REDIS_PASSWORD=$REDIS_PASSWORD \
    $REDIS_IMAGE \
    redis-server --requirepass $REDIS_PASSWORD --bind 0.0.0.0
wait_for_container redis_service || exit 1
log "Redis container status: $(docker inspect -f '{{.State.Status}}' redis_service)"

# 2. API (depends on Redis)
if ! check_port $${API_PORT%:*}; then
    log "ERROR: Port $${API_PORT%:*} is not available for API"
    exit 1
fi
log "Deploying API..."
docker run -d --network app-network --restart always --name api -p $API_PORT \
    $API_IMAGE
wait_for_container api || exit 1
log "API container status: $(docker inspect -f '{{.State.Status}}' api)"

# 3. Prometheus (monitoring base)
if ! check_port $${PROMETHEUS_PORT%:*}; then
    log "ERROR: Port $${PROMETHEUS_PORT%:*} is not available for Prometheus"
    exit 1
fi
log "Deploying Prometheus..."
docker run -d --network app-network --restart always --name prometheus -p $PROMETHEUS_PORT \
    $PROMETHEUS_IMAGE
wait_for_container prometheus || exit 1
log "Prometheus container status: $(docker inspect -f '{{.State.Status}}' prometheus)"

# 4. Grafana (depends on Prometheus)
if ! check_port $${GRAFANA_PORT%:*}; then
    log "ERROR: Port $${GRAFANA_PORT%:*} is not available for Grafana"
    exit 1
fi
log "Deploying Grafana..."
docker run -d --network app-network --restart always --name grafana-app -p $GRAFANA_PORT \
    --user root \
    $GRAFANA_IMAGE
wait_for_container grafana-app || exit 1
log "Grafana container status: $(docker inspect -f '{{.State.Status}}' grafana-app)"

# 5. React App (frontend)
if ! check_port $${REACT_PORT%:*}; then
    log "ERROR: Port $${REACT_PORT%:*} is not available for React App"
    exit 1
fi
log "Deploying React App..."
docker run -d --network app-network --restart always --name react-app -p $REACT_PORT \
    $REACT_IMAGE
wait_for_container react-app || exit 1
log "React App container status: $(docker inspect -f '{{.State.Status}}' react-app)"

# 6. Grafana Renderer (depends on Grafana)
if ! check_port $${RENDERER_PORT%:*}; then
    log "ERROR: Port $${RENDERER_PORT%:*} is not available for Renderer"
    exit 1
fi
log "Deploying Grafana Renderer..."
docker run -d --network app-network --restart always --name renderer -p $RENDERER_PORT \
    $RENDERER_IMAGE
wait_for_container renderer || exit 1
log "Renderer container status: $(docker inspect -f '{{.State.Status}}' renderer)"

# Verify all containers are running
log "=== Final Deployment Status ==="
log "Network Status: $(docker network inspect app-network -f '{{.Name}} is {{.Driver}}')"

# Log open ports first
log "Open Ports Summary:"
netstat -tulpn | grep LISTEN | while read line; do
    log "$line"
done

# Log container status after ports
log "Container Status Summary:"
log "$(docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}')"
docker ps --format "{{.Names}}: {{.Status}}" | while read line; do 
    log "$line"
done

# Log resource usage
log "Resource Usage Summary:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | while read line; do
    log "$line"
done

log "=== END Final Status ==="
log "END - user data execution"