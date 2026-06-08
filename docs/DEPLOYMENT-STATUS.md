# Deployment Status

## Latest Deployment: Build 1.0.56

**Date**: 2026-06-07  
**Status**: Deployed to Int with real Salesforce wiring  
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
- **App ID**: 976d1c5b-bc4b-4cdf-9fd3-6fd7567a1a03
- **Backend**: Salesforce Sandbox via OAuth token exchange
- **Key Vault**: amn-wus2-sfdcread-kv-i01 (secrets resolving, status: Success)
- **JWT**: Validated, Azure CLI pre-authorized
- **SF OAuth**: **BLOCKED** — Connected App returns `"request not supported on this domain"` for `client_credentials` grant
- **Status**: Deployed, awaiting Salesforce Connected App configuration

---

## Blocker: Salesforce Connected App

The `client_credentials` OAuth grant is rejected by Salesforce (both `test.salesforce.com` and `login.salesforce.com`). Salesforce admin must:

1. Enable Client Credentials Flow on the Connected App
2. Assign a "Run As" user for client_credentials
3. Confirm correct token endpoint URL (may need org-specific sandbox domain)

---

## Testing

```bash
# Health check (no auth needed)
curl https://api.int.amnhealthcare.io/sfdcread/int/health

# Smoke test (requires az login)
.\test-harness\Invoke-ApimSmokeTest.ps1 -Environment int
```

| Test | Status |
|------|--------|
| Policy deployment | Pass |
| Key Vault named value resolution | Pass |
| JWT validation (Azure CLI) | Pass |
| Salesforce OAuth token exchange | **Fail** — SF Connected App not configured |
| MCP e2e through Salesforce | Blocked |
| Copilot Studio → APIM → Salesforce | TODO |
