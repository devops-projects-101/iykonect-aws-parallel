#!/bin/bash
sudo apt-get update
sudo apt-get install -y docker.io awscli
sudo systemctl start docker
sudo systemctl enable docker

# Configure AWS CLI
aws configure set aws_access_key_id "${aws_access_key}"
aws configure set aws_secret_access_key "${aws_secret_key}"
aws configure set region "${aws_region}"

# Configure AWS CLI and authenticate with ECR
aws ecr get-login-password --region ${aws_region} | sudo docker login --username AWS --password-stdin 571664317480.dkr.ecr.${aws_region}.amazonaws.com

# Create docker network
sudo docker network create app-network

# Pull images from ECR
sudo docker pull 571664317480.dkr.ecr.${aws_region}.amazonaws.com/iykonect-images:redis
sudo docker pull 571664317480.dkr.ecr.${aws_region}.amazonaws.com/iykonect-images:prometheus
sudo docker pull 571664317480.dkr.ecr.${aws_region}.amazonaws.com/iykonect-images:grafana
sudo docker pull 571664317480.dkr.ecr.${aws_region}.amazonaws.com/iykonect-images:api
sudo docker pull 571664317480.dkr.ecr.${aws_region}.amazonaws.com/iykonect-images:react-app

# Run Redis
sudo docker run -d \
  --name redis_service \
  --network app-network \
  -p 6379:6379 \
  -e REDIS_PASSWORD=IYKONECTpassword \
  --restart always \
  571664317480.dkr.ecr.${aws_region}.amazonaws.com/iykonect-images:redis \
  redis-server --requirepass IYKONECTpassword --bind 0.0.0.0

# Run API
sudo docker run -d \
  --name api \
  --network app-network \
  -p 8000:80 \
  --restart always \
  571664317480.dkr.ecr.${aws_region}.amazonaws.com/iykonect-images:api

# Run Prometheus
sudo docker run -d \
  --name prometheus \
  --network app-network \
  -p 9090:9090 \
  --restart always \
  571664317480.dkr.ecr.${aws_region}.amazonaws.com/iykonect-images:prometheus

# Run Grafana Renderer
sudo docker run -d \
  --name renderer \
  --network app-network \
  -p 8081:8081 \
  --restart always \
  grafana/grafana-image-renderer:latest

# Run Grafana
sudo docker run -d \
  --name iykon-graphana-app \
  --network app-network \
  -p 3100:3000 \
  --user root \
  --restart always \
  571664317480.dkr.ecr.${aws_region}.amazonaws.com/iykonect-images:grafana

# Create required directories and set permissions
sudo mkdir -p /home/ubuntu/logs /home/ubuntu/grafana/{provisioning/datasources,provisioning/dashboards,dashboards}
sudo chown -R ubuntu:ubuntu /home/ubuntu/logs /home/ubuntu/grafana