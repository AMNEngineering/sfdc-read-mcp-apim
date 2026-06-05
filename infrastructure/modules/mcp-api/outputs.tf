output "api_id" {
  description = "API resource ID"
  value       = azurerm_api_management_api.this.id
}

output "api_name" {
  description = "API name"
  value       = azurerm_api_management_api.this.name
}

output "api_path" {
  description = "API path"
  value       = azurerm_api_management_api.this.path
}

output "api_url" {
  description = "Full API URL"
  value       = "https://${data.azurerm_api_management.apim.gateway_url}/${azurerm_api_management_api.this.path}"
}

output "operation_id" {
  description = "MCP operation ID"
  value       = azurerm_api_management_api_operation.mcp_invoke.operation_id
}
