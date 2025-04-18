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
sudo apt-get install -y docker.io awscli
sudo systemctl start docker
sudo systemctl enable docker
log "Installed required packages"

# Configure AWS CLI
aws_region="eu-west-1"
aws configure set aws_access_key_id "${aws_access_key}"
aws configure set aws_secret_access_key "${aws_secret_key}"
aws configure set region "eu-west-1"
log "Configured AWS CLI"

# Configure AWS CLI and authenticate with ECR
aws ecr get-login-password --region eu-west-1 | sudo docker login --username AWS --password-stdin 571664317480.dkr.ecr.eu-west-1.amazonaws.com

# Create docker network
sudo docker network create app-network

# Function to check disk space
check_disk_space() {
    local threshold=80
    local usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ $usage -gt $threshold ]; then
        log "WARNING: Disk usage is at ${usage}%. Cleaning up..."
        # Clean Docker
        sudo docker system prune -af
        sudo docker volume prune -f
        sudo docker builder prune -af
        
        # Clear package manager cache
        sudo apt-get clean
        sudo apt-get autoremove -y
        
        # Show new disk usage
        df -h
    fi
}

# Pull images from ECR with detailed error handling and disk space checks
log "Starting to pull images from ECR"
for image in redis prometheus grafana api react-app; do
    check_disk_space
    log "Pulling image: $image"
    if output=$(sudo docker pull 571664317480.dkr.ecr.eu-west-1.amazonaws.com/iykonect-images:$image 2>&1); then
        log "Successfully pulled $image"
        log "Output: $output"
    else
        log "ERROR: Failed to pull $image"
        log "Error details: $output"
        check_disk_space
        exit 1
    fi
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