output "apim_mcp_endpoint" {
  description = "Full APIM MCP endpoint URL"
  value       = module.mcp_api.api_url
}

output "api_id" {
  description = "APIM API resource ID"
  value       = module.mcp_api.api_id
}

output "api_name" {
  description = "APIM API name"
  value       = module.mcp_api.api_name
}

output "api_path" {
  description = "API path"
  value       = module.mcp_api.api_path
}

output "backend_id" {
  description = "Backend resource ID"
  value       = module.backend_pool.backend_id
}

output "backend_name" {
  description = "Backend name"
  value       = module.backend_pool.backend_name
}

output "pool_name" {
  description = "Backend pool name (for policy reference)"
  value       = module.backend_pool.pool_name
}

output "backend_url" {
  description = "Backend URL"
  value       = module.backend_pool.backend_url
}

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

output "next_steps" {
  description = "Post-deployment instructions"
  value       = <<-EOT
    ✅ Deployment complete for ${var.environment} environment

    📋 Next Steps:
    1. Verify named values in APIM portal
    2. Test JWT authentication with: az account get-access-token --resource api://${var.sfdc_read_mcp_app_id}
    3. Run test suite: ./test-harness/Invoke-SfdcReadTest.ps1 -Environment ${var.environment}
    4. MCP endpoint: ${module.mcp_api.api_url}

    🔐 Security:
    - Entra JWT validation: ✅
    - Rate limiting: 300 req/min per user
    - Audit logging: x-correlation-id in all requests

    📊 Monitor:
    - APIM Application Insights for request logs
    - Backend: ${module.backend_pool.backend_url}
  EOT
}
