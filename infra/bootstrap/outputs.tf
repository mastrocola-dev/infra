output "state_resource_group" {
  description = "Resource group that hosts the Terraform state backend."
  value       = azurerm_resource_group.tfstate.name
}

output "state_storage_account" {
  description = "Storage account name for the remote state backend."
  value       = azurerm_storage_account.tfstate.name
}

output "state_container" {
  description = "Blob container that stores state files."
  value       = azurerm_storage_container.tfstate.name
}

output "foundation_backend_config" {
  description = "Paste-ready backend config for infra/foundation (backend.hcl)."
  value       = <<-EOT
    resource_group_name  = "${azurerm_resource_group.tfstate.name}"
    storage_account_name = "${azurerm_storage_account.tfstate.name}"
    container_name       = "${azurerm_storage_container.tfstate.name}"
    key                  = "foundation.tfstate"
    use_azuread_auth     = true
  EOT
}
