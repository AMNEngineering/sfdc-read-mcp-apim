terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.71"
    }
  }
}

locals {
  enabled       = var.client_app_id != ""
  scope         = var.default_scope != "" ? var.default_scope : "api://${var.client_app_id}/user_impersonation"
  authorize_url = "https://login.microsoftonline.com/${var.tenant_id}/oauth2/v2.0/authorize"
  token_url     = "https://login.microsoftonline.com/${var.tenant_id}/oauth2/v2.0/token"
}

resource "azurerm_api_management_authorization_server" "this" {
  count = local.enabled ? 1 : 0

  name                = var.name
  api_management_name = var.apim_name
  resource_group_name = var.resource_group
  display_name        = var.display_name
  description         = "Entra v2 authorization code flow for the SFDCRead MCP API. Tenant ${var.tenant_id}, app ${var.client_app_id}."

  authorization_endpoint       = local.authorize_url
  token_endpoint               = local.token_url
  client_registration_endpoint = "https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/Overview/appId/${var.client_app_id}"

  client_id                    = var.client_app_id
  grant_types                  = ["authorizationCode"]
  authorization_methods        = ["GET"]
  bearer_token_sending_methods = ["authorizationHeader"]
  default_scope                = local.scope
  support_state                = true
}
