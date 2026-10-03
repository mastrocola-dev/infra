locals {
  github_owner = "mastrocola-dev@324597838"

  github_repository_ids = {
    infra = 1355062376
    www   = 1357772879
    docs  = 1356325722
  }

  github_federations = {
    infra-main = { repository = "infra", ref = "ref:refs/heads/main" }
    infra-pr   = { repository = "infra", ref = "pull_request" }
    www-main   = { repository = "www", ref = "ref:refs/heads/main" }
    www-pr     = { repository = "www", ref = "pull_request" }
    docs-pr    = { repository = "docs", ref = "pull_request" }
  }

  principals = merge(
    { for name, identity in azurerm_user_assigned_identity.ci : name => identity.principal_id },
    { for name, identity in azurerm_user_assigned_identity.runtime : "run-${name}" => identity.principal_id },
  )
}

resource "azurerm_resource_group" "identity" {
  name     = "rg-identity"
  location = var.location
  tags     = local.tags
}

resource "azurerm_user_assigned_identity" "ci" {
  for_each            = local.github_repository_ids
  name                = "id-${each.key}"
  resource_group_name = azurerm_resource_group.identity.name
  location            = azurerm_resource_group.identity.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "github" {
  for_each                  = local.github_federations
  name                      = "github-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci[each.value.repository].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${local.github_owner}/${each.value.repository}@${local.github_repository_ids[each.value.repository]}:${each.value.ref}"
}

resource "azurerm_role_definition" "static_web_app_secrets_reader" {
  name        = "Static Web App Secrets Reader"
  scope       = azurerm_resource_group.portfolio_dev.id
  description = "Reads Static Web Apps deployment tokens"

  permissions {
    actions = [
      "Microsoft.Web/staticSites/read",
      "Microsoft.Web/staticSites/listSecrets/action",
    ]
  }

  assignable_scopes = [azurerm_resource_group.portfolio_dev.id]
}

resource "azurerm_role_assignment" "www_static_web_app_secrets" {
  scope              = azurerm_resource_group.portfolio_dev.id
  role_definition_id = azurerm_role_definition.static_web_app_secrets_reader.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.ci["www"].principal_id
  principal_type     = "ServicePrincipal"
}
