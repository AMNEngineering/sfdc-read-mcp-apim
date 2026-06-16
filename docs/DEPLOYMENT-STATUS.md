# Deployment Status

## Latest Deployment: Build 1.0.56

**Date**: 2026-06-07 (state last reconciled 2026-06-09)
**Status**: Int APIM policy reverted to `client_credentials`; revert pending commit and pipeline redeploy.
**Pipeline**: Build → dev_plan → dev_apply → dev_verify → int_plan → int_apply → int_verify

---

## Dev Environment

- **APIM**: amn-wus2-hub-apim-d02
- **API Path**: sfdcread/dev
- **AFD URL**: https://api.dev.amnhealthcare.io/sfdcread/dev
- **App ID**: 6ce6ccb1-32db-40f8-97b5-bfbe700d052e
- **Backend**: Inline mock responses (no backend server needed)
- **JWT**: Validated, Azure CLI pre-authorized
- **Status**: Deployed, AFD routing confirmed working

## Int Environment

- **APIM**: amn-wus2-hub-apim-i02
- **API Path**: sfdcread/int
- **AFD URL**: https://api.int.amnhealthcare.io/sfdcread/int
- **App ID**: 42971939-bc78-4c23-963e-c3e0f87e3bd1 ("SFDCRead INT MCP")
  - Earlier "SFDC Read MCP Reader Int" reg (`976d1c5b-bc4b-4cdf-9fd3-6fd7567a1a03`) was retired on the single-audience consolidation; APIM no longer accepts that audience.
- **Backend**: Salesforce MCP at `https://api.salesforce.com` (NOT the org's `instance_url`)
- **Key Vault**: amn-wus2-sfdcread-kv-i01 (secrets resolving, status: Success)
- **JWT**: Validated, Azure CLI pre-authorized
- **SF OAuth (client_credentials)**: Working — token returned with scopes `sfap_api mcp_api api` and `api_instance_url=https://api.salesforce.com`
- **SF MCP**: Working — initialize, tools/list, getUserInfo all return 200; soqlQuery reaches SF (currently blocked on Run-As user perm set, not wiring)
- **Status**: APIM still running prior `client_credentials` policy that routes to `instance_url` (broken vs MCP at `api.salesforce.com`). Revert to corrected `client_credentials` policy (routes to `api.salesforce.com`) is staged locally; pipeline redeploy pending commit.

---

## Remaining Items

### External (Salesforce admin)

| Item | Status |
|------|--------|
| Enable `client_credentials` grant + Run As user | **Done** (2026-06-08) |
| Activate MCP Server (`platform/sobject-reads`) | **Done** (confirmed 2026-06-09) |
| Add `Account` (and any other in-scope SObjects) to `MCP_ReadOnly_Access` permission set | **Open** — currently `soqlQuery` returns `INVALID_TYPE` for Account |

### Internal

| Item | Status |
|------|--------|
| Commit + push policy/Terraform revert | Pending |
| Redeploy int via ADO pipeline | Pending |
| Run `Invoke-ApimSmokeTest.ps1 -Environment int` end-to-end | Pending pipeline |
| Decommission unused `sfdc-jwt-signing` cert in Key Vault | Low priority |
| Test Copilot Studio → APIM → Salesforce e2e | After smoke test passes |

---

## Testing

```bash
# Health check (no auth needed)
curl https://api.int.amnhealthcare.io/sfdcread/int/health

# Smoke test (requires az login; targets INT by default)
.\test-harness\Invoke-ApimSmokeTest.ps1
```

| Test | Status |
|------|--------|
| Policy deployment | Pass |
| Key Vault named value resolution | Pass |
| JWT validation (Azure CLI) | Pass |
| Salesforce OAuth (`client_credentials`) token exchange | **Pass** — scopes `sfap_api mcp_api api`, includes `api_instance_url` |
| Salesforce REST API (SObject list) | Pass — token valid against `/services/data/...` |
| MCP `initialize` (direct, bypassing APIM) | **Pass** (2026-06-09) |
| MCP `tools/list` (direct) | **Pass** — 6 tools returned |
| MCP `getUserInfo` (direct) | **Pass** — returns Run-As identity |
| MCP `soqlQuery` for Account (direct) | **Fail** — `INVALID_TYPE`; SF perm set missing Account read (not a wiring issue) |
| MCP e2e through APIM | Pending — needs reverted policy deployed |
| Copilot Studio → APIM → Salesforce | TODO |
