# Dev Environment Configuration
# Backend: Mock Salesforce MCP server (localhost)

environment         = "dev"
apim_name           = "amn-wus2-hub-apim-d02"
apim_resource_group = "amn-wus2-hub-rg-d01"

# Mock backend (local PowerShell server)
backend_url = "http://localhost:8080"

# Salesforce MCP path for mock
sfdc_mcp_path = "/platform/mcp/v1/platform/sobject-reads"

# Azure AD tenant (AMN Healthcare)
tenant_id = "6232c2ec-fa42-4f27-92cd-787913fba489"

# Entra app registration: SFDC Read MCP Reader Dev
sfdc_read_mcp_app_id = "6ce6ccb1-32db-40f8-97b5-bfbe700d052e"

# Mock Salesforce credentials (any value works for dev mock)
sfdc_client_id     = "mock-client-id"
sfdc_client_secret = "mock-client-secret"
sfdc_token_url     = "http://localhost:8080/oauth/token"

# Tags
tags = {
  environment = "dev"
  project     = "sfdc-read-mcp-apim"
  managed_by  = "terraform"
  cost_center = "platform-engineering"
}
