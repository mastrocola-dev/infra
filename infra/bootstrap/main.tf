# ------------------------------------------------------------------
# Bootstrap layer — run ONCE, locally, authenticated as a human Owner
# (az login with marcio@mastrocola.dev).
#
# Solves the chicken-and-egg problem: the remote state backend cannot
# provision itself, and the CI identity must not have the privileges
# required to create it. State for this layer is intentionally local.
# ------------------------------------------------------------------

terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    storage {
      data_plane_available = false
    }
  }
  storage_use_azuread = true
  subscription_id = var.subscription_id
}

data "azurerm_client_config" "current" {}

# The CI/CD identity (app registration created during initial setup).
data "azuread_service_principal" "github_actions" {
  display_name = var.github_app_display_name
}

# ------------------------------------------------------------------
# Resource groups
# ------------------------------------------------------------------

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-tfstate"
  location = var.location
  tags     = local.tags
}

# Created manually via the portal during initial setup — adopted here
# with an import block so it becomes managed by code (Terraform >= 1.7).
import {
  to = azurerm_resource_group.portfolio_dev
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-portfolio-dev"
}

resource "azurerm_resource_group" "portfolio_dev" {
  name     = "rg-portfolio-dev"
  location = var.location
  tags     = local.tags
}

# ------------------------------------------------------------------
# Remote state backend
# ------------------------------------------------------------------

resource "random_string" "state_suffix" {
  length  = 6
  lower   = true
  upper   = false
  special = false
}

resource "azurerm_storage_account" "tfstate" {
  name                     = "sttfstate${random_string.state_suffix.result}"
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Security posture: Entra ID auth only, no shared keys, no public blobs.
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"

  blob_properties {
    versioning_enabled = true # point-in-time recovery for state files

    delete_retention_policy {
      days = 14
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "tfstate" {
  name               = "tfstate"
  storage_account_id = azurerm_storage_account.tfstate.id
}

# ------------------------------------------------------------------
# RBAC — least privilege, data plane only where possible
# ------------------------------------------------------------------

# CI identity: read/write state blobs, nothing else on this account.
resource "azurerm_role_assignment" "ci_state_blob" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azuread_service_principal.github_actions.object_id
}

# Human operator: same data-plane role (shared keys are disabled, so
# even Owners need an explicit data role to touch blobs).
resource "azurerm_role_assignment" "operator_state_blob" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# CI identity: Contributor scoped to the workload resource group only.
# This assignment already exists (created via portal); import it before
# the first apply — see README for the one-liner.
resource "azurerm_role_assignment" "ci_workload_contributor" {
  scope                = azurerm_resource_group.portfolio_dev.id
  role_definition_name = "Contributor"
  principal_id         = data.azuread_service_principal.github_actions.object_id
}

# ------------------------------------------------------------------
# Cost guardrail
# ------------------------------------------------------------------

resource "azurerm_consumption_budget_subscription" "monthly" {
  name            = "budget-monthly"
  subscription_id = "/subscriptions/${var.subscription_id}"
  amount          = var.monthly_budget_amount
  time_grain      = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      enabled        = true
      operator       = "GreaterThanOrEqualTo"
      threshold      = notification.value
      contact_emails = [var.notification_email]
    }
  }

  notification {
    enabled        = true
    operator       = "GreaterThanOrEqualTo"
    threshold      = 100
    threshold_type = "Forecasted"
    contact_emails = [var.notification_email]
  }
}

locals {
  tags = {
    project     = "portfolio"
    environment = "dev"
    managed_by  = "terraform"
    layer       = "bootstrap"
  }
}
