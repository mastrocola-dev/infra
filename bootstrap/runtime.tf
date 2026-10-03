locals {
  runtime_identities = toset(["api", "worker", "mcp-docs"])
}

resource "azurerm_user_assigned_identity" "runtime" {
  for_each            = local.runtime_identities
  name                = "id-run-${each.key}"
  resource_group_name = azurerm_resource_group.identity.name
  location            = azurerm_resource_group.identity.location
  tags                = local.tags
}

resource "azuread_application_registration" "mcp_docs" {
  display_name                   = "mcp-docs"
  description                    = "Token audience of the mcp-docs function app. Holds no credentials."
  sign_in_audience               = "AzureADMyOrg"
  requested_access_token_version = 2
}

resource "azuread_application_identifier_uri" "mcp_docs" {
  application_id = azuread_application_registration.mcp_docs.id
  identifier_uri = "api://${azuread_application_registration.mcp_docs.client_id}"
}

resource "azuread_service_principal" "mcp_docs" {
  client_id = azuread_application_registration.mcp_docs.client_id
}
