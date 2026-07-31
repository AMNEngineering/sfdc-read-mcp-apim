terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.71"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.9"
    }
  }
}

# Create MCP Server using Azure API
# Docs: https://learn.microsoft.com/en-us/rest/api/apimanagement/current-ga/mcp-server/create-or-update
resource "azapi_resource" "mcp_server" {
  type      = "Microsoft.ApiManagement/service/mcpServers@2024-06-01-preview"
  name      = var.mcp_server_name
  parent_id = "${data.azurerm_api_management.apim.id}"

  body = jsonencode({
    properties = {
      displayName        = var.display_name
      description        = var.description
      backendMcpServerUrl = var.backend_mcp_url
      transportType      = var.transport_type
      basePath           = var.base_path
    }
  })

  tags = var.tags
}

data "azurerm_api_management" "apim" {
  name                = var.apim_name
  resource_group_name = var.resource_group
}

# Apply policy to the MCP server
# Note: azurerm provider doesn't support MCP server policies yet
# Using null_resource with Azure CLI as a workaround
resource "null_resource" "mcp_server_policy" {
  count = var.policy_xml_content != "" ? 1 : 0

  triggers = {
    policy_hash      = md5(var.policy_xml_content)
    mcp_server_id    = azapi_resource.mcp_server.id
    always_run       = timestamp()  # Force policy check on every apply
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Save policy to temp file
      $policyFile = [System.IO.Path]::GetTempFileName()
      @'
${var.policy_xml_content}
'@ | Out-File -FilePath $policyFile -Encoding UTF8

      # Apply policy via Azure REST API
      $mcpServerName = "${var.mcp_server_name}"
      $apimName = "${var.apim_name}"
      $resourceGroup = "${var.resource_group}"

      # Get subscription ID
      $subId = (az account show --query id -o tsv)

      # MCP server policy REST API endpoint
      $policyUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName/mcpServers/$mcpServerName/policies/policy?api-version=2024-06-01-preview"

      # Get access token
      $token = (az account get-access-token --query accessToken -o tsv)

      # Create policy JSON payload
      $policyContent = Get-Content $policyFile -Raw
      $payload = @{
        properties = @{
          value  = $policyContent
          format = "xml"
        }
      } | ConvertTo-Json -Depth 10

      # Apply policy
      try {
        Invoke-RestMethod -Method Put -Uri $policyUrl `
          -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
          -Body $payload
        Write-Host "✅ MCP server policy applied successfully"
      } catch {
        Write-Warning "⚠️  Policy application failed. You may need to apply it manually in the portal."
        Write-Warning "Error: $_"
        # Don't fail the deployment - policy can be applied manually
      } finally {
        Remove-Item $policyFile -ErrorAction SilentlyContinue
      }
    EOT

    interpreter = ["pwsh", "-Command"]
  }

  depends_on = [azapi_resource.mcp_server]
}
