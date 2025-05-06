resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.default_tags
}

# Create Storage Account for VM configuration values
resource "azurerm_storage_account" "config" {
  name                     = "iykonectazureblob"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.default_tags
}

# Create Storage Container for VM configuration
resource "azurerm_storage_container" "config" {
  name                  = "vm-config"
  storage_account_name  = azurerm_storage_account.config.name
  container_access_type = "private"
}

# Create Blob with VM configuration data
resource "azurerm_storage_blob" "vm_config" {
  name                   = "vm-config.json"
  storage_account_name   = azurerm_storage_account.config.name
  storage_container_name = azurerm_storage_container.config.name
  type                   = "Block"
  source_content         = jsonencode({
    aws_access_key = var.aws_access_key,
    aws_secret_key = var.aws_secret_key,
    aws_region     = var.aws_region,
    admin_username = var.admin_username,
    app_name       = "${var.prefix}-app"
  })
  
  # Explicit dependency on the container to ensure it exists before creating the blob
  depends_on = [azurerm_storage_container.config]
}

# Create Network Watcher in the main resource group instead of letting Azure create NetworkWatcherRG
resource "azurerm_network_watcher" "main" {
  name                = "${var.prefix}-network-watcher"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.default_tags
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
  vm_size              = "Standard_D4s_v3"  # 4 vCPUs, 16 GB RAM
  admin_username       = var.admin_username
  admin_password       = var.admin_password
  aws_access_key       = var.aws_access_key
  aws_secret_key       = var.aws_secret_key
  aws_region           = var.aws_region
  tags                 = var.default_tags
  desired_count        = var.desired_count

  storage_account_id     = azurerm_storage_account.config.id
  storage_account_name   = azurerm_storage_account.config.name
  storage_container_name = azurerm_storage_container.config.name
  storage_blob_name      = azurerm_storage_blob.vm_config.name
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