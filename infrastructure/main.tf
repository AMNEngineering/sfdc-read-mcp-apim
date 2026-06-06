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

  named_values = {
    # Entra app ID (plain text, used in policy for JWT validation)
    "sfdc-read-mcp-app-id" = {
      display_name = "SFDC-Read-MCP-App-ID"
      value        = var.sfdc_read_mcp_app_id
    }

    # Salesforce OAuth credentials (secrets)
    "nv-sfdc-read-mcp-client-id" = {
      display_name = "SFDC-MCP-Client-ID"
      secret_value = var.sfdc_client_id
    }

    "nv-sfdc-read-mcp-client-secret" = {
      display_name = "SFDC-MCP-Client-Secret"
      secret_value = var.sfdc_client_secret
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
  }

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

# MCP API Module
module "mcp_api" {
  source = "./modules/mcp-api"

  apim_name      = var.apim_name
  resource_group = var.apim_resource_group
  service_name   = "sfdc-read"
  environment    = var.environment

  # API path: sfdc-read/{environment}
  api_path = "sfdc-read/${var.environment}"

  # No APIM subscription required (Entra JWT is the auth)
  subscription_required = false

  api_description = "Salesforce MCP Read-Only API for Power BI and Copilot Studio (${var.environment})"

  depends_on = [module.backend_pool]
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
