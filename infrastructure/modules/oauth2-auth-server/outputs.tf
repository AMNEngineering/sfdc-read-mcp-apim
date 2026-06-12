output "name" {
  description = "Auth server name (empty when disabled)"
  value       = length(azurerm_api_management_authorization_server.this) > 0 ? azurerm_api_management_authorization_server.this[0].name : ""
}

output "enabled" {
  description = "Whether the auth server was created"
  value       = length(azurerm_api_management_authorization_server.this) > 0
}

output "default_scope" {
  description = "Default scope advertised by the auth server"
  value       = length(azurerm_api_management_authorization_server.this) > 0 ? azurerm_api_management_authorization_server.this[0].default_scope : ""
}
