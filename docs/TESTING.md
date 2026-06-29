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

The smoke test validates end-to-end APIM deployment including JWT authentication.

### Current Limitation

**Azure CLI cannot acquire tokens for the API scope directly.** The app registrations expose `user_impersonation` scope, but Azure CLI (`04b07795-8ddb-461a-bbee-02f9e1bf7b46`) is not pre-authorized.

### Workaround: Manual Token Acquisition

For now, test APIM without the smoke test script:

#### Option 1: Use Postman/REST Client

1. Configure OAuth 2.0 in Postman:
   - **Grant Type**: Authorization Code with PKCE
   - **Auth URL**: `https://login.microsoftonline.com/6232c2ec-fa42-4f27-92cd-787913fba489/oauth2/v2.0/authorize`
   - **Access Token URL**: `https://login.microsoftonline.com/6232c2ec-fa42-4f27-92cd-787913fba489/oauth2/v2.0/token`
   - **Client ID**: `6ce6ccb1-32db-40f8-97b5-bfbe700d052e` (dev) or `42971939-bc78-4c23-963e-c3e0f87e3bd1` (int, "SFDCRead INT MCP")
   - **Scope**: `api://6ce6ccb1-32db-40f8-97b5-bfbe700d052e/user_impersonation` (dev) or `api://42971939-bc78-4c23-963e-c3e0f87e3bd1/user_impersonation` (int)
   - **Redirect URI**: `https://oauth.pstmn.io/v1/callback`

2. Get Access Token (will prompt for login)

3. Send MCP request:
   ```
   POST https://amn-wus2-hub-apim-d02.azure-api.net/sfdcread/dev/mcp
   Headers:
     Authorization: Bearer <token>
     Content-Type: application/json
   Body:
     {"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}
   ```

#### Option 2: Direct cURL (No JWT - Will Fail Auth)

This demonstrates that JWT validation is working:

```bash
curl -X POST https://amn-wus2-hub-apim-d02.azure-api.net/sfdcread/dev/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

Expected: `401 Unauthorized` (JWT validation working correctly)

### Automated Smoke Test

The smoke test runs today against deployed INT. It needs a dedicated test client app (Azure CLI cannot acquire tokens for the API scope directly, as noted above). Provision the test client app via one of:

```powershell
cd test-harness
.\New-TestClientApp.ps1         # MS Graph PowerShell SDK path
# or
.\New-TestClientApp-AzCli.ps1   # az ad path
```

Then run:

```powershell
cd test-harness
.\Invoke-ApimSmokeTest.ps1
```

The smoke test:
- Acquires a JWT interactively against the test client app
- Calls through APIM to real Salesforce INT
- Exercises in-scope SObjects (PASS = data returned)
- Exercises boundary assertions (PASS = correctly blocked — e.g. `Account` returns `INVALID_TYPE`; FAIL = boundary breach)
- Distinguishes WARN (wiring healthy, data-access error needs review against documented scope) from FAIL (broken wiring or boundary breach)

See the script's header comment for full status semantics. Adding Dev/Prod targets is a TODO in the script itself.

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
