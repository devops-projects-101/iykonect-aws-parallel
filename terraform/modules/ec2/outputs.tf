locals {
  active_instance = {
    id = aws_instance.main.id,
    ip = aws_instance.main.public_ip
  }
}

output "instance_id" {
  value = aws_instance.main.id
}

output "public_ip" {
  value = aws_instance.main.public_ip
}

output "api_endpoint" {
  value = "http://${aws_instance.main.public_ip}:8000"
}

output "prometheus_endpoint" {
  value = "http://${aws_instance.main.public_ip}:9090"
}

output "grafana_endpoint" {
  value = "http://${aws_instance.main.public_ip}:3100"
}

output "renderer_endpoint" {
  value = "http://${aws_instance.main.public_ip}:8081"
}

output "security_group_id" {
  value = aws_security_group.instance.id
}
