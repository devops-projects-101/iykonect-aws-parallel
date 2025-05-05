#!/bin/bash

# This script handles deployment and redeployment of containers in the Azure environment

set -e

# Logging function
log() {
    echo "[$(date)] $1" | tee -a /var/log/redeploy.log
}

# Get instance metadata for Azure
VM_NAME=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text")
RESOURCE_GROUP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text")
LOCATION=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")
PUBLIC_IP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text")
PRIVATE_IP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2021-02-01&format=text")

log "Starting container deployment/redeployment process..."
log "VM Information:"
log "Name: $VM_NAME"
log "Resource Group: $RESOURCE_GROUP"
log "Location: $LOCATION"
log "Public IP: $PUBLIC_IP"
log "Private IP: $PRIVATE_IP"

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    log "ERROR: Docker is not installed"
    exit 1
fi

if ! systemctl is-active --quiet docker; then
    log "ERROR: Docker service is not running. Attempting to start..."
    systemctl start docker
    sleep 5
    
    if ! systemctl is-active --quiet docker; then
        log "ERROR: Failed to start Docker service"
        exit 1
    fi
fi

# Stop and remove all running containers
log "Stopping and removing all running containers..."
docker stop $(docker ps -q) 2>/dev/null || log "No containers to stop"
docker rm $(docker ps -a -q) 2>/dev/null || log "No containers to remove"

# Recreate docker network
log "Creating/recreating docker network..."
docker network rm app-network 2>/dev/null || true
docker network create app-network || true

# Make sure AWS credentials are available for ECR access
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_DEFAULT_REGION" ]; then
    log "AWS credentials not found in environment. Checking ~/.aws/credentials..."
    
    if [ ! -f ~/.aws/credentials ]; then
        log "ERROR: AWS credentials not found. Cannot authenticate with ECR."
        exit 1
    fi
fi

# Login to AWS ECR
log "Authenticating with AWS ECR..."
ECR_LOGIN_RESULT=$(aws ecr get-login-password --region ${AWS_DEFAULT_REGION:-eu-west-1} | docker login --username AWS --password-stdin 571664317480.dkr.ecr.${AWS_DEFAULT_REGION:-eu-west-1}.amazonaws.com 2>&1)

if [ $? -ne 0 ]; then
    log "ERROR: Failed to authenticate with AWS ECR: $ECR_LOGIN_RESULT"
    exit 1
fi

log "Successfully authenticated with AWS ECR"

# Function to run docker command with appropriate error handling
run_docker() {
    local command="$1"
    local container="$2"
    
    log "Running: $command"
    output=$(eval "$command" 2>&1) || {
        log "ERROR: Docker command failed: $output"
        return 1
    }
    
    # Check if container is running
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if [ "$(docker inspect -f '{{.State.Status}}' $container 2>/dev/null)" = "running" ]; then
            log "Container $container is running"
            # Check container logs for any startup errors
            docker logs $container | tail -n 20 | tee -a /var/log/redeploy.log
            return 0
        fi
        log "Waiting for container $container (attempt $attempt/$max_attempts)"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log "ERROR: Container $container failed to start properly"
    docker logs $container | tee -a /var/log/redeploy.log
    return 1
}

# Pull the latest images
log "Pulling latest images from ECR..."
docker pull 571664317480.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/iykonect-images:api-latest
docker pull 571664317480.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/iykonect-images:web-latest
docker pull 571664317480.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/iykonect-images:signable-latest
docker pull 571664317480.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/iykonect-images:email-server-latest
docker pull 571664317480.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/iykonect-images:company-house-latest
docker pull 571664317480.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/iykonect-images:redis-latest
docker pull 571664317480.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/iykonect-images:prometheus-latest
docker pull 571664317480.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/iykonect-images:grafana-latest
docker pull nginx:latest

# Deploy containers with Azure-specific configurations
log "Deploying containers with Azure-specific configurations..."

# API Container
log "Deploying API container..."
run_docker "docker run -d --network app-network --restart always --name api -p 0.0.0.0:8000:80 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    -e AZURE_VM=true \
    -e AZURE_LOCATION=$LOCATION \
    -e AZURE_RESOURCE_GROUP=$RESOURCE_GROUP \
    571664317480.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/iykonect-images:api-latest" "api" || exit 1

# Web Container
log "Deploying Web container..."
run_docker "docker run -d --network app-network --restart always --name web -p 0.0.0.0:3000:3000 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    -e AZURE_VM=true \
    -e AZURE_LOCATION=$LOCATION \
    -e AZURE_RESOURCE_GROUP=$RESOURCE_GROUP \
    571664317480.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/iykonect-images:web-latest" "web" || exit 1

# Signable Container
log "Deploying Signable container..."
run_docker "docker run -d --network app-network --restart always --name signable -p 0.0.0.0:8082:80 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    -e AZURE_VM=true \
    571664317480.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/iykonect-images:signable-latest" "signable" || exit 1

# Email Server Container
log "Deploying Email Server container..."
run_docker "docker run -d --network app-network --restart always --name email-server -p 0.0.0.0:8025:5001 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    -e AZURE_VM=true \
    571664317480.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/iykonect-images:email-server-latest" "email-server" || exit 1

# Company House Container
log "Deploying Company House container..."
run_docker "docker run -d --network app-network --restart always --name company-house -p 0.0.0.0:8083:80 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    -e AZURE_VM=true \
    571664317480.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/iykonect-images:company-house-latest" "company-house" || exit 1

# Redis Container
log "Deploying Redis container..."
run_docker "docker run -d --network app-network --restart always --name redis -p 0.0.0.0:6379:6379 \
    571664317480.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/iykonect-images:redis-latest" "redis" || exit 1

# Prometheus Container
log "Deploying Prometheus container..."
run_docker "docker run -d --network app-network --restart always --name prometheus -p 0.0.0.0:9090:9090 \
    -v /opt/iykonect/prometheus:/etc/prometheus \
    571664317480.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/iykonect-images:prometheus-latest" "prometheus" || exit 1

# Grafana Container
log "Deploying Grafana container..."
run_docker "docker run -d --network app-network --restart always --name grafana -p 0.0.0.0:3100:3000 \
    -v /opt/iykonect/grafana:/var/lib/grafana \
    571664317480.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/iykonect-images:grafana-latest" "grafana" || exit 1

# Nginx Control Container
log "Deploying Nginx control container..."
run_docker "docker run -d --network app-network --restart always --name nginx-control -p 0.0.0.0:8008:80 \
    nginx:latest" "nginx-control" || exit 1

log "All containers deployed successfully"

# Run health check to verify deployment
log "Running health check..."
/opt/iykonect-aws-repo/terraform-azure/modules/vm/scripts/container-health-check.sh 2>&1 | tee -a /var/log/redeploy.log

# Clean up unused images to save disk space
log "Cleaning up unused Docker images..."
docker image prune -f

# Display network configuration
log "==============================================="
log "Network configuration"
log "==============================================="
log "IP Addresses:"
ip addr show | grep "inet " | tee -a /var/log/redeploy.log

log "Docker networks:"
docker network ls | tee -a /var/log/redeploy.log
docker network inspect app-network | tee -a /var/log/redeploy.log

log "Container IP addresses:"
docker ps -q | xargs docker inspect --format='{{.Name}} {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | tee -a /var/log/redeploy.log

log "Published ports:"
docker ps --format "{{.Names}}: {{.Ports}}" | tee -a /var/log/redeploy.log

# Final status
log "==============================================="
log "Azure Docker setup and deployment completed"
log "==============================================="
log "=== Azure Docker Deployment Complete ==="
log "Public IP: ${PUBLIC_IP}"
log "Private IP: ${PRIVATE_IP}"
log "API URL: http://${PUBLIC_IP}:8000"
log "Web URL: http://${PUBLIC_IP}:3000"
log "Signable URL: http://${PUBLIC_IP}:8082"
log "Email Server URL: http://${PUBLIC_IP}:8025"
log "Company House URL: http://${PUBLIC_IP}:8083"
log "Redis Port: ${PUBLIC_IP}:6379"
log "Prometheus URL: http://${PUBLIC_IP}:9090"
log "Grafana URL: http://${PUBLIC_IP}:3100"
log "Nginx Control URL: http://${PUBLIC_IP}:8008"

log "Redeployment process completed successfully"
exit 0