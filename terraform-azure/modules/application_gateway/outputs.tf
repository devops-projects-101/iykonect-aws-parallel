output "backend_pool_id" {
  description = "ID of the Application Gateway's Backend Address Pool"
  value       = azurerm_application_gateway.main.backend_address_pool[0].id
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