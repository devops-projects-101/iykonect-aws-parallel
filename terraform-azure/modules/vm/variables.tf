variable "prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region to deploy resources"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet to associate resources with"
  type        = string
}

variable "vm_size" {
  description = "Size of the Azure VM"
  type        = string
  default     = "Standard_B2s"
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
  default     = null
}

variable "admin_ssh_key" {
  description = "SSH public key data for VM access"
  type        = string
}

variable "backend_pool_id" {
  description = "ID of the Backend Address Pool (Load Balancer or Application Gateway)"
  type        = string
  default     = ""
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
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}

variable "desired_count" {
  description = "Number of VMs to create"
  type        = number
  default     = 1
}

variable "storage_account_id" {
  description = "ID of the storage account containing configuration"
  type        = string
  default     = ""
}

variable "storage_account_name" {
  description = "Name of the storage account containing configuration"
  type        = string
  default     = ""
}

variable "storage_container_name" {
  description = "Name of the storage container containing configuration"
  type        = string
  default     = ""
}

variable "storage_blob_name" {
  description = "Name of the storage blob containing configuration"
  type        = string
  default     = ""
}

