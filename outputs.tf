output "primary_app_url" {
  value = "https://${azurerm_linux_web_app.app_primary.default_hostname}"
}

output "secondary_app_url" {
  value = "https://${azurerm_linux_web_app.app_secondary.default_hostname}"
}

output "frontdoor_url" {
  value = "https://${azurerm_cdn_frontdoor_endpoint.afd_endpoint.host_name}"
}

output "sql_primary_server" {
  value = azurerm_mssql_server.sql_primary.fully_qualified_domain_name
}
