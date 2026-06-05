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

resource "azurerm_api_management_named_value" "this" {
  for_each = var.named_values

  name                = each.key
  resource_group_name = var.resource_group
  api_management_name = var.apim_name
  display_name        = each.value.display_name

  # Exactly one of these must be set
  value = each.value.key_vault_secret_id == null && each.value.secret_value == null ? each.value.value : null

  # Secret stored directly in APIM (not recommended for prod)
  secret = each.value.secret_value != null ? true : (each.value.key_vault_secret_id != null ? true : false)

  # Key Vault reference (use dynamic block syntax)
  dynamic "value_from_key_vault" {
    for_each = each.value.key_vault_secret_id != null ? [1] : []
    content {
      secret_id = each.value.key_vault_secret_id
    }
  }

  # Note: azurerm_api_management_named_value does not support tags

  lifecycle {
    # Prevent replacement if only secret value changed (causes downtime)
    create_before_destroy = true
  }
}
