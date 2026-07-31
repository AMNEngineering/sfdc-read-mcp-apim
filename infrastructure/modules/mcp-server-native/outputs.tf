output "mcp_server_id" {
  description = "The ID of the MCP server"
  value       = azapi_resource.mcp_server.id
}

output "mcp_server_name" {
  description = "The name of the MCP server"
  value       = azapi_resource.mcp_server.name
}

output "mcp_server_url" {
  description = "The full URL to access the MCP server"
  value       = "https://${data.azurerm_api_management.apim.gateway_url}/${var.base_path}/mcp"
}
