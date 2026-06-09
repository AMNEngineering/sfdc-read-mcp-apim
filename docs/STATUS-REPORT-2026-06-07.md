# SFDCRead MCP-APIM Contract: Status Report

**Date:** 2026-06-09
**Project:** Salesforce Read-Only MCP Gateway (sobject-reads)
**Scope:** Dev and Int environments (Prod is out of scope for this phase)

---

## Executive Summary

The SFDCRead project exposes Salesforce's read-only MCP server through Azure API Management, enabling Power BI and Copilot Studio agents to query Salesforce data securely via Entra ID authentication.

End-to-end wiring through APIM is healthy in int: Entra JWT → APIM policy → Salesforce `client_credentials` token exchange → MCP at `https://api.salesforce.com/platform/mcp/v1/sandbox/platform/sobject-reads`. Smoke test reports **5 pass / 2 warn / 0 fail**; the two warnings are scope decisions on the Salesforce side, not wiring bugs.

**Next gate:** confirm with the data owner which SObjects (and which fields) should be exposed, then have the SF admin add them to `MCP_ReadOnly_Access` on the Run-As user before Copilot Studio testing.

---

## What's In Place

### Infrastructure & IaC

| Component | Details |
|-----------|---------|
| Terraform modules | Modular: named-values, mcp-api, backend-pool, mcp-policy, operation-policy |
| Dev deployment | APIM `amn-wus2-hub-apim-d02`, inline mock responses |
| Int deployment | APIM `amn-wus2-hub-apim-i02`, real Salesforce sandbox backend |
| TF state backends | Dev: `amncowus2tfstatesad01`, Int: `amncowus2tfstatesap01` |
| Int Key Vault | `amn-wus2-sfdcread-kv-i01`, RG `amn-wus2-sfdcread-rg-i01`, RBAC authorization |
| AFD routing | Working on dev and int |

### CI/CD Pipeline

| Component | Details |
|-----------|---------|
| ADO pipeline | `.ado/pipelines/deploy.yml`, triggered on push to `main` |
| Pipeline template | `amn-az-tf-common-pipelines` v2.1.8, Terraform 1.12.0 |
| Pipeline flow | Build → dev_plan → dev_apply (gate) → dev_verify → int_plan → int_apply (gate) → int_verify |
| Apply gates | Manual approval on `dev_apply` and `int_apply` via ADO environments |
| Verify stages | Management-API health check + MCP smoke test |
| Prod stages | Commented out, pending future CAB approval (out of scope) |

### Identity & Security

| Component | Details |
|-----------|---------|
| Entra app registration (Dev) | `SFDC Read MCP Reader`, App ID: `6ce6ccb1-32db-40f8-97b5-bfbe700d052e` |
| Entra app registration (Int) | App ID: `976d1c5b-bc4b-4cdf-9fd3-6fd7567a1a03` |
| AD groups | `AZ_AMN_AAD_SfdcReadMcp_{ENV}_User`, synced via AD Connect |
| MCP.Read app role | Assigned to AD groups per environment |
| JWT validation | APIM policy validates tenant, audience, client app IDs; extracts user OID for correlation |
| Azure CLI client ID in policy | Allowed for smoke test / dev access (Terraform-managed) |

### Key Vault & Credentials

| Component | Details |
|-----------|---------|
| KV secret references in APIM | Named values `SFDC-MCP-Client-ID` and `SFDC-MCP-Client-Secret` reference KV |
| Salesforce sandbox credentials | Client ID and secret loaded in KV; APIM MI has Key Vault Secrets User role |
| APIM named values (int) | `SFDC-Read-MCP-App-ID`, `SFDC-MCP-Client-ID`, `SFDC-MCP-Client-Secret`, `SFDC-MCP-Token-URL`, `SFDC-MCP-Base-URL`, `SFDC-MCP-Path` |
| Dev credentials | Inline mock values (no KV needed for dev) |

### APIM Policies

| Policy | Details |
|--------|---------|
| Dev mock policy | Full MCP protocol mock inline: initialize, tools/list, tools/call (6 tools), notifications, error handling |
| Int real policy | Entra JWT validation → Salesforce OAuth (`client_credentials`) → backend routing to `api.salesforce.com` |
| Health check policy | `GET /health` returns service status without JWT (required for AFD probes and pipeline verification) |

### Test Harness

| Component | Details |
|-----------|---------|
| APIM smoke test script | `Invoke-ApimSmokeTest.ps1` — 7 tests, MCP streamable-HTTP (HttpClient + SSE), JWT negative test, correlation ID validation |
| Local mock server | `MockSalesforceMcpServer.ps1` — full MCP protocol on localhost:8080 |
| Mock server test script | `Test-MockServer.ps1` — validates mock responses locally |
| Test client app creation scripts | Graph SDK and Azure CLI variants |
| Test client config | `test-client-config.json` exists but app IDs not yet populated |

---

## Current Smoke Test Result (int)

| # | Test | Status | Notes |
|---|------|--------|-------|
| 1 | Initialize | Pass | sobject-reads v1.0.0, session established |
| 2 | tools/list | Pass | 6 tools returned via SSE |
| 3 | getObjectSchema (index) | Pass | |
| 4 | getObjectSchema (Account) | **Warn** | `INTERNAL_ERROR` — Account not in `MCP_ReadOnly_Access` (scope decision) |
| 5 | soqlQuery (`SELECT Id, Name FROM Account`) | **Warn** | `INVALID_TYPE` — Account not in `MCP_ReadOnly_Access` (scope decision) |
| 6 | getUserInfo | Pass | Returns Run-As identity |
| 7 | JWT validation (negative) | Pass | 401 on invalid token |

The two WARNs share a single root cause: Account isn't exposed via the Run-As permission set. Per design intent (see README "Design Intent — Limited Exposure is the Product"), this is a data-owner decision, not a bug. Reproducible evidence for the Salesforce team: [REPRO-Account-Scope-2026-06-09.md](REPRO-Account-Scope-2026-06-09.md) (control call on `User` returns data, failing call on `Account` returns `INVALID_TYPE`, same token + session).

---

## Environment Summary

| | Dev | Int | Prod |
|---|-----|-----|------|
| APIM instance | amn-wus2-hub-apim-d02 | amn-wus2-hub-apim-i02 | amn-wus2-hub-apim-p02 |
| Backend | Inline APIM mock | Salesforce sandbox (`api.salesforce.com` MCP) | -- |
| App registration | Done | Done | -- |
| AD groups | Done | Done | -- |
| Key Vault | N/A (mock creds) | Done | -- |
| AFD routing | Done | Done | -- |
| SF OAuth | N/A (mocked) | Working (`client_credentials`, scope `sfap_api mcp_api api`) | -- |
| SF MCP endpoint | N/A (mocked) | Working (`api.salesforce.com`) | -- |
| Pipeline verify stage | Done | Done | -- |

---

## Open Items

### External (Salesforce / data owner)

| Item | Owner |
|------|-------|
| Confirm scope: which SObjects and which fields are intended for this gateway's consumers (default is exclude — see README "Design Intent") | Data owner / GRC |
| Add the confirmed SObjects to `MCP_ReadOnly_Access` on the Run-As user | Salesforce Admin |

### Our Items

| Item | Priority |
|------|----------|
| Populate `test-client-config.json` with test app registrations | Medium |
| Add rate limiting to APIM policy | Medium |
| Add mutation rejection (block non-read MCP methods) to APIM policy | Medium |
| Extend smoke test to probe each approved in-scope SObject (after scope confirmed) | Medium |
| Test Copilot Studio → APIM → Salesforce end-to-end (blocked on scope + perm-set update) | High |

---

## Next Steps

1. **Data owner / GRC:** Confirm the list of in-scope SObjects and any field-level masking.
2. **Salesforce Admin:** Add the confirmed SObjects to `MCP_ReadOnly_Access` on the Run-As user.
3. **Re-test:** `Invoke-ApimSmokeTest.ps1 -Environment int` to confirm WARNs clear for approved SObjects.
4. **Copilot Studio:** Test agent → APIM → Salesforce end-to-end.
