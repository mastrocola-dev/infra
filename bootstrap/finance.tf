resource "azurerm_resource_group" "finance_dev" {
  name     = "rg-finance-dev"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_container" "tfstate_finance" {
  name               = "tfstate-finance"
  storage_account_id = azurerm_storage_account.tfstate.id
}

resource "azurerm_role_assignment" "finance_state_blob" {
  scope                = azurerm_storage_container.tfstate_finance.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.ci["finance"].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "finance_workload_contributor" {
  scope                = azurerm_resource_group.finance_dev.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.ci["finance"].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "finance_runtime_identity_operator" {
  scope                = azurerm_user_assigned_identity.runtime["finance"].id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.ci["finance"].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "finance_db_password_reader" {
  scope                = azurerm_key_vault_secret.managed["finance-db-password"].resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.ci["finance"].principal_id
  principal_type       = "ServicePrincipal"
}
