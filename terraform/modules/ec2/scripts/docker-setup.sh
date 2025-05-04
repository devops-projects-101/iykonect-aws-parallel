#!/bin/bash

# Function for logging
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
}

# Wait for container to be healthy
wait_for_container() {
    local container=$1
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if [ "$(docker inspect -f '{{.State.Status}}' $container 2>/dev/null)" = "running" ]; then
            log "Container $container is running"
            # Check container logs for any startup errors
            docker logs $container | tail -n 20 | tee -a /var/log/user-data.log
            return 0
        fi
        log "Waiting for container $container (attempt $attempt/$max_attempts)"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log "ERROR: Container $container failed to start properly"
    docker logs $container | tee -a /var/log/user-data.log
    return 1
}

# Verify port availability
check_port() {
    local port=$1
    if lsof -i:"$port" >/dev/null 2>&1; then
        log "ERROR: Port $port is already in use"
        return 1
    fi
    return 0
}

# Function to validate endpoint health
validate_endpoint() {
    local endpoint="$1"
    local max_attempts=15
    local attempt=1
    local timeout=3
    
    log "Validating endpoint: $endpoint"
    
    # Try both localhost and public IP to help diagnose binding issues
    log "Checking local binding first: http://localhost:${endpoint##*:}"
    curl -v "http://localhost:${endpoint##*:}" --max-time $timeout 2>&1 | tee -a /var/log/user-data.log
    
    log "Checking 127.0.0.1 binding: http://127.0.0.1:${endpoint##*:}"
    curl -v "http://127.0.0.1:${endpoint##*:}" --max-time $timeout 2>&1 | tee -a /var/log/user-data.log
    
    while [ $attempt -le $max_attempts ]; do
        local response
        local status_code
        
        # Capture both response and error output
        response=$(curl -s -o /dev/null -w "%{http_code}" --request GET "$endpoint" --max-time $timeout 2>&1)
        status_code=$?
        
        if [ $status_code -eq 0 ] && [ "$response" -ge 200 ] && [ "$response" -lt 400 ]; then
            log "✅ Endpoint $endpoint is healthy (HTTP $response)"
            return 0
        else
            # Get detailed error message for logging
            if [ $status_code -ne 0 ]; then
                error_msg=$(curl -s --request GET "$endpoint" --max-time $timeout 2>&1)
                log "❌ Endpoint check failed: $error_msg (curl exit code: $status_code)"
                
                # Check network configuration
                log "Network configuration for container on port ${endpoint##*:}:"
                docker ps -q | xargs docker inspect --format='{{.Name}} {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | tee -a /var/log/user-data.log
                netstat -tulpn | grep ${endpoint##*:} | tee -a /var/log/user-data.log
            else
                log "❌ Endpoint returned HTTP status: $response"
            fi
            
            log "Waiting for endpoint $endpoint to become available (attempt $attempt/$max_attempts)"
            sleep 5
            attempt=$((attempt + 1))
        fi
    done
    
    # Final detailed error check if all attempts failed
    log "ERROR: Endpoint $endpoint failed health check after $max_attempts attempts"
    log "FINAL DETAILED CHECK:"
    curl -v --request GET "$endpoint" --max-time $timeout 2>&1 | tee -a /var/log/user-data.log
    
    log "CONTAINER LOGS for port ${endpoint##*:}:"
    # Find container exposed on this port
    port_number=${endpoint##*:}
    container_id=$(docker ps -q --filter publish=$port_number)
    if [ -n "$container_id" ]; then
        docker logs $container_id | tail -n 50 | tee -a /var/log/user-data.log
    else
        log "No container found exposing port $port_number"
    fi
    
    return 1
}

# Get instance metadata
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

# Install Docker
log "==============================================="
log "Starting Docker installation and setup"
log "==============================================="
log "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

# System settings
log "Configuring system settings for Docker..."
echo "fs.inotify.max_user_watches = 524288" >> /etc/sysctl.conf
sysctl -p

# Install Docker packages
log "Installing Docker packages..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io
systemctl enable docker
systemctl start docker

# Docker setup
log "Setting up Docker environment..."
docker system prune -af
docker network create app-network || true

# Login to ECR
log "Logging into ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com

# Function to run docker command
run_docker() {
    local command="$1"
    local container="$2"
    
    log "Running: $command"
    output=$(eval "$command" 2>&1) || {
        log "ERROR: Docker command failed: $output"
        return 1
    }
    
    wait_for_container "$container" || return 1
    return 0
}

# Deploy API container
log "Deploying API container..."
if ! check_port 8000; then
    log "ERROR: Port 8000 is not available"
    exit 1
fi
run_docker "docker run -d --network app-network --restart always --name api -p 0.0.0.0:8000:8000 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:api-latest" "api" || exit 1
validate_endpoint "http://${PRIVATE_IP}:8000" || log "API validation failed but continuing deployment"

# Deploy Web container
log "Deploying Web container..."
if ! check_port 5001; then
    log "ERROR: Port 5001 is not available"
    exit 1
fi
run_docker "docker run -d --network app-network --restart always --name web -p 0.0.0.0:5001:5001 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:web-latest" "web" || exit 1
validate_endpoint "http://${PRIVATE_IP}:5001" || log "Web validation failed but continuing deployment"

# Deploy Signable container
log "Deploying Signable container..."
if ! check_port 8082; then
    log "ERROR: Port 8082 is not available"
    exit 1
fi
run_docker "docker run -d --network app-network --restart always --name signable -p 0.0.0.0:8082:8082 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:signable-latest" "signable" || exit 1
validate_endpoint "http://${PRIVATE_IP}:8082" || log "Signable validation failed but continuing deployment"

# Deploy Email Server container
log "Deploying Email Server container..."
if ! check_port 8025; then
    log "ERROR: Port 8025 is not available"
    exit 1
fi
run_docker "docker run -d --network app-network --restart always --name email-server -p 0.0.0.0:8025:8025 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:email-server-latest" "email-server" || exit 1
validate_endpoint "http://${PRIVATE_IP}:8025" || log "Email server validation failed but continuing deployment"

# Deploy Company House container
log "Deploying Company House container..."
if ! check_port 8083; then
    log "ERROR: Port 8083 is not available"
    exit 1
fi
run_docker "docker run -d --network app-network --restart always --name company-house -p 0.0.0.0:8083:8083 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:company-house-latest" "company-house" || exit 1
validate_endpoint "http://${PRIVATE_IP}:8083" || log "Company House validation failed but continuing deployment"

# Deploy Redis container
log "Deploying Redis container..."
if ! check_port 6379; then
    log "ERROR: Port 6379 is not available"
    exit 1
fi
run_docker "docker run -d --network app-network --restart always --name redis -p 0.0.0.0:6379:6379 \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:redis-latest" "redis" || exit 1

# Deploy Prometheus container
log "Deploying Prometheus container..."
if ! check_port 9090; then
    log "ERROR: Port 9090 is not available"
    exit 1
fi
run_docker "docker run -d --network app-network --restart always --name prometheus -p 0.0.0.0:9090:9090 \
    -v /opt/iykonect/prometheus:/etc/prometheus \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:prometheus-latest" "prometheus" || exit 1
validate_endpoint "http://${PRIVATE_IP}:9090" || log "Prometheus validation failed but continuing deployment"

# Deploy Grafana container
log "Deploying Grafana container..."
if ! check_port 3100; then
    log "ERROR: Port 3100 is not available"
    exit 1
fi
run_docker "docker run -d --network app-network --restart always --name grafana -p 0.0.0.0:3100:3100 \
    -v /opt/iykonect/grafana:/var/lib/grafana \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:grafana-latest" "grafana" || exit 1
validate_endpoint "http://${PRIVATE_IP}:3100" || log "Grafana validation failed but continuing deployment"

# Display network configuration
log "==============================================="
log "Network configuration"
log "==============================================="
log "IP Addresses:"
ip addr show | grep "inet " | tee -a /var/log/user-data.log

log "Network routes:"
route -n | tee -a /var/log/user-data.log

log "Docker networks:"
docker network ls | tee -a /var/log/user-data.log
docker network inspect app-network | tee -a /var/log/user-data.log

log "Container IP addresses:"
docker ps -q | xargs docker inspect --format='{{.Name}} {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | tee -a /var/log/user-data.log

log "Published ports:"
docker ps --format "{{.Names}}: {{.Ports}}" | tee -a /var/log/user-data.log

log "==============================================="
log "Docker setup and deployment completed"
log "==============================================="

# Final status
log "=== Deployment Complete ==="
log "Public IP: ${PUBLIC_IP}"
log "Private IP: ${PRIVATE_IP}"
log "API URL: http://${PUBLIC_IP}:8000"
log "Web URL: http://${PUBLIC_IP}:5001"
log "Signable URL: http://${PUBLIC_IP}:8082"
log "Email Server URL: http://${PUBLIC_IP}:8025"
log "Company House URL: http://${PUBLIC_IP}:8083"
log "Redis Port: ${PUBLIC_IP}:6379"
log "Prometheus URL: http://${PUBLIC_IP}:9090"
log "Grafana URL: http://${PUBLIC_IP}:3100"