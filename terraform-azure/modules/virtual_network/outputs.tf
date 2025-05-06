output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.main.name
}

output "vm_subnet_id" {
  description = "ID of the VM Subnet"
  value       = azurerm_subnet.vm.id
}

output "appgw_subnet_id" {
  description = "ID of the Application Gateway Subnet"
  value       = azurerm_subnet.appgw.id
}

output "nsg_id" {
  description = "ID of the Network Security Group"
  value       = azurerm_network_security_group.main.id
}