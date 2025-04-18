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


##################################################################################################


# Function to setup EFS volume for Docker
setup_efs() {
    local mount_point="/iykonect-data"
    log "Starting EFS setup..."

    # Install EFS utilities
    log "Installing EFS utilities..."
    sudo apt-get install -y nfs-common

    # Create mount point
    log "Creating mount point at $mount_point"
    sudo mkdir -p $mount_point

    # Mount EFS filesystem
    log "Mounting EFS filesystem..."
    if ! sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport "${efs_dns_name}:/" $mount_point; then
        log "ERROR: Failed to mount EFS"
        return 1
    fi

    # Add to fstab
    if ! grep -q "$mount_point" /etc/fstab; then
        echo "${efs_dns_name}:/ $mount_point nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0" | sudo tee -a /etc/fstab
        log "Added fstab entry"
    fi

    # Configure Docker to use EFS
    sudo mkdir -p /etc/docker
    cat << EOF | sudo tee /etc/docker/daemon.json
{
    "data-root": "$mount_point/docker",
    "storage-driver": "overlay2"
}
EOF

    # Create Docker directory structure
    sudo mkdir -p $mount_point/{docker,data,logs}
    sudo chown -R root:root $mount_point/docker

    # Restart Docker
    log "Restarting Docker service..."
    if ! sudo systemctl restart docker; then
        log "ERROR: Failed to restart Docker service"
        return 1
    fi

    log "EFS setup completed successfully"
    return 0
}

#######################################################################################

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

##########################################################################################


# Install required packages
sudo apt-get update
sudo apt-get install -y docker.io awscli xfsprogs
sudo systemctl start docker
sudo systemctl enable docker
log "Installed required packages"

# Setup EFS volume for Docker
if ! setup_efs; then
    log "ERROR: Failed to setup EFS volume for Docker"
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