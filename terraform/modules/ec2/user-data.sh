#!/bin/bash

set -x
set -e

# Logging function
log() {
    echo "[$(date)] $1" >> /var/log/user-data.log
}

# Initial setup
sudo apt-get update
sudo apt-get install -y nfs-common awscli jq
log "Installed basic packages"


# Fetch credentials from S3
log "Fetching credentials from S3"
aws s3 cp s3://iykonect-aws-parallel/credentials.sh /root/credentials.sh
chmod 600 /root/credentials.sh

# Load credentials
sh /root/credentials.sh
log "Credentials loaded successfully"



# Configure AWS CLI
log "Configuring AWS CLI"
aws configure set aws_access_key_id "${AWS_ACCESS_KEY_ID}"
aws configure set aws_secret_access_key "${AWS_SECRET_ACCESS_KEY}"
aws configure set region "${AWS_REGION}"
aws configure set output "json"



# Setup mount point for EFS first
mount_point="/iykonect-data"
sudo mkdir -p $mount_point
log "Created mount point at $mount_point"

# Mount EFS before Docker installation
log "Mounting EFS filesystem at ${EFS_DNS_NAME}"
if ! sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport "${EFS_DNS_NAME}:/" $mount_point; then
    log "ERROR: Failed to mount EFS"
    exit 1
fi
log "EFS mounted successfully"

# Prepare Docker directories on EFS
sudo mkdir -p $mount_point/docker
sudo mkdir -p $mount_point/data
sudo mkdir -p $mount_point/logs
sudo chown -R root:root $mount_point/docker
sudo chmod -R 755 $mount_point/docker

# Now install Docker
sudo apt-get remove docker docker-engine docker.io containerd runc || true
sudo apt-get update
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Setup kernel modules and sysctl settings
cat << EOF | sudo tee /etc/modules-load.d/docker.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Configure system settings
cat << EOF | sudo tee -a /etc/sysctl.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
fs.inotify.max_user_watches = 524288
EOF

sudo sysctl -p

# Setup Docker daemon with EFS storage
sudo mkdir -p /etc/docker
cat << EOF | sudo tee /etc/docker/daemon.json
{
    "data-root": "$mount_point/docker",
    "storage-driver": "overlay2",
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m"
    },
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ]
}
EOF

# Install Docker and verify
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable docker
sudo systemctl start docker

# Verify Docker is using EFS
if ! sudo docker info | grep "Docker Root Dir: $mount_point/docker"; then
    log "ERROR: Docker not using EFS storage"
    exit 1
fi
log "Docker configured with EFS storage successfully"

log "START - user data execution"





# Verify AWS configuration
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log "ERROR: AWS CLI configuration failed"
    exit 1
fi
log "AWS CLI configured successfully"

# Restart Docker with new configuration
sudo systemctl daemon-reload
sudo systemctl restart docker

# Verify Docker is running
if ! sudo docker info > /dev/null 2>&1; then
    log "ERROR: Docker failed to start"
    exit 1
fi
log "Docker configured successfully"

# Create docker network
sudo docker network create app-network

# Clean up Docker system
log "Cleaning up Docker system"
sudo docker system prune -af
log "Docker system cleaned"

# Login to ECR
log "Authenticating with ECR"
if ! aws ecr get-login-password --region ${AWS_REGION} | sudo docker login --username AWS --password-stdin 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com; then
    log "ERROR: Failed to authenticate with ECR"
    exit 1
fi
log "Successfully authenticated with ECR"

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