#!/bin/bash

# This script checks the health of Docker containers in the Azure environment

set -e

# Logging function
log() {
    echo "[$(date)] $1"
}

log "Starting container health check..."

# Check if Docker service is running
if ! systemctl is-active --quiet docker; then
    log "ERROR: Docker service is not running"
    exit 1
fi

# Get list of running containers
CONTAINERS=$(docker ps --format "{{.Names}}")

if [ -z "$CONTAINERS" ]; then
    log "WARNING: No containers are currently running"
    exit 1
fi

# Check status of each container
FAILED=0
for CONTAINER in $CONTAINERS; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER")
    
    if [ "$STATUS" != "running" ]; then
        log "Container $CONTAINER is not running (status: $STATUS)"
        FAILED=1
    else
        # Get container health if available
        HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER")
        
        if [ "$HEALTH" = "unhealthy" ]; then
            log "Container $CONTAINER is unhealthy"
            FAILED=1
        elif [ "$HEALTH" != "none" ] && [ "$HEALTH" != "healthy" ]; then
            log "Container $CONTAINER health status: $HEALTH"
        else
            log "Container $CONTAINER is running properly"
        fi
    fi
done

check_endpoint "http://localhost:8000" "api" "8000"
check_endpoint "http://localhost:3000" "web" "3000"
check_endpoint "http://localhost:8082" "signable" "8082"
check_endpoint "http://localhost:8025" "email-server" "8025"
check_endpoint "http://localhost:8083" "company-house" "8083"
check_endpoint "" "redis" "6379"
check_endpoint "http://localhost:9090" "prometheus" "9090"
check_endpoint "http://localhost:3100" "grafana" "3100"
check_endpoint "http://localhost:8008" "nginx-control" "8008"

echo "PORT ACCESS CHECK"
echo "----------------"
FAILED_PORTS=""

for port in 8000 3000 8082 8025 8083 6379 9090 3100 8008; do
    if ! nc -z localhost $port; then
        log "Port $port is not accessible"
        FAILED_PORTS="$FAILED_PORTS $port"
    fi
done

if [ -n "$FAILED_PORTS" ]; then
    log "The following ports are not accessible:$FAILED_PORTS"
    exit 1
else
    log "All ports are accessible"
fi

if [ $FAILED -eq 1 ]; then
    log "One or more containers have issues"
    exit 1
else
    log "All containers are running properly"
    exit 0
fi