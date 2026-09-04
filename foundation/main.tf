data "azurerm_resource_group" "portfolio_dev" {
  name = "rg-portfolio-dev"
}

resource "random_string" "artifacts_suffix" {
  length  = 6
  lower   = true
  upper   = false
  special = false
}

resource "azurerm_storage_account" "artifacts" {
  name                     = "stportfolio${random_string.artifacts_suffix.result}"
  resource_group_name      = data.azurerm_resource_group.portfolio_dev.name
  location                 = data.azurerm_resource_group.portfolio_dev.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Cool"

  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"

  tags = local.tags
}

locals {
  tags = {
    project     = "mastrocola-dev"
    environment = "dev"
    managed_by  = "terraform"
    layer       = "foundation"
  }
}
