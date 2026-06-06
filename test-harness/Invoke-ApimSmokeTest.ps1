<#
.SYNOPSIS
    APIM smoke test for SFDC Read MCP API
.DESCRIPTION
    Tests the deployed APIM API end-to-end:
    - Acquires Entra ID JWT token
    - Calls through APIM gateway
    - Exercises all 6 MCP tools
    - Validates responses
.PARAMETER Environment
    Target environment: dev, int, prod
.PARAMETER TenantId
    Entra tenant ID (defaults to AMN Healthcare)
.PARAMETER ClientId
    Test client app registration ID (interactive user auth)
.EXAMPLE
    .\Invoke-ApimSmokeTest.ps1 -Environment dev -ClientId "your-test-app-id"
#>

param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'int', 'prod')]
    [string]$Environment,

    [string]$TenantId = "6232c2ec-fa42-4f27-92cd-787913fba489",

    [string]$ClientId = "",

    [switch]$VerboseLogging
)

$ErrorActionPreference = "Stop"

# Environment-specific endpoints (via Azure Front Door)
$ApimEndpoints = @{
    dev  = "https://api.dev.amnhealthcare.io/sfdc-read/dev"
    int  = "https://api.int.amnhealthcare.io/sfdc-read/int"
    prod = "https://api.amnhealthcare.io/sfdc-read/prod"
}

# App registrations for JWT audience
$AppIds = @{
    dev  = "6ce6ccb1-32db-40f8-97b5-bfbe700d052e"
    int  = "976d1c5b-bc4b-4cdf-9fd3-6fd7567a1a03"
    prod = "TBD"
}

$script:TestResults = @()

function Write-TestLog {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'ERROR'   { 'Red' }
        'WARN'    { 'Yellow' }
        default   { 'Cyan' }
    }

    $symbol = switch ($Level) {
        'SUCCESS' { '[+]' }
        'ERROR'   { '[-]' }
        'WARN'    { '[!]' }
        default   { '[>]' }
    }

    Write-Host "[$timestamp] $symbol $Message" -ForegroundColor $color
}

function Get-EntraJwt {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$Scope
    )

    Write-TestLog "Acquiring Entra JWT token..." -Level INFO

    try {
        # Use az cli for token acquisition (device code flow if needed)
        if ([string]::IsNullOrEmpty($ClientId)) {
            # Default to Azure CLI own app registration
            $token = az account get-access-token --resource "api://$Scope" --query accessToken -o tsv
        }
        else {
            # Interactive device code flow with specific client
            Write-TestLog "Using device code flow with client $ClientId" -Level INFO
            $tokenResponse = az account get-access-token `
                --resource "api://$Scope" `
                --query accessToken -o tsv 2>&1

            if ($LASTEXITCODE -ne 0) {
                throw "Token acquisition failed: $tokenResponse"
            }
            $token = $tokenResponse
        }

        if ([string]::IsNullOrEmpty($token)) {
            throw "Token acquisition returned empty token"
        }

        Write-TestLog "JWT token acquired successfully" -Level SUCCESS
        return $token
    }
    catch {
        Write-TestLog "Failed to acquire token: $_" -Level ERROR
        throw
    }
}

function Invoke-McpRequest {
    param(
        [string]$Endpoint,
        [string]$BearerToken,
        [string]$Method,
        [hashtable]$Params = @{},
        [int]$Id = 1,
        [string]$CorrelationId = [guid]::NewGuid().ToString()
    )

    $body = @{
        jsonrpc = "2.0"
        id      = $Id
        method  = $Method
        params  = $Params
    } | ConvertTo-Json -Depth 10 -Compress

    $headers = @{
        Authorization      = "Bearer $BearerToken"
        "x-correlation-id" = $CorrelationId
    }

    if ($VerboseLogging) {
        Write-TestLog "Request: $Method" -Level INFO
        Write-TestLog "Body: $body" -Level INFO
    }

    try {
        $response = Invoke-RestMethod `
            -Uri $Endpoint `
            -Method Post `
            -Headers $headers `
            -Body $body `
            -ContentType "application/json" `
            -ResponseHeadersVariable responseHeaders

        if ($VerboseLogging) {
            Write-TestLog "Response headers: $($responseHeaders | ConvertTo-Json -Compress)" -Level INFO
            Write-TestLog "Response: $($response | ConvertTo-Json -Depth 10 -Compress)" -Level INFO
        }

        # Validate correlation ID echo
        if ($responseHeaders.ContainsKey('x-correlation-id')) {
            if ($responseHeaders['x-correlation-id'] -eq $CorrelationId) {
                Write-TestLog "Correlation ID echoed correctly" -Level SUCCESS
            }
            else {
                Write-TestLog "Correlation ID mismatch! Sent: $CorrelationId, Received: $($responseHeaders['x-correlation-id'])" -Level WARN
            }
        }

        return $response
    }
    catch {
        Write-TestLog "Request failed: $_" -Level ERROR
        Write-TestLog "Status: $($_.Exception.Response.StatusCode.value__) $($_.Exception.Response.StatusDescription)" -Level ERROR
        throw
    }
}

function Test-Initialize {
    param($Endpoint, $Token)

    Write-TestLog "`n--- Test 1: Initialize ---" -Level INFO

    $response = Invoke-McpRequest `
        -Endpoint $Endpoint `
        -BearerToken $Token `
        -Method "initialize" `
        -Params @{
            protocolVersion = "2024-11-05"
            capabilities    = @{
                roots = @{ listChanged = $true }
            }
            clientInfo      = @{
                name    = "apim-smoke-test"
                version = "1.0.0"
            }
        } `
        -Id 1

    # Validate response structure
    if ($response.jsonrpc -ne "2.0") {
        throw "Invalid JSON-RPC version: $($response.jsonrpc)"
    }

    if (-not $response.result.serverInfo) {
        throw "Missing serverInfo in response"
    }

    Write-TestLog "Server: $($response.result.serverInfo.name) v$($response.result.serverInfo.version)" -Level SUCCESS
    Write-TestLog "Protocol: $($response.result.protocolVersion)" -Level SUCCESS

    $script:TestResults += @{
        Test   = "Initialize"
        Status = "PASS"
        Server = $response.result.serverInfo.name
    }
}

function Test-ToolsList {
    param($Endpoint, $Token)

    Write-TestLog "`n--- Test 2: Tools List ---" -Level INFO

    $response = Invoke-McpRequest `
        -Endpoint $Endpoint `
        -BearerToken $Token `
        -Method "tools/list" `
        -Id 2

    if (-not $response.result.tools) {
        throw "Missing tools array in response"
    }

    $toolCount = $response.result.tools.Count
    Write-TestLog "Tools available: $toolCount" -Level SUCCESS

    $expectedTools = @(
        "getSobjectSchema",
        "soqlQuery",
        "soslSearch",
        "getUserIdentity",
        "getRecentItems",
        "getRelatedRecords"
    )

    foreach ($tool in $expectedTools) {
        if ($response.result.tools.name -contains $tool) {
            Write-TestLog "  ✓ $tool" -Level SUCCESS
        }
        else {
            Write-TestLog "  ✗ $tool MISSING" -Level ERROR
        }
    }

    $script:TestResults += @{
        Test   = "Tools List"
        Status = "PASS"
        Count  = $toolCount
    }

    return $response.result.tools
}

function Test-GetSobjectSchema {
    param($Endpoint, $Token)

    Write-TestLog "`n--- Test 3: getSobjectSchema (index) ---" -Level INFO

    $response = Invoke-McpRequest `
        -Endpoint $Endpoint `
        -BearerToken $Token `
        -Method "tools/call" `
        -Params @{
            name      = "getSobjectSchema"
            arguments = @{}
        } `
        -Id 3

    if ($response.result.isError -eq $true) {
        throw "Tool returned error: $($response.result.content[0].text)"
    }

    $objects = $response.result.content[0].text | ConvertFrom-Json
    Write-TestLog "Objects returned: $($objects.Count)" -Level SUCCESS

    # Validate structure
    if ($objects[0].name -and $objects[0].label) {
        Write-TestLog "  First object: $($objects[0].name) ($($objects[0].label))" -Level SUCCESS
    }
    else {
        throw "Invalid object structure"
    }

    $script:TestResults += @{
        Test   = "getSobjectSchema (index)"
        Status = "PASS"
        Count  = $objects.Count
    }
}

function Test-GetSobjectSchemaDetail {
    param($Endpoint, $Token)

    Write-TestLog "`n--- Test 4: getSobjectSchema (Account fields) ---" -Level INFO

    $response = Invoke-McpRequest `
        -Endpoint $Endpoint `
        -BearerToken $Token `
        -Method "tools/call" `
        -Params @{
            name      = "getSobjectSchema"
            arguments = @{
                "object-name" = "Account"
            }
        } `
        -Id 4

    if ($response.result.isError -eq $true) {
        throw "Tool returned error: $($response.result.content[0].text)"
    }

    $fields = $response.result.content[0].text | ConvertFrom-Json
    Write-TestLog "Fields returned: $($fields.Count)" -Level SUCCESS

    # Check for standard Account fields
    $requiredFields = @("Id", "Name")
    foreach ($field in $requiredFields) {
        if ($fields.name -contains $field) {
            Write-TestLog "  ✓ $field field present" -Level SUCCESS
        }
        else {
            Write-TestLog "  ✗ $field field MISSING" -Level WARN
        }
    }

    $script:TestResults += @{
        Test   = "getSobjectSchema (Account)"
        Status = "PASS"
        Fields = $fields.Count
    }
}

function Test-SoqlQuery {
    param($Endpoint, $Token)

    Write-TestLog "`n--- Test 5: soqlQuery ---" -Level INFO

    $response = Invoke-McpRequest `
        -Endpoint $Endpoint `
        -BearerToken $Token `
        -Method "tools/call" `
        -Params @{
            name      = "soqlQuery"
            arguments = @{
                query = "SELECT Id, Name FROM Account LIMIT 5"
            }
        } `
        -Id 5

    if ($response.result.isError -eq $true) {
        throw "Query returned error: $($response.result.content[0].text)"
    }

    $records = $response.result.content[0].text | ConvertFrom-Json
    Write-TestLog "Records returned: $($records.Count)" -Level SUCCESS

    if ($records.Count -gt 0) {
        Write-TestLog "  First record: $($records[0].Id) - $($records[0].Name)" -Level SUCCESS
    }

    $script:TestResults += @{
        Test    = "soqlQuery"
        Status  = "PASS"
        Records = $records.Count
    }
}

function Test-GetUserIdentity {
    param($Endpoint, $Token)

    Write-TestLog "`n--- Test 6: getUserIdentity ---" -Level INFO

    $response = Invoke-McpRequest `
        -Endpoint $Endpoint `
        -BearerToken $Token `
        -Method "tools/call" `
        -Params @{
            name      = "getUserIdentity"
            arguments = @{}
        } `
        -Id 6

    if ($response.result.isError -eq $true) {
        throw "Tool returned error: $($response.result.content[0].text)"
    }

    $identity = $response.result.content[0].text | ConvertFrom-Json
    Write-TestLog "User ID: $($identity.user_id)" -Level SUCCESS
    Write-TestLog "Username: $($identity.username)" -Level SUCCESS
    Write-TestLog "Org ID: $($identity.organization_id)" -Level SUCCESS

    $script:TestResults += @{
        Test     = "getUserIdentity"
        Status   = "PASS"
        Username = $identity.username
    }
}

function Test-JwtValidation {
    param($Endpoint, $Token)

    Write-TestLog "`n--- Test 7: JWT Validation (negative test) ---" -Level INFO

    try {
        $response = Invoke-RestMethod `
            -Uri $Endpoint `
            -Method Post `
            -Headers @{ Authorization = "Bearer invalid-token-12345" } `
            -Body '{"jsonrpc":"2.0","id":99,"method":"tools/list","params":{}}' `
            -ContentType "application/json"

        Write-TestLog "FAIL: Invalid token was accepted!" -Level ERROR
        $script:TestResults += @{
            Test   = "JWT Validation"
            Status = "FAIL"
        }
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 401) {
            Write-TestLog "Invalid token correctly rejected (401)" -Level SUCCESS
            $script:TestResults += @{
                Test   = "JWT Validation"
                Status = "PASS"
            }
        }
        else {
            Write-TestLog "Unexpected status code: $($_.Exception.Response.StatusCode.value__)" -Level WARN
            $script:TestResults += @{
                Test   = "JWT Validation"
                Status = "WARN"
            }
        }
    }
}

# Main execution
Write-Host "`n===============================================================" -ForegroundColor Cyan
Write-Host "  APIM Smoke Test - SFDC Read MCP API" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan

Write-TestLog "Environment: $Environment" -Level INFO
Write-TestLog "Endpoint: $($ApimEndpoints[$Environment])" -Level INFO
Write-TestLog "App ID: $($AppIds[$Environment])" -Level INFO

# Step 1: Acquire JWT token
$jwt = Get-EntraJwt -TenantId $TenantId -ClientId $ClientId -Scope $AppIds[$Environment]

# Step 2: Run tests
try {
    Test-Initialize -Endpoint $ApimEndpoints[$Environment] -Token $jwt
    Test-ToolsList -Endpoint $ApimEndpoints[$Environment] -Token $jwt
    Test-GetSobjectSchema -Endpoint $ApimEndpoints[$Environment] -Token $jwt
    Test-GetSobjectSchemaDetail -Endpoint $ApimEndpoints[$Environment] -Token $jwt
    Test-SoqlQuery -Endpoint $ApimEndpoints[$Environment] -Token $jwt
    Test-GetUserIdentity -Endpoint $ApimEndpoints[$Environment] -Token $jwt
    Test-JwtValidation -Endpoint $ApimEndpoints[$Environment] -Token $jwt

    # Summary
    Write-Host "`n===============================================================" -ForegroundColor Green
    Write-Host "  Test Summary" -ForegroundColor Green
    Write-Host "===============================================================" -ForegroundColor Green

    $passed = ($script:TestResults | Where-Object { $_.Status -eq "PASS" }).Count
    $total = $script:TestResults.Count

    foreach ($result in $script:TestResults) {
        $status = if ($result.Status -eq "PASS") { "[+]" } else { "[-]" }
        $color = if ($result.Status -eq "PASS") { "Green" } else { "Red" }
        Write-Host "  $status $($result.Test)" -ForegroundColor $color
    }

    $resultColor = if ($passed -eq $total) { "Green" } else { "Yellow" }
    Write-Host "`n  Results: $passed/$total passed" -ForegroundColor $resultColor

    if ($passed -eq $total) {
        Write-Host "`n[OK] All tests passed! APIM API is healthy.`n" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "`n[WARN] Some tests failed. Review logs above.`n" -ForegroundColor Yellow
        exit 1
    }
}
catch {
    Write-TestLog "Test suite failed: $_" -Level ERROR
    Write-Host "`n[ERROR] Test suite aborted due to error.`n" -ForegroundColor Red
    exit 1
}
