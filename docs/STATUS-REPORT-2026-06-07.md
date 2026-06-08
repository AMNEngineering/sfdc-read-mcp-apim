# SFDCRead MCP-APIM Contract: Status Report

**Date:** 2026-06-07 (updated 2026-06-08)  
**Project:** Salesforce Read-Only MCP Gateway (sobject-reads)  
**Scope:** Dev and Int environments (Prod is out of scope for this phase)

---

## Executive Summary

The SFDCRead project exposes Salesforce's read-only MCP server through Azure API Management, enabling Power BI and Copilot Studio agents to query Salesforce data securely via Entra ID authentication. Int environment is deployed with real Salesforce wiring (Build 1.0.56). All APIM infrastructure, policies, Key Vault, AFD routing, and identity are in place and verified.

**Single external blocker:** Salesforce Connected App rejects `client_credentials` grant — returns `"request not supported on this domain"`. Requires Salesforce admin to enable the flow and assign a Run As user.

---

## What's In Place

### Infrastructure & IaC

| Component | Status | Details |
|-----------|--------|---------|
| Terraform modules | Done | Modular design: named-values, mcp-api, backend-pool, mcp-policy, operation-policy |
| Dev deployment | Done | APIM `amn-wus2-hub-apim-d02`, inline mock responses (no backend needed) |
| Int deployment | Done | APIM `amn-wus2-hub-apim-i02`, real Salesforce sandbox backend (Build 1.0.56) |
| TF state backends | Done | Dev: `amncowus2tfstatesad01`, Int: `amncowus2tfstatesap01` |
| Int Key Vault | Done | `amn-wus2-sfdcread-kv-i01`, RG `amn-wus2-sfdcread-rg-i01`, RBAC authorization |
| AFD routing | Done | Both dev and int confirmed working (verified 2026-06-08) |

### CI/CD Pipeline

| Component | Status | Details |
|-----------|--------|---------|
| ADO pipeline | Done | `.ado/pipelines/deploy.yml`, triggered on push to `main` |
| Pipeline template | Done | Uses `amn-az-tf-common-pipelines` v2.1.8, Terraform 1.12.0 |
| Int plan/apply stages | Deployed | Custom implementation handles exit code 2; live since Build 1.0.56 |
| Dev plan/apply stages | Pending commit | Custom implementation (bypasses exit code 2 in common template) |
| Dev verify stage | Pending commit | Health check against `api.dev.amnhealthcare.io` |
| Int verify stage | Pending commit | Health check + MCP smoke test (graceful fallback if SPN not authorized) |
| Prod stages | N/A | Commented out, pending future CAB approval (out of scope) |
| Target pipeline flow | Pending commit | Build → dev_plan → dev_apply → dev_verify → int_plan → int_apply → int_verify |

### Identity & Security

| Component | Status | Details |
|-----------|--------|---------|
| Entra app registration (Dev) | Done | `SFDC Read MCP Reader`, App ID: `6ce6ccb1-32db-40f8-97b5-bfbe700d052e` |
| Entra app registration (Int) | Done | App ID: `976d1c5b-bc4b-4cdf-9fd3-6fd7567a1a03` |
| AD groups | Done | `AZ_AMN_AAD_SfdcReadMcp_{ENV}_User` created, synced via AD Connect |
| MCP.Read app role | Done | Assigned to AD groups per environment |
| JWT validation (APIM policy) | Done | Validates tenant, audience, client app IDs; extracts user OID for correlation |
| Azure CLI client ID in policy | Live on int APIM | Pushed directly via REST API for testing; pending commit for Terraform to manage it permanently |

### Key Vault & Credentials

| Component | Status | Details |
|-----------|--------|---------|
| KV secret references in APIM | Done | Named values `SFDC-MCP-Client-ID` and `SFDC-MCP-Client-Secret` reference KV; status: **Success** |
| Salesforce sandbox credentials | Done | Client ID and secret loaded in KV, APIM MI has Key Vault Secrets User role |
| APIM named values (int) | Done | `SFDC-Read-MCP-App-ID`, `SFDC-MCP-Client-ID` (KV), `SFDC-MCP-Client-Secret` (KV), `SFDC-MCP-Token-URL`, `SFDC-MCP-Path` — all resolving by **display name** |
| Dev credentials | Done | Inline mock values (no KV needed for dev) |

### APIM Policies

| Policy | Status | Details |
|--------|--------|---------|
| Dev mock policy | Done | Full MCP protocol mock inline: initialize, tools/list, tools/call (6 tools), notifications, error handling |
| Int/Prod real policy | Done | Entra JWT validation → Salesforce OAuth token exchange (`client_credentials`) → dynamic backend routing to SF instance URL |
| Health check policy | Done | `GET /health` returns service status without JWT (required for AFD probes and pipeline verification) |

### Test Harness

| Component | Status | Details |
|-----------|--------|---------|
| APIM smoke test script | Done | `Invoke-ApimSmokeTest.ps1` — 7 tests including JWT negative test, correlation ID validation |
| Local mock server | Done | `MockSalesforceMcpServer.ps1` — full MCP protocol on localhost:8080 |
| Mock server test script | Done | `Test-MockServer.ps1` — validates mock responses locally |
| Test client app creation scripts | Done | Both Graph SDK and Azure CLI variants |
| Test client config | Partial | `test-client-config.json` exists but app IDs are `null` (not yet populated) |

---

## Salesforce Connection Status

### Blocker: `client_credentials` Grant Rejected

**Tested 2026-06-08.** Direct OAuth call from both APIM and local machine:

```
POST https://test.salesforce.com/services/oauth2/token
grant_type=client_credentials&client_id=<KV value>&client_secret=<KV value>

Response: 400
{"error":"invalid_grant","error_description":"request not supported on this domain"}
```

Same result against `login.salesforce.com`.

**Root cause:** The Salesforce Connected App is not configured for the `client_credentials` flow. Required Salesforce admin actions:

1. **Enable Client Credentials Flow** on the Connected App (Setup → App Manager → Edit)
2. **Assign a "Run As" user** for the client_credentials flow (Setup → Manage Connected Apps → Edit Policies)
3. **Verify the token endpoint** — may need org-specific sandbox domain instead of `test.salesforce.com` (e.g., `https://amnhealthcare--<sandbox>.sandbox.my.salesforce.com/services/oauth2/token`)

**APIM side is confirmed working:** JWT validation passes, OAuth exchange executes, policy correctly handles the token response. The 500 is caused by Salesforce returning a 400 to the token exchange.

---

## Testing Checklist

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | APIM policy deploys without error | Pass | Build 1.0.56 succeeded |
| 2 | Named values resolve from Key Vault | Pass | Verified via REST API — both secrets show `status: Success` |
| 3 | AFD routing to APIM | Pass | Health endpoints return 200 on both dev and int |
| 4 | JWT validation accepts Azure CLI token | Pass | 401 → 200 after adding Azure CLI client ID to policy |
| 5 | Salesforce OAuth token exchange | **Fail** | `client_credentials` grant rejected by Salesforce — Connected App config needed |
| 6 | MCP initialize through APIM to Salesforce | Blocked | Depends on #5 |
| 7 | MCP tools/list returns Salesforce tools | Blocked | Depends on #5 |
| 8 | MCP tools/call (soqlQuery) returns real data | Blocked | Depends on #5 |
| 9 | Copilot Studio → APIM → Salesforce e2e | TODO | |
| 10 | Power BI → APIM → Salesforce e2e | TODO | |

---

## Environment Summary

| | Dev | Int | Prod |
|---|-----|-----|------|
| Latest build | 1.0.56 | 1.0.56 | Out of scope |
| APIM instance | amn-wus2-hub-apim-d02 | amn-wus2-hub-apim-i02 | amn-wus2-hub-apim-p02 |
| Backend | Inline APIM mock | Salesforce sandbox | -- |
| App registration | Done | Done | -- |
| AD groups | Done | Done | -- |
| Key Vault | N/A (mock creds) | Done (secrets loaded, resolving) | -- |
| AFD routing | Done | Done | -- |
| SF OAuth working | N/A (mocked) | **Blocked — SF Connected App config** | -- |
| Pipeline verify stage | Pending commit | Pending commit | -- |

---

## Remaining Items

### External Dependency

| Item | Owner | Action |
|------|-------|--------|
| Salesforce Connected App: enable `client_credentials` grant + assign Run As user | Salesforce Admin | Required before int e2e testing works |
| Salesforce token URL: confirm correct sandbox domain | Salesforce Admin | May need org-specific URL instead of `test.salesforce.com` |

### Our Items

| Item | Priority |
|------|----------|
| Commit and push pipeline changes (dev stages, verify stages, Azure CLI client ID in policy) | High |
| Re-test SF OAuth after Connected App is configured | High |
| Run full smoke test against int (`Invoke-ApimSmokeTest.ps1 -Environment int`) | High |
| Test Copilot Studio → APIM → Salesforce end-to-end | High |
| Populate `test-client-config.json` with test app registrations | Medium |
| Add rate limiting to APIM policy | Medium |
| Add mutation rejection (block non-read MCP methods) to APIM policy | Medium |

---

## Next Steps

1. **Commit:** Push local changes — dev stages, verify stages, Azure CLI client ID in both policies
2. **Salesforce Admin:** Enable `client_credentials` grant on Connected App, assign Run As user, confirm token URL
3. **Re-test:** Once SF Connected App is configured, re-run `Invoke-ApimSmokeTest.ps1 -Environment int`
4. **Copilot Studio:** Test Copilot Studio agent calling APIM → Salesforce end-to-end

---
---

## Appendix A: Key Lessons Learned

| Issue | Root Cause | Resolution |
|-------|-----------|------------|
| Named value `{{...}}` resolution failures (Build 1.0.55) | APIM resolves `{{...}}` by **display name**, not Terraform resource name | Changed all references to use display names: `SFDC-MCP-Client-ID` not `nv-sfdc-read-mcp-client-id` |
| XML entity errors (Build 1.0.54) | Literal `&` in `<set-body>` must be `&amp;` (XML parser decodes before C# eval) | Used `&amp;` in form body |
| JObject parse errors (Build 1.0.53) | `@()` C# expressions need raw `<JObject>`, not XML-escaped `&lt;JObject&gt;` | Used raw generics inside expressions |
| Dev pipeline exit code 2 | Common template treats TF plan exit code 2 (changes detected) as failure | Custom plan/apply stages with explicit exit code handling |
| 401 on smoke test | Azure CLI's app ID not in policy `client-application-ids` | Added `04b07795-8ddb-461a-bbee-02f9e1bf7b46` as allowed client |

---

## Appendix B: AMN Ops Plugin Skill — Improvements Noted

During SFDCRead development, several improvements were identified and some have already been applied to the `amn-ops-skills` plugin in the marketplace repo. A detailed list exists in `docs/AMN-OPS-PLUGIN-IMPROVEMENTS.md`.

### Improvements Already Made

| Improvement | Skill | Date |
|-------------|-------|------|
| AMN IPS infrastructure awareness section (AFD 3-tier pattern) | `mcp-apim-onboarding` | 2026-06-06 |
| Mandatory `GET /health` endpoint guardrail for all APIM contracts | `mcp-apim-onboarding` | 2026-06-06 |
| AFD routing pattern documented with sfdc-read as reference implementation | `mcp-apim-onboarding` | 2026-06-05 |
| APIM shared infrastructure clarification (company-wide, 700+ APIs) | `new-relic-observability` | Recent |
| Corrected New Relic account ID | `new-relic-observability` | Recent |
| APIM instance name placeholders fixed (PR #9) | `new-relic-observability` | 2026-06-07 |

### Improvements Still Needed

**mcp-apim-onboarding (v0.2.0):**

1. **Missing backing scripts** — `Deploy-McpApim.ps1` and `Deploy-ApimForFoundry.ps1` are referenced but do not exist
2. **Script path references are wrong** — examples show wrong path vs actual `setup/foundry/scripts/apim/shared/Deploy-NativeMcpApim.ps1`
3. **API path prefix inconsistency** — three different conventions in the same skill
4. **Deploy-NativeMcpApim.ps1 is incomplete** — missing models mock and context_management removal
5. **Capability 3 has no auth enforcement** — client-to-APIM auth listed as anonymous
6. **TBD stubs unresolved** — multiple placeholder references remain
7. **Version should bump** — substantial updates since 0.2.0

**new-relic-observability (v0.1.0):**

1. **No New Relic dashboard link** — checklist requires adding tiles but provides no URL
2. **NRQL examples are project-specific** — queries hardcode `codeveloperaifp01`
3. **Int environment AFD details are TBD**
4. **Dormant since creation** — only 3 commits total
