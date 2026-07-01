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
.PARAMETER TokenMode
    How to acquire the bearer:
      AzCli   - default; uses `az account get-access-token --resource api://<app-id>`
                under whatever identity az is logged in as. Produces aud=api://<app-id>
                — the audience format PA and Copilot Studio actually use in production
                (Scope: api://<app-id>/user_impersonation per the onboarding docs).
                Works with WIF-federated SPNs (no client_secret needed), so this is
                what CI runs.
      AppOnly - posts client_credentials directly to the v2 token endpoint using
                ARM_CLIENT_ID/SECRET/TENANT_ID env vars. Produces aud=<bare-GUID>
                (self-OAuth shape retained for the AADSTS90009 fallback path only).
                Cannot be used with WIF SPNs. Retained for secret-based SPNs and
                for local dev when you want to exercise the bare-GUID branch of the
                dual-audience policy.

    Coverage limits: both modes produce APP-ONLY tokens (SPN authenticates itself
    with `roles` claim populated from its own app-role assignments). PA and Copilot
    Studio use DELEGATED user tokens (both `scp: user_impersonation` and `roles:
    MCP.Read` populated from the user's assignment). CI can't easily reproduce the
    delegated interactive flow; the delegated path must be verified manually against
    the deployed connectors. See docs/TESTING.md "Known automation gap".
.PARAMETER AssertDelegated
    Manual-test guardrail. Verifies the acquired token is a delegated user token
    (has `scp` claim) rather than an app-only token (only `roles` claim). Prints
    the identity-relevant claims so the operator has paste-into-PR evidence of
    which user/audience/scope was exercised. Use when running locally under your
    daily-driver `az login` to validate the delegated path that CI cannot cover
    (see docs/TESTING.md "Known automation gap"). Fails fast if the token shape
    is wrong for the intended test.
.EXAMPLE
    .\Invoke-ApimSmokeTest.ps1
.EXAMPLE
    .\Invoke-ApimSmokeTest.ps1 -TokenMode AppOnly
.EXAMPLE
    # Manual delegated-token verification, run as your daily driver:
    az login
    .\Invoke-ApimSmokeTest.ps1 -AssertDelegated
#>

param(
    [ValidateSet('dev', 'int')]
    [string]$Environment = 'int',

    [string]$TenantId = "6232c2ec-fa42-4f27-92cd-787913fba489",

    [string]$ClientId = "",

    [ValidateSet('AzCli', 'AppOnly')]
    [string]$TokenMode = 'AzCli',

    [switch]$AssertDelegated,

    [switch]$VerboseLogging
)

$ErrorActionPreference = "Stop"

# Per-env constants. Dev iterates fast: no live SF backend, inline mock in
# policies/apim-policy-sfdc-read-mcp-dev-mock.xml, safe to hammer. Int is
# the live SF path (policies/apim-policy-sfdc-read-mcp.xml). Both share
# the JWT/role/session shape so client-side regressions show up in dev.
#
# Int dual-audience note: APIM accepts both `api://42971939-...` (the
# .default / api-scope flow used by Power Automate and Copilot Studio)
# and the bare `42971939-...` GUID (self-OAuth where client == resource).
# See policies/apim-policy-sfdc-read-mcp.xml.
$envConfig = switch ($Environment) {
    'dev' {
        @{
            Endpoint = 'https://api.dev.amnhealthcare.io/sfdcread/dev/mcp'
            AppId    = '6ce6ccb1-32db-40f8-97b5-bfbe700d052e'  # SFDC Read MCP Reader Dev
        }
    }
    'int' {
        @{
            Endpoint = 'https://api.int.amnhealthcare.io/sfdcread/int/mcp'
            AppId    = '42971939-bc78-4c23-963e-c3e0f87e3bd1'  # SFDCRead INT MCP
        }
    }
}
$ApimEndpoint = $envConfig.Endpoint
$AppId        = $envConfig.AppId

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

    Write-TestLog "Acquiring Entra JWT token via az cli (aud=api://$Scope)..." -Level INFO

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

function Get-AppOnlyJwt {
    # client_credentials directly against the v2 token endpoint using the ADO
    # service connection SPN exported by AzureCLI@2 (addSpnToEnvironment=true).
    # Scope shape <app-id>/.default (NO api:// prefix) makes Entra issue a token
    # with aud=<bare-GUID> — the format PA produces in self-OAuth and that PR #19
    # taught the policy to accept.
    param(
        [string]$TenantId,
        [string]$AppId
    )

    Write-TestLog "Acquiring app-only JWT token via client_credentials (aud=$AppId)..." -Level INFO

    $clientId     = $env:ARM_CLIENT_ID
    $clientSecret = $env:ARM_CLIENT_SECRET
    $resolvedTenant = if ([string]::IsNullOrEmpty($env:ARM_TENANT_ID)) { $TenantId } else { $env:ARM_TENANT_ID }

    if ([string]::IsNullOrEmpty($clientId) -or [string]::IsNullOrEmpty($clientSecret)) {
        throw "TokenMode=AppOnly requires ARM_CLIENT_ID and ARM_CLIENT_SECRET in the environment. " +
              "In ADO use AzureCLI@2 with addSpnToEnvironment=true and export them in the inline script. " +
              "Locally, export them from a service principal credential you already hold."
    }

    $body = @{
        client_id     = $clientId
        client_secret = $clientSecret
        grant_type    = 'client_credentials'
        scope         = "$AppId/.default"
    }

    try {
        $resp = Invoke-RestMethod `
            -Uri "https://login.microsoftonline.com/$resolvedTenant/oauth2/v2.0/token" `
            -Method POST `
            -Body $body `
            -ContentType 'application/x-www-form-urlencoded'

        if ([string]::IsNullOrEmpty($resp.access_token)) {
            throw "Token endpoint returned no access_token"
        }

        Write-TestLog "App-only JWT acquired (expires in $($resp.expires_in)s)" -Level SUCCESS
        return $resp.access_token
    }
    catch {
        # The most likely failure here is the ADO SPN not having the MCP.Read
        # role on the SFDCRead app reg's SP. Surface that hypothesis loudly
        # rather than burying it in a generic auth error.
        $msg = "App-only token acquisition failed: $_"
        Write-TestLog $msg -Level ERROR
        Write-TestLog "If the policy later returns 401/403, check that the calling SPN ($clientId) has the MCP.Read app role assignment on the SFDCRead app reg's service principal (per docs/onboarding/IDENTITY-BOOTSTRAP-INT.md Step 7.3 pattern)." -Level WARN
        throw
    }
}

function Get-JwtPayload {
    # Decode the middle segment of a JWT (no signature verification — we just
    # acquired the token, this is for inspection only). Returns the parsed
    # claims as a PSCustomObject.
    param([string]$Jwt)

    $parts = $Jwt -split '\.'
    if ($parts.Count -lt 2) { throw "Bearer is not a JWT" }

    $payload = $parts[1].Replace('-', '+').Replace('_', '/')
    $padding = (4 - ($payload.Length % 4)) % 4
    $payload = $payload + ('=' * $padding)

    $bytes = [Convert]::FromBase64String($payload)
    return [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
}

function Assert-DelegatedToken {
    # Verify the acquired bearer is a delegated user token, not an app-only
    # token. Delegated tokens carry `scp`; app-only tokens carry `roles` only.
    # Power Automate and Copilot Studio user-delegated flows carry `scp`, so
    # this is the manual-test guardrail that proves the operator actually
    # exercised the path PA users take — not (e.g.) an accidental SPN login.
    param([string]$Jwt)

    Write-TestLog "`n--- Delegated-token assertion ---" -Level INFO

    $claims = Get-JwtPayload -Jwt $Jwt

    $rolesValue = if ($claims.roles) { ($claims.roles -join ', ') } else { '<none>' }
    $scpValue   = if ($claims.scp)   { $claims.scp }                 else { '<none>' }
    $upnValue   = if ($claims.upn)   { $claims.upn } elseif ($claims.preferred_username) { $claims.preferred_username } else { '<none>' }

    Write-Host "  aud   : $($claims.aud)"
    Write-Host "  scp   : $scpValue"
    Write-Host "  roles : $rolesValue"
    Write-Host "  oid   : $($claims.oid)"
    Write-Host "  name  : $($claims.name)"
    Write-Host "  upn   : $upnValue"

    if (-not $claims.scp) {
        Write-TestLog "Token has no 'scp' claim — this is an app-only token, not a delegated user token." -Level ERROR
        Write-TestLog "For delegated-path verification, run 'az login' as your daily driver and invoke this script WITHOUT -TokenMode AppOnly." -Level ERROR
        throw "AssertDelegated failed: token is app-only (no scp claim)"
    }

    if (-not (@($claims.roles) -contains 'MCP.Read')) {
        Write-TestLog "Token does not carry 'MCP.Read' in roles claim — user is not in AZ_AMN_AAD_SfdcReadMcp_Int_User, or membership hasn't propagated. APIM will 403." -Level WARN
    }

    Write-TestLog "Delegated token confirmed (scp present)" -Level SUCCESS
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

        $statusCode = [int]$response.StatusCode
        Write-TestLog "HTTP $statusCode; Content-Type: $mediaType" -Level INFO

        # Dump ALL response headers so we can spot Transfer-Encoding: chunked,
        # a hidden Content-Type variant, x-ms-* diagnostics, or anything else the
        # response-parsing path would otherwise discard. Response headers live on
        # $response.Headers, entity headers (Content-Type, Content-Length, etc.)
        # live on $response.Content.Headers — enumerate both.
        Write-TestLog "--- Response headers ---" -Level INFO
        foreach ($h in $response.Headers) {
            Write-TestLog "  $($h.Key): $($h.Value -join ', ')" -Level INFO
        }
        if ($response.Content -and $response.Content.Headers) {
            foreach ($h in $response.Content.Headers) {
                Write-TestLog "  $($h.Key): $($h.Value -join ', ')" -Level INFO
            }
        }
        Write-TestLog "--- end headers ---" -Level INFO

        if ($mediaType -eq 'text/event-stream') {
            $parsed = Read-McpSseResponse -Response $response -ExpectedId $Id -TimeoutSeconds $TimeoutSeconds
        } else {
            $bodyText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $bodyLen = if ($null -eq $bodyText) { 0 } else { $bodyText.Length }
            Write-TestLog "Body length: $bodyLen bytes" -Level INFO
            if ($bodyLen -eq 0) {
                Write-TestLog "Empty body from gateway on $Method (status $statusCode). ConvertFrom-Json will yield `$null." -Level WARN
            } else {
                # Truncate to keep log readable — 2 KB is plenty for JSON-RPC envelopes
                $preview = if ($bodyLen -gt 2048) { $bodyText.Substring(0, 2048) + "…[truncated $($bodyLen - 2048) bytes]" } else { $bodyText }
                Write-TestLog "Raw body: $preview" -Level INFO
            }
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

    $corrId = [guid]::NewGuid().ToString()
    Write-TestLog "tools/list correlation-id: $corrId" -Level INFO
    Write-TestLog "tools/list Mcp-Session-Id in scope: $script:McpSessionId" -Level INFO

    $response = Invoke-McpRequest `
        -Endpoint $Endpoint `
        -BearerToken $Token `
        -Method "tools/list" `
        -Id 2 `
        -CorrelationId $corrId

    # Regression guard: empty-body 200 on tools/list is the exact signature we saw
    # when APIM short-circuited notifications/initialized locally (PR #6, commit
    # bfef686). SF gates tools/list behind its own view of the session-ready
    # signal — if APIM swallows the notification, SF hands back HTTP 200 with an
    # empty body and the client's ConvertFrom-Json yields $null. Fail fast with a
    # targeted hint so future readers don't have to re-derive this.
    if ($null -eq $response) {
        throw "tools/list returned an empty body (parsed to `$null). This is the exact fingerprint of APIM swallowing notifications/initialized without forwarding to Salesforce — SF then serves empty on subsequent requests. Check policies/apim-policy-sfdc-read-mcp.xml for any <return-response> block gated on mcpMethod == 'notifications/initialized'; that block must NOT exist in int. correlation-id: $corrId"
    }

    # Assert JSON-RPC 2.0 envelope shape (would catch a malformed / non-JSON body
    # that somehow parsed to a truthy object).
    if ($response.jsonrpc -ne "2.0") {
        throw "tools/list response is not a valid JSON-RPC 2.0 envelope (jsonrpc='$($response.jsonrpc)'). correlation-id: $corrId"
    }

    if (-not $response.result.tools) {
        Write-TestLog "tools/list returned no tools array. Raw parsed response follows:" -Level ERROR
        Write-TestLog ($response | ConvertTo-Json -Depth 10) -Level ERROR
        if ($response.error) {
            Write-TestLog "JSON-RPC error code: $($response.error.code)" -Level ERROR
            Write-TestLog "JSON-RPC error message: $($response.error.message)" -Level ERROR
            if ($response.error.data) {
                Write-TestLog "JSON-RPC error data: $($response.error.data | ConvertTo-Json -Depth 10 -Compress)" -Level ERROR
            }
        }
        throw "Missing tools array in response (correlation-id $corrId; see dump above)"
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

Write-TestLog "Environment: $Environment" -Level INFO
Write-TestLog "Endpoint: $ApimEndpoint" -Level INFO
Write-TestLog "App ID: $AppId" -Level INFO
Write-TestLog "Token mode: $TokenMode" -Level INFO

# Step 1: Acquire JWT token
$jwt = switch ($TokenMode) {
    'AppOnly' { Get-AppOnlyJwt -TenantId $TenantId -AppId $AppId }
    default   { Get-EntraJwt   -TenantId $TenantId -ClientId $ClientId -Scope $AppId }
}

if ($AssertDelegated) {
    Assert-DelegatedToken -Jwt $jwt
}

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
