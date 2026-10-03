locals {
  secret_readers = {
    cloudflare-api-token      = "infra"
    anthropic-api-key-ci      = "docs"
    anthropic-api-key-runtime = "run-worker"
    turnstile-secret-key      = "run-api"
  }
}

resource "azurerm_key_vault" "main" {
  name                       = "kv-mastrocola-dev"
  resource_group_name        = azurerm_resource_group.identity.name
  location                   = azurerm_resource_group.identity.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = local.tags
}

resource "azurerm_role_assignment" "operator_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "operator_secrets_propagation" {
  depends_on      = [azurerm_role_assignment.operator_secrets]
  create_duration = "90s"
}

resource "azurerm_key_vault_secret" "managed" {
  for_each         = local.secret_readers
  name             = each.key
  key_vault_id     = azurerm_key_vault.main.id
  value_wo         = "unset"
  value_wo_version = 1
  depends_on       = [time_sleep.operator_secrets_propagation]

  lifecycle {
    ignore_changes = [expiration_date, tags]
  }
}

resource "azurerm_role_assignment" "secret_reader" {
  for_each             = local.secret_readers
  scope                = azurerm_key_vault_secret.managed[each.key].resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = local.principals[each.value]
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "infra_secret_metadata" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Reader"
  principal_id         = azurerm_user_assigned_identity.ci["infra"].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "operator_certificates" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "operator_certificates_propagation" {
  depends_on      = [azurerm_role_assignment.operator_certificates]
  create_duration = "90s"
}

resource "azurerm_key_vault_certificate" "origin_api" {
  name         = "origin-api"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [time_sleep.operator_certificates_propagation]

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = false
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      key_usage          = ["digitalSignature", "keyEncipherment"]
      subject            = "CN=api.mastrocola.dev"
      validity_in_months = 12
    }
  }

  lifecycle {
    ignore_changes = [certificate_policy]
  }
}

data "azuread_service_principal" "app_service" {
  client_id = "abfa0a7c-a6b6-4736-8310-5855508787cd"
}

resource "azurerm_role_assignment" "app_service_origin_certificate" {
  for_each = {
    certificate = azurerm_key_vault_certificate.origin_api.resource_manager_versionless_id
    secret      = "${azurerm_key_vault.main.id}/secrets/${azurerm_key_vault_certificate.origin_api.name}"
  }
  scope                = each.value
  role_definition_name = "Key Vault Certificate User"
  principal_id         = data.azuread_service_principal.app_service.object_id
  principal_type       = "ServicePrincipal"
}
