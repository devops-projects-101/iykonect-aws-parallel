output "instance_public_ip" {
  value = module.ec2.public_ip
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "api_endpoint" {
  value = module.ec2.api_endpoint
}

output "prometheus_endpoint" {
  value = module.ec2.prometheus_endpoint
}

output "grafana_endpoint" {
  value = module.ec2.grafana_endpoint
}

output "sonarqube_endpoint" {
  value = module.ec2.sonarqube_endpoint
}

output "renderer_endpoint" {
  value = module.ec2.renderer_endpoint
}
