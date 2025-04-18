locals {
  active_instance_id = local.use_spot && length(aws_spot_instance_request.main) > 0 ? aws_spot_instance_request.main[0].spot_instance_id : aws_instance.fallback[0].id
  active_public_ip  = local.use_spot && length(aws_spot_instance_request.main) > 0 ? aws_spot_instance_request.main[0].public_ip : aws_instance.fallback[0].public_ip
}

output "instance_id" {
  value = local.active_instance_id
}

output "public_ip" {
  value = local.active_public_ip
}

output "api_endpoint" {
  value = "http://${local.active_public_ip}:8000"
}

output "prometheus_endpoint" {
  value = "http://${local.active_public_ip}:9090"
}

output "grafana_endpoint" {
  value = "http://${local.active_public_ip}:3100"
}

output "sonarqube_endpoint" {
  value = "http://${local.active_public_ip}:9000"
}

output "renderer_endpoint" {
  value = "http://${local.active_public_ip}:8081"
}

output "security_group_id" {
  value = aws_security_group.instance.id
}
