resource "azurerm_servicebus_namespace" "agent" {
  name                = "sb-agent-${random_string.suffix.result}"
  resource_group_name = data.azurerm_resource_group.portfolio_dev.name
  location            = data.azurerm_resource_group.portfolio_dev.location
  sku                 = "Basic"
  local_auth_enabled  = false
  minimum_tls_version = "1.2"
  tags                = local.tags
}

resource "azurerm_servicebus_queue" "jobs" {
  name                = "jobs"
  namespace_id        = azurerm_servicebus_namespace.agent.id
  max_delivery_count  = 2
  default_message_ttl = "PT10M"
}

resource "azurerm_servicebus_queue" "events" {
  name                = "events"
  namespace_id        = azurerm_servicebus_namespace.agent.id
  default_message_ttl = "PT1H"
}
