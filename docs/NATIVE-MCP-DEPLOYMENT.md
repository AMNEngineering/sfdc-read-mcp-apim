# Native MCP Server Deployment Runbook

**Status**: Experimental parallel deployment alongside generic API

**Target**: INT environment only (dev disabled for faster iteration)

---

## Prerequisites

- [x] Generic API deployed and working
- [x] `enable_native_mcp = true` in `infrastructure/environments/int.tfvars`
- [x] Azure CLI authenticated with APIM contributor role
- [x] Terraform >= 1.6
- [x] PowerShell >= 7.0

---

## Deployment Steps

### 1. Plan and Validate

```powershell
cd infrastructure
terraform init
terraform plan -var-file=environments/int.tfvars
```

**Expected output**:
- `module.mcp_server_native[0]` will be created (new azapi_resource)
- `module.mcp_api` will show 3 operations removed (GET /mcp, DELETE /mcp, POST /)
- No changes to `module.mcp_policy` (generic API policy)

**Acceptance**: Plan shows MCP server creation + operation removals, no unexpected changes.

---

### 2. Deploy

```powershell
terraform apply -var-file=environments/int.tfvars
```

**Watch for**:
- MCP server resource creation via azapi
- Policy application via PowerShell provisioner (may warn if REST API fails)
- Obsolete operations removed from generic API

**If policy application fails**: Don't worry—Terraform will warn but not fail. Apply manually in portal (Step 3).

---

### 3. Verify MCP Server in Portal

1. Navigate to Azure Portal → APIM instance `amn-wus2-hub-apim-i02`
2. Left nav → **MCP Servers** (not "APIs")
3. Confirm `sfdcread-mcp-native-int` appears in list
4. Click server → verify:
   - Display name: `MCP INT - SFDCRead (Native)`
   - Backend URL: `https://api.salesforce.com/platform/mcp/v1/sandbox/platform/sobject-reads`
   - Base path: `sfdcread-mcp-native`
   - Transport: StreamableHttp

---

### 4. Verify Policy Applied

1. In MCP server → left nav → **Policies**
2. Confirm policy XML matches [policies/apim-policy-sfdc-read-mcp-native.xml](../policies/apim-policy-sfdc-read-mcp-native.xml)
3. **If blank or missing**:
   - Copy policy from file
   - Paste into policy editor
   - Save

**Key policy sections**:
- JWT validation (tenant + dual-audience)
- Role check (MCP.Read)
- SF token exchange (client_credentials)
- Authorization header replacement

---

### 5. Verify Generic API Simplified

1. Azure Portal → APIM → **APIs** tab
2. Select `api-sfdc-read-int`
3. Confirm only 2 operations:
   - `GET /health`
   - `POST /mcp`
4. Verify obsolete operations removed:
   - ❌ GET /mcp (SSE)
   - ❌ DELETE /mcp (session cleanup)
   - ❌ POST / (legacy)

---

### 6. Run Smoke Tests

Test both endpoints to confirm functional parity:

```powershell
# Test generic API (baseline)
.\test-harness\Invoke-ApimSmokeTest.ps1 -Environment int

# Test native MCP server
.\test-harness\Invoke-ApimSmokeTest.ps1 -Environment int-native

# Compare side-by-side
.\test-harness\Compare-GenericVsNative.ps1
```

**Acceptance**: Both endpoints pass with identical results.

---

## Validation Checklist

| Check | Generic API | Native MCP | Status |
|-------|-------------|------------|--------|
| **Discoverability** | APIs tab, under "S" | **MCP Servers tab** ✅ | |
| **Operations** | POST /mcp, GET /health | Managed by APIM | |
| **Policy applied** | ✅ | ✅ | |
| **Smoke test passes** | ✅ | ✅ | |
| **JWT validation** | ✅ Entra + role check | ✅ Same | |
| **SF token exchange** | ✅ client_credentials | ✅ Same | |
| **MCP tools work** | ✅ All 6 tools | ✅ Same | |

---

## Troubleshooting

### MCP Server Not Created

**Symptom**: `terraform apply` succeeds but no MCP server in portal

**Cause**: `azapi` provider version mismatch or API version not supported

**Fix**:
1. Check provider version: `terraform version`
2. Update azapi provider: `terraform init -upgrade`
3. If still fails: Create manually in portal (see [PLAN-NATIVE-MCP-PARALLEL.md](PLAN-NATIVE-MCP-PARALLEL.md) Phase 0)

---

### Policy Not Applied

**Symptom**: MCP server exists but policy blank in portal

**Cause**: PowerShell provisioner failed (REST API auth issue)

**Fix**:
1. Portal → MCP server → Policies
2. Copy policy from [policies/apim-policy-sfdc-read-mcp-native.xml](../policies/apim-policy-sfdc-read-mcp-native.xml)
3. Paste and Save
4. Re-run smoke test: `.\test-harness\Invoke-ApimSmokeTest.ps1 -Environment int-native`

---

### Smoke Test Fails for Native but Generic Passes

**Symptom**: Generic API ✅ Native MCP ❌

**Cause**: Policy mismatch or backend URL wrong

**Debug**:
1. Compare policies:
   ```powershell
   diff (Get-Content policies/apim-policy-sfdc-read-mcp.xml) `
        (Get-Content policies/apim-policy-sfdc-read-mcp-native.xml)
   ```
2. Check backend URL in portal: MCP server → Settings
3. Check Application Insights for error details
4. Test with correlation ID for tracing

---

### Both Endpoints Fail

**Symptom**: Generic API ❌ Native MCP ❌

**Cause**: Environment issue (SF backend, Key Vault, Entra app)

**Fix**:
1. Check Salesforce backend: `curl https://api.salesforce.com/platform/mcp/v1/sandbox/platform/sobject-reads`
2. Verify Key Vault secrets exist: `az keyvault secret show --vault-name amn-wus2-sfdcread-kv-i01 --name sfdc-client-id`
3. Confirm Entra app role: `az ad app show --id 42971939-bc78-4c23-963e-c3e0f87e3bd1 --query "appRoles[?value=='MCP.Read']"`

---

## Rollback Plan

### Rollback Native MCP Only

```powershell
# Disable native MCP in tfvars
# infrastructure/environments/int.tfvars: enable_native_mcp = false

terraform apply -var-file=environments/int.tfvars
```

Generic API unaffected—continues running.

---

### Rollback Generic API Simplification

```powershell
# Uncomment operations in infrastructure/modules/mcp-api/main.tf:
# - mcp_get (GET /mcp)
# - mcp_delete (DELETE /mcp)
# - mcp_invoke_legacy (POST /)

terraform apply -var-file=environments/int.tfvars
```

Restores 5 operations (3 obsolete + 2 active).

---

## Next Steps

1. ✅ Deploy native MCP to INT
2. ✅ Run functional parity tests
3. 🔍 Compare monitoring in Application Insights
4. 🧪 Test Power Automate connector with native endpoint
5. 📊 Document findings in [MCP-NATIVE-VALIDATION.md](MCP-NATIVE-VALIDATION.md)
6. 🗳️  Decision: Migrate or stay with generic API

---

## Production Rollout (Future)

**If native MCP proves valuable**:

1. Update `infrastructure/environments/prod.tfvars`:
   ```hcl
   enable_native_mcp = true
   ```

2. Deploy to prod with CAB approval:
   ```powershell
   terraform apply -var-file=environments/prod.tfvars
   ```

3. Migrate consumers to `/sfdcread-mcp-native/mcp`

4. Retire generic API (`enable_native_mcp = false` for generic, keep native)

**If staying with generic API**:

1. Set `enable_native_mcp = false` in all envs
2. Delete `infrastructure/modules/mcp-server-native/`
3. Remove native-specific test configs
4. Continue with simplified generic API (2 operations only)
