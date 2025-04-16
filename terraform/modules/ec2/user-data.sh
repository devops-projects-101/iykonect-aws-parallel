#!/bin/bash
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl start docker
sudo systemctl enable docker

# Docker Hub login
echo "${docker_password}" | sudo docker login -u ${docker_username} --password-stdin

# Create docker network
sudo docker network create iykonect-network

# Run Redis
sudo docker run -d \
  --name redis \
  --network iykonect-network \
  -p 6379:6379 \
  --restart always \
  redis:latest

# Run API
sudo docker run -d \
  --name api \
  --network iykonect-network \
  -p 8080:80 \
  --restart always \
  iykonect/iykonect-api:latest

# Run Postgres
sudo docker run -d \
  --name postgres \
  --network iykonect-network \
  -p 5432:5432 \
  -e POSTGRES_DB=sonarqube \
  -e POSTGRES_USER=sonarqube \
  -e POSTGRES_PASSWORD=sonarqube \
  --restart always \
  postgres:13

# Run SonarQube
sudo docker run -d \
  --name sonarqube \
  --network iykonect-network \
  -p 9000:9000 \
  --restart always \
  sonarqube:community

# Run Prometheus
sudo docker run -d \
  --name prometheus \
  --network iykonect-network \
  -p 9090:9090 \
  --restart always \
  prom/prometheus:latest

# Run Grafana
sudo docker run -d \
  --name grafana \
  --network iykonect-network \
  -p 3000:3000 \
  --restart always \
  grafana/grafana-oss:11.0.0-ubuntu