output "lb_id" {
  description = "ID of the Load Balancer"
  value       = azurerm_lb.main.id
}

output "public_ip_address" {
  description = "Public IP address of the Load Balancer"
  value       = azurerm_public_ip.lb.ip_address
}

output "backend_pool_id" {
  description = "ID of the Backend Address Pool"
  value       = azurerm_lb_backend_address_pool.main.id
}