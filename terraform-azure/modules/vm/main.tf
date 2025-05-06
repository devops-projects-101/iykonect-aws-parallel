resource "azurerm_public_ip" "vm" {
  count               = var.desired_count
  name                = "${var.prefix}-vm-pip-${count.index}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "main" {
  count               = var.desired_count
  name                = "${var.prefix}-nic-${count.index}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm[count.index].id
  }
}

# Remove the backend address pool association since it's incompatible with Application Gateway
# We will manually register the VM's IP with the Application Gateway instead

# Create a managed identity for VM access to Azure resources
resource "azurerm_user_assigned_identity" "vm_identity" {
  name                = "${var.prefix}-vm-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Comment out the role assignment since our service principal doesn't have permission
# to create role assignments. Instead, we'll use a different approach for storage access.
# NOTE: You'll need to manually assign this role in Azure Portal or via Azure CLI if you need
# this functionality, or use a service principal with more permissions.
/*
resource "azurerm_role_assignment" "storage_blob_reader" {
  scope                = "${var.storage_account_id}/blobServices/default/containers/${var.storage_container_name}"
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.vm_identity.principal_id
}
*/

resource "azurerm_linux_virtual_machine" "main" {
  count                 = var.desired_count
  name                  = "${var.prefix}-vm-${count.index}"
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  disable_password_authentication = false
  network_interface_ids = [azurerm_network_interface.main[count.index].id]
  tags                  = var.tags

  # Assign the managed identity to the VM
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.vm_identity.id]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 50
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(
    templatefile("${path.module}/user-data.sh", {
      admin_username = var.admin_username
      aws_access_key = var.aws_access_key
      aws_secret_key = var.aws_secret_key
      aws_region     = var.aws_region
      storage_account_name = var.storage_account_name
      storage_container_name = var.storage_container_name
      storage_blob_name = var.storage_blob_name
    })
  )
}