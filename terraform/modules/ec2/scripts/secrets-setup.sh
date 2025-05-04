#!/bin/bash

# Function for logging
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
}

# Get instance metadata
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Fetch secrets from AWS Secrets Manager
log "==============================================="
log "Fetching secrets from AWS Secrets Manager"
log "==============================================="
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

log "==============================================="
log "Secrets setup completed"
log "==============================================="