output "resource_group_name" {
  description = "Name of the Azure Resource Group"
  value       = azurerm_resource_group.main.name
}

output "virtual_network_name" {
  description = "Name of the Virtual Network"
  value       = module.virtual_network.vnet_name
}

output "load_balancer_ip" {
  description = "Public IP address of the Azure Load Balancer"
  value       = module.load_balancer.public_ip_address
}

output "vm_ips" {
  description = "Private IP addresses of the Azure VMs"
  value       = module.vm.vm_private_ips
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = module.vm.ssh_command
}

# Docker URL outputs
output "docker_registry_endpoint" {
  description = "URL for Docker Registry if deployed"
  value       = module.vm.docker_registry_endpoint
}

output "docker_api_endpoint" {
  description = "Docker API endpoint"
  value       = module.vm.docker_api_endpoint
}

output "docker_api_tls_endpoint" {
  description = "Docker API TLS endpoint"
  value       = module.vm.docker_api_tls_endpoint
}

output "docker_container_urls" {
  description = "Map of container names to their URLs"
  value       = module.vm.docker_container_urls
}

# Load balancer container URLs
output "load_balancer_container_urls" {
  description = "Map of container names to their load balancer URLs"
  value = {
    api           = "http://${module.load_balancer.public_ip_address}:8000"
    web           = "http://${module.load_balancer.public_ip_address}:5001"
    signable      = "http://${module.load_balancer.public_ip_address}:8082"
    email_server  = "http://${module.load_balancer.public_ip_address}:8025"
    company_house = "http://${module.load_balancer.public_ip_address}:8083"
    prometheus    = "http://${module.load_balancer.public_ip_address}:9090"
    grafana       = "http://${module.load_balancer.public_ip_address}:3100"
    nginx_control = "http://${module.load_balancer.public_ip_address}:8008"
  }
}