#!/bin/bash

# Enhanced Azure Monitor setup script with dashboard for user-data.log visualization

set -e

# Logging function
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/azure-monitor-setup.log
}

log "Starting enhanced Azure Monitor setup..."

# Get instance metadata for Azure
VM_NAME=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text")
RESOURCE_GROUP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text")
SUBSCRIPTION_ID=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/subscriptionId?api-version=2021-02-01&format=text")
LOCATION=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")

log "VM Information:"
log "Name: $VM_NAME"
log "Resource Group: $RESOURCE_GROUP"
log "Subscription ID: $SUBSCRIPTION_ID"
log "Location: $LOCATION"

# Install Azure Monitor agent
log "Installing Azure Monitor agent..."
curl -sL https://aka.ms/InstallAzureMonitorLinuxAgent | sudo bash

# Configure Azure Monitor to collect Docker metrics
log "Configuring Azure Monitor to collect Docker metrics..."
mkdir -p /etc/azuremonitoragent/config.d/

cat > /etc/azuremonitoragent/config.d/docker.toml << 'EOF'
# Azure Monitor agent configuration for Docker
[inputs.docker]
  endpoint = "unix:///var/run/docker.sock"
  gather_services = false
  container_names = []
  container_name_include = []
  container_name_exclude = []
  timeout = "5s"
  perdevice = true
  total = false
EOF

# Configure log collection including user-data.log
log "Configuring log collection for user-data.log..."
cat > /etc/azuremonitoragent/config.d/logs.toml << 'EOF'
# Azure Monitor log collection configuration
[[inputs.tail]]
  files = ["/var/log/user-data.log"]
  data_format = "syslog"
  name_override = "user_data_logs"
  from_beginning = true
  
[[inputs.tail]]
  files = ["/var/log/syslog"]
  data_format = "syslog"
  name_override = "system_logs"
  from_beginning = true
  
[[inputs.tail]]
  files = ["/var/log/docker.log"]
  data_format = "syslog"
  name_override = "docker_logs"
  from_beginning = true
EOF

# Configure Azure CLI for local dashboard creation
log "Configuring Azure CLI for dashboard creation..."
az login --identity

# Create a Grafana dashboard for log visualization
log "Setting up Grafana dashboard for log visualization..."
mkdir -p /opt/iykonect/grafana/provisioning/dashboards

# Create a dashboard definition file
cat > /opt/iykonect/grafana/provisioning/dashboards/iykonect-dashboard.json << 'EOF'
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": "-- Grafana --",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts",
        "type": "dashboard"
      }
    ]
  },
  "editable": true,
  "gnetId": null,
  "graphTooltip": 0,
  "id": 1,
  "links": [],
  "panels": [
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "fill": 1,
      "fillGradient": 0,
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 0,
        "y": 0
      },
      "hiddenSeries": false,
      "id": 2,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "nullPointMode": "null",
      "options": {
        "alertThreshold": true
      },
      "percentage": false,
      "pluginVersion": "7.4.0",
      "pointradius": 2,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "rate(node_cpu_seconds_total{mode=\"user\"}[1m])",
          "interval": "",
          "legendFormat": "CPU Usage",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "CPU Usage",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "fill": 1,
      "fillGradient": 0,
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 12,
        "y": 0
      },
      "hiddenSeries": false,
      "id": 4,
      "legend": {
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "nullPointMode": "null",
      "options": {
        "alertThreshold": true
      },
      "percentage": false,
      "pluginVersion": "7.4.0",
      "pointradius": 2,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "node_memory_MemTotal_bytes - node_memory_MemFree_bytes - node_memory_Buffers_bytes - node_memory_Cached_bytes",
          "interval": "",
          "legendFormat": "Memory Usage",
          "refId": "A"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "Memory Usage",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "bytes",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "datasource": "Loki",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "gridPos": {
        "h": 15,
        "w": 24,
        "x": 0,
        "y": 8
      },
      "id": 6,
      "options": {
        "showLabels": false,
        "showTime": true,
        "sortOrder": "Descending",
        "wrapLogMessage": true
      },
      "pluginVersion": "7.4.0",
      "targets": [
        {
          "expr": "{filename=\"/var/log/user-data.log\"}",
          "refId": "A"
        }
      ],
      "timeFrom": null,
      "timeShift": null,
      "title": "User Data Logs",
      "type": "logs"
    }
  ],
  "refresh": "10s",
  "schemaVersion": 27,
  "style": "dark",
  "tags": [],
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-6h",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "",
  "title": "IYKonect Azure Dashboard",
  "uid": "iykonect-azure",
  "version": 1
}
EOF

# Configure Grafana to load the dashboard
mkdir -p /opt/iykonect/grafana/provisioning/datasources

cat > /opt/iykonect/grafana/provisioning/datasources/datasources.yaml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    jsonData:
      maxLines: 1000
EOF

# Add a Grafana dashboard provisioning configuration
mkdir -p /opt/iykonect/grafana/provisioning/dashboards
cat > /opt/iykonect/grafana/provisioning/dashboards/dashboards.yaml << 'EOF'
apiVersion: 1

providers:
  - name: 'IYKonect'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    options:
      path: /var/lib/grafana/provisioning/dashboards
EOF

# Setup a Loki container for log aggregation
log "Setting up Loki for log aggregation..."
cat > /opt/iykonect/loki-config.yaml << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2020-01-01
      store: boltdb
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 168h

storage_config:
  boltdb:
    directory: /tmp/loki/index
  filesystem:
    directory: /tmp/loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s
EOF

# Create a script to setup promtail for log forwarding
log "Creating promtail setup script..."
cat > /opt/iykonect/setup-promtail.sh << 'EOF'
#!/bin/bash
set -e

# Download and configure promtail
wget -q -O /tmp/promtail.zip "https://github.com/grafana/loki/releases/download/v2.3.0/promtail-linux-amd64.zip"
unzip -q /tmp/promtail.zip -d /tmp
mv /tmp/promtail-linux-amd64 /usr/local/bin/promtail
chmod +x /usr/local/bin/promtail

# Configure promtail
mkdir -p /etc/promtail
cat > /etc/promtail/config.yaml << 'EOP'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
    - targets:
        - localhost
      labels:
        job: varlogs
        __path__: /var/log/*log
EOP

# Create systemd service for promtail
cat > /etc/systemd/system/promtail.service << 'EOP'
[Unit]
Description=Promtail service for sending logs to Loki
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/config.yaml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOP

# Start promtail service
systemctl daemon-reload
systemctl enable promtail
systemctl start promtail
EOF

chmod +x /opt/iykonect/setup-promtail.sh

# Run promtail setup
log "Running promtail setup..."
/opt/iykonect/setup-promtail.sh

# Restart the Azure Monitor agent to apply changes
log "Restarting Azure Monitor agent..."
systemctl restart azuremonitoragent

# Create a service for tailing user-data.log to the dashboard
log "Setting up user-data.log streaming service..."
cat > /etc/systemd/system/log-stream.service << 'EOF'
[Unit]
Description=Stream user-data.log to dashboard
After=docker.service

[Service]
Type=simple
ExecStart=/bin/bash -c "tail -f /var/log/user-data.log | tee -a /opt/iykonect/logs/user-data-stream.log"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create log directory
mkdir -p /opt/iykonect/logs

# Enable and start the service
systemctl daemon-reload
systemctl enable log-stream
systemctl start log-stream

log "Creating Azure Log Analytics integration..."
# Create an Azure CLI script to setup Log Analytics
cat > /opt/iykonect/setup-log-analytics.sh << 'EOF'
#!/bin/bash

# Extract Azure instance metadata
RESOURCE_GROUP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text")
VM_NAME=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text")
LOCATION=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")

# Create Log Analytics workspace if it doesn't exist
WORKSPACE_NAME="iykonect-logs-$RESOURCE_GROUP"
az monitor log-analytics workspace create \
  --resource-group $RESOURCE_GROUP \
  --workspace-name $WORKSPACE_NAME \
  --location $LOCATION

# Get the workspace ID
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group $RESOURCE_GROUP \
  --workspace-name $WORKSPACE_NAME \
  --query customerId -o tsv)

# Get the workspace key
WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
  --resource-group $RESOURCE_GROUP \
  --workspace-name $WORKSPACE_NAME \
  --query primarySharedKey -o tsv)

# Configure the VM to send logs to Log Analytics
az vm extension set \
  --resource-group $RESOURCE_GROUP \
  --vm-name $VM_NAME \
  --name OmsAgentForLinux \
  --publisher Microsoft.EnterpriseCloud.Monitoring \
  --settings "{\"workspaceId\": \"$WORKSPACE_ID\"}" \
  --protected-settings "{\"workspaceKey\": \"$WORKSPACE_KEY\"}"

# Create a custom dashboard for the VM
az portal dashboard create \
  --resource-group $RESOURCE_GROUP \
  --name "IYKonect-Dashboard-$VM_NAME" \
  --location $LOCATION \
  --input-path /opt/iykonect/azure-dashboard.json
EOF

# Create an Azure dashboard template
cat > /opt/iykonect/azure-dashboard.json << 'EOF'
{
  "properties": {
    "lenses": {
      "0": {
        "order": 0,
        "parts": {
          "0": {
            "position": {
              "x": 0,
              "y": 0,
              "colSpan": 6,
              "rowSpan": 4
            },
            "metadata": {
              "inputs": [],
              "type": "Extension/Microsoft_Azure_Monitoring/PartType/LogsBlade",
              "settings": {
                "content": {
                  "Query": "// User Data Logs\n// This query retrieves the most recent user-data.log entries\nSearch in (heartbeat)\n| where Computer == \"{{vmName}}\"\n| where OSType == \"Linux\"\n| extend LogData = parse_json(tostring(parse_json(tostring(iff(isnotempty(todynamic(tostring(iff(isnotempty(tostring(todynamic(tostring(iff(isnotempty(todynamic(tostring(iff(isnotempty(HostCustomFields), HostCustomFields, \"\"))))), todynamic(tostring(iff(isnotempty(HostCustomFields), HostCustomFields, \"\"))), \"\")))), todynamic(tostring(iff(isnotempty(todynamic(tostring(iff(isnotempty(HostCustomFields), HostCustomFields, \"\")))), todynamic(tostring(iff(isnotempty(HostCustomFields), HostCustomFields, \"\"))), \"\"))), \"\"))))), todynamic(tostring(iff(isnotempty(todynamic(tostring(iff(isnotempty(todynamic(tostring(iff(isnotempty(HostCustomFields), HostCustomFields, \"\"))))), todynamic(tostring(iff(isnotempty(HostCustomFields), HostCustomFields, \"\"))), \"\")))), todynamic(tostring(iff(isnotempty(todynamic(tostring(iff(isnotempty(HostCustomFields), HostCustomFields, \"\")))), todynamic(tostring(iff(isnotempty(HostCustomFields), HostCustomFields, \"\"))), \"\"))), \"\"))))))\n| project TimeGenerated, LogData\n| order by TimeGenerated desc\n| take 100",
                  "TimePeriod": {
                    "value": {
                      "relative": {
                        "duration": 24,
                        "timeUnit": 1
                      }
                    }
                  }
                }
              }
            }
          },
          "1": {
            "position": {
              "x": 6,
              "y": 0,
              "colSpan": 6,
              "rowSpan": 4
            },
            "metadata": {
              "inputs": [
                {
                  "name": "options",
                  "value": {
                    "chart": {
                      "metrics": [
                        {
                          "resourceMetadata": {
                            "id": "/subscriptions/{{subscriptionId}}/resourceGroups/{{resourceGroup}}/providers/Microsoft.Compute/virtualMachines/{{vmName}}"
                          },
                          "name": "Percentage CPU",
                          "aggregationType": 4,
                          "namespace": "microsoft.compute/virtualmachines",
                          "metricVisualization": {
                            "displayName": "Percentage CPU",
                            "color": "#00BFFF"
                          }
                        }
                      ],
                      "title": "CPU Utilization",
                      "visualization": {
                        "chartType": 2,
                        "legendVisualization": {
                          "isVisible": true,
                          "position": 2,
                          "hideSubtitle": false
                        },
                        "axisVisualization": {
                          "x": {
                            "isVisible": true,
                            "axisType": 2
                          },
                          "y": {
                            "isVisible": true,
                            "axisType": 1
                          }
                        }
                      }
                    },
                    "timespan": {
                      "relative": {
                        "duration": 24,
                        "timeUnit": 1
                      }
                    }
                  }
                }
              ],
              "type": "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
            }
          },
          "2": {
            "position": {
              "x": 0,
              "y": 4,
              "colSpan": 6,
              "rowSpan": 4
            },
            "metadata": {
              "inputs": [
                {
                  "name": "options",
                  "value": {
                    "chart": {
                      "metrics": [
                        {
                          "resourceMetadata": {
                            "id": "/subscriptions/{{subscriptionId}}/resourceGroups/{{resourceGroup}}/providers/Microsoft.Compute/virtualMachines/{{vmName}}"
                          },
                          "name": "Network In Total",
                          "aggregationType": 1,
                          "namespace": "microsoft.compute/virtualmachines",
                          "metricVisualization": {
                            "displayName": "Network In Total",
                            "color": "#00FF00"
                          }
                        },
                        {
                          "resourceMetadata": {
                            "id": "/subscriptions/{{subscriptionId}}/resourceGroups/{{resourceGroup}}/providers/Microsoft.Compute/virtualMachines/{{vmName}}"
                          },
                          "name": "Network Out Total",
                          "aggregationType": 1,
                          "namespace": "microsoft.compute/virtualmachines",
                          "metricVisualization": {
                            "displayName": "Network Out Total",
                            "color": "#FF0000"
                          }
                        }
                      ],
                      "title": "Network Traffic",
                      "visualization": {
                        "chartType": 2,
                        "legendVisualization": {
                          "isVisible": true,
                          "position": 2,
                          "hideSubtitle": false
                        },
                        "axisVisualization": {
                          "x": {
                            "isVisible": true,
                            "axisType": 2
                          },
                          "y": {
                            "isVisible": true,
                            "axisType": 1
                          }
                        }
                      }
                    },
                    "timespan": {
                      "relative": {
                        "duration": 24,
                        "timeUnit": 1
                      }
                    }
                  }
                }
              ],
              "type": "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
            }
          },
          "3": {
            "position": {
              "x": 6,
              "y": 4,
              "colSpan": 6,
              "rowSpan": 4
            },
            "metadata": {
              "inputs": [
                {
                  "name": "options",
                  "value": {
                    "chart": {
                      "metrics": [
                        {
                          "resourceMetadata": {
                            "id": "/subscriptions/{{subscriptionId}}/resourceGroups/{{resourceGroup}}/providers/Microsoft.Compute/virtualMachines/{{vmName}}"
                          },
                          "name": "Disk Read Bytes",
                          "aggregationType": 1,
                          "namespace": "microsoft.compute/virtualmachines",
                          "metricVisualization": {
                            "displayName": "Disk Read Bytes",
                            "color": "#00BFFF"
                          }
                        },
                        {
                          "resourceMetadata": {
                            "id": "/subscriptions/{{subscriptionId}}/resourceGroups/{{resourceGroup}}/providers/Microsoft.Compute/virtualMachines/{{vmName}}"
                          },
                          "name": "Disk Write Bytes",
                          "aggregationType": 1,
                          "namespace": "microsoft.compute/virtualmachines",
                          "metricVisualization": {
                            "displayName": "Disk Write Bytes",
                            "color": "#FF8C00"
                          }
                        }
                      ],
                      "title": "Disk I/O",
                      "visualization": {
                        "chartType": 2,
                        "legendVisualization": {
                          "isVisible": true,
                          "position": 2,
                          "hideSubtitle": false
                        },
                        "axisVisualization": {
                          "x": {
                            "isVisible": true,
                            "axisType": 2
                          },
                          "y": {
                            "isVisible": true,
                            "axisType": 1
                          }
                        }
                      }
                    },
                    "timespan": {
                      "relative": {
                        "duration": 24,
                        "timeUnit": 1
                      }
                    }
                  }
                }
              ],
              "type": "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
            }
          },
          "4": {
            "position": {
              "x": 0,
              "y": 8,
              "colSpan": 12,
              "rowSpan": 4
            },
            "metadata": {
              "inputs": [
                {
                  "name": "options",
                  "value": {
                    "chart": {
                      "metrics": [
                        {
                          "resourceMetadata": {
                            "id": "/subscriptions/{{subscriptionId}}/resourceGroups/{{resourceGroup}}/providers/Microsoft.Compute/virtualMachines/{{vmName}}"
                          },
                          "name": "Available Memory Bytes",
                          "aggregationType": 4,
                          "namespace": "microsoft.compute/virtualmachines",
                          "metricVisualization": {
                            "displayName": "Available Memory",
                            "color": "#8B008B"
                          }
                        }
                      ],
                      "title": "Memory Usage",
                      "visualization": {
                        "chartType": 2,
                        "legendVisualization": {
                          "isVisible": true,
                          "position": 2,
                          "hideSubtitle": false
                        },
                        "axisVisualization": {
                          "x": {
                            "isVisible": true,
                            "axisType": 2
                          },
                          "y": {
                            "isVisible": true,
                            "axisType": 1
                          }
                        }
                      }
                    },
                    "timespan": {
                      "relative": {
                        "duration": 24,
                        "timeUnit": 1
                      }
                    }
                  }
                }
              ],
              "type": "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
            }
          }
        }
      }
    },
    "metadata": {
      "model": {
        "timeRange": {
          "value": {
            "relative": {
              "duration": 24,
              "timeUnit": 1
            }
          },
          "type": "MsPortalFx.Composition.Configuration.ValueTypes.TimeRange"
        },
        "filters": {
          "value": {
            "MsPortalFx_TimeRange": {
              "model": {
                "format": "utc",
                "granularity": "auto",
                "relative": "24h"
              },
              "displayCache": {
                "name": "UTC Time",
                "value": "Past 24 hours"
              }
            }
          }
        }
      }
    }
  },
  "name": "IYKonect Azure Dashboard",
  "type": "Microsoft.Portal/dashboards"
}
EOF

# Make script executable
chmod +x /opt/iykonect/setup-log-analytics.sh

# Run the Log Analytics setup
log "Running Log Analytics and dashboard setup..."
/opt/iykonect/setup-log-analytics.sh

# Create the custom dashboard access link
VM_NAME=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text")
RESOURCE_GROUP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text")

# Create a shortcut for viewing logs
cat > /usr/local/bin/logs-dashboard << 'EOF'
#!/bin/bash
echo "=============================================="
echo "    IYKonect Azure Dashboard Access URLs     "
echo "=============================================="
echo ""
echo "Grafana Dashboard (local):"
echo "http://localhost:3100"
echo ""
echo "Azure Portal Dashboard:"
VM_NAME=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text")
RESOURCE_GROUP=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text")
SUBSCRIPTION_ID=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/subscriptionId?api-version=2021-02-01&format=text")
echo "https://portal.azure.com/#@/dashboard/arm/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Portal/dashboards/IYKonect-Dashboard-${VM_NAME}"
echo ""
echo "Last 20 lines of user-data.log:"
echo "--------------------------------------------"
tail -n 20 /var/log/user-data.log
echo ""
echo "For more logs, use: tail -n 100 /var/log/user-data.log"
echo "=============================================="
EOF

chmod +x /usr/local/bin/logs-dashboard

# Add logs-dashboard to aliases
echo "alias logs-dashboard='/usr/local/bin/logs-dashboard'" >> /etc/profile.d/iykonect-welcome.sh

log "Enhanced Azure Monitor setup completed with dashboard for user-data.log visualization."
log "You can use the 'logs-dashboard' command to access log dashboards."