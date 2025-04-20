#!/bin/bash

# Ensure script runs as root
if [ "$(id -u)" != "0" ]; then
   exec sudo "$0" "$@"
fi

set -x
set -e

#region Variables
AWS_REGION=eu-west-1


# Initial setup
apt-get update
apt-get install -y awscli jq
log "Installed basic packages"



# Logging function with proper permissions
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
}



# Setup user environment
cat << 'EOF' >> /etc/profile.d/iykonect-welcome.sh
# Auto switch to root
if [ "$(id -u)" != "0" ]; then
    sudo su -
fi

# Show system status on login
alias status='
clear
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                     SYSTEM STATUS BOARD                        ║"
echo "╠════════════════════════════════════════════════════════════════╣"

# Terraform Outputs
echo "║ Terraform Status:                                              ║"
if aws s3 cp s3://iykonect-aws-parallel/terraform.tfstate /tmp/terraform.tfstate > /dev/null 2>&1; then
    echo "║ Infrastructure Endpoints:                                      ║"
    INSTANCE_IP=$(cat /tmp/terraform.tfstate | jq -r ".outputs.instance_public_ip.value")
    API_ENDPOINT=$(cat /tmp/terraform.tfstate | jq -r ".outputs.api_endpoint.value")
    PROMETHEUS_ENDPOINT=$(cat /tmp/terraform.tfstate | jq -r ".outputs.prometheus_endpoint.value")
    GRAFANA_ENDPOINT=$(cat /tmp/terraform.tfstate | jq -r ".outputs.grafana_endpoint.value")
    SONARQUBE_ENDPOINT=$(cat /tmp/terraform.tfstate | jq -r ".outputs.sonarqube_endpoint.value")
    RENDERER_ENDPOINT=$(cat /tmp/terraform.tfstate | jq -r ".outputs.renderer_endpoint.value")
    
    echo "║ Instance IP:        $INSTANCE_IP"
    echo "║ API:               $API_ENDPOINT"
    echo "║ Prometheus:        $PROMETHEUS_ENDPOINT"
    echo "║ Grafana:           $GRAFANA_ENDPOINT"
    echo "║ SonarQube:         $SONARQUBE_ENDPOINT"
    echo "║ Renderer:          $RENDERER_ENDPOINT"
else
    echo -e "\e[91m║ ERROR: Could not fetch Terraform state!\e[0m                       ║"
fi
echo "╟────────────────────────────────────────────────────────────────╢"

# ECR Images Check
echo "║ ECR Images:                                                    ║"
if aws ecr list-images --repository-name iykonect-images --region eu-west-1 --filter tagStatus=TAGGED --output table > /tmp/ecr_output 2>&1; then
    cat /tmp/ecr_output
else
    echo -e "\e[91m║ ERROR: Failed to fetch ECR images!\e[0m                            ║"
fi
echo "╟────────────────────────────────────────────────────────────────╢"

# S3 Bucket Check
echo "║ S3 Contents:                                                   ║"
if (aws s3 ls s3://iykonect-aws-parallel/ && aws s3 ls s3://iykons-s3-storage/) > /tmp/s3_output 2>&1; then
    cat /tmp/s3_output
else
    echo -e "\e[91m║ ERROR: Failed to list S3 bucket contents!\e[0m                     ║"
fi
echo "╟────────────────────────────────────────────────────────────────╢"

# Container Status with Details
echo "║ Docker Container Status:                                       ║"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo "╟────────────────────────────────────────────────────────────────╢"

# Recent Logs with Container Status
echo "║ Recent System and Container Status Logs:                       ║"
echo "║ System Logs:                                                   ║"
tail -n 5 /var/log/user-data.log
echo "║ Container Status:                                              ║"
docker ps --format "{{.Names}}: {{.Status}}" > /tmp/container_status
cat /tmp/container_status | while read line; do echo "║ $line"; done
echo "╟────────────────────────────────────────────────────────────────╢"

# Help Commands
echo "║ Useful Commands:                                               ║"
echo "║ - Use <status> to refresh this status board                    ║"
echo "║ - tail -f /var/log/user-data.log to follow logs                ║"
echo "║ - docker logs <container_name> -n 100 for container logs       ║"
echo "╚════════════════════════════════════════════════════════════════╝"'

# Execute status check on login
status
EOF

chmod +x /etc/profile.d/iykonect-welcome.sh
log "User environment configured"




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


# Verify AWS Configuration
log "Verifying AWS configuration..."
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log "ERROR: AWS credentials validation failed"
    exit 1
fi
log "AWS credentials verified successfully"

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

LOGIN_OUTPUT=$(aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com 2>&1)
log "ECR login output: ${LOGIN_OUTPUT}"
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
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:react-standalone
log "React App container status: $(docker inspect -f '{{.State.Status}}' react-app)"

# Grafana Renderer
log "Deploying Grafana Renderer..."
docker run -d --network app-network --restart always --name renderer -p 8081:8081 \
    grafana/grafana-image-renderer:latest
log "Renderer container status: $(docker inspect -f '{{.State.Status}}' renderer)"

# Log final deployment status
log "=== Final Deployment Status ==="
log "Network Status: $(docker network inspect app-network -f '{{.Name}} is {{.Driver}}')"
log "Container Status Summary:"
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