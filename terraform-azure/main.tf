resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.default_tags
}

# Create Network Watcher in the main resource group instead of letting Azure create NetworkWatcherRG
resource "azurerm_network_watcher" "main" {
  name                = "${var.prefix}-network-watcher"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.default_tags
}

# Create Key Vault for SSH keys
resource "azurerm_key_vault" "main" {
  name                = "iykkv"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id          = var.azure_tenant_id
  sku_name           = "standard"

  purge_protection_enabled    = false
  soft_delete_retention_days = 7

  access_policy {
    tenant_id = var.azure_tenant_id
    object_id = var.azure_client_id

    key_permissions = [
      "Get", "List"
    ]

    secret_permissions = [
      "Get", "List"
    ]
  }

  tags = var.default_tags
}

# Reference existing SSH key
data "azurerm_ssh_public_key" "existing" {
  name                = "common_azure_ssh_key"
  resource_group_name = "iykonect-azure-parallel-rg"
}

module "virtual_network" {
  source              = "./modules/virtual_network"
  prefix              = var.prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = var.default_tags
}

# Create VM first to get IP addresses
module "vm" {
  source               = "./modules/vm"
  prefix               = var.prefix
  resource_group_name  = azurerm_resource_group.main.name
  location             = var.location
  subnet_id            = module.virtual_network.vm_subnet_id
  vm_size              = var.vm_size
  admin_username       = var.admin_username
  admin_password       = var.admin_password
  aws_access_key       = var.aws_access_key
  aws_secret_key       = var.aws_secret_key
  aws_region           = var.aws_region
  admin_ssh_key        = data.azurerm_ssh_public_key.existing.public_key
  tags                 = var.default_tags
  desired_count        = var.desired_count
}

# Then create Application Gateway with VM IP addresses
module "application_gateway" {
  source               = "./modules/application_gateway"
  prefix               = var.prefix
  resource_group_name  = azurerm_resource_group.main.name
  location             = var.location
  subnet_id            = module.virtual_network.appgw_subnet_id
  backend_vm_ip_addresses = module.vm.vm_private_ips
  tags                 = var.default_tags
  depends_on           = [module.vm]
}

# Consolidated DNS zone and delegation for parallel subdomain
data "azurerm_dns_zone" "parent" {
  name                = var.parent_dns_zone_name
  resource_group_name = var.parent_dns_zone_resource_group
}

resource "azurerm_dns_zone" "parallel" {
  name                = "parallel.${var.parent_dns_zone_name}"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.default_tags
}

resource "azurerm_dns_ns_record" "parallel_delegation" {
  name                = "parallel"
  zone_name           = data.azurerm_dns_zone.parent.name
  resource_group_name = data.azurerm_dns_zone.parent.resource_group_name
  ttl                 = 300
  records             = azurerm_dns_zone.parallel.name_servers
}