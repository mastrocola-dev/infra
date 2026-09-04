output "artifacts_storage_account" {
  description = "Storage account provisioned by the CI pipeline."
  value       = azurerm_storage_account.artifacts.name
}
