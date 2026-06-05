<#
.SYNOPSIS
    Creates ADO variable group for SFDC Read MCP APIM deployment
.PARAMETER Environment
    Target environment (dev/int/prod)
.PARAMETER OrganizationUrl
    ADO organization URL
.PARAMETER ProjectName
    ADO project name
.EXAMPLE
    .\create-variable-group.ps1 -Environment dev
#>

param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'int', 'prod')]
    [string]$Environment,

    [string]$OrganizationUrl = "https://dev.azure.com/AMNEngineering",
    [string]$ProjectName = "Cloud Operations"
)

$ErrorActionPreference = "Stop"

# Check Azure CLI and extension
Write-Host "Checking Azure CLI..." -ForegroundColor Cyan
$azVersion = az version 2>&1 | ConvertFrom-Json
if (-not $azVersion) {
    throw "Azure CLI not found. Install from https://aka.ms/installazurecli"
}

Write-Host "Checking azure-devops extension..." -ForegroundColor Cyan
$extensions = az extension list | ConvertFrom-Json
if (-not ($extensions | Where-Object { $_.name -eq "azure-devops" })) {
    Write-Host "Installing azure-devops extension..." -ForegroundColor Yellow
    az extension add --name azure-devops
}

# Set defaults
Write-Host "Configuring ADO defaults..." -ForegroundColor Cyan
az devops configure --defaults organization=$OrganizationUrl project=$ProjectName

# Variable group name
$groupName = "sfdc-read-mcp-apim-$Environment-vars"

# Check if group exists
Write-Host "Checking if variable group '$groupName' exists..." -ForegroundColor Cyan
$existingGroup = az pipelines variable-group list --group-name $groupName 2>$null | ConvertFrom-Json

if ($existingGroup) {
    Write-Host "Variable group '$groupName' already exists (ID: $($existingGroup[0].id))" -ForegroundColor Yellow
    $continue = Read-Host "Update existing group? (y/n)"
    if ($continue -ne 'y') {
        Write-Host "Aborting." -ForegroundColor Red
        exit 1
    }
    $groupId = $existingGroup[0].id
}
else {
    Write-Host "Creating variable group '$groupName'..." -ForegroundColor Green
    $newGroup = az pipelines variable-group create `
        --name $groupName `
        --description "Variables for SFDC Read MCP APIM deployment ($Environment)" `
        --authorize true `
        --output json | ConvertFrom-Json

    $groupId = $newGroup.id
    Write-Host "Created variable group with ID: $groupId" -ForegroundColor Green
}

# Define variables based on environment
$variables = @{}

# Common variables for all environments
$variables["ARM_TENANT_ID"] = "6232c2ec-fa42-4f27-92cd-787913fba489"
$variables["TF_STATE_CONTAINER"] = "tfstate"

# Environment-specific variables
switch ($Environment) {
    "dev" {
        $variables["ARM_SUBSCRIPTION_ID"] = Read-Host "Enter non-prod Azure subscription ID"
        $variables["TF_STATE_RESOURCE_GROUP"] = Read-Host "Enter Terraform state resource group name"
        $variables["TF_STATE_STORAGE_ACCOUNT"] = Read-Host "Enter Terraform state storage account name"
        $variables["APIM_NAME"] = "amn-wus2-hub-apim-d02"
        $variables["APIM_RESOURCE_GROUP"] = "amn-wus2-hub-rg-d01"
        $variables["SFDC_CLIENT_ID"] = "mock-client-id"
        $variables["SFDC_CLIENT_SECRET"] = "mock-client-secret"  # Mark as secret later
        $variables["SFDC_READ_MCP_APP_ID"] = Read-Host "Enter Entra app registration ID (api://sfdc-read-mcp-reader)"
    }
    "int" {
        $variables["ARM_SUBSCRIPTION_ID"] = Read-Host "Enter non-prod Azure subscription ID"
        $variables["TF_STATE_RESOURCE_GROUP"] = Read-Host "Enter Terraform state resource group name"
        $variables["TF_STATE_STORAGE_ACCOUNT"] = Read-Host "Enter Terraform state storage account name"
        $variables["APIM_NAME"] = "amn-wus2-hub-apim-d02"
        $variables["APIM_RESOURCE_GROUP"] = "amn-wus2-hub-rg-d01"
        $variables["SFDC_CLIENT_ID"] = Read-Host "Enter Salesforce Sandbox client ID"
        $variables["SFDC_CLIENT_SECRET"] = Read-Host "Enter Salesforce Sandbox client secret (will be marked secret)" -AsSecureString | ConvertFrom-SecureString -AsPlainText
        $variables["SFDC_READ_MCP_APP_ID"] = Read-Host "Enter Entra app registration ID (api://sfdc-read-mcp-reader)"
    }
    "prod" {
        $variables["ARM_SUBSCRIPTION_ID"] = Read-Host "Enter prod Azure subscription ID"
        $variables["TF_STATE_RESOURCE_GROUP"] = Read-Host "Enter Terraform state resource group name"
        $variables["TF_STATE_STORAGE_ACCOUNT"] = Read-Host "Enter Terraform state storage account name"
        $variables["APIM_NAME"] = "amn-wus2-hub-apim-p02"
        $variables["APIM_RESOURCE_GROUP"] = "amn-wus2-hub-rg-p01"
        $variables["SFDC_CLIENT_ID"] = Read-Host "Enter Salesforce Production client ID"
        $variables["SFDC_CLIENT_SECRET"] = Read-Host "Enter Salesforce Production client secret (will be marked secret)" -AsSecureString | ConvertFrom-SecureString -AsPlainText
        $variables["SFDC_READ_MCP_APP_ID"] = Read-Host "Enter Entra app registration ID (api://sfdc-read-mcp-reader)"
    }
}

# Add service principal credentials (shared setup)
Write-Host "`nService Principal Credentials:" -ForegroundColor Cyan
$variables["ARM_CLIENT_ID"] = Read-Host "Enter service principal client ID"
$variables["ARM_CLIENT_SECRET"] = Read-Host "Enter service principal client secret (will be marked secret)" -AsSecureString | ConvertFrom-SecureString -AsPlainText

# Add variables to group
Write-Host "`nAdding variables to group..." -ForegroundColor Cyan
foreach ($key in $variables.Keys) {
    $value = $variables[$key]
    $secret = $key -match "SECRET" -or $key -eq "ARM_CLIENT_SECRET"

    if ($secret) {
        Write-Host "  Adding SECRET variable: $key" -ForegroundColor Yellow
        az pipelines variable-group variable create `
            --group-id $groupId `
            --name $key `
            --value $value `
            --secret true `
            --output none 2>$null

        # Update if already exists
        if ($LASTEXITCODE -ne 0) {
            az pipelines variable-group variable update `
                --group-id $groupId `
                --name $key `
                --value $value `
                --secret true `
                --output none
        }
    }
    else {
        Write-Host "  Adding variable: $key = $value" -ForegroundColor Gray
        az pipelines variable-group variable create `
            --group-id $groupId `
            --name $key `
            --value $value `
            --output none 2>$null

        # Update if already exists
        if ($LASTEXITCODE -ne 0) {
            az pipelines variable-group variable update `
                --group-id $groupId `
                --name $key `
                --value $value `
                --output none
        }
    }
}

Write-Host "`n✅ Variable group '$groupName' configured successfully!" -ForegroundColor Green
Write-Host "   Group ID: $groupId" -ForegroundColor Gray
Write-Host "   View at: $OrganizationUrl/$ProjectName/_library?itemType=VariableGroups&view=VariableGroupView&variableGroupId=$groupId" -ForegroundColor Cyan

Write-Host "`n📋 Next steps:" -ForegroundColor Yellow
Write-Host "   1. Verify all variables are correct in ADO UI" -ForegroundColor Gray
Write-Host "   2. Ensure secrets are marked correctly" -ForegroundColor Gray
Write-Host "   3. Grant pipeline access to this variable group" -ForegroundColor Gray
Write-Host "   4. Create service connection: Azure-APIM-SFDC-$Environment" -ForegroundColor Gray
