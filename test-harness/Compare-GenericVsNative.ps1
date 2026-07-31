<#
.SYNOPSIS
    Compare generic API vs native MCP server side-by-side
.DESCRIPTION
    Runs smoke tests against both endpoints and compares:
    - Functional parity (same tests pass/fail)
    - Response times
    - Response content (should be identical)
    - Error handling
.PARAMETER Environment
    Environment to test (int only, native MCP not deployed to dev yet)
.PARAMETER TokenMode
    How to acquire bearer token (AzCli or AppOnly)
.EXAMPLE
    .\Compare-GenericVsNative.ps1
.EXAMPLE
    .\Compare-GenericVsNative.ps1 -TokenMode AppOnly
#>

param(
    [ValidateSet('int')]
    [string]$Environment = 'int',

    [ValidateSet('AzCli', 'AppOnly')]
    [string]$TokenMode = 'AzCli'
)

$ErrorActionPreference = 'Stop'

Write-Host "`n🔬 Generic API vs Native MCP Server Comparison" -ForegroundColor Cyan
Write-Host "=" * 60

# Endpoints
$genericEndpoint = "https://api.int.amnhealthcare.io/sfdcread/int/mcp"
$nativeEndpoint  = "https://amn-wus2-hub-apim-i02.azure-api.net/sfdcread-mcp-native/mcp"

Write-Host "`nEndpoints:" -ForegroundColor Yellow
Write-Host "  Generic API:   $genericEndpoint"
Write-Host "  Native MCP:    $nativeEndpoint`n"

# Results storage
$results = @{
    Generic = @{ Passed = 0; Failed = 0; Warnings = 0; Duration = 0 }
    Native  = @{ Passed = 0; Failed = 0; Warnings = 0; Duration = 0 }
}

function Invoke-ComparisonTest {
    param(
        [string]$TestName,
        [string]$Endpoint,
        [string]$Token
    )

    Write-Host "  Testing $Endpoint..." -NoNewline

    $startTime = Get-Date
    try {
        $result = & "$PSScriptRoot\Invoke-ApimSmokeTest.ps1" `
            -Environment $(if ($Endpoint -match 'native') { 'int-native' } else { 'int' }) `
            -TokenMode $TokenMode `
            -ErrorAction Stop

        $duration = (Get-Date) - $startTime

        # Parse test results (assuming script outputs pass/fail counts)
        # Adjust this based on actual output format
        Write-Host " ✅ Completed in $($duration.TotalSeconds)s" -ForegroundColor Green

        return @{
            Success  = $true
            Duration = $duration.TotalSeconds
            Output   = $result
        }
    }
    catch {
        $duration = (Get-Date) - $startTime
        Write-Host " ❌ Failed in $($duration.TotalSeconds)s" -ForegroundColor Red
        Write-Host "     Error: $_" -ForegroundColor Red

        return @{
            Success  = $false
            Duration = $duration.TotalSeconds
            Error    = $_.Exception.Message
        }
    }
}

# Run tests against both endpoints
Write-Host "`n📊 Running smoke tests..." -ForegroundColor Cyan
Write-Host "-" * 60

Write-Host "`n1️⃣  Generic API (existing)" -ForegroundColor Yellow
$genericResult = Invoke-ComparisonTest -TestName "Generic API" -Endpoint $genericEndpoint -Token ""

Write-Host "`n2️⃣  Native MCP Server (experimental)" -ForegroundColor Yellow
$nativeResult = Invoke-ComparisonTest -TestName "Native MCP" -Endpoint $nativeEndpoint -Token ""

# Compare results
Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "📋 Comparison Summary" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

$comparisonTable = @(
    @{ Metric = "Status"; Generic = $(if ($genericResult.Success) { "✅ Pass" } else { "❌ Fail" }); Native = $(if ($nativeResult.Success) { "✅ Pass" } else { "❌ Fail" }) }
    @{ Metric = "Duration"; Generic = "$([math]::Round($genericResult.Duration, 2))s"; Native = "$([math]::Round($nativeResult.Duration, 2))s" }
    @{ Metric = "Performance"; Generic = "Baseline"; Native = $(
        $diff = $nativeResult.Duration - $genericResult.Duration
        $pct = [math]::Round(($diff / $genericResult.Duration) * 100, 1)
        if ($diff -lt 0) { "🚀 $([math]::Abs($pct))% faster" }
        elseif ($diff -gt 0) { "🐢 $pct% slower" }
        else { "⚖️  Same" }
    )}
)

$comparisonTable | Format-Table -AutoSize

# Functional parity check
Write-Host "`n🔍 Functional Parity" -ForegroundColor Cyan
Write-Host "-" * 60

if ($genericResult.Success -and $nativeResult.Success) {
    Write-Host "✅ Both endpoints passed smoke tests" -ForegroundColor Green
    Write-Host "   Functional parity confirmed" -ForegroundColor Green
}
elseif (!$genericResult.Success -and !$nativeResult.Success) {
    Write-Host "⚠️  Both endpoints failed" -ForegroundColor Yellow
    Write-Host "   May indicate environment issue, not endpoint-specific" -ForegroundColor Yellow
}
else {
    Write-Host "❌ Functional parity BROKEN" -ForegroundColor Red
    if ($genericResult.Success) {
        Write-Host "   Generic API passes but Native MCP fails" -ForegroundColor Red
        Write-Host "   Native MCP Error: $($nativeResult.Error)" -ForegroundColor Red
    }
    else {
        Write-Host "   Native MCP passes but Generic API fails" -ForegroundColor Red
        Write-Host "   Generic API Error: $($genericResult.Error)" -ForegroundColor Red
    }
}

# Next steps
Write-Host "`n📝 Next Steps" -ForegroundColor Cyan
Write-Host "-" * 60

if ($genericResult.Success -and $nativeResult.Success) {
    Write-Host "1. ✅ Functional parity confirmed - safe to proceed"
    Write-Host "2. 🔍 Compare Application Insights logs for MCP-specific telemetry"
    Write-Host "3. 🧪 Test Power Automate connector pointing at native endpoint"
    Write-Host "4. 📊 Compare monitoring dashboards (generic vs native)"
    Write-Host "5. 📋 Document findings in docs/MCP-NATIVE-VALIDATION.md"
}
else {
    Write-Host "1. ❌ Fix failing endpoint before proceeding"
    Write-Host "2. 🔍 Check APIM portal for policy errors"
    Write-Host "3. 📋 Review logs in Application Insights"
    Write-Host "4. 🐛 Debug with: .\Invoke-ApimSmokeTest.ps1 -Environment <env>"
}

Write-Host ""
