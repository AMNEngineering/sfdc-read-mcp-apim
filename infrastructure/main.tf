terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.71"
    }
  }
}

provider "azurerm" {
  features {}
}

# Named Values Module
module "named_values" {
  source = "./modules/named-values"

  apim_name      = var.apim_name
  resource_group = var.apim_resource_group

  named_values = merge(
    {
      # Entra app ID (plain text, used in policy for JWT validation)
      "sfdc-read-mcp-app-id" = {
        display_name = "SFDC-Read-MCP-App-ID"
        value        = var.sfdc_read_mcp_app_id
      }

      # Salesforce OAuth token URL
      "nv-sfdc-read-mcp-token-url" = {
        display_name = "SFDC-MCP-Token-URL"
        value        = var.sfdc_token_url
      }

      # Salesforce MCP endpoint path
      "nv-sfdc-read-mcp-path" = {
        display_name = "SFDC-MCP-Path"
        value        = var.sfdc_mcp_path
      }

      # MCP base URL (api.salesforce.com for all orgs)
      "nv-sfdc-read-mcp-base-url" = {
        display_name = "SFDC-MCP-Base-URL"
        value        = var.sfdc_mcp_base_url
      }
    },

    # Salesforce credentials: Key Vault references for int/prod, inline for dev
    var.key_vault_name != "" ? {
      "nv-sfdc-read-mcp-client-id" = {
        display_name        = "SFDC-MCP-Client-ID"
        key_vault_secret_id = "https://${var.key_vault_name}.vault.azure.net/secrets/sfdc-client-id"
      }
      "nv-sfdc-read-mcp-client-secret" = {
        display_name        = "SFDC-MCP-Client-Secret"
        key_vault_secret_id = "https://${var.key_vault_name}.vault.azure.net/secrets/sfdc-client-secret"
      }
      } : {
      "nv-sfdc-read-mcp-client-id" = {
        display_name = "SFDC-MCP-Client-ID"
        secret_value = var.sfdc_client_id
      }
      "nv-sfdc-read-mcp-client-secret" = {
        display_name = "SFDC-MCP-Client-Secret"
        secret_value = var.sfdc_client_secret
      }
    }
  )

  tags = var.tags
}

# Backend + Pool Module
module "backend_pool" {
  source = "./modules/backend-pool"

  apim_name      = var.apim_name
  resource_group = var.apim_resource_group
  service_name   = "sfdc-read"
  environment    = var.environment
  backend_url    = var.backend_url

  # TLS validation (disable for dev mock, enable for int/prod)
  tls_validate_certificate_chain = var.environment != "dev"
  tls_validate_certificate_name  = var.environment != "dev"

  description = "Salesforce MCP sobject-reads server (${var.environment})"

  depends_on = [module.named_values]
}

# OAuth2 Authorization Server (for Power Automate / Copilot Studio)
module "oauth2_auth_server" {
  source = "./modules/oauth2-auth-server"

  apim_name      = var.apim_name
  resource_group = var.apim_resource_group

  name          = "sfdc-read-mcp-${var.environment}-entra"
  display_name  = "SFDCRead MCP Entra (${var.environment})"
  tenant_id     = var.tenant_id
  client_app_id = var.sfdc_read_mcp_app_id
}

# MCP API Module
module "mcp_api" {
  source = "./modules/mcp-api"

  apim_name      = var.apim_name
  resource_group = var.apim_resource_group
  service_name   = "sfdc-read"
  environment    = var.environment

  # API path: sfdcread/{environment} (matches AFD route /sfdcread/*)
  api_path = "sfdcread/${var.environment}"

  # No APIM subscription required (Entra JWT is the auth)
  subscription_required = false

  api_description = "Salesforce MCP Read-Only API for Power BI and Copilot Studio (${var.environment})"

  # OAuth2 binding so APIM's exported OpenAPI carries authorize/token URLs + scope
  oauth2_authorization_server_name = module.oauth2_auth_server.name
  oauth2_scope                     = module.oauth2_auth_server.default_scope

  depends_on = [module.backend_pool, module.oauth2_auth_server]
}

# MCP Policy Module (API-level policy for main operations)
module "mcp_policy" {
  source = "./modules/mcp-policy"

  apim_name      = var.apim_name
  resource_group = var.apim_resource_group
  api_name       = module.mcp_api.api_name

  # Load policy XML and inject variables
  # Dev uses mock responses, Int/Prod use real backend
  policy_xml_content = templatefile(
    var.environment == "dev"
    ? "${path.root}/../policies/apim-policy-sfdc-read-mcp-dev-mock.xml"
    : "${path.root}/../policies/apim-policy-sfdc-read-mcp.xml",
    {
      tenant_id   = var.tenant_id
      environment = var.environment
    }
  )

  depends_on = [module.mcp_api, module.named_values]
}

# Health Check Operation Policy (no JWT required)
module "health_check_policy" {
  source = "./modules/mcp-api-operation-policy"

  apim_name      = var.apim_name
  resource_group = var.apim_resource_group
  api_name       = module.mcp_api.api_name
  operation_id   = "health-check"

  policy_xml_content = templatefile("${path.root}/../policies/apim-policy-health-check.xml", {
    environment = var.environment
  })

  depends_on = [module.mcp_api]
}

# Native MCP Server Module (experimental, parallel deployment)
# Only deployed when enable_native_mcp = true
module "mcp_server_native" {
  count  = var.enable_native_mcp ? 1 : 0
  source = "./modules/mcp-server-native"

  apim_name      = var.apim_name
  resource_group = var.apim_resource_group

  mcp_server_name = "sfdcread-mcp-native-${var.environment}"
  display_name    = "MCP ${upper(var.environment)} - SFDCRead (Native)"
  description     = "Salesforce MCP Read-Only Server (Native APIM MCP) - ${upper(var.environment)}"

  backend_mcp_url = "${var.sfdc_mcp_base_url}${var.sfdc_mcp_path}"
  transport_type  = "StreamableHttp"
  base_path       = "sfdcread-mcp-native"

  policy_xml_content = templatefile("${path.root}/../policies/apim-policy-sfdc-read-mcp-native.xml", {
    tenant_id = var.tenant_id
  })

  tags = var.tags

  depends_on = [module.named_values, module.oauth2_auth_server]
}
