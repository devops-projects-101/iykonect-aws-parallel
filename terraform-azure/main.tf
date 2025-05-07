# This file contains the Terraform configuration to deploy Azure resources,
# including a Resource Group, Network Watcher, Key Vault, Virtual Network,
# Virtual Machine, Application Gateway, and DNS configuration for a subdomain.

# Create the main Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.default_tags
}

# Create Network Watcher in the main resource group
# This prevents Azure from creating a default NetworkWatcherRG
resource "azurerm_network_watcher" "main" {
  name                = "${var.prefix}-network-watcher"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.default_tags
}

# Create Key Vault for SSH keys and other secrets
resource "azurerm_key_vault" "main" {
  name                = "iykkv" # Consider making this name more dynamic/unique
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = var.azure_tenant_id
  sku_name            = "standard"

  # Soft delete and purge protection settings
  purge_protection_enabled = false # Set to true for production environments
  soft_delete_retention_days = 7   # Minimum 7 days, recommend higher for production

  # Access policy for a specific principal (e.g., a service principal or user)
  # Ensure var.azure_tenant_id and var.azure_client_id are correctly defined
  access_policy {
    tenant_id = var.azure_tenant_id
    object_id = var.azure_client_id # Object ID of the principal needing access

    key_permissions = [
      "Get", "List"
    ]

    secret_permissions = [
      "Get", "List"
    ]
  }

  tags = var.default_tags
}

# Reference an existing SSH public key stored in Azure
# Ensure the resource group and name match your existing SSH key resource
data "azurerm_ssh_public_key" "existing" {
  name                = "common_azure_ssh_key"
  resource_group_name = "iykonect-azure-parallel-rg" # Resource group where the SSH key exists
}

# Deploy the Virtual Network using a module
# This module should define the VNet and subnets (including one for App Gateway and VMs)
module "virtual_network" {
  source              = "./modules/virtual_network" # Path to your virtual_network module
  prefix              = var.prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = var.default_tags
  # The module should output subnet IDs, e.g., vm_subnet_id and appgw_subnet_id
}

# Create VM(s) first to get their private IP addresses
# These VMs will be the backend targets for the Application Gateway
module "vm" {
  source              = "./modules/vm" # Path to your vm module
  prefix              = var.prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  subnet_id           = module.virtual_network.vm_subnet_id # Assign VMs to the VM subnet
  vm_size             = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password # Avoid using passwords directly in config - use Key Vault
  aws_access_key      = var.aws_access_key # Consider storing secrets in Key Vault
  aws_secret_key      = var.aws_secret_key # Consider storing secrets in Key Vault
  aws_region          = var.aws_region
  admin_ssh_key       = data.azurerm_ssh_public_key.existing.public_key # Use the referenced SSH key
  tags                = var.default_tags
  desired_count       = var.desired_count # Number of VMs to deploy
  # The module should output the private IPs of the deployed VMs, e.g., vm_private_ips
}

# Then create the Application Gateway
# It uses the VM private IP addresses as backend targets
module "application_gateway" {
  source              = "./modules/application_gateway" # Path to your application_gateway module
  prefix              = var.prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  subnet_id           = module.virtual_network.appgw_subnet_id # Assign App Gateway to its subnet
  backend_vm_ip_addresses = module.vm.vm_private_ips # Pass VM IPs to the App Gateway backend pool
  tags                = var.default_tags
  # Ensure the Application Gateway is created after the VMs
  depends_on          = [module.vm]
  # Your application_gateway module should output the Public IP resource ID or name
  # For example, it might output 'public_ip_id' or 'public_ip_name'
}

# --- DNS Configuration for Subdomain Association ---

# Data source to reference the parent DNS zone
# This zone should already exist and be managed elsewhere or manually
data "azurerm_dns_zone" "parent" {
  name                = var.parent_dns_zone_name
  resource_group_name = var.parent_dns_zone_resource_group
}

# Create the delegated DNS zone for the subdomain (e.g., parallel.yourdomain.com)
resource "azurerm_dns_zone" "parallel" {
  name                = "parallel.${var.parent_dns_zone_name}"
  resource_group_name = azurerm_resource_group.main.name # Place the subdomain zone in the main RG
  tags                = var.default_tags
}

# Create NS records in the parent zone to delegate the subdomain to the new zone
resource "azurerm_dns_ns_record" "parallel_delegation" {
  name                = "parallel" # The subdomain name relative to the parent zone
  zone_name           = data.azurerm_dns_zone.parent.name
  resource_group_name = data.azurerm_dns_zone.parent.resource_group_name
  ttl                 = 300
  records             = azurerm_dns_zone.parallel.name_servers # Use the nameservers of the delegated zone
}

# Retrieve the Public IP associated with the Application Gateway
# The name uses the correct naming convention from the module (${var.prefix}-appgw-pip)
data "azurerm_public_ip" "appgw_public_ip" {
  name                = "${var.prefix}-appgw-pip"
  resource_group_name = azurerm_resource_group.main.name
  
  # Ensure this data source is only read after the application gateway is created
  depends_on = [module.application_gateway]
}

# Create an A record in the delegated subdomain DNS zone
# This A record points the root of the subdomain (parallel.yourdomain.com)
# to the Public IP address of the Application Gateway.
resource "azurerm_dns_a_record" "appgw_subdomain_a_record" {
  # Use "@" for the root of the subdomain (parallel.<parent_dns_zone_name>)
  name                = "@"
  zone_name           = azurerm_dns_zone.parallel.name
  resource_group_name = azurerm_dns_zone.parallel.resource_group_name
  ttl                 = 300 # Time to live for the DNS record

  # Set the record's IP address to the Application Gateway's Public IP
  records             = [data.azurerm_public_ip.appgw_public_ip.ip_address]

  # Ensure the DNS record is created after the Application Gateway is deployed
  # and the Public IP information is available.
  depends_on = [
    module.application_gateway,
    data.azurerm_public_ip.appgw_public_ip # Ensure the data source resolves the IP
  ]
}