data "azurerm_resource_group" "portfolio_dev" {
  name = "rg-portfolio-dev"
}

resource "azurerm_static_web_app" "www" {
  name                = "stapp-portfolio-www"
  resource_group_name = data.azurerm_resource_group.portfolio_dev.name
  location            = "eastus2"
  sku_tier            = "Free"
  sku_size            = "Free"

  tags = local.tags
}

resource "azurerm_static_web_app_custom_domain" "apex" {
  static_web_app_id = azurerm_static_web_app.www.id
  domain_name       = var.domain
  validation_type   = "dns-txt-token"
}

resource "cloudflare_dns_record" "apex_validation" {
  zone_id = var.cloudflare_zone_id
  name    = var.domain
  type    = "TXT"
  content = azurerm_static_web_app_custom_domain.apex.validation_token
  ttl     = 1
}

resource "cloudflare_dns_record" "apex" {
  zone_id = var.cloudflare_zone_id
  name    = var.domain
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
