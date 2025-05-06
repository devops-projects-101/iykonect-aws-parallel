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

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}

variable "backend_address_pool_name" {
  description = "Name of the backend address pool"
  type        = string
  default     = "vm-backend-pool"
}

variable "frontend_port_name" {
  description = "Name of the frontend port"
  type        = string
  default     = "frontend-port"
}

variable "frontend_ip_configuration_name" {
  description = "Name of the frontend IP configuration"
  type        = string
  default     = "frontend-ip-config"
}

variable "http_setting_name" {
  description = "Name of the HTTP setting"
  type        = string
  default     = "http-setting"
}

variable "listener_name" {
  description = "Name of the listener"
  type        = string
  default     = "http-listener"
}

variable "request_routing_rule_name" {
  description = "Name of the request routing rule"
  type        = string
  default     = "routing-rule"
}

variable "public_ip_sku" {
  description = "SKU of the public IP address"
  type        = string
  default     = "Standard"
}

variable "gateway_ip_configuration_name" {
  description = "Name of the gateway IP configuration"
  type        = string
  default     = "gateway-ip-config"
}