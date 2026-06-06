# Deployment Status

## Latest Deployment: Build 1.0.40 ✅

**Date**: 2026-06-06  
**Status**: Successfully deployed to Dev and Int  

---

## ✅ Dev Environment - READY

- **APIM**: amn-wus2-hub-apim-d02
- **API Path**: sfdc-read/dev
- **AFD URL**: https://api.dev.amnhealthcare.io/sfdc-read/dev
- **App ID**: 6ce6ccb1-32db-40f8-97b5-bfbe700d052e
- **Backend**: Inline mock responses (no backend server needed)
- **JWT**: Validated, Azure CLI pre-authorized
- **Status**: ⚠️ Awaiting AFD routing configuration

## ✅ Int Environment - READY

- **APIM**: amn-wus2-hub-apim-i02
- **API Path**: sfdc-read/int
- **AFD URL**: https://api.int.amnhealthcare.io/sfdc-read/int
- **App ID**: 976d1c5b-bc4b-4cdf-9fd3-6fd7567a1a03
- **Backend**: Salesforce Sandbox (https://api.salesforce.com)
- **JWT**: Validated, Azure CLI pre-authorized
- **Status**: ⚠️ Awaiting AFD routing + Salesforce credentials

---

## 🔴 BLOCKER: AFD Routing

Azure Front Door needs routes configured:

**Dev**: /sfdc-read/dev → amn-wus2-hub-apim-d02.azure-api.net
**Int**: /sfdc-read/int → amn-wus2-hub-apim-i02.azure-api.net

---

## Testing Once AFD Configured

```bash
# Get token
TOKEN=$(az account get-access-token --resource "api://6ce6ccb1-32db-40f8-97b5-bfbe700d052e" --query accessToken -o tsv)

# Test dev
curl -X POST https://api.dev.amnhealthcare.io/sfdc-read/dev \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

Expected: 200 OK with mock MCP tool list
