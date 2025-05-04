#!/bin/bash

# Container health check script for status command
# This script checks the health status of all deployed containers

# Enable color output
GREEN="\033[0;32m"
RED="\033[0;31m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

check_endpoint() {
    local endpoint="$1"
    local container="$2"
    local port="$3"
    local timeout=2
    local health_status=0

    # Print container status first
    printf "%-15s" "$container"
    
    status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
    if [ $? -ne 0 ]; then
        printf "[${RED}NOT FOUND${NC}]"
        health_status=1
    elif [ "$status" != "running" ]; then
        printf "[${RED}$status${NC}]"
        health_status=1
    else
        # Show port information
        if [ -n "$port" ]; then
            printf "[${GREEN}RUNNING${NC}] [${CYAN}PORT: $port${NC}]"
        else
            printf "[${GREEN}RUNNING${NC}]"
        fi

        if [ -n "$endpoint" ]; then
            # Check if endpoint is responding
            response=$(curl -s -o /dev/null -w "%{http_code}" --request GET "$endpoint" --max-time $timeout 2>/dev/null)
            if [ $? -eq 0 ] && [ "$response" -ge 200 ] && [ "$response" -lt 400 ]; then
                printf " [${GREEN}ENDPOINT OK${NC}]"
            else
                printf " [${RED}ENDPOINT ERROR${NC}]"
                health_status=1
            fi
        fi
    fi
    
    echo ""
    
    # Show container logs if health check failed
    if [ $health_status -eq 1 ] && [ -n "$container" ]; then
        if docker ps -a | grep -q "$container"; then
            echo ""
            echo "Last 20 lines of logs for $container:"
            echo "-----------------------------------"
            docker logs --tail 20 "$container" 2>&1
            echo "-----------------------------------"
            echo ""
        fi
    fi
    
    return $health_status
}

# Check port accessibility via netcat if available
check_port_access() {
    local port="$1"
    local host="localhost"
    
    if command -v nc >/dev/null 2>&1; then
        if nc -z -w2 $host $port >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    fi
    
    # Fallback to curl if netcat is not available
    if curl -s "http://$host:$port" -m 1 >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Get instance IPs
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

echo "CONTAINER       STATUS              ENDPOINT"
echo "-----------------------------------------------"
check_endpoint "http://${PRIVATE_IP}:8000" "api" "8000"
check_endpoint "http://${PRIVATE_IP}:5001" "web" "5001"
check_endpoint "http://${PRIVATE_IP}:8082" "signable" "8082"
check_endpoint "http://${PRIVATE_IP}:8025" "email-server" "8025"
check_endpoint "http://${PRIVATE_IP}:8083" "company-house" "8083"
check_endpoint "" "redis" "6379"
check_endpoint "http://${PRIVATE_IP}:9090" "prometheus" "9090"
check_endpoint "http://${PRIVATE_IP}:3100" "grafana" "3100"
check_endpoint "http://${PRIVATE_IP}:8008" "nginx-control" "8008"

echo "PORT ACCESS CHECK"
echo "----------------"
for port in 8000 5001 8082 8025 8083 6379 9090 3100 8008; do
    printf "%-5s: " "$port"
    if check_port_access "$port"; then
        echo -e "[${GREEN}ACCESSIBLE${NC}]"
    else
        echo -e "[${RED}NOT ACCESSIBLE${NC}]"
        
        # Show container logs for the failed port
        container_id=$(docker ps -q --filter publish=$port)
        if [ -n "$container_id" ]; then
            container_name=$(docker inspect --format='{{.Name}}' $container_id | sed 's/\///')
            echo ""
            echo "Last 20 lines of logs for container on port $port ($container_name):"
            echo "-----------------------------------"
            docker logs --tail 20 $container_id 2>&1
            echo "-----------------------------------"
            echo ""
        fi
    fi
done