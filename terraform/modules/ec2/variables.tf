variable "prefix" {
  type        = string
  description = "Prefix for resource naming"
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "docker_compose_content" {
  type        = string
  description = "Content of docker-compose.yml file"
}

variable "docker_username" {
  description = "Docker Hub username"
  type        = string
  sensitive   = true
}

variable "docker_password" {
  description = "Docker Hub password"
  type        = string
  sensitive   = true
}

variable "aws_access_key" {
  description = "AWS Access Key for ECR access"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Key for ECR access"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS Region for ECR"
  type        = string
  default     = "eu-west-1"
}

variable "efs_dns_name" {
  description = "DNS name of the EFS filesystem"
  type        = string
}

