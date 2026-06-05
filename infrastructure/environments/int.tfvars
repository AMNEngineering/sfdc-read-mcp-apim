# Int Environment Configuration
# Backend: Salesforce Sandbox

environment         = "int"
apim_name          = "amn-wus2-hub-apim-i02"
apim_resource_group = "amn-wus2-hub-rg-i01"

# Salesforce sandbox
backend_url = "https://api.salesforce.com"

# Salesforce MCP path for sandbox
sfdc_mcp_path = "/platform/mcp/v1/sandbox/platform/sobject-reads"

# Azure AD tenant (AMN Healthcare)
tenant_id = "6232c2ec-fa42-4f27-92cd-787913fba489"

# Entra app registration (to be created by security team)
# Placeholder - replace with actual app ID
sfdc_read_mcp_app_id = "00000000-0000-0000-0000-000000000000"

# Salesforce credentials (from Key Vault or ADO variable group)
# These should be injected at runtime, not committed
sfdc_client_id     = "REPLACE_WITH_SFDC_SANDBOX_CLIENT_ID"
sfdc_client_secret = "REPLACE_WITH_SFDC_SANDBOX_CLIENT_SECRET"
sfdc_token_url     = "https://test.salesforce.com/services/oauth2/token"

# Tags
tags = {
  environment = "int"
  project     = "sfdc-read-mcp-apim"
  managed_by  = "terraform"
  cost_center = "platform-engineering"
}
