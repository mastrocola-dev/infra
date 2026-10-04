resource "azurerm_storage_account" "app" {
  for_each                 = local.apps
  name                     = "st${replace(each.key, "-", "")}${random_string.suffix.result}"
  resource_group_name      = data.azurerm_resource_group.portfolio_dev.name
  location                 = data.azurerm_resource_group.portfolio_dev.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"

  tags = local.tags
}

resource "azurerm_storage_container" "deployments" {
  for_each           = local.apps
  name               = "deployments"
  storage_account_id = azurerm_storage_account.app[each.key].id
}

resource "azurerm_service_plan" "app" {
  for_each            = local.apps
  name                = "asp-${each.key}"
  resource_group_name = data.azurerm_resource_group.portfolio_dev.name
  location            = data.azurerm_resource_group.portfolio_dev.location
  os_type             = "Linux"
  sku_name            = "FC1"
  tags                = local.tags
}

resource "azurerm_function_app_flex_consumption" "app" {
  for_each            = local.apps
  name                = "func-${each.key}-${random_string.suffix.result}"
  resource_group_name = data.azurerm_resource_group.portfolio_dev.name
  location            = data.azurerm_resource_group.portfolio_dev.location
  service_plan_id     = azurerm_service_plan.app[each.key].id

  storage_container_type            = "blobContainer"
  storage_container_endpoint        = "${azurerm_storage_account.app[each.key].primary_blob_endpoint}${azurerm_storage_container.deployments[each.key].name}"
  storage_authentication_type       = "UserAssignedIdentity"
  storage_user_assigned_identity_id = data.azurerm_user_assigned_identity.runtime[each.key].id

  runtime_name           = "node"
  runtime_version        = "24"
  maximum_instance_count = 2
  instance_memory_in_mb  = 512
  https_only             = true

  app_settings = merge(local.app_settings[each.key], {
    AZURE_CLIENT_ID                  = data.azurerm_user_assigned_identity.runtime[each.key].client_id
    AzureWebJobsStorage__accountName = azurerm_storage_account.app[each.key].name
    AzureWebJobsStorage__credential  = "managedidentity"
    AzureWebJobsStorage__clientId    = data.azurerm_user_assigned_identity.runtime[each.key].client_id
  })

  identity {
    type         = "UserAssigned"
    identity_ids = [data.azurerm_user_assigned_identity.runtime[each.key].id]
  }

  site_config {
    application_insights_connection_string = azurerm_application_insights.agent.connection_string

    dynamic "cors" {
      for_each = each.key == "api" ? [var.site_origins] : []

      content {
        allowed_origins = cors.value
      }
    }
  }

  dynamic "auth_settings_v2" {
    for_each = each.key == "mcp-docs" ? [var.mcp_docs_client_id] : []

    content {
      auth_enabled           = true
      require_authentication = true
      unauthenticated_action = "Return401"

      active_directory_v2 {
        client_id            = auth_settings_v2.value
        tenant_auth_endpoint = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0/"
        allowed_audiences    = [auth_settings_v2.value, "api://${auth_settings_v2.value}"]
        allowed_applications = [data.azurerm_user_assigned_identity.runtime["worker"].client_id]
      }

      login {}
    }
  }

  tags = local.tags
}
