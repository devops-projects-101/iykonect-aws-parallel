output "vm_ids" {
  description = "IDs of the Azure Virtual Machines"
  value       = azurerm_linux_virtual_machine.main[*].id
}

output "vm_private_ips" {
  description = "Private IP addresses of the Azure VMs"
  value       = azurerm_network_interface.main[*].private_ip_address
}

output "vm_public_ips" {
  description = "Public IP addresses of the Azure VMs"
  value       = azurerm_public_ip.vm[*].ip_address
}

output "ssh_command" {
  description = "SSH command to connect to the first VM"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.vm[0].ip_address}"
}

output "docker_registry_endpoint" {
  description = "URL for Docker Registry if deployed"
  value       = ["http://${azurerm_public_ip.vm[*].ip_address}:5000"]
}

output "docker_api_endpoint" {
  description = "Docker API endpoint"
  value       = ["tcp://${azurerm_public_ip.vm[*].ip_address}:2375"]
}

output "docker_api_tls_endpoint" {
  description = "Docker API TLS endpoint"
  value       = ["tcp://${azurerm_public_ip.vm[*].ip_address}:2376"]
}

output "docker_container_urls" {
  description = "Map of container names to their URLs"
  value = {
    api            = formatlist("http://%s:8000", azurerm_public_ip.vm[*].ip_address)
    web            = formatlist("http://%s:5001", azurerm_public_ip.vm[*].ip_address)
    signable       = formatlist("http://%s:8082", azurerm_public_ip.vm[*].ip_address)
    email_server   = formatlist("http://%s:8025", azurerm_public_ip.vm[*].ip_address)
    company_house  = formatlist("http://%s:8083", azurerm_public_ip.vm[*].ip_address)
    redis          = formatlist("%s:6379", azurerm_public_ip.vm[*].ip_address)
    prometheus     = formatlist("http://%s:9090", azurerm_public_ip.vm[*].ip_address)
    grafana        = formatlist("http://%s:3100", azurerm_public_ip.vm[*].ip_address)
    nginx_control  = formatlist("http://%s:8008", azurerm_public_ip.vm[*].ip_address)
  }
}