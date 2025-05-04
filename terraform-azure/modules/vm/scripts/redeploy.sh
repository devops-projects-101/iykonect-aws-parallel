#!/bin/bash

# This script handles redeployment of containers in the Azure environment

set -e

# Logging function
log() {
    echo "[$(date)] $1" | tee -a /var/log/redeploy.log
}

log "Starting container redeployment process..."

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
ECR_LOGIN_RESULT=$(aws ecr get-login-password --region ${AWS_DEFAULT_REGION:-eu-west-1} | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.${AWS_DEFAULT_REGION:-eu-west-1}.amazonaws.com 2>&1)

if [ $? -ne 0 ]; then
    log "ERROR: Failed to authenticate with AWS ECR: $ECR_LOGIN_RESULT"
    exit 1
fi

log "Successfully authenticated with AWS ECR"

# Pull the latest images
if [ -f /opt/iykonect-aws-repo/docker/docker-compose.yml ]; then
    cd /opt/iykonect-aws-repo/docker
    
    log "Pulling latest images from ECR..."
    docker-compose pull
    
    log "Restarting containers..."
    docker-compose down
    docker-compose up -d
    
    log "Containers redeployed successfully"
else
    log "ERROR: docker-compose.yml file not found at expected location"
    exit 1
fi

# Clean up unused images to save disk space
log "Cleaning up unused Docker images..."
docker image prune -f

log "Redeployment process completed successfully"
exit 0