#!/bin/bash

# Enable logging of both stdout and stderr
exec 1> >(tee /var/log/user-data.log) 2>&1

echo "[$(date)] START - user data execution"

sudo apt-get update
sudo apt-get install -y docker.io awscli
sudo systemctl start docker
sudo systemctl enable docker
echo "[$(date)] Installed required packages"

# Configure AWS CLI
aws configure set aws_access_key_id "${aws_access_key}"
aws configure set aws_secret_access_key "${aws_secret_key}"
aws configure set region "${aws_region}"
echo "[$(date)] Configured AWS CLI"

# Configure AWS CLI and authenticate with ECR
aws ecr get-login-password --region ${aws_region} | sudo docker login --username AWS --password-stdin 571664317480.dkr.ecr.${aws_region}.amazonaws.com

# Create docker network
sudo docker network create app-network

# Pull images from ECR with detailed error handling
echo "[$(date)] Starting to pull images from ECR"
for image in redis prometheus grafana api react-app; do
    echo "[$(date)] Pulling image: $image"
    if output=$(sudo docker pull 571664317480.dkr.ecr.${aws_region}.amazonaws.com/iykonect-images:$image 2>&1); then
        echo "[$(date)] Successfully pulled $image"
        echo "Output: $output"
    else
        echo "[$(date)] ERROR: Failed to pull $image"
        echo "Error details: $output"
        exit 1
    fi
done

# Define container configurations
declare -A containers=(
    ["redis"]="--name redis_service -p 6379:6379 -e REDIS_PASSWORD=IYKONECTpassword"
    ["api"]="--name api -p 8000:80"
    ["prometheus"]="--name prometheus -p 9090:9090"
    ["grafana"]="--name iykon-graphana-app -p 3100:3000 --user root"
)

# Function to check container status
check_container() {
    local container_name=$1
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "[$(date)] Checking $container_name status (Attempt $attempt/$max_attempts)"
        if status=$(sudo docker inspect --format '{{.State.Status}}' "$container_name" 2>&1); then
            if [ "$status" = "running" ]; then
                echo "[$(date)] Container $container_name is running successfully"
                return 0
            else
                echo "[$(date)] Container $container_name status: $status"
            fi
        else
            echo "[$(date)] Error checking container status: $status"
        fi
        attempt=$((attempt + 1))
        sleep 5
    done
    return 1
}

# Run containers in a loop
echo "[$(date)] Starting containers"
for container in "${!containers[@]}"; do
    echo "[$(date)] Starting $container container"
    if [ "$container" = "redis" ]; then
        cmd="sudo docker run -d --network app-network --restart always ${containers[$container]} 571664317480.dkr.ecr.${aws_region}.amazonaws.com/iykonect-images:$container redis-server --requirepass IYKONECTpassword --bind 0.0.0.0"
    else
        cmd="sudo docker run -d --network app-network --restart always ${containers[$container]} 571664317480.dkr.ecr.${aws_region}.amazonaws.com/iykonect-images:$container"
    fi

    if output=$(eval "$cmd" 2>&1); then
        echo "[$(date)] $container container started successfully"
        echo "Container ID: $output"
        
        # Verify container is running properly
        container_name="${container}"
        if [ "$container" = "grafana" ]; then
            container_name="iykon-graphana-app"
        fi
        if ! check_container "$container_name"; then
            echo "[$(date)] ERROR: Container $container_name failed health check"
            exit 1
        fi
    else
        echo "[$(date)] ERROR: Failed to start $container container"
        echo "Error details: $output"
        exit 1
    fi
done

# Run Grafana Renderer (non-ECR image)
echo "[$(date)] Starting Grafana Renderer container"
if output=$(sudo docker run -d \
    --name renderer \
    --network app-network \
    -p 8081:8081 \
    --restart always \
    grafana/grafana-image-renderer:latest 2>&1); then
    echo "[$(date)] Grafana Renderer container started successfully"
    echo "Container ID: $output"
else
    echo "[$(date)] ERROR: Failed to start Grafana Renderer container"
    echo "Error details: $output"
    exit 1
fi

# Create required directories and set permissions
sudo mkdir -p /home/ubuntu/logs /home/ubuntu/grafana/{provisioning/datasources,provisioning/dashboards,dashboards}
sudo chown -R ubuntu:ubuntu /home/ubuntu/logs /home/ubuntu/grafana

echo "[$(date)] END - user data execution"