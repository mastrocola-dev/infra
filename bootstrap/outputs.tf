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

output "tenant_id" {
  description = "Entra tenant ID, for the AZURE_TENANT_ID repository variable."
  value       = data.azurerm_client_config.current.tenant_id
}

output "ci_client_ids" {
  description = "Client ID of each repository identity, for its AZURE_CLIENT_ID repository variable."
  value       = { for repository, identity in azurerm_user_assigned_identity.ci : repository => identity.client_id }
}

output "key_vault_name" {
  description = "Key Vault holding every secret, for the KEY_VAULT_NAME repository variable."
  value       = azurerm_key_vault.main.name
}
