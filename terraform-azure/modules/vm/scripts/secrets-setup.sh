#!/bin/bash

# Azure-specific Secrets Setup Script for IYKonect infrastructure

# Function for logging
log() {
    echo "[$(date)] $1" | sudo tee -a /var/log/user-data.log
}


log "Starting from secret setup"
# Source VM metadata from the permanent manifest file
# Source VM metadata from the permanent manifest file
METADATA_FILE="/opt/iykonect/metadata/vm_metadata.sh"

log "Loading VM metadata from $METADATA_FILE"
source "$METADATA_FILE"



# Create timestamp for this run
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Check if AWS credentials are available and set AWS region
if [ -f /root/.aws/credentials ]; then
    AWS_REGION=$(grep region /root/.aws/credentials | head -1 | cut -d= -f2 | tr -d ' ')
    if [ -z "$AWS_REGION" ]; then
        AWS_REGION="eu-west-1"
    fi
else
    AWS_REGION="eu-west-1"
    log "WARNING: AWS credentials file not found, using default region."
fi

log "==============================================="
log "Fetching secrets from AWS Secrets Manager (Azure VM: $VM_NAME)"
log "==============================================="
log "VM Information:"
log "Name: $VM_NAME"
log "Resource Group: $RESOURCE_GROUP"
log "Location: $LOCATION"
log "Public IP: $PUBLIC_IP"
log "Private IP: $PRIVATE_IP"
log "AWS Region for Secrets: $AWS_REGION"

# Create necessary directories
mkdir -p /opt/iykonect/env/history
mkdir -p /opt/iykonect/config/history
mkdir -p /opt/iykonect/config/current

# Remove existing file if it exists to avoid appending to corrupted file
rm -f /opt/iykonect/env/app.env
touch /opt/iykonect/env/app.env
chmod 600 /opt/iykonect/env/app.env

# Create a new environment file with header documentation
log "Setting up explicit environment variables for Azure environment"
cat > /opt/iykonect/env/app.env << EOL
# Environment configuration for IYKonect Azure VM
# Generated on: $(date)
# VM Name: $VM_NAME
# Resource Group: $RESOURCE_GROUP
# Location: $LOCATION
# Public IP: $PUBLIC_IP
# Private IP: $PRIVATE_IP

# Base URLs
API_ENDPOINT=http://${PUBLIC_IP}:8000
REACT_APP_BASE_URL=http://${PUBLIC_IP}:8000
AppSettings__DomainBaseUrl=http://${PUBLIC_IP}:3000

# Azure-specific settings
AZURE_VM=true
AZURE_LOCATION=${LOCATION}
AZURE_RESOURCE_GROUP=${RESOURCE_GROUP}

# Database connection string
ConnectionStrings__DefaultConnection=Server=${PRIVATE_IP};Database=iykonect;User Id=iykonectuser;Password=iykonectpassword;

# Service endpoints
SERVICE_EMAIL_ENDPOINT=http://${PRIVATE_IP}:8025
SERVICE_COMPANY_HOUSE_ENDPOINT=http://${PRIVATE_IP}:8083
SERVICE_SIGNABLE_ENDPOINT=http://${PRIVATE_IP}:8082
EOL

# Make a timestamped copy
cp /opt/iykonect/env/app.env "/opt/iykonect/env/history/app.env.${TIMESTAMP}"

# Initialize app.json if it doesn't exist
echo "{}" > /opt/iykonect/config/app.json

# Test AWS CLI to ensure it's properly configured
log "Testing AWS CLI configuration..."
TEST_OUTPUT=$(aws sts get-caller-identity 2>&1)
if [ $? -ne 0 ]; then
    log "ERROR: AWS CLI is not properly configured. Error: $TEST_OUTPUT"
    log "Will proceed with only local environment variables."
    
    log "Minimal environment setup completed with fallback values"
    log "==============================================="
    log "Secrets setup completed with fallback configuration"
    log "==============================================="
    exit 0
fi

# Get list of secrets using a more reliable approach
log "Retrieving secrets list from AWS Secrets Manager..."
SECRETS_OUTPUT_FILE=$(mktemp)
aws secretsmanager list-secrets --region ${AWS_REGION} --output json > ${SECRETS_OUTPUT_FILE} 2>&1
if [ $? -ne 0 ]; then
    log "ERROR: Failed to retrieve secrets list from AWS Secrets Manager."
    cat ${SECRETS_OUTPUT_FILE} | tee -a /var/log/user-data.log
    rm ${SECRETS_OUTPUT_FILE}
    
    log "==============================================="
    log "Secrets setup completed with only local configuration"
    log "==============================================="
    exit 0
fi

# Parse secrets list safely
SECRETS_LIST=$(jq -r '.SecretList[].Name' ${SECRETS_OUTPUT_FILE} 2>/dev/null)
if [ -z "$SECRETS_LIST" ]; then
    log "WARNING: No secrets found in AWS Secrets Manager or error parsing output."
    cat ${SECRETS_OUTPUT_FILE} | tee -a /var/log/user-data.log
    rm ${SECRETS_OUTPUT_FILE}
    
    log "==============================================="
    log "Secrets setup completed with only local configuration"
    log "==============================================="
    exit 0
fi
rm ${SECRETS_OUTPUT_FILE}

log "Found secrets: ${SECRETS_LIST}"

# Process each secret with improved error handling
for FULL_SECRET_NAME in ${SECRETS_LIST}; do
  # Skip empty secret names
  if [ -z "$FULL_SECRET_NAME" ]; then
    continue
  fi
  
  # Extract variable name (after slash)
  if [[ "$FULL_SECRET_NAME" == *"/"* ]]; then
    SECRET_VAR_NAME=$(echo "$FULL_SECRET_NAME" | rev | cut -d'/' -f1 | rev)
  else
    SECRET_VAR_NAME=$FULL_SECRET_NAME
  fi
  
  # Skip excluded secrets
  if [[ "$SECRET_VAR_NAME" == "QA" || "$SECRET_VAR_NAME" == "Production" ]]; then
    log "Skipping excluded secret: ${FULL_SECRET_NAME}"
    continue
  fi
  
  # Get the secret value with better error handling
  log "Retrieving secret: ${FULL_SECRET_NAME}"
  SECRET_OUTPUT_FILE=$(mktemp)
  aws secretsmanager get-secret-value --secret-id ${FULL_SECRET_NAME} \
    --region ${AWS_REGION} --query SecretString --output text > ${SECRET_OUTPUT_FILE} 2>&1
  
  # Check if the command was successful and file contains valid data
  if [ $? -ne 0 ] || grep -q "<Error" ${SECRET_OUTPUT_FILE} || grep -q "<html" ${SECRET_OUTPUT_FILE}; then
    log "ERROR: Failed to retrieve secret ${FULL_SECRET_NAME}:"
    cat ${SECRET_OUTPUT_FILE} | tee -a /var/log/user-data.log
    rm ${SECRET_OUTPUT_FILE}
    continue
  fi
  
  # Read the secret value
  SECRET_VALUE=$(<${SECRET_OUTPUT_FILE})
  rm ${SECRET_OUTPUT_FILE}
  
  # Skip empty values
  if [ -z "$SECRET_VALUE" ]; then
    log "WARNING: Empty value for secret ${FULL_SECRET_NAME}, skipping."
    continue
  fi
  
  # Process the secret value
  if echo "$SECRET_VALUE" | grep -q "^{" && echo "$SECRET_VALUE" | grep -q "}$"; then
    # Looks like JSON - validate it
    if echo "$SECRET_VALUE" | jq empty >/dev/null 2>&1; then
      log "Saving JSON config for ${SECRET_VAR_NAME}"
      echo "$SECRET_VALUE" > "/opt/iykonect/config/current/${SECRET_VAR_NAME}.json"
      cp "/opt/iykonect/config/current/${SECRET_VAR_NAME}.json" "/opt/iykonect/config/history/${SECRET_VAR_NAME}.json.${TIMESTAMP}"
      # Safely merge JSON
      if jq -s '.[0] * .[1]' /opt/iykonect/config/app.json <(echo "$SECRET_VALUE") > /tmp/merged.json 2>/dev/null; then
        mv /tmp/merged.json /opt/iykonect/config/app.json
      else
        log "WARNING: Failed to merge JSON for ${SECRET_VAR_NAME}"
      fi
    else
      log "WARNING: Invalid JSON format for ${SECRET_VAR_NAME}, treating as string"
      # Only add to environment if it doesn't contain XML/HTML tags
      if ! echo "$SECRET_VALUE" | grep -q "<\|>" ; then
        echo "# Added from AWS Secrets Manager" >> /opt/iykonect/env/app.env
        echo "${SECRET_VAR_NAME}=${SECRET_VALUE}" >> /opt/iykonect/env/app.env
      else
        log "WARNING: Secret value contains XML/HTML tags, skipping"
      fi
    fi
  # Check if SSL key/cert
  elif [[ "$SECRET_VALUE" == *"BEGIN"* && ("$SECRET_VALUE" == *"PRIVATE KEY"* || "$SECRET_VALUE" == *"CERTIFICATE"*) ]]; then
    log "Saving PEM file for ${SECRET_VAR_NAME}"
    echo "$SECRET_VALUE" > "/opt/iykonect/config/current/${SECRET_VAR_NAME}.pem"
    cp "/opt/iykonect/config/current/${SECRET_VAR_NAME}.pem" "/opt/iykonect/config/history/${SECRET_VAR_NAME}.pem.${TIMESTAMP}"
    chmod 600 "/opt/iykonect/config/current/${SECRET_VAR_NAME}.pem"
  # Plain text value - add as environment variable if it doesn't contain XML/HTML
  elif ! echo "$SECRET_VALUE" | grep -q "<\|>" ; then
    log "Adding environment variable: ${SECRET_VAR_NAME}"
    echo "# Added from AWS Secrets Manager" >> /opt/iykonect/env/app.env
    echo "${SECRET_VAR_NAME}=${SECRET_VALUE}" >> /opt/iykonect/env/app.env
  else
    log "WARNING: Secret ${SECRET_VAR_NAME} contains XML/HTML tags, skipping"
  fi
done

# Fix any potential issues in the environment file
log "Cleaning up environment file..."
# Make a backup
cp /opt/iykonect/env/app.env /opt/iykonect/env/app.env.bak

# Filter out any lines containing XML/HTML tags
grep -v "<\|>" /opt/iykonect/env/app.env.bak > /opt/iykonect/env/app.env
chmod 600 /opt/iykonect/env/app.env

# Create a manifest of all environment files
log "Creating environment files manifest..."
cat > "/opt/iykonect/env/manifest.${TIMESTAMP}.txt" << EOF
Environment Configuration Manifest
Generated: $(date)
VM Name: ${VM_NAME}
Resource Group: ${RESOURCE_GROUP}
Location: ${LOCATION}

Environment Files:
$(find /opt/iykonect/env -type f -ls)

Configuration Files:
$(find /opt/iykonect/config -type f -ls)
EOF

chmod 600 "/opt/iykonect/env/manifest.${TIMESTAMP}.txt"

# Display the environment file for debugging (hide sensitive values)
log "Environment file created with the following variables (values hidden):"
grep -v -e "^#" /opt/iykonect/env/app.env | sed 's/=.*$/=********/' | sort

log "==============================================="
log "Secrets setup completed successfully"
log "==============================================="
log "A backup copy of all files has been created with timestamp: ${TIMESTAMP}"