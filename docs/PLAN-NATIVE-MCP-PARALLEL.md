# Plan: Add Native MCP Server in Parallel

**Objective**: Deploy Azure APIM native MCP server alongside the existing generic API to validate native MCP features and inform future architecture decisions.

**Constraints**: 
- Minimal changes to existing production infrastructure
- Comment out (don't delete) obsolete generic API operations for easy rollback
- All native MCP additions are net-new

---

## Current State

| Component | Path | Status |
|-----------|------|--------|
| Generic API (production) | `/sfdcread/{env}/mcp` | ✅ Running in DEV/INT |
| APIM operations | 5 operations (POST/GET/DELETE /mcp, POST /, GET /health) | ✅ Deployed |
| Policy | [policies/apim-policy-sfdc-read-mcp.xml](../policies/apim-policy-sfdc-read-mcp.xml) | ✅ 206 lines |
| Backend | Salesforce MCP (`api.salesforce.com`) | ✅ Working |
| Consumers | Power Automate, Copilot Studio | ✅ Using generic API |

---

## Target State

| Component | Path | Additions |
|-----------|------|-----------|
| **Native MCP Server** | `/sfdcread-mcp-native/mcp` | 🆕 New APIM MCP Server resource |
| Policy | [policies/apim-policy-sfdc-read-mcp-native.xml](../policies/apim-policy-sfdc-read-mcp-native.xml) | 🆕 ~150 lines (simplified) |
| Infrastructure | `infrastructure/modules/mcp-server-native/` | 🆕 Terraform module |
| Testing | `int-native` environment in smoke test | 🆕 Already added |
| Validation doc | [MCP-NATIVE-VALIDATION.md](MCP-NATIVE-VALIDATION.md) | 🆕 Already created |

---

## Scope of Work

### Phase 0: Simplify Generic API (Cleanup)

**Goal**: Remove obsolete MCP operations from generic API that aren't actually used.

**Rationale**: Only POST `/mcp` is used for MCP Streamable HTTP protocol. GET (SSE), DELETE (session cleanup), and POST `/` (legacy) are unused noise.

**Deliverables**:
1. Comment out (don't delete) unused operations in `infrastructure/modules/mcp-api/main.tf`:
   - `mcp_get` (GET /mcp) - Deprecated SSE transport
   - `mcp_delete` (DELETE /mcp) - Rarely used session cleanup
   - `mcp_invoke_legacy` (POST /) - Unused backward compatibility endpoint
2. Keep active:
   - `health_check` (GET /health) - AFD health probe
   - `mcp_post` (POST /mcp) - **The only operation that matters**

**Files Modified**:
- 🆕 `infrastructure/modules/mcp-api/main.tf` - Comment out 3 operation resources

**Effort**: 30 minutes

**Rollback**: Uncomment the operations and redeploy if needed.

---

### Phase 1: Infrastructure Setup (Terraform)

**Goal**: Automate native MCP server provisioning via Terraform.

**Deliverables**:
1. New Terraform module: `infrastructure/modules/mcp-server-native/`
   - `main.tf` - Uses `azapi` provider to create MCP server resource
   - `variables.tf` - Inputs for MCP server config
   - `outputs.tf` - MCP server URL and metadata
2. Wire module into `infrastructure/main.tf`
3. Add conditional deployment (only deploys if `enable_native_mcp = true`)
4. Environment configs updated:
   - `infrastructure/environments/dev.tfvars` - Add `enable_native_mcp = false` (opt-in)
   - `infrastructure/environments/int.tfvars` - Add `enable_native_mcp = true` (test in INT)

**Files Modified**:
- ✅ `infrastructure/modules/mcp-server-native/main.tf` (already created)
- ✅ `infrastructure/modules/mcp-server-native/variables.tf` (already created)
- ✅ `infrastructure/modules/mcp-server-native/outputs.tf` (already created)
- 🆕 `infrastructure/main.tf` - Add module call
- 🆕 `infrastructure/variables.tf` - Add `enable_native_mcp` flag
- 🆕 `infrastructure/environments/*.tfvars` - Add flag per env

**Effort**: 2-4 hours

---

### Phase 2: Policy Deployment

**Goal**: Apply the native MCP policy to the new server.

**Challenge**: `azapi` provider may not support MCP server policy attachment yet. Fallback: manual portal application or REST API call.

**Deliverables**:
1. ✅ Policy file created: `policies/apim-policy-sfdc-read-mcp-native.xml`
2. Terraform attempts to apply policy via `azurerm_api_management_policy` (if supported)
3. If not supported: Document manual steps in README or use `null_resource` with Azure CLI

**Files Modified**:
- ✅ `policies/apim-policy-sfdc-read-mcp-native.xml` (already created)
- 🆕 `infrastructure/modules/mcp-server-native/main.tf` - Add policy resource or null_resource

**Effort**: 1-2 hours (may require REST API workaround)

---

### Phase 3: Testing Infrastructure

**Goal**: Smoke test can validate both generic API and native MCP server.

**Deliverables**:
1. ✅ Smoke test updated with `int-native` environment (already done)
2. 🆕 CI pipeline variant to test native endpoint
3. 🆕 Validation script to compare responses between generic and native

**Files Modified**:
- ✅ `test-harness/Invoke-ApimSmokeTest.ps1` (already updated)
- 🆕 `.ado/pipelines/smoke-test-native.yml` - New pipeline for native endpoint
- 🆕 `test-harness/Compare-GenericVsNative.ps1` - Side-by-side comparison script

**Effort**: 2-3 hours

---

### Phase 4: Documentation

**Goal**: Document the parallel deployment and how to validate/compare.

**Deliverables**:
1. ✅ Validation plan: `docs/MCP-NATIVE-VALIDATION.md` (already created)
2. 🆕 Update `README.md` - Document both endpoints
3. 🆕 Update `docs/ARCHITECTURE.md` - Explain parallel deployment
4. 🆕 Runbook: `docs/NATIVE-MCP-DEPLOYMENT.md` - How to deploy/manage native MCP

**Files Modified**:
- 🆕 `README.md` - Add native MCP section
- 🆕 `docs/ARCHITECTURE.md` - Document dual-track architecture
- 🆕 `docs/NATIVE-MCP-DEPLOYMENT.md` - Deployment runbook

**Effort**: 2-3 hours

---

### Phase 5: Deployment & Validation

**Goal**: Deploy to INT, run validation tests, document findings.

**Deliverables**:
1. Deploy native MCP to INT via Terraform
2. Run smoke test against both endpoints
3. Compare monitoring/telemetry in Application Insights
4. Test Power Automate connector pointing at new URL
5. Document findings in validation tracker

**Tasks**:
- Deploy: `terraform apply -var-file=environments/int.tfvars`
- Test: `.\test-harness\Invoke-ApimSmokeTest.ps1 -Environment int-native`
- Compare: `.\test-harness\Compare-GenericVsNative.ps1`
- Monitor: Review Application Insights for MCP-specific fields
- Document: Update validation tracker with results

**Effort**: 3-4 hours

---

## Total Effort Estimate

| Phase | Effort | Status |
|-------|--------|--------|
| 0. Simplify Generic API | 30 min | Pending |
| 1. Infrastructure (Terraform) | 2-4 hours | In progress |
| 2. Policy Deployment | 1-2 hours | Pending |
| 3. Testing Infrastructure | 2-3 hours | Partially done |
| 4. Documentation | 2-3 hours | Partially done |
| 5. Deployment & Validation | 3-4 hours | Pending |
| **Total** | **11-17 hours** | ~30% complete |

---

## Success Criteria

✅ **Functional Parity**: Native MCP passes all smoke tests that generic API passes  
✅ **No Regressions**: Existing generic API continues working unchanged  
✅ **Infrastructure as Code**: Native MCP fully automated via Terraform  
✅ **Monitoring Comparison**: Side-by-side telemetry documented  
✅ **Decision Data**: Clear recommendation to migrate or stay with generic API

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| `azapi` provider doesn't support MCP server policies | Use `null_resource` with Azure CLI REST API call |
| Native MCP has protocol incompatibilities | Keep generic API as primary; native is experiment-only |
| Terraform state drift between generic and native | Use separate state files or modules to isolate resources |
| Native MCP requires different Entra app | Reuse existing app; same JWT validation works for both |

---

## Rollback Plan

If native MCP doesn't work or adds no value:
1. Set `enable_native_mcp = false` in tfvars
2. Run `terraform apply` to destroy native MCP resources
3. Remove native-specific test configs
4. Continue with generic API—zero production impact

---

## Next Steps

1. Complete Terraform integration (`main.tf` module wiring)
2. Test Terraform deployment to INT
3. Create comparison test script
4. Deploy and run validation tests
5. Document findings and make recommendation
