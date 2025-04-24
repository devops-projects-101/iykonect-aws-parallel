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
apt-get install -y awscli jq apt-transport-https ca-certificates curl gnupg lsb-release htop collectd
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
#for container in redis_service api prometheus iykon-graphana-app react-app renderer; 
for container in api react-app; do
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
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
log "Detected AWS region: ${AWS_REGION}, Instance ID: ${INSTANCE_ID}"

# Install CloudWatch agent
log "Installing CloudWatch agent..."
wget https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb
rm ./amazon-cloudwatch-agent.deb

# Configure CloudWatch agent
log "Configuring CloudWatch agent..."
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat << 'EOF' > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
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
          },
          {
            "file_path": "/var/log/docker.log",
            "log_group_name": "iykonect-docker-logs",
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
        "resources": [
          "*"
        ],
        "measurement": [
          "usage_active",
          "usage_system",
          "usage_user",
          "usage_idle"
        ],
        "metrics_collection_interval": 60
      },
      "mem": {
        "measurement": [
          "used_percent",
          "used",
          "total"
        ],
        "metrics_collection_interval": 60
      },
      "swap": {
        "measurement": [
          "used",
          "free",
          "used_percent"
        ]
      },
      "disk": {
        "resources": [
          "/"
        ],
        "measurement": [
          "used_percent",
          "inodes_used_percent",
          "used",
          "total"
        ],
        "metrics_collection_interval": 60
      },
      "diskio": {
        "resources": [
          "*"
        ],
        "measurement": [
          "reads",
          "writes",
          "read_bytes",
          "write_bytes"
        ],
        "metrics_collection_interval": 60
      },
      "net": {
        "resources": [
          "*"
        ],
        "measurement": [
          "bytes_sent",
          "bytes_recv",
          "packets_sent",
          "packets_recv"
        ],
        "metrics_collection_interval": 60
      },
      "processes": {
        "measurement": [
          "running",
          "blocked",
          "zombie"
        ]
      },
      "docker": {
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

# Create CloudWatch Dashboard
log "Creating CloudWatch dashboard..."
DASHBOARD_NAME="IYKonect-Dashboard-${INSTANCE_ID}"
DASHBOARD_BODY=$(cat << EOF
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
          ["...", "cpu_usage_system", ".", ".", {"stat": "Average"}],
          ["...", "cpu_usage_user", ".", ".", {"stat": "Average"}]
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
        "region": "${AWS_REGION}",
        "view": "timeSeries",
        "stacked": false,
        "yAxis": {
          "left": {
            "min": 0,
            "max": 100
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 6,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          ["IYKonect/EC2", "disk_used_percent", "host", "${INSTANCE_ID}", "path", "/", {"stat": "Average"}]
        ],
        "period": 60,
        "title": "Disk Usage",
        "region": "${AWS_REGION}",
        "view": "timeSeries",
        "stacked": false,
        "yAxis": {
          "left": {
            "min": 0,
            "max": 100
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 6,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          ["IYKonect/EC2", "net_bytes_sent", "host", "${INSTANCE_ID}", "interface", "eth0", {"stat": "Sum"}],
          ["...", "net_bytes_recv", ".", ".", ".", ".", {"stat": "Sum"}]
        ],
        "period": 60,
        "title": "Network Traffic",
        "region": "${AWS_REGION}",
        "view": "timeSeries",
        "stacked": false
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 12,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          ["IYKonect/EC2", "container_cpu_usage_percent", "host", "${INSTANCE_ID}", "container_name", "api", {"stat": "Average"}],
          ["...", ".", ".", ".", ".", "react-app", {"stat": "Average"}]
        ],
        "period": 60,
        "title": "Container CPU Usage",
        "region": "${AWS_REGION}",
        "view": "timeSeries",
        "stacked": false
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 12,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          ["IYKonect/EC2", "container_memory_usage_percent", "host", "${INSTANCE_ID}", "container_name", "api", {"stat": "Average"}],
          ["...", ".", ".", ".", ".", "react-app", {"stat": "Average"}]
        ],
        "period": 60,
        "title": "Container Memory Usage",
        "region": "${AWS_REGION}",
        "view": "timeSeries",
        "stacked": false,
        "yAxis": {
          "left": {
            "min": 0,
            "max": 100
          }
        }
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 18,
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE 'iykonect-user-data-logs' | fields @timestamp, @message\n| sort @timestamp desc\n| limit 100",
        "region": "${AWS_REGION}",
        "title": "User Data Logs",
        "view": "table"
      }
    }
  ]
}
EOF
)

# Start CloudWatch agent
log "Starting CloudWatch agent..."
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Create CloudWatch Dashboard using AWS CLI
log "Creating CloudWatch Dashboard using AWS CLI..."
aws cloudwatch put-dashboard --dashboard-name "${DASHBOARD_NAME}" --dashboard-body "${DASHBOARD_BODY}" --region ${AWS_REGION}
log "CloudWatch Dashboard URL: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"

# Fetch secrets from AWS Secrets Manager and create environment files
log "Fetching secrets from AWS Secrets Manager..."
mkdir -p /opt/iykonect/env
mkdir -p /opt/iykonect/config

# List all available secrets
log "Listing available secrets..."
SECRETS_LIST=$(aws secretsmanager list-secrets --region ${AWS_REGION} --query "SecretList[].Name" --output text)
log "Found secrets: ${SECRETS_LIST}"

# Create a clean env file (simple key=value pairs only)
touch /opt/iykonect/env/app.env
chmod 600 /opt/iykonect/env/app.env

# Create JSON config directory
mkdir -p /opt/iykonect/config
echo "{}" > /opt/iykonect/config/app.json
chmod 600 /opt/iykonect/config/app.json

# Process each secret separately
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
  
  # Skip explicitly excluded secrets
  if [[ "$SECRET_VAR_NAME" == "QA" || "$SECRET_VAR_NAME" == "Production" ]]; then
    log "Skipping excluded secret: ${FULL_SECRET_NAME} (${SECRET_VAR_NAME})"
    continue
  fi
  
  # Get the secret value
  SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id ${FULL_SECRET_NAME} --region ${AWS_REGION} --query SecretString --output text 2>/dev/null)
  
  if [ -n "$SECRET_VALUE" ]; then
    # Check if the secret is in JSON format
    if echo "$SECRET_VALUE" | jq -e . >/dev/null 2>&1; then
      log "Secret ${FULL_SECRET_NAME} is in JSON format, adding to config directory"
      
      # Save the JSON object to its own config file
      echo "$SECRET_VALUE" > "/opt/iykonect/config/${SECRET_VAR_NAME}.json"
      
      # Also merge into the main config file
      jq -s '.[0] * .[1]' /opt/iykonect/config/app.json <(echo "$SECRET_VALUE") > /opt/iykonect/config/app.json.tmp
      mv /opt/iykonect/config/app.json.tmp /opt/iykonect/config/app.json

      # For JSON objects, we don't add them to the env file
    else
      # Check if it's an SSL key (contains BEGIN and PRIVATE KEY or CERTIFICATE)
      if [[ "$SECRET_VALUE" == *"BEGIN"* && ("$SECRET_VALUE" == *"PRIVATE KEY"* || "$SECRET_VALUE" == *"CERTIFICATE"*) ]]; then
        log "Secret ${FULL_SECRET_NAME} is an SSL key, saving to config file"
        echo "$SECRET_VALUE" > "/opt/iykonect/config/${SECRET_VAR_NAME}.pem"
        chmod 600 "/opt/iykonect/config/${SECRET_VAR_NAME}.pem"
      else
        # Simple string value - safe to add to env file
        log "Secret ${FULL_SECRET_NAME} is a simple key=value, adding to env file"
        echo "${SECRET_VAR_NAME}=${SECRET_VALUE}" >> /opt/iykonect/env/app.env
      fi
    fi
    log "Processed secret ${FULL_SECRET_NAME}"
  else
    log "WARNING: Could not fetch secret ${FULL_SECRET_NAME}"
  fi
done

# Add default values if the env file is empty
if [ ! -s /opt/iykonect/env/app.env ]; then
  log "WARNING: No simple secrets found, using default values"
  cat << EOF > /opt/iykonect/env/app.env
DB_USERNAME=default_user
DB_PASSWORD=default_password
API_KEY=default_api_key
JWT_SECRET=default_jwt_secret
REDIS_PASSWORD=IYKONECTpassword
EOF
fi

# Add the API_ENDPOINT to the env file dynamically
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "API_ENDPOINT=http://${PUBLIC_IP}:8000" >> /opt/iykonect/env/app.env

# Remove duplicate entries from env file
if [ -s /opt/iykonect/env/app.env ]; then
  log "Removing duplicate entries from environment file..."
  awk -F '=' '!seen[$1]++' /opt/iykonect/env/app.env > /opt/iykonect/env/app.env.tmp
  mv /opt/iykonect/env/app.env.tmp /opt/iykonect/env/app.env
fi

# Final report on processed files
log "Final environment file created at /opt/iykonect/env/app.env with $(wc -l < /opt/iykonect/env/app.env) variables"
log "Config files created in /opt/iykonect/config/ with $(find /opt/iykonect/config/ -type f | wc -l) files"

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

# Function to run docker command and capture output
run_docker() {
  local command="$1"
  local container_name="$2"
  
  log "Running docker command: $command"
  
  # Execute command and capture output
  local output
  output=$(eval "$command" 2>&1) || {
    local exit_code=$?
    log "ERROR: Docker command failed with exit code $exit_code"
    log "ERROR OUTPUT: $output"
    return $exit_code
  }
  
  # Log successful output
  log "Docker command executed successfully"
  log "OUTPUT: $output"
  
  # Wait for container to be ready
  wait_for_container "$container_name" || {
    log "ERROR: Container $container_name failed to start properly"
    log "Container logs:"
    docker logs "$container_name" 2>&1 | while read -r line; do
      log "[$container_name] $line"
    done
    return 1
  }
  
  log "Container $container_name is running successfully"
  return 0
}

# 1. API
if ! check_port 8000; then
    log "ERROR: Port 8000 is not available for API"
    exit 1
fi
log "Deploying API..."
run_docker "docker run -d --network app-network --restart always --name api -p 8000:80 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:api-latest" "api" || {
    log "FATAL: Failed to deploy API container"
    exit 1
}
log "API container status: $(docker inspect -f '{{.State.Status}}' api)"

# 2. React App (frontend)
if ! check_port 3000; then
    log "ERROR: Port 3000 is not available for React App"
    exit 1
fi
log "Deploying React App..."
run_docker "docker run -d --network app-network --restart always --name react-app -p 3000:3000 \
    --env-file /opt/iykonect/env/app.env \
    -v /opt/iykonect/config:/app/config \
    571664317480.dkr.ecr.${AWS_REGION}.amazonaws.com/iykonect-images:web-latest" "react-app" || {
    log "FATAL: Failed to deploy React App container"
    exit 1
}
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