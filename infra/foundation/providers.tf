terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Partial configuration: values come from backend.hcl (local runs)
  # or -backend-config flags (CI). Keeps environment-specific details
  # out of version-controlled code.
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  # Authentication is environment-driven:
  #   CI    -> OIDC via ARM_USE_OIDC / ARM_CLIENT_ID / ARM_TENANT_ID
  #   local -> Azure CLI session (az login)
  # storage_use_azuread lets the provider talk to storage data planes
  # with Entra ID tokens, consistent with shared keys being disabled.
  storage_use_azuread = true
}
