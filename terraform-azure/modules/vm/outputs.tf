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