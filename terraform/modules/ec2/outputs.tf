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
  description = "HTTP endpoint for the API service"
  value = "http://${aws_instance.main.public_ip}:8000"
}

output "web_endpoint" {
  description = "HTTP endpoint for the Web service"
  value = "http://${aws_instance.main.public_ip}:3000"
}

output "signable_endpoint" {
  description = "HTTP endpoint for the Signable service"
  value = "http://${aws_instance.main.public_ip}:8082"
}

output "email_server_endpoint" {
  description = "HTTP endpoint for the Email Server service"
  value = "http://${aws_instance.main.public_ip}:8025"
}

output "company_house_endpoint" {
  description = "HTTP endpoint for the Company House service"
  value = "http://${aws_instance.main.public_ip}:8083"
}

output "redis_endpoint" {
  description = "Endpoint for the Redis service"
  value = "${aws_instance.main.public_ip}:6379" # Redis doesn't typically use http
}

output "prometheus_endpoint" {
  description = "HTTP endpoint for the Prometheus service"
  value = "http://${aws_instance.main.public_ip}:9090"
}

output "grafana_endpoint" {
  description = "HTTP endpoint for the Grafana service"
  value = "http://${aws_instance.main.public_ip}:3100"
}

output "nginx_control_endpoint" {
  description = "HTTP endpoint for the Nginx control container"
  value = "http://${aws_instance.main.public_ip}:8008"
}

output "security_group_id" {
  value = aws_security_group.instance.id
}
