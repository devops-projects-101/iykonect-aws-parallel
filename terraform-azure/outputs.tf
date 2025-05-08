output "resource_group_name" {
  description = "Name of the Azure Resource Group"
  value       = azurerm_resource_group.main.name
}

output "virtual_network_name" {
  description = "Name of the Virtual Network"
  value       = module.virtual_network.vnet_name
}

output "application_gateway_enabled" {
  description = "Whether the Application Gateway is enabled"
  value       = var.enable_application_gateway
}

output "application_gateway_ip" {
  description = "Public IP address of the Azure Application Gateway"
  value       = var.enable_application_gateway ? module.application_gateway[0].public_ip : "Application Gateway disabled"
}

output "application_gateway_domain" {
  description = "Domain name (FQDN) of the Azure Application Gateway"
  value       = var.enable_application_gateway ? module.application_gateway[0].appgw_fqdn : "Application Gateway disabled"
}

output "application_gateway_url" {
  description = "URL for the Application Gateway"
  value       = var.enable_application_gateway ? "http://${module.application_gateway[0].public_ip}" : "Application Gateway disabled"
}

output "active_endpoint" {
  description = "The active endpoint that DNS is pointing to (Application Gateway or VM)"
  value       = var.enable_application_gateway ? "Application Gateway" : "Virtual Machine"
}

output "active_ip" {
  description = "The active IP address that DNS is pointing to"
  value       = var.enable_application_gateway ? module.application_gateway[0].public_ip : module.vm.vm_public_ips[0]
}

output "nginx_url" {
  description = "URL for Nginx running on port 80"
  value       = "http://${module.vm.vm_public_ips[0]}"
}

output "vm_public_ips" {
  description = "Public IP addresses of the Azure VMs"
  value       = module.vm.vm_public_ips
}

output "vm_private_ips" {
  description = "Private IP addresses of the Azure VMs"
  value       = module.vm.vm_private_ips
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = module.vm.ssh_command
}

# Service URLs via Nginx
output "service_urls" {
  description = "Map of service paths to their URLs via Nginx"
  value = {
    main_url      = "http://${module.vm.vm_public_ips[0]}"
    api           = "http://${module.vm.vm_public_ips[0]}/api"
    signable      = "http://${module.vm.vm_public_ips[0]}/signable"
    email_server  = "http://${module.vm.vm_public_ips[0]}/email"
    company_house = "http://${module.vm.vm_public_ips[0]}/company-house"
    prometheus    = "http://${module.vm.vm_public_ips[0]}/prometheus"
    grafana       = "http://${module.vm.vm_public_ips[0]}/grafana"
  }
}

# Direct container URLs (for internal/debug use)
output "direct_container_urls" {
  description = "Map of container names to their direct URLs"
  value = {
    api           = "http://${module.vm.vm_public_ips[0]}:8000"
    web           = "http://${module.vm.vm_public_ips[0]}:3000"
    signable      = "http://${module.vm.vm_public_ips[0]}:8082"
    email_server  = "http://${module.vm.vm_public_ips[0]}:8025"
    company_house = "http://${module.vm.vm_public_ips[0]}:8083"
    prometheus    = "http://${module.vm.vm_public_ips[0]}:9090"
    grafana       = "http://${module.vm.vm_public_ips[0]}:3100"
    nginx_control = "http://${module.vm.vm_public_ips[0]}:8008"
  }
}