#!/bin/bash

# Enable logging of both stdout and stderr
# exec 1> /var/log/user-data.log 2>&1

# Logging function
log() {
    echo "[$(date)] $1 "
    echo "[$(date)] $1 " >> /var/log/user-data.log
}

log "START - user data execution"

# Clean up disk space
log "Cleaning up disk space"
sudo apt-get clean
sudo apt-get autoremove -y
sudo rm -rf /var/lib/apt/lists/*
sudo rm -rf /usr/share/doc/*
sudo rm -rf /usr/share/man/*
sudo rm -rf /var/cache/apt/*
sudo rm -rf /var/tmp/*
sudo rm -rf /tmp/*
log "Disk cleanup completed"

# Show disk space
df -h
log "Current disk space usage shown above"

sudo apt-get update
sudo apt-get install -y docker.io awscli xfsprogs
sudo systemctl start docker
sudo systemctl enable docker
log "Installed required packages"

# Wait for EBS volume to be attached
log "Waiting for EBS volume to be available..."
while [ ! -e /dev/xvdf ]; do
    log "EBS volume not yet attached, waiting 5 seconds..."
    sleep 5
done
log "EBS volume detected at /dev/xvdf"

# Format and mount the EBS volume
log "Preparing EBS volume for Docker data"
if sudo file -s /dev/xvdf | grep -q "data"; then
    log "Formatting EBS volume with XFS..."
    sudo mkfs.xfs /dev/xvdf
else
    log "EBS volume already formatted"
fi

log "Creating mount point directory..."
sudo mkdir -p /docker-data

log "Mounting EBS volume..."
if sudo mount /dev/xvdf /docker-data; then
    log "EBS volume mounted successfully"
else
    log "ERROR: Failed to mount EBS volume"
    exit 1
fi

# Add mount to fstab
log "Adding mount to fstab for persistence"
if grep -q "/docker-data" /etc/fstab; then
    log "Fstab entry already exists"
else
    echo "/dev/xvdf /docker-data xfs defaults 0 0" | sudo tee -a /etc/fstab
    log "Added fstab entry"
fi

# Configure Docker to use the new volume
log "Configuring Docker to use EBS volume"
sudo mkdir -p /etc/docker
cat << EOF | sudo tee /etc/docker/daemon.json
{
    "data-root": "/docker-data",
    "storage-driver": "overlay2"
}
EOF

# Verify Docker data directory
sudo mkdir -p /docker-data/docker
log "Docker data directory created on EBS volume"

# Restart Docker to apply new configuration
log "Restarting Docker service..."
if sudo systemctl restart docker; then
    log "Docker service restarted successfully"
else
    log "ERROR: Failed to restart Docker service"
    exit 1
fi

# Verify Docker is running with new configuration
if sudo docker info | grep "Docker Root Dir: /docker-data"; then
    log "Docker successfully configured to use EBS volume"
else
    log "ERROR: Docker not using EBS volume"
    exit 1
fi

# Configure AWS CLI
log "Configuring AWS CLI"
mkdir -p /root/.aws
cat > /root/.aws/credentials << EOF
[default]
aws_access_key_id = ${aws_access_key}
aws_secret_access_key = ${aws_secret_key}
EOF

cat > /root/.aws/config << EOF
[default]
region = eu-west-1
output = json
EOF

chmod 600 /root/.aws/credentials
chmod 600 /root/.aws/config
log "AWS CLI credentials configured"

# Verify AWS CLI configuration
if aws sts get-caller-identity > /dev/null 2>&1; then
    log "AWS CLI configuration verified successfully"
else
    log "ERROR: AWS CLI configuration failed"
    exit 1
fi

# Configure AWS CLI and authenticate with ECR
aws ecr get-login-password --region eu-west-1 | sudo docker login --username AWS --password-stdin 571664317480.dkr.ecr.eu-west-1.amazonaws.com

# Create docker network
sudo docker network create app-network

# Function to check disk space
check_disk_space() {
    USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    log "Current disk usage: $USAGE%"
    
    if [ "$USAGE" -gt 70 ]; then
        log "WARNING: Disk usage is high at $USAGE%. Performing cleanup..."
        
        # Stop and remove all containers
        sudo docker stop $(sudo docker ps -aq) 2>/dev/null
        sudo docker rm $(sudo docker ps -aq) 2>/dev/null
        
        # Remove all images
        sudo docker rmi $(sudo docker images -q) 2>/dev/null
        
        # Clean Docker system
        sudo docker system prune -af
        sudo docker volume prune -f
        sudo docker builder prune -af
        
        # Clear package manager and system caches
        sudo apt-get clean
        sudo apt-get autoremove -y
        sudo rm -rf /var/lib/apt/lists/*
        sudo rm -rf /var/cache/*
        sudo rm -rf /tmp/*
        sudo rm -rf /var/tmp/*
        
        # Clear npm and yarn caches
        sudo rm -rf /usr/local/share/.cache/yarn
        sudo rm -rf /root/.npm
        sudo rm -rf /home/ubuntu/.npm
        
        NEW_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
        log "Disk usage after cleanup: $NEW_USAGE%"
        
        if [ "$NEW_USAGE" -gt 80 ]; then
            log "ERROR: Unable to free sufficient disk space"
            return 1
        fi
    fi
    return 0
}

# Pull images from ECR with detailed error handling and disk space checks
log "Starting to pull images from ECR"
for image in redis prometheus grafana api react-app; do
    if ! check_disk_space; then
        log "ERROR: Insufficient disk space to pull images"
        exit 1
    fi
    
    log "Pulling image: $image"
    PULL_CMD="sudo docker pull 571664317480.dkr.ecr.eu-west-1.amazonaws.com/iykonect-images:$image"
    
    while IFS= read -r line; do
        log "$line"
        if [[ $line == *"no space left on device"* ]]; then
            if ! check_disk_space; then
                log "ERROR: Failed to free up space during pull"
                exit 1
            fi
        fi
    done < <($PULL_CMD 2>&1 || echo "PULL_FAILED: $?")
    
    if ! sudo docker image inspect 571664317480.dkr.ecr.eu-west-1.amazonaws.com/iykonect-images:$image >/dev/null 2>&1; then
        log "ERROR: Failed to pull $image"
        exit 1
    fi
    
    log "Successfully pulled $image"
done

# Function to check container status
check_container() {
    local container_name=$1
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Checking $container_name status (Attempt $attempt/$max_attempts)"
        if status=$(sudo docker inspect --format '{{.State.Status}}' "$container_name" 2>&1); then
            if [ "$status" = "running" ]; then
                log "Container $container_name is running successfully"
                return 0
            else
                log "Container $container_name status: $status"
            fi
        else
            log "Error checking container status: $status"
        fi
        attempt=$((attempt + 1))
        sleep 5
    done
    return 1
}

# Pull images and run containers
for service in redis prometheus grafana api react-app; do
    log "Starting $service container"
    
    case $service in
        "redis")
            cmd="sudo docker run -d --network app-network --restart always --name redis_service -p 6379:6379 -e REDIS_PASSWORD=IYKONECTpassword 571664317480.dkr.ecr.eu-west-1.amazonaws.com/iykonect-images:redis redis-server --requirepass IYKONECTpassword --bind 0.0.0.0"
            container_name="redis_service"
            ;;
        "api")
            cmd="sudo docker run -d --network app-network --restart always --name api -p 8000:80 571664317480.dkr.ecr.eu-west-1.amazonaws.com/iykonect-images:api"
            container_name="api"
            ;;
        "prometheus")
            cmd="sudo docker run -d --network app-network --restart always --name prometheus -p 9090:9090 571664317480.dkr.ecr.eu-west-1.amazonaws.com/iykonect-images:prometheus"
            container_name="prometheus"
            ;;
        "grafana")
            cmd="sudo docker run -d --network app-network --restart always --name iykon-graphana-app -p 3100:3000 --user root 571664317480.dkr.ecr.eu-west-1.amazonaws.com/iykonect-images:grafana"
            container_name="iykon-graphana-app"
            ;;
    esac

    if [ ! -z "$cmd" ]; then
        if output=$(eval "$cmd" 2>&1); then
            log "$service container started successfully"
            log "Container ID: $output"
            
            # Verify container is running properly
            if ! check_container "$container_name"; then
                log "ERROR: Container $container_name failed health check"
                exit 1
            fi
        else
            log "ERROR: Failed to start $service container"
            log "Error details: $output"
            exit 1
        fi
    fi
done

# Run Grafana Renderer (non-ECR image)
log "Starting Grafana Renderer container"
if output=$(sudo docker run -d \
    --name renderer \
    --network app-network \
    -p 8081:8081 \
    --restart always \
    grafana/grafana-image-renderer:latest 2>&1); then
    log "Grafana Renderer container started successfully"
    log "Container ID: $output"
else
    log "ERROR: Failed to start Grafana Renderer container"
    log "Error details: $output"
    exit 1
fi

# Create required directories and set permissions
sudo mkdir -p /home/ubuntu/logs /home/ubuntu/grafana/{provisioning/datasources,provisioning/dashboards,dashboards}
sudo chown -R ubuntu:ubuntu /home/ubuntu/logs /home/ubuntu/grafana

log "END - user data execution"