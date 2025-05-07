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

# Retrieve the Public IP associated with the Application Gateway
data "azurerm_public_ip" "appgw_public_ip" {
  name                = "${var.prefix}-appgw-pip"
  resource_group_name = azurerm_resource_group.main.name
  
  # Ensure this data source is only read after the application gateway is created
  depends_on = [module.application_gateway]
}

# Create an A record in the subdomain zone
resource "azurerm_dns_a_record" "appgw_subdomain_a_record" {
  name                = "@"
  zone_name           = azurerm_dns_zone.parallel.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [data.azurerm_public_ip.appgw_public_ip.ip_address]
  
  depends_on = [
    module.application_gateway,
    data.azurerm_public_ip.appgw_public_ip
  ]
}