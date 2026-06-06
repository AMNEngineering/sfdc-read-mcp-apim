<#
.SYNOPSIS
    Creates a dedicated test client app using Azure CLI
.DESCRIPTION
    Provisions a public client app registration that can acquire tokens
    for the SFDC Read MCP API using user credentials.
.PARAMETER Environment
    Target environment: dev, int
#>

param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'int')]
    [string]$Environment
)

$ErrorActionPreference = "Stop"

# App IDs for the server API apps we need to access
$ServerAppIds = @{
    dev = "6ce6ccb1-32db-40f8-97b5-bfbe700d052e"
    int = "976d1c5b-bc4b-4cdf-9fd3-6fd7567a1a03"
}

$TenantId = "6232c2ec-fa42-4f27-92cd-787913fba489"
$ServerAppId = $ServerAppIds[$Environment]

Write-Host "`n=== Creating Test Client App for $Environment ===" -ForegroundColor Cyan
Write-Host "Server API App ID: $ServerAppId" -ForegroundColor Gray

# Get the server app to find the user_impersonation scope ID
Write-Host "`nLooking up server API app..." -ForegroundColor Yellow
$serverApp = az ad app show --id $ServerAppId | ConvertFrom-Json

$userImpScope = $serverApp.api.oauth2PermissionScopes | Where-Object { $_.value -eq "user_impersonation" }
if (-not $userImpScope) {
    throw "user_impersonation scope not found on server app!"
}

$scopeId = $userImpScope.id
Write-Host "Found user_impersonation scope: $scopeId" -ForegroundColor Gray

# Check if test client already exists
$displayName = "SFDC Read MCP Test Client $Environment"
Write-Host "`nChecking if test client already exists..." -ForegroundColor Yellow

$existingApps = az ad app list --display-name $displayName | ConvertFrom-Json
if ($existingApps -and $existingApps.Count -gt 0) {
    Write-Host "Test client already exists: $($existingApps[0].appId)" -ForegroundColor Green
    $appId = $existingApps[0].appId
}
else {
    Write-Host "Creating new test client app..." -ForegroundColor Yellow

    # Create manifest for required resource access
    $requiredResourceAccess = @(
        @{
            resourceAppId = $ServerAppId
            resourceAccess = @(
                @{
                    id = $scopeId
                    type = "Scope"
                }
            )
        }
    ) | ConvertTo-Json -Depth 10 -Compress

    # Create the app
    $app = az ad app create `
        --display-name $displayName `
        --sign-in-audience "AzureADMyOrg" `
        --is-fallback-public-client true `
        --public-client-redirect-uris "http://localhost" "urn:ietf:wg:oauth:2.0:oob" `
        --required-resource-accesses $requiredResourceAccess | ConvertFrom-Json

    $appId = $app.appId
    Write-Host "Created test client app: $appId" -ForegroundColor Green

    # Create service principal
    Write-Host "Creating service principal..." -ForegroundColor Yellow
    az ad sp create --id $appId | Out-Null
    Write-Host "Service principal created" -ForegroundColor Green

    # Wait for SP creation to propagate
    Start-Sleep -Seconds 3
}

# Grant admin consent
Write-Host "`nGranting admin consent..." -ForegroundColor Yellow

# Get service principal IDs
$testClientSp = az ad sp show --id $appId | ConvertFrom-Json
$serverApiSp = az ad sp show --id $ServerAppId | ConvertFrom-Json

if (-not $testClientSp) {
    Write-Host "Service principal not found. Creating..." -ForegroundColor Yellow
    az ad sp create --id $appId | Out-Null
    Start-Sleep -Seconds 3
    $testClientSp = az ad sp show --id $appId | ConvertFrom-Json
}

# Check existing grants
$existingGrants = az ad oauth2-permission-grant list `
    --filter "clientId eq '$($testClientSp.id)' and resourceId eq '$($serverApiSp.id)'" | ConvertFrom-Json

if ($existingGrants -and $existingGrants.Count -gt 0) {
    Write-Host "Admin consent already granted" -ForegroundColor Green
}
else {
    # Grant consent using REST API (az cli doesn't have direct command)
    $body = @{
        clientId = $testClientSp.id
        consentType = "AllPrincipals"
        principalId = $null
        resourceId = $serverApiSp.id
        scope = "user_impersonation"
    } | ConvertTo-Json

    $token = az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv

    try {
        $response = Invoke-RestMethod `
            -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants" `
            -Method Post `
            -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
            -Body $body

        Write-Host "Admin consent granted!" -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 400 -and $_ -match "already exists") {
            Write-Host "Admin consent already exists" -ForegroundColor Green
        }
        else {
            Write-Host "Warning: Could not grant admin consent automatically" -ForegroundColor Yellow
            Write-Host "You may need to grant consent manually in Azure Portal" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n=== Test Client App Ready ===" -ForegroundColor Green
Write-Host "App ID: $appId" -ForegroundColor Cyan
Write-Host "Tenant ID: $TenantId" -ForegroundColor Cyan
Write-Host "Scope: api://$ServerAppId/user_impersonation" -ForegroundColor Cyan

Write-Host "`nUpdate smoke test to use this client:" -ForegroundColor Yellow
Write-Host ".\Invoke-ApimSmokeTest.ps1 -Environment $Environment -ClientId $appId" -ForegroundColor Gray

Write-Host "`nOr acquire token manually:" -ForegroundColor Yellow
Write-Host @"
# PowerShell
`$token = (Get-AzAccessToken -ResourceUrl "api://$ServerAppId").Token

# Or Azure CLI
az account get-access-token --resource api://$ServerAppId --query accessToken -o tsv
"@ -ForegroundColor Gray

Write-Host "`nTest client app created successfully!`n" -ForegroundColor Green

# Save app ID for smoke test
$configPath = Join-Path $PSScriptRoot "test-client-config.json"
@{
    dev = if ($Environment -eq "dev") { $appId } else { $null }
    int = if ($Environment -eq "int") { $appId } else { $null }
} | ConvertTo-Json | Out-File $configPath -Encoding UTF8

Write-Host "Client ID saved to: $configPath" -ForegroundColor Gray
