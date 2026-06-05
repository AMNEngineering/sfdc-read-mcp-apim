<#
.SYNOPSIS
    Quick test to validate the mock MCP server
.DESCRIPTION
    Tests the mock server's MCP protocol implementation
#>

param(
    [string]$ServerUrl = "http://localhost:8080"
)

$ErrorActionPreference = "Stop"

function Test-McpEndpoint {
    param(
        [string]$Method,
        [hashtable]$Params = @{},
        [int]$Id = 1
    )

    $body = @{
        jsonrpc = "2.0"
        id      = $Id
        method  = $Method
        params  = $Params
    } | ConvertTo-Json -Depth 10

    Write-Host "→ Testing $Method..." -ForegroundColor Cyan

    try {
        $response = Invoke-RestMethod -Uri $ServerUrl -Method Post -Body $body -ContentType "application/json"
        Write-Host "✓ $Method successful" -ForegroundColor Green
        return $response
    }
    catch {
        Write-Host "✗ $Method failed: $_" -ForegroundColor Red
        throw
    }
}

Write-Host "`n🧪 Testing Mock Salesforce MCP Server at $ServerUrl`n" -ForegroundColor Yellow

# Test 1: Initialize
$initResponse = Test-McpEndpoint -Method "initialize" -Params @{
    protocolVersion = "2024-11-05"
    capabilities    = @{
        roots = @{ listChanged = $true }
    }
    clientInfo      = @{
        name    = "test-client"
        version = "1.0.0"
    }
}

Write-Host "  Server: $($initResponse.result.serverInfo.name) v$($initResponse.result.serverInfo.version)" -ForegroundColor Gray

# Test 2: Tools List
$toolsResponse = Test-McpEndpoint -Method "tools/list" -Id 2
$toolCount = $toolsResponse.result.tools.Count
Write-Host "  Tools available: $toolCount" -ForegroundColor Gray

# Test 3: getSobjectSchema (index)
$schemaResponse = Test-McpEndpoint -Method "tools/call" -Params @{
    name      = "getSobjectSchema"
    arguments = @{}
} -Id 3

# Test 4: soqlQuery
$queryResponse = Test-McpEndpoint -Method "tools/call" -Params @{
    name      = "soqlQuery"
    arguments = @{
        query = "SELECT Id, Name FROM Account LIMIT 5"
    }
} -Id 4

$records = $queryResponse.result.content[0].text | ConvertFrom-Json
Write-Host "  Query returned $($records.Count) records" -ForegroundColor Gray

# Test 5: getUserIdentity
$identityResponse = Test-McpEndpoint -Method "tools/call" -Params @{
    name      = "getUserIdentity"
    arguments = @{}
} -Id 5

$identity = $identityResponse.result.content[0].text | ConvertFrom-Json
Write-Host "  User: $($identity.username)" -ForegroundColor Gray

Write-Host "`n✅ All tests passed!`n" -ForegroundColor Green
Write-Host "Mock server is ready for APIM integration testing." -ForegroundColor Cyan
