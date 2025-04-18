#!/bin/bash

# Ensure script runs as root
if [ "$(id -u)" != "0" ]; then
   exec sudo "$0" "$@"
fi

set -x
set -e

# Configure AWS credentials directly
export AWS_ACCESS_KEY_ID='${AWS_ACCESS_KEY_ID}'
export AWS_SECRET_ACCESS_KEY='${AWS_SECRET_ACCESS_KEY}'
export AWS_REGION='${AWS_REGION}'
export AWS_DEFAULT_REGION='${AWS_REGION}'

# Configure AWS CLI
mkdir -p ~/.aws
cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
EOF

cat > ~/.aws/config << EOF
[default]
region = ${AWS_REGION}
output = json
EOF

# Logging function with proper permissions
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
}

log "AWS credentials configured with region: ${AWS_REGION}"

# Verify AWS Configuration
log "Verifying AWS configuration..."
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log "ERROR: AWS credentials validation failed"
    exit 1
fi
log "AWS credentials verified successfully"

# Initial setup
apt-get update
apt-get install -y awscli jq
log "Installed basic packages"

# Install Docker
apt-get remove docker docker-engine docker.io containerd runc || true
apt-get update
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

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

# Clean Docker system
log "Cleaning up Docker system"
docker system prune -af
log "Docker system cleaned"

# Create docker network
docker network create app-network
log "Docker network created"

# Login to ECR
log "Logging into ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com
log "ECR login successful"

# Deploy all containers
log "Starting container deployments"

# Redis
log "Deploying Redis..."
docker run -d --network app-network --restart always --name redis_service -p 6379:6379 \
    -e REDIS_PASSWORD=IYKONECTpassword \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:redis \
    redis-server --requirepass IYKONECTpassword --bind 0.0.0.0
log "Redis container status: $(docker inspect -f '{{.State.Status}}' redis_service)"

# API
log "Deploying API..."
docker run -d --network app-network --restart always --name api -p 8000:80 \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:api
log "API container status: $(docker inspect -f '{{.State.Status}}' api)"

# Prometheus
log "Deploying Prometheus..."
docker run -d --network app-network --restart always --name prometheus -p 9090:9090 \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:prometheus
log "Prometheus container status: $(docker inspect -f '{{.State.Status}}' prometheus)"

# Grafana
log "Deploying Grafana..."
docker run -d --network app-network --restart always --name iykon-graphana-app -p 3100:3000 \
    --user root \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:grafana
log "Grafana container status: $(docker inspect -f '{{.State.Status}}' iykon-graphana-app)"

# React App
log "Deploying React App..."
docker run -d --network app-network --restart always --name react-app -p 3000:3000 \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:react-app
log "React App container status: $(docker inspect -f '{{.State.Status}}' react-app)"

# Grafana Renderer
log "Deploying Grafana Renderer..."
docker run -d --network app-network --restart always --name renderer -p 8081:8081 \
    grafana/grafana-image-renderer:latest
log "Renderer container status: $(docker inspect -f '{{.State.Status}}' renderer)"

log "All containers deployed. Final status:"
docker ps --format "{{.Names}}: {{.Status}}"
log "END - user data execution"