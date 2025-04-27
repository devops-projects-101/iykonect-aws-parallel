variable "prefix" {
  type    = string
  default = "iykonect-migrate"
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

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy   = "Terraform"
    Project     = "iykonect"
    Environment = "parallel"
  }
}
