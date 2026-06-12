# Int Environment Configuration
# Backend: Salesforce Sandbox via Key Vault credentials

environment         = "int"
apim_name           = "amn-wus2-hub-apim-i02"
apim_resource_group = "amn-wus2-hub-rg-i01"

# Salesforce sandbox MCP endpoint
backend_url = "https://api.salesforce.com"

# Salesforce MCP path for sandbox
sfdc_mcp_path = "/platform/mcp/v1/sandbox/platform/sobject-reads"

# Azure AD tenant (AMN Healthcare)
tenant_id = "6232c2ec-fa42-4f27-92cd-787913fba489"

# Entra app registration: SFDC Read MCP Reader Int (legacy reader app, retained as accepted audience)
sfdc_read_mcp_app_id = "976d1c5b-bc4b-4cdf-9fd3-6fd7567a1a03"

# Entra app registration: SFDCRead INT MCP (Power Automate / Copilot Studio client app)
sfdc_read_mcp_copilot_app_id = "42971939-bc78-4c23-963e-c3e0f87e3bd1"

# Salesforce credentials from Key Vault (provisioned by New-SfdcReadKeyVault.ps1)
key_vault_name     = "amn-wus2-sfdcread-kv-i01"
sfdc_client_id     = ""
sfdc_client_secret = ""
sfdc_token_url     = "https://amnhealthcare--qa.sandbox.my.salesforce.com/services/oauth2/token"

# MCP backend (routes to api.salesforce.com, not the SF instance URL)
sfdc_mcp_base_url = "https://api.salesforce.com"

# Tags
tags = {
  environment = "int"
  project     = "sfdc-read-mcp-apim"
  managed_by  = "terraform"
  cost_center = "platform-engineering"
}
