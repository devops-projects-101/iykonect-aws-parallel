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

# Then create the Application Gateway (only if enabled)
# It uses the VM private IP addresses as backend targets
module "application_gateway" {
  count               = var.enable_application_gateway ? 1 : 0
  source              = "./modules/application_gateway" # Path to your application_gateway module
  prefix              = var.prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  subnet_id           = module.virtual_network.appgw_subnet_id # Assign App Gateway to its subnet
  backend_vm_ip_addresses = module.vm.vm_private_ips # Pass VM IPs to the App Gateway backend pool
  tags                = var.default_tags
  # Ensure the Application Gateway is created after the VMs
  depends_on          = [module.vm]
}

