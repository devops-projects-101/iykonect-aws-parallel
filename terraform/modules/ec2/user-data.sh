#!/bin/bash

# Ensure script runs as root
if [ "$(id -u)" != "0" ]; then
   exec sudo "$0" "$@"
fi

set -x
set -e

# Logging function with proper permissions
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
}

#region Variables
AWS_REGION=eu-west-1

# Verify port is available
check_port() {
    local port=$1
    if lsof -i:"$port" >/dev/null 2>&1; then
        log "ERROR: Port $port is already in use"
        return 1
    fi
    return 0
}

# Wait for container to be healthy
wait_for_container() {
    local container=$1
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if [ "$(docker inspect -f '{{.State.Status}}' $container 2>/dev/null)" = "running" ]; then
            log "Container $container is running"
            return 0
        fi
        log "Waiting for container $container to be ready (attempt $attempt/$max_attempts)"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log "ERROR: Container $container failed to start properly"
    docker logs $container
    return 1
}

# Initial setup and packages
log "Starting initial setup..."
apt-get update
apt-get install -y awscli jq apt-transport-https ca-certificates curl gnupg lsb-release htop
log "Installed basic packages"

# Setup status command
cat << 'EOF' > /usr/local/bin/status
#!/bin/bash
clear
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                     SYSTEM STATUS BOARD                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"

# System Info
echo
echo "📊 SYSTEM INFO"
echo "──────────────"
uptime
echo
echo "CPU Usage (top 5 processes):"
ps -eo pcpu,pid,user,args | sort -k 1 -r | head -5
echo
echo "Memory Usage:"
free -h
echo

# Container Status
echo "🐳 DOCKER CONTAINERS"
echo "──────────────────"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo

# Recent Logs
echo "📝 RECENT SYSTEM LOGS"
echo "──────────────────"
tail -n 10 /var/log/user-data.log
echo

# Container Logs
echo "📋 RECENT CONTAINER LOGS"
echo "──────────────────"
for container in redis_service api prometheus iykon-graphana-app react-app renderer; do
    if docker ps -q -f name=$container >/dev/null 2>&1; then
        echo "[$container]"
        docker logs --tail 5 $container 2>&1
        echo
    fi
done

# Help Section
echo "ℹ️  AVAILABLE COMMANDS"
echo "──────────────────"
echo "status                    - Show this dashboard"
echo "docker ps                 - List running containers"
echo "docker logs CONTAINER     - View container logs"
echo "tail -f /var/log/user-data.log   - Follow system logs"
echo
EOF

chmod +x /usr/local/bin/status

# Add status command to profile
echo "alias status='/usr/local/bin/status'" >> /etc/profile.d/iykonect-welcome.sh

# Get instance region from metadata service
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')
log "Detected AWS region: ${AWS_REGION}"

# Fetch secrets from AWS Secrets Manager and create environment file
log "Fetching secrets from AWS Secrets Manager..."
mkdir -p /opt/iykonect/env

# List all available secrets
log "Listing available secrets..."
SECRETS_LIST=$(aws secretsmanager list-secrets --region ${AWS_REGION} --query "SecretList[].Name" --output text)
log "Found secrets: ${SECRETS_LIST}"

# Create a temporary directory for processing
mkdir -p /opt/iykonect/tmp
chmod 700 /opt/iykonect/tmp

# Create the environment file
touch /opt/iykonect/env/app.env
chmod 600 /opt/iykonect/env/app.env

# Iterate through each secret and add its values to the environment file
for FULL_SECRET_NAME in ${SECRETS_LIST}; do
  # Extract variable name (part after the slash)
  if [[ "$FULL_SECRET_NAME" == *"/"* ]]; then
    # Extract everything after the last slash
    SECRET_VAR_NAME=$(echo "$FULL_SECRET_NAME" | rev | cut -d'/' -f1 | rev)
    log "Processing secret: ${FULL_SECRET_NAME} (using variable name: ${SECRET_VAR_NAME})"
  else
    # No slash, use the whole name
    SECRET_VAR_NAME=$FULL_SECRET_NAME
    log "Processing secret: ${FULL_SECRET_NAME}"
  fi
  
  # Get the secret value
  SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id ${FULL_SECRET_NAME} --region ${AWS_REGION} --query SecretString --output text 2>/dev/null)
  
  if [ -n "$SECRET_VALUE" ]; then
    # Check if it's a JSON object
    if echo "$SECRET_VALUE" | jq -e . >/dev/null 2>&1; then
      log "Secret ${FULL_SECRET_NAME} is in JSON format, extracting key-value pairs"
      # Create a separate file for this secret to avoid issues with newlines and special characters
      SECRET_FILE="/opt/iykonect/tmp/${SECRET_VAR_NAME}.json"
      echo "$SECRET_VALUE" > "$SECRET_FILE"
      
      # Process each line of the JSON by flattening it first
      jq -r 'paths(scalars) as $p | [$p | join("_"), getpath($p) | tostring] | join("=")' "$SECRET_FILE" | while read -r line; do
        KEY=$(echo "$line" | cut -d'=' -f1)
        VALUE=$(echo "$line" | cut -d'=' -f2-)
        echo "${KEY}=\"${VALUE}\"" >> /opt/iykonect/env/app.env
      done
    else
      # Not JSON, treat as simple string, use the extracted variable name
      # Quote the value to handle special characters
      log "Secret ${FULL_SECRET_NAME} is a simple string, adding as ${SECRET_VAR_NAME}=<value>"
      echo "${SECRET_VAR_NAME}=\"${SECRET_VALUE}\"" >> /opt/iykonect/env/app.env
    fi
    log "Added secret ${FULL_SECRET_NAME} to environment file"
  else
    log "WARNING: Could not fetch secret ${FULL_SECRET_NAME}"
  fi
done

# Clean up temporary files
rm -rf /opt/iykonect/tmp

# If environment file is empty, add default values
if [ ! -s /opt/iykonect/env/app.env ]; then
  log "WARNING: No secrets found or could be parsed, using default values"
  cat << EOF > /opt/iykonect/env/app.env
DB_USERNAME="default_user"
DB_PASSWORD="default_password"
API_KEY="default_api_key"
JWT_SECRET="default_jwt_secret"
REDIS_PASSWORD="IYKONECTpassword"
EOF
fi

# Remove duplicate entries (keeping the last occurrence)
if [ -s /opt/iykonect/env/app.env ]; then
  log "Removing duplicate entries from environment file..."
  cat /opt/iykonect/env/app.env | awk -F '=' '!seen[$1]++' | tac > /opt/iykonect/env/app.env.tmp
  tac /opt/iykonect/env/app.env.tmp > /opt/iykonect/env/app.env
  rm /opt/iykonect/env/app.env.tmp
fi

log "Final environment file created at /opt/iykonect/env/app.env with $(wc -l < /opt/iykonect/env/app.env) variables"

# Verify AWS Configuration first
log "Verifying AWS configuration..."
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log "ERROR: AWS credentials validation failed"
    exit 1
fi
log "AWS credentials verified successfully"

# Verify S3 access
log "Verifying S3 bucket access..."
if ! aws s3 ls s3://iykonect-aws-parallel/ > /dev/null 2>&1; then
    log "ERROR: S3 bucket access verification failed"
    exit 1
fi
log "S3 bucket access verified successfully"

# Verify ECR access
log "Verifying ECR permissions..."
if ! aws ecr list-images --repository-name iykonect-images --region ${AWS_REGION} --output table > /dev/null 2>&1; then
    log "ERROR: ECR access verification failed"
    exit 1
fi
log "ECR permissions verified successfully"

# Install Docker
log "Installing Docker..."
apt-get remove docker docker-engine docker.io containerd runc || true
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Configure system settings
cat << EOF | tee -a /etc/sysctl.conf
fs.inotify.max_user_watches = 524288
EOF
sysctl -p

# Install Docker packages
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io
systemctl enable docker
systemctl start docker

# Docker setup
log "Setting up Docker environment..."
docker system prune -af
docker network create app-network || true
log "Docker environment ready"

# Login to ECR
log "Logging into ECR..."
LOGIN_OUTPUT=$(aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin 571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com 2>&1)
log "ECR login output: ${LOGIN_OUTPUT}"

# Install system utilities for monitoring
log "Installing system utilities..."
apt-get install -y lsof net-tools
log "System utilities installed"

# Deploy containers in order of dependencies
log "Starting container deployments"

# 1. API
if ! check_port 8000; then
    log "ERROR: Port 8000 is not available for API"
    exit 1
fi
log "Deploying API..."
docker run -d --network app-network --restart always --name api -p 8000:80 \
    --env-file /opt/iykonect/env/app.env \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:api-latest
wait_for_container api || exit 1
log "API container status: $(docker inspect -f '{{.State.Status}}' api)"

# 2. React App (frontend)
if ! check_port 3000; then
    log "ERROR: Port 3000 is not available for React App"
    exit 1
fi
log "Deploying React App..."
# Add the API_ENDPOINT to the env file dynamically
echo "API_ENDPOINT=http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8000" >> /opt/iykonect/env/app.env
docker run -d --network app-network --restart always --name react-app -p 3000:3000 \
    --env-file /opt/iykonect/env/app.env \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:web-latest
wait_for_container react-app || exit 1
log "React App container status: $(docker inspect -f '{{.State.Status}}' react-app)"

# Verify active containers only
log "=== Final Deployment Status ==="
log "Network Status: $(docker network inspect app-network -f '{{.Name}} is {{.Driver}}')"

# Log open ports first
log "Open Ports Summary:"
netstat -tulpn | grep LISTEN | while read line; do
    log "$line"
done

# Log container status after ports
log "Container Status Summary:"
log "$(docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}')"
docker ps --format "{{.Names}}: {{.Status}}" | while read line; do 
    log "$line"
done

# Log resource usage
log "Resource Usage Summary:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | while read line; do
    log "$line"
done

log "=== END Final Status ==="
log "END - user data execution"