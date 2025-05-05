# Azure Configuration
prefix          = "iykonect-azure-infra"
location        = "West Europe"
vm_size         = "Standard_B2s"
admin_username  = "azure"
# admin_password is provided via GitHub Actions secrets
desired_count   = 1

# Default tags
default_tags = {
  ManagedBy   = "Terraform"
  Project     = "iykonect"
  Environment = "production"
}