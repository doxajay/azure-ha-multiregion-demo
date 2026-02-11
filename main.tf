# This creates:

# 2 resource groups

# 2 App Service Plans

# 2 Web Apps (containers)

# SQL primary + secondary + failover group

# Front Door routing to both apps

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  suffix = random_string.suffix.result
}

# -------------------------
# Resource Groups (2 regions)
# -------------------------
resource "azurerm_resource_group" "rg_primary" {
  name     = "rg-fcha-ha-${local.suffix}-p"
  location = var.primary_region
}

resource "azurerm_resource_group" "rg_secondary" {
  name     = "rg-fcha-ha-${local.suffix}-s"
  location = var.secondary_region
}

# -------------------------
# App Service Plans
# -------------------------
resource "azurerm_service_plan" "asp_primary" {
  name                = "asp-fcha-${local.suffix}-p"
  resource_group_name = azurerm_resource_group.rg_primary.name
  location            = azurerm_resource_group.rg_primary.location
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_service_plan" "asp_secondary" {
  name                = "asp-fcha-${local.suffix}-s"
  resource_group_name = azurerm_resource_group.rg_secondary.name
  location            = azurerm_resource_group.rg_secondary.location
  os_type             = "Linux"
  sku_name            = "B1"
}

# -------------------------
# Web Apps (Container-based demo app)
# -------------------------
resource "azurerm_linux_web_app" "app_primary" {
  name                = "app-fcha-${local.suffix}-p"
  resource_group_name = azurerm_resource_group.rg_primary.name
  location            = azurerm_resource_group.rg_primary.location
  service_plan_id     = azurerm_service_plan.asp_primary.id

  site_config {
    application_stack {
      docker_image_name   = "traefik/whoami:latest"
      docker_registry_url = "https://index.docker.io"
    }
  }

  app_settings = {
    WEBSITES_PORT = "80"
  }
}

resource "azurerm_linux_web_app" "app_secondary" {
  name                = "app-fcha-${local.suffix}-s"
  resource_group_name = azurerm_resource_group.rg_secondary.name
  location            = azurerm_resource_group.rg_secondary.location
  service_plan_id     = azurerm_service_plan.asp_secondary.id

  site_config {
    application_stack {
      docker_image_name   = "traefik/whoami:latest"
      docker_registry_url = "https://index.docker.io"
    }
  }

  app_settings = {
    WEBSITES_PORT = "80"
  }
}

# -------------------------
# Azure SQL Primary + Secondary + Failover Group
# -------------------------
resource "azurerm_mssql_server" "sql_primary" {
  name                         = "sqlfcha${local.suffix}p"
  resource_group_name          = azurerm_resource_group.rg_primary.name
  location                     = azurerm_resource_group.rg_primary.location
  version                      = "12.0"
  administrator_login          = "sqladminuser"
  administrator_login_password = "ChangeMe!123456789"
}

resource "azurerm_mssql_server" "sql_secondary" {
  name                         = "sqlfcha${local.suffix}s"
  resource_group_name          = azurerm_resource_group.rg_secondary.name
  location                     = azurerm_resource_group.rg_secondary.location
  version                      = "12.0"
  administrator_login          = azurerm_mssql_server.sql_primary.administrator_login
  administrator_login_password = azurerm_mssql_server.sql_primary.administrator_login_password
}

resource "azurerm_mssql_database" "db_primary" {
  name      = "sqldb-fcha-${local.suffix}"
  server_id = azurerm_mssql_server.sql_primary.id
  sku_name  = "Basic"
}

resource "azurerm_mssql_failover_group" "fg" {
  name      = "fg-fcha-${local.suffix}"
  server_id = azurerm_mssql_server.sql_primary.id
  databases = [azurerm_mssql_database.db_primary.id]

  partner_server {
    id = azurerm_mssql_server.sql_secondary.id
  }

  read_write_endpoint_failover_policy {
    mode          = "Automatic"
    grace_minutes = 60
  }
}

# -------------------------
# Azure Front Door (Standard)
# -------------------------
resource "azurerm_cdn_frontdoor_profile" "afd_profile" {
  name                = "afd-fcha-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg_primary.name
  sku_name            = "Standard_AzureFrontDoor"
}

resource "azurerm_cdn_frontdoor_endpoint" "afd_endpoint" {
  name                     = "ep-fcha-${local.suffix}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd_profile.id
}

resource "azurerm_cdn_frontdoor_origin_group" "og" {
  name                     = "og-fcha-${local.suffix}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd_profile.id

  health_probe {
    interval_in_seconds = 30
    path                = "/"
    protocol            = "Https"
    request_type        = "GET"
  }

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }
}

resource "azurerm_cdn_frontdoor_origin" "origin_primary" {
  name                          = "origin-primary"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.og.id
  enabled                       = true

  host_name          = azurerm_linux_web_app.app_primary.default_hostname
  http_port          = 80
  https_port         = 443
  origin_host_header = azurerm_linux_web_app.app_primary.default_hostname

  certificate_name_check_enabled = true

  priority = 1
  weight   = 50
}

resource "azurerm_cdn_frontdoor_origin" "origin_secondary" {
  name                          = "origin-secondary"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.og.id
  enabled                       = true

  host_name          = azurerm_linux_web_app.app_secondary.default_hostname
  http_port          = 80
  https_port         = 443
  origin_host_header = azurerm_linux_web_app.app_secondary.default_hostname

  certificate_name_check_enabled = true

  priority = 1
  weight   = 50
}

resource "azurerm_cdn_frontdoor_route" "route" {
  name                          = "route-all"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.afd_endpoint.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.og.id
  cdn_frontdoor_origin_ids = [
    azurerm_cdn_frontdoor_origin.origin_primary.id,
    azurerm_cdn_frontdoor_origin.origin_secondary.id
  ]

  patterns_to_match      = ["/*"]
  supported_protocols    = ["Https"]
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = false
  link_to_default_domain = true
}

