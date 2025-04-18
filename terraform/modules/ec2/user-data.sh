#!/bin/bash

# Ensure script runs as root
if [ "$(id -u)" != "0" ]; then
   exec sudo "$0" "$@"
fi

set -x
set -e

# Logging function with proper permissions
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
}

# Initial setup
apt-get update
apt-get install -y awscli jq
log "Installed basic packages"

# Get and load credentials with proper permissions
log "Reading credentials from S3"
mkdir -p /root/.aws

# Add retry mechanism for S3 download
max_attempts=5
attempt=1
while [ $attempt -le $max_attempts ]; do
    log "Attempt $attempt to download credentials file..."
    
    # Verify S3 bucket exists
    if ! aws s3 ls s3://iykonect-aws-parallel/; then
        log "ERROR: Cannot access S3 bucket, attempt $attempt"
        sleep 10
        attempt=$((attempt + 1))
        continue
    fi
    
    # Try to download file
    if aws s3 cp s3://iykonect-aws-parallel/credentials.sh /root/credentials.sh; then
        log "Successfully downloaded credentials file"
        break
    fi
    
    log "Failed to download credentials file, attempt $attempt"
    [ $attempt -lt $max_attempts ] && sleep 10
    attempt=$((attempt + 1))
done

if [ $attempt -gt $max_attempts ]; then
    log "ERROR: Failed to download credentials after $max_attempts attempts"
    exit 1
fi

chmod 600 /root/credentials.sh
cat /root/credentials.sh >> /var/log/user-data.log
. /root/credentials.sh

# Verify credentials loaded
if [ -z "$AWS_REGION" ]; then
    log "ERROR: AWS_REGION not set, credentials may not have loaded properly"
    exit 1
fi
log "Using AWS region: ${AWS_REGION}"

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