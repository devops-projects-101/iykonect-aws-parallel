#!/bin/bash

set -x
set -e

# Logging function
log() {
    echo "[$(date)] $1" >> /var/log/user-data.log
}

# Initial setup
sudo apt-get update
sudo apt-get install -y awscli jq
log "Installed basic packages"

# Fetch and load credentials from S3
log "Fetching credentials from S3"
aws s3 cp s3://iykonect-aws-parallel/credentials.sh /root/credentials.sh || {
    log "ERROR: Failed to fetch credentials.sh from S3"
    exit 1
}
chmod 600 /root/credentials.sh

# Display file content for debugging (hide sensitive info)
log "Credentials file content (partial):"
grep "AWS_REGION" /root/credentials.sh | sed 's/=.*/=***/'

# Source the credentials
source /root/credentials.sh

# Verify AWS configuration
if [ -z "$AWS_REGION" ]; then
    log "ERROR: AWS_REGION not set after sourcing credentials"
    exit 1
fi
log "Using AWS region: ${AWS_REGION}"

# Install Docker
sudo apt-get remove docker docker-engine docker.io containerd runc || true
sudo apt-get update
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Configure system settings
cat << EOF | sudo tee -a /etc/sysctl.conf
fs.inotify.max_user_watches = 524288
EOF
sudo sysctl -p

# Install Docker packages
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable docker
sudo systemctl start docker

# Clean Docker system
log "Cleaning up Docker system"
sudo docker system prune -af
log "Docker system cleaned"

# Create docker network
sudo docker network create app-network
log "Docker network created"

# Deploy all containers
log "Starting container deployments"

# Redis
log "Deploying Redis..."
sudo docker run -d --network app-network --restart always --name redis_service -p 6379:6379 \
    -e REDIS_PASSWORD=IYKONECTpassword \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:redis \
    redis-server --requirepass IYKONECTpassword --bind 0.0.0.0
log "Redis container status: $(sudo docker inspect -f '{{.State.Status}}' redis_service)"

# API
log "Deploying API..."
sudo docker run -d --network app-network --restart always --name api -p 8000:80 \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:api
log "API container status: $(sudo docker inspect -f '{{.State.Status}}' api)"

# Prometheus
log "Deploying Prometheus..."
sudo docker run -d --network app-network --restart always --name prometheus -p 9090:9090 \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:prometheus
log "Prometheus container status: $(sudo docker inspect -f '{{.State.Status}}' prometheus)"

# Grafana
log "Deploying Grafana..."
sudo docker run -d --network app-network --restart always --name iykon-graphana-app -p 3100:3000 \
    --user root \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:grafana
log "Grafana container status: $(sudo docker inspect -f '{{.State.Status}}' iykon-graphana-app)"

# React App
log "Deploying React App..."
sudo docker run -d --network app-network --restart always --name react-app -p 3000:3000 \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:react-app
log "React App container status: $(sudo docker inspect -f '{{.State.Status}}' react-app)"

# Grafana Renderer
log "Deploying Grafana Renderer..."
sudo docker run -d --network app-network --restart always --name renderer -p 8081:8081 \
    grafana/grafana-image-renderer:latest
log "Renderer container status: $(sudo docker inspect -f '{{.State.Status}}' renderer)"

log "All containers deployed. Final status:"
sudo docker ps --format "{{.Names}}: {{.Status}}"
log "END - user data execution"