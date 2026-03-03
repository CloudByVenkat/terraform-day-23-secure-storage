output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "workspace" {
  description = "Current workspace"
  value       = terraform.workspace
}

output "summary" {
  description = "Deployment summary"
  value = {
    workspace       = terraform.workspace
    resource_group  = azurerm_resource_group.main.name
    storage_account = azurerm_storage_account.main.name
    location        = var.location
  }
}
