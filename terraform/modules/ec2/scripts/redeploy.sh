#!/bin/bash

# Redeploy script - Stops and refreshes all Docker containers with latest ECR images
# Usage: Simply run 'redeploy' command

# Function for logging
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/redeploy.log
}

# Get instance metadata
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

# Make sure cowsay is installed
if ! command -v cowsay &> /dev/null; then
    log "Installing cowsay..."
    apt-get update -qq && apt-get install -y cowsay
fi

# Create redeploy log if it doesn't exist
touch /var/log/redeploy.log

log "===================================================="
cowsay -f dragon "Starting redeployment of all containers" | tee -a /var/log/redeploy.log
log "===================================================="

# Stop and remove all running containers
log "Stopping and removing all running containers..."
docker stop $(docker ps -q) 2>/dev/null || log "No containers to stop"
docker rm $(docker ps -a -q) 2>/dev/null || log "No containers to remove"

# Refresh ECR login
log "Refreshing ECR login credentials..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com
if [ $? -ne 0 ]; then
    log "ERROR: Failed to login to ECR. Aborting deployment."
    cowsay -f tux "ECR login failed! Deployment aborted." | tee -a /var/log/redeploy.log
    exit 1
fi

# Refresh secrets from AWS Secrets Manager
log "Refreshing secrets from AWS Secrets Manager..."
/opt/iykonect-aws-repo/terraform/modules/ec2/scripts/secrets-setup.sh
if [ $? -ne 0 ]; then
    log "WARNING: There was an issue refreshing secrets. Continuing with deployment..."
    cowsay -f sheep "Warning: Secrets refresh had issues" | tee -a /var/log/redeploy.log
fi

# Recreate docker network
log "Recreating docker network..."
docker network rm app-network 2>/dev/null || true
docker network create app-network

# Pull latest images from ECR
log "Pulling latest images from ECR..."
docker pull 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:api-latest
docker pull 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:web-latest
docker pull 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:signable-latest
docker pull 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:email-server-latest
docker pull 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:company-house-latest
docker pull 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:redis-latest
docker pull 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:prometheus-latest
docker pull 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:grafana-latest
docker pull nginx:latest

# Deploy API container
log "Deploying API container..."
docker run -d --network app-network --restart always --name api -p 0.0.0.0:8000:8000 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:api-latest

# Deploy Web container
log "Deploying Web container..."
docker run -d --network app-network --restart always --name web -p 0.0.0.0:5001:5001 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:web-latest

# Deploy Signable container
log "Deploying Signable container..."
docker run -d --network app-network --restart always --name signable -p 0.0.0.0:8082:8082 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:signable-latest

# Deploy Email Server container
log "Deploying Email Server container..."
docker run -d --network app-network --restart always --name email-server -p 0.0.0.0:8025:8025 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:email-server-latest

# Deploy Company House container
log "Deploying Company House container..."
docker run -d --network app-network --restart always --name company-house -p 0.0.0.0:8083:8083 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:company-house-latest

# Deploy Redis container
log "Deploying Redis container..."
docker run -d --network app-network --restart always --name redis -p 0.0.0.0:6379:6379 \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:redis-latest

# Deploy Prometheus container
log "Deploying Prometheus container..."
docker run -d --network app-network --restart always --name prometheus -p 0.0.0.0:9090:9090 \
    -v /opt/iykonect/prometheus:/etc/prometheus \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:prometheus-latest

# Deploy Grafana container
log "Deploying Grafana container..."
docker run -d --network app-network --restart always --name grafana -p 0.0.0.0:3100:3100 \
    -v /opt/iykonect/grafana:/var/lib/grafana \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:grafana-latest

# Deploy Nginx container as a controlled image for health checks
log "Deploying Nginx container..."
docker run -d --network app-network --restart always --name nginx-control -p 0.0.0.0:8008:80 \
    nginx:latest

# Wait for all containers to start
log "Waiting for all containers to start..."
sleep 10

# Run health check to verify deployment
log "Running health check..."
/opt/iykonect-aws-repo/terraform/modules/ec2/scripts/container-health-check.sh 2>&1 | tee -a /var/log/redeploy.log

# Display summary
log "===================================================="
cowsay -f turtle "Redeployment complete!" | tee -a /var/log/redeploy.log
log "===================================================="
log "Services available at:"
log "API URL:           http://${PUBLIC_IP}:8000"
log "Web URL:           http://${PUBLIC_IP}:5001"
log "Signable URL:      http://${PUBLIC_IP}:8082"
log "Email Server URL:  http://${PUBLIC_IP}:8025"
log "Company House URL: http://${PUBLIC_IP}:8083"
log "Redis Port:        ${PUBLIC_IP}:6379"
log "Prometheus URL:    http://${PUBLIC_IP}:9090"
log "Grafana URL:       http://${PUBLIC_IP}:3100"
log "Nginx Control URL: http://${PUBLIC_IP}:8008"
log "===================================================="