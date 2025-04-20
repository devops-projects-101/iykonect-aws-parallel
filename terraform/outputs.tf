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

output "prometheus_endpoint" {
  description = "HTTP endpoint for Prometheus"
  value       = module.ec2.prometheus_endpoint
}

output "grafana_endpoint" {
  description = "HTTP endpoint for Grafana"
  value       = module.ec2.grafana_endpoint
}

output "renderer_endpoint" {
  description = "HTTP endpoint for Grafana renderer"
  value       = module.ec2.renderer_endpoint
}
