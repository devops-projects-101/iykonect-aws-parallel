#!/bin/bash

# Logging function
log() {
    echo "[$(date)] $1" >> /var/log/user-data.log
}

log "START - user data execution"

# Validate required AWS credentials
validate_aws_inputs() {
    declare -a missing_vars

    [ -z "${aws_access_key}" ] && missing_vars[${#missing_vars[@]}]="aws_access_key"
    [ -z "${aws_secret_key}" ] && missing_vars[${#missing_vars[@]}]="aws_secret_key"
    [ -z "${aws_region}" ] && missing_vars[${#missing_vars[@]}]="aws_region"
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log "ERROR: Missing required AWS credentials:"
        for var in "${missing_vars[@]}"; do
            log "  - $var"
        done
        return 1
    fi
    
    log "AWS credentials validation passed"
    return 0
}

if ! validate_aws_inputs; then
    exit 1
fi

# Initial setup
sudo apt-get update
sudo apt-get install -y docker.io awscli nfs-common
sudo systemctl start docker
sudo systemctl enable docker
log "Installed required packages"

# Setup EFS
mount_point="/iykonect-data"
log "Setting up EFS at $mount_point"

# Mount EFS with retries
mount_efs() {
    max_attempts=5
    attempt=1
    mount_options="nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport"
    
    while [ $attempt -le $max_attempts ]; do
        log "Attempting to mount EFS (Attempt $attempt/$max_attempts)"
        
        # Test EFS endpoint
        if ! nc -zv "${efs_dns_name}" 2049 >/dev/null 2>&1; then
            log "WARNING: EFS endpoint not reachable, waiting..."
            sleep 10
            attempt=$((attempt + 1))
            continue
        fi
        
        # Try mounting
        if sudo mount -t nfs4 -o "$mount_options" "${efs_dns_name}:/" "$mount_point"; then
            log "EFS mounted successfully"
            echo "${efs_dns_name}:/ $mount_point nfs4 $mount_options,_netdev 0 0" | sudo tee -a /etc/fstab
            return 0
        fi
        
        log "Mount attempt $attempt failed, retrying..."
        attempt=$((attempt + 1))
        sleep 5
    done
    
    log "ERROR: Failed to mount EFS after $max_attempts attempts"
    return 1
}

# Create mount point and attempt mount
sudo mkdir -p $mount_point
if ! mount_efs; then
    exit 1
fi

# Configure Docker
sudo mkdir -p /etc/docker
cat << EOF | sudo tee /etc/docker/daemon.json
{
    "data-root": "$mount_point/docker",
    "storage-driver": "overlay2"
}
EOF

# Setup Docker directories
sudo mkdir -p $mount_point/{docker,data,logs}
sudo chown -R root:root $mount_point/docker
sudo systemctl restart docker

# Configure AWS CLI with proper validation
configure_aws() {
    log "Setting up AWS credentials"
    
    # Set AWS environment variables first
    export AWS_DEFAULT_REGION="${aws_region}"
    export AWS_REGION="${aws_region}"
    export AWS_ACCESS_KEY_ID="${aws_access_key}"
    export AWS_SECRET_ACCESS_KEY="${aws_secret_key}"

    # Create AWS config directory with proper permissions
    mkdir -p /root/.aws
    chmod 700 /root/.aws

    # Write credentials file
    cat > /root/.aws/credentials << EOF
[default]
aws_access_key_id = ${aws_access_key}
aws_secret_access_key = ${aws_secret_key}
EOF
    chmod 600 /root/.aws/credentials

    # Write config file
    cat > /root/.aws/config << EOF
[default]
region = ${aws_region}
output = json
EOF
    chmod 600 /root/.aws/config

    # Verify credentials work
    for i in {1..3}; do
        log "Verifying AWS credentials (attempt $i/3)"
        if aws sts get-caller-identity --region "${aws_region}" >/dev/null 2>&1; then
            log "AWS credentials verified successfully"
            return 0
        fi
        sleep 5
    done

    log "ERROR: Failed to validate AWS credentials after 3 attempts"
    return 1
}

# Run AWS configuration
if ! configure_aws; then
    exit 1
fi

# Login to ECR
aws ecr get-login-password --region "${aws_region}" | sudo docker login --username AWS --password-stdin 571664317480.dkr.ecr."${aws_region}".amazonaws.com

# Create docker network
sudo docker network create app-network

# Pull images and run containers
log "Starting to pull images from ECR"
for service in redis prometheus grafana api react-app; do
    log "Pulling image: $service"
    if sudo docker pull 571664317480.dkr.ecr."${aws_region}".amazonaws.com/iykonect-images:"$service"; then
        log "Successfully pulled $service"
    else
        log "ERROR: Failed to pull $service"
        exit 1
    fi

    log "Starting $service container"
    case $service in
        "redis")
            cmd="sudo docker run -d --network app-network --restart always --name redis_service -p 6379:6379 -e REDIS_PASSWORD=IYKONECTpassword 571664317480.dkr.ecr.${aws_region}.amazonaws.com/iykonect-images:redis redis-server --requirepass IYKONECTpassword --bind 0.0.0.0"
            ;;
        "api")
            cmd="sudo docker run -d --network app-network --restart always --name api -p 8000:80 571664317480.dkr.ecr.${aws_region}.amazonaws.com/iykonect-images:api"
            ;;
        "prometheus")
            cmd="sudo docker run -d --network app-network --restart always --name prometheus -p 9090:9090 571664317480.dkr.ecr.${aws_region}.amazonaws.com/iykonect-images:prometheus"
            ;;
        "grafana")
            cmd="sudo docker run -d --network app-network --restart always --name iykon-graphana-app -p 3100:3000 --user root 571664317480.dkr.ecr.${aws_region}.amazonaws.com/iykonect-images:grafana"
            ;;
    esac

    if [ ! -z "$cmd" ]; then
        if eval "$cmd"; then
            log "$service container started successfully"
        else
            log "ERROR: Failed to start $service container"
            exit 1
        fi
    fi
done

# Run Grafana Renderer (non-ECR image)
log "Starting Grafana Renderer container"
if sudo docker run -d \
    --name renderer \
    --network app-network \
    -p 8081:8081 \
    --restart always \
    grafana/grafana-image-renderer:latest; then
    log "Grafana Renderer container started successfully"
else
    log "ERROR: Failed to start Grafana Renderer container"
    exit 1
fi

# Create required directories and set permissions
sudo mkdir -p /home/ubuntu/logs /home/ubuntu/grafana/{provisioning/datasources,provisioning/dashboards,dashboards}
sudo chown -R ubuntu:ubuntu /home/ubuntu/logs /home/ubuntu/grafana

log "END - user data execution"