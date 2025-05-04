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

if [ $FAILED -eq 1 ]; then
    log "One or more containers have issues"
    exit 1
else
    log "All containers are running properly"
    exit 0
fi