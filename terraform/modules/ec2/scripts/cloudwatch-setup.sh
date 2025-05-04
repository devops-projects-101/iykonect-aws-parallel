#!/bin/bash

# Function for logging
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
}

# Get instance metadata
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

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
log "CloudWatch dashboard created: ${DASHBOARD_NAME}"

# Final status
log "=== CloudWatch Setup Complete ==="
log "Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=IYKonect-Dashboard-${INSTANCE_ID}"