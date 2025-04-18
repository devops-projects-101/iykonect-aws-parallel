#!/bin/bash

# Logging function
log() {
    echo "[$(date)] $1" >> /var/log/user-data.log
}

# Initial setup
sudo apt-get update
sudo apt-get install -y docker.io awscli nfs-common jq
sudo systemctl start docker
sudo systemctl enable docker
log "Installed required packages"

log "START - user data execution"


# Fetch credentials from S3
log "Fetching credentials from S3"
aws s3 cp s3://iykonect-aws-parallel/credentials.sh /root/credentials.sh
chmod 600 /root/credentials.sh

# Load credentials
source /root/credentials.sh
log "Credentials loaded successfully"



# Setup mount point for EFS
mount_point="/iykonect-data"
sudo mkdir -p $mount_point
log "Created mount point at $mount_point"

# Mount EFS
log "Mounting EFS filesystem at ${EFS_DNS_NAME}"
if ! sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport "${EFS_DNS_NAME}:/" $mount_point; then
    log "ERROR: Failed to mount EFS"
    exit 1
fi
log "EFS mounted successfully"


# Configure AWS CLI
log "Configuring AWS CLI"
aws configure set aws_access_key_id "${AWS_ACCESS_KEY_ID}"
aws configure set aws_secret_access_key "${AWS_SECRET_ACCESS_KEY}"
aws configure set region "${AWS_REGION}"
aws configure set output "json"

# Verify AWS configuration
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log "ERROR: AWS CLI configuration failed"
    exit 1
fi
log "AWS CLI configured successfully"

# Setup Docker 
log "Configuring Docker with EFS storage"
sudo mkdir -p /etc/docker
cat << EOF | sudo tee /etc/docker/daemon.json
{
    "data-root": "$mount_point/docker",
    "storage-driver": "overlay2"
}
EOF

sudo mkdir -p $mount_point/{docker,data,logs}
sudo chown -R root:root $mount_point/docker
sudo systemctl restart docker

# Create docker network
sudo docker network create app-network

# Pull and run containers
log "Starting to pull and run containers"
for service in redis prometheus grafana api react-app; do
    log "Deploying $service"
    if ! sudo docker pull 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:$service; then
        log "ERROR: Failed to pull $service"
        exit 1
    fi

    case $service in
        "redis")
            cmd="sudo docker run -d --network app-network --restart always --name redis_service -p 6379:6379 -e REDIS_PASSWORD=IYKONECTpassword 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:redis redis-server --requirepass IYKONECTpassword --bind 0.0.0.0"
            ;;
        "api")
            cmd="sudo docker run -d --network app-network --restart always --name api -p 8000:80 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:api"
            ;;
        "prometheus")
            cmd="sudo docker run -d --network app-network --restart always --name prometheus -p 9090:9090 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:prometheus"
            ;;
        "grafana")
            cmd="sudo docker run -d --network app-network --restart always --name iykon-graphana-app -p 3100:3000 --user root 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:grafana"
            ;;
    esac

    if [ ! -z "$cmd" ] && ! eval "$cmd"; then
        log "ERROR: Failed to start $service"
        exit 1
    fi
    log "$service deployed successfully"
done

# Deploy Grafana Renderer
log "Deploying Grafana Renderer"
if ! sudo docker run -d --name renderer --network app-network -p 8081:8081 --restart always grafana/grafana-image-renderer:latest; then
    log "ERROR: Failed to start Grafana Renderer"
    exit 1
fi

log "END - user data execution"