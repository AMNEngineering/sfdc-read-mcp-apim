# Testing Guide

## Overview

This document describes how to test the SFDC Read MCP APIM deployment across environments.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- PowerShell 7+
- Access to AMN Healthcare Entra tenant
- Network access to APIM endpoints

## Mock Server (Dev Only)

The mock server emulates Salesforce's MCP protocol for local development.

### Start Mock Server

```powershell
cd test-harness/mocks
.\MockSalesforceMcpServer.ps1 -VerboseLogging
```

The server listens on `http://localhost:8080` and implements 6 MCP tools:
- `getSobjectSchema` - Returns object metadata
- `soqlQuery` - Executes SOQL queries (returns mock data)
- `soslSearch` - Full-text search
- `getUserIdentity` - Current user info
- `getRecentItems` - Recently accessed records
- `getRelatedRecords` - Child record traversal

> **Mock-vs-real divergence (known):** the mock predates Salesforce's hosted MCP coming online and uses different tool names than the real SF MCP server. The real server exposes `getObjectSchema`, `soqlQuery`, `find`, `getUserInfo`, `listRecentSobjectRecords`, `getRelatedRecords` — see [Salesforce MCP Integration Reference](SALESFORCE-MCP-INTEGRATION-REFERENCE.md). Mock alignment is a separate follow-up; the smoke test (`Invoke-ApimSmokeTest.ps1`) targets INT against real SF, so the divergence does not affect smoke testing today.

### Test Mock Server Directly

```powershell
cd test-harness
.\Test-MockServer.ps1
```

Expected output:
```
✓ initialize successful
✓ tools/list successful  
✓ getSobjectSchema successful
✓ soqlQuery successful
✓ getUserIdentity successful
All tests passed!
```

## APIM Smoke Test

The smoke test (`test-harness/Invoke-ApimSmokeTest.ps1`) validates the deployed INT gateway end-to-end. It supports two token modes; together they exercise the two audience formats the dual-audience policy accepts.

### Automated (CI)

`int_verify` runs the smoke in `-TokenMode AppOnly` (see `.ado/pipelines/deploy.yml`):

- Bearer acquired via `client_credentials` against the v2 token endpoint
- Scope: `<app-id>/.default` (bare-GUID, no `api://` prefix)
- Result: app-only token with `aud=<bare-GUID>`, `roles=[MCP.Read]`
- Validates: the policy still accepts bare-GUID audience — the format Power Automate's self-OAuth produces, per PR #19

If `int_verify` fails the smoke step, the most common cause is the ADO Upper SPN missing the `MCP.Read` app-role assignment on the SFDCRead app reg's SP. Fix is the same Graph PATCH pattern as `docs/onboarding/IDENTITY-BOOTSTRAP-INT.md` Step 7.3, with the SPN's object ID as the principal.

### Manual delegated-token test (run as your daily driver)

CI cannot exercise the delegated-token (`scp`-bearing) path that Power Automate and Copilot Studio user-delegated connections actually carry — see [Known automation gap](#known-automation-gap) below for why. The workaround is to run the smoke locally under your own daily-driver `az login`:

```powershell
az login --tenant 6232c2ec-fa42-4f27-92cd-787913fba489
cd test-harness
./Invoke-ApimSmokeTest.ps1 -AssertDelegated
```

`-AssertDelegated` fails fast if the acquired token is app-only (no `scp` claim) and prints the identity-relevant claims so you have paste-into-PR evidence of which user, audience, scope, and role membership were exercised.

**When to run it:**

- Before merging any PR that touches `policies/apim-policy-sfdc-read-mcp.xml` JWT validation, audience config, or claim parsing
- After any change to the per-environment app reg's identifier URIs or app-role assignments
- After any change to `AZ_AMN_AAD_SfdcReadMcp_Int_User` group membership rules

**Evidence to capture in the PR comment:**

- The "Token claims" block printed by `-AssertDelegated`
- The smoke summary line (`Results: X pass / Y warn / Z fail`)
- The correlation ID of any failed test (the script echoes `x-correlation-id` per request)

The smoke test:

- Acquires a JWT
- Calls through APIM to real Salesforce INT
- Exercises in-scope SObjects (PASS = data returned)
- Exercises boundary assertions (PASS = correctly blocked — e.g. `Account` returns `INVALID_TYPE`; FAIL = boundary breach)
- Distinguishes WARN (wiring healthy, data-access error needs review against documented scope) from FAIL (broken wiring or boundary breach)

See the script's header comment for full status semantics.

### Known automation gap

The delegated-token (`scp`) path is **deliberately not automated**. The available identity options don't fit:

| Option | Fit | Why not |
|---|---|---|
| Managed identity | No | Issues app-only tokens only (no `scp` claim); cannot impersonate a user |
| Dedicated licensed mailbox SA | No | Recurring per-seat cost + user-lifecycle (HR/CA/MFA) overhead just to host a refresh token |
| ROPC (password grant) | No | Microsoft-deprecated; AMN tenant CA policy blocks it; requires storing a real user password |
| Headless browser auth-code | No | Brittle to Entra UI changes; AMN CA policies (compliant-device, location) reject headless agents; MFA still needs solving |
| Daily-driver refresh token in KV | Shelved | Would impersonate a real human in Entra sign-in logs; audit-trail confusion outweighs CI value at current scope |

Decision: validate the delegated path with the documented manual run above before policy- or identity-touching PRs merge, rather than via CI. Revisit if the rate of delegated-token regressions becomes high enough to justify the daily-driver-refresh-token mechanism (and accept the audit-log consequence).

## Integration Testing (Int Environment)

Int environment connects to **Salesforce Sandbox** instead of the mock server.

### Prerequisites

- Salesforce Sandbox credentials configured in APIM named values
- Valid Salesforce OAuth client ID/secret in Azure Key Vault
- Salesforce External Client App configured with MCP API scope

### Salesforce Setup Required

Before testing Int, ensure:

1. **Salesforce Sandbox has MCP Servers enabled**
   - Feature flag: `enable_mcp_servers`
   - Type: `sobject-reads` (read-only)

2. **External Client App created in Salesforce**
   - OAuth scope: `mcp_api`  
   - Callback URL: (not needed for client credentials flow)
   - Client ID/Secret stored in Azure Key Vault

3. **APIM Named Values Updated**
   - `nv-sfdc-read-mcp-client-id` → Salesforce Client ID
   - `nv-sfdc-read-mcp-client-secret` → Salesforce Client Secret  
   - `nv-sfdc-read-mcp-token-url` → `https://amnhealthcare--qa.sandbox.my.salesforce.com/services/oauth2/token` (INT — verified against `infrastructure/environments/int.tfvars`)

### Test Against Int

Same as dev testing, but use:
- **Endpoint**: `https://api.int.amnhealthcare.io/sfdcread/int/mcp` (Front Door route; APIM-direct still works at `https://amn-wus2-hub-apim-i02.azure-api.net/sfdcread/int/mcp`)
- **App ID**: `42971939-bc78-4c23-963e-c3e0f87e3bd1` ("SFDCRead INT MCP")
- **Scope**: `api://42971939-bc78-4c23-963e-c3e0f87e3bd1/user_impersonation`

> **Historical note:** The earlier "SFDC Read MCP Reader Int" app reg (`976d1c5b-bc4b-4cdf-9fd3-6fd7567a1a03`) was retired on the consolidation that collapsed APIM to a single audience. Old references in branches, scripts, or saved Postman collections should be updated.

Int will return **real Salesforce data** from the sandbox org.

## Validation Checklist

### Dev Environment
- [ ] Mock server starts and responds to MCP requests
- [ ] APIM rejects requests without Authorization header (401)
- [ ] APIM rejects requests with invalid JWT (401)
- [ ] APIM accepts valid JWT and routes to mock backend
- [ ] Correlation ID is echoed in response headers
- [ ] User OID extracted to `x-apim-user-id` header

### Int Environment  
- [ ] APIM acquires Salesforce OAuth token successfully
- [ ] APIM routes to Salesforce sandbox
- [ ] Real Salesforce data returned in responses
- [ ] Read-only enforcement (mutations rejected)
- [ ] Salesforce user permissions respected

## Troubleshooting

### "401 Unauthorized" from APIM

**Cause**: Missing or invalid JWT token

**Fix**: Ensure Authorization header has valid Bearer token for the correct app ID

### "ValidationError: One or more fields contain incorrect values"

**Cause**: APIM policy XML has syntax errors or references non-existent resources

**Fix**: Check backend-id references actual backend name (not pool)

### "The specified container does not exist"

**Cause**: Terraform state container missing in storage account

**Fix**: Create container manually or let pipeline create it

### Mock Server Not Responding

**Cause**: Port 8080 already in use or firewall blocking

**Fix**: 
```powershell
# Check if port is in use
Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue

# Kill process using port
Stop-Process -Id (Get-NetTCPConnection -LocalPort 8080).OwningProcess -Force

# Restart mock server
.\MockSalesforceMcpServer.ps1
```

## Next Steps

1. **Add Azure CLI as pre-authorized application** in app registrations to enable automated smoke tests
2. **Create dedicated test client app** with public client flow (no secret) for CI/CD pipelines
3. **Integrate smoke test into ADO pipeline** as post-deployment validation
4. **Document Power BI and Copilot Studio connection** setup once testing completes
