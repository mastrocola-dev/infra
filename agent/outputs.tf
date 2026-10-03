output "function_apps" {
  value = { for app, resource in azurerm_function_app_flex_consumption.app : app => resource.name }
}

output "hostnames" {
  value = { for app, resource in azurerm_function_app_flex_consumption.app : app => resource.default_hostname }
}

output "storage_accounts" {
  value = { for app, resource in azurerm_storage_account.app : app => resource.name }
}

output "service_bus_namespace" {
  value = azurerm_servicebus_namespace.agent.name
}
