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
# FRONT DOOR
############################################

resource "azurerm_cdn_frontdoor_profile" "afd_profile" {
  name                = local.afd_profile_name
  resource_group_name = azurerm_resource_group.rg_primary.name
  sku_name            = "Standard_AzureFrontDoor"
}

resource "time_sleep" "wait_for_afd_profile" {
  depends_on      = [azurerm_cdn_frontdoor_profile.afd_profile]
  create_duration = "60s"
}

resource "azurerm_cdn_frontdoor_endpoint" "afd_endpoint" {
  depends_on = [time_sleep.wait_for_afd_profile]
  name       = local.afd_endpoint_name
  profile_id = azurerm_cdn_frontdoor_profile.afd_profile.id
}

resource "azurerm_cdn_frontdoor_origin_group" "og" {
  depends_on = [azurerm_cdn_frontdoor_endpoint.afd_endpoint]
  name       = local.og_name
  profile_id = azurerm_cdn_frontdoor_profile.afd_profile.id

  health_probe {
    interval_in_seconds = 60
    path                = "/"
    protocol            = "Https"
    request_type        = "GET"
  }

  load_balancing {
    additional_latency_in_milliseconds = 0
    sample_size                        = 4
    successful_samples_required        = 3
  }
}

resource "azurerm_cdn_frontdoor_origin" "origin_primary" {
  name                           = "origin-primary"
  origin_group_id                = azurerm_cdn_frontdoor_origin_group.og.id
  enabled                        = true
  host_name                      = azurerm_linux_web_app.app_primary.default_hostname
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = azurerm_linux_web_app.app_primary.default_hostname
  certificate_name_check_enabled = true
  priority                       = 1
  weight                         = 1000
}

resource "azurerm_cdn_frontdoor_origin" "origin_secondary" {
  name                           = "origin-secondary"
  origin_group_id                = azurerm_cdn_frontdoor_origin_group.og.id
  enabled                        = true
  host_name                      = azurerm_linux_web_app.app_secondary.default_hostname
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = azurerm_linux_web_app.app_secondary.default_hostname
  certificate_name_check_enabled = true
  priority                       = 2
  weight                         = 1000
}

resource "azurerm_cdn_frontdoor_route" "route" {
  name                   = "route-${var.project}-${local.suffix}"
  endpoint_id            = azurerm_cdn_frontdoor_endpoint.afd_endpoint.id
  origin_group_id        = azurerm_cdn_frontdoor_origin_group.og.id
  origin_ids             = [
    azurerm_cdn_frontdoor_origin.origin_primary.id,
    azurerm_cdn_frontdoor_origin.origin_secondary.id
  ]
  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true
  https_redirect_enabled = true
}
