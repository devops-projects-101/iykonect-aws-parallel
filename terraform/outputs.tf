output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = module.ec2.public_ip
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "api_endpoint" {
  description = "HTTP endpoint for the API service"
  value       = module.ec2.api_endpoint
}

output "web_endpoint" {
  description = "HTTP endpoint for the Web service"
  value       = module.ec2.web_endpoint
}

output "signable_endpoint" {
  description = "HTTP endpoint for the Signable service"
  value       = module.ec2.signable_endpoint
}

output "email_server_endpoint" {
  description = "HTTP endpoint for the Email Server service"
  value       = module.ec2.email_server_endpoint
}

output "company_house_endpoint" {
  description = "HTTP endpoint for the Company House service"
  value       = module.ec2.company_house_endpoint
}

output "redis_endpoint" {
  description = "Endpoint for the Redis service"
  value       = module.ec2.redis_endpoint
}

output "prometheus_endpoint" {
  description = "HTTP endpoint for Prometheus"
  value       = module.ec2.prometheus_endpoint
}

output "grafana_endpoint" {
  description = "HTTP endpoint for Grafana"
  value       = module.ec2.grafana_endpoint
}

output "nginx_control_endpoint" {
  description = "HTTP endpoint for Nginx control container"
  value       = module.ec2.nginx_control_endpoint
}

# # Docker-related endpoints
# output "docker_registry_endpoint" {
#   description = "URL for Docker Registry if deployed"
#   value       = module.ec2.docker_registry_endpoint
# }

# output "docker_api_endpoint" {
#   description = "Docker API endpoint"
#   value       = module.ec2.docker_api_endpoint
# }

# output "docker_api_tls_endpoint" {
#   description = "Docker API TLS endpoint"
#   value       = module.ec2.docker_api_tls_endpoint
# }

# output "docker_container_urls" {
#   description = "Map of container names to their URLs"
#   value       = module.ec2.docker_container_urls
# }
