variable "prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for EFS security group"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for EFS mount target"
  type        = string
}

variable "allowed_security_groups" {
  description = "List of security group IDs allowed to access EFS"
  type        = list(string)
}
