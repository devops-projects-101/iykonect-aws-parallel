output "backend_pool_id" {
  description = "ID of the Application Gateway's Backend Address Pool"
  value       = [for pool in azurerm_application_gateway.main.backend_address_pool : pool.id if pool.name == var.backend_address_pool_name][0]
}

output "public_ip" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.appgw.ip_address
}

output "appgw_name" {
  description = "Name of the Application Gateway"
  value       = azurerm_application_gateway.main.name
}

output "appgw_id" {
  description = "ID of the Application Gateway"
  value       = azurerm_application_gateway.main.id
}

output "appgw_fqdn" {
  description = "FQDN (Fully Qualified Domain Name) of the Application Gateway"
  value       = azurerm_public_ip.appgw.fqdn
}