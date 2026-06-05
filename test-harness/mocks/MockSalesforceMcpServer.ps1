<#
.SYNOPSIS
    Mock Salesforce MCP Server for Dev environment testing
.DESCRIPTION
    Implements the Salesforce Hosted MCP Server protocol (JSON-RPC 2.0)
    for the sobject-reads server. Returns synthetic data for all 6 tools.
.PARAMETER Port
    HTTP listener port (default: 8080)
.PARAMETER Verbose
    Enable verbose logging of all requests/responses
.EXAMPLE
    .\MockSalesforceMcpServer.ps1 -Port 8080 -Verbose
#>

param(
    [int]$Port = 8080,
    [switch]$VerboseLogging
)

$ErrorActionPreference = "Stop"

# Mock data store
$script:MockData = @{
    ServerInfo = @{
        name    = "sobject-reads"
        version = "1.0.0-mock"
    }

    SObjects = @(
        @{ name = "Account"; label = "Account"; keyPrefix = "001" }
        @{ name = "Contact"; label = "Contact"; keyPrefix = "003" }
        @{ name = "Opportunity"; label = "Opportunity"; keyPrefix = "006" }
        @{ name = "Case"; label = "Case"; keyPrefix = "500" }
        @{ name = "Lead"; label = "Lead"; keyPrefix = "00Q" }
        @{ name = "Task"; label = "Task"; keyPrefix = "00T" }
        @{ name = "Event"; label = "Event"; keyPrefix = "00U" }
        @{ name = "User"; label = "User"; keyPrefix = "005" }
    )

    AccountFields = @(
        @{ name = "Id"; type = "id"; label = "Account ID" }
        @{ name = "Name"; type = "string"; label = "Account Name" }
        @{ name = "BillingStreet"; type = "string"; label = "Billing Street" }
        @{ name = "BillingCity"; type = "string"; label = "Billing City" }
        @{ name = "BillingState"; type = "string"; label = "Billing State" }
        @{ name = "Phone"; type = "phone"; label = "Phone" }
        @{ name = "Website"; type = "url"; label = "Website" }
        @{ name = "Industry"; type = "picklist"; label = "Industry" }
        @{ name = "AnnualRevenue"; type = "currency"; label = "Annual Revenue" }
    )
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "INFO"  { "Cyan" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function New-JsonRpcResponse {
    param(
        [Parameter(Mandatory)]
        $Id,
        [Parameter(Mandatory)]
        $Result
    )

    return @{
        jsonrpc = "2.0"
        id      = $Id
        result  = $Result
    } | ConvertTo-Json -Depth 10 -Compress
}

function New-JsonRpcError {
    param(
        [Parameter(Mandatory)]
        $Id,
        [Parameter(Mandatory)]
        [int]$Code,
        [Parameter(Mandatory)]
        [string]$Message
    )

    return @{
        jsonrpc = "2.0"
        id      = $Id
        error   = @{
            code    = $Code
            message = $Message
        }
    } | ConvertTo-Json -Depth 10 -Compress
}

function Handle-Initialize {
    param($Id)

    $result = @{
        protocolVersion = "2024-11-05"
        capabilities    = @{
            tools     = @{}
            resources = @{ subscribe = $true }
        }
        serverInfo      = $script:MockData.ServerInfo
    }

    return New-JsonRpcResponse -Id $Id -Result $result
}

function Handle-ToolsList {
    param($Id)

    $tools = @(
        @{
            name        = "getSobjectSchema"
            description = "Returns Salesforce object schema. Call with no params for compact index; call with object-name for full field schema."
            inputSchema = @{
                type       = "object"
                properties = @{
                    "object-name" = @{ type = "string" }
                }
                required   = @()
            }
            annotations = @{ readOnlyHint = $true }
        },
        @{
            name        = "soqlQuery"
            description = "Runs a SOQL query to retrieve Salesforce records."
            inputSchema = @{
                type       = "object"
                properties = @{
                    query = @{ type = "string" }
                }
                required   = @("query")
            }
            annotations = @{ readOnlyHint = $true }
        },
        @{
            name        = "soslSearch"
            description = "Runs a SOSL text search across multiple objects."
            inputSchema = @{
                type       = "object"
                properties = @{
                    search = @{ type = "string" }
                }
                required   = @("search")
            }
            annotations = @{ readOnlyHint = $true }
        },
        @{
            name        = "getUserIdentity"
            description = "Returns identity for the currently authenticated user."
            inputSchema = @{
                type       = "object"
                properties = @{}
                required   = @()
            }
            annotations = @{ readOnlyHint = $true }
        },
        @{
            name        = "getRecentItems"
            description = "Retrieves recently viewed/modified records of a given type."
            inputSchema = @{
                type       = "object"
                properties = @{
                    "sobject-name" = @{ type = "string" }
                }
                required   = @("sobject-name")
            }
            annotations = @{ readOnlyHint = $true }
        },
        @{
            name        = "getRelatedRecords"
            description = "Fetches child records related to a parent via relationship path."
            inputSchema = @{
                type       = "object"
                properties = @{
                    "sobject-name"      = @{ type = "string" }
                    id                   = @{ type = "string" }
                    "relationship-path" = @{ type = "string" }
                }
                required   = @("sobject-name", "id", "relationship-path")
            }
            annotations = @{ readOnlyHint = $true }
        }
    )

    $result = @{ tools = $tools }
    return New-JsonRpcResponse -Id $Id -Result $result
}

function Handle-ToolsCall {
    param($Id, $Name, $Arguments)

    Write-Log "Tool call: $Name with args: $($Arguments | ConvertTo-Json -Compress)" -Level "INFO"

    switch ($Name) {
        "getSobjectSchema" {
            $objectName = $Arguments."object-name"
            if ([string]::IsNullOrEmpty($objectName)) {
                # Return compact index
                $content = $script:MockData.SObjects | ConvertTo-Json -Compress
            }
            else {
                # Return field schema for specific object
                if ($objectName -eq "Account") {
                    $content = $script:MockData.AccountFields | ConvertTo-Json -Compress
                }
                else {
                    $content = @"
[{"name":"Id","type":"id","label":"Record ID"},{"name":"Name","type":"string","label":"Name"}]
"@
                }
            }

            $result = @{
                content = @(@{ type = "text"; text = $content })
                isError = $false
            }
            return New-JsonRpcResponse -Id $Id -Result $result
        }

        "soqlQuery" {
            $query = $Arguments.query
            if ([string]::IsNullOrEmpty($query)) {
                $result = @{
                    content = @(@{ type = "text"; text = "INVALID_QUERY: query parameter is required" })
                    isError = $true
                }
                return New-JsonRpcResponse -Id $Id -Result $result
            }

            # Generate mock records
            $mockRecords = @(
                @{ Id = "001xx000001XyzAAA"; Name = "Acme Corp"; Industry = "Technology"; AnnualRevenue = 5000000 }
                @{ Id = "001xx000001XyzAAB"; Name = "Global Industries"; Industry = "Manufacturing"; AnnualRevenue = 12000000 }
                @{ Id = "001xx000001XyzAAC"; Name = "Tech Solutions Inc"; Industry = "Technology"; AnnualRevenue = 3000000 }
            )

            $content = $mockRecords | ConvertTo-Json -Compress
            $result = @{
                content = @(@{ type = "text"; text = $content })
                isError = $false
            }
            return New-JsonRpcResponse -Id $Id -Result $result
        }

        "soslSearch" {
            $search = $Arguments.search
            $mockResults = @(
                @{ Id = "001xx000001XyzAAA"; Name = "Acme Corp"; Type = "Account" }
                @{ Id = "003xx000001XyzAAA"; Name = "John Smith"; Type = "Contact" }
            )

            $content = $mockResults | ConvertTo-Json -Compress
            $result = @{
                content = @(@{ type = "text"; text = $content })
                isError = $false
            }
            return New-JsonRpcResponse -Id $Id -Result $result
        }

        "getUserIdentity" {
            $identity = @{
                user_id       = "005xx000001XyzAAA"
                username      = "mockuser@example.com"
                display_name  = "Mock User"
                email         = "mockuser@example.com"
                organization_id = "00Dxx0000001gEREAY"
            }

            $content = $identity | ConvertTo-Json -Compress
            $result = @{
                content = @(@{ type = "text"; text = $content })
                isError = $false
            }
            return New-JsonRpcResponse -Id $Id -Result $result
        }

        "getRecentItems" {
            $mockRecent = @(
                @{ Id = "001xx000001XyzAAA"; Name = "Recent Account 1" }
                @{ Id = "001xx000001XyzAAB"; Name = "Recent Account 2" }
            )

            $content = $mockRecent | ConvertTo-Json -Compress
            $result = @{
                content = @(@{ type = "text"; text = $content })
                isError = $false
            }
            return New-JsonRpcResponse -Id $Id -Result $result
        }

        "getRelatedRecords" {
            $mockRelated = @(
                @{ Id = "003xx000001XyzAAA"; Name = "Related Contact 1" }
                @{ Id = "003xx000001XyzAAB"; Name = "Related Contact 2" }
            )

            $content = $mockRelated | ConvertTo-Json -Compress
            $result = @{
                content = @(@{ type = "text"; text = $content })
                isError = $false
            }
            return New-JsonRpcResponse -Id $Id -Result $result
        }

        default {
            $result = @{
                content = @(@{ type = "text"; text = "ERROR: Unknown tool '$Name'" })
                isError = $true
            }
            return New-JsonRpcResponse -Id $Id -Result $result
        }
    }
}

function Handle-Request {
    param([string]$Body)

    try {
        $request = $Body | ConvertFrom-Json

        if ($VerboseLogging) {
            Write-Log "Request: $Body" -Level "INFO"
        }

        # Handle JSON-RPC methods
        switch ($request.method) {
            "initialize" {
                return Handle-Initialize -Id $request.id
            }

            "notifications/initialized" {
                # No response needed for notifications
                return $null
            }

            "tools/list" {
                return Handle-ToolsList -Id $request.id
            }

            "tools/call" {
                $name = $request.params.name
                $arguments = $request.params.arguments
                return Handle-ToolsCall -Id $request.id -Name $name -Arguments $arguments
            }

            default {
                return New-JsonRpcError -Id $request.id -Code -32601 -Message "Method not found: $($request.method)"
            }
        }
    }
    catch {
        Write-Log "Error processing request: $_" -Level "ERROR"
        return New-JsonRpcError -Id 0 -Code -32700 -Message "Parse error: $_"
    }
}

# Start HTTP listener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

Write-Log "🚀 Mock Salesforce MCP Server started on http://localhost:$Port" -Level "INFO"
Write-Log "📋 Implements: sobject-reads (6 tools)" -Level "INFO"
Write-Log "🔧 Press Ctrl+C to stop" -Level "INFO"

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        Write-Log "→ $($request.HttpMethod) $($request.Url.PathAndQuery)" -Level "INFO"

        # Read request body
        $reader = New-Object System.IO.StreamReader($request.InputStream)
        $body = $reader.ReadToEnd()
        $reader.Close()

        # Process request
        $responseBody = Handle-Request -Body $body

        if ($null -ne $responseBody) {
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
            $response.ContentType = "application/json"
            $response.ContentLength64 = $buffer.Length
            $response.StatusCode = 200
            $response.OutputStream.Write($buffer, 0, $buffer.Length)

            if ($VerboseLogging) {
                Write-Log "Response: $responseBody" -Level "INFO"
            }
        }
        else {
            $response.StatusCode = 204  # No Content for notifications
        }

        $response.Close()
        Write-Log "← $($response.StatusCode)" -Level "INFO"
    }
}
finally {
    $listener.Stop()
    Write-Log "Mock server stopped" -Level "INFO"
}
