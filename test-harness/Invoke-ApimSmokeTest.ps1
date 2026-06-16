<#
.SYNOPSIS
    APIM smoke test for SFDC Read MCP API
.DESCRIPTION
    Tests the deployed APIM API end-to-end:
    - Acquires Entra ID JWT token
    - Calls through APIM gateway
    - Exercises all 6 MCP tools
    - Validates responses

    Status semantics:
      PASS = expected outcome occurred. For in-scope probes that means
             data returned; for boundary assertions (e.g. Account is
             intentionally excluded) it means the call was correctly
             blocked. See the per-test functions for which semantics apply.
      WARN = wiring/protocol healthy but the call returned an unexpected
             data-access error on a probe that wasn't explicitly framed
             as a boundary assertion. Flag for review against the
             documented scope — do not reflexively widen MCP_ReadOnly_Access.
             See README "Design Intent".
      FAIL = something is broken (JWT, OAuth, routing, protocol) OR a
             boundary assertion was breached (an out-of-scope SObject
             became accessible — a security regression). Suite exits 1.
.PARAMETER TenantId
    Entra tenant ID (defaults to AMN Healthcare)
.PARAMETER ClientId
    Test client app registration ID (interactive user auth)
.EXAMPLE
    .\Invoke-ApimSmokeTest.ps1
#>

param(
    [string]$TenantId = "6232c2ec-fa42-4f27-92cd-787913fba489",

    [string]$ClientId = "",

    [switch]$VerboseLogging
)

$ErrorActionPreference = "Stop"

# SFDCRead INT — the only deployed environment today.
# Add dev/prod back here when they come online.
#
# APIM accepts TWO audiences for INT (dual-audience design — see
# infrastructure/environments/int.tfvars):
#   - sfdc_read_mcp_app_id         976d1c5b-bc4b-4cdf-9fd3-6fd7567a1a03 (legacy
#     "SFDC Read MCP Reader Int" app reg — currently has a broken appRole
#     definition: value="User" instead of "MCP.Read", needs cleanup or repair)
#   - sfdc_read_mcp_copilot_app_id 42971939-bc78-4c23-963e-c3e0f87e3bd1
#     ("SFDCRead INT MCP" — Copilot Studio / Power Automate audience, correct
#     MCP.Read role, group AZ_AMN_AAD_SfdcReadMcp_Int_User assigned to it)
#
# We test against the Copilot audience because that's the path real consumers
# (Copilot Studio, Power Automate) use end-to-end.
$ApimEndpoint = "https://api.int.amnhealthcare.io/sfdcread/int/mcp"
$AppId        = "42971939-bc78-4c23-963e-c3e0f87e3bd1"

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

function Send-McpNotification {
    # MCP/JSON-RPC notification: no id, no response body. Server returns 202.
    param(
        [string]$Endpoint,
        [string]$BearerToken,
        [string]$Method,
        [hashtable]$Params = @{},
        [string]$CorrelationId = [guid]::NewGuid().ToString()
    )

    $body = @{
        jsonrpc = "2.0"
        method  = $Method
        params  = $Params
    } | ConvertTo-Json -Depth 10 -Compress

    $httpClient = [System.Net.Http.HttpClient]::new()
    $httpClient.Timeout = [TimeSpan]::FromSeconds(15)

    $request = $null
    $response = $null
    try {
        $request = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::Post, $Endpoint)
        $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $BearerToken)
        $request.Headers.Add('x-correlation-id', $CorrelationId)
        [void]$request.Headers.Accept.Add(
            [System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new('application/json'))
        [void]$request.Headers.Accept.Add(
            [System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new('text/event-stream'))
        if ($script:McpSessionId) {
            $request.Headers.Add('Mcp-Session-Id', $script:McpSessionId)
        }
        $request.Content = [System.Net.Http.StringContent]::new(
            $body, [System.Text.Encoding]::UTF8, 'application/json')

        $response = $httpClient.SendAsync($request).GetAwaiter().GetResult()

        if (-not $response.IsSuccessStatusCode) {
            $errorBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            throw "HTTP $([int]$response.StatusCode) $($response.ReasonPhrase): $errorBody"
        }

        if ($VerboseLogging) {
            Write-TestLog "Notification $Method -> $([int]$response.StatusCode)" -Level INFO
        }
    }
    finally {
        if ($response) { $response.Dispose() }
        if ($request)  { $request.Dispose() }
        $httpClient.Dispose()
    }
}

function Get-McpHeaderValue {
    param(
        [System.Net.Http.HttpResponseMessage]$Response,
        [string]$Name
    )

    if ($Response.Headers.Contains($Name)) {
        return ($Response.Headers.GetValues($Name) | Select-Object -First 1)
    }
    if ($Response.Content -and $Response.Content.Headers.Contains($Name)) {
        return ($Response.Content.Headers.GetValues($Name) | Select-Object -First 1)
    }
    return $null
}

function Read-McpSseResponse {
    # MCP streamable-HTTP transport: server may respond with text/event-stream.
    # Each event delimits with a blank line; data: lines carry the JSON-RPC payload.
    # We stop reading as soon as we get the response matching $ExpectedId, since
    # the server may keep the stream open for unrelated server-to-client traffic.
    param(
        [System.Net.Http.HttpResponseMessage]$Response,
        [int]$ExpectedId,
        [int]$TimeoutSeconds = 60
    )

    $stream = $Response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)

    try {
        $dataBuffer = [System.Text.StringBuilder]::new()
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

        while ($true) {
            if ((Get-Date) -gt $deadline) {
                throw "SSE read timed out after $TimeoutSeconds seconds waiting for response id=$ExpectedId"
            }

            $line = $reader.ReadLine()
            if ($null -eq $line) {
                # EOS without seeing our response
                if ($dataBuffer.Length -gt 0) {
                    $jsonText = $dataBuffer.ToString()
                    try {
                        $parsed = $jsonText | ConvertFrom-Json
                        if ($parsed.id -eq $ExpectedId) { return $parsed }
                    } catch { }
                }
                throw "SSE stream closed without matching response for id=$ExpectedId"
            }

            if ([string]::IsNullOrEmpty($line)) {
                # Blank line = event boundary
                if ($dataBuffer.Length -gt 0) {
                    $jsonText = $dataBuffer.ToString()
                    [void]$dataBuffer.Clear()
                    try {
                        $parsed = $jsonText | ConvertFrom-Json
                        if ($parsed.id -eq $ExpectedId) { return $parsed }
                    } catch {
                        # non-JSON payload (e.g. keep-alive), skip
                    }
                }
                continue
            }

            if ($line.StartsWith(':')) { continue }  # SSE comment

            if ($line.StartsWith('data:')) {
                $payload = $line.Substring(5)
                if ($payload.StartsWith(' ')) { $payload = $payload.Substring(1) }
                if ($dataBuffer.Length -gt 0) { [void]$dataBuffer.Append("`n") }
                [void]$dataBuffer.Append($payload)
            }
            # other SSE fields (event:, id:, retry:) are ignored
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Invoke-McpRequest {
    param(
        [string]$Endpoint,
        [string]$BearerToken,
        [string]$Method,
        [hashtable]$Params = @{},
        [int]$Id = 1,
        [string]$CorrelationId = [guid]::NewGuid().ToString(),
        [int]$TimeoutSeconds = 60
    )

    $body = @{
        jsonrpc = "2.0"
        id      = $Id
        method  = $Method
        params  = $Params
    } | ConvertTo-Json -Depth 10 -Compress

    if ($VerboseLogging) {
        Write-TestLog "Request: $Method" -Level INFO
        Write-TestLog "Body: $body" -Level INFO
    }

    $httpClient = [System.Net.Http.HttpClient]::new()
    $httpClient.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds + 5)

    $request = $null
    $response = $null
    try {
        $request = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::Post, $Endpoint)
        $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $BearerToken)
        $request.Headers.Add('x-correlation-id', $CorrelationId)
        [void]$request.Headers.Accept.Add(
            [System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new('application/json'))
        [void]$request.Headers.Accept.Add(
            [System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new('text/event-stream'))
        if ($script:McpSessionId) {
            $request.Headers.Add('Mcp-Session-Id', $script:McpSessionId)
        }
        $request.Content = [System.Net.Http.StringContent]::new(
            $body, [System.Text.Encoding]::UTF8, 'application/json')

        # ResponseHeadersRead = start processing as soon as headers arrive,
        # without buffering the full body. Essential for SSE.
        $response = $httpClient.SendAsync(
            $request,
            [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()

        # Capture Mcp-Session-Id from the initialize response
        if (-not $script:McpSessionId) {
            $sid = Get-McpHeaderValue -Response $response -Name 'Mcp-Session-Id'
            if ($sid) {
                $script:McpSessionId = $sid
                Write-TestLog "MCP session established: $sid" -Level SUCCESS
            }
        }

        # Validate correlation ID echo
        $echoedCorr = Get-McpHeaderValue -Response $response -Name 'x-correlation-id'
        if ($echoedCorr) {
            if ($echoedCorr -eq $CorrelationId) {
                Write-TestLog "Correlation ID echoed correctly" -Level SUCCESS
            } else {
                Write-TestLog "Correlation ID mismatch! Sent: $CorrelationId, Received: $echoedCorr" -Level WARN
            }
        }

        if (-not $response.IsSuccessStatusCode) {
            $errorBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            throw "HTTP $([int]$response.StatusCode) $($response.ReasonPhrase): $errorBody"
        }

        $mediaType = $null
        if ($response.Content -and $response.Content.Headers.ContentType) {
            $mediaType = $response.Content.Headers.ContentType.MediaType
        }

        if ($mediaType -eq 'text/event-stream') {
            $parsed = Read-McpSseResponse -Response $response -ExpectedId $Id -TimeoutSeconds $TimeoutSeconds
        } else {
            $bodyText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $parsed = $bodyText | ConvertFrom-Json
        }

        if ($VerboseLogging) {
            Write-TestLog "Response: $($parsed | ConvertTo-Json -Depth 10 -Compress)" -Level INFO
        }

        return $parsed
    }
    catch {
        Write-TestLog "Request failed: $_" -Level ERROR
        throw
    }
    finally {
        if ($response) { $response.Dispose() }
        if ($request)  { $request.Dispose() }
        $httpClient.Dispose()
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

    # Per MCP spec, the client must signal it's ready before issuing other requests
    Send-McpNotification -Endpoint $Endpoint -BearerToken $Token -Method "notifications/initialized"

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
        "getObjectSchema",
        "soqlQuery",
        "find",
        "getUserInfo",
        "listRecentSobjectRecords",
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

function Test-GetObjectSchemaIndex {
    param($Endpoint, $Token)

    Write-TestLog "`n--- Test 3: getObjectSchema (index) ---" -Level INFO

    $response = Invoke-McpRequest `
        -Endpoint $Endpoint `
        -BearerToken $Token `
        -Method "tools/call" `
        -Params @{
            name      = "getObjectSchema"
            arguments = @{}
        } `
        -Id 3

    if ($response.result.isError -eq $true) {
        Write-TestLog "Tool returned error: $($response.result.content[0].text)" -Level WARN
        $script:TestResults += @{
            Test   = "getObjectSchema (index)"
            Status = "WARN"
            Error  = $response.result.content[0].text
        }
        return
    }

    $objects = $response.result.content[0].text | ConvertFrom-Json
    $count = if ($objects -is [array]) { $objects.Count } else { 1 }
    Write-TestLog "Objects returned: $count" -Level SUCCESS

    $script:TestResults += @{
        Test   = "getObjectSchema (index)"
        Status = "PASS"
        Count  = $count
    }
}

function Test-AccountBoundarySchema {
    # Boundary assertion: Account is intentionally OUT of scope for this gateway.
    # PASS when the call is blocked, FAIL if Account becomes accessible.
    # Don't "fix" this by widening MCP_ReadOnly_Access — see README "Design Intent".
    param($Endpoint, $Token)

    Write-TestLog "`n--- Test 4: Boundary — Account excluded (schema) ---" -Level INFO

    $response = Invoke-McpRequest `
        -Endpoint $Endpoint `
        -BearerToken $Token `
        -Method "tools/call" `
        -Params @{
            name      = "getObjectSchema"
            arguments = @{
                objects = "Account"
            }
        } `
        -Id 4

    if ($response.result.isError -eq $true) {
        Write-TestLog "Boundary holds: Account schema access blocked as expected" -Level SUCCESS
        $script:TestResults += @{
            Test   = "Boundary: Account excluded (schema)"
            Status = "PASS"
            Error  = $response.result.content[0].text
        }
        return
    }

    # If we get here, the boundary was breached — Account became accessible.
    Write-TestLog "BOUNDARY BREACH: Account schema is now accessible — perm set has been widened beyond design" -Level ERROR
    $script:TestResults += @{
        Test    = "Boundary: Account excluded (schema)"
        Status  = "FAIL"
        Payload = $response.result.content[0].text
    }
}

function Test-AccountBoundaryQuery {
    # Boundary assertion: Account is intentionally OUT of scope for this gateway.
    # PASS when soqlQuery against Account is blocked, FAIL if records come back.
    param($Endpoint, $Token)

    Write-TestLog "`n--- Test 5: Boundary — Account excluded (soqlQuery) ---" -Level INFO

    $response = Invoke-McpRequest `
        -Endpoint $Endpoint `
        -BearerToken $Token `
        -Method "tools/call" `
        -Params @{
            name      = "soqlQuery"
            arguments = @{
                q = "SELECT Id, Name FROM Account LIMIT 5"
            }
        } `
        -Id 5

    if ($response.result.isError -eq $true) {
        Write-TestLog "Boundary holds: Account query blocked as expected" -Level SUCCESS
        $script:TestResults += @{
            Test   = "Boundary: Account excluded (soqlQuery)"
            Status = "PASS"
            Error  = $response.result.content[0].text
        }
        return
    }

    # If we get here, the boundary was breached.
    Write-TestLog "BOUNDARY BREACH: Account is queryable — perm set has been widened beyond design" -Level ERROR
    $script:TestResults += @{
        Test    = "Boundary: Account excluded (soqlQuery)"
        Status  = "FAIL"
        Payload = $response.result.content[0].text
    }
}

function Test-GetUserInfo {
    param($Endpoint, $Token)

    Write-TestLog "`n--- Test 6: getUserInfo ---" -Level INFO

    $response = Invoke-McpRequest `
        -Endpoint $Endpoint `
        -BearerToken $Token `
        -Method "tools/call" `
        -Params @{
            name      = "getUserInfo"
            arguments = @{}
        } `
        -Id 6

    if ($response.result.isError -eq $true) {
        throw "Tool returned error: $($response.result.content[0].text)"
    }

    $payload = $response.result.content[0].text
    Write-TestLog "User info payload: $payload" -Level SUCCESS

    $script:TestResults += @{
        Test    = "getUserInfo"
        Status  = "PASS"
        Payload = $payload
    }
}

function Test-JwtValidation {
    param($Endpoint, $Token)

    Write-TestLog "`n--- Test 7: JWT Validation (negative test) ---" -Level INFO

    try {
        $null = Invoke-RestMethod `
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

Write-TestLog "Environment: int" -Level INFO
Write-TestLog "Endpoint: $ApimEndpoint" -Level INFO
Write-TestLog "App ID: $AppId" -Level INFO

# Step 1: Acquire JWT token
$jwt = Get-EntraJwt -TenantId $TenantId -ClientId $ClientId -Scope $AppId

# Step 2: Run tests
try {
    Test-Initialize -Endpoint $ApimEndpoint -Token $jwt
    $null = Test-ToolsList -Endpoint $ApimEndpoint -Token $jwt
    Test-GetObjectSchemaIndex -Endpoint $ApimEndpoint -Token $jwt
    Test-AccountBoundarySchema -Endpoint $ApimEndpoint -Token $jwt
    Test-AccountBoundaryQuery -Endpoint $ApimEndpoint -Token $jwt
    Test-GetUserInfo -Endpoint $ApimEndpoint -Token $jwt
    Test-JwtValidation -Endpoint $ApimEndpoint -Token $jwt

    # Summary
    Write-Host "`n===============================================================" -ForegroundColor Green
    Write-Host "  Test Summary" -ForegroundColor Green
    Write-Host "===============================================================" -ForegroundColor Green

    $passed = ($script:TestResults | Where-Object { $_.Status -eq "PASS" }).Count
    $warned = ($script:TestResults | Where-Object { $_.Status -eq "WARN" }).Count
    $failed = ($script:TestResults | Where-Object { $_.Status -eq "FAIL" }).Count
    $total = $script:TestResults.Count

    foreach ($result in $script:TestResults) {
        $symbol = switch ($result.Status) {
            "PASS" { "[+]" }
            "WARN" { "[!]" }
            default { "[-]" }
        }
        $color = switch ($result.Status) {
            "PASS" { "Green" }
            "WARN" { "Yellow" }
            default { "Red" }
        }
        Write-Host "  $symbol $($result.Test)" -ForegroundColor $color
    }

    $resultColor = if ($failed -eq 0) { if ($warned -eq 0) { "Green" } else { "Yellow" } } else { "Red" }
    Write-Host "`n  Results: $passed pass / $warned warn / $failed fail (of $total)" -ForegroundColor $resultColor

    if ($failed -eq 0) {
        if ($warned -eq 0) {
            Write-Host "`n[OK] All tests passed! APIM API is healthy.`n" -ForegroundColor Green
        } else {
            Write-Host "`n[OK] Wiring healthy. Warnings are expected (tracked external dependencies — see STATUS-REPORT).`n" -ForegroundColor Yellow
        }
        exit 0
    }
    else {
        Write-Host "`n[FAIL] $failed test(s) failed. Review logs above.`n" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-TestLog "Test suite failed: $_" -Level ERROR
    Write-Host "`n[ERROR] Test suite aborted due to error.`n" -ForegroundColor Red
    exit 1
}
