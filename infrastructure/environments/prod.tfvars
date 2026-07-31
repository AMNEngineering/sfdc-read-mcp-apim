# Prod Environment Configuration
# Backend: Salesforce Production via Key Vault credentials
#
# SKELETON — values marked TBD must be filled by the prod build per
# docs/onboarding/IDENTITY-BOOTSTRAP-PROD.md before this is applied.
# Do NOT terraform apply prod with any TBD value still in place. The pipeline's
# ManualValidation@0 gate is the last line of defense; do not rely on it.

environment         = "prod"
apim_name           = "amn-wus2-hub-apim-p02"
apim_resource_group = "amn-wus2-hub-rg-p01"

# Salesforce production MCP endpoint
backend_url = "https://api.salesforce.com"

# Salesforce MCP path for production org (NOT sandbox — note the missing
# '/sandbox' segment that int uses).
sfdc_mcp_path = "/platform/mcp/v1/platform/sobject-reads"

# Azure AD tenant (AMN Healthcare)
tenant_id = "6232c2ec-fa42-4f27-92cd-787913fba489"

# Entra app registration: SFDCRead PROD MCP
# Provisioned by temp/Setup-SingleAppReg-Mcp.ps1 with
#   -AppDisplayName "SFDCRead PROD MCP"
#   -GroupDisplayName "AZ_AMN_AAD_SfdcReadMcp_Prod_User"
# per docs/onboarding/IDENTITY-BOOTSTRAP-PROD.md Step 1.
sfdc_read_mcp_app_id = "TBD-after-prod-app-reg-created"

# Salesforce production credentials from Key Vault (provisioned per
# IDENTITY-BOOTSTRAP-PROD.md Step 6).
key_vault_name     = "TBD-amn-wus2-sfdcread-kv-p01"
sfdc_client_id     = ""
sfdc_client_secret = ""

# Salesforce production org token endpoint — use the org's My Domain URL, NOT
# login.salesforce.com. Confirm with Salesforce admin during the prod build.
sfdc_token_url = "TBD-https://amnhealthcare.my.salesforce.com/services/oauth2/token"

# MCP backend (routes to api.salesforce.com, not the SF instance URL)
sfdc_mcp_base_url = "https://api.salesforce.com"

# Tags
tags = {
  environment = "prod"
  project     = "sfdc-read-mcp-apim"
  managed_by  = "terraform"
  cost_center = "platform-engineering"
}
