terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.71"
    }
  }
}

data "azurerm_api_management" "apim" {
  name                = var.apim_name
  resource_group_name = var.resource_group
}

locals {
  # Default path: mcp/{service}/{env}
  api_path        = var.api_path != "" ? var.api_path : "mcp/${var.service_name}/${var.environment}"
  api_name        = "api-${var.service_name}-${var.environment}"
  api_description = var.api_description != "" ? var.api_description : "MCP API for ${var.service_name} (${var.environment})"
}

resource "azurerm_api_management_api" "this" {
  name                  = local.api_name
  resource_group_name   = var.resource_group
  api_management_name   = var.apim_name
  revision              = "1"
  display_name          = upper("${var.service_name} MCP ${var.environment}")
  path                  = local.api_path
  protocols             = var.protocols
  subscription_required = var.subscription_required
  description           = local.api_description

  # API type - HTTP for MCP JSON-RPC
  service_url = "" # Backend routing handled by policy

  # No import, defining inline
}

# Single wildcard operation for MCP JSON-RPC
resource "azurerm_api_management_api_operation" "mcp_invoke" {
  operation_id        = "invoke-mcp"
  api_name            = azurerm_api_management_api.this.name
  api_management_name = var.apim_name
  resource_group_name = var.resource_group
  display_name        = "Invoke MCP"
  method              = "POST"
  url_template        = "/"
  description         = "MCP JSON-RPC 2.0 endpoint (initialize, tools/list, tools/call)"

  response {
    status_code = 200
    description = "Success"
    representation {
      content_type = "application/json"
    }
  }

  response {
    status_code = 401
    description = "Unauthorized"
  }

  response {
    status_code = 429
    description = "Too Many Requests"
  }

  response {
    status_code = 500
    description = "Internal Server Error"
  }
}
