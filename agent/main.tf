data "azurerm_resource_group" "portfolio_dev" {
  name = "rg-portfolio-dev"
}

data "azurerm_client_config" "current" {}

data "azurerm_user_assigned_identity" "runtime" {
  for_each            = local.apps
  name                = "id-run-${each.key}"
  resource_group_name = "rg-identity"
}

resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  special = false
}

resource "azurerm_log_analytics_workspace" "agent" {
  name                = "log-agent"
  resource_group_name = data.azurerm_resource_group.portfolio_dev.name
  location            = data.azurerm_resource_group.portfolio_dev.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 1
  tags                = local.tags
}

resource "azurerm_application_insights" "agent" {
  name                = "appi-agent"
  resource_group_name = data.azurerm_resource_group.portfolio_dev.name
  location            = data.azurerm_resource_group.portfolio_dev.location
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.agent.id
  tags                = local.tags
}

locals {
  apps = toset(["api", "worker", "mcp-docs"])

  hostnames = { for app in local.apps : app => "func-${app}-${random_string.suffix.result}.azurewebsites.net" }

  service_bus_settings = {
    ServiceBus__fullyQualifiedNamespace = "${azurerm_servicebus_namespace.agent.name}.servicebus.windows.net"
    ServiceBus__credential              = "managedidentity"
  }

  app_settings = {
    api = merge(local.service_bus_settings, {
      ServiceBus__clientId = data.azurerm_user_assigned_identity.runtime["api"].client_id
      TURNSTILE_SECRET_URI = "https://${var.key_vault_name}.vault.azure.net/secrets/turnstile-secret-key"
    })
    worker = merge(local.service_bus_settings, {
      ServiceBus__clientId  = data.azurerm_user_assigned_identity.runtime["worker"].client_id
      MCP_DOCS_URL          = "https://${local.hostnames["mcp-docs"]}/mcp"
      MCP_DOCS_AUDIENCE     = "api://${var.mcp_docs_client_id}"
      ANTHROPIC_API_KEY_URI = "https://${var.key_vault_name}.vault.azure.net/secrets/anthropic-api-key-runtime"
    })
    mcp-docs = {}
  }

  tags = {
    project     = "mastrocola-dev"
    environment = "dev"
    managed_by  = "terraform"
    layer       = "agent"
  }
}
