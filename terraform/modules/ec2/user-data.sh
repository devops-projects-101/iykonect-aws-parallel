#!/bin/bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose
sudo systemctl start docker
sudo systemctl enable docker

# Create environment file with Docker image versions
cat > /home/ubuntu/.env << EOL
REDIS_IMAGE=redis:latest
API_IMAGE=iykonect/iykonect-api:latest
SONARQUBE_IMAGE=sonarqube:community
POSTGRES_IMAGE=postgres:13
PROMETHEUS_IMAGE=prom/prometheus:latest
GRAFANA_IMAGE=grafana/grafana-oss:11.0.0-ubuntu
EOL

# Create docker-compose directory and file
mkdir -p /home/ubuntu/docker
echo '${docker_compose_content}' > /home/ubuntu/docker/docker-compose.yml

# Set permissions and start services
cd /home/ubuntu/docker
sudo chown -R ubuntu:ubuntu .
sudo docker compose --env-file ../.env up -d
