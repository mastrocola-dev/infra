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

resource "azurerm_role_assignment" "ci_runtime_identity_operator" {
  for_each             = azurerm_user_assigned_identity.runtime
  scope                = each.value.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.ci["infra"].principal_id
  principal_type       = "ServicePrincipal"
}

data "terraform_remote_state" "agent" {
  backend = "azurerm"

  config = {
    resource_group_name  = azurerm_resource_group.tfstate.name
    storage_account_name = azurerm_storage_account.tfstate.name
    container_name       = azurerm_storage_container.tfstate.name
    key                  = "agent.tfstate"
    use_azuread_auth     = true
  }
}

locals {
  agent_storage = { for app, name in data.terraform_remote_state.agent.outputs.storage_accounts : app => "${azurerm_resource_group.portfolio_dev.id}/providers/Microsoft.Storage/storageAccounts/${name}" }
  agent_queues  = { for queue in ["jobs", "events"] : queue => "${azurerm_resource_group.portfolio_dev.id}/providers/Microsoft.ServiceBus/namespaces/${data.terraform_remote_state.agent.outputs.service_bus_namespace}/queues/${queue}" }

  runtime_grants = {
    api-host      = { identity = "api", role = "Storage Blob Data Owner", scope = local.agent_storage["api"] }
    api-state     = { identity = "api", role = "Storage Table Data Contributor", scope = local.agent_storage["api"] }
    api-jobs      = { identity = "api", role = "Azure Service Bus Data Sender", scope = local.agent_queues["jobs"] }
    api-events    = { identity = "api", role = "Azure Service Bus Data Receiver", scope = local.agent_queues["events"] }
    worker-host   = { identity = "worker", role = "Storage Blob Data Owner", scope = local.agent_storage["worker"] }
    worker-jobs   = { identity = "worker", role = "Azure Service Bus Data Receiver", scope = local.agent_queues["jobs"] }
    worker-events = { identity = "worker", role = "Azure Service Bus Data Sender", scope = local.agent_queues["events"] }
    mcp-docs-host = { identity = "mcp-docs", role = "Storage Blob Data Owner", scope = local.agent_storage["mcp-docs"] }
  }
}

resource "azurerm_role_assignment" "runtime" {
  for_each             = local.runtime_grants
  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.runtime[each.value.identity].principal_id
  principal_type       = "ServicePrincipal"
}

locals {
  deployers = {
    service-agent = "worker"
    service-api   = "api"
    docs          = "mcp-docs"
  }

  deploy_grants = merge(
    { for repository, app in local.deployers : "${repository}-app" => { repository = repository, role = "Website Contributor", scope = "${azurerm_resource_group.portfolio_dev.id}/providers/Microsoft.Web/sites/${data.terraform_remote_state.agent.outputs.function_apps[app]}" } },
    { for repository, app in local.deployers : "${repository}-plan" => { repository = repository, role = "Reader", scope = "${azurerm_resource_group.portfolio_dev.id}/providers/Microsoft.Web/serverFarms/asp-${app}" } },
  )
}

resource "azurerm_role_assignment" "ci_deploy" {
  for_each             = local.deploy_grants
  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.ci[each.value.repository].principal_id
  principal_type       = "ServicePrincipal"
}
