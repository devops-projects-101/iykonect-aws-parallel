# --- DNS Configuration for Subdomain Association ---


# parallel.iykonect.iykons.com



# Data source to reference the parent DNS zone
# This zone should already exist and be managed elsewhere or manually
data "azurerm_dns_zone" "parent" {
  name                = var.parent_dns_zone_name
  resource_group_name = var.parent_dns_zone_resource_group
}

# Create the delegated DNS zone for the subdomain
resource "azurerm_dns_zone" "parallel" {
  name                = "parallel.${var.parent_dns_zone_name}"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.default_tags
}

# Create NS records in the parent zone to delegate the subdomain
resource "azurerm_dns_ns_record" "parallel_delegation" {
  name                = "parallel"
  zone_name           = data.azurerm_dns_zone.parent.name
  resource_group_name = data.azurerm_dns_zone.parent.resource_group_name
  ttl                 = 300
  
  # Explicitly list all name servers from the subdomain zone
  records             = azurerm_dns_zone.parallel.name_servers
  
  # Ensure the DNS zone is created before the NS record
  depends_on = [azurerm_dns_zone.parallel]
}

# Retrieve the Public IP associated with the Application Gateway (only if enabled)
data "azurerm_public_ip" "appgw_public_ip" {
  count               = var.enable_application_gateway ? 1 : 0
  name                = "${var.prefix}-appgw-pip"
  resource_group_name = azurerm_resource_group.main.name
  
  # Ensure this data source is only read after the application gateway is created
  depends_on = [module.application_gateway]
}

# Create an A record in the subdomain zone pointing to either Application Gateway or VM based on toggle
resource "azurerm_dns_a_record" "subdomain_a_record" {
  name                = "@"
  zone_name           = azurerm_dns_zone.parallel.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  
  # If Application Gateway is enabled, use its IP; otherwise use the VM's public IP
  records             = var.enable_application_gateway ? [data.azurerm_public_ip.appgw_public_ip[0].ip_address] : [module.vm.vm_public_ips[0]]
  
  depends_on = [
    module.vm,
    module.application_gateway
  ]
}