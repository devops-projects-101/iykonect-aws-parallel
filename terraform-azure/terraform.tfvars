# Azure Configuration
prefix          = "iykonect-infrastucture"
location        = "West Europe"
vm_size         = "Standard_D4_v4"
admin_username  = "azure"
# admin_password is provided via GitHub Actions secrets
desired_count   = 1
enable_application_gateway = false  # Set to false to disable Application Gateway and point DNS directly to VM

# Default tags
default_tags = {
  ManagedBy   = "DevOps"
  Project     = "iykonect"
  Environment = "production"
  ProvisionedBy  = "Terraform"
}