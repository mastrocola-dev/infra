locals {
  api_hostname = "api.${var.domain}"
  key_vault_id = lower("/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/rg-identity/providers/Microsoft.KeyVault/vaults/${var.key_vault_name}")

  cloudflare_cidrs = concat(
    sort(data.cloudflare_ip_ranges.cloudflare.ipv4_cidrs),
    sort(data.cloudflare_ip_ranges.cloudflare.ipv6_cidrs),
  )
}

data "cloudflare_ip_ranges" "cloudflare" {}

resource "cloudflare_dns_record" "api_verification" {
  zone_id = var.cloudflare_zone_id
  name    = "asuid.${local.api_hostname}"
  type    = "TXT"
  content = "\"${azurerm_function_app_flex_consumption.app["api"].custom_domain_verification_id}\""
  ttl     = 1
}

resource "azapi_resource" "origin_certificate" {
  type                      = "Microsoft.Web/sites/certificates@2024-11-01"
  name                      = "origin-api"
  parent_id                 = azurerm_function_app_flex_consumption.app["api"].id
  location                  = data.azurerm_resource_group.portfolio_dev.location
  schema_validation_enabled = false
  response_export_values    = ["properties.thumbprint"]

  body = {
    properties = {
      keyVaultId         = local.key_vault_id
      keyVaultSecretName = "origin-api"
    }
  }
}

resource "azurerm_app_service_custom_hostname_binding" "api" {
  hostname            = local.api_hostname
  app_service_name    = azurerm_function_app_flex_consumption.app["api"].name
  resource_group_name = data.azurerm_resource_group.portfolio_dev.name
  ssl_state           = "SniEnabled"
  thumbprint          = azapi_resource.origin_certificate.output.properties.thumbprint

  depends_on = [cloudflare_dns_record.api_verification]
}

resource "cloudflare_zone_setting" "ssl" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "ssl"
  value      = "strict"
}

resource "cloudflare_dns_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = local.api_hostname
  type    = "CNAME"
  content = azurerm_function_app_flex_consumption.app["api"].default_hostname
  proxied = true
  ttl     = 1

  depends_on = [
    azurerm_app_service_custom_hostname_binding.api,
    cloudflare_zone_setting.ssl,
  ]
}

resource "cloudflare_ruleset" "rate_limit" {
  zone_id = var.cloudflare_zone_id
  name    = "rate limit"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [
    {
      description = "api requests per address"
      expression  = "starts_with(http.request.uri.path, \"/\")"
      action      = "block"

      ratelimit = {
        characteristics     = ["ip.src", "cf.colo.id"]
        period              = 10
        requests_per_period = 20
        mitigation_timeout  = 10
      }
    }
  ]
}
