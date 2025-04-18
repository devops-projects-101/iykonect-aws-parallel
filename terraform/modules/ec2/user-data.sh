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
aws s3 cp s3://iykonect-aws-parallel/credentials.sh /root/credentials.sh
chmod 600 /root/credentials.sh
source /root/credentials.sh
log "Credentials loaded successfully"

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

# Login to ECR using credentials from S3
log "Authenticating with ECR"
if ! aws ecr get-login-password --region ${AWS_REGION} | sudo docker login --username AWS --password-stdin 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com; then
    log "ERROR: Failed to authenticate with ECR"
    exit 1
fi
log "Successfully authenticated with ECR"

# Pull and run containers
log "Starting to pull and run containers"
for service in redis prometheus grafana api react-app; do
    log "Deploying $service"
    if ! sudo docker pull 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:$service; then
        log "ERROR: Failed to pull $service"
        exit 1
    fi

    case $service in
        "redis")
            cmd="sudo docker run -d --network app-network --restart always --name redis_service -p 6379:6379 -e REDIS_PASSWORD=IYKONECTpassword 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:redis redis-server --requirepass IYKONECTpassword --bind 0.0.0.0"
            ;;
        "api")
            cmd="sudo docker run -d --network app-network --restart always --name api -p 8000:80 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:api"
            ;;
        "prometheus")
            cmd="sudo docker run -d --network app-network --restart always --name prometheus -p 9090:9090 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:prometheus"
            ;;
        "grafana")
            cmd="sudo docker run -d --network app-network --restart always --name iykon-graphana-app -p 3100:3000 --user root 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:grafana"
            ;;
    esac

    if [ ! -z "$cmd" ] && ! eval "$cmd"; then
        log "ERROR: Failed to start $service"
        exit 1
    fi
    log "$service deployed successfully"
done

# Deploy Grafana Renderer
log "Deploying Grafana Renderer"
if ! sudo docker run -d --name renderer --network app-network -p 8081:8081 --restart always grafana/grafana-image-renderer:latest; then
    log "ERROR: Failed to start Grafana Renderer"
    exit 1
fi

log "END - user data execution"