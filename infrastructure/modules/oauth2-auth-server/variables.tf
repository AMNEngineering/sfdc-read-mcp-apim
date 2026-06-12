variable "apim_name" {
  description = "APIM instance name"
  type        = string
}

variable "resource_group" {
  description = "APIM resource group"
  type        = string
}

variable "name" {
  description = "Authorization server identifier (used in APIM API binding)"
  type        = string
}

variable "display_name" {
  description = "Authorization server display name shown in the developer portal"
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant ID — used to build v2 authorize/token endpoints"
  type        = string
}

variable "client_app_id" {
  description = "Entra app registration the OAuth2 client authenticates against (e.g. the Power Automate / Copilot Studio app). Empty string disables auth server creation."
  type        = string
  default     = ""
}

variable "default_scope" {
  description = "Default scope advertised to clients. Defaults to api://<client_app_id>/user_impersonation when blank."
  type        = string
  default     = ""
}
