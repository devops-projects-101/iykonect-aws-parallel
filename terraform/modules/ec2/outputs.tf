output "instance_id" {
  value = aws_spot_instance_request.main.spot_instance_id
}

output "public_ip" {
  value = aws_spot_instance_request.main.public_ip
}

output "api_endpoint" {
  value = "http://${aws_spot_instance_request.main.public_ip}:8000"
}

output "prometheus_endpoint" {
  value = "http://${aws_spot_instance_request.main.public_ip}:9090"
}

output "grafana_endpoint" {
  value = "http://${aws_spot_instance_request.main.public_ip}:3100"
}

output "sonarqube_endpoint" {
  value = "http://${aws_spot_instance_request.main.public_ip}:9000"
}

output "renderer_endpoint" {
  value = "http://${aws_spot_instance_request.main.public_ip}:8081"
}

output "security_group_id" {
  value = aws_security_group.instance.id
}
