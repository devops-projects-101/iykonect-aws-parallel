variable "prefix" {
  type    = string
  default = "iykonect-azure"
}

variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "West Europe"
}

# Azure credentials
variable "azure_subscription_id" {
  description = "Azure Subscription ID"
  type        = string
  sensitive   = true
}

variable "azure_tenant_id" {
  description = "Azure Tenant ID"
  type        = string
  sensitive   = true
}

variable "azure_client_id" {
  description = "Azure Client ID"
  type        = string
  sensitive   = true
}

variable "azure_client_secret" {
  description = "Azure Client Secret"
  type        = string
  sensitive   = true
}

# AWS credentials for ECR access
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
    Environment = "azure"
  }
}

variable "vm_size" {
  description = "Size of the Azure VM (e.g., Standard_D8s_v4 for 8 cores, 32 GB RAM)"
  type        = string
  default     = "Standard_D8s_v4" # Or "Standard_D8s_v5"
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "adminuser"
}

variable "admin_password" {
  description = "Admin password for the VM"
  type        = string
  sensitive   = true
}

variable "desired_count" {
  description = "Desired count of VMs"
  type        = number
  default     = 1
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "parent_dns_zone_name" {
  description = "Name of the existing parent DNS zone"
  type        = string
  default     = "iykonect.iykons.com"
}

variable "parent_dns_zone_resource_group" {
  description = "Resource group of the existing parent DNS zone"
  type        = string
  default     = "DevOps-ClickOps"
}

variable "enable_application_gateway" {
  description = "Whether to deploy the Application Gateway. If false, DNS will point directly to VM"
  type        = bool
  default     = true
}