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