# This creates:

# 2 resource groups

# 2 App Service Plans

# 2 Web Apps (containers)

# SQL primary + secondary + failover group

# Front Door routing to both apps

############################################
# RESOURCE GROUPS
############################################

resource "azurerm_resource_group" "rg_primary" {
  name     = local.rg_primary_name
  location = var.primary_location
}

resource "azurerm_resource_group" "rg_secondary" {
  name     = local.rg_secondary_name
  location = var.secondary_location
}

############################################
# APP SERVICE PLANS
############################################

resource "azurerm_service_plan" "asp_primary" {
  name                = local.asp_primary_name
  location            = azurerm_resource_group.rg_primary.location
  resource_group_name = azurerm_resource_group.rg_primary.name
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_service_plan" "asp_secondary" {
  name                = local.asp_secondary_name
  location            = azurerm_resource_group.rg_secondary.location
  resource_group_name = azurerm_resource_group.rg_secondary.name
  os_type             = "Linux"
  sku_name            = "F1"
}

############################################
# WEB APPS
############################################

resource "azurerm_linux_web_app" "app_primary" {
  name                = local.app_primary_name
  location            = azurerm_resource_group.rg_primary.location
  resource_group_name = azurerm_resource_group.rg_primary.name
  service_plan_id     = azurerm_service_plan.asp_primary.id

  https_only = true

  site_config {
    always_on = true

    application_stack {
      docker_image_name   = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      docker_registry_url = "https://mcr.microsoft.com"
    }
  }
}

resource "azurerm_linux_web_app" "app_secondary" {
  name                = local.app_secondary_name
  location            = azurerm_resource_group.rg_secondary.location
  resource_group_name = azurerm_resource_group.rg_secondary.name
  service_plan_id     = azurerm_service_plan.asp_secondary.id

  https_only = true

  site_config {
    always_on = false

    application_stack {
      docker_image_name   = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      docker_registry_url = "https://mcr.microsoft.com"
    }
  }
}

############################################
# SQL PRIMARY
############################################

resource "azurerm_mssql_server" "sql_primary" {
  name                         = local.sql_primary_name
  resource_group_name          = azurerm_resource_group.rg_primary.name
  location                     = azurerm_resource_group.rg_primary.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password
  public_network_access_enabled = true
}

resource "azurerm_mssql_database" "db_primary" {
  name      = local.db_name
  server_id = azurerm_mssql_server.sql_primary.id
  sku_name  = "Basic"
}

############################################
# -----------------------------
# Azure Front Door (Standard/Premium) - azurerm 3.x compatible
# -----------------------------

resource "azurerm_cdn_frontdoor_profile" "afd_profile" {
  name                = "afd-${var.project_name}"
  resource_group_name = azurerm_resource_group.rg_primary.name
  sku_name            = "Standard_AzureFrontDoor"
}

resource "azurerm_cdn_frontdoor_endpoint" "afd_endpoint" {
  name                     = "ep-${var.project_name}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd_profile.id
  enabled                  = true
}

resource "azurerm_cdn_frontdoor_origin_group" "og" {
  name                     = "og-${var.project_name}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd_profile.id

  session_affinity_enabled = false

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    interval_in_seconds = 120
    path                = "/"
    protocol            = "Https"
    request_type        = "GET"
  }
}

resource "azurerm_cdn_frontdoor_origin" "origin_primary" {
  name                          = "origin-primary"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.og.id

  host_name                      = azurerm_linux_web_app.app_primary.default_hostname
  origin_host_header              = azurerm_linux_web_app.app_primary.default_hostname
  http_port                       = 80
  https_port                      = 443
  priority                        = 1
  weight                          = 100
  enabled                         = true
  certificate_name_check_enabled  = true
}

resource "azurerm_cdn_frontdoor_origin" "origin_secondary" {
  name                          = "origin-secondary"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.og.id

  host_name                      = azurerm_linux_web_app.app_secondary.default_hostname
  origin_host_header              = azurerm_linux_web_app.app_secondary.default_hostname
  http_port                       = 80
  https_port                      = 443
  priority                        = 2
  weight                          = 100
  enabled                         = true
  certificate_name_check_enabled  = true
}

resource "azurerm_cdn_frontdoor_route" "route" {
  name                          = "route-${var.project_name}"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.afd_endpoint.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.og.id
  cdn_frontdoor_origin_ids      = [
    azurerm_cdn_frontdoor_origin.origin_primary.id,
    azurerm_cdn_frontdoor_origin.origin_secondary.id
  ]

  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http", "Https"]
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true
  https_redirect_enabled = true
  enabled                = true
}


