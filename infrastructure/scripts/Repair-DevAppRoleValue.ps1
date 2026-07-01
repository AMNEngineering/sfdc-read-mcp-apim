#Requires -Version 7.0
#Requires -Modules Az.Accounts

<#
.SYNOPSIS
  Fix the SFDC Read MCP Reader Dev app-role `value` from "User" to "MCP.Read".

.DESCRIPTION
  The dev app reg (`6ce6ccb1-...`) currently exposes a single app role whose
  displayName is "MCP.Read" but whose `value` is `User` — a historical
  divergence from int, which uses `value = "MCP.Read"`. The dev policy
  (policies/apim-policy-sfdc-read-mcp-dev-mock.xml) checks
  `roles.Contains("MCP.Read")`, so today anyone in the dev group receives a
  token with `roles=[User]` and is 403'd. This makes the dev environment
  effectively untestable end-to-end.

  This script PATCHes the appRoles array on the dev app reg with the same
  role `id` (preserving the existing group→role assignment) and the corrected
  `value = "MCP.Read"`. One-shot. Idempotent — re-running when the value is
  already correct is a no-op.

  Follows the ADM elevation pattern documented in
  amn-ops-ai-plugin-marketplace/setup/scripts/ADM-ELEVATION-PATTERN.md.
  Uses Az PowerShell SDK (Connect-AzAccount) in an isolated context so your
  daily-driver `az` session is not touched.

.PARAMETER WhatIf
  Standard PowerShell WhatIf. Reports what would change, does not patch.

.EXAMPLE
  .\infrastructure\scripts\Repair-DevAppRoleValue.ps1 -WhatIf
  .\infrastructure\scripts\Repair-DevAppRoleValue.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$AppObjectId    = "c4b63ff2-0e9e-4078-a514-da7351dd874c",
    [string]$AppId          = "6ce6ccb1-32db-40f8-97b5-bfbe700d052e",
    [string]$AppDisplayName = "SFDC Read MCP Reader Dev",
    [string]$ExpectedValue  = "MCP.Read",
    [string]$TenantId       = "6232c2ec-fa42-4f27-92cd-787913fba489"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ADM elevation required" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will PATCH Microsoft Graph to fix the appRole `value`" -ForegroundColor White
Write-Host "on '$AppDisplayName' from its current setting to '$ExpectedValue'." -ForegroundColor White
Write-Host ""
Write-Host "The role `id` is preserved, so the existing dev-group assignment" -ForegroundColor White
Write-Host "on the SP survives unchanged." -ForegroundColor White
Write-Host ""
Write-Host "Your Azure CLI session (daily-driver) is NOT affected — Connect-AzAccount" -ForegroundColor Green
Write-Host "uses an isolated PowerShell context. Microsoft Graph only — no Azure" -ForegroundColor Green
Write-Host "subscription operations." -ForegroundColor Green
Write-Host ""

$go = Read-Host "Ready to elevate? (Y/N)"
if ($go -notmatch '^[Yy]') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

try {
    Write-Host ""
    Write-Host "Connecting to Azure PowerShell (isolated context)..." -ForegroundColor Yellow
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

    # ── Read current state via Graph ──

    Write-Host ""
    Write-Host "Reading current appRoles..." -ForegroundColor Yellow
    $resp = Invoke-AzRestMethod -Uri "https://graph.microsoft.com/v1.0/applications/$AppObjectId" -Method GET -WhatIf:$false
    if ($resp.StatusCode -ne 200) { throw "Graph GET failed (HTTP $($resp.StatusCode)): $($resp.Content)" }
    $app = $resp.Content | ConvertFrom-Json
    $currentRoles = @($app.appRoles)

    Write-Host "Current:"
    $currentRoles | ForEach-Object { "  id=$($_.id)  displayName='$($_.displayName)'  value='$($_.value)'  isEnabled=$($_.isEnabled)" }

    # ── Locate the role to repair ──

    $target = $currentRoles | Where-Object { $_.displayName -eq $ExpectedValue -or $_.value -eq $ExpectedValue } | Select-Object -First 1
    if (-not $target) {
        throw "Could not find an appRole with displayName or value '$ExpectedValue' on '$AppDisplayName'. Refusing to patch — app reg is in an unexpected state."
    }

    if ($target.value -eq $ExpectedValue) {
        Write-Host ""
        Write-Host "Role value is already '$ExpectedValue' (id=$($target.id)). Nothing to do." -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "Target role:" -ForegroundColor Yellow
    Write-Host "  id            : $($target.id)"
    Write-Host "  displayName   : $($target.displayName)"
    Write-Host "  current value : '$($target.value)'"
    Write-Host "  new value     : '$ExpectedValue'"

    # ── Build merged appRoles (preserve id + all other roles verbatim) ──

    $merged = @()
    foreach ($role in $currentRoles) {
        if ($role.id -eq $target.id) {
            $merged += @{
                id                 = $role.id
                allowedMemberTypes = @($role.allowedMemberTypes)
                description        = $role.description
                displayName        = $role.displayName
                isEnabled          = [bool]$role.isEnabled
                value              = $ExpectedValue
            }
        } else {
            $merged += @{
                id                 = $role.id
                allowedMemberTypes = @($role.allowedMemberTypes)
                description        = $role.description
                displayName        = $role.displayName
                isEnabled          = [bool]$role.isEnabled
                value              = $role.value
            }
        }
    }

    # ── Mutate (gated by ShouldProcess / -WhatIf) ──

    if (-not $PSCmdlet.ShouldProcess("$AppDisplayName ($AppId)", "Set appRole value to '$ExpectedValue' on role $($target.id)")) {
        Write-Host ""
        Write-Host "WhatIf — would PATCH appRoles. No changes made." -ForegroundColor Yellow
        return
    }

    $payload = @{ appRoles = $merged } | ConvertTo-Json -Depth 10 -Compress
    Write-Host ""
    Write-Host "PATCHing..." -ForegroundColor Yellow
    $resp = Invoke-AzRestMethod -Uri "https://graph.microsoft.com/v1.0/applications/$AppObjectId" -Method PATCH -Payload $payload
    if ($resp.StatusCode -lt 200 -or $resp.StatusCode -ge 300) {
        throw "Graph PATCH failed (HTTP $($resp.StatusCode)): $($resp.Content)"
    }

    # ── Verify ──

    Write-Host "Verifying..." -ForegroundColor Yellow
    $resp = Invoke-AzRestMethod -Uri "https://graph.microsoft.com/v1.0/applications/$AppObjectId" -Method GET -WhatIf:$false
    $verifyRoles = ($resp.Content | ConvertFrom-Json).appRoles
    $verifyRoles | ForEach-Object { "  id=$($_.id)  value='$($_.value)'  isEnabled=$($_.isEnabled)" }

    $ok = ($verifyRoles | Where-Object { $_.id -eq $target.id -and $_.value -eq $ExpectedValue } | Measure-Object).Count -eq 1

    if ($ok) {
        Write-Host ""
        Write-Host "ROLE VALUE UPDATED." -ForegroundColor Green
        Write-Host "  Role id=$($target.id) now has value='$ExpectedValue'." -ForegroundColor Green
        Write-Host "  The existing dev-group→role assignment on the SP is unchanged (same role id)." -ForegroundColor Green
        Write-Host ""
        Write-Host "Users in AZ_AMN_AAD_SfdcReadMcp_Dev_User will now receive tokens with" -ForegroundColor Yellow
        Write-Host "roles=[$ExpectedValue] on next sign-in / token refresh. Smoke test:" -ForegroundColor Yellow
        Write-Host "  .\test-harness\Invoke-ApimSmokeTest.ps1 -Environment dev -AssertDelegated" -ForegroundColor Cyan
    } else {
        Write-Host ""
        Write-Host "VERIFY FAILED. Expected role id=$($target.id) with value='$ExpectedValue'." -ForegroundColor Red
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
