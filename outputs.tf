output "primary_app_url" {
  value = "https://${azurerm_linux_web_app.app_primary.default_hostname}"
}

output "secondary_app_url" {
  value = "https://${azurerm_linux_web_app.app_secondary.default_hostname}"
}

output "front_door_url" {
  value = "https://${azurerm_cdn_frontdoor_endpoint.afd_endpoint.host_name}"
}

output "sql_failover_group_listener" {
  value = azurerm_mssql_failover_group.fg.read_write_endpoint_failover_policy[0].mode
  description = "Failover group created; connect apps to the FG listener (shown in Azure portal under failover group)."
}

