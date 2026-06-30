#Requires -Version 7.0
#Requires -Modules Az.Accounts

<#
.SYNOPSIS
  Add Azure CLI to preAuthorizedApplications on the SFDCRead INT MCP app reg.

.DESCRIPTION
  Follows the canonical ADM elevation pattern documented in
  amn-ops-ai-plugin-marketplace/setup/scripts/ADM-ELEVATION-PATTERN.md.

  Critical rule from that pattern: use Az PowerShell SDK (Connect-AzAccount),
  NOT azure cli. `az login` changes auth GLOBALLY per Windows user, which
  breaks Claude Code, other terminals, and any tool using DefaultAzureCredential
  with az CLI fallback. Connect-AzAccount creates an ISOLATED context.

  This script:
    - Runs from your daily-driver shell.
    - Prompts you to elevate; Connect-AzAccount opens device-code auth for
      your .adm account in an isolated PowerShell context.
    - PATCHes Microsoft Graph via Invoke-AzRestMethod (no az CLI calls).
    - Disconnect-AzAccount in finally — guarantees cleanup.
    - Your `az` daily-driver session is untouched throughout.

  After it succeeds, you can run the smoke test on your daily-driver
  immediately. No `az account clear` needed.

.PARAMETER WhatIf
  Standard PowerShell WhatIf. Reports what would change, does not patch.

.EXAMPLE
  .\infrastructure\scripts\Add-AzureCliPreAuth-Int.ps1 -WhatIf
  .\infrastructure\scripts\Add-AzureCliPreAuth-Int.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$AppObjectId    = "def34cbb-e8fd-4a31-b4c4-b475db090d9e",
    [string]$AppId          = "42971939-bc78-4c23-963e-c3e0f87e3bd1",
    [string]$AppDisplayName = "SFDCRead INT MCP",
    [string]$AzureCliAppId  = "04b07795-8ddb-461a-bbee-02f9e1bf7b46",
    [string]$ApimAppId      = "8602e328-9b72-4f2d-a4ae-1387d013a2b3",
    [string]$UserImpScopeId = "7f9d31f4-e830-4af1-99c1-fdb7667fba8e",
    [string]$TenantId       = "6232c2ec-fa42-4f27-92cd-787913fba489"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Prompt for elevation ──

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ADM elevation required" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will PATCH Microsoft Graph to add Azure CLI to the" -ForegroundColor White
Write-Host "preAuthorizedApplications list on '$AppDisplayName'." -ForegroundColor White
Write-Host ""
Write-Host "You will be prompted to authenticate with your .adm account via" -ForegroundColor White
Write-Host "device code. Sign in with e.g. Bart.Elia.adm@amnhealthcare.onmicrosoft.com" -ForegroundColor Yellow
Write-Host ""
Write-Host "Your Azure CLI session (daily-driver) is NOT affected — Connect-AzAccount" -ForegroundColor Green
Write-Host "uses an isolated PowerShell context. See:" -ForegroundColor Green
Write-Host "  amn-ops-ai-plugin-marketplace/setup/scripts/ADM-ELEVATION-PATTERN.md" -ForegroundColor DarkGray
Write-Host ""
Write-Host "This script calls Microsoft Graph only — no Azure subscription operations." -ForegroundColor Green
Write-Host "The Az.Accounts interactive subscription picker is suppressed for this" -ForegroundColor Green
Write-Host "session; whichever subscription the SDK auto-selects is fine." -ForegroundColor Green
Write-Host ""

$go = Read-Host "Ready to elevate? (Y/N)"
if ($go -notmatch '^[Yy]') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

try {
    # ── Elevate ──

    Write-Host ""
    Write-Host "Connecting to Azure PowerShell (isolated context)..." -ForegroundColor Yellow
    # -WhatIf:$false on auth + read-only Graph GETs so dry-run still authenticates
    # and inspects current state. The Graph PATCH below stays gated by the explicit
    # $PSCmdlet.ShouldProcess() — that's the only mutation the script performs.
    # Update-AzConfig -LoginExperienceV2 Off suppresses the Az.Accounts 3.x+ interactive
    # subscription picker. -Scope Process scopes the change to this PowerShell process
    # only, so the user's other Az sessions are unaffected. Safe to set unconditionally
    # because the script never reads or writes subscription-scoped resources — Graph only.
    Update-AzConfig -LoginExperienceV2 Off -Scope Process -WhatIf:$false | Out-Null
    Disconnect-AzAccount -ErrorAction SilentlyContinue -WhatIf:$false | Out-Null
    Connect-AzAccount -TenantId $TenantId -UseDeviceAuthentication -ErrorAction Stop -WhatIf:$false | Out-Null

    $context = Get-AzContext
    $currentAccount = $context.Account.Id

    if ($currentAccount -notlike "*.adm*") {
        Write-Host ""
        Write-Host "Signed in as '$currentAccount' — this is not a .adm account. Aborting." -ForegroundColor Red
        Disconnect-AzAccount -WhatIf:$false | Out-Null
        exit 1
    }
    Write-Host "Elevated as: $currentAccount" -ForegroundColor Green
    $selectedSub = $context.Subscription
    if ($selectedSub) {
        Write-Host "Auto-selected subscription: $($selectedSub.Name) ($($selectedSub.Id))" -ForegroundColor DarkGray
        Write-Host "(Not used by this script — Microsoft Graph only.)" -ForegroundColor DarkGray
    }

    # ── Read current state via Graph ──

    Write-Host ""
    Write-Host "Reading current preAuthorizedApplications..." -ForegroundColor Yellow
    $resp = Invoke-AzRestMethod -Uri "https://graph.microsoft.com/v1.0/applications/$AppObjectId" -Method GET -WhatIf:$false
    if ($resp.StatusCode -ne 200) { throw "Graph GET failed (HTTP $($resp.StatusCode)): $($resp.Content)" }
    $app = $resp.Content | ConvertFrom-Json
    $currentList = @($app.api.preAuthorizedApplications)

    Write-Host "Current:"
    $currentList | ForEach-Object { "  $($_.appId) -> [$([string]::Join(',', @($_.delegatedPermissionIds)))]" }

    # ── Idempotency / sanity ──

    if ($currentList | Where-Object { $_.appId -eq $AzureCliAppId }) {
        Write-Host ""
        Write-Host "Azure CLI ($AzureCliAppId) is already pre-authorized. Nothing to do." -ForegroundColor Green
        return
    }
    if (-not ($currentList | Where-Object { $_.appId -eq $ApimAppId })) {
        throw "APIM ($ApimAppId) is NOT in the current pre-auth list. Refusing to patch — app reg is in an unexpected state."
    }

    # ── Build merged list ──

    $merged = @()
    foreach ($entry in $currentList) {
        $merged += @{
            appId                  = $entry.appId
            delegatedPermissionIds = @($entry.delegatedPermissionIds)
        }
    }
    $merged += @{
        appId                  = $AzureCliAppId
        delegatedPermissionIds = @($UserImpScopeId)
    }

    Write-Host ""
    Write-Host "Proposed:"
    $merged | ForEach-Object { "  $($_.appId) -> [$([string]::Join(',', $_.delegatedPermissionIds))]" }

    # ── Mutate (gated by ShouldProcess / -WhatIf) ──

    if (-not $PSCmdlet.ShouldProcess("$AppDisplayName ($AppId)", "Add Azure CLI to preAuthorizedApplications")) {
        Write-Host ""
        Write-Host "WhatIf — would PATCH preAuthorizedApplications. No changes made." -ForegroundColor Yellow
        return
    }

    $payload = @{ api = @{ preAuthorizedApplications = $merged } } | ConvertTo-Json -Depth 10 -Compress
    Write-Host ""
    Write-Host "PATCHing..." -ForegroundColor Yellow
    $resp = Invoke-AzRestMethod -Uri "https://graph.microsoft.com/v1.0/applications/$AppObjectId" -Method PATCH -Payload $payload
    if ($resp.StatusCode -lt 200 -or $resp.StatusCode -ge 300) {
        throw "Graph PATCH failed (HTTP $($resp.StatusCode)): $($resp.Content)"
    }

    # ── Verify ──

    Write-Host "Verifying..." -ForegroundColor Yellow
    $resp = Invoke-AzRestMethod -Uri "https://graph.microsoft.com/v1.0/applications/$AppObjectId" -Method GET -WhatIf:$false
    $verifyList = ($resp.Content | ConvertFrom-Json).api.preAuthorizedApplications
    $verifyList | ForEach-Object { "  $($_.appId) -> [$([string]::Join(',', @($_.delegatedPermissionIds)))]" }

    $apimOk = ($verifyList | Where-Object { $_.appId -eq $ApimAppId      -and ($_.delegatedPermissionIds -contains $UserImpScopeId) } | Measure-Object).Count -eq 1
    $cliOk  = ($verifyList | Where-Object { $_.appId -eq $AzureCliAppId  -and ($_.delegatedPermissionIds -contains $UserImpScopeId) } | Measure-Object).Count -eq 1

    if ($apimOk -and $cliOk) {
        Write-Host ""
        Write-Host "PRE-AUTH UPDATED." -ForegroundColor Green
        Write-Host "  APIM ($ApimAppId): user_impersonation pre-authorized." -ForegroundColor Green
        Write-Host "  Azure CLI ($AzureCliAppId): user_impersonation pre-authorized." -ForegroundColor Green
        Write-Host ""
        Write-Host "Your daily-driver az CLI is unchanged. Smoke test now:" -ForegroundColor Yellow
        Write-Host "  .\test-harness\Invoke-ApimSmokeTest.ps1" -ForegroundColor Cyan
    } else {
        Write-Host ""
        Write-Host "VERIFY FAILED. apimOk=$apimOk cliOk=$cliOk" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    Write-Host ""
    Write-Host "Disconnecting elevated session..." -ForegroundColor Gray
    Disconnect-AzAccount -ErrorAction SilentlyContinue -WhatIf:$false | Out-Null
    Write-Host "Done. Your az CLI / Claude Code sessions are unaffected." -ForegroundColor Gray
}
