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

output "web-latest" {
  value = "http://${aws_instance.main.public_ip}:5001"
}

output "signable-latest" {
  value = "http://${aws_instance.main.public_ip}:8082"
}

output "email-server-latest" {
  value = "http://${aws_instance.main.public_ip}:8025"
}

output "company-house-latest" {
  value = "http://${aws_instance.main.public_ip}:8083"
}


output "redis-latest" {
  value = "http://${aws_instance.main.public_ip}:6379"
}


output "prometheus-latest" {
  value = "http://${aws_instance.main.public_ip}:9090"
}


output "grafana-latest" {
  value = "http://${aws_instance.main.public_ip}:3100"
}

output "security_group_id" {
  value = aws_security_group.instance.id
}
