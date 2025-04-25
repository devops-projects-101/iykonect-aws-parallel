#!/bin/bash

# Ensure script runs as root
if [ "$(id -u)" != "0" ]; then
   exec sudo "$0" "$@"
fi

set -e

# Logging function
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
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
        log "Waiting for container $container (attempt $attempt/$max_attempts)"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log "ERROR: Container $container failed to start properly"
    docker logs $container
    return 1
}

# Initial setup
log "Starting initial setup..."
apt-get update && apt-get install -y awscli jq apt-transport-https ca-certificates curl gnupg lsb-release htop collectd
log "Package installation completed"

# Get instance metadata
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
log "Instance info: Region=${AWS_REGION}, ID=${INSTANCE_ID}, IP=${PUBLIC_IP}"

# Setup status command
cat << 'EOF' > /usr/local/bin/status
#!/bin/bash
clear
echo "╔══════════════════════════════════════════════════╗"
echo "║               SYSTEM STATUS BOARD                ║"
echo "╚══════════════════════════════════════════════════╝"
echo
echo "📊 SYSTEM INFO"
echo "──────────────"
uptime
echo "CPU Usage (top 5 processes):"
ps -eo pcpu,pid,user,args | sort -k 1 -r | head -5
echo "Memory Usage:"
free -h
echo
echo "🐳 DOCKER CONTAINERS"
echo "──────────────"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo
echo "📝 RECENT LOGS"
echo "──────────────"
tail -n 10 /var/log/user-data.log
EOF

chmod +x /usr/local/bin/status
echo "alias status='/usr/local/bin/status'" >> /etc/profile.d/iykonect-welcome.sh

# Install CloudWatch agent
log "==============================================="
log "Starting CloudWatch agent installation process"
log "==============================================="
wget -q https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/amazon-cloudwatch-agent.deb
dpkg -i -E /tmp/amazon-cloudwatch-agent.deb
rm /tmp/amazon-cloudwatch-agent.deb
log "CloudWatch agent package installation completed"

# Configure CloudWatch agent
log "Configuring CloudWatch agent..."
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "iykonect-user-data-logs",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "iykonect-system-logs",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "IYKonect/EC2",
    "metrics_collected": {
      "cpu": {
        "resources": ["*"],
        "measurement": ["usage_active", "usage_system", "usage_user"]
      },
      "mem": {
        "measurement": ["used_percent", "used", "total"]
      },
      "disk": {
        "resources": ["/"],
        "measurement": ["used_percent", "used"]
      },
      "net": {
        "resources": ["*"],
        "measurement": ["bytes_sent", "bytes_recv"]
      },
      "docker": {
        "resources": ["*"],
        "metrics_collection_interval": 60,
        "measurement": [
          "container_cpu_usage_percent",
          "container_memory_usage_percent",
          "container_memory_usage",
          "network_io_usage"
        ]
      }
    }
  }
}
EOF
log "CloudWatch agent configuration file created"

# Start CloudWatch agent with detailed logging
log "==============================================="
log "Starting CloudWatch agent service"
log "==============================================="
log "Running agent control command to fetch config..."
CW_OUTPUT=$(/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json 2>&1)
log "CloudWatch agent control command output:"
echo "$CW_OUTPUT" | while read -r line; do
  log "CW-AGENT: $line"
done

# Enable and start service
log "Enabling CloudWatch agent service..."
systemctl enable amazon-cloudwatch-agent
log "Starting CloudWatch agent service..."
systemctl start amazon-cloudwatch-agent

# Verify CloudWatch agent status
CW_STATUS=$(systemctl status amazon-cloudwatch-agent | grep "Active:" | awk '{print $2}')
if [ "$CW_STATUS" = "active" ]; then
  log "CloudWatch agent service started successfully (status: $CW_STATUS)"
else
  log "WARNING: CloudWatch agent may not have started correctly (status: $CW_STATUS)"
  log "Checking CloudWatch agent logs:"
  tail -n 20 /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log | while read -r line; do
    log "CW-LOG: $line"
  done
fi
log "==============================================="
log "CloudWatch agent setup completed"
log "==============================================="

# Create CloudWatch Dashboard
log "Creating CloudWatch dashboard..."
DASHBOARD_NAME="IYKonect-Dashboard-${INSTANCE_ID}"

# Create dashboard using a template
cat > /tmp/dashboard.json << EOF
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          ["IYKonect/EC2", "cpu_usage_active", "host", "${INSTANCE_ID}", {"stat": "Average"}],
          ["...", "cpu_usage_system", ".", ".", {"stat": "Average"}]
        ],
        "period": 60,
        "title": "CPU Usage",
        "region": "${AWS_REGION}",
        "view": "timeSeries",
        "stacked": false
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          ["IYKonect/EC2", "mem_used_percent", "host", "${INSTANCE_ID}", {"stat": "Average"}]
        ],
        "period": 60,
        "title": "Memory Usage",
        "region": "${AWS_REGION}"
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 18,
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE 'iykonect-user-data-logs' | fields @timestamp, @message | sort @timestamp desc | limit 100",
        "region": "${AWS_REGION}",
        "title": "User Data Logs"
      }
    }
  ]
}
EOF

aws cloudwatch put-dashboard --dashboard-name "${DASHBOARD_NAME}" --dashboard-body file:///tmp/dashboard.json --region ${AWS_REGION}

# Fetch secrets from AWS Secrets Manager
log "Fetching secrets from AWS Secrets Manager..."
mkdir -p /opt/iykonect/env
mkdir -p /opt/iykonect/config
touch /opt/iykonect/env/app.env
chmod 600 /opt/iykonect/env/app.env

# Create list of variables to be explicitly defined in the script (not extracted from secrets)
log "Setting up list of variables to be explicitly defined in the script"
declare -a EXPLICIT_VARS=("API_ENDPOINT" "REACT_APP_BASE_URL" "AppSettings__DomainBaseUrl")

# Get list of secrets
SECRETS_LIST=$(aws secretsmanager list-secrets --region ${AWS_REGION} --query "SecretList[].Name" --output text)
log "Found secrets: ${SECRETS_LIST}"

# Process each secret
for FULL_SECRET_NAME in ${SECRETS_LIST}; do
  # Extract variable name (after slash)
  if [[ "$FULL_SECRET_NAME" == *"/"* ]]; then
    SECRET_VAR_NAME=$(echo "$FULL_SECRET_NAME" | rev | cut -d'/' -f1 | rev)
  else
    SECRET_VAR_NAME=$FULL_SECRET_NAME
  fi
  
  # Skip excluded secrets
  if [[ "$SECRET_VAR_NAME" == "QA" || "$SECRET_VAR_NAME" == "Production" ]]; then
    continue
  fi
  
  # Skip variables that will be explicitly defined
  if [[ " ${EXPLICIT_VARS[@]} " =~ " ${SECRET_VAR_NAME} " ]]; then
    log "Skipping secret ${FULL_SECRET_NAME} as it will be explicitly defined"
    continue
  fi
  
  # Get the secret value
  SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id ${FULL_SECRET_NAME} \
    --region ${AWS_REGION} --query SecretString --output text 2>/dev/null)
  
  if [ -n "$SECRET_VALUE" ]; then
    # Check if JSON
    if echo "$SECRET_VALUE" | jq -e . >/dev/null 2>&1; then
      echo "$SECRET_VALUE" > "/opt/iykonect/config/${SECRET_VAR_NAME}.json"
      jq -s '.[0] * .[1]' /opt/iykonect/config/app.json <(echo "$SECRET_VALUE") > /tmp/merged.json
      mv /tmp/merged.json /opt/iykonect/config/app.json
    # Check if SSL key
    elif [[ "$SECRET_VALUE" == *"BEGIN"* && ("$SECRET_VALUE" == *"PRIVATE KEY"* || "$SECRET_VALUE" == *"CERTIFICATE"*) ]]; then
      echo "$SECRET_VALUE" > "/opt/iykonect/config/${SECRET_VAR_NAME}.pem"
      chmod 600 "/opt/iykonect/config/${SECRET_VAR_NAME}.pem"
    else
      # Simple string
      echo "${SECRET_VAR_NAME}=${SECRET_VALUE}" >> /opt/iykonect/env/app.env
    fi
  fi
done

# Explicitly define required environment variables
log "Explicitly defining required environment variables"
echo "API_ENDPOINT=http://${PUBLIC_IP}:8000" >> /opt/iykonect/env/app.env
echo "REACT_APP_BASE_URL=http://${PUBLIC_IP}:8000" >> /opt/iykonect/env/app.env
echo "AppSettings__DomainBaseUrl=http://${PUBLIC_IP}:3000" >> /opt/iykonect/env/app.env

# Remove duplicate entries (ensuring our explicit definitions take precedence)
log "Removing duplicate entries from environment file (explicit definitions take precedence)"
awk -F '=' '!seen[$1]++' /opt/iykonect/env/app.env > /tmp/env.tmp && mv /tmp/env.tmp /opt/iykonect/env/app.env

# Install Docker
log "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

# System settings
echo "fs.inotify.max_user_watches = 524288" >> /etc/sysctl.conf
sysctl -p

# Install Docker packages
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io
systemctl enable docker
systemctl start docker

# Docker setup
docker system prune -af
docker network create app-network || true

# Login to ECR
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
if ! check_port 8000; then
    log "ERROR: Port 8000 is not available"
    exit 1
fi
log "Deploying API..."
run_docker "docker run -d --network app-network --restart always --name api -p 8000:80 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:api-latest" "api" || exit 1

# Deploy React App
if ! check_port 3000; then
    log "ERROR: Port 3000 is not available"
    exit 1
fi
log "Deploying React App..."
run_docker "docker run -d --network app-network --restart always --name react-app -p 3000:3000 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:web-latest" "react-app" || exit 1

# Final status
log "=== Deployment Complete ==="
log "API URL: http://${PUBLIC_IP}:8000"
log "Web URL: http://${PUBLIC_IP}:3000"
log "Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"