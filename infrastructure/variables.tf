variable "environment" {
  description = "Environment (dev, int, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "int", "prod"], var.environment)
    error_message = "Environment must be dev, int, or prod"
  }
}

variable "apim_name" {
  description = "APIM instance name"
  type        = string
}

variable "apim_resource_group" {
  description = "APIM resource group"
  type        = string
}

variable "backend_url" {
  description = "Salesforce MCP backend URL (or mock URL for dev)"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "sfdc_read_mcp_app_id" {
  description = "Entra app registration ID for api://sfdc-read-mcp-reader"
  type        = string
}

variable "sfdc_read_mcp_copilot_app_id" {
  description = "Entra app registration ID for the Power Automate / Copilot Studio client app (e.g. SFDCRead INT MCP). Used as a second accepted audience and as the OAuth2 authorization server client_id. Empty string disables auth server creation and second-audience validation."
  type        = string
  default     = ""
}

# Salesforce OAuth credentials — either inline (dev) or from Key Vault (int/prod)
variable "sfdc_client_id" {
  description = "Salesforce External Client App - Client ID (empty when using Key Vault)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "sfdc_client_secret" {
  description = "Salesforce External Client App - Client Secret (empty when using Key Vault)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "sfdc_mcp_base_url" {
  description = "Salesforce MCP API base URL — https://api.salesforce.com for all orgs"
  type        = string
  default     = "https://api.salesforce.com"
}

variable "key_vault_name" {
  description = "Key Vault name for SFDC credentials. When set, named values reference KV secrets instead of inline values."
  type        = string
  default     = ""
}

variable "sfdc_token_url" {
  description = "Salesforce OAuth token URL"
  type        = string
  default     = "https://login.salesforce.com/services/oauth2/token"
}

variable "sfdc_mcp_path" {
  description = "Salesforce MCP endpoint path"
  type        = string
}

variable "key_vault_id" {
  description = "Key Vault resource ID for secret storage (optional)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    project    = "sfdc-read-mcp-apim"
    managed_by = "terraform"
  }
}
