data "azurerm_resource_group" "portfolio_dev" {
  name = "rg-portfolio-dev"
}

import {
  to = azurerm_static_web_app_custom_domain.www
  id = "${azurerm_static_web_app.www.id}/customDomains/www.${var.domain}"
}

resource "azurerm_static_web_app" "www" {
  name                = "stapp-portfolio-www"
  resource_group_name = data.azurerm_resource_group.portfolio_dev.name
  location            = "eastus2"
  sku_tier            = "Free"
  sku_size            = "Free"

  tags = local.tags

  lifecycle {
    ignore_changes = [repository_url, repository_branch]
  }
}

resource "azurerm_static_web_app_custom_domain" "apex" {
  static_web_app_id = azurerm_static_web_app.www.id
  domain_name       = var.domain
  validation_type   = "dns-txt-token"
}

resource "azurerm_static_web_app_custom_domain" "www" {
  static_web_app_id = azurerm_static_web_app.www.id
  domain_name       = "www.${var.domain}"
  validation_type   = "cname-delegation"

  depends_on = [cloudflare_dns_record.www]

  lifecycle {
    ignore_changes = [validation_type]
  }
}

resource "cloudflare_dns_record" "apex" {
  zone_id = var.cloudflare_zone_id
  name    = var.domain
  type    = "CNAME"
  content = azurerm_static_web_app.www.default_host_name
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "www" {
  zone_id = var.cloudflare_zone_id
  name    = "www.${var.domain}"
  type    = "CNAME"
  content = azurerm_static_web_app.www.default_host_name
  proxied = false
  ttl     = 1
}

locals {
  tags = {
    project     = "mastrocola-dev"
    environment = "dev"
    managed_by  = "terraform"
    layer       = "site"
  }
}
