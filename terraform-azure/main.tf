resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.default_tags
}

module "virtual_network" {
  source              = "./modules/virtual_network"
  prefix              = var.prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = var.default_tags
}

module "load_balancer" {
  source               = "./modules/load_balancer"
  prefix               = var.prefix
  resource_group_name  = azurerm_resource_group.main.name
  location             = var.location
  subnet_id            = module.virtual_network.subnet_id
  tags                 = var.default_tags
}

module "vm" {
  source               = "./modules/vm"
  prefix               = var.prefix
  resource_group_name  = azurerm_resource_group.main.name
  location             = var.location
  subnet_id            = module.virtual_network.subnet_id
  vm_size              = var.vm_size
  admin_username       = var.admin_username
  admin_password       = var.admin_password
  lb_backend_pool_id   = module.load_balancer.backend_pool_id
  aws_access_key       = var.aws_access_key
  aws_secret_key       = var.aws_secret_key
  aws_region           = var.aws_region
  tags                 = var.default_tags
  desired_count        = var.desired_count
}