<#
.SYNOPSIS
    Creates a dedicated test client app for APIM smoke tests
.DESCRIPTION
    Provisions a public client app registration that can acquire tokens
    for the SFDC Read MCP API using user credentials (device code flow).
.PARAMETER Environment
    Target environment: dev, int
.EXAMPLE
    .\New-TestClientApp.ps1 -Environment dev
#>

param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'int')]
    [string]$Environment
)

$ErrorActionPreference = "Stop"

# App IDs for the server API apps we need to access.
# int  = "SFDCRead INT MCP" (the canonical, post-2026-06-11 reg). The earlier
#        "SFDC Read MCP Reader Int" (976d1c5b...) was retired by
#        temp/Remove-LegacyReaderAppReg-Int.ps1 — do not re-add it.
$ServerAppIds = @{
    dev = "6ce6ccb1-32db-40f8-97b5-bfbe700d052e"
    int = "42971939-bc78-4c23-963e-c3e0f87e3bd1"
}

$TenantId = "6232c2ec-fa42-4f27-92cd-787913fba489"
$ServerAppId = $ServerAppIds[$Environment]

Write-Host "`n=== Creating Test Client App for $Environment ===" -ForegroundColor Cyan
Write-Host "Server API App ID: $ServerAppId" -ForegroundColor Gray

# Check if already logged in to Azure AD
Write-Host "`nChecking Azure AD connection..." -ForegroundColor Yellow
try {
    $context = Get-MgContext -ErrorAction Stop
    Write-Host "Connected to tenant: $($context.TenantId)" -ForegroundColor Green
}
catch {
    Write-Host "Not connected. Connecting to Microsoft Graph..." -ForegroundColor Yellow
    Connect-MgGraph -TenantId $TenantId -Scopes "Application.ReadWrite.All", "User.Read.All" -NoWelcome
}

# Define test client app
$displayName = "SFDC Read MCP Test Client $Environment"
$appName = "sfdc-read-mcp-test-client-$Environment"

Write-Host "`nChecking if test client already exists..." -ForegroundColor Yellow
$existingApp = Get-MgApplication -Filter "displayName eq '$displayName'" -ErrorAction SilentlyContinue

if ($existingApp) {
    Write-Host "Test client already exists: $($existingApp.AppId)" -ForegroundColor Green
    Write-Host "Using existing app registration." -ForegroundColor Gray
    $appId = $existingApp.AppId
}
else {
    Write-Host "Creating new test client app..." -ForegroundColor Yellow

    # Get the server API app to find the user_impersonation scope ID
    $serverApp = Get-MgApplication -Filter "appId eq '$ServerAppId'"
    if (-not $serverApp) {
        throw "Server API app $ServerAppId not found!"
    }

    $userImpersonationScope = $serverApp.Api.Oauth2PermissionScopes | Where-Object { $_.Value -eq "user_impersonation" }
    if (-not $userImpersonationScope) {
        throw "user_impersonation scope not found on server app!"
    }

    Write-Host "Found user_impersonation scope: $($userImpersonationScope.Id)" -ForegroundColor Gray

    # Create the test client app
    $app = New-MgApplication `
        -DisplayName $displayName `
        -SignInAudience "AzureADMyOrg" `
        -IsFallbackPublicClient `
        -PublicClient @{
            RedirectUris = @(
                "http://localhost",
                "urn:ietf:wg:oauth:2.0:oob"
            )
        } `
        -RequiredResourceAccess @(
            @{
                ResourceAppId = $ServerAppId
                ResourceAccess = @(
                    @{
                        Id = $userImpersonationScope.Id
                        Type = "Scope"
                    }
                )
            }
        )

    Write-Host "Created test client app: $($app.AppId)" -ForegroundColor Green
    $appId = $app.AppId

    # Create service principal
    Write-Host "Creating service principal..." -ForegroundColor Yellow
    $sp = New-MgServicePrincipal -AppId $appId
    Write-Host "Service principal created: $($sp.Id)" -ForegroundColor Green
}

# Grant admin consent for the required permissions
Write-Host "`nGranting admin consent for user_impersonation scope..." -ForegroundColor Yellow

# Get service principals
$testClientSp = Get-MgServicePrincipal -Filter "appId eq '$appId'"
$serverApiSp = Get-MgServicePrincipal -Filter "appId eq '$ServerAppId'"

if (-not $testClientSp) {
    Write-Host "Creating service principal for test client..." -ForegroundColor Yellow
    $testClientSp = New-MgServicePrincipal -AppId $appId
}

# Check if consent already granted
$existingGrant = Get-MgOauth2PermissionGrant -Filter "clientId eq '$($testClientSp.Id)' and resourceId eq '$($serverApiSp.Id)'" -ErrorAction SilentlyContinue

if ($existingGrant) {
    Write-Host "Admin consent already granted." -ForegroundColor Green
}
else {
    Write-Host "Granting admin consent..." -ForegroundColor Yellow

    $userImpersonationScope = $serverApiSp.Oauth2PermissionScopes | Where-Object { $_.Value -eq "user_impersonation" }

    New-MgOauth2PermissionGrant `
        -ClientId $testClientSp.Id `
        -ConsentType "AllPrincipals" `
        -ResourceId $serverApiSp.Id `
        -Scope "user_impersonation" | Out-Null

    Write-Host "Admin consent granted!" -ForegroundColor Green
}

Write-Host "`n=== Test Client App Ready ===" -ForegroundColor Green
Write-Host "App ID: $appId" -ForegroundColor Cyan
Write-Host "Tenant ID: $TenantId" -ForegroundColor Cyan
Write-Host "Scope: api://$ServerAppId/user_impersonation" -ForegroundColor Cyan

Write-Host "`nTo acquire a token for testing:" -ForegroundColor Yellow
Write-Host "az login --scope api://$ServerAppId/.default --allow-no-subscriptions" -ForegroundColor Gray

Write-Host "`nOr use this PowerShell snippet:" -ForegroundColor Yellow
Write-Host @"
`$token = (Get-AzAccessToken -ResourceUrl "api://$ServerAppId" -AsSecureString:`$false).Token
Invoke-RestMethod ``
  -Uri "https://amn-wus2-hub-apim-$($Environment[0])02.azure-api.net/mcp/sfdc-read/$Environment" ``
  -Method Post ``
  -Headers @{ Authorization = "Bearer `$token" } ``
  -Body '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' ``
  -ContentType "application/json"
"@ -ForegroundColor Gray

Write-Host "`nTest client app created successfully!`n" -ForegroundColor Green
